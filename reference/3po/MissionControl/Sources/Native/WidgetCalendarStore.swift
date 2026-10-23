import Foundation
import Observation

@MainActor @Observable final class WidgetCalendarStore {
    var revision = 0
    private var cache: [String:CalendarSnapshot] = [:]
    private var pending: [String:Task<CalendarSnapshot,Error>] = [:]
    private let service: EventKitService
    init(service: EventKitService) { self.service = service }
    func invalidate() { revision += 1; cache = [:] }
    func load(_ range: DateInterval) async throws -> CalendarSnapshot {
        let key = "\(revision):\(range.start.timeIntervalSince1970):\(range.end.timeIntervalSince1970)"
        if let result = cache[key] { return result }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await service.calendar(from:range.start,to:range.end) }; pending[key] = task
        defer { pending[key] = nil }
        let value = try await task.value
        if cache.count > 32 { cache.removeAll() }
        cache[key] = value; return value
    }
}
