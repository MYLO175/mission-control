import Foundation

/// Stable storage identities for users of the existing combined learning allowance.
enum LearningLane: String, CaseIterable, Codable, Hashable, Sendable {
    case conversation
    case nativeSources
    case whatsapp
    case organisation
    case maintenance
}

enum BackgroundLearningPolicy {
    /// Successful persisted slot claims determine waiting time. Checking an idle,
    /// paused or budget-blocked lane must never move it to the back of this order.
    static func orderedLanes(receipts: [LearningLane: Date], now: Date) -> [LearningLane] {
        let lanes = LearningLane.allCases
        return lanes.enumerated().sorted { left, right in
            let l = receipts[left.element].map { now.timeIntervalSince($0) } ?? .infinity
            let r = receipts[right.element].map { now.timeIntervalSince($0) } ?? .infinity
            return l == r ? left.offset < right.offset : l > r
        }.map(\.element)
    }
}

/// Services retain their eligibility, limits, failure pauses and inference work.
/// This coordinator only offers them one serial opportunity in a fair order.
@MainActor final class BackgroundLearningCoordinator {
    private var checking = false

    /// `attempt` returns true only when the shared budget persisted a new claim.
    /// A checked batch, a busy flag or a later inference result is not a receipt.
    @discardableResult
    func check(now: Date, receipts: [LearningLane: Date], available: () -> Bool, attempt: (LearningLane, Date) -> Bool) -> LearningLane? {
        guard !checking else { return nil }
        checking = true
        defer { checking = false }
        for lane in BackgroundLearningPolicy.orderedLanes(receipts: receipts, now: now) {
            // A previous service check can change ownership or start foreground
            // work without claiming this allowance. Check again before each lane.
            guard !Task.isCancelled, available() else { return nil }
            if attempt(lane, now) { return lane }
        }
        return nil
    }
}
