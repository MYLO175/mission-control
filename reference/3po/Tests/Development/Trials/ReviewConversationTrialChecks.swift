import Foundation

@main struct ReviewConversationTrialChecks {
    @MainActor static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            precondition(value(), label); checks += 1
        }
        func finish(_ engine:ReviewTrialEngine) { for _ in 0..<80 {engine.tick()} }
        let engine = ReviewTrialEngine(); engine.automatic = false
        engine.startHeartbeat()
        check(engine.submit("yes"),"An explicit reply is accepted during heartbeat")
        check(engine.queuedCount == 1 && engine.activeJobID == nil,"Heartbeat retains exclusive execution")
        check(engine.projectTasks.isEmpty && engine.calendarEntries.isEmpty,"Queueing performs no action")
        let id = engine.jobs[0].id
        let captured = engine.jobs[0].actions
        engine.selection = ["report-task"]
        check(engine.jobs[0].actions == captured,"Accepted actions retain their exact snapshot")
        engine.selection = Set(captured.map(\.id))
        check(!engine.submit("yes please") && engine.jobs.count == 1,"Identical queued plan keeps its operation identity")
        engine.finishHeartbeat()
        check(engine.activeJobID == id && engine.jobs[0].state == .running,"Heartbeat completion starts the queued job once")
        finish(engine)
        check(engine.jobs[0].state == .succeeded && engine.jobs[0].savedCount == 9,"Success requires every action outcome")
        check(engine.projectTasks.count == 4 && engine.calendarEntries.count == 5,"Multiple project and Calendar actions complete")
        check(engine.projectTasks.first?.date == "No deadline assigned","No preparation deadline is invented")
        check(engine.calendarEntries.filter(\.provisional).count == 2,"Unallocated presentation windows remain provisional")
        check(engine.messages.filter(\.human).count == 2,"Human replies remain in the Review conversation")
        check(engine.submit("yes"),"Repeated explicit approval can be checked against existing entries")
        finish(engine)
        check(engine.projectTasks.count == 4 && engine.calendarEntries.count == 5,"Repeated approval cannot duplicate entries")

        engine.reset(); engine.automatic = false
        check(!engine.submit("project tasks only"),"A variation adjusts the plan without granting approval")
        check(engine.selectedActions.count == 4 && engine.jobs.isEmpty,"Variation selects project actions only")
        check(engine.submit("👍"),"An unambiguous acknowledgement approves the displayed plan")
        finish(engine)
        check(engine.calendarEntries.isEmpty && engine.projectTasks.count == 4,"Project-only choice retains destinations")
        engine.reset()
        check(!engine.submit("leave November out") && engine.selectedActions.count == 6,"November exclusion updates all related actions")
        check(!engine.submit("What are these?") && engine.jobs.isEmpty,"An unsupported scripted reply never authorises actions")

        engine.reset(); engine.automatic = false; engine.injectUncertainSave = true
        _ = engine.submit("yes"); finish(engine)
        check(engine.jobs[0].state == .partial && engine.jobs[0].savedCount == 8,"Unconfirmed save cannot produce full success")
        check(engine.attention != nil && engine.paused,"Partial outcome remains visible and pauses queue")
        let uncertain = engine.jobs[0].actions.first {engine.jobs[0].outcomes[$0.id] == .uncertain}!
        let entries = engine.calendarEntries.count
        check(!engine.submit("yes") && engine.jobs.count == 1,"An uncertain operation cannot be resubmitted")
        engine.checkUncertain(engine.jobs[0].id,actionID:uncertain.id)
        check(engine.jobs[0].state == .succeeded && engine.calendarEntries.count == entries,"Readback resolves the original operation without repeating its save")

        engine.reset(); engine.automatic = false; engine.startHeartbeat(); _ = engine.submit("yes")
        engine.stop(); finish(engine)
        check(engine.queuedCount == 1 && engine.projectTasks.isEmpty,"Stop pauses queued work without replay")
        engine.continueQueue(); engine.tick(); engine.tick(); engine.stop()
        check(engine.jobs[0].state == .stopped && engine.jobs[0].savedCount == 1,"Stop retains completed receipts")

        engine.reset();engine.automatic = false;engine.startHeartbeat();_ = engine.submit("yes")
        engine.changeOwner();engine.continueQueue()
        check(engine.jobs[0].state == .failed && engine.projectTasks.isEmpty,"Changed account rejects the captured job without retargeting")

        engine.reset();engine.automatic = false;engine.injectUncertainSave = true;engine.startHeartbeat()
        _ = engine.submit("yes");_ = engine.submit("calendar only");_ = engine.submit("yes")
        engine.finishHeartbeat();finish(engine)
        check(engine.jobs[0].state == .partial && engine.jobs[1].state == .queued,"An overlapping request waits after an uncertain save")
        engine.continueQueue();finish(engine)
        check(engine.jobs[1].state == .queued && engine.paused,"Continue cannot bypass the earlier unconfirmed receipt")
        let original=engine.jobs[0]
        let overlap=original.actions.first {original.outcomes[$0.id] == .uncertain}!
        engine.checkUncertain(original.id,actionID:overlap.id);engine.continueQueue();finish(engine)
        check(engine.jobs[1].state == .succeeded && engine.calendarEntries.count == 5,"Verified original readback releases the overlapping plan without duplicates")

        engine.reset();engine.automatic = false;engine.injectUncertainSave = true;_ = engine.submit("yes")
        for _ in 0..<10 {engine.tick()};engine.stop()
        let stopped=engine.jobs[0];let unresolved=stopped.actions.first {stopped.outcomes[$0.id] == .uncertain}!
        engine.checkUncertain(stopped.id,actionID:unresolved.id)
        check(engine.jobs[0].state == .stopped && engine.jobs[0].savedCount == 5,"Readback of one save cannot complete a stopped unfinished plan")

        engine.reset();engine.automatic = false;_ = engine.submit("yes");finish(engine)
        engine.changeOwner()
        check(engine.projectTasks.isEmpty && engine.calendarEntries.isEmpty && engine.visibleJobs.isEmpty,"Another account cannot inherit entries or outcomes")
        _ = engine.submit("yes");finish(engine)
        check(engine.projectTasks.count == 4 && engine.calendarEntries.count == 5 && engine.visibleJobs.count == 1,"New account approval uses its own entries and receipts")
        engine.reset();engine.automatic = false;engine.injectUncertainSave = true;_ = engine.submit("yes");finish(engine);engine.changeOwner()
        check(engine.submit("yes"),"Another account is not blocked by old-owner uncertainty")
        finish(engine)
        check(engine.visibleJobs[0].state == .succeeded && engine.attention == nil,"Another account cannot inherit old failure attention")

        check(EvaluationLaunchGuard.decision(arguments:["demo","--preview-review-conversation"],isDebug:true) == .proceed,"DEBUG trial mode is registered")
        if case .exit(code:64,output:_) = EvaluationLaunchGuard.decision(arguments:["demo","--preview-review-conversation"],isDebug:false) {checks += 1} else {preconditionFailure("Release trial cannot enter personal startup")}
        print("Review conversation trial: \(checks)/\(checks) source-free checks passed")
    }
}
