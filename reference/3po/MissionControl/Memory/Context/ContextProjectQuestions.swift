import Foundation

/// A clarification about an existing human-owned project. This record never creates a project,
/// authorises an action, or contains the human's answer text.
struct ContextProjectQuestion: Codable, Equatable, Identifiable, Sendable {
    struct Status: RawRepresentable, Codable, Hashable, Sendable {
        var rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
        func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
        static let pending = Self(rawValue: "pending")
        static let dismissed = Self(rawValue: "dismissed")
        static let answered = Self(rawValue: "answered")
        var isSupported: Bool { [.pending, .dismissed, .answered].contains(self) }
    }
    static let maximumQuestionCharacters = 300
    static let maximumQuestionBytes = 2_400
    let id: String
    let registration: String
    let projectID: UUID
    let identity: ContextPageReference
    let question: String
    var revision: UUID
    let created: Date
    var updated: Date
    var finished: Date?
    var status: Status
    var answerPageID: String?
    var answerPageRevision: UUID?

    init(registration: String, projectID: UUID, identity: ContextPageReference, question: String,
         revision: UUID = UUID(), created: Date = .now, updated: Date? = nil, finished: Date? = nil,
         status: Status = .pending, answerPageID: String? = nil, answerPageRevision: UUID? = nil) {
        id = Self.stableID(registration: registration, projectID: projectID)
        self.registration = registration; self.projectID = projectID; self.identity = identity
        self.question = question; self.revision = revision; self.created = created; self.updated = updated ?? created
        self.finished = finished; self.status = status; self.answerPageID = answerPageID; self.answerPageRevision = answerPageRevision
    }
    static func stableID(registration: String, projectID: UUID) -> String {
        let account = Data(registration.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "context-project-question:" + account + ":" + projectID.uuidString.lowercased()
    }
    private enum CodingKeys: String, CodingKey {
        case id, registration, projectID, identity, question, revision, created, updated, finished, status, answerPageID, answerPageRevision
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        registration = try values.decode(String.self, forKey: .registration)
        projectID = try values.decode(UUID.self, forKey: .projectID)
        identity = try values.decode(ContextPageReference.self, forKey: .identity)
        question = try values.decode(String.self, forKey: .question)
        revision = try values.decode(UUID.self, forKey: .revision)
        created = try values.decode(Date.self, forKey: .created)
        updated = try values.decodeIfPresent(Date.self, forKey: .updated) ?? created
        finished = try values.decodeIfPresent(Date.self, forKey: .finished)
        status = try values.decode(Status.self, forKey: .status)
        answerPageID = try values.decodeIfPresent(String.self, forKey: .answerPageID)
        answerPageRevision = try values.decodeIfPresent(UUID.self, forKey: .answerPageRevision)
    }
}

/// Admission metadata only; these rules never infer a purpose or change saved question history.
enum ContextProjectQuestionRules {
    static func open(status: String) -> Bool { ["planned", "active", "waiting"].contains(status) }
    static func candidate(status: String, hasOpenWork: Bool, hasHumanNotes: Bool) -> Bool {
        open(status: status) && (hasOpenWork || (status == "active" && hasHumanNotes))
    }
    static func purpose(_ page: ContextPage, registration: String, identity: ContextPageReference) -> Bool {
        let key = "project-purpose:" + identity.key
        return page.registration == registration && page.owner == .human && page.kind == .note && page.key == key &&
            page.id == ContextPage.stableID(registration: registration, kind: .note, key: key) &&
            page.references == [identity] && !page.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    static func actionable(_ question: ContextProjectQuestion, currentIdentity: ContextPageReference?,
                           candidate: Bool, hasPurpose: Bool) -> Bool {
        question.status == .pending && currentIdentity == question.identity && candidate && !hasPurpose
    }
}

enum ContextProjectQuestionFailure: LocalizedError, Equatable {
    case unavailable, corrupt, unsupportedSchema(Int), invalid, stale, finished, notDismissed, unsupportedStatus
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Project-question storage is unavailable."
        case .corrupt: return "Saved project questions could not be read safely. Original data is preserved."
        case .unsupportedSchema: return "Project questions were saved by an unsupported version. Original data is preserved."
        case .invalid: return "The project question contains invalid fields. No changes were saved."
        case .stale: return "This project question changed. Reopen it before continuing."
        case .finished: return "This project question has already been answered or dismissed."
        case .notDismissed: return "Only a currently dismissed project question can be restored."
        case .unsupportedStatus: return "This project question uses an unsupported status. It is preserved without being used."
        }
    }
}
