import Foundation

/// Uses the production callback adapter with fictional values, never an EKEventStore.
private actor FictionalNativeReader: NativeSourceReading {
    private var reminderResults: [[TaskItem]?]
    private(set) var reminderReads = 0
    private let sources: [SourceOption]

    init(sources: [SourceOption], reminderResults: [[TaskItem]?]) {
        self.sources = sources
        self.reminderResults = reminderResults
    }

    func reminders() async throws -> ReminderSnapshot {
        reminderReads += 1
        let result = reminderResults.removeFirst()
        let items: [TaskItem] = try await NativeSourceRead.fetchSnapshot(source: "Reminders") { completion in
            completion(result)
        }
        return .init(sources: sources, reminders: items)
    }

    func calendar(from start: Date, to end: Date) async throws -> CalendarSnapshot {
        throw NativeSourceReadError.unavailable("Calendar")
    }

    func completedReminders(excluded: Set<String>, now: Date) async throws -> [CompletedReminder] {
        throw NativeSourceReadError.unavailable("Reminders")
    }
}

private final class CollectionClock: @unchecked Sendable {
    private let lock = NSLock()
    private let value: Date
    private var count = 0

    init(_ value: Date) { self.value = value }
    func read() -> Date {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return value
    }
    var reads: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}
private final class PendingNativeFetch: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (([TaskItem]?) -> Void)?
    private var cancellations = 0
    private var finished = false
    func register(_ callback: @escaping ([TaskItem]?) -> Void) -> (() -> Void) {
        lock.lock(); self.callback = callback; lock.unlock()
        return { self.lock.lock(); self.cancellations += 1; self.lock.unlock() }
    }
    func finish() { lock.lock(); finished = true; lock.unlock() }
    var state: (registered: Bool, cancelled: Int, finished: Bool) { lock.lock(); defer { lock.unlock() }; return (callback != nil, cancellations, finished) }
    func deliver(_ items: [TaskItem]?) { lock.lock(); let callback = callback; lock.unlock(); callback?(items) }
}

@main struct NativeSourceReadChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }

        let oldSuccess = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshed = oldSuccess.addingTimeInterval(60)
        let source = SourceOption(id: "fictional-list", title: "Fictional list", account: "Fictional account", writable: true)
        let oldTask = TaskItem(id: "existing-task", listID: source.id, title: "Prepare fictional report", due: nil, hasTime: false, sourceLabel: source.label, writable: true, recurring: false)
        let newTask = TaskItem(id: "new-task", listID: source.id, title: "Plan fictional meeting", due: refreshed, hasTime: true, sourceLabel: source.label, writable: true, recurring: false)
        let original = ReminderSnapshot(sources: [source], reminders: [oldTask])
        let reader = FictionalNativeReader(sources: [source], reminderResults: [nil, [], [newTask]])
        let boundary: any NativeSourceReading = reader
        var state = NativeSourceCollection(snapshot: original, health: SourceHealth(lastSuccess: oldSuccess, loading: true))
        let clock = CollectionClock(refreshed)

        state = await state.collecting(read: { try await boundary.reminders() }, now: { clock.read() })
        check(state.snapshot.reminders.map(\.id) == [oldTask.id], "A nil callback must retain the saved reminder identities.")
        check(state.snapshot.sources == original.sources, "An unavailable fetch must retain its old sources too.")
        check(state.health.lastSuccess == oldSuccess, "Unavailable data must not receive a fresh success timestamp.")
        check(state.health.error == "Reminders did not return a result. Refresh to try again.", "Unavailable reads must carry the source failure.")
        check(state.health.detail.hasPrefix("Stale · "), "A cached snapshot must be visibly stale after failure.")
        check(!state.health.loading && clock.reads == 0, "Failure must stop loading without claiming a successful read.")

        state.health.loading = true
        state = await state.collecting(read: { try await boundary.reminders() }, now: { clock.read() })
        check(state.snapshot.reminders.isEmpty, "A successful empty callback must clear old reminders.")
        check(state.snapshot.sources == [source], "A successful empty list still retains collected source metadata.")
        check(state.health.lastSuccess == refreshed && state.health.error == nil && !state.health.loading, "A real empty result must clear stale failure and record success.")
        check(clock.reads == 1, "Collection time is recorded only at successful completion.")

        state = await state.collecting(read: { try await boundary.reminders() }, now: { clock.read() })
        check(state.snapshot.reminders.map(\.id) == [newTask.id], "A successful populated callback must replace the snapshot.")
        check(await reader.reminderReads == 3, "Failures must not trigger an automatic replay.")

        let initial = NativeSourceCollection(snapshot: original, health: SourceHealth(loading: true))
        let unavailable = await initial.collecting(read: { throw IntegrationError.denied("Reminders") }, now: { clock.read() })
        check(unavailable.snapshot.reminders.map(\.id) == [oldTask.id] && unavailable.health.lastSuccess == nil, "Permission failure must preserve data without manufacturing previous success.")
        check(unavailable.health.error?.contains("access denied") == true && !unavailable.health.loading, "Other source failures must retain their actual explanation.")

        // Cancellation after a provider returns must not allow its late snapshot
        // to replace data or masquerade as newly collected context.
        let cancelled = Task {
            await state.collecting(read: {
                withUnsafeCurrentTask { $0?.cancel() }
                return original
            }, now: { clock.read() })
        }
        let afterCancellation = await cancelled.value
        check(afterCancellation.snapshot.reminders.map(\.id) == [newTask.id], "Cancelled late success must leave the previous snapshot in place.")
        check(afterCancellation.health.lastSuccess == refreshed && afterCancellation.health.error?.contains("cancelled") == true && !afterCancellation.health.loading, "Cancellation must not claim fresh evidence.")
        check(clock.reads == 2, "Cancellation must not read the success clock.")

        let cancelledCallback = Task {
            try await NativeSourceRead.fetchSnapshot(source: "Reminders") { completion in
                withUnsafeCurrentTask { $0?.cancel() }
                completion([newTask])
            }
        }
        do {
            _ = try await cancelledCallback.value
            preconditionFailure("A callback received after cancellation must not become a successful read.")
        } catch is CancellationError {
            check(true, "The production callback adapter must reject a cancelled successful result.")
        }

        let pending = PendingNativeFetch()
        let stopped = Task {
            defer { pending.finish() }
            let _: [TaskItem] = try await NativeSourceRead.fetchCancellableSnapshot(source: "Reminders", fetch: pending.register)
        }
        while !pending.state.registered { try await Task.sleep(for: .milliseconds(1)) }
        stopped.cancel()
        for _ in 0..<100 where !pending.state.finished { try await Task.sleep(for: .milliseconds(2)) }
        check(pending.state.finished && pending.state.cancelled == 1, "Stop must release a held callback and cancel its provider exactly once.")
        pending.deliver([newTask]); pending.deliver(nil)
        do { try await stopped.value; preconditionFailure("A stopped fetch succeeded") } catch is CancellationError {}

        let expired = PendingNativeFetch()
        do {
            let _: [TaskItem] = try await NativeSourceRead.fetchCancellableSnapshot(source: "Reminders", timeout: 0.01, fetch: expired.register)
            preconditionFailure("A provider without a callback did not time out")
        } catch NativeSourceReadError.timedOut(let source) { check(source == "Reminders" && expired.state.cancelled == 1, "Deadline must release the waiter and cancel the native request.") }
        expired.deliver([newTask])

        let registrationRace = PendingNativeFetch()
        let race = Task {
            let _: [TaskItem] = try await NativeSourceRead.fetchCancellableSnapshot(source: "Reminders", fetch: { callback in
                withUnsafeCurrentTask { $0?.cancel() }
                return registrationRace.register(callback)
            })
        }
        do { try await race.value; preconditionFailure("Cancellation during registration succeeded") } catch is CancellationError {}
        check(registrationRace.state.cancelled == 1, "Cancellation before the native token returns must still cancel that token.")
        registrationRace.deliver([newTask])

        let success = PendingNativeFetch()
        let successTask = Task { try await NativeSourceRead.fetchCancellableSnapshot(source: "Reminders", timeout: 0.02, fetch: success.register) }
        while !success.state.registered { try await Task.sleep(for: .milliseconds(1)) }
        success.deliver([newTask]); success.deliver(nil)
        let successful = try await successTask.value
        try await Task.sleep(for: .milliseconds(30))
        check(successful.map(\.id) == [newTask.id] && success.state.cancelled == 0, "Successful/duplicate callbacks must not later time out or cancel the provider.")

        let retainedHealth = SourceHealth(lastSuccess: oldSuccess, error: "Existing failure", loading: true)
        let failedCalendar = await NativeSourceCollection(snapshot: CalendarSnapshot(sources: [source], events: []), health: retainedHealth).collecting(read: { try await boundary.calendar(from: oldSuccess, to: refreshed) })
        check(failedCalendar.health.lastSuccess == oldSuccess && failedCalendar.health.error?.hasPrefix("Calendar") == true && !failedCalendar.health.loading, "The typed boundary must preserve failure semantics for each native source.")

        print("PASS \(checks) native source read assertions: nil/empty/populated callbacks, cached data and health, permission failure, cancellation and no replay; no native store or inference.")
    }
}
