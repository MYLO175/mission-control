import Foundation

/// Fictional synchronous services emulate permitted claims only. No real model,
/// source, storage, clock, user preferences or background service is constructed.
@MainActor private final class FictionalLearningServices {
    var receipts: [LearningLane: Date] = [:]
    var eligible = Set(LearningLane.allCases)
    var paused: Set<LearningLane> = []
    var persistenceAvailable = true
    var attempts: [LearningLane] = []
    var claims: [(lane: LearningLane, date: Date)] = []
    private var slots: [Int: Int] = [:]
    private let anchor: Date

    init(anchor: Date) { self.anchor = anchor }

    func attempt(_ lane: LearningLane, now: Date) -> Bool {
        attempts.append(lane)
        guard eligible.contains(lane), !paused.contains(lane), persistenceAvailable, !Task.isCancelled else { return false }
        let day = Int(floor(now.timeIntervalSince(anchor) / 86400))
        guard slots[day, default: 0] < 4,
              claims.last.map({ now.timeIntervalSince($0.date) >= 1800 }) ?? true else { return false }
        slots[day, default: 0] += 1
        claims.append((lane, now))
        receipts[lane] = now
        return true
    }
}

@main struct BackgroundLearningChecks {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            checks += 1
        }
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let coordinator = BackgroundLearningCoordinator()
        let all = LearningLane.allCases

        check(BackgroundLearningPolicy.orderedLanes(receipts: [:], now: anchor) == all, "Unclaimed lanes must use a stable order.")
        let mixed: [LearningLane: Date] = [.conversation: anchor, .nativeSources: anchor.addingTimeInterval(-3600), .whatsapp: anchor, .maintenance: anchor.addingTimeInterval(3600)]
        check(BackgroundLearningPolicy.orderedLanes(receipts: mixed, now: anchor) == [.organisation, .nativeSources, .conversation, .whatsapp, .maintenance], "Missing receipts go first, ties are stable, and a future receipt stays newest.")
        let encoded = try JSONEncoder().encode(mixed)
        check(try JSONDecoder().decode([LearningLane: Date].self, from: encoded) == mixed, "Lane claim identities and times must survive Codable storage.")

        let busy = FictionalLearningServices(anchor: anchor)
        var returned: [LearningLane] = []
        for day in 0..<3 {
            for slot in 0..<8 {
                let now = anchor.addingTimeInterval(Double(day * 86400 + slot * 1800))
                let before = busy.claims.count
                if let claimed = coordinator.check(now: now, receipts: busy.receipts, available: { true }, attempt: { busy.attempt($0, now: $1) }) {
                    returned.append(claimed)
                }
                check(busy.claims.count - before <= 1, "A polling check may claim at most one service.")
                if slot < 4 {
                    let beforeReceipts = busy.receipts
                    let tooSoon = coordinator.check(now: now.addingTimeInterval(1799), receipts: busy.receipts, available: { true }, attempt: { busy.attempt($0, now: $1) })
                    check(tooSoon == nil && busy.receipts == beforeReceipts, "Cooldown-blocked checks must not advance lane receipts.")
                }
            }
        }
        check(busy.claims.count == 12 && returned == busy.claims.map(\.lane), "Three days must retain the fictional four-slot daily limit.")
        check(Set(busy.claims.prefix(5).map(\.lane)) == Set(all), "Every continuously eligible lane must receive a slot within five claims.")
        for first in 0...(busy.claims.count - all.count) {
            check(Set(busy.claims[first..<(first + all.count)].map(\.lane)) == Set(all), "Continuously eligible lanes must rotate fairly over every five successful claims.")
        }
        check(zip(busy.claims, busy.claims.dropFirst()).allSatisfy { $1.date.timeIntervalSince($0.date) >= 1800 }, "Claims must remain at least thirty minutes apart.")

        let idle = FictionalLearningServices(anchor: anchor)
        idle.eligible = [.nativeSources, .whatsapp]
        idle.paused = [.whatsapp]
        let idleResult = coordinator.check(now: anchor, receipts: idle.receipts, available: { true }, attempt: { idle.attempt($0, now: $1) })
        check(idleResult == .nativeSources && idle.attempts == [.conversation, .nativeSources], "An idle lane must not delay other ready work.")
        check(idle.receipts[.conversation] == nil && idle.receipts[.whatsapp] == nil, "Idle and paused lanes cannot claim a slot.")
        check(idle.claims.count == 1, "The first actual claim must stop further service checks.")

        idle.paused = [.nativeSources, .whatsapp]
        let previous = idle.receipts
        let noneReady = coordinator.check(now: anchor.addingTimeInterval(1800), receipts: idle.receipts, available: { true }, attempt: { idle.attempt($0, now: $1) })
        check(noneReady == nil && idle.receipts == previous && idle.claims.count == 1, "Paused or ineligible work must preserve its receipts and allowance.")

        let failedSave = FictionalLearningServices(anchor: anchor)
        failedSave.persistenceAvailable = false
        check(coordinator.check(now: anchor, receipts: [:], available: { true }, attempt: { failedSave.attempt($0, now: $1) }) == nil && failedSave.claims.isEmpty && failedSave.receipts.isEmpty, "A failed claim save must not count as a claimed slot.")

        for reason in ["foreground", "sleep", "account changed"] {
            var foreground = false
            var sleeping = false
            var account = "captured-fictional-account"
            let capturedAccount = account
            var tried: [LearningLane] = []
            var guardReads = 0
            let result = coordinator.check(now: anchor, receipts: [:], available: {
                guardReads += 1
                return !foreground && !sleeping && account == capturedAccount
            }, attempt: { lane, _ in
                tried.append(lane)
                switch reason {
                case "foreground": foreground = true
                case "sleep": sleeping = true
                default: account = "another-fictional-account"
                }
                return false
            })
            check(result == nil && tried == [.conversation] && guardReads == 2, "Availability must be rechecked between attempts when \(reason) changes.")
        }
        var blockedAttempts = 0
        check(coordinator.check(now: anchor, receipts: [:], available: { false }, attempt: { _, _ in blockedAttempts += 1; return true }) == nil && blockedAttempts == 0, "A blocked owner must not touch any service.")

        let cancelledServices = FictionalLearningServices(anchor: anchor)
        let cancelled = Task { @MainActor in
            coordinator.check(now: anchor, receipts: [:], available: { true }, attempt: { lane, now in
                withUnsafeCurrentTask { $0?.cancel() }
                return cancelledServices.attempt(lane, now: now)
            })
        }
        check(await cancelled.value == nil && cancelledServices.claims.isEmpty && cancelledServices.attempts == [.conversation], "Cancellation before claim must not count a slot or try a later service.")

        var innerAttempted = false
        let recursive = coordinator.check(now: anchor, receipts: [:], available: { true }, attempt: { _, _ in
            let nested = coordinator.check(now: anchor, receipts: [:], available: { true }, attempt: { _, _ in innerAttempted = true; return true })
            check(nested == nil, "One scheduling check must not reenter another check.")
            return true
        })
        check(recursive == .conversation && !innerAttempted, "Nested checks must not claim a second slot.")

        print("PASS \(checks) background learning assertions: fair five-lane claims, three fictional days, limits/cooldown, idle/paused work, failed persistence, availability, cancellation and serial checks; no sources or inference.")
    }
}
