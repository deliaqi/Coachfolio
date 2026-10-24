import Foundation

enum SidebarRoute: Hashable {
    case overview
    case clients
    case client(UUID)
    case session(UUID)
}

enum CredentialLevel: String, Codable, CaseIterable, Identifiable {
    case acc = "ACC"
    case pcc = "PCC"
    var id: String { rawValue }
}

enum Speaker: String, Codable, CaseIterable, Identifiable {
    case unknown = "Unassigned"
    case coach = "Coach"
    case client = "Client"
    var id: String { rawValue }

    var color: String {
        switch self {
        case .unknown: "neutral"
        case .coach: "forest"
        case .client: "blue"
        }
    }
}

struct CoachClient: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var notes: String = ""
}

struct TranscriptUtterance: Identifiable, Codable, Hashable {
    var id: Int
    var startTime: TimeInterval
    var speaker: Speaker = .unknown
    var speakerID: Int? = nil
    var text: String

    var timestamp: String {
        let seconds = max(0, Int(startTime))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum FindingStatus: String, Codable, CaseIterable {
    case evidence = "Evidence seen"
    case mixed = "Mixed evidence"
    case notObserved = "Not observed"
    case reviewNeeded = "Review needed"

    var color: String {
        switch self {
        case .evidence: "forest"
        case .mixed: "gold"
        case .notObserved: "rose"
        case .reviewNeeded: "neutral"
        }
    }
}

struct EvidenceNote: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var detail: String
    var turnIDs: [Int] = []
}

struct CompetencyFinding: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var competency: String
    var status: FindingStatus
    var note: String
    var turnIDs: [Int] = []
}

struct PracticeReview: Codable, Hashable {
    var createdAt: Date = Date()
    var targetLevel: CredentialLevel
    var method: String
    var alignment: String
    var summary: String
    var strengths: [EvidenceNote]
    var growthAreas: [EvidenceNote]
    var findings: [CompetencyFinding]
    var nextPractice: String
    var limitations: String
    var accReadiness: String? = nil
    var accReadinessRationale: String? = nil
}

struct CoachingSession: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var clientID: UUID
    var title: String
    var date: Date
    var language: String
    var audioFilename: String
    var duration: TimeInterval = 0
    var consentConfirmed: Bool = false
    var openAIConsentConfirmed: Bool? = nil
    var transcript: [TranscriptUtterance] = []
    var review: PracticeReview?

    var hasTranscript: Bool {
        transcript.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var formattedDuration: String {
        guard duration > 0 else { return "—" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct StudioData: Codable {
    var clients: [CoachClient] = []
    var sessions: [CoachingSession] = []
}

enum ImportLanguage: String, CaseIterable, Identifiable {
    case english = "English"
    case mandarin = "Chinese (Mandarin)"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case japanese = "Japanese"
    case other = "Other"

    var id: String { rawValue }
    var whisperLanguageCode: String? {
        switch self {
        case .english: "en"
        case .mandarin: "zh"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        case .japanese: "ja"
        case .other: nil
        }
    }

    static func guess(from filename: String) -> ImportLanguage {
        let name = filename.lowercased()
        if name.contains("chinese") || name.contains("mandarin") || name.contains("中文") { return .mandarin }
        if name.contains("spanish") { return .spanish }
        if name.contains("french") { return .french }
        if name.contains("german") { return .german }
        if name.contains("japanese") { return .japanese }
        return .english
    }
}

enum FilenameHints {
    static func clientName(from filename: String) -> String {
        var value = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        value = value.replacingOccurrences(of: #"^\d{8}[_ -]*"#, with: "", options: .regularExpression)
        let languageSuffixes = ["_english", "_chinese", "_mandarin", "_spanish", "_french", "_german", "_japanese"]
        for suffix in languageSuffixes where value.lowercased().hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
            break
        }
        value = value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func date(from filename: String) -> Date? {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let match = base.range(of: #"^\d{8}"#, options: .regularExpression) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: String(base[match]))
    }
}

enum StandardsLinks {
    static let coreCompetencies = URL(string: "https://coachingfederation.org/wp-content/uploads/2025/09/icf-cs-core-competencies-2025.pdf")!
    static let accCriteria = URL(string: "https://coachingfederation.org/credentialing/performance-evaluations/criteria-for-assessing-acc/")!
    static let pccCriteria = URL(string: "https://coachingfederation.org/credentialing/performance-evaluations/criteria-for-assessing-pcc/")!
}
