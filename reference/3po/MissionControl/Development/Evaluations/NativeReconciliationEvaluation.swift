#if DEBUG
import Foundation

/// Exercises the actual dashboard collection/reconciliation path with gated fictional reads.
private actor ReconciliationReader: NativeSourceReading {
    private var gate: CheckedContinuation<ReminderSnapshot, Error>?
    private(set) var reads = 0
    private(set) var calendarReads = 0
    var failNext = false
    let fresh = ReminderSnapshot(sources: [], reminders: [.init(id:"verified-new",listID:"fictional",title:"Fictional saved reminder",due:nil,hasTime:false,sourceLabel:"Fixture",writable:true,recurring:false)])
    func reminders() async throws -> ReminderSnapshot {
        reads += 1
        if reads == 1 { return try await withCheckedThrowingContinuation { gate = $0 } }
        if failNext { failNext=false;throw NativeSourceReadError.unavailable("Fictional reminders") }
        return fresh
    }
    func waitForFirstRead() async { while gate == nil { await Task.yield() } }
    func releaseOld() { gate?.resume(returning:.init(sources:[],reminders:[]));gate=nil }
    func failFollowingRead() { failNext=true }
    func calendar(from: Date, to: Date) async throws -> CalendarSnapshot { calendarReads += 1;return .init(sources:[],events:[]) }
    func completedReminders(excluded: Set<String>, now: Date) async throws -> [CompletedReminder] { [] }
}

enum NativeReconciliationEvaluation {
    @MainActor static func run() async throws -> [String: Bool] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") else { throw IntegrationError.verification }
        let reader=ReconciliationReader(),model=DashboardModel(nativeSources:reader)
        var checks:[String:Bool]=[:]
        let initial=Task { await model.refreshReminders() }
        await reader.waitForFirstRead()
        // A confirmed save must return while the old source read is still suspended.
        try model.reconcileVerifiedNativeWriteFixture(.reminder)
        try model.reconcileVerifiedNativeWriteFixture(.reminder)
        checks["confirmed reminder reconciliation returns before slow collection"] = model.reminderHealth.loading && !model.writing
        await reader.releaseOld()
        await initial.value
        try await model.finishNativeReconciliationFixture()
        checks["overlapping writes coalesce and discard the pre-write snapshot"] = await reader.reads == 2 && model.reminderData.reminders.map(\.id) == ["verified-new"]
        checks["reminder reconciliation never requests Calendar"] = await reader.calendarReads == 0
        await reader.failFollowingRead()
        try model.reconcileVerifiedNativeWriteFixture(.reminder)
        try await model.finishNativeReconciliationFixture()
        checks["failed reconciliation retains verified collection and releases write controls"] = model.reminderHealth.error != nil && model.reminderData.reminders.map(\.id) == ["verified-new"] && !model.writing && model.writeError == nil
        return checks
    }
}
#endif
