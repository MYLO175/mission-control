import Foundation
import SwiftData

/// Exercise the actual shared allowance and actual claim ordering, using only
/// fictional records in private temporary stores. No service/source startup.
@main struct LearningBudgetChecks {
    @MainActor static func main() throws {
        enum Injected: Error { case failed }
        var assertions = 0
        func check(_ value: Bool, _ reason: String) {
            assertions += 1
            precondition(value, reason)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3po-budget-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func open(_ name: String) throws -> ModelContainer {
            try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(
                url: directory.appendingPathComponent(name + ".store"), cloudKitDatabase: .none))
        }
        func progress(_ records: LocalRecordRepository, account: String) throws -> LearningBudgetProgress? {
            let values: [String: LearningBudgetProgress]? = try records.decode("paCombinedLearningBudget")
            return values?[account]
        }
        let calendar = Calendar.current
        let anchor = calendar.date(from: DateComponents(year: 2032, month: 4, day: 10, hour: 10))!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: anchor)!

        // Shared limits apply across lanes, while accounts have their own state.
        let container = try open("limits"), records = LocalRecordRepository(container: container)
        let budget = LearningBudget(container: container)
        check(budget.receipts("alpha").isEmpty, "A new account must not inherit another lane's receipt")
        check(!budget.claim("", manual: false, now: anchor, lane: .conversation), "Empty identity must refuse automatic work")
        check(!budget.claim("", manual: true, now: anchor), "Empty identity must refuse manual work")
        let lanes = LearningLane.allCases
        for (index, lane) in lanes.prefix(4).enumerated() {
            let now = anchor.addingTimeInterval(Double(index) * 1800)
            let oldRevision = budget.revision
            check(budget.claim("alpha", manual: false, now: now, lane: lane), "A valid shared slot must persist")
            let saved = try progress(records, account: "alpha")!
            check(saved.attempts == index + 1, "All lanes must increment the same persisted allowance")
            check(saved.day == BriefingRules.day(now) && saved.lastAttempt == now, "The persisted claim must retain its exact day and time")
            check(saved.lastServed?[lane.rawValue] == now && budget.receipts("alpha")[lane] == now, "Persisted and in-memory lane receipts must match")
            check(budget.receipts("alpha").count == index + 1, "Only a successful lane claim creates a receipt")
            check(budget.revision != oldRevision, "Successful persistence must publish a new revision")
            let bytes = try records.read("paCombinedLearningBudget"), receipts = budget.receipts("alpha"), revision = budget.revision
            check(!budget.claim("alpha", manual: false, now: now.addingTimeInterval(1799), lane: .maintenance), "The shared cooldown must reject one second before thirty minutes")
            check(try records.read("paCombinedLearningBudget") == bytes, "Cooldown refusal must not change stored allowance")
            check(budget.receipts("alpha") == receipts && budget.revision == revision, "Cooldown refusal cannot advance fairness or revision")
            check(budget.claim("alpha", manual: true, now: now.addingTimeInterval(1), lane: .maintenance), "Manual work keeps its independent allowance")
            check(try records.read("paCombinedLearningBudget") == bytes, "Manual work must not consume or renew automatic state")
            check(budget.receipts("alpha") == receipts && budget.revision == revision, "Manual work cannot change automatic lane order")
        }
        let fullBytes = try records.read("paCombinedLearningBudget")
        check(!budget.claim("alpha", manual: false, now: anchor.addingTimeInterval(7200), lane: .maintenance), "The fifth lane must respect the four shared daily slots")
        check(try records.read("paCombinedLearningBudget") == fullBytes, "Daily refusal must preserve the persisted record")
        check(budget.claim("beta", manual: false, now: anchor, lane: .maintenance), "Another account has independent allowance and cooldown")
        check(try progress(records, account: "alpha")?.attempts == 4, "Another account must preserve alpha's spent allowance")
        check(budget.receipts("beta") == [.maintenance: anchor], "Another account receives only its own lane receipt")
        check(budget.receipts("alpha")[.maintenance] == nil, "An account switch must not leak receipts")
        let reopened = LearningBudget(container: try open("limits"))
        check(reopened.receipts("alpha") == budget.receipts("alpha") && reopened.receipts("beta") == budget.receipts("beta"), "Lane and account identities must survive store reopen")
        check(!reopened.claim("alpha", manual: false, now: anchor.addingTimeInterval(9000)), "The spent allowance must survive reopen")
        check(reopened.claim("alpha", manual: false, now: nextDay, lane: .maintenance), "A later local day can claim a new allowance")
        let nextProgress = try progress(records, account: "alpha")!
        check(nextProgress.attempts == 1 && nextProgress.day == BriefingRules.day(nextDay), "Day rollover resets count only after a successful claim")
        check(nextProgress.lastServed?.count == 5, "Day rollover preserves older lane waiting-time identities")
        check(reopened.receipts("alpha")[.conversation] == anchor, "Day rollover must not artificially renew another lane")

        // Crossing midnight resets quota but cannot bypass the existing cooldown.
        let midnightContainer = try open("midnight"), midnight = LearningBudget(container: midnightContainer)
        let late = calendar.date(bySettingHour: 23, minute: 50, second: 0, of: anchor)!
        let early = late.addingTimeInterval(900)
        check(BriefingRules.day(late) != BriefingRules.day(early), "Fixture must actually cross the local day")
        check(midnight.claim("night", manual: false, now: late, lane: .conversation), "Late-day first claim must persist")
        let midnightRecords = LocalRecordRepository(container: midnightContainer), nightBytes = try midnightRecords.read("paCombinedLearningBudget")
        check(!midnight.claim("night", manual: false, now: early, lane: .nativeSources), "Day rollover cannot erase a fifteen-minute cooldown")
        check(try midnightRecords.read("paCombinedLearningBudget") == nightBytes, "Rejected rollover cannot change the prior due anchor")
        check(midnight.claim("night", manual: false, now: late.addingTimeInterval(1800), lane: .nativeSources), "The exact cooldown boundary after midnight must be accepted")
        check(try progress(midnightRecords, account: "night")?.attempts == 1, "Accepted next-day claim starts at one")

        // Failure after pending changes were prepared must not publish a claim,
        // save another owner, or become durable through an unrelated later save.
        let failureContainer = try open("failure"), failureRecords = LocalRecordRepository(container: failureContainer)
        var failCommit = false
        let injected = LocalRecordRepository(container: failureContainer) { _ in if failCommit { throw Injected.failed } }
        let failingBudget = LearningBudget(container: failureContainer, repository: injected)
        check(failingBudget.claim("failure-account", manual: false, now: anchor, lane: .conversation), "Failure fixture must start with a real persisted claim")
        let beforeBytes = try failureRecords.read("paCombinedLearningBudget"), beforeReceipts = failingBudget.receipts("failure-account"), beforeRevision = failingBudget.revision
        let other = CachedDashboard(key: "unrelated-owner", data: Data("pending fiction".utf8))
        failureContainer.mainContext.insert(other)
        failCommit = true
        let failedTime = anchor.addingTimeInterval(1800)
        check(!failingBudget.claim("failure-account", manual: false, now: failedTime, lane: .nativeSources), "An injected commit failure must reject a prepared claim")
        check(failingBudget.receipts("failure-account") == beforeReceipts, "Failure must restore all prior lane receipts")
        check(failingBudget.revision == beforeRevision, "Failure must not publish a successful revision")
        check(try failureRecords.read("paCombinedLearningBudget") == beforeBytes, "Failure cannot advance durable attempt count or time")
        check(failureContainer.mainContext.hasChanges, "Failure cannot discard another owner's unsaved work")
        check(try failureRecords.read("unrelated-owner") == nil, "The failed claim cannot commit another owner")
        try failureContainer.mainContext.save()
        try failureRecords.write(["later-save": Data("unrelated fiction".utf8)])
        let failureReopen = LearningBudget(container: try open("failure"))
        check(failureReopen.receipts("failure-account") == beforeReceipts, "A later save and reopen cannot resurrect failed fairness receipts")
        check(try progress(failureRecords, account: "failure-account")?.attempts == 1, "A later save cannot resurrect failed allowance consumption")
        failCommit = false
        check(failingBudget.claim("failure-account", manual: false, now: failedTime, lane: .nativeSources), "Failed persistence must not impose a phantom cooldown")
        check(failingBudget.receipts("failure-account")[.nativeSources] == failedTime, "Only the eventual successful claim may renew that lane")
        check(try progress(failureRecords, account: "failure-account")?.attempts == 2, "Recovery must spend exactly one more slot")

        let emptyFailureContainer = try open("empty-failure")
        let alwaysFail = LocalRecordRepository(container: emptyFailureContainer) { _ in throw Injected.failed }
        let emptyFailureBudget = LearningBudget(container: emptyFailureContainer, repository: alwaysFail)
        let emptyRevision = emptyFailureBudget.revision
        check(!emptyFailureBudget.claim("new-failure", manual: false, now: anchor, lane: .conversation), "A new-account commit failure must refuse the first slot")
        check(emptyFailureBudget.receipts("new-failure").isEmpty && emptyFailureBudget.revision == emptyRevision, "First-save failure cannot introduce account receipts or a revision")
        check(try LocalRecordRepository(container: emptyFailureContainer).read("paCombinedLearningBudget") == nil, "First-save failure cannot leave a durable budget row")
        let failedCoordinator = BackgroundLearningCoordinator()
        let noResult = failedCoordinator.check(now: anchor, receipts: emptyFailureBudget.receipts("new-failure"), available: { true }) { lane, now in
            lane == .conversation && emptyFailureBudget.claim("new-failure", manual: false, now: now, lane: lane)
        }
        check(noResult == nil && emptyFailureBudget.receipts("new-failure").isEmpty, "A coordinator must not treat a failed persistent claim as service progress")

        // Real persisted receipts, not a parallel fake budget, drive fairness
        // over three days. Each attempt reloads the actual saved account state.
        let fairContainer = try open("fair"), fairRecords = LocalRecordRepository(container: fairContainer)
        let coordinator = BackgroundLearningCoordinator()
        var served: [LearningLane] = []
        for day in 0..<3 {
            let start = calendar.date(byAdding: .day, value: day, to: anchor)!
            for slot in 0..<4 {
                let now = start.addingTimeInterval(Double(slot) * 1800)
                let current = LearningBudget(container: try open("fair"))
                let selected = coordinator.check(now: now, receipts: current.receipts("fair-account"), available: { true }) { lane, clock in
                    current.claim("fair-account", manual: false, now: clock, lane: lane)
                }
                check(selected == lanes[served.count % lanes.count], "Persisted receipts must choose the longest-waiting lane after reopening")
                served.append(selected!)
                check(try progress(fairRecords, account: "fair-account")?.attempts == slot + 1, "Fair scheduling must use the real persisted shared daily allowance")
                let bytes = try fairRecords.read("paCombinedLearningBudget"), receipts = current.receipts("fair-account")
                let blocked = coordinator.check(now: now.addingTimeInterval(1), receipts: receipts, available: { true }) { lane, clock in
                    current.claim("fair-account", manual: false, now: clock, lane: lane)
                }
                check(blocked == nil && current.receipts("fair-account") == receipts, "Cooldown-blocked polling cannot change persisted lane order")
                check(try fairRecords.read("paCombinedLearningBudget") == bytes, "Cooldown-blocked polling cannot save a different budget")
            }
            let current = LearningBudget(container: try open("fair"))
            let blocked = coordinator.check(now: start.addingTimeInterval(7200), receipts: current.receipts("fair-account"), available: { true }) { lane, clock in
                current.claim("fair-account", manual: false, now: clock, lane: lane)
            }
            check(blocked == nil, "The real fifth daily coordinator opportunity must respect shared allowance")
        }
        check(served.count == 12, "Three days must yield only twelve automatic slots")
        for index in 0...(served.count - lanes.count) {
            check(Set(served[index..<(index + lanes.count)]) == Set(lanes), "Every five persisted claims must serve all continuously eligible lanes")
        }
        let finalFair = LearningBudget(container: try open("fair"))
        check(finalFair.receipts("fair-account").keys.count == lanes.count, "The complete fair rotation must survive final reopen")

        // Legacy records, unknown future lane metadata and corrupt state retain
        // their identities rather than being quietly rewritten during reads.
        let legacyContainer = try open("legacy"), legacyRecords = LocalRecordRepository(container: legacyContainer)
        var old = LearningBudgetProgress(); old.day = BriefingRules.day(anchor); old.attempts = 1; old.lastAttempt = anchor
        var future = old; future.lastServed = ["future-lane": anchor.addingTimeInterval(-7200), LearningLane.whatsapp.rawValue: anchor]
        let legacyBytes = try JSONEncoder().encode(["legacy": old, "future": future])
        try legacyRecords.write(["paCombinedLearningBudget": legacyBytes, "unknown-record": Data([1,2,3])])
        let legacy = LearningBudget(container: legacyContainer)
        check(legacy.receipts("legacy").isEmpty, "Legacy allowance without per-lane receipts must decode")
        check(legacy.receipts("future") == [.whatsapp: anchor], "Unknown lane metadata must not become an invented current lane")
        check(try legacyRecords.read("paCombinedLearningBudget") == legacyBytes, "Reading legacy receipts cannot rewrite saved data")
        check(legacy.claim("future", manual: false, now: anchor.addingTimeInterval(1800), lane: .nativeSources), "Known lane can claim beside future compatibility metadata")
        check(try progress(legacyRecords, account: "future")?.lastServed?["future-lane"] == future.lastServed?["future-lane"], "Known claims must preserve unknown lane metadata")
        check(try progress(legacyRecords, account: "legacy")?.attempts == old.attempts, "Known claims preserve other legacy accounts")
        check(try legacyRecords.read("unknown-record") == Data([1,2,3]), "Budget writes cannot change other cached records")
        let corruptContainer = try open("corrupt"), corruptRecords = LocalRecordRepository(container: corruptContainer)
        let corrupt = Data("not a budget".utf8)
        try corruptRecords.write(["paCombinedLearningBudget": corrupt])
        let unreadable = LearningBudget(container: corruptContainer)
        check(!unreadable.claim("corrupt", manual: false, now: anchor, lane: .conversation), "Corrupt automatic state must fail closed")
        check(!unreadable.claim("corrupt", manual: true, now: anchor), "Manual independence must not erase an unreadable record")
        check(try corruptRecords.read("paCombinedLearningBudget") == corrupt, "Corrupt state must remain available for recovery")
        let unavailable = LearningBudget(container: nil)
        check(!unavailable.claim("missing", manual: false, now: anchor, lane: .conversation), "Missing storage must refuse an automatic durable claim")
        check(unavailable.claim("missing", manual: true, now: anchor), "Existing manual admission remains independent of automatic storage")
        check(unavailable.receipts("missing").isEmpty, "Manual admission without storage cannot create a receipt")
        print("PASS \(assertions) actual learning-budget checks: persisted lane receipts, four/day and exact shared cooldown, manual independence, account/day reopen, commit failure/later saves, real three-day fair rotation and legacy/corrupt-state preservation. Fictional private stores only; no sources, model, native writes or settings changes.")
    }
}
