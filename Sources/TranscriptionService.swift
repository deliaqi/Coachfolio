import Foundation
import AVFoundation
import WhisperKit
import SpeakerKit

enum TranscriptionError: LocalizedError {
    case invalidAudio
    case noSpeechFound
    case modelDownloadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAudio:
            "This recording could not be opened for transcription."
        case .noSpeechFound:
            "Whisper did not recognize speech in this recording. You can still add a transcript manually."
        case .modelDownloadFailed(let details):
            "The on-device speech model could not be prepared. Check your internet connection and try again. \(details)"
        case .transcriptionFailed(let details):
            "Whisper could not transcribe this recording. The audio is unchanged. \(details)"
        }
    }
}

struct TranscriptionOutput {
    var utterances: [TranscriptUtterance]
    var speakerWarning: String?
}

enum TranscriptionService {
    private static let whisperModel = "large-v3-v20240930_626MB"

    private struct TimedSegment {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
        var speaker: Speaker = .unknown
        var speakerID: Int?
    }

    static func duration(of url: URL) async -> TimeInterval {
        do {
            let asset = AVURLAsset(url: url)
            let time = try await asset.load(.duration)
            let value = CMTimeGetSeconds(time)
            return value.isFinite ? value : 0
        } catch {
            return 0
        }
    }

    static func transcribe(
        url: URL,
        language: ImportLanguage,
        progress: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> TranscriptionOutput {
        let duration = await duration(of: url)
        guard duration > 0 else { throw TranscriptionError.invalidAudio }

        await progress("Preparing Whisper model…")
        let modelFolder: URL
        do {
            modelFolder = try await WhisperKit.download(variant: whisperModel) { update in
                let percent = Int((update.fractionCompleted * 100).rounded())
                Task { @MainActor in progress("Downloading Whisper model · \(percent)%") }
            }
        } catch {
            throw TranscriptionError.modelDownloadFailed(error.localizedDescription)
        }

        await progress("Loading Whisper model on this Mac…")
        let whisper: WhisperKit
        do {
            whisper = try await WhisperKit(WhisperKitConfig(
                model: whisperModel,
                modelFolder: modelFolder.path,
                verbose: false,
                load: true,
                download: false
            ))
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }

        await progress("Transcribing the recording…")
        let results: [TranscriptionResult]
        do {
            results = try await whisper.transcribe(
                audioPath: url.path,
                audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
                decodeOptions: DecodingOptions(
                    language: language.whisperLanguageCode,
                    skipSpecialTokens: true
                ),
                callback: { update in
                    let excerpt = update.text
                        .replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !excerpt.isEmpty else { return nil }
                    let preview = String(excerpt.suffix(52))
                    Task { @MainActor in
                        progress("Transcribing · \(preview)")
                    }
                    return nil
                }
            )
        } catch {
            throw TranscriptionError.transcriptionFailed(error.localizedDescription)
        }

        // Whisper and Pyannote are both Core ML pipelines. Release Whisper's model
        // weights before loading the diarization models to reduce peak memory use.
        await whisper.unloadModels()

        let plainSegments = Self.transcriptionSegments(from: results)
        guard !plainSegments.isEmpty else { throw TranscriptionError.noSpeechFound }

        await progress("Separating speakers…")
        do {
            let diarization = try await diarize(url: url, progress: progress)
            let speakerSegments = Self.assignSpeakers(to: plainSegments, using: diarization)
            guard !speakerSegments.isEmpty else {
                return TranscriptionOutput(
                    utterances: Self.group(plainSegments),
                    speakerWarning: "Speaker detection returned no labels. Transcript turns are unassigned; review the labels before analysis."
                )
            }
            let turns = Self.group(speakerSegments)
            guard !turns.isEmpty else {
                return TranscriptionOutput(
                    utterances: Self.group(plainSegments),
                    speakerWarning: "Speaker detection returned no labels. Transcript turns are unassigned; review the labels before analysis."
                )
            }
            return TranscriptionOutput(utterances: turns, speakerWarning: nil)
        } catch {
            let turns = Self.group(plainSegments)
            return TranscriptionOutput(
                utterances: turns,
                speakerWarning: "Speaker detection could not run: \(error.localizedDescription) Transcript turns are unassigned; review the labels before analysis."
            )
        }
    }

    private static func diarize(
        url: URL,
        progress: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> DiarizationResult {
        let config = PyannoteConfig(
            download: true,
            load: false,
            verbose: false,
            concurrentSegmenterWorkers: 1,
            concurrentEmbedderWorkers: 1
        )
        await progress("Preparing speaker models (first run may take a few minutes)…")
        let speakerKit = try await SpeakerKit(config)
        guard let diarizer = speakerKit.diarizer as? SpeakerKitDiarizer else {
            throw TranscriptionError.transcriptionFailed("Speaker detection is unavailable.")
        }

        await progress("Loading speaker model…")
        try await diarizer.loadModels()

        await progress("Finding speaker turns…")
        let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
        return try await speakerKit.diarize(
            audioArray: audio,
            options: PyannoteDiarizationOptions(numberOfSpeakers: 2),
            progressCallback: { update in
                let percent = Int((update.fractionCompleted * 100).rounded())
                Task { @MainActor in progress("Finding speaker turns · \(percent)%") }
            }
        )
    }

    private static func transcriptionSegments(from results: [TranscriptionResult]) -> [TimedSegment] {
        results.flatMap { result in
            return result.segments.compactMap { segment -> TimedSegment? in
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                // WhisperKit offsets segment timestamps when it joins chunked results.
                // `result.seekTime` describes that offset; adding it here again doubles
                // timestamps for recordings that span multiple audio chunks.
                let start = TimeInterval(segment.start)
                let end = max(start, TimeInterval(segment.end))
                return TimedSegment(text: text, start: start, end: end)
            }
        }
    }

    private static func assignSpeakers(to segments: [TimedSegment], using diarization: DiarizationResult) -> [TimedSegment] {
        let voiceSegments = diarization.segments.sorted { $0.startTime < $1.startTime }
        var speakerOrder: [Int] = []
        for id in voiceSegments.compactMap({ $0.speaker.speakerId }) where !speakerOrder.contains(id) {
            speakerOrder.append(id)
        }

        return segments.map { segment in
            var overlapBySpeaker: [Int: TimeInterval] = [:]
            for voice in voiceSegments {
                guard let id = voice.speaker.speakerId else { continue }
                let overlap = max(0, min(segment.end, TimeInterval(voice.endTime)) - max(segment.start, TimeInterval(voice.startTime)))
                if overlap > 0 { overlapBySpeaker[id, default: 0] += overlap }
            }

            let ranked = overlapBySpeaker.sorted { $0.value > $1.value }
            guard let first = ranked.first else { return segment }
            let segmentDuration = max(0.1, segment.end - segment.start)
            let hasClearMajority = first.value / segmentDuration >= 0.55 &&
                (ranked.count == 1 || first.value >= ranked[1].value * 1.25)
            guard hasClearMajority, let index = speakerOrder.firstIndex(of: first.key) else { return segment }

            var attributed = segment
            attributed.speaker = index == 0 ? .coach : (index == 1 ? .client : .unknown)
            attributed.speakerID = first.key
            return attributed
        }
    }

    private static func group(_ segments: [TimedSegment]) -> [TranscriptUtterance] {
        let ordered = segments.sorted { $0.start < $1.start }
        var turns: [TranscriptUtterance] = []
        var currentText = ""
        var currentStart: TimeInterval = 0
        var currentEnd: TimeInterval = 0
        var currentSpeaker: Speaker = .unknown
        var currentSpeakerID: Int?

        func flush() {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            turns.append(TranscriptUtterance(
                id: turns.count + 1,
                startTime: currentStart,
                endTime: currentEnd,
                speaker: currentSpeaker,
                speakerID: currentSpeakerID,
                text: text
            ))
            currentText = ""
        }

        for segment in ordered {
            if !currentText.isEmpty && (segment.speaker != currentSpeaker || segment.speakerID != currentSpeakerID || segment.start - currentEnd > 1.25) {
                flush()
            }
            if currentText.isEmpty {
                currentStart = segment.start
                currentSpeaker = segment.speaker
                currentSpeakerID = segment.speakerID
            }
            if !currentText.isEmpty && !currentText.hasSuffix(" ") && !segment.text.hasPrefix(" ") {
                currentText += " "
            }
            currentText += segment.text
            currentEnd = max(currentEnd, segment.end)
        }
        flush()
        return turns
    }
}
