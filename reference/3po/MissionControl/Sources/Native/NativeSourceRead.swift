import Foundation

/// Read-only native context boundary. Writing remains on the guarded EventKit APIs.
protocol NativeSourceReading {
    func calendar(from start: Date, to end: Date) async throws -> CalendarSnapshot
    func reminders() async throws -> ReminderSnapshot
    func completedReminders(excluded: Set<String>, now: Date) async throws -> [CompletedReminder]
}

extension NativeSourceReading {
    func completedReminders(excluded: Set<String>) async throws -> [CompletedReminder] {
        try await completedReminders(excluded: excluded, now: .now)
    }
}

enum NativeSourceReadError: LocalizedError {
    case unavailable(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let source):
            return "\(source) did not return a result. Refresh to try again."
        case .timedOut(let source):
            return "\(source) did not respond in time. Refresh to try again."
        }
    }
}

enum NativeSourceRead {
    /// EventKit supplies nil for an unavailable result, whereas an empty array is
    /// a successful read. Keep that distinction before building any snapshot.
    static func requireSnapshot<Snapshot>(_ value: Snapshot?, source: String) throws -> Snapshot {
        guard let value else { throw NativeSourceReadError.unavailable(source) }
        return value
    }

    static func fetchSnapshot<Snapshot>(source: String, timeout: TimeInterval = 45, fetch: (@escaping (Snapshot?) -> Void) -> Void) async throws -> Snapshot {
        try await fetchCancellableSnapshot(source: source, timeout: timeout, fetch: { completion in
            fetch(completion)
            return nil
        })
    }

    static func fetchCancellableSnapshot<Snapshot>(source: String, timeout: TimeInterval = 45, fetch: (@escaping (Snapshot?) -> Void) -> (() -> Void)?) async throws -> Snapshot {
        try Task.checkCancellation()
        let request = NativeReadRequest<Snapshot>()
        let value: Snapshot = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                request.install(continuation)
                request.deadline(after: timeout, source: source)
                let cancel = fetch { result in
                    request.finish(Result { try requireSnapshot(result, source: source) })
                }
                request.installCancellation(cancel)
            }
        } onCancel: {
            request.finish(.failure(CancellationError()), cancelProvider: true)
        }
        try Task.checkCancellation()
        return value
    }
}

/// EventKit suppresses its callback when cancelled. Resume our waiter ourselves,
/// and arbitrate callback, cancellation and deadline under one lock.
private final class NativeReadRequest<Snapshot>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Snapshot, Error>?
    private var result: Result<Snapshot, Error>?
    private var cancel: (() -> Void)?
    private var cancelledProvider = false
    private var timer: DispatchSourceTimer?

    func install(_ continuation: CheckedContinuation<Snapshot, Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func installCancellation(_ cancel: (() -> Void)?) {
        lock.lock()
        if result == nil { self.cancel = cancel; lock.unlock() }
        else { let shouldCancel = cancelledProvider; lock.unlock(); if shouldCancel { cancel?() } }
    }
    func deadline(after timeout: TimeInterval, source: String) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + max(0.001, timeout.isFinite ? timeout : 45))
        timer.setEventHandler { [weak self] in self?.finish(.failure(NativeSourceReadError.timedOut(source)), cancelProvider: true) }
        lock.lock()
        if result == nil { self.timer = timer; lock.unlock(); timer.resume() }
        else { lock.unlock(); timer.resume(); timer.cancel() }
    }
    func finish(_ result: Result<Snapshot, Error>, cancelProvider: Bool = false) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result; cancelledProvider = cancelProvider
        let continuation = continuation, cancel = cancelProvider ? cancel : nil, timer = timer
        self.continuation = nil; self.cancel = nil; self.timer = nil
        lock.unlock()
        timer?.cancel(); cancel?(); continuation?.resume(with: result)
    }
}

/// A refresh replaces data only after a successful read. Consumers retain the
/// cached snapshot on failure, while health prevents it being used as fresh evidence.
struct NativeSourceCollection<Snapshot> {
    var snapshot: Snapshot
    var health: SourceHealth

    func collecting(read: () async throws -> Snapshot, now: () -> Date = { .now }) async -> Self {
        var updated = self
        do {
            try Task.checkCancellation()
            let value = try await read()
            try Task.checkCancellation()
            updated.snapshot = value
            updated.health = .init(lastSuccess: now())
        } catch {
            updated.health.loading = false
            updated.health.error = error is CancellationError ? "Refresh cancelled; previous data is retained." : error.localizedDescription
        }
        return updated
    }
}
