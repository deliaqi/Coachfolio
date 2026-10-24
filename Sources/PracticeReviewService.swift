import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ReviewServiceError: LocalizedError {
    case noTranscript
    case localConsentRequired
    case cloudConsentRequired

    var errorDescription: String? {
        switch self {
        case .noTranscript: "Add a transcript before starting a practice review."
        case .localConsentRequired: "Confirm client permission before reviewing this session."
        case .cloudConsentRequired: "Confirm permission to send this transcript to OpenAI before creating a GPT review."
        }
    }
}

enum PracticeReviewService {
    static let competencies = [
        "Demonstrates Ethical Practice",
        "Embodies a Coaching Mindset",
        "Establishes and Maintains Agreements",
        "Cultivates Trust and Safety",
        "Maintains Presence",
        "Listens Actively",
        "Evokes Awareness",
        "Facilitates Client Growth"
    ]

    static func analyze(_ session: CoachingSession, target: CredentialLevel) async throws -> PracticeReview {
        guard !session.transcript.isEmpty else { throw ReviewServiceError.noTranscript }
        if OpenAIReviewSettings.selectedProvider == .openAI {
            return try await OpenAIReviewService.analyze(session, target: target)
        }
        #if canImport(FoundationModels)
        if SystemLanguageModel.default.availability == .available {
            do { return try await modelReview(session, target: target) }
            catch { return signalReview(session, target: target, note: "On-device review was unavailable for this session; showing a transparent language-signal scan.") }
        }
        #endif
        return signalReview(session, target: target, note: "Apple’s on-device language model is unavailable on this Mac; showing a transparent language-signal scan.")
    }

    private static func signalReview(_ session: CoachingSession, target: CredentialLevel, note: String) -> PracticeReview {
        let coachTurns = session.transcript.filter { $0.speaker == .coach }
        let clientTurns = session.transcript.filter { $0.speaker == .client }
        let allTurns = session.transcript
        let questionTurns = coachTurns.filter { isQuestion($0.text) }
        let openQuestionTurns = questionTurns.filter { isOpenQuestion($0.text) }
        let adviceTurns = coachTurns.filter { isAdviceLike($0.text) }
        let reflectionTurns = coachTurns.filter { containsAny($0.text, ["i hear", "what i'm hearing", "it sounds like", "you said", "我听到", "我听见", "你的意思"]) }
        let actionTurns = coachTurns.filter { containsAny($0.text, ["what will you", "what are you going to", "next step", "action", "by when", "commit", "接下来", "下一步", "行动", "什么时候"]) }
        let unknownCoachShare = coachTurns.count == 0

        var strengths: [EvidenceNote] = []
        var growth: [EvidenceNote] = []
        if !openQuestionTurns.isEmpty {
            strengths.append(EvidenceNote(title: "Questions invite exploration", detail: "The coach used \(openQuestionTurns.count) open-question signal(s). Check the cited moments for whether they led to new client awareness.", turnIDs: sampleIDs(openQuestionTurns)))
        }
        if !reflectionTurns.isEmpty {
            strengths.append(EvidenceNote(title: "Listening is reflected back", detail: "Language patterns suggest the coach reflected the client’s meaning. Confirm that the reflections were accurate and responsive.", turnIDs: sampleIDs(reflectionTurns)))
        }
        if !actionTurns.isEmpty {
            strengths.append(EvidenceNote(title: "Learning moves toward action", detail: "The close of the conversation includes action or accountability language. Review whether the plan came from the client.", turnIDs: sampleIDs(actionTurns)))
        }
        if strengths.isEmpty {
            strengths.append(EvidenceNote(title: "Review the coach’s questions", detail: "After labeling the coach’s turns, listen for moments where the client defines the focus, explores meaning, and chooses what to do next."))
        }
        if !adviceTurns.isEmpty {
            growth.append(EvidenceNote(title: "Notice advice and direction", detail: "The transcript contains \(adviceTurns.count) turn(s) with advice-like language. Check whether the coach asked permission and returned ownership to the client.", turnIDs: sampleIDs(adviceTurns)))
        }
        if coachTurns.count > 0 && questionTurns.count < max(2, coachTurns.count / 8) {
            growth.append(EvidenceNote(title: "Make more room for client meaning", detail: "Few question-shaped turns were detected in the coach’s labeled turns. Consider where a curious question could reveal the client’s perspective.", turnIDs: sampleIDs(coachTurns.prefix(4).map { $0 })))
        }
        if unknownCoachShare {
            growth.append(EvidenceNote(title: "Label coach and client turns", detail: "Speaker labels are needed before this scan can attribute language patterns to the coach. Set labels in the transcript and run the review again.", turnIDs: []))
        }

        let agreementTurns = coachTurns.filter { containsAny($0.text, ["what would you like to focus", "what do you want to work on", "what would be useful", "session outcome", "今天想", "本次想", "希望探讨", "想聚焦"]) }
        let awarenessTurns = openQuestionTurns
        let findings = competencies.map { name -> CompetencyFinding in
            switch name {
            case "Establishes and Maintains Agreements":
                return finding(name, turns: agreementTurns, message: "Look for a shared session focus, what success would mean to the client, and check-ins when the direction changes.")
            case "Listens Actively":
                return finding(name, turns: reflectionTurns, message: "A transcript can show verbal reflection; tone, silence, emotion, and nonverbal cues need human review.")
            case "Evokes Awareness":
                return finding(name, turns: awarenessTurns, message: "Open-question language appears here. Review whether it helped the client notice a new perspective, belief, or meaning.")
            case "Facilitates Client Growth":
                return finding(name, turns: actionTurns, message: "Action or accountability language appears here. Check client ownership, learning integration, and closure.")
            case "Demonstrates Ethical Practice":
                return CompetencyFinding(competency: name, status: .reviewNeeded, note: "Ethics, confidentiality, and boundaries cannot be established from a transcript scan. Review the engagement context.")
            case "Cultivates Trust and Safety":
                return CompetencyFinding(competency: name, status: .reviewNeeded, note: "Safety and trust depend on context, impact, and how the client experienced the interaction.")
            case "Maintains Presence":
                return CompetencyFinding(competency: name, status: .reviewNeeded, note: "Presence, pacing, and responsiveness need a human listen; text patterns are not a reliable proxy.")
            default:
                return CompetencyFinding(competency: name, status: .reviewNeeded, note: "Reflect on curiosity, flexibility, and how the coach’s own learning shaped this session.")
            }
        }
        let unknownTurns = allTurns.filter { $0.speaker == .unknown }.count
        let alignment = coachTurns.isEmpty ? "Add speaker labels to review" : "Evidence scan only · human review needed"
        let summary = "A language-pattern scan detected \(questionTurns.count) question-shaped coach turn(s), including \(openQuestionTurns.count) open-question signal(s), and \(adviceTurns.count) advice-like turn(s). These counts are prompts for listening, not quality scores. \(unknownTurns) transcript turn(s) still have no speaker label; \(clientTurns.count) are labeled as client."
        return PracticeReview(
            targetLevel: target,
            method: "Local language-signal scan",
            alignment: alignment,
            summary: summary,
            strengths: strengths,
            growthAreas: growth,
            findings: findings,
            nextPractice: "Choose one cited moment, replay it, and write down what the client wanted in that moment, what you noticed, and what you might ask next time. Compare your reflection with the \(target.rawValue) guidance before drawing a conclusion.",
            limitations: "\(note) Speech-to-text may be inaccurate. This scan does not understand the full client context, vocal tone, nonverbal behavior, consent, ethics, or the quality and impact of a coach’s intervention. It cannot determine whether a session passes an ICF performance evaluation."
        )
    }

    private static func finding(_ name: String, turns: [TranscriptUtterance], message: String) -> CompetencyFinding {
        let status: FindingStatus = turns.count >= 2 ? .evidence : (turns.isEmpty ? .notObserved : .mixed)
        return CompetencyFinding(competency: name, status: status, note: message, turnIDs: sampleIDs(turns))
    }

    private static func isQuestion(_ text: String) -> Bool {
        text.contains("?") || containsAny(text, ["吗", "么", "什么", "为什么", "怎么", "如何", "谁", "哪里", "是否", "可不可以"])
    }

    private static func isOpenQuestion(_ text: String) -> Bool {
        containsAny(text, ["what", "how", "why", "tell me", "describe", "imagine", "what matters", "你希望", "你在乎", "对你来说", "是什么", "怎么想", "如何看", "为什么"])
    }

    private static func isAdviceLike(_ text: String) -> Bool {
        containsAny(text, ["you should", "you need to", "i recommend", "i suggest", "you could try", "what if you", "你应该", "你需要", "我建议", "你可以尝试"])
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        let lower = text.lowercased()
        return phrases.contains(where: lower.contains)
    }

    private static func sampleIDs(_ turns: [TranscriptUtterance]) -> [Int] { Array(turns.prefix(3).map(\.id)) }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func modelReview(_ session: CoachingSession, target: CredentialLevel) async throws -> PracticeReview {
        let instructions = """
        You are a reflective practice aide for an experienced coach. Assess only the supplied transcript, with balanced and specific feedback. Do not make a credentialing decision, predict a pass, or present yourself as an ICF assessor. Distinguish an absence of transcript evidence from evidence that a behavior did not happen. Never infer vocal tone, nonverbal behavior, consent, ethics, or client impact from text. Speaker labels are user-entered; do not attribute unassigned turns to either person. Use only exact turn numbers as evidence and never invent quotes. Return concise, respectful coaching language. For each criterion, use only the status strings Evidence seen, Mixed evidence, Not observed, or Review needed.
        """
        let transcript = session.transcript.prefix(110).map { utterance in
            "[\(utterance.id)] \(utterance.timestamp) \(utterance.speaker.rawValue.uppercased()): \(utterance.text)"
        }.joined(separator: "\n")
        let levelDescription = target == .acc
            ? "ACC practice lens: foundational application of coaching skills, a clear shared session focus, active listening, client-directed exploration, and staying in the coach role."
            : "PCC practice lens: deeper client connection and partnership, work that is fully client-driven with shared responsibility, exploration of meaning and alignment, and learning translated into client-owned growth."
        let prompt = """
        Review this coaching session for reflective practice at the \(target.rawValue) level.
        \(levelDescription)
        Consider these eight competency areas: \(competencies.joined(separator: "; ")). Use the transcript as limited evidence, not a checklist. For each area, give one concise observation and cite up to three supplied turn numbers. Use Review needed for dimensions a transcript cannot establish. Keep readiness wording qualitative and explicitly non-credentialing.

        Session date: \(session.date.formatted(date: .abbreviated, time: .omitted)); transcript language: \(session.language).

        TRANSCRIPT
        \(transcript)
        """
        let result = try await LanguageModelSession(instructions: instructions).respond(to: prompt, generating: GeneratedReview.self).content
        func notes(_ generated: [GeneratedNote]) -> [EvidenceNote] {
            generated.map { note in
                EvidenceNote(title: note.title, detail: note.detail, turnIDs: validIDs(note.turnNumbers, in: session.transcript))
            }
        }
        let findings = result.criteria.map { item in
            CompetencyFinding(
                competency: item.competency,
                status: FindingStatus(rawValue: item.status) ?? .reviewNeeded,
                note: item.note,
                turnIDs: validIDs(item.turnNumbers, in: session.transcript)
            )
        }
        return PracticeReview(
            targetLevel: target,
            method: "Apple on-device language model",
            alignment: result.alignment,
            summary: result.summary,
            strengths: notes(result.strengths),
            growthAreas: notes(result.growthAreas),
            findings: findings,
            nextPractice: result.nextPractice,
            limitations: "This is a transcript-only practice reflection generated on this Mac. It is not an official ICF assessment or pass prediction. Turn numbers are checked against the transcript, but the interpretation can still be wrong. A trained ICF assessor evaluates submitted performance recordings against the applicable current criteria."
        )
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedNote {
        var title: String
        var detail: String
        var turnNumbers: [Int]
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedCriterion {
        var competency: String
        var status: String
        var note: String
        var turnNumbers: [Int]
    }

    @available(macOS 26.0, *)
    @Generable
    struct GeneratedReview {
        var alignment: String
        var summary: String
        var strengths: [GeneratedNote]
        var growthAreas: [GeneratedNote]
        var criteria: [GeneratedCriterion]
        var nextPractice: String
    }

    @available(macOS 26.0, *)
    private static func validIDs(_ ids: [Int], in turns: [TranscriptUtterance]) -> [Int] {
        let valid = Set(turns.map(\.id))
        return Array(ids.filter(valid.contains).prefix(3))
    }
    #endif
}
