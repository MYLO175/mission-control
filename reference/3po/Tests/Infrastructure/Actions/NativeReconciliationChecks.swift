import Foundation

@main struct NativeReconciliationChecks {
    @MainActor static func main() async {
        let worker=NativeReconciliation()
        var reads=0,calendarReads=0,finished=false
        var gate:CheckedContinuation<Void,Never>?
        var receipt="confirmed"
        worker.schedule(.reminders) { kind in
            reads += 1
            await withCheckedContinuation { gate=$0 }
            // A source outage is handled as source health, never a failed native save.
            finished=true
        }
        precondition(reads == 0 && receipt == "confirmed", "Scheduling must release the confirmed save synchronously")
        while gate == nil { await Task.yield() }
        worker.schedule(.reminders) { _ in reads += 100 }
        worker.schedule(.reminders) { _ in reads += 1 }
        worker.schedule(.calendar) { _ in calendarReads += 1 }
        precondition(reads == 1 && !finished, "A slow source must not run a second overlapping collection")
        gate?.resume();gate=nil
        while calendarReads == 0 { await Task.yield() }
        precondition(reads == 2 && calendarReads == 1 && receipt == "confirmed", "Pending writes must coalesce to the latest collection without altering the receipt")
        let storage=NSObject(),otherStorage=NSObject()
        let old=NativeCollectionScope(registration:"one",sourceRevision:1,writeGeneration:1,storage:ObjectIdentifier(storage))
        precondition(old != .init(registration:"one",sourceRevision:1,writeGeneration:2,storage:ObjectIdentifier(storage)), "Late pre-write snapshot must be rejected before EventKit announces the change")
        precondition(old != .init(registration:"two",sourceRevision:1,writeGeneration:1,storage:ObjectIdentifier(storage)), "An account switch must reject an old collection")
        precondition(old != .init(registration:"one",sourceRevision:2,writeGeneration:1,storage:ObjectIdentifier(storage)), "Changed source controls must reject old collection")
        precondition(old != .init(registration:"one",sourceRevision:1,writeGeneration:1,storage:ObjectIdentifier(otherStorage)), "Changed storage must reject old collection")
        receipt="verified"
        print("Native reconciliation: 7 checks passed")
    }
}
