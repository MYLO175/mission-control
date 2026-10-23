import Foundation

/// Metadata only: unsupported saved pages reserve their identity without exposing their content.
enum ContextPageIdentityStatus: Equatable, Sendable {
    case missing, available, preserved, unavailable
}

/// A readable projection, not a replacement for canonical facts or action receipts.
struct ContextPage: Codable, Equatable, Identifiable, Sendable {
    struct Kind: RawRepresentable, Codable, Hashable, Sendable {
        var rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
        func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
        static let overview = Self(rawValue: "overview")
        static let topic = Self(rawValue: "topic")
        static let project = Self(rawValue: "project")
        static let calendarPurpose = Self(rawValue: "calendarPurpose")
        static let note = Self(rawValue: "note")
        static let instruction = Self(rawValue: "instruction")
        var isSupported: Bool { [.overview, .topic, .project, .calendarPurpose, .note, .instruction].contains(self) }
    }
    struct Owner: RawRepresentable, Codable, Hashable, Sendable {
        var rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }
        init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
        func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
        static let human = Self(rawValue: "human")
        static let generated = Self(rawValue: "generated")
        var isSupported: Bool { self == .human || self == .generated }
    }

    let id: String
    let registration: String
    let kind: Kind
    let key: String
    var owner: Owner
    var title: String
    var synopsis: String
    var markdown: String
    var references: [ContextPageReference]
    var revision: UUID
    var created: Date
    var updated: Date
    var evidenceQuotes: [ContextPageQuote]? = nil
    /// Page-specific successful input coverage, separate from the support for its current prose.
    var processedReferences: [ContextPageReference]? = nil

    init(registration: String, kind: Kind, key: String, owner: Owner, title: String,
         synopsis: String = "", markdown: String, references: [ContextPageReference] = [],
         revision: UUID = UUID(), created: Date = .now, updated: Date? = nil) {
        self.id = Self.stableID(registration: registration, kind: kind, key: key)
        self.registration = registration; self.kind = kind; self.key = key; self.owner = owner
        self.title = title; self.synopsis = synopsis; self.markdown = markdown
        self.references = references; self.revision = revision; self.created = created; self.updated = updated ?? created
    }

    static func stableID(registration: String, kind: Kind, key: String) -> String {
        "context-page:" + ContextPageIdentity.component(registration) + ":" + ContextPageIdentity.component(kind.rawValue) + ":" + ContextPageIdentity.component(key)
    }
    var isSupported: Bool { kind.isSupported && owner.isSupported }
}

/// Exact bounded support retained separately from the readable page body.
struct ContextPageQuote: Codable, Equatable, Sendable {
    var referenceID: String
    var quote: String
}

/// Exact canonical identity and version. No source bodies, inferred permission or authority.
struct ContextPageReference: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: String
    let key: String
    let revision: String
    init(kind: String, key: String, revision: String) {
        self.id = Self.stableID(kind: kind, key: key)
        self.kind = kind; self.key = key; self.revision = revision
    }
    static func stableID(kind: String, key: String) -> String {
        ContextPageIdentity.component(kind) + ":" + ContextPageIdentity.component(key)
    }
    private enum CodingKeys: String, CodingKey { case id, kind, key, revision }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(String.self, forKey: .kind)
        key = try values.decode(String.self, forKey: .key)
        revision = try values.decode(String.self, forKey: .revision)
        let expected = Self.stableID(kind: kind, key: key)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? expected
        guard id == expected else { throw ContextPageFailure.invalid("reference identity") }
    }
}

/// Every committed page revision is retained; Restore appends a new child version.
struct ContextPageVersion: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let page: ContextPage
    let parentRevision: UUID?
    let restoredFrom: UUID?
    init(page: ContextPage, parentRevision: UUID? = nil, restoredFrom: UUID? = nil) {
        id = page.revision; self.page = page; self.parentRevision = parentRevision; self.restoredFrom = restoredFrom
    }
}

/// Exact inputs processed by successful consolidation cycles, committed with their pages.
/// This is local metadata and is never supplied wholesale as model context.
struct ContextPageCheckpoint: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let registration: String
    var revision: UUID
    var references: [ContextPageReference]
    var updated: Date
    init(registration: String, references: [ContextPageReference], revision: UUID = UUID(), updated: Date = .now) {
        id = Self.stableID(registration: registration)
        self.registration = registration; self.references = references; self.revision = revision; self.updated = updated
    }
    static func stableID(registration: String) -> String { "context-checkpoint:" + ContextPageIdentity.component(registration) }
}

struct ContextPageReferenceChange: Equatable, Sendable {
    let previous: ContextPageReference
    let current: ContextPageReference
}
struct ContextPageChanges: Equatable, Sendable {
    let added: [ContextPageReference]
    let changed: [ContextPageReferenceChange]
    let removed: [ContextPageReference]
    let unchangedCount: Int
    var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }
}

struct ContextPageDirectoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: ContextPage.Kind
    let owner: ContextPage.Owner
    let title: String
    let synopsis: String
    let revision: UUID
    init(_ page: ContextPage) {
        id = page.id; kind = page.kind; owner = page.owner; title = page.title; synopsis = page.synopsis; revision = page.revision
    }
}
struct ContextPageDirectory: Codable, Equatable, Sendable {
    let entries: [ContextPageDirectoryEntry]
    let omittedCount: Int
    func encoded() throws -> Data { try ContextPageLimits.encoder().encode(self) }
}

enum ContextPageLimits {
    static let maximumTitleBytes = 240
    static let maximumSynopsisBytes = 800
    static let maximumMarkdownBytes = 24_000
    static let maximumPageReferences = 512
    static let maximumDirectoryBytes = 8_000
    static let maximumProviderBytes = 32_000

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    /// Reject rather than truncate a page. Callers must first validate current permission/evidence.
    static func providerPayload(_ page: ContextPage, maximumBytes: Int = maximumProviderBytes,
                                isEligible: (ContextPage) -> Bool) throws -> Data? {
        guard page.isSupported, isEligible(page) else { return nil }
        let data = try encoder().encode(page)
        guard maximumBytes >= 0, data.count <= maximumBytes else { throw ContextPageFailure.payloadTooLarge }
        return data
    }
}

enum ContextPageFailure: LocalizedError, Equatable {
    case unavailable, corrupt, unsupportedSchema(Int), unsupportedPage, stalePage, staleCheckpoint, missingVersion, payloadTooLarge
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Context-page storage is unavailable."
        case .corrupt: return "Saved context pages could not be read safely. Original data is preserved."
        case .unsupportedSchema: return "Context pages were saved by an unsupported version. Original data is preserved."
        case .unsupportedPage: return "This page uses an unsupported kind or owner. It is preserved without being used."
        case .stalePage: return "This context page changed. Reopen it before saving."
        case .staleCheckpoint: return "The consolidation checkpoint changed. Prepare it again before saving."
        case .missingVersion: return "That context-page version is unavailable."
        case .payloadTooLarge: return "The context-page payload exceeds its explicit size limit."
        case .invalid("consolidation IDs"): return "The context update returned missing or unexpected page identities. Saved pages and pending changes are retained."
        case .invalid("consolidation result"): return "The model did not finish a structured context-page result. Saved pages and pending changes are retained."
        case .invalid("consolidation page"): return "The context update exceeded its text or evidence bounds. Saved pages and pending changes are retained."
        case .invalid("consolidation evidence"): return "A context update quotation could not be verified against its exact supplied record. Saved pages and pending changes are retained."
        case .invalid("consolidation evidence record"): return "The context update selected a source that was not issued in this batch. Saved pages and pending changes are retained."
        case .invalid("consolidation evidence passage"): return "The context update selected a passage that was not issued for that source. Saved pages and pending changes are retained."
        case .invalid("consolidation evidence selector"): return "The context update returned conflicting evidence selectors. Saved pages and pending changes are retained."
        case .invalid("consolidation evidence quote"): return "A legacy context quotation did not exactly match its supplied source. Saved pages and pending changes are retained."
        case .invalid("project question"): return "The context update returned an unsupported project question. Saved pages and pending changes are retained."
        case .invalid("changed supporting records"): return "Supporting context changed during the page update. Saved pages and pending changes are retained."
        case .invalid("duplicate reference"): return "The context update repeated a supporting record. Saved pages and pending changes are retained."
        case .invalid: return "The context page contains invalid fields. No changes were saved."
        }
    }
}

private enum ContextPageIdentity {
    /// Reversible components are collision-free and do not depend on a mutable title.
    static func component(_ value: String) -> String {
        Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
