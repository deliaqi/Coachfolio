import Foundation
import Observation

@MainActor
@Observable
final class StudioStore {
    private(set) var clients: [CoachClient] = []
    private(set) var sessions: [CoachingSession] = []
    private(set) var storageError: String?

    private var rootDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("CoachJournal", isDirectory: true)
    }

    private var dataURL: URL { rootDirectory.appendingPathComponent("coach-data.json") }
    private var audioDirectory: URL { rootDirectory.appendingPathComponent("Audio", isDirectory: true) }

    init() { load() }

    var sortedSessions: [CoachingSession] {
        sessions.sorted { $0.date > $1.date }
    }

    func client(for id: UUID) -> CoachClient? { clients.first { $0.id == id } }
    func session(for id: UUID) -> CoachingSession? { sessions.first { $0.id == id } }
    func audioURL(for session: CoachingSession) -> URL { audioDirectory.appendingPathComponent(session.audioFilename) }
    func sessions(for clientID: UUID) -> [CoachingSession] { sortedSessions.filter { $0.clientID == clientID } }

    @discardableResult
    func importRecording(from source: URL, clientName: String, title: String, date: Date, language: ImportLanguage, consentConfirmed: Bool, openAIConsentConfirmed: Bool = false) throws -> UUID {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let accessGranted = source.startAccessingSecurityScopedResource()
        defer { if accessGranted { source.stopAccessingSecurityScopedResource() } }

        let safeExtension = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let storedName = "\(UUID().uuidString).\(safeExtension)"
        let destination = audioDirectory.appendingPathComponent(storedName)
        try FileManager.default.copyItem(at: source, to: destination)

        let cleanedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientRecord: CoachClient
        if let existing = clients.first(where: { $0.name.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame }) {
            clientRecord = existing
        } else {
            clientRecord = CoachClient(name: cleanedName)
            clients.append(clientRecord)
        }

        let session = CoachingSession(
            clientID: clientRecord.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Coaching session" : title,
            date: date,
            language: language.rawValue,
            audioFilename: storedName,
            consentConfirmed: consentConfirmed,
            openAIConsentConfirmed: openAIConsentConfirmed
        )
        sessions.append(session)
        save()
        return session.id
    }

    func updateConsent(sessionID: UUID, confirmed: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].consentConfirmed = confirmed
        if !confirmed {
            sessions[index].openAIConsentConfirmed = false
            sessions[index].review = nil
        }
        save()
    }

    func updateOpenAIConsent(sessionID: UUID, confirmed: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].openAIConsentConfirmed = confirmed
        if !confirmed { sessions[index].review = nil }
        save()
    }

    func updateTranscript(sessionID: UUID, utterances: [TranscriptUtterance], duration: TimeInterval) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let usableUtterances = utterances.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usableUtterances.isEmpty else { return }
        sessions[index].transcript = usableUtterances
        sessions[index].duration = duration
        sessions[index].review = nil
        save()
    }

    func setSpeaker(sessionID: UUID, utteranceID: Int, speaker: Speaker) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let utteranceIndex = sessions[sessionIndex].transcript.firstIndex(where: { $0.id == utteranceID }) else { return }
        sessions[sessionIndex].transcript[utteranceIndex].speaker = speaker
        sessions[sessionIndex].review = nil
        save()
    }

    func setSpeaker(sessionID: UUID, speakerID: Int, speaker: Speaker) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let matchingTurns = sessions[sessionIndex].transcript.indices.filter {
            sessions[sessionIndex].transcript[$0].speakerID == speakerID
        }
        guard !matchingTurns.isEmpty else { return }
        for index in matchingTurns {
            sessions[sessionIndex].transcript[index].speaker = speaker
        }
        sessions[sessionIndex].review = nil
        save()
    }

    func splitUtterance(
        sessionID: UUID,
        utteranceID: Int,
        firstText: String,
        secondText: String,
        splitTime: TimeInterval,
        firstSpeaker: Speaker,
        secondSpeaker: Speaker
    ) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let utteranceIndex = sessions[sessionIndex].transcript.firstIndex(where: { $0.id == utteranceID }) else { return }

        let firstText = firstText.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondText = secondText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstText.isEmpty, !secondText.isEmpty else { return }

        let original = sessions[sessionIndex].transcript[utteranceIndex]
        let boundedSplitTime = max(original.startTime, min(splitTime, original.endTime ?? splitTime))
        sessions[sessionIndex].transcript[utteranceIndex].text = firstText
        sessions[sessionIndex].transcript[utteranceIndex].endTime = boundedSplitTime
        sessions[sessionIndex].transcript[utteranceIndex].speaker = firstSpeaker
        sessions[sessionIndex].transcript[utteranceIndex].speakerID = nil

        let nextID = (sessions[sessionIndex].transcript.map(\.id).max() ?? 0) + 1
        let secondTurn = TranscriptUtterance(
            id: nextID,
            startTime: boundedSplitTime,
            endTime: original.endTime,
            speaker: secondSpeaker,
            speakerID: nil,
            text: secondText
        )
        sessions[sessionIndex].transcript.insert(secondTurn, at: utteranceIndex + 1)
        sessions[sessionIndex].review = nil
        save()
    }

    func mergeUtteranceWithPrevious(
        sessionID: UUID,
        previousUtteranceID: Int,
        utteranceID: Int,
        speaker: Speaker
    ) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let previousIndex = sessions[sessionIndex].transcript.firstIndex(where: { $0.id == previousUtteranceID }),
              let utteranceIndex = sessions[sessionIndex].transcript.firstIndex(where: { $0.id == utteranceID }),
              previousIndex < utteranceIndex else { return }

        let previous = sessions[sessionIndex].transcript[previousIndex]
        let utterance = sessions[sessionIndex].transcript[utteranceIndex]
        let mergedText = [previous.text, utterance.text]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !mergedText.isEmpty else { return }

        sessions[sessionIndex].transcript[previousIndex].text = mergedText
        sessions[sessionIndex].transcript[previousIndex].endTime = utterance.endTime ?? previous.endTime
        sessions[sessionIndex].transcript[previousIndex].speaker = speaker
        sessions[sessionIndex].transcript[previousIndex].speakerID = previous.speakerID == utterance.speakerID
            ? previous.speakerID
            : nil
        sessions[sessionIndex].transcript.remove(at: utteranceIndex)
        sessions[sessionIndex].review = nil
        save()
    }

    func updateUtteranceText(sessionID: UUID, utteranceID: Int, text: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let utteranceIndex = sessions[sessionIndex].transcript.firstIndex(where: { $0.id == utteranceID }) else { return }
        sessions[sessionIndex].transcript[utteranceIndex].text = text
        sessions[sessionIndex].review = nil
        save()
    }

    func saveReview(sessionID: UUID, review: PracticeReview) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].review = review
        save()
    }

    func addClient(name: String, notes: String = "") {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !clients.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return }
        clients.append(CoachClient(name: name, notes: notes))
        save()
    }

    func updateClientNotes(clientID: UUID, notes: String) {
        guard let index = clients.firstIndex(where: { $0.id == clientID }) else { return }
        clients[index].notes = notes
        save()
    }

    func updateSessionLanguage(sessionID: UUID, language: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].language = language
        sessions[index].review = nil
        save()
    }

    func deleteSession(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions.remove(at: index)
        try? FileManager.default.removeItem(at: audioURL(for: session))
        save()
    }

    private func load() {
        do {
            guard FileManager.default.fileExists(atPath: dataURL.path) else { return }
            let data = try Data(contentsOf: dataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(StudioData.self, from: data)
            clients = decoded.clients
            sessions = decoded.sessions
        } catch {
            storageError = "Your local library could not be read: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(StudioData(clients: clients, sessions: sessions))
            try data.write(to: dataURL, options: .atomic)
            storageError = nil
        } catch {
            storageError = "Your changes could not be saved locally: \(error.localizedDescription)"
        }
    }
}
