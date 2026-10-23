import Foundation
import CryptoKit
import SwiftData

/// Desktop source projections and existing child workers. The scheduler itself
/// never owns a dashboard, a source collector, a foreground queue or native writes.
@MainActor enum HeartbeatDashboardAdapter {
    static func runtime(_ model:DashboardModel)->HeartbeatRuntime {
        .init(environment:{environment(model)},prepareSources:{request in
            try request.validate()
            let access=model.whatsapp.access(for:request.registration)
            let wants=(request.whatsappEnabled || access.briefEnabled) && access.enabled && !access.chats.isEmpty
            // The helper continuously publishes received messages. Analysis uses
            // that cache and never waits for a new snapshot or reconnect.
            let ready=wants && model.whatsapp.connected && !model.whatsapp.linkedIdentity.isEmpty
            var value=sources(model,whatsappReady:ready)
            value.wantsWhatsApp=wants
            return value
        },currentSources:{sources(model,whatsappReady:$0)},availableMail:{$0.available(index:model.mailIndex,snapshot:model.mailData,excluded:model.assistant.excludedAccounts)},sourceFingerprint:{sourceFingerprint(model,mailReview:$0,whatsappReady:$1,whatsappEnabled:$2)},mailFingerprints:{review in
            Dictionary(uniqueKeysWithValues:review.accountIDs.map{($0,mailFingerprint(model,account:$0))})
        },pending:{pending(model,mailReview:$0,whatsappReady:$1,nativeReady:$2)},activity:{activity(model,registration:$0,runID:$1)},email:{request in
            try request.validate()
            model.emailSummaries.process(model,resume:true,heartbeat:true,mailReview:request.mailReview,heartbeatRequest:request)
            do {while model.emailSummaries.busy {try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))}} catch {await model.emailSummaries.cancelAndWait();throw error}
            return .init(failure:model.emailSummaries.enabled && model.emailSummaries.paused ? model.emailSummaries.error ?? "Email assessment did not finish. Completed summaries are saved." : nil)
        },suggestions:{request in
            try request.validate()
            model.proactive.check(model,manual:request.manual,heartbeat:true,heartbeatWhatsAppReady:request.whatsappReady,mailReview:request.mailReview,heartbeatRequest:request)
            do {while model.proactive.busy {try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))}} catch {await model.proactive.cancelAndWait();throw error}
            return .init(failure:model.proactive.error,nativeUnavailable:model.proactive.sourceReadError != nil,detail:model.proactive.validationNotice(request.registration,runID:request.runID))
        },brief:{request in
            try request.validate()
            model.briefings.check(model,manual:request.manual,heartbeatID:request.runID,mailReview:request.mailReview,whatsappReady:request.whatsappReady,heartbeatRequest:request)
            do {while model.briefings.busy {try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))}} catch {await model.briefings.cancelAndWait();throw error}
            return .init(failure:model.briefings.error)
        },cancelChildren:{
            model.emailSummaries.cancel(includeFeedback:false);model.proactive.cancel();model.briefings.cancel()
            if let runID=model.heartbeat.ownedRunID {model.cancelHeartbeatLearning(runID:runID);model.emailSummaries.cancelHeartbeatFeedback(runID:runID)}
        },feedback:{request in
            try await model.emailSummaries.runHeartbeatFeedback(request,model:model)
        },learning:{request in
            let result=try await model.runHeartbeatLearning(request:request)
            try request.validate()
            let pages = try await populateContextPages(model, request: request)
            try request.validate()
            let failures = [result.failure, pages.failure].compactMap { $0 }
            return .init(failure:failures.isEmpty ? nil : failures.joined(separator:" · "),detail:result.detail + " " + pages.detail,skipped:result.skipped && pages.skipped)
        },started:{model.heartbeatActivityStarted($0,$1,$2)},finished:{model.heartbeatActivityFinished($0,$1)})
    }

    /// An explicit heartbeat finishes the context backlog captured at its start. Each call
    /// remains bounded, owned and charged before inference; new arrivals wait for a later run.
    private static func populateContextPages(_ model: DashboardModel, request: HeartbeatChildRequest) async throws -> HeartbeatLearningResult {
        guard request.manual else { return try await model.contextConsolidation.run(model, request: request) }
        try request.validate()
        let initial = model.contextConsolidation.targets(model, registration: request.registration)
        guard !initial.isEmpty else { return try await model.contextConsolidation.run(model, request: request) }
        let initialCount = initial.count
        let snapshot = ContextPopulationSnapshot(initial: initial, pages: model.contextPages.pages(registration: request.registration))
        func outstanding() -> (targetIDs: Set<String>, workCount: Int) {
            let current = model.contextConsolidation.targets(model, registration: request.registration, eligibleReferences: snapshot.references)
            let records = model.contextKnowledge(registration: request.registration, includeTopics: false, retainingReferences: snapshot.references, purpose: .maintenance)
            return snapshot.remaining(current: current, records: records, pages: model.contextPages.pages(registration: request.registration))
        }
        var batches = 0
        while true {
            try Task.checkCancellation(); try request.validate()
            let pending = outstanding()
            guard !pending.targetIDs.isEmpty else { break }
            let result = try await model.contextConsolidation.run(model, request: request, targetIDs: pending.targetIDs, eligibleReferences: snapshot.references)
            try request.validate()
            if result.failure != nil || result.skipped { return result }
            guard outstanding().workCount < pending.workCount else {
                return .init(failure: "Context population made no progress on its captured input. Completed pages are retained; remaining input waits for a fresh heartbeat.", detail: "Context population stopped without replaying the same batch.", skipped: false)
            }
            batches += 1
            await Task.yield()
        }
        let later = model.contextConsolidation.targets(model, registration: request.registration).count
        return .init(detail: "Context population completed in \(batches) bounded batch\(batches == 1 ? "" : "es"); all \(initialCount) requested pages were considered." + (later == 0 ? " No page updates remain pending." : " \(later) later page updates remain pending."), skipped: batches == 0)
    }

    private static func environment(_ model:DashboardModel)->HeartbeatEnvironment {
        func otherLearning(_ busy:Bool,_ runID:String?)->Bool {busy && !(runID.map{model.heartbeat.ownsLearningRun($0)} ?? false)}
        let learning=otherLearning(model.contextConsolidation.busy,model.contextConsolidation.ownedHeartbeatRunID) || otherLearning(model.sourceLearning.busy,model.sourceLearning.ownedHeartbeatRunID) || otherLearning(model.nativeSourceLearning.busy,model.nativeSourceLearning.ownedHeartbeatRunID) || otherLearning(model.memoryMaintenance.busy,model.memoryMaintenance.ownedHeartbeatRunID) || otherLearning(model.memoryLearning.busy,model.memoryLearning.ownedHeartbeatRunID) || otherLearning(model.lifeOrganisation.busy,model.lifeOrganisation.ownedHeartbeatRunID)
        let feedback=model.emailSummaries.feedback.activeID != nil && !(model.emailSummaries.feedback.ownedHeartbeatRunID.map{model.heartbeat.ownsLearningRun($0)} ?? false)
        let foreground=model.reviewWork.busy || feedback || model.assistant.busy || model.chatGPT.busy || model.projectPlacement.busy || learning
        let proposals=model.proactive.state.accounts[model.chatGPT.activeID]
        let preview=["--sample","--preview-review-inbox","--preview-settings"].contains{ProcessInfo.processInfo.arguments.contains($0)}
        return .init(registration:model.chatGPT.activeID,model:model.chatGPT.selectedModel,sourceSettings:model.proactive.sourceSettingsScope(model),scope:model.proactive.scope(model),whatsappChoices:model.whatsapp.choicesRevision,whatsappIdentity:model.whatsapp.linkedIdentity,contextEnabled:model.assistant.contextEnabled,inferenceVerified:model.chatGPT.inferenceVerified,usagePaused:model.chatGPT.usagePaused,workBusy:foreground || model.writing || model.briefings.busy || model.proactive.busy || model.emailSummaries.busy,foregroundBusy:foreground,permitted:!preview,emailEnabled:model.emailSummaries.enabled,proposalsEnabled:model.proactive.enabled,proposalAllowanceReached:proposals?.day == BriefingRules.day(model.heartbeat.currentTime) && (proposals?.attempts ?? 0) >= 96)
    }
    private static func sources(_ model:DashboardModel,whatsappReady:Bool)->HeartbeatSources {
        let registration=model.chatGPT.activeID,access=model.whatsapp.access(for:registration)
        let accounts=model.mailData.accounts.filter{!model.assistant.excludedAccounts.contains($0.id)}
        return .init(mailReview:.collected(index:model.mailIndex,snapshot:model.mailData,excluded:model.assistant.excludedAccounts),accounts:accounts,enabledMail:Set(accounts.map(\.id)),nativeReady:model.heartbeatNativeReady,wantsWhatsApp:(model.heartbeat.whatsappEnabled || access.briefEnabled) && access.enabled && !access.chats.isEmpty,whatsappReady:whatsappReady)
    }
    private static func pending(_ model:DashboardModel,mailReview:MailReviewScope,whatsappReady:Bool,nativeReady:Bool)->HeartbeatPending {
        let proposals=model.proactive.enabled && model.proactive.hasPendingSources(model,mailReview:mailReview,whatsappReady:whatsappReady)
        let accounts=Set(mailReview.accountIDs.filter{id in
            var one=mailReview;one.windows=one.windows.filter{$0.key == id}
            return model.emailSummaries.hasPendingIncoming(model,mailReview:one) || !nativeReady || (model.proactive.enabled && model.proactive.hasPendingSources(model,mailReview:mailReview,whatsappReady:whatsappReady,mailAccountID:id))
        })
        return .init(any:model.emailSummaries.feedback.items(model.chatGPT.activeID).contains{$0.state == .queued && $0.heartbeatEligible == true} || model.emailSummaries.hasPendingIncoming(model,mailReview:mailReview) || (nativeReady && proposals),mailAccounts:accounts,proposals:proposals || (model.proactive.enabled && environment(model).proposalAllowanceReached))
    }
    private static func activity(_ model:DashboardModel,registration:String,runID:String)->HeartbeatActivity {
        .init(preparedItems:model.proactive.state.records.filter{$0.registration == registration}.count,emailDrafts:model.emailSummaries.records.filter{$0.registration == registration && $0.replyDraft != nil}.count,whatsappDrafts:model.proactive.state.records.filter{$0.registration == registration && $0.replyDraft != nil}.count,handled:model.emailSummaries.records.filter{$0.registration == registration && $0.handling != nil}.count,briefUpdated:model.briefings.state.updatedBriefs?[registration]?.heartbeatID == runID,questions:model.briefings.state.reviewQuestions?.filter{$0.snapshot.registration == registration && $0.snapshot.heartbeatID == runID}.count ?? 0)
    }
    private static func mailFingerprint(_ model:DashboardModel,account:String)->String {
        let values=model.mailData.messages.filter{$0.accountID == account}.map{$0.id+":"+EmailSummary.fingerprint($0)+":"+String($0.replied)}.sorted()
        return SHA256.hash(data:Data(values.joined(separator:"\n").utf8)).map{String(format:"%02x",$0)}.joined()
    }
    private static func sourceFingerprint(_ model:DashboardModel,mailReview:MailReviewScope,whatsappReady:Bool,whatsappEnabled:Bool)->String {
        let a=model.assistant,registration=model.chatGPT.activeID
        let mail=mailReview.accountIDs.sorted().map{$0+":"+mailFingerprint(model,account:$0)}
        let access=model.whatsapp.access(for:registration)
        let wa=whatsappReady && whatsappEnabled && access.enabled && model.whatsapp.connected ? model.whatsapp.messages.filter{access.chats.contains($0.chat)}.map{SourceContextRules.revision($0)}.sorted() : []
        let calendar=model.paOrientation?.calendar ?? model.calendarData
        let events=calendar.events.filter{!a.excludedCalendars.contains($0.calendarID)}.map{$0.id+":"+$0.title+":"+$0.start.ISO8601Format()+":"+$0.end.ISO8601Format()}.sorted()
        let tasks=model.reminderData.reminders.filter{!a.excludedLists.contains($0.listID)}.map{$0.id+":"+$0.title+":"+($0.due?.ISO8601Format() ?? "")}.sorted()
        let life=a.projects.items(registration).map{$0.id.uuidString+":"+$0.revision.uuidString}.sorted()
        let value=[model.proactive.scope(model),String(whatsappEnabled),String(model.emailSummaries.enabled),String(model.proactive.enabled),model.chatGPT.selectedModel,EmailNativeEvidence.hash(model.completedReminders),EmailNativeEvidence.hash(model.emailSummaries.dismissalContext(model))]+mail+wa+events+tasks+life
        return SHA256.hash(data:Data(value.joined(separator:"\n").utf8)).map{String(format:"%02x",$0)}.joined()
    }
}

@MainActor extension HeartbeatService {
    func check(_ model:DashboardModel,manual:Bool = false) {check(runtime:HeartbeatDashboardAdapter.runtime(model),manual:manual)}
    func willSleep(_ model:DashboardModel) {willSleep(runtime:HeartbeatDashboardAdapter.runtime(model))}
    func didWake(_ model:DashboardModel) {didWake(runtime:HeartbeatDashboardAdapter.runtime(model))}
    func deviceAvailabilityChanged(_ model:DashboardModel) {deviceAvailabilityChanged(runtime:HeartbeatDashboardAdapter.runtime(model))}
    func scheduleStatus(_ model:DashboardModel)->String {scheduleStatus(runtime:HeartbeatDashboardAdapter.runtime(model))}
    func manualCheckBlockReason(_ model:DashboardModel)->String? {manualCheckBlockReason(runtime:HeartbeatDashboardAdapter.runtime(model))}
    func manualCheckHelp(_ model:DashboardModel)->String {manualCheckHelp(runtime:HeartbeatDashboardAdapter.runtime(model))}
    func mailReviewStatus(_ model:DashboardModel)->String {mailReviewStatus(registration:model.chatGPT.activeID,accounts:model.mailData.accounts.filter{!model.assistant.excludedAccounts.contains($0.id)})}
}

#if DEBUG
@MainActor extension HeartbeatService {
    static func evaluateScheduling(_ model:DashboardModel) async throws->[String:Any] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox"),ProcessInfo.processInfo.arguments.contains("--scheduler-only") else {throw SummaryFailure.invalid}
        var result=try await evaluateOwnedScheduling()
        var checks=result["checks"] as! [String:Bool]
        checks.merge(try await NativeReconciliationEvaluation.run()) {_,new in new}
        checks.merge(try PreparedApprovalEvaluation.run()) {_,new in new}
        let store=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let now=ISO8601DateFormatter().date(from:"2026-10-07T12:00:00Z")!
        let joiningBrief=BriefingService(container:store)
        checks["explicit brief refresh joins the heartbeat without reserving a blocking slot"] = model.heartbeat.withRunningReviewFixture {joiningBrief.updateToday(model);return !joiningBrief.busy}
        checks.merge(try BriefingService.evaluateHeartbeatStorage(model)) {_,new in new}
        // Actual email-consumer guards over fictional independently collected
        // headers: no source/helper startup, inference or personal cache writes.
        let previousMail=model.mailData,previousIndex=model.mailIndex
        defer {model.mailData=previousMail;model.mailIndex=previousIndex}
        let messageJSON:[String:Any]=["id":"fictional-mail:42","accountID":"fictional-mail","account":"Fictional","messageID":42,"internetMessageID":"fixture@example.invalid","sender":"Fictional coordinator","subject":"Prototype report","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:messageJSON))
        let fictionalAccounts=[MailAccount(id:"fictional-mail",title:"Fictional")]
        model.mailData=MailSnapshot(messages:[message],accounts:fictionalAccounts,errors:[])
        model.mailIndex=MailIndexState();model.mailIndex.discovered(now:now.addingTimeInterval(-300));model.mailIndex.prepare(accounts:fictionalAccounts,now:now)
        let page=model.mailIndex.monitor("fictional-mail")!
        model.mailData=model.mailIndex.apply(MailBatch(messages:[message],messageIDs:[42,43],nextOffset:1,complete:false,errors:[]),to:page.id,snapshot:model.mailData,now:now.addingTimeInterval(-300))
        model.mailIndex.failed("fictional-mail",detail:"A message changed or moved",now:now)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let beforeCollector=try encoder.encode(model.mailIndex)
        let collected=MailReviewScope.collected(index:model.mailIndex,snapshot:model.mailData,excluded:[])
        checks["actual email consumer accepts collected headers during a failed partial poll"] = model.emailSummaries.reviewPermitted(message,model:model,scope:collected)
        checks["heartbeat mail capture preserves actual collector cursors and retry backoff"] = try encoder.encode(model.mailIndex) == beforeCollector
        var revisedJSON=messageJSON;revisedJSON["subject"]="Revised prototype report"
        let revised=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:revisedJSON))
        model.mailData=MailSnapshot(messages:[revised],accounts:fictionalAccounts,errors:[])
        checks["actual consumer rejects changed exact headers in collected mode"] = !model.emailSummaries.reviewPermitted(message,model:model,scope:collected)
        model.mailData=MailSnapshot(messages:[message],accounts:[],errors:[])
        checks["actual consumer rejects removed collected account"] = !model.emailSummaries.reviewPermitted(message,model:model,scope:collected)
        model.mailData=MailSnapshot(messages:[message],accounts:fictionalAccounts,errors:[])
        model.mailIndex.failed("fictional-mail",detail:"Body identity changed",now:now.addingTimeInterval(1))
        checks["actual consumer rejects new source failures during captured analysis"] = !model.emailSummaries.reviewPermitted(message,model:model,scope:collected)
        result["checks"]=checks;result["passed"]=checks.values.filter{$0}.count;result["total"]=checks.count
        return result
    }
}
#endif
