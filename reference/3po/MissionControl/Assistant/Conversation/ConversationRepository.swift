import Foundation
import SwiftData

struct ConversationSaveStatistics: Equatable {
    var encodedBytes = 0
    var encodedTurns = 0
    var writtenRecords = 0
    var removedRecords = 0
}

enum ConversationStorageFailure: LocalizedError {
    case unavailable, invalid(String), changed, readback
    var errorDescription: String? {
        switch self {
        case .unavailable: "Conversation storage is unavailable."
        case .invalid(let detail): "Conversation storage could not be read: " + detail
        case .changed: "Conversation storage changed. Reopen it before saving."
        case .readback: "Conversation save could not be verified. Reopen it before continuing."
        }
    }
}

/// Additive chunked storage. The legacy bytes remain an untouched recovery original.
/// Metadata, changed chunks and their new index revision commit in one owned transaction.
@MainActor final class ConversationRepository {
    static let legacyKey = "assistantConversations"
    static let indexKey = "assistantConversations.chunked.index"
    static let chunkSize = 64
    private struct Entry: Codable { var id: UUID; var turnCount: Int; var chunkCount: Int }
    private struct Index: Codable { var version = 1; var revision = UUID(); var conversations: [Entry] }
    private let repository: LocalRecordRepository?
    private var loaded = false
    private var requiresReload = false
    private var snapshot: [AssistantConversation] = []
    private var priorIndex: Index?
    private var priorIndexData: Data?
    private var legacyData: Data?
    private var rawIndex: [String: Any]?
    private var rawMetadata: [UUID: [String: Any]] = [:]
    private var rawTurns: [UUID: [UUID: [String: Any]]] = [:]
    private(set) var lastSave = ConversationSaveStatistics()

    init(container: ModelContainer?, repository: LocalRecordRepository? = nil) {
        self.repository = repository ?? container.map { LocalRecordRepository(container: $0) }
    }
    static func metadataKey(_ id: UUID) -> String { "assistantConversations.chunked.metadata." + id.uuidString }
    static func chunkKey(_ id: UUID, _ number: Int) -> String { "assistantConversations.chunked.turns." + id.uuidString + "." + String(number) }
    private static func chunks(_ turns: Int) -> Int { turns / chunkSize + (turns % chunkSize == 0 ? 0 : 1) }
    /// Foundation normalises JSON numbers through Decimal/Double. Refuse values
    /// outside exact Decimal precision/range instead of rounding opaque future data.
    private static func requireLosslessNumbers(_ data: Data) throws {
        let bytes = Array(data), numeric = Set("0123456789.eE+-".utf8)
        var index = 0, inString = false, escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 45 || (48...57).contains(byte) {
                var end = index + 1
                while end < bytes.count && numeric.contains(bytes[end]) { end += 1 }
                let token = String(decoding: bytes[index..<end], as: UTF8.self)
                let parts = token.split { $0 == "e" || $0 == "E" }
                let mantissa = parts.first ?? "", digits = Array(mantissa.utf8.filter { (48...57).contains($0) }).drop { $0 == 48 }
                if !digits.isEmpty {
                    let trailing = digits.reversed().prefix { $0 == 48 }.count
                    let fraction = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.index(after: $0), to: mantissa.endIndex) } ?? 0
                    guard let exponent = parts.count == 1 ? 0 : Int(parts[1]), (-128...127).contains(exponent),
                          digits.count - trailing <= 38, (-128...127).contains(exponent - fraction + trailing) else { throw ConversationStorageFailure.invalid("Unsupported opaque numeric precision or range; original bytes are preserved.") }
                }
                index = end; continue
            }
            index += 1
        }
    }
    private static func object(_ data: Data) throws -> [String: Any] {
        try requireLosslessNumbers(data)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ConversationStorageFailure.invalid("Expected an object.") }
        return value
    }
    private static func rows(_ data: Data) throws -> [[String: Any]] {
        try requireLosslessNumbers(data)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ConversationStorageFailure.invalid("Expected conversation or turn records.") }
        return value
    }
    private static func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private static func validate(_ conversations: [AssistantConversation]) throws {
        guard Set(conversations.map(\.id)).count == conversations.count,
              conversations.allSatisfy({ Set($0.turns.map(\.id)).count == $0.turns.count }) else { throw ConversationStorageFailure.invalid("Duplicate conversation or turn identities.") }
    }
    private static func turnMap(_ rows: [[String: Any]], turns: [AssistantTurn]) throws -> [UUID: [String: Any]] {
        guard rows.count == turns.count else { throw ConversationStorageFailure.invalid("Turn count mismatch.") }
        return Dictionary(uniqueKeysWithValues: zip(turns, rows).map { ($0.0.id, $0.1) })
    }

    func load() throws -> [AssistantConversation] {
        guard let repository else { throw ConversationStorageFailure.unavailable }
        let indexData = try repository.read(Self.indexKey)
        var conversations: [AssistantConversation] = [], metadata: [UUID: [String: Any]] = [:], turns: [UUID: [UUID: [String: Any]]] = [:]
        var index: Index?, indexObject: [String: Any]?, original: Data?
        if let indexData {
            let decoded = try JSONDecoder().decode(Index.self, from: indexData)
            guard decoded.version == 1 else { throw ConversationStorageFailure.invalid("Unsupported index version.") }
            guard Set(decoded.conversations.map(\.id)).count == decoded.conversations.count,
                  decoded.conversations.allSatisfy({ $0.turnCount >= 0 && $0.chunkCount == Self.chunks($0.turnCount) }) else { throw ConversationStorageFailure.invalid("Invalid index identities or chunk counts.") }
            for entry in decoded.conversations {
                guard let bytes = try repository.read(Self.metadataKey(entry.id)) else { throw ConversationStorageFailure.invalid("Missing conversation metadata.") }
                var object = try Self.object(bytes), allRows: [[String: Any]] = []
                // Metadata cannot carry a hidden second history.
                guard object["turns"] == nil else { throw ConversationStorageFailure.invalid("Turns found in metadata.") }
                for number in 0..<entry.chunkCount {
                    guard let chunk = try repository.read(Self.chunkKey(entry.id, number)) else { throw ConversationStorageFailure.invalid("Missing conversation chunk.") }
                    let rows = try Self.rows(chunk)
                    guard rows.count == min(Self.chunkSize, entry.turnCount - number * Self.chunkSize) else { throw ConversationStorageFailure.invalid("Conversation chunk size mismatch.") }
                    allRows.append(contentsOf: rows)
                }
                object["turns"] = allRows
                let conversation = try JSONDecoder().decode(AssistantConversation.self, from: Self.data(object))
                guard conversation.id == entry.id else { throw ConversationStorageFailure.invalid("Conversation metadata identity mismatch.") }
                conversations.append(conversation)
                object.removeValue(forKey: "turns"); metadata[entry.id] = object
                // Duplicate IDs are checked before constructing the map.
                guard Set(conversation.turns.map(\.id)).count == conversation.turns.count else { throw ConversationStorageFailure.invalid("Duplicate turn identities.") }
                turns[entry.id] = try Self.turnMap(allRows, turns: conversation.turns)
            }
            index = decoded; indexObject = try Self.object(indexData)
        } else {
            original = try repository.read(Self.legacyKey)
            if let original {
                conversations = try JSONDecoder().decode([AssistantConversation].self, from: original)
                try Self.validate(conversations)
                for (conversation, var object) in zip(conversations, try Self.rows(original)) {
                    let rows = object["turns"] as? [[String: Any]] ?? []
                    turns[conversation.id] = try Self.turnMap(rows, turns: conversation.turns)
                    object.removeValue(forKey: "turns"); metadata[conversation.id] = object
                }
            }
        }
        try Self.validate(conversations)
        // Publish only after the complete indexed history has been verified.
        snapshot = conversations; priorIndex = index; priorIndexData = indexData; legacyData = original
        rawIndex = indexObject; rawMetadata = metadata; rawTurns = turns; loaded = true
        requiresReload = false
        return conversations
    }

    // These types use synthesised Codable keys matching stored property names. Mirror
    // includes nil optional properties, preventing known nil fields from resurrecting.
    // A future custom CodingKeys mapping must update this schema and its regression checks.
    private static func keys<T>(_ value: T) -> Set<String> { Set(Mirror(reflecting: value).children.compactMap { $0.label }) }
    private static func preservingUnknown(_ new: [String: Any], old: [String: Any]?, known: Set<String>) -> [String: Any] {
        var result = new
        for (key, value) in old ?? [:] where !known.contains(key) && result[key] == nil { result[key] = value }
        return result
    }
    private static func sameID(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        guard let left = a["id"] as? String, let right = b["id"] as? String else { return false }
        return UUID(uuidString: left) != nil && UUID(uuidString: left) == UUID(uuidString: right)
    }
    private static func encodedTurn(_ turn: AssistantTurn, old: [String: Any]?) throws -> [String: Any] {
        var row = preservingUnknown(try object(JSONEncoder().encode(turn)), old: old, known: keys(turn))
        if let capture = turn.contextCapture, let new = row["contextCapture"] as? [String: Any], let previous = old?["contextCapture"] as? [String: Any], sameID(new, previous) {
            var merged = preservingUnknown(new, old: previous, known: keys(capture))
            if let lookups = capture.lookups, let values = new["lookups"] as? [[String: Any]] {
                let priorLookups = previous["lookups"] as? [[String: Any]] ?? []
                merged["lookups"] = zip(lookups, values).map { lookup, value in preservingUnknown(value, old: priorLookups.first { sameID(value, $0) }, known: keys(lookup)) }
            }
            row["contextCapture"] = merged
        }
        if let images = turn.images, let values = row["images"] as? [[String: Any]] {
            let previous = old?["images"] as? [[String: Any]] ?? []
            row["images"] = zip(images, values).map { image, value in
                preservingUnknown(value, old: previous.first { sameID(value, $0) }, known: keys(image))
            }
        }
        return row
    }
    private static func metadata(_ conversation: AssistantConversation) -> AssistantConversation { var value = conversation; value.turns = []; return value }
    private static func ownedKeys(_ index: Index?) -> Set<String> {
        Set((index?.conversations ?? []).flatMap { entry in [metadataKey(entry.id)] + (0..<entry.chunkCount).map { chunkKey(entry.id, $0) } })
    }

    func save(_ conversations: [AssistantConversation]) throws {
        guard let repository else { throw ConversationStorageFailure.unavailable }
        guard !requiresReload else { throw ConversationStorageFailure.readback }
        if !loaded { _ = try load() }
        try Self.validate(conversations)
        guard try repository.read(Self.indexKey) == priorIndexData else { throw ConversationStorageFailure.changed }
        if priorIndex == nil { guard try repository.read(Self.legacyKey) == legacyData else { throw ConversationStorageFailure.changed } }
        let previous = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        var values: [String: Data] = [:], nextMetadata: [UUID: [String: Any]] = [:], nextTurns: [UUID: [UUID: [String: Any]]] = [:]
        var statistics = ConversationSaveStatistics()
        let nextIndex = Index(conversations: conversations.map { .init(id: $0.id, turnCount: $0.turns.count, chunkCount: Self.chunks($0.turns.count)) })
        for conversation in conversations {
            let old = previous[conversation.id]
            var metadata = rawMetadata[conversation.id] ?? [:]
            if priorIndex == nil || old.map({ Self.metadata($0) != Self.metadata(conversation) }) ?? true {
                let encoded = try Self.object(JSONEncoder().encode(Self.metadata(conversation)))
                metadata = Self.preservingUnknown(encoded, old: metadata, known: Self.keys(conversation)); metadata.removeValue(forKey: "turns")
                values[Self.metadataKey(conversation.id)] = try Self.data(metadata)
            }
            nextMetadata[conversation.id] = metadata
            let currentIDs = Set(conversation.turns.map(\.id))
            var rows = (rawTurns[conversation.id] ?? [:]).filter { currentIDs.contains($0.key) }
            for number in 0..<Self.chunks(conversation.turns.count) {
                let start = number * Self.chunkSize, end = min(start + Self.chunkSize, conversation.turns.count)
                let changed = old.map { previous in
                    guard start < previous.turns.count else { return true }
                    let oldEnd = min(start + Self.chunkSize, previous.turns.count)
                    return Array(previous.turns[start..<oldEnd]) != Array(conversation.turns[start..<end])
                } ?? true
                if priorIndex == nil || changed {
                    var chunk: [[String: Any]] = []
                    for turn in conversation.turns[start..<end] {
                        let row = try Self.encodedTurn(turn, old: rawTurns[conversation.id]?[turn.id])
                        chunk.append(row); rows[turn.id] = row
                    }
                    values[Self.chunkKey(conversation.id, number)] = try Self.data(chunk)
                    statistics.encodedTurns += chunk.count
                }
            }
            nextTurns[conversation.id] = rows
        }
        let removals = Self.ownedKeys(priorIndex).subtracting(Self.ownedKeys(nextIndex))
        if priorIndex != nil && values.isEmpty && removals.isEmpty && snapshot.map(\.id) == conversations.map(\.id) { lastSave = statistics; return }
        let ownedBefore = Self.ownedKeys(priorIndex)
        for key in values.keys where !ownedBefore.contains(key) {
            // An absent index does not authorise overwriting an orphan/future record
            // that happens to share our namespace and a requested new identity.
            guard try repository.read(key) == nil else { throw ConversationStorageFailure.changed }
        }
        var indexObject = Self.preservingUnknown(try Self.object(JSONEncoder().encode(nextIndex)), old: rawIndex, known: Self.keys(nextIndex))
        // Preserve future optional entry metadata for the same exact conversation ID.
        let oldEntries = rawIndex?["conversations"] as? [[String: Any]] ?? []
        indexObject["conversations"] = zip(nextIndex.conversations, indexObject["conversations"] as? [[String: Any]] ?? []).map { entry, value in
            Self.preservingUnknown(value, old: oldEntries.first { Self.sameID(value, $0) }, known: Self.keys(entry))
        }
        let indexData = try Self.data(indexObject); values[Self.indexKey] = indexData
        try repository.write(values, removing: removals)
        do {
            for (key, expected) in values { guard try repository.read(key) == expected else { throw ConversationStorageFailure.readback } }
            for key in removals { guard try repository.read(key) == nil else { throw ConversationStorageFailure.readback } }
        } catch {
            // Commit returned, but its verification did not. Explicit fresh load
            // must reconcile it even if the stored index appears unchanged.
            requiresReload = true
            throw error
        }
        statistics.encodedBytes = values.values.reduce(0) { $0 + $1.count }
        statistics.writtenRecords = values.count; statistics.removedRecords = removals.count
        snapshot = conversations; priorIndex = nextIndex; priorIndexData = indexData; rawIndex = indexObject
        rawMetadata = nextMetadata; rawTurns = nextTurns; lastSave = statistics
    }
}
