import Foundation
import Observation
import SwiftData

/// Numeric/category metadata only: no prompts, replies, sources, credentials or error bodies.
@MainActor @Observable final class AIUsageStore {
    private(set) var state = AIUsageState()
    private(set) var error: String?
    private let container: ModelContainer?
    private var writable = true
    init(container: ModelContainer?, now: Date = .now) {
        self.container = container; state.trackingStarted = now
        do {
            if let record = try LocalRecordRepository.read("paAIUsage", container: container) {
                let saved = try JSONDecoder().decode(AIUsageState.self, from: record)
                guard saved.version == 1, saved.records.count <= AIUsageRules.maximumRecords,
                      Set(saved.records.map(\.id)).count == saved.records.count, saved.records.allSatisfy(AIUsageRules.valid) else { throw CocoaError(.fileReadCorruptFile) }
                state = saved; state.records = saved.records.map { AIUsageRules.recovered($0, now: now) }
            }
        } catch { writable = false; self.error = "Saved usage could not be read. Its original record is preserved; new calls are not being counted." }
    }
    @discardableResult func begin(registration: String, model: String, purpose: AIRequestPurpose, now: Date = .now) -> UUID? {
        let value = AIUsageRecord(registration: registration, model: AIUsageRules.modelLabel(model), purpose: purpose, started: now)
        guard AIUsageRules.valid(value) else { return nil }
        return change(now: now) { $0.records.append(value) } ? value.id : nil
    }
    func finish(_ id: UUID?, outcome: AIRequestOutcome, tokens: AIReportedTokens? = nil, httpStatus: Int? = nil, now: Date = .now) {
        guard let id, outcome != .running, state.records.contains(where: { $0.id == id && $0.outcome == .running }) else { return }
        _ = change(now: now) { state in
            guard let index = state.records.firstIndex(where: { $0.id == id }) else { return }
            state.records[index].outcome = outcome; state.records[index].finished = max(now, state.records[index].started)
            state.records[index].tokens = tokens.flatMap { $0.valid ? $0 : nil }
            state.records[index].httpStatus = httpStatus.flatMap { (100...599).contains($0) ? $0 : nil }
        }
    }
    func records(registration: String, window: AIUsageWindow, now: Date = .now, calendar: Calendar = .current) -> [AIUsageRecord] {
        let start = window.start(now: now, calendar: calendar)
        return state.records.filter { $0.registration == registration && $0.started >= start && $0.started <= now }.sorted { $0.started > $1.started }
    }
    private func change(now: Date, action: (inout AIUsageState) -> Void) -> Bool {
        guard writable, let container else { if error == nil { error = "Usage storage is unavailable. AI work can continue, but new calls are not being counted." }; return false }
        var revised = state; action(&revised)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
        revised.records.sort { $0.started == $1.started ? $0.id.uuidString < $1.id.uuidString : $0.started < $1.started }
        let removed = revised.records.filter { $0.started < cutoff } + Array(revised.records.filter { $0.started >= cutoff }.dropLast(AIUsageRules.maximumRecords))
        revised.records = Array(revised.records.filter { $0.started >= cutoff }.suffix(AIUsageRules.maximumRecords))
        if let last = removed.last { revised.truncatedBefore = max(revised.truncatedBefore ?? .distantPast, last.started) }
        do {
            try LocalRecordRepository(container: container).write(["paAIUsage": JSONEncoder().encode(revised)], now: now)
            state = revised; error = nil; return true
        } catch { self.error = "Usage could not be saved. Counts may be incomplete; AI work is unchanged."; return false }
    }
}
