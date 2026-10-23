import Foundation

// A total wall-clock bound also covers streams that keep sending heartbeats.
// Each request owns its session; stopping one never invalidates sign-in/model calls.
final class InferenceDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var expired = false
    private var timer: Task<Void,Never>?
    var didExpire: Bool { lock.withLock { expired } }
    init(session: URLSession, seconds: Double = 180) {
        timer = Task.detached { [weak self] in
            do { try await Task.sleep(for:.seconds(seconds)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            let shouldCancel = self.lock.withLock { () -> Bool in
                guard !self.finished else { return false }
                self.expired = true; return true
            }
            if shouldCancel { session.invalidateAndCancel() }
        }
    }
    func stop() { lock.withLock { finished = true }; timer?.cancel() }
    deinit { timer?.cancel() }
}
