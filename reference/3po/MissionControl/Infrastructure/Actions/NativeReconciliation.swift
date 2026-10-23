import Foundation

/// Ownership of a collected snapshot, including writes not yet announced by EventKit.
struct NativeCollectionScope: Equatable {
    var registration: String
    var sourceRevision: Int
    var writeGeneration: Int
    var storage: ObjectIdentifier?
}

enum NativeReconciliationKind: Hashable { case calendar, reminders }

/// A confirmed save ends before collection. Coalesce later writes while a read is in flight.
@MainActor final class NativeReconciliation {
    private var pending: [NativeReconciliationKind: @MainActor () async -> Void] = [:]
    private var task: Task<Void, Never>?
    func waitForPending() async { await task?.value }
    func schedule(_ kind: NativeReconciliationKind, refresh: @escaping @MainActor (NativeReconciliationKind) async -> Void) {
        pending[kind] = { await refresh(kind) }
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !self.pending.isEmpty {
                let next: NativeReconciliationKind = self.pending[.reminders] != nil ? .reminders : .calendar
                let operation = self.pending.removeValue(forKey:next)
                await operation?()
            }
            self.task = nil
        }
    }
}
