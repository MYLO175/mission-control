import Foundation

struct AssistantTranscriptPage {
    var rows: [AssistantTranscriptRow]
    var totalCount: Int
    var threadCount: Int
    var lastThreadTurnID: UUID?
    var lastVisibleTurn: AssistantTurn?
}

/// Stable completed history is prepared only when the owning service changes its
/// transcript revision. Delivery support is checked independently on every read:
/// current permissions/evidence and temporal expiry are never frozen by the cache.
/// Those service reads remain in the caller's SwiftUI/Observation tracking scope.
@MainActor final class AssistantTranscriptProjectionCache {
    private var key: Key?
    private var entries: [Entry] = []
    private var positions: [UUID: Int] = [:]
    private var delivered: [AssistantTurn] = []
    private var visibility: [UUID: Bool] = [:]
    private var rows: [AssistantTranscriptRow] = []
    private(set) var threadBuilds = 0
    private(set) var rowBuilds = 0
    private struct Key: Equatable {
        var owner: ObjectIdentifier
        var revision: UUID
        var registration: String
        var feed: UUID?
        var topic: UUID?
        var calendar: Calendar
    }
    private struct Entry {
        var turn: AssistantTurn
        var index: Int
        var topic: Bool
    }
    func value(owner: AnyObject, revision: UUID, registration: String, feed: AssistantConversation?, topic: AssistantConversation?, activeTurnID: UUID?, limit: Int, calendar: Calendar = .current, visible: (AssistantTurn) -> Bool) -> AssistantTranscriptPage {
        let feed = feed?.accountID == registration ? feed : nil
        let topic = topic?.accountID == registration ? topic : nil
        var changed = false
        let current = Key(owner: ObjectIdentifier(owner), revision: revision, registration: registration, feed: feed?.id, topic: topic?.id, calendar: calendar)
        if key != current {
            var next = (feed?.turns ?? []).enumerated().compactMap { offset, turn in
                turn.contextID == topic?.id && turn.profileSessionID == nil ? Entry(turn: turn, index: offset, topic: false) : nil
            }
            next += (topic?.turns ?? []).enumerated().compactMap { offset, turn in
                turn.profileSessionID == nil ? Entry(turn: turn, index: offset, topic: true) : nil
            }
            entries = next.enumerated().sorted {
                let a = $0.element.turn.created ?? .distantPast, b = $1.element.turn.created ?? .distantPast
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            positions = Dictionary(entries.enumerated().map { ($0.element.turn.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            delivered = entries.compactMap { $0.turn.deliveryID == nil ? nil : $0.turn }
            key = current; visibility = [:]; threadBuilds += 1; changed = true
        }
        refreshVisibility(visible, calendar: calendar, force: changed)
        var page = Array(rows.suffix(max(0, limit)))
        var live: AssistantTurn?
        if let activeTurnID, let position = positions[activeTurnID] {
            let entry = entries[position], turns = entry.topic ? topic?.turns : feed?.turns
            if let turns, turns.indices.contains(entry.index), turns[entry.index].id == activeTurnID { live = turns[entry.index] }
        }
        if let live, let index = page.firstIndex(where: { $0.id == live.id }) { page[index].turn = live }
        let last = rows.last.map { row in live?.id == row.id ? live! : row.turn }
        return .init(rows: page, totalCount: rows.count, threadCount: entries.count, lastThreadTurnID: entries.last?.turn.id, lastVisibleTurn: last)
    }
    private func refreshVisibility(_ visible: (AssistantTurn) -> Bool, calendar: Calendar, force: Bool) {
        let next = Dictionary(delivered.map { ($0.id, visible($0)) }, uniquingKeysWith: { first, _ in first })
        if force || next != visibility {
            rows = ConversationRules.transcript(entries.map(\.turn), visible: { $0.deliveryID == nil || next[$0.id] == true }, calendar: calendar)
            rowBuilds += 1
        }
        visibility = next
    }
}

/// Ignore content growth while following the bottom. Only a user scroll away
/// suspends following; reading older messages survives each streamed delta.
struct AssistantTranscriptScrollState: Equatable {
    private(set) var followsBottom = true
    mutating func update(distanceFromBottom: Double, userScrolling: Bool) {
        let near = distanceFromBottom.isFinite && distanceFromBottom <= 80
        if userScrolling || near { followsBottom = near }
    }
    mutating func pause() { followsBottom = false }
    mutating func reset() { followsBottom = true }
}

struct AssistantTranscriptRenderKey: Equatable {
    var turn: AssistantTurn
    var registration: String
    var conversationID: UUID?
    var topicID: UUID?
    var lastTurnID: UUID?
    var replying: Bool
    var toolStatus: String
    var discoveryEntries: [String: UUID]
}
