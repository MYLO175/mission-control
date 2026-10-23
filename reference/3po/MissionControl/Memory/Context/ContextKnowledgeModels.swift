import Foundation
import CryptoKit

/// Relevance never grants access. Every page resolves its original support for the requesting feature.
enum ContextKnowledgePurpose: String, CaseIterable {
    case conversation, brief, suggestions, manualSuggestions, heartbeatSuggestions
    case email, setup, maintenance, inspection
    var humanOnly: Bool { self == .email || self == .setup }
    var includesWorkingChanges: Bool { !humanOnly }
}

enum ContextFeature: String, CaseIterable, Identifiable {
    case assistant, projects, reminders
    var id: String { rawValue }
    var title: String {
        switch self {
        case .assistant: return "Assistant instructions"
        case .projects: return "Project instructions"
        case .reminders: return "Reminder instructions"
        }
    }
    var defaultText: String {
        switch self {
        case .assistant: return "Use relevant context pages and recent changes to answer naturally and concisely. Read more context when needed, state uncertainty and ask one useful question when essential information is missing. Remember useful enduring context with its original evidence."
        case .projects: return "Use the purpose and current context of existing project spaces to suggest where work belongs. Keep project tasks separate from Apple Reminders. Ask what a project is for when that is unclear. Project creation and changes follow the human's request or approval."
        case .reminders: return "Use relevant project and personal context when helping with reminders. Preserve the human's requested date and destination; ask only for essential missing information. Do not infer completion from elapsed time or a missing source."
        }
    }
}

/// Routing descriptions only. Personal facts and policy bodies stay in their scoped pages.
struct ContextTopicRoute: Identifiable {
    var key: String
    var title: String
    var about: String
    var id: String { "area:" + key }
    var input: [String: String] { ["title": title, "description": about, "read": id] }
    static var all: [Self] {
        LifeArea.allCases.map { area in
            let about: String = switch area {
            case .about: "Personal background, priorities and everyday preferences."
            case .studies: "Education, courses, learning goals and study context."
            case .career: "Career goals, job applications and work preferences."
            case .projects: "Personal projects, building interests and longer-term aims."
            case .interests: "Hobbies, interests and activities you enjoy."
            case .wellbeing: "Wellbeing, habits and personal support preferences."
            case .people: "People, groups and relationships mentioned in your context."
            case .home: "Home, family life and everyday living context."
            case .administration: "Personal administration, accounts and organisation preferences."
            case .unsorted: "Useful context that has not yet been assigned to a topic."
            }
            return .init(key: area.rawValue, title: area.title, about: about)
        } + [.init(key: "recent", title: "Recent context", about: "Saved conversation context and recorded changes spanning topics.")]
    }
    static func named(_ key: String) -> Self? { all.first { $0.key == key } }
}

/// The screen and model use the same exact routes to existing policy owners.
enum ContextInstructionRoute: Hashable, Identifiable {
    case feature(ContextFeature), brief, review, calendars
    static var all: [Self] { ContextFeature.allCases.map(Self.feature) + [.brief, .review, .calendars] }
    var id: String {
        let key = switch self { case .feature(let feature): feature.rawValue; case .brief: "brief"; case .review: "review"; case .calendars: "calendars" }
        return "instructions:" + key
    }
    var title: String {
        switch self { case .feature(let feature): feature.title; case .brief: "Brief instructions"; case .review: "Review guidance"; case .calendars: "Calendar guide" }
    }
    var about: String {
        switch self {
        case .feature(.assistant): "How 3PO should respond and help in conversation."
        case .feature(.projects): "How to organise and plan work in existing project spaces."
        case .feature(.reminders): "How to help with reminders, dates and task destinations."
        case .brief: "What to include in your daily brief and how to write it."
        case .review: "What deserves attention, informed by your Review feedback."
        case .calendars: "What each permitted calendar is for and where events belong."
        }
    }
    var symbol: String {
        switch self { case .feature: "text.alignleft"; case .brief: "sun.max"; case .review: "tray"; case .calendars: "calendar" }
    }
    var input: [String: String] { ["title": title, "description": about, "read": id] }
}

/// Request-local projections. Stored references point to canonical records; no second source archive.
struct ContextKnowledgeRecord {
    var reference: ContextPageReference
    var title: String
    var text: String
    var date: Date
    var areas: [LifeArea] = []
    var memoryID: UUID? = nil
    var projectID: UUID? = nil
    var whatsappChatID: String? = nil
    var relevance: String? = nil
    var input: [String: String] {
        var value = ["id": reference.contextKey, "revision": reference.revision, "title": title,
                     "text": text, "observed": date.ISO8601Format()]
        if let relevance { value["relevance"] = relevance }
        return value
    }
}
extension ContextPageReference {
    var contextKey: String { kind + ":" + key }
}
enum ContextKnowledgeRules {
    static func bytePrefix(_ text: String, maximumBytes: Int) -> String {
        var result = "", count = 0
        for character in text {
            let value = String(character), bytes = value.utf8.count
            guard count + bytes <= maximumBytes else { break }
            result += value; count += bytes
        }
        return result
    }
    static func projectText(title: String, kind: String, notes: String, status: String, due: String?, parent: String?, scope: String) -> String {
        "Title: \(title)\nKind: \(kind)\nStatus: \(status)\nDue: \(due ?? "None recorded")\nParent identity: \(parent ?? "Root")\nContext: \(scope)\nHuman project notes:\n\(notes)"
    }
    static func actionText(confirmed: Int, receipts: [String]) -> String {
        "Verified historical app operations: \(confirmed). This records the app operation only, not real-world completion.\n" + receipts.joined(separator: "\n")
    }
    static func excerpt(_ text: String, offset: Int, limit: Int) -> (text: String, next: Int?, total: Int) {
        let start = min(max(0, offset), text.count)
        let value = String(text.dropFirst(start).prefix(max(0, limit)))
        let end = start + value.count
        return (value, end < text.count ? end : nil, text.count)
    }
    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func json(_ value: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    static func current(_ references: [ContextPageReference], records: [ContextKnowledgeRecord]) -> Bool {
        let current = Dictionary(records.map { ($0.reference.contextKey, $0.reference.revision) }, uniquingKeysWith: { first, _ in first })
        return references.allSatisfy { current[$0.contextKey] == $0.revision }
    }
    static func matches(_ query: String?, title: String, synopsis: String, key: String, selfLabel: String = "") -> Bool {
        guard let query else { return true }
        let terms = MemoryRetrieval.queryTerms(query, selfLabel: selfLabel)
        return !terms.isDisjoint(with: MemoryRetrieval.tokens(title + " " + synopsis + " " + key))
    }
    /// Retrieval candidates only; lexical overlap never establishes project ownership or plan identity.
    static func projectCandidate(_ record: ContextKnowledgeRecord, title: String, notes: String, selfLabel: String = "") -> Bool {
        guard record.reference.kind == "human" || record.reference.kind == "whatsapp" || record.reference.kind.hasPrefix("native-") else { return false }
        let titleTerms = MemoryRetrieval.queryTerms(title, selfLabel: selfLabel).filter { $0.count >= 3 }
        let textTerms = MemoryRetrieval.tokens(record.text + " " + record.title)
        let overlap = titleTerms.intersection(textTerms)
        if overlap.count >= 2 || (titleTerms.count == 1 && overlap.first.map { $0.count >= 5 } == true) { return true }
        let noteTerms = MemoryRetrieval.tokens(notes).filter { $0.count >= 5 }
        return !overlap.isEmpty && noteTerms.intersection(textTerms).count >= 2
    }
}

