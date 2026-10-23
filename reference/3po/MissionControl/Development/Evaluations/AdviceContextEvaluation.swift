#if DEBUG
import Foundation
import SwiftUI
import SwiftData
import Observation
import Synchronization

/// Actual consumer projections, fictional data and disposable storage; zero subscription requests.
@MainActor enum AdviceContextEvaluation {
    private static func activityOutcomeChecks(_ model:DashboardModel)throws->[String:Bool] {
        let registration=model.chatGPT.activeID,usage=model.aiUsage.state.records.count
        let id=model.assistant.openReview(key:"fictional-pill-answer",title:"Fictional action question",sourceKind:"mail",accountID:"fictional-mail",messageID:"fictional-question",identity:nil,chatID:nil,seeds:[])!
        let response=UUID()
        precondition(model.assistant.appendReview("Which time should I use?",conversationID:id,turnID:response))
        let question=AIActivityRecord(id:"action:"+response.uuidString,registration:registration,kind:.action,state:.needsAnswer,title:"3PO actions",message:"Which time should I use?",destination:.assistant(targetID:id.uuidString))
        precondition(model.aiActivity.upsert(question))
        var checks=["actual pill adapter keeps an unanswered question pending":model.activityPresentation(question).state == .needsAnswer]
        let other=model.assistant.openReview(key:"fictional-pill-other",title:"Other fictional source",sourceKind:"mail",accountID:"fictional-mail",messageID:"fictional-other",identity:nil,chatID:nil,seeds:[])!
        _=model.assistant.appendReview("Use noon",conversationID:other,human:true)
        checks["another source reply does not resolve the current question"]=model.activityPresentation(question).state == .needsAnswer
        _=model.assistant.appendReview("Use noon",conversationID:id,human:true)
        checks["same-source reply updates the displayed question"]=model.activityPresentation(question).state == .replied
        checks["reply display preserves the saved question and acknowledgement"]=model.aiActivity.state.records.first{$0.id == question.id} == question
        var foreign=question;foreign.registration="another-account"
        checks["reply presentation does not cross accounts"]=model.activityPresentation(foreign) == foreign
        let recoveryResponse=UUID()
        precondition(model.assistant.appendReview("Fictional project creation completed",conversationID:id,turnID:recoveryResponse))
        let old=AIActivityRecord(id:"action:"+UUID().uuidString,registration:registration,kind:.action,state:.partial,title:"3PO actions",message:"An earlier project attempt failed",destination:.assistant(targetID:id.uuidString))
        let repaired=AIActivityRecord(id:"action:"+recoveryResponse.uuidString,registration:registration,kind:.action,state:.partial,title:"3PO actions",message:"Use the exact project item identity returned by a current read.",destination:.assistant(targetID:id.uuidString))
        precondition(model.aiActivity.upsert(repaired))
        let completed=AssistantActionResult(phase:"completed",receipts:["Created 4 local workspace items."],confirmedActions:4,unconfirmedActions:0,resolvedActivityIDs:[old.id])
        model.assistant.seedActionResultFixture(conversationID:id,responseID:recoveryResponse,result:completed,errors:[])
        checks["verified final action metadata corrects a stale partial display"]=model.activityPresentation(repaired).state == .succeeded
        checks["recovered success uses the verified receipt"]=model.activityPresentation(repaired).message == "Created 4 local workspace items."
        checks["explicit exact earlier recovery clears only that attention"]=model.activityPresentation(old).state == .resolved
        checks["recovery display preserves raw failure history and acknowledgement"]=model.aiActivity.state.records.first{$0.id == repaired.id} == repaired
        let repairedTurn=model.assistant.conversation(id)!.turns.first{$0.id == recoveryResponse}!
        checks["successful repaired reply has no What went wrong but retains diagnostics"]=PAReadPrerequisite.visibleFailures(unresolved:repairedTurn.unresolvedToolErrors,history:repairedTurn.toolErrors).isEmpty && repairedTurn.toolErrors?.isEmpty == false
        var uncertain=completed;uncertain.phase="uncertain";uncertain.unconfirmedActions=1
        model.assistant.seedActionResultFixture(conversationID:id,responseID:recoveryResponse,result:uncertain,errors:["A save needs checking"])
        checks["uncertain or partial work cannot become a success projection"]=model.activityPresentation(repaired).state == .partial && model.activityPresentation(old).state == .partial
        checks["genuine unresolved reply failures retain What went wrong"] = !PAReadPrerequisite.visibleFailures(unresolved:model.assistant.conversation(id)!.turns.first{$0.id == recoveryResponse}!.unresolvedToolErrors,history:[]).isEmpty
        model.assistant.seedActionResultFixture(conversationID:id,responseID:recoveryResponse,result:completed,errors:["An unrelated sibling still failed"])
        checks["successful approval cannot conceal a genuine unresolved sibling"]=model.activityPresentation(repaired).state == .partial && model.activityPresentation(old).state == .partial
        model.assistant.seedActionResultFixture(conversationID:id,responseID:recoveryResponse,result:completed,errors:[])
        var otherAccount=repaired;otherAccount.registration="foreign-account"
        checks["saved outcome projection cannot cross accounts"]=model.activityPresentation(otherAccount) == otherAccount
        let previous=model.reviewWork;defer {model.reviewWork=previous}
        let source=ReviewWorkSource(key:"fictional-pill-answer",title:"Fictional action question",kind:"mail",accountID:"fictional-mail",messageID:"fictional-question")
        var action=ReviewWorkAction(id:"canonical-action",title:"Fictional task",destination:"Project",payload:Data());action.phase = .saved
        var job=ReviewWorkJob(conversationID:id,scope:model.reviewWorkScope(),source:source,mode:.approval,human:"yes",actions:[action]);job.phase = .completed
        let failed=AIActivityRecord(id:"review:"+job.id.uuidString+":"+UUID().uuidString,registration:registration,kind:.review,state:.failed,title:"Fictional task",message:"The previous attempt failed",destination:.review(targetID:id.uuidString))
        func install(_ job:ReviewWorkJob)throws {let bytes=try JSONEncoder().encode(ReviewWorkState(jobs:[job]));model.reviewWork=ReviewWorkService(load:{bytes},persist:{_ in})}
        try install(job)
        checks["successful exact retry clears the old failure display"]=model.activityPresentation(failed).state == .resolved
        job.actions[0].phase = .failed;try install(job)
        checks["partial or unrelated retry cannot clear the old failure"]=model.activityPresentation(failed).state == .failed
        let outcome=AssistantTurnOutcome(registration:registration,conversationID:id,humanTurnID:UUID(),responseTurnID:UUID(),phase:"completed",message:"Verbose model prose should stay in the conversation",receipts:["Created reminder: Fictional follow-up"],errors:[],confirmedActions:1,attemptedTools:["change_reminder"])
        checks["completed Review jobs use verified receipt text"]=model.classifyAssistantOutcome(outcome).message == "Created reminder: Fictional follow-up"
        let reply=AssistantTurnOutcome(registration:registration,conversationID:id,humanTurnID:UUID(),responseTurnID:UUID(),phase:"completed",message:"An ordinary answer",receipts:[],errors:[])
        checks["ordinary Review answers retain their original conversation text"]=model.classifyAssistantOutcome(reply).message == reply.message
        let success=AIActivityRecord(id:"action:"+UUID().uuidString,registration:registration,kind:.action,state:.succeeded,title:"3PO actions",message:"Created reminder: Fictional follow-up")
        checks["actual Activity adapter displays a concise canonical receipt"]=model.activityPresentation(success).message == "Reminder created: Fictional follow-up" && success.message == "Created reminder: Fictional follow-up"
        checks["activity resolution makes zero inference calls"]=model.aiUsage.state.records.count == usage
        let feedback=ReviewFeedbackJob(registration:registration,messageID:"fictional-retry-email",accountID:"fictional-mail",headerFingerprint:"header",bodyFingerprint:"body",assessmentVersion:"assessment",model:"fictional-model",sourceRevision:0,words:"Routine fictional announcements can stay quiet.",about:"Fictional newsletter",heartbeatEligible:true)
        precondition(model.emailSummaries.feedback.submit(feedback))
        let failedFeedback=AIActivityRecord(id:"feedback:"+feedback.id.uuidString+":"+UUID().uuidString,registration:registration,kind:.feedback,state:.failed,title:"Feedback",message:"Old failure",destination:.feedback(targetID:feedback.id.uuidString))
        checks["feedback alert stays unresolved before verified save"]=model.activityPresentation(failedFeedback).state == .failed
        precondition(model.emailSummaries.feedback.markSaved(feedback.id))
        checks["feedback saved job without memory readback cannot resolve failure"]=model.activityPresentation(failedFeedback).state == .failed
        precondition(model.assistant.memory.saveReviewPreference(feedback.words,registration:registration,about:feedback.about,id:feedback.memoryID))
        checks["same feedback retry with exact saved memory resolves old failure"]=model.activityPresentation(failedFeedback).state == .resolved && failedFeedback.state == .failed && failedFeedback.message == "Old failure"
        var otherFeedback=failedFeedback;otherFeedback.destination = .feedback(targetID:UUID().uuidString)
        checks["feedback retry never resolves another submission failure"]=model.activityPresentation(otherFeedback).state == .failed
        var wrongRecord=failedFeedback;wrongRecord.id="feedback:"+UUID().uuidString
        checks["feedback resolution requires matching stored operation identity"]=model.activityPresentation(wrongRecord).state == .failed
        checks["feedback outcome resolution makes zero inference calls"]=model.aiUsage.state.records.count == usage
        return checks
    }
    private static func navigationStorageChecks()throws->[String:Bool] {
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let context=container.mainContext,unrelated=Data(repeating:42,count:1_000_000)
        context.insert(CachedDashboard(key:"fictional-unrelated-cache",data:unrelated));try context.save()
        let workspace=WorkspaceStore(container:container,calendars:[],lists:[],accounts:[],date:.now)
        let original=workspace.state.selectedPageID,next=workspace.state.pages.first{$0.id != original}!.id
        let before=try context.fetch(FetchDescriptor<CachedDashboard>()).first{$0.key == "workspace"}!.updated
        workspace.select(original)
        let after=try context.fetch(FetchDescriptor<CachedDashboard>()).first{$0.key == "workspace"}!.updated
        var checks=["selecting the mounted page performs no redundant save":before == after]
        workspace.select(next)
        let reopened=WorkspaceStore(container:container,calendars:[],lists:[],accounts:[],date:.now)
        checks["page selection persists through exact-key fetch and reopen"]=reopened.state.selectedPageID == next && reopened.state.pages == workspace.state.pages
        let drafts=ChatDraftStore(container:container),widget=UUID(),other=UUID(),conversation=UUID()
        drafts.set("Fictional draft",registration:"fixture-one",widget:widget,conversation:conversation)
        drafts.set("Other fictional draft",registration:"fixture-two",widget:other,conversation:conversation);drafts.flush()
        let reopenedDrafts=ChatDraftStore(container:container)
        checks["exact-key draft save preserves account and widget isolation on reopen"]=reopenedDrafts.text(registration:"fixture-one",widget:widget,conversation:conversation) == "Fictional draft" && reopenedDrafts.text(registration:"fixture-two",widget:other,conversation:conversation) == "Other fictional draft" && reopenedDrafts.text(registration:"fixture-two",widget:widget,conversation:conversation).isEmpty
        reopenedDrafts.set("",registration:"fixture-one",widget:widget,conversation:conversation);reopenedDrafts.flush()
        let clearedDrafts=ChatDraftStore(container:container)
        checks["clearing one saved draft preserves the other account draft"]=clearedDrafts.text(registration:"fixture-one",widget:widget,conversation:conversation).isEmpty && clearedDrafts.text(registration:"fixture-two",widget:other,conversation:conversation) == "Other fictional draft"
        let records=try context.fetch(FetchDescriptor<CachedDashboard>())
        checks["targeted UI saves preserve unrelated cache bytes and unique keys"]=records.first{$0.key == "fictional-unrelated-cache"}?.data == unrelated && records.filter{$0.key == "workspace"}.count == 1 && records.filter{$0.key == "assistantDrafts"}.count == 1
        let feedback=EmailSummaryService(container:container)
        let submission=ReviewFeedbackJob(registration:"fixture-one",messageID:"fictional-newsletter",accountID:"fictional-mail",headerFingerprint:"header",bodyFingerprint:"body",assessmentVersion:"assessment",model:"fictional-model",sourceRevision:0,words:"Routine fictional newsletters can stay quiet.",about:"Newsletters")
        checks["feedback submission persists before any inference"]=feedback.feedback.submit(submission)
        let reopenedFeedback=EmailSummaryService(container:container)
        checks["feedback reopen retains exact words and owner without replay"]=reopenedFeedback.feedback.records.first?.state == .interrupted && reopenedFeedback.feedback.records.first?.words == submission.words && reopenedFeedback.feedback.items("fixture-two").isEmpty
        let memory=PAMemoryStore(container:container)
        checks["feedback saves its issued exact memory identity"]=memory.saveReviewPreference(submission.words,registration:submission.registration,about:submission.about,id:submission.memoryID)
        let reopenedMemory=PAMemoryStore(container:container)
        checks["feedback exact memory target survives storage readback"]=reopenedMemory.records.first{$0.id == submission.memoryID}?.reviewFeedback == submission.words
        checks["feedback refuses duplicate save at its exact memory identity"] = !reopenedMemory.saveReviewPreference(submission.words,registration:submission.registration,about:submission.about,id:submission.memoryID) && reopenedMemory.records.filter{$0.id == submission.memoryID}.count == 1
        return checks
    }
    private static func resolutionConsumerChecks(_ model:DashboardModel)throws->[String:Bool] {
        try ReviewInboxEvaluation.seedResolutionPreview(model)
        let saved=model.emailSummaries.records,request=saved.first{$0.id == "assessment-request"}!,confirmation=saved.first{$0.id == "assessment-confirmation"}!,original=request.message!,now=Date.now,owner=model.chatGPT.activeID
        let revision=model.emailSummaries.resolutionRevision(model)
        var checks:[String:Bool]=[:]
        checks["later submission removes original assessment from active email/review/brief"] = !model.emailSummaries.highlights(model).contains{$0.0.id == original.id} && !model.reviewInbox.emails.contains{$0.0.id == original.id} && !model.briefings.currentEmails(model).contains{$0.0.id == original.id}
        checks["new assessment stage stays actionable and counts once"] = model.reviewInbox.pendingCount == 1 && model.reviewInbox.emails.map{$0.0.id} == ["assessment-next-stage"]
        checks["resolved assessment leaves inspectable exact two-message history"] = model.reviewInbox.resolved.count == 1 && model.reviewInbox.resolved[0].2 == request.resolution
        let capturedResolutions=model.emailSummaries.resolutionContext(model)
        checks["exact supplied confirmation context is initially available"] = !capturedResolutions.isEmpty && model.emailSummaries.resolutionContextAvailable(capturedResolutions,model:model)
        checks["exact confirmation context retains purpose-specific Mail access"] = !model.emailSummaries.resolutionContextAvailable(capturedResolutions,model:model,mailAccounts:[],use:.brief)
        do {
            defer {try? model.emailSummaries.seedAdviceFixture(saved)}
            var unrelated=request
            unrelated.id="fictional-unrelated-no-confirmation";unrelated.resolution=nil
            unrelated.reviewContext = .init(policy:model.emailSummaries.policy(owner),memories:[],discoveryRevision:nil,contextPageDependencies:["context-purpose:email":"1"])
            let ordinary=model.emailSummaries.sourceAssessments(model).filter{$0.1.resolution != nil}.map{$0.1.id}
            let candidates=model.emailSummaries.sourceAssessments(model,requiringResolution:true).map{$0.1.id}
            checks["confirmation candidate filter preserves the exact guarded sorted subset"] = candidates == ordinary
            let additions=(0..<80).map { index in var row=unrelated;row.id += "-\(index)";return row }
            try model.emailSummaries.seedAdviceFixture(saved + additions)
            let builds=model.contextKnowledgeBuildCount
            let actual=model.emailSummaries.resolutionContext(model)
            checks["confirmation lookup ignores unrelated assessments before context-page validation"] = actual == capturedResolutions && model.contextKnowledgeBuildCount == builds
        }
        do {
            let capturedMail=model.mailData
            defer {model.mailData=capturedMail;try? model.emailSummaries.seedAdviceFixture(saved)}
            var additions:[EmailSummary]=[]
            for index in 0..<30 {
                let id="unrelated-confirmation-request-\(index)"
                let raw:[String:Any]=["id":id,"accountID":original.accountID,"account":original.account,"messageID":index+10,"internetMessageID":id+"@example.invalid","sender":original.sender,"subject":"Other fictional assessment \(index)","received":original.received.addingTimeInterval(Double(index+1)).ISO8601Format(),"unread":true,"replied":false,"flagged":false]
                let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:raw))
                var summary=request;summary.id=id;summary.message=message;summary.messageReceived=message.received;summary.fingerprint=EmailSummary.fingerprint(message)
                let requestVersion=EmailSummary.sourceVersion(message,summary),assessmentRevision=summary.adviceRevision(replied:message.replied)
                summary.resolution?.requestVersion=requestVersion
                summary.resolution?.assessmentRevision=assessmentRevision
                additions.append(summary)
            }
            model.mailData = .init(messages:capturedMail.messages+additions.compactMap(\.message),accounts:capturedMail.accounts,errors:[])
            try model.emailSummaries.seedAdviceFixture(saved+additions)
            checks["confirmation fixture actually crowds supplied row outside presentation cap"] = model.emailSummaries.resolutionContext(model).count == 24 && !model.emailSummaries.resolutionContext(model).contains(capturedResolutions[0])
            checks["new unrelated confirmations cannot revoke supplied exact context"] = model.emailSummaries.resolutionContextAvailable(capturedResolutions,model:model)
            additions[0].resolution?.reason="Unrelated comparison wording changed."
            try model.emailSummaries.seedAdviceFixture(saved+additions)
            checks["unrelated confirmation edits cannot revoke supplied exact context"] = model.emailSummaries.resolutionContextAvailable(capturedResolutions,model:model)
            var edited=saved;edited[edited.firstIndex{$0.id == request.id}!].resolution?.reason="The supplied comparison wording changed."
            try model.emailSummaries.seedAdviceFixture(edited+additions)
            checks["changed supplied confirmation row rejects its earlier context"] = !model.emailSummaries.resolutionContextAvailable(capturedResolutions,model:model)
        }
        let pa: [String:Any] = try model.assistant.snapshot(model).flatMap{try JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]} ?? [:]
        checks["PA receives completed communication context without stale request"] = (pa["savedEmailSummaries"] as? [[String:Any]])?.contains{$0["id"] as? String == original.id} == false && (pa["resolvedEmailRequests"] as? [[String:Any]])?.first?["confirmationQuote"] as? String == confirmation.evidence
        checks["follow-up retention excludes addressed email obligation"] = !model.emailSummaries.memories(model).contains{$0.0.id == original.id}
        let rawSnapshot=DailyBriefing(id:"fictional-resolution",registration:owner,day:BriefingRules.day(now),created:now,items:[],sources:[.init(id:"resolved_0",label:"Fictional completion",kind:"mailResolution",date:now,originalID:confirmation.id,contentRevision:EmailNativeEvidence.hash(request.resolution!))],coverage:"Fictional",message:"The coding assessment was submitted.",reviewAcknowledgementRevision:model.reviewAcknowledgementRevision,emailResolutionRevision:revision)
        try model.briefings.seedAdviceFixture(rawSnapshot,model:model)
        let snapshot=model.briefings.state.records[0]
        checks["brief exact completion receipt is initially current"] = model.briefings.freshnessNote(snapshot,model:model) == nil
        model.emailSummaries.dismiss(confirmation.id,model:model,expectedRegistration:owner,expectedVersion:ReviewAcknowledgementRules.emailVersion(confirmation.message!,confirmation))
        checks["Dismiss of confirmation does not reopen addressed request"] = model.emailSummaries.resolved(model).count == 1 && model.reviewInbox.pendingCount == 1
        model.emailSummaries.undoDismiss(model)
        model.emailSummaries.keepForReview(request.id,model:model)
        checks["Keep in review reopens original and removes inferred history"] = model.reviewInbox.resolved.isEmpty && model.reviewInbox.emails.contains{$0.0.id == original.id} && model.reviewInbox.pendingCount == 2
        checks["Keep in review invalidates earlier brief completion context"] = model.briefings.freshnessNote(snapshot,model:model) != nil
        model.emailSummaries.keepForReview(request.id,model:model,keep:false)
        checks["reversing Keep restores same exact receipt without another inference"] = model.emailSummaries.resolved(model).first?.2 == request.resolution && model.emailSummaries.resolutionRevision(model) == revision
        var proposal=PADiscovery(id:UUID().uuidString,registration:owner,mailID:request.id,kind:"reminder",message:"Complete the Orion Labs coding assessment.",evidence:request.evidence,created:now,scope:"fictional")
        proposal.sourceRevision=request.fingerprint;proposal.sourceAssessmentRevision=request.adviceRevision(replied:false)
        try model.proactive.seedAdviceFixture([proposal],model:model)
        proposal=model.proactive.state.records[0]
        checks["resolved context leaves saved proposal reviewable until heartbeat retirement"] = !model.proactive.visible(proposal,model:model) && model.proactive.canReview(proposal.id,model:model)
        let claim=NativeCreationRequest(id:UUID(uuidString:proposal.id)!,kind:.reminder,registration:owner)
        try model.nativeCreations.begin(claim)
        checks["uncertain native creation remains visible with no new approval authority"] = model.proactive.visible(proposal,model:model) && !model.proactive.canReview(proposal.id,model:model) && !model.proactive.reviewEvidenceAvailable(proposal.id,model:model) && model.proactive.sourceDetails(proposal,model:model) != nil
        var pending=proposal;pending.id=UUID().uuidString;pending.kind="change";pending.reviewState="pending"
        try model.proactive.seedAdviceFixture([pending],model:model);pending=model.proactive.state.records[0]
        checks["pending native change remains available for outcome checking"] = model.proactive.visible(pending,model:model) && !model.proactive.canReview(pending.id,model:model)
        try model.emailSummaries.observeBodyVersion(confirmation.message!,hash:"observed-corrected-confirmation",model:model)
        checks["observed body correction immediately withdraws completion before failed reassessment"] = model.emailSummaries.resolved(model).isEmpty && model.emailSummaries.highlights(model).contains{$0.0.id == original.id}
        checks["observed source correction invalidates exact supplied confirmation context"] = !model.emailSummaries.resolutionContextAvailable(capturedResolutions,model:model)
        let reopenedService=try model.emailSummaries.reopenedResolutionFixture()
        checks["observed drift persists through reopen without new AI output"] = reopenedService.records.first{$0.id == confirmation.id}?.observedBodyFingerprint == "observed-corrected-confirmation" && reopenedService.resolved(model).isEmpty && reopenedService.highlights(model).contains{$0.0.id == original.id} && reopenedService.records.first{$0.id == original.id}?.resolution == request.resolution
        try model.emailSummaries.observeBodyVersion(confirmation.message!,hash:confirmation.bodyFingerprint!,model:model)
        checks["verified original body restores the same saved completion receipt"] = model.emailSummaries.resolved(model).count == 1
        var changed=saved;changed[changed.firstIndex{$0.id == confirmation.id}!].bodyFingerprint="corrected-confirmation-body"
        try model.emailSummaries.seedAdviceFixture(changed)
        checks["same-header confirmation body correction invalidates completion receipt"] = model.emailSummaries.resolved(model).isEmpty && model.emailSummaries.highlights(model).contains{$0.0.id == original.id}
        checks["corrected evidence withdraws old brief without overwriting saved history"] = model.briefings.freshnessNote(snapshot,model:model) != nil && model.emailSummaries.records.first{$0.id == original.id}?.resolution == request.resolution
        try model.emailSummaries.seedAdviceFixture(saved)
        let mail=model.mailData;model.mailData = .init(messages:mail.messages,accounts:[],errors:[])
        checks["unavailable or removed account cannot support resolved communication"] = model.emailSummaries.resolved(model).isEmpty && model.emailSummaries.resolutionContext(model).isEmpty
        model.mailData=mail
        let completionPool=model.emailSummaries.completionCandidates([(original,request)],model:model,scope:nil)
        checks["quiet confirmations participate in bounded comparison evidence"] = completionPool.contains{$0.0.id == confirmation.id} && completionPool.count <= 12
        var reopened=request;reopened.resolution=nil
        let task=TaskItem(id:"fictional-planned-assessment",listID:"fixture-list",title:"Complete Orion Labs coding assessment",due:now,hasTime:false,sourceLabel:"Fixture",writable:true,recurring:false,modified:now)
        model.reminderData = .init(sources:[],reminders:[task]);model.reminderHealth = .init(lastSuccess:now);model.paOrientationHealth = .init(lastSuccess:now)
        reopened.handling = .init(assessmentRevision:reopened.adviceRevision(replied:false),native:.reminder(task),reason:"Exact assessment is planned.",created:now)
        try model.emailSummaries.seedAdviceFixture([reopened,confirmation])
        checks["already planned request can still compare later submission confirmation"] = model.proactive.emailReviewCandidates(model,heartbeat:true,mailReview:nil,whatsappReady:true,now:now).contains{$0.0.id == original.id}
        try model.emailSummaries.seedAdviceFixture(saved)
        return checks
    }
    private static func fingerprintCacheChecks(_ model:DashboardModel)->[String:Bool] {
        let service=model.whatsapp,oldMessages=service.messages,oldIdentity=service.linkedIdentity
        defer {service.messages=oldMessages;service.linkedIdentity=oldIdentity}
        service.linkedIdentity="fictional-cache-device"
        service.messages=(0..<2000).map{.init(id:"cache-\($0)",chat:$0.isMultiple(of:2) ? "fixture-a" : "fixture-b",sender:"Fictional sender",text:"Fictional text \($0)",sentByMe:false,time:Double($0))}
        var checks:[String:Bool]=[:]
        let initialBuilds=service.windowFingerprintBuilds
        let changed=Mutex(false)
        let fingerprint=withObservationTracking {service.windowFingerprint(chat:"fixture-a")} onChange:{changed.withLock{$0=true}}
        for _ in 0..<200 { _=service.windowFingerprint(chat:"fixture-a") }
        checks["200 repeated window checks hash a large unchanged chat only once"]=service.windowFingerprintBuilds == initialBuilds+1
        checks["cache population does not invalidate observed source inputs"]=changed.withLock{!$0}
        checks["cached fingerprint exactly matches canonical source revisions"]=fingerprint == ProactiveRules.whatsappWindow(service.messages,chats:["fixture-a"],identity:service.linkedIdentity)
        let warmedMessages=Mutex(false)
        withObservationTracking {_=service.windowFingerprint(chat:"fixture-a")} onChange:{warmedMessages.withLock{$0=true}}
        let original=service.messages[0]
        service.messages[0] = .init(id:original.id,chat:original.chat,sender:original.sender,text:"Changed fictional source content",sentByMe:original.sentByMe,time:original.time)
        let edited=service.windowFingerprint(chat:"fixture-a")
        checks["same-count in-place source correction invalidates a warmed window"]=edited != fingerprint && edited == ProactiveRules.whatsappWindow(service.messages,chats:["fixture-a"],identity:service.linkedIdentity)
        checks["warmed cache hits still observe message changes"]=warmedMessages.withLock{$0}
        let unrelated=service.messages[1]
        service.messages[1] = .init(id:unrelated.id,chat:unrelated.chat,sender:unrelated.sender,text:"An unrelated chat changed",sentByMe:unrelated.sentByMe,time:unrelated.time)
        checks["unrelated chat changes preserve exact fingerprint after rebuilding"]=service.windowFingerprint(chat:"fixture-a") == edited
        service.messages.reverse()
        checks["message order retains canonical window fingerprint"]=service.windowFingerprint(chat:"fixture-a") == edited
        service.messages.append(.init(id:"fixture-new",chat:"fixture-a",sender:"Fictional sender",text:"New reply",sentByMe:true,time:3000))
        let appended=service.windowFingerprint(chat:"fixture-a")
        checks["appending new evidence invalidates the warmed window"]=appended != edited
        service.messages.removeLast()
        checks["removing evidence restores the exact earlier fingerprint"]=service.windowFingerprint(chat:"fixture-a") == edited
        let warmedIdentity=Mutex(false)
        withObservationTracking {_=service.windowFingerprint(chat:"fixture-a")} onChange:{warmedIdentity.withLock{$0=true}}
        service.linkedIdentity="fictional-other-device"
        checks["warmed cache observes identity changes and cannot reuse another device window"]=warmedIdentity.withLock{$0} && service.windowFingerprint(chat:"fixture-a") != edited
        service.linkedIdentity=""
        checks["identity reset recomputes the canonical empty-identity window"]=service.windowFingerprint(chat:"fixture-a") == ProactiveRules.whatsappWindow(service.messages,chats:["fixture-a"],identity:"")
        service.messages=[]
        checks["source loss invalidates the cached window"]=service.windowFingerprint(chat:"fixture-a") == ProactiveRules.whatsappWindow([],chats:["fixture-a"],identity:"")
        checks["a cached fingerprint cannot bypass current purpose and access guards"] = !model.whatsappDependenciesAvailable([.init(chatID:"fixture-a",linkedIdentity:"fictional-cache-device",fingerprint:fingerprint)],use:.brief)
        return checks
    }
    private static func feedbackRefreshChecks(_ model:DashboardModel)async throws->[String:Bool] {
        let mail=model.mailData,summaries=model.emailSummaries.records,usage=model.aiUsage.state.records.count
        var addedMemories:[UUID]=[]
        defer {model.mailData=mail;try? model.emailSummaries.seedAdviceFixture(summaries);for id in addedMemories {_=model.assistant.memory.forget(id)}}
        let body="Fictional routine newsletter with optional events.",registration=model.chatGPT.activeID
        let fields:[String:Any]=["id":"feedback-refresh-fixture","accountID":"fictional-mail","account":"Fictional Mail","messageID":1,"internetMessageID":"feedback-refresh@example.invalid","sender":"Fictional newsletter","subject":"Optional events","received":Date.now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:fields))
        let summary=EmailSummary(id:message.id,registration:registration,fingerprint:EmailSummary.fingerprint(message),summary:"Optional events",attention:false,reason:"",evidence:body,bodyFingerprint:EmailSummary.fingerprintBody(body),message:message)
        model.mailData = .init(messages:[message],accounts:[.init(id:message.accountID,title:message.account)],errors:[])
        try model.emailSummaries.seedAdviceFixture([summary])
        let source=ReviewFeedbackEmail(message:message,summary:summary)
        var checks:[String:Bool]=[:]
        for phase in ["body read","inference","memory during body read","memory during inference"] {
            let current=model.emailSummaries.feedbackOwnershipGuard(source,model:model,isCurrent:{true})
            var reads=0,requests=0
            func addMemory()throws {
                let memory=PAMemory(registration:registration,text:"Fictional unrelated preference "+UUID().uuidString,kind:.preference,provenance:"Fictional human")
                guard model.assistant.memory.put(memory) else {throw SummaryFailure.invalid};addedMemories.append(memory.id)
            }
            let result=try await ReviewFeedbackRules.prepare(source,words:"These can stay quiet",about:message.subject,model:model.chatGPT.selectedModel,isCurrent:current,readBody:{
                reads += 1;await Task.yield()
                if phase == "body read" {model.sourceRevision += 1}
                if phase == "memory during body read" {try addMemory()}
                return body
            },infer:{_ in
                requests += 1;await Task.yield()
                if phase == "inference" {model.sourceRevision += 1}
                if phase == "memory during inference" {try addMemory()}
                return "{\"rule\":\"Routine fictional newsletters can stay quiet.\"}"
            })
            checks["actual feedback guard tolerates unrelated change during "+phase]=reads == 2 && requests == 1 && result.bodyFingerprint == summary.bodyFingerprint
        }
        checks["feedback refresh regressions use no subscription inference"]=usage == model.aiUsage.state.records.count
        return checks
    }
    private static func capturedEmailContextChecks(_ model:DashboardModel)async throws->[String:Bool] {
        let memory=model.assistant.memory,projects=model.assistant.projects,registration=model.chatGPT.activeID,usage=model.aiUsage.state.records.count
        let originalMemoryIDs=Set(memory.records.map(\.id)),originalProjectIDs=Set(projects.state.items.map(\.id))
        defer {
            for record in memory.records where !originalMemoryIDs.contains(record.id) {_=memory.forget(record.id)}
            for item in projects.items(registration,includeTopics:true) where !originalProjectIDs.contains(item.id) {try? projects.trash(item.id,registration:registration,keepChildren:false,expectedRevision:projects.revision)}
        }
        let fields:[String:Any]=["id":"captured-context-fixture","accountID":"fictional-mail","account":"Fictional Mail","messageID":1,"internetMessageID":"captured-context@example.invalid","sender":"Fictional engineer","subject":"Zephyr resonator","received":Date.now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:fields))
        let fact=PAMemory(registration:registration,text:"I am building the Zephyr resonator.",kind:.context,provenance:"Fictional human")
        guard memory.put(fact) else {throw SummaryFailure.invalid}
        let project=try projects.save(LifeItem(registration:registration,kind:.space,title:"Zephyr resonator",status:.active),expected:nil)
        let header=model.emailSummaries.relevanceContext(message,model:model,header:true),body=model.emailSummaries.relevanceContext(message,model:model,body:"Please review the Zephyr resonator.")
        var checks=["actual email captures include the relevant human fact and project":header.memories.contains{$0["id"] == fact.id.uuidString} && header.workspace.contains{$0["id"] == "life:"+project.id.uuidString} && !body.memoryReceipts.isEmpty]
        @MainActor func held(_ valid:@escaping ()->Bool,change:()throws->Void)async throws->Bool {
            var release:CheckedContinuation<Void,Never>?
            let task=Task { @MainActor in await withCheckedContinuation {release=$0};return valid() }
            while release == nil {await Task.yield()}
            do {try change()} catch {release?.resume();_=await task.value;throw error}
            release?.resume();return await task.value
        }
        checks["held email input survives unrelated memory project and EventKit changes"]=try await held({model.emailSummaries.relevanceContextAvailable(header,model:model,header:true) && model.emailSummaries.relevanceContextAvailable(body,model:model)},change:{
            guard memory.put(PAMemory(registration:registration,text:"I like fictional woodland walks.",kind:.preference,provenance:"Fictional human")) else {throw SummaryFailure.invalid}
            _=try projects.save(LifeItem(registration:registration,kind:.space,title:"Fictional pottery",status:.active),expected:nil)
            model.sourceRevision += 1
        })
        checks["held email input survives newly selected facts crowding its header window"]=try await held({model.emailSummaries.relevanceContextAvailable(header,model:model,header:true)},change:{
            for _ in 0..<8 {guard memory.put(PAMemory(registration:registration,text:fact.text,kind:.context,provenance:"Fictional human")) else {throw SummaryFailure.invalid}}
        })
        checks["crowding fixture actually changes the newly retrieved header window"]=header.memories != model.emailSummaries.relevanceContext(message,model:model,header:true).memories
        let preferenceStamp=model.emailSummaries.reviewPreferenceStamp(message,model:model,evidence:"Please review the Zephyr resonator.")
        checks["new applicable Review preference cannot be stamped as already assessed"] = !(try await held({preferenceStamp == model.emailSummaries.reviewPreferenceStamp(message,model:model,evidence:"Please review the Zephyr resonator.")},change:{guard memory.saveReviewPreference("Prioritise messages about my Zephyr resonator.",registration:registration,about:"Zephyr resonator") else {throw SummaryFailure.invalid}}))
        checks["selected human-memory bookkeeping does not revoke email input"]=try await held({model.emailSummaries.relevanceContextAvailable(body,model:model)},change:{guard memory.put(fact) else {throw SummaryFailure.invalid}})
        var changed=fact;changed.text="I stopped building the Zephyr resonator."
        checks["held email input rejects a changed supplied human belief"] = !(try await held({model.emailSummaries.relevanceContextAvailable(body,model:model)},change:{guard memory.put(changed) else {throw SummaryFailure.invalid}}))
        guard memory.put(fact) else {throw SummaryFailure.invalid}
        var edited=project;edited.notes="New exact supplied project context"
        checks["held email input rejects a changed supplied project"] = !(try await held({model.emailSummaries.relevanceContextAvailable(body,model:model)},change:{_=try projects.save(edited,expected:project.revision)}))
        let humanRows=[MemoryRetrieval.record(fact)]
        checks["reply draft selected facts remain available after unrelated changes"]=model.emailSummaries.humanMemoryContextAvailable(humanRows,model:model,includeTopics:true)
        _=memory.forget(fact.id)
        checks["reply draft rejects forgotten supplied human facts"] = !model.emailSummaries.humanMemoryContextAvailable(humanRows,model:model,includeTopics:true)
        checks["email context dependency checks make zero inference requests"]=usage == model.aiUsage.state.records.count
        return checks
    }
    static func run(_ model:DashboardModel)async throws->[String:Any] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-advice-context"),model.assistant.memory.enabled,model.assistant.contextEnabled else {
            throw ActionFailure.message("This check requires the existing memory/source context settings to be on. No settings were changed.")
        }
        // Fictional summary seeding clears its persisted error. Preserve the
        // installed diagnostic even when a held validation throws.
        let savedSummaryError=UserDefaults.standard.object(forKey:"emailSummaryError")
        defer {UserDefaults.standard.set(savedSummaryError,forKey:"emailSummaryError")}
        let registration=model.chatGPT.activeID,now=Date.now,store=model.assistant.memory
        let identity=MemorySourceIdentity(kind:.calendar,accountID:"fictional-provider",containerID:"fictional-study",itemID:"fictional-orion")
        let quote="Prepare four sensors for the Orion supervision."
        let source=MemorySourceEvidence(identity:identity,revision:"fictional-v1",label:"Fictional Studies",quote:quote,observed:now,sourceDate:now)
        let fact=PAMemory(registration:registration,text:"A Calendar entry requests a four-sensor Orion prototype.",kind:.commitment,explicit:false,provenance:"Fictional source",evidence:quote,certainty:.inferred,durability:.situational,source:source,sourceState:.proposed)
        let human=PAMemory(registration:registration,text:"I prefer preparing the day before.",kind:.preference,provenance:"Fictional human",evidence:"I prefer preparing the day before.")
        var permitted=true,projectionCalls=0
        store.sourceIsPermitted={_ in permitted}
        store.sourcePermissionProjection={projectionCalls += 1;return permitted ? [fact.id] : []}
        guard store.put(human) else { throw SummaryFailure.invalid }
        let humanOnlyPermitted=store.permittedRecords
        let humanOnlySkippedProjection=projectionCalls == 0 && humanOnlyPermitted.map(\.id) == [human.id]
        guard store.putSources([fact],evidenceTexts:[identity:quote],expectedRevision:store.revision) else { throw SummaryFailure.invalid }
        let capture=model.automaticMemory(.brief)
        var checks=fingerprintCacheChecks(model)
        let heartbeatAdapter=HeartbeatDashboardAdapter.runtime(model),beforeWrite=heartbeatAdapter.environment()
        let wasWriting=model.writing;model.writing=true
        let duringWrite=heartbeatAdapter.environment();model.writing=wasWriting
        checks["native writing blocks new heartbeat admission without revoking the current AI owner"] = duringWrite.workBusy && duringWrite.foregroundBusy == beforeWrite.foregroundBusy
        let mailAttention=PADiscovery(id:"fixture-mail-attention",registration:registration,mailID:"fixture-mail",kind:"reminder",message:"Fictional request",evidence:"Fictional evidence",created:now,scope:"fictional")
        var whatsappAttention=mailAttention;whatsappAttention.sourceKind="whatsapp"
        checks["Mail-only attention does not acquire WhatsApp permission dependencies"] = !PAToolSession.attentionUsesWhatsApp(model,discoveries:[mailAttention],acknowledgements:[])
        checks["actual returned WhatsApp attention retains its permission dependency"] = PAToolSession.attentionUsesWhatsApp(model,discoveries:[whatsappAttention],acknowledgements:[])
        let whatsappBrief=DailyBriefing(id:"fixture-wa-brief",registration:registration,day:BriefingRules.day(now),created:now,items:[],sources:[.init(id:"whatsapp_0",label:"Fictional chat",kind:"whatsapp",date:now)],coverage:"Fictional",message:"Fictional chat context")
        checks["attention binds permission to actual saved brief source provenance"] = PAToolSession.attentionUsesWhatsApp(model,brief:whatsappBrief,acknowledgements:[])
        checks.merge(try await feedbackRefreshChecks(model),uniquingKeysWith:{$1})
        checks.merge(try await ReviewInferenceGuardEvaluation.run(),uniquingKeysWith:{$1})
        checks.merge(try await ForegroundInteractionEvaluation.run(),uniquingKeysWith:{$1})
        checks.merge(try await ContextPagesEvaluation.run(),uniquingKeysWith:{$1})
        checks.merge(try await capturedEmailContextChecks(model),uniquingKeysWith:{$1})
        checks.merge(try navigationStorageChecks(),uniquingKeysWith:{$1})
        checks["human-only store avoids source projection"]=humanOnlySkippedProjection
        projectionCalls=0
        let humanDependencies=capture.dependencies.filter{$0.id == human.id.uuidString}
        let exactHuman=model.memoryDependencyRecords(humanDependencies,use:.brief)
        checks["human dependencies avoid unrelated source projection"]=projectionCalls == 0 && exactHuman.map(\.id) == [human.id] && model.memoryDependenciesAvailable(humanDependencies,use:.brief)
        _=model.memoryDependencyRecords(capture.dependencies,use:.brief)
        checks["mixed dependencies still check live source permission"]=projectionCalls > 0
        checks["actual capture includes permitted source and human facts"]=capture.records.count == 2 && capture.dependencies.count == 2
        let morning=DailyBriefing(id:"fictional-morning",registration:registration,day:BriefingRules.day(now),created:now,items:[.init(text:"Prepare the Orion prototype.",sourceIDs:["memory_0"])],sources:[.init(id:"memory_0",label:"Fictional memory",kind:"memory",date:nil,originalID:fact.id.uuidString)],coverage:"Fictional",message:"Good morning. Prepare the Orion prototype. [memory_0]",memoryDependencies:capture.dependencies)
        let json:[String:Any]=["id":"fictional-message","accountID":"fictional-mail","account":"Fictional Mail","messageID":1,"internetMessageID":"orion@example.invalid","sender":"Fictional tutor","subject":"Orion preparation","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:json))
        model.mailData = .init(messages:[message],accounts:[.init(id:message.accountID,title:message.account)],errors:[])
        let summary=EmailSummary(id:message.id,registration:registration,fingerprint:EmailSummary.fingerprint(message),summary:"Orion preparation requested.",attention:true,reason:"Prepare the prototype",evidence:quote,bodyFingerprint:"fictional-body-v1",message:message,worthReading:true,needsReply:false)
        try model.emailSummaries.seedAdviceFixture([summary])
        checks["brief input includes exact current email assessment"] = model.briefings.currentEmails(model).count == 1
        var renamedJSON=json;renamedJSON["sender"]="Updated fictional contact name"
        let renamedSender=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:renamedJSON))
        model.mailData = .init(messages:[renamedSender],accounts:model.mailData.accounts,errors:[])
        checks["stale sender metadata withholds old assessment before brief inference"] = model.briefings.currentEmails(model).isEmpty
        checks["withholding a stale assessment preserves saved history"] = model.emailSummaries.records.count == 1 && model.emailSummaries.records[0].fingerprint == summary.fingerprint
        model.mailData = .init(messages:[message],accounts:model.mailData.accounts,errors:[])
        let advice=PADiscovery(id:UUID().uuidString,registration:registration,mailID:message.id,kind:"reminder",message:"Would a prototype reminder help?",evidence:quote,created:now,scope:"fixture",sourceRevision:summary.fingerprint,memoryDependencies:capture.dependencies,memoryUse:.manualSuggestions,sourceAssessmentRevision:summary.adviceRevision(replied:false))
        try model.proactive.seedAdviceFixture([advice],model:model)
        try model.briefings.seedAdviceFixture(morning,model:model)
        let savedAdvice=model.proactive.state.records[0],savedMorning=model.briefings.state.records[0]
        let delivery=ConversationRules.morningKey(registration:registration,day:morning.day)
        checks["actual current brief is initially available"]=model.briefings.current(model)?.id == morning.id
        checks["saved brief display hides internal aliases without rewriting the original"]=BriefingRules.displayProse(savedMorning) == "Good morning. Prepare the Orion prototype." && savedMorning.message == morning.message && savedMorning.items[0].sourceIDs == ["memory_0"]
        checks["original cited morning delivery remains valid for exact history guards"]=model.briefings.allowsChatDelivery(delivery,content:BriefingRules.prose(morning),model:model)
        checks["actual Tasks suggestion is initially visible"]=model.proactive.visible(savedAdvice,model:model)
        let repeated=(0..<40).map{index in var value=savedAdvice;value.id="fixture-projection-\(index)";return value}
        try model.proactive.seedAdviceFixture(repeated,model:model)
        let repeatedStart=Date.now
        let expected=Set(model.proactive.state.records.filter{model.proactive.visible($0,model:model)}.map(\.id))
        let repeatedMilliseconds=Date.now.timeIntervalSince(repeatedStart)*1000
        let builds=model.proactive.reviewContextBuildCount,projectionStart=Date.now
        let projected=model.reviewInbox
        let sharedMilliseconds=Date.now.timeIntervalSince(projectionStart)*1000
        checks["forty saved suggestions display without constructing AI evidence context"] = model.proactive.reviewContextBuildCount == builds && projected.discoveries.count == 40
        checks["shared review context preserves exact visibility and grouped badge count"] = Set(projected.discoveries.map(\.id)) == expected && projected.emailCards.count == 1 && model.reviewInboxPendingCount == projected.pendingCount
        permitted=false
        checks["supporting memory changes do not erase prepared suggestions"] = model.reviewInbox.discoveries.count == 40
        let presentationBuilds=model.preparedReview.builds
        for _ in 0..<100 {_ = model.reviewInboxPendingCount;_ = model.reviewInbox}
        checks["badge and repeated navigation reuse the same prepared inbox"] = model.preparedReview.builds == presentationBuilds
        let healthBefore=model.reminderHealth
        model.reminderHealth = .init(lastSuccess:now.addingTimeInterval(-7200))
        checks["native freshness does not invalidate prepared presentation"] = model.reviewInbox.discoveries.count == 40 && model.preparedReview.builds == presentationBuilds
        model.reminderHealth=healthBefore
        let excludedBefore=model.assistant.excludedAccounts
        model.assistant.excludedAccounts.insert(message.accountID)
        checks["explicit source withdrawal immediately hides prepared cards"] = model.reviewInbox.discoveries.isEmpty && model.reviewInbox.emailCards.isEmpty
        model.assistant.excludedAccounts=excludedBefore
        checks["restored source access exposes the same saved cards"] = model.reviewInbox.discoveries.count == 40
        permitted=true
        try model.proactive.seedAdviceFixture([savedAdvice],model:model)
        permitted=false
        checks["revocation rejects captured context before a save"] = !model.memoryDependenciesAvailable(capture.dependencies,use:.brief) && capture != model.automaticMemory(.brief)
        checks["revocation removes current advice"]=model.briefings.current(model) == nil && !model.proactive.visible(savedAdvice,model:model)
        checks["dated morning stays inspectable"]=model.briefings.savedToday(model)?.id == morning.id && model.briefings.savedToday(model)?.message == morning.message
        checks["stale morning leaves future AI history"] = !model.briefings.allowsChatDelivery(delivery,content:BriefingRules.prose(morning),model:model)
        model.reviewDiscovery(savedAdvice)
        checks["saved suggestion remains reviewable after supporting memory changed"]=model.editTarget != nil
        model.editTarget=nil
        checks["morning completion and notification claims survive"]=BriefingRules.completedDays(records:model.briefings.state.records,registration:registration) == [morning.day] && model.briefings.state.notificationClaims == [morning.day]
        permitted=true
        checks["matching evidence can become usable again"]=model.briefings.current(model)?.id == morning.id && model.proactive.visible(savedAdvice,model:model)
        _=store.put(.init(registration:registration,text:"I enjoy tennis.",kind:.context,provenance:"Unrelated fictional fact"))
        checks["unrelated facts leave persisted advice valid"]=model.briefings.current(model)?.id == morning.id && model.proactive.visible(savedAdvice,model:model)
        let updateOnly=PAMemory(registration:registration,text:"I may need extra Orion preparation.",kind:.context,explicit:false,provenance:"Fictional provisional context",certainty:.inferred,durability:.situational)
        guard store.put(updateOnly) else { throw SummaryFailure.invalid }
        var partialUpdate=morning;partialUpdate.id="fictional-partial-update";partialUpdate.morningID=morning.id;partialUpdate.created=now.addingTimeInterval(0.5);partialUpdate.memoryDependencies=model.automaticMemory(.brief).dependencies
        try model.briefings.seedAdviceFixture(savedMorning,update:partialUpdate,model:model)
        guard store.forget(updateOnly.id) else { throw SummaryFailure.invalid }
        checks["stale update falls back to independently usable morning"]=model.briefings.current(model)?.id == morning.id
        checks["latest stale update stays inspectable with explanation"]=model.briefings.savedToday(model)?.id == partialUpdate.id && model.briefings.freshnessNote(model.briefings.savedToday(model)!,model:model) != nil
        var corrected=human;corrected.id=UUID();corrected.text="I now prefer preparing two days before.";corrected.evidence=corrected.text
        guard store.correct(human.id,with:corrected) else { throw SummaryFailure.invalid }
        checks["human correction sets old advice aside"]=model.briefings.current(model) == nil && !model.proactive.visible(savedAdvice,model:model)
        var update=morning;update.id="fictional-update";update.morningID=morning.id;update.created=now.addingTimeInterval(1);update.message="Updated preparation advice.";update.memoryDependencies=model.automaticMemory(.brief).dependencies
        try model.briefings.seedAdviceFixture(savedMorning,update:update,model:model)
        checks["fresh update uses original morning identity"]=model.briefings.current(model)?.id == update.id && model.briefings.savedMorning(model)?.id == morning.id
        checks["update keeps original morning text and notification claim"]=model.briefings.state.records[0].message == morning.message && model.briefings.state.notificationClaims == [morning.day]
        var legacy=savedAdvice;legacy.memoryDependencies=nil;legacy.memoryUse=nil;legacy.sourceAssessmentRevision=nil
        try model.proactive.seedAdviceFixture([legacy],model:model)
        let savedLegacy=model.proactive.state.records[0]
        checks["legacy advice remains readable without invented receipts"]=model.proactive.visible(savedLegacy,model:model)
        var changedJSON=json;changedJSON["subject"]="Orion preparation cancelled"
        let changed=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:changedJSON))
        model.mailData = .init(messages:[changed],accounts:model.mailData.accounts,errors:[])
        checks["changed header hides an unchanged legacy assessment"] = !model.proactive.visible(savedLegacy,model:model)
        let request=WhatsAppReadMessage(id:"fictional-request",chat:"fictional-study",sender:"Tutor",text:quote,sentByMe:false,time:now.timeIntervalSince1970*1000)
        let cancel=WhatsAppReadMessage(id:"fictional-cancel",chat:request.chat,sender:"Tutor",text:"The supervision has been cancelled.",sentByMe:false,time:request.time+1000)
        checks["later cancellation changes conversation receipt"]=ProactiveRules.whatsappWindow([request],chats:[request.chat],identity:"fictional-link") != ProactiveRules.whatsappWindow([request,cancel],chats:[request.chat],identity:"fictional-link")
        let study=PAMemory(registration:registration,text:"Alex is entering fourth year of Cambridge Engineering.",kind:.context,provenance:"Fictional human",evidence:"Alex is entering fourth year of Cambridge Engineering.",organisation:.init(areas:[.studies],connections:[],selfName:"Alex"))
        let weather=PAMemory(registration:registration,text:"Include the weather forecast in today's brief.",kind:.preference,provenance:"Fictional human")
        let family=PAMemory(registration:registration,text:"My family live in Newbury.",kind:.context,provenance:"Fictional human")
        checks["relevance fixtures save without replacing existing memory"]=store.put(study) && store.put(weather) && store.put(family)
        let securityQuery=MemoryRetrieval.emailQuery(subject:"Security alert",sender:"Google",body:"Alex: We noticed a new sign-in to your Google Account on a Mac OS device. If this was you, you don't need to do anything. If not, we'll help you secure your account.")
        let securityMemory=model.automaticMemory(.heartbeatSuggestions,query:securityQuery)
        checks["actual automatic security context omits unrelated biography and preferences"]=securityMemory.records.isEmpty && securityMemory.dependencies.isEmpty
        checks["actual email classification context omits unrelated human facts"]=store.context(registration,query:securityQuery,includeSources:false).isEmpty
        checks["actual notebook security input supplies no facts"]=PAContextCapture.notebookIDs(store.notebook(registration).context(query:securityQuery,selectedMemoryIDs:[])).memories.isEmpty
        let university=model.automaticMemory(.heartbeatSuggestions,query:"Cambridge Engineering module selection")
        checks["actual university context keeps the study fact only"]=university.records.map{$0["id"]} == [study.id.uuidString]
        checks["source assessment without a query does not supply a biography"]=model.automaticMemory(.heartbeatSuggestions).records.isEmpty
        checks["broad day planning remains available without editing saved memory"]=model.automaticMemory(.brief).records.contains{$0["id"] == weather.id.uuidString} && store.records.contains{$0.id == family.id && $0.text == family.text}
        checks["fixture uses only its account and starts no native write"]=store.records.allSatisfy{$0.registration == registration} && model.writing == false
        model.mailData = .init(messages:[message],accounts:model.mailData.accounts,errors:[])
        try model.emailSummaries.seedAdviceFixture([summary])
        let acknowledgement=PADiscovery(id:"fictional-ack",registration:registration,mailID:message.id,kind:"reminder",message:"Review the Orion preparation request.",evidence:quote,created:now,scope:"fictional",sourceRevision:summary.fingerprint,sourceAssessmentRevision:summary.adviceRevision(replied:message.replied))
        try model.proactive.seedAdviceFixture([acknowledgement],model:model)
        let beforeAcknowledgement=model.reviewAcknowledgementRevision,nativeBefore=DiscoveryNativeTarget.fingerprint(model.reminderData),memoryBefore=store.revision
        var emptyReceiptBrief=savedMorning
        emptyReceiptBrief.reviewAcknowledgementRevision=beforeAcknowledgement;emptyReceiptBrief.reviewAcknowledgementReceipts=[]
        checks["empty acknowledgement receipts retain all other brief freshness checks"] = model.briefings.freshnessNote(emptyReceiptBrief,model:model) == model.briefings.freshnessNote(emptyReceiptBrief,model:model,checkAcknowledgements:false)
        model.proactive.dismiss(model.proactive.state.records[0],model:model)
        checks["empty acknowledgement receipts cannot bypass changed human choices"] = model.briefings.freshnessNote(emptyReceiptBrief,model:model)?.contains("choices changed") == true
        checks["Dismiss counts as exact acknowledgement without native or memory changes"] = model.reviewAcknowledgementRevision != beforeAcknowledgement && !model.acknowledgedEmail(message,summary) && DiscoveryNativeTarget.fingerprint(model.reminderData) == nativeBefore && store.revision == memoryBefore
        checks["dismissing one proposal preserves independent actions in the same source"] = model.briefings.currentEmails(model).count == 1 && model.proactive.emailReviewCandidates(model,heartbeat:true,mailReview:nil,whatsappReady:false,now:now).count == 1
        let ackRows=model.reviewAcknowledgements()
        let originalAcknowledgement=model.proactive.state.records[0]
        var siblingAcknowledgement=originalAcknowledgement;siblingAcknowledgement.id="fictional-ack-sibling"
        try model.proactive.seedAdviceFixture([originalAcknowledgement,siblingAcknowledgement],model:model)
        let acknowledgementBuilds=model.proactive.reviewContextBuildCount
        let bothAcknowledgements=model.reviewAcknowledgements()
        checks["acknowledgements share one synchronous current evidence projection"] = bothAcknowledgements.contains{$0.id == "discovery:fictional-ack"} && bothAcknowledgements.contains{$0.id == "discovery:fictional-ack-sibling"} && model.proactive.reviewContextBuildCount-acknowledgementBuilds == 1
        try model.proactive.seedAdviceFixture([originalAcknowledgement],model:model)
        let snapshot=model.assistant.snapshot(model).flatMap{try? JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]}
        checks["foreground source context knows the acknowledged concern"] = ackRows.contains{$0.id == "discovery:fictional-ack"} && (snapshot?["reviewAcknowledgements"] as? [[String:Any]])?.contains{$0["id"] as? String == "discovery:fictional-ack"} == true && (snapshot?["savedEmailSummaries"] as? [[String:Any]])?.count == 1
        checks["actual dismissal survives reopening its cache"] = model.proactive.reopenedAcknowledgementFixture().first?.dismissed == true && model.proactive.reopenedAcknowledgementFixture().first?.dismissedSourceVersion != nil
        checks["unavailable Mail lanes supply no acknowledged source prose"] = model.reviewAcknowledgements(use:.brief,mailAccounts:[],whatsappReady:false).isEmpty
        let acknowledgedBrief=DailyBriefing(id:"fictional-ack-brief",registration:registration,day:BriefingRules.day(now),created:now,items:[],sources:[],coverage:"Fictional",message:"The dismissed concern has been seen.",reviewAcknowledgementRevision:model.reviewAcknowledgementRevision,reviewAcknowledgementReceipts:ackRows.map(ReviewAcknowledgementReceipt.init))
        try model.briefings.seedAdviceFixture(acknowledgedBrief,model:model)
        checks["saved brief keeps current acknowledgement support"] = model.briefings.current(model)?.id == acknowledgedBrief.id
        var changedAssessment=summary;changedAssessment.bodyFingerprint="fictional-body-v2"
        try model.emailSummaries.seedAdviceFixture([changedAssessment])
        checks["changed historical negative context preserves an unrelated saved brief"] = model.briefings.current(model)?.id == acknowledgedBrief.id && model.briefings.savedToday(model)?.id == acknowledgedBrief.id && model.reviewAcknowledgements().isEmpty
        try model.emailSummaries.seedAdviceFixture([summary])
        model.proactive.undo(model)
        checks["Undo restores concern and original human-choice revision"] = !model.acknowledgedEmail(message,summary) && model.reviewAcknowledgementRevision == beforeAcknowledgement && model.briefings.currentEmails(model).count == 1
        model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:summary.registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))
        checks["email-work dismissal is acknowledged across contexts"] = model.acknowledgedEmail(message,model.emailSummaries.records[0]) && model.reviewAcknowledgements().contains{$0.id == "email:"+message.id} && model.briefings.currentEmails(model).isEmpty
        model.emailSummaries.undoDismiss(model)
        checks["email-work Undo restores source attention"] = model.briefings.currentEmails(model).count == 1 && model.reviewAcknowledgementRevision == beforeAcknowledgement
        model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:"fictional-other-registration",expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))
        checks["stale registration cannot acknowledge another account's email"] = model.emailSummaries.records[0].dismissed != true
        try model.emailSummaries.seedAdviceFixture([changedAssessment])
        model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))
        checks["stale email card cannot acknowledge changed content"] = model.emailSummaries.records[0].dismissed != true
        let oldProposal=model.proactive.state.records[0]
        model.proactive.dismiss(oldProposal,model:model)
        checks["stale proposal dismissal does not acknowledge newer source content"] = model.proactive.state.records[0].dismissedSourceVersion == nil && model.reviewAcknowledgements().isEmpty

        try model.emailSummaries.seedAdviceFixture([summary])
        checks["feedback accepts only exact current permitted email"] = model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)
        let feedbackOwner=model.emailSummaries.feedbackOwnershipGuard(.init(message:message,summary:summary),model:model,isCurrent:{true})
        let capturedNativeRevision=model.sourceRevision
        model.sourceRevision += 1 // The same invalidation as EKEventStoreChanged during an awaited request.
        checks["feedback ownership survives unrelated EventKit notification during interpretation"] = feedbackOwner() && capturedNativeRevision != model.sourceRevision
        model.mailData = .init(messages:[renamedSender],accounts:model.mailData.accounts,errors:[])
        checks["feedback rejects live header change"] = !model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)
        checks["captured feedback ownership rejects changed email header"] = !feedbackOwner()
        model.mailData = .init(messages:[message],accounts:[],errors:[])
        checks["feedback rejects removed Mail account"] = !model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)
        checks["captured feedback ownership rejects removed Mail account"] = !feedbackOwner()
        model.mailData = .init(messages:[message],accounts:[.init(id:message.accountID,title:message.account)],errors:[])
        try model.emailSummaries.seedAdviceFixture([changedAssessment])
        checks["captured feedback ownership rejects changed email body"] = !feedbackOwner()
        try model.emailSummaries.seedAdviceFixture([summary])
        checks["captured feedback ownership rejects changed human submission"] = !model.emailSummaries.feedbackOwnershipGuard(.init(message:message,summary:summary),model:model,isCurrent:{false})()
        let cancelledFeedbackOwner=model.emailSummaries.feedbackOwnershipGuard(.init(message:message,summary:summary),model:model,isCurrent:{true})
        model.emailSummaries.cancelReviewFeedback()
        checks["captured feedback ownership rejects explicit foreground cancellation"] = !cancelledFeedbackOwner()
        let memoryFeedbackOwner=model.emailSummaries.feedbackOwnershipGuard(.init(message:message,summary:summary),model:model,isCurrent:{true})
        let project=try model.assistant.projects.save(LifeItem(registration:registration,kind:.space,title:"Orion prototype",status:.active),expected:nil)
        let projectContext=model.emailSummaries.relevanceContext(message,model:model)
        checks["header relevance retrieves current project even without matching human facts"] = projectContext.workspace.contains{$0["id"] == "life:"+project.id.uuidString} && projectContext.memories.isEmpty
        let relevantHuman=PAMemory(registration:registration,text:"I am building the Orion prototype this term.",kind:.context,provenance:"Fictional human",evidence:"I am building the Orion prototype this term.")
        guard store.put(relevantHuman) else {throw SummaryFailure.invalid}
        checks["captured feedback ownership tolerates memory never supplied to interpretation"] = memoryFeedbackOwner()
        let relevanceContext=model.emailSummaries.relevanceContext(message,model:model,body:quote)
        checks["email life context selects matching human facts without source facts or biography"] = relevanceContext.memories.contains{$0["id"] == relevantHuman.id.uuidString} && !relevanceContext.memories.contains{$0["id"] == fact.id.uuidString || $0["id"] == human.id.uuidString}
        let supported=try EmailRelevanceRules.validated(.init(reason:"Matches current Orion work",evidence:quote,memoryIDs:[relevantHuman.id.uuidString],workspaceIDs:["life:"+project.id.uuidString],preferenceIDs:[]),context:relevanceContext,message:message,body:quote)
        checks["supported life relevance remains currently usable"] = model.emailSummaries.relevanceAvailable(supported,model:model)
        var newerJSON=json;newerJSON["id"]="fictional-unrelated";newerJSON["received"]=now.addingTimeInterval(60).ISO8601Format()
        let newer=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:newerJSON))
        var taskJSON=newerJSON;taskJSON["id"]="fictional-task"
        let taskMail=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:taskJSON))
        var reading=summary;reading.attention=false;reading.personalRelevance=supported
        var unrelated=summary;unrelated.id=newer.id;unrelated.fingerprint=EmailSummary.fingerprint(newer);unrelated.message=newer;unrelated.attention=false
        var actualTask=summary;actualTask.id=taskMail.id;actualTask.fingerprint=EmailSummary.fingerprint(taskMail);actualTask.message=taskMail
        actualTask.personalRelevance=supported;actualTask.followUpEvidence="Wednesday of week one"
        model.mailData = .init(messages:[message,newer,taskMail],accounts:model.mailData.accounts,errors:[])
        try model.emailSummaries.seedAdviceFixture([reading,unrelated,actualTask])
        checks["current relevance ranks useful reading above newer routine reading while actual tasks stay first"] = model.emailSummaries.highlights(model).map{$0.0.id} == [taskMail.id,message.id,newer.id]
        let taskAssessment=model.emailSummaries.highlights(model).first{$0.0.id == taskMail.id}!.1.adviceRevision(replied:false)
        var renamedProject=project;renamedProject.title="Orion renamed"
        _ = try model.assistant.projects.save(renamedProject,expected:project.revision)
        checks["project change withdraws saved relevance boost"] = !model.emailSummaries.relevanceAvailable(supported,model:model)
        checks["stale life-only reading is withheld from current brief input"] = !model.briefings.currentEmails(model).contains{$0.0.id == message.id}
        checks["date-clarified actionable assessment also invalidates withdrawn life relevance"] = model.emailSummaries.highlights(model).first{$0.0.id == taskMail.id}!.1.adviceRevision(replied:false) != taskAssessment
        model.mailData = .init(messages:[message],accounts:model.mailData.accounts,errors:[])
        try model.emailSummaries.seedAdviceFixture([summary])
        let beforePreference=model.assistant.memory.revision
        let preferenceID=UUID()
        guard model.assistant.memory.saveReviewPreference("Prioritise useful Orion prototype updates.",registration:registration,about:"Orion prototype",id:preferenceID) else {throw SummaryFailure.invalid}
        let savedPreference=model.assistant.memory.records.first{$0.id == preferenceID}!
        let matching=PAWorkingContext.prepare(memory:model.assistant.memory,registration:registration,purpose:.emailBody,query:"Orion update")
        let unrelatedContext=PAWorkingContext.prepare(memory:model.assistant.memory,registration:registration,purpose:.emailBody,query:"Unrelated shopping discount")
        checks["canonical preference changes context and matches only its topic"] = model.assistant.memory.revision != beforePreference && matching.memoryIDs.contains(preferenceID) && !unrelatedContext.memoryIDs.contains(preferenceID)
        var outdated=savedPreference;outdated.text="Stale editor text"
        checks["stale preference editor cannot overwrite canonical memory"] = !model.assistant.memory.saveReviewPreference("Changed",registration:registration,expected:outdated)
        checks["preference account ownership is captured"] = !model.assistant.memory.saveReviewPreference("Changed",registration:"fictional-other",expected:savedPreference)
        checks["disabled canonical preference leaves every context consumer"] = model.assistant.memory.retire(savedPreference.id,retired:true,expectedRevision:model.assistant.memory.revision) && !PAWorkingContext.prepare(memory:model.assistant.memory,registration:registration,purpose:.conversation,query:"Orion prototype").memoryIDs.contains(preferenceID)
        let isolated=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let legacyPreferenceFixture=ReviewRelevancePreference(registration:registration,topic:"Fictional old topic",direction:"more")
        try LocalRecordRepository(container:isolated).save([legacyPreferenceFixture],key:"reviewRelevancePreferences")
        let converted=PAMemoryStore(container:isolated)
        let legacyPreferenceFixtureRemoved = try LocalRecordRepository.read("reviewRelevancePreferences",container:isolated) == nil
        checks["legacyPreferenceFixture preferences convert once into canonical storage"] = converted.records.contains{$0.id == legacyPreferenceFixture.id && $0.reviewPreference == true} && legacyPreferenceFixtureRemoved
        let reopened=PAMemoryStore(container:isolated)
        checks["converted preference and original receipt proof reopen"] = reopened.matchesConvertedReviewPreference(id:legacyPreferenceFixture.id.uuidString,revision:legacyPreferenceFixture.revision.uuidString,registration:registration,direction:"more") && reopened.records.count == converted.records.count
        let invalidStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let invalidBytes=try JSONEncoder().encode([legacyPreferenceFixture,legacyPreferenceFixture]);try LocalRecordRepository(container:invalidStore).write(["reviewRelevancePreferences":invalidBytes])
        let invalid=PAMemoryStore(container:invalidStore)
        let invalidRetained = try LocalRecordRepository.read("reviewRelevancePreferences",container:invalidStore) == invalidBytes
        checks["invalid saved preferences are blocked and preserved without exposure"] = !invalid.reviewPreferenceMigrationReadable && invalid.records.isEmpty && invalidRetained
        try model.proactive.seedAdviceFixture([],model:model)
        try ReviewInboxEvaluation.seedEmailWorkPreview(model)
        let words="Assessment submission confirmations can stay quiet. Assessment invitations and results are important to me."
        guard model.assistant.memory.saveReviewPreference(words,registration:registration) else {throw SummaryFailure.invalid}
        let reviewMemory=model.assistant.memory.reviewPreferences(registration).first!
        var example=model.mailData.messages[0]
        let assessmentRaw:[String:Any]=["id":"feedback-assessment","accountID":"fictional-mail","account":"Fictional Mail","messageID":10,"internetMessageID":"feedback-assessment@example.invalid","sender":"Assessment portal <fixture@example.invalid>","subject":"Orion Labs coding assessment invitation","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        example=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:assessmentRaw))
        let feedbackContext=model.emailSummaries.relevanceContext(example,model:model,body:"Please complete your Orion Labs coding assessment.")
        checks["human feedback reaches actual assessment header and body with exact memory receipts"] = feedbackContext.memories.contains{$0["id"] == reviewMemory.id.uuidString && $0["text"] == words} && feedbackContext.memoryReceipts.contains{$0.id == reviewMemory.id.uuidString} && model.emailSummaries.relevanceContext(example,model:model,header:true).memories.contains{$0["id"] == reviewMemory.id.uuidString}
        checks["feedback does not fill unrelated email context"] = !model.emailSummaries.relevanceContext(model.mailData.messages[0],model:model,body:"Orion project review attendance").memories.contains{$0["id"] == reviewMemory.id.uuidString}
        var currentAssessment=EmailSummary(id:example.id,registration:registration,fingerprint:EmailSummary.fingerprint(example),summary:"Coding assessment invitation",attention:true,reason:"Complete coding assessment",evidence:"Please complete your Orion Labs coding assessment.",bodyFingerprint:"fixture",message:example,worthReading:true,needsReply:false,reviewPreferenceRevision:model.emailSummaries.reviewPreferenceStamp(example,model:model,evidence:"Coding assessment invitation Please complete your Orion Labs coding assessment."),reviewPolicyVersion:2)
        currentAssessment.reviewContext = .init(policy:model.emailSummaries.policy(registration),memories:feedbackContext.memories,discoveryRevision:currentAssessment.reviewPreferenceRevision,contextPageDependencies:feedbackContext.contextPageDependencies)
        checks["unchanged feedback does not repeatedly reassess saved email"] = !model.emailSummaries.preferenceNeedsRecheck(currentAssessment,message:example,model:model)
        guard model.assistant.memory.saveReviewPreference("Assessment invitations matter; successful submission confirmations do not need review.",registration:registration,expected:reviewMemory) else {throw SummaryFailure.invalid}
        checks["edited feedback schedules bounded reconsideration and invalidates old exact support"] = model.emailSummaries.preferenceNeedsRecheck(currentAssessment,message:example,model:model) && !model.memoryDependenciesAvailable(feedbackContext.memoryReceipts,use:.suggestions)
        currentAssessment.dismissed=true;currentAssessment.dismissedSourceVersion=ReviewAcknowledgementRules.emailVersion(example,currentAssessment)
        checks["feedback changes do not resurrect acknowledged concerns"] = !model.emailSummaries.preferenceNeedsRecheck(currentAssessment,message:example,model:model)
        let revisedReview=model.assistant.memory.reviewPreferences(registration).first!
        guard model.assistant.memory.retire(revisedReview.id,retired:true,expectedRevision:model.assistant.memory.revision) else {throw SummaryFailure.invalid}
        checks["disabled feedback leaves current input but retains original human evidence"] = !model.emailSummaries.relevanceContext(example,model:model).memories.contains{$0["id"] == revisedReview.id.uuidString} && model.assistant.memory.lineage(revisedReview.id).count == 2
        guard model.assistant.memory.saveReviewPreference("These can stay quiet, but invitations and new deadlines matter.",registration:registration,about:"Assessment submission confirmations") else {throw SummaryFailure.invalid}
        let contextualReview=model.assistant.memory.reviewPreferences(registration).first!
        let contextualInput=model.emailSummaries.relevanceContext(example,model:model,body:"Please complete your coding assessment.")
        checks["contextual feedback retains its human-confirmed topic in actual targeted input"] = contextualInput.memories.contains{$0["id"] == contextualReview.id.uuidString && $0["text"] == "These can stay quiet, but invitations and new deadlines matter." && $0["reviewAbout"] == "Assessment submission confirmations"}
        guard model.assistant.memory.retire(contextualReview.id,retired:true,expectedRevision:model.assistant.memory.revision) else {throw SummaryFailure.invalid}
        let reviewBase=model.reviewInboxPendingCount
        checks["review badge counts actionable email and excludes planned and completed email"] = reviewBase == 1 && model.reviewInbox.emails.count == 1 && model.reviewInbox.handled.count == 2
        checks["sidebar count-only path agrees with the full Review projection"] = model.reviewInboxPendingCount == model.reviewInbox.pendingCount
        let orientationHealth=model.paOrientationHealth,reminderHealth=model.reminderHealth
        model.paOrientationHealth = .init(lastSuccess:now.addingTimeInterval(-601));model.reminderHealth = .init(lastSuccess:now.addingTimeInterval(-601))
        checks["aged native caches retain saved heartbeat handling decisions"] = model.reviewInboxPendingCount == reviewBase && model.reviewInboxPendingCount == model.reviewInbox.pendingCount
        model.paOrientationHealth=orientationHealth;model.reminderHealth=reminderHealth
        checks["refreshed native evidence restores the current badge count"] = model.reviewInboxPendingCount == reviewBase
        let reviewMail=model.reviewInbox.emails[0]
        model.emailSummaries.dismiss(reviewMail.0.id,model:model,expectedRegistration:registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(reviewMail.0,reviewMail.1))
        checks["review badge immediately drops a dismissed concern"] = model.reviewInbox.pendingCount == reviewBase-1
        model.emailSummaries.undoDismiss(model)
        checks["review badge restores dismissed concern on Undo"] = model.reviewInbox.pendingCount == reviewBase
        let completedEmail=model.reviewInbox.handled.first{$0.0.id == "preview-2"}!
        var bad=completedEmail.1;bad.handling?.native.title="Check whether risk assessment is required and complete it if needed"
        checks["unrelated legacy assessment association is withheld without deleting its receipt"] = model.emailSummaries.handling(bad,message:completedEmail.0,model:model) == nil && bad.handling != nil
        var quiet=completedEmail.1;quiet.attention=false
        checks["informational confirmation cannot be marked handled by a native task"] = model.emailSummaries.handling(quiet,message:completedEmail.0,model:model) == nil
        let handledMail=model.reviewInbox.handled[0]
        model.emailSummaries.keepForReview(handledMail.1.id,model:model)
        checks["Keep in review restores a handled email to the count"] = model.reviewInbox.pendingCount == reviewBase+1
        model.emailSummaries.keepForReview(handledMail.1.id,model:model,keep:false)
        var proposal=PADiscovery(id:UUID().uuidString,registration:registration,mailID:reviewMail.0.id,kind:"reminder",message:"Review the separate Orion reminder proposal.",evidence:reviewMail.1.evidence,created:now,scope:"fictional",sourceRevision:reviewMail.1.fingerprint,sourceAssessmentRevision:reviewMail.1.adviceRevision(replied:false))
        try model.proactive.seedAdviceFixture([proposal],model:model)
        proposal=model.proactive.state.records[0]
        checks["email and proposal share one card and one badge item"] = model.reviewInbox.pendingCount == reviewBase && model.reviewInbox.emailCards.count == 1 && model.reviewInbox.emailCards[0].discoveries == [proposal] && model.reviewInbox.standaloneDiscoveries.isEmpty
        var groupedUpdate=proposal;groupedUpdate.id=UUID().uuidString;groupedUpdate.kind="update";groupedUpdate.message="The Orion review has additional background context."
        try model.proactive.seedAdviceFixture([proposal,groupedUpdate],model:model)
        checks["additional background context retains its receipt inside the same email card"] = model.reviewInbox.pendingCount == reviewBase && model.reviewInbox.emailCards[0].discoveries.count == 2 && model.proactive.state.records.count == 2
        model.proactive.dismiss(groupedUpdate,model:model)
        checks["dismissing one attached concern preserves the email and sibling action"] = model.reviewInbox.emailCards.count == 1 && model.reviewInbox.emailCards[0].discoveries == [proposal] && model.reviewInbox.pendingCount == reviewBase
        model.proactive.undo(model)
        checks["attached concern Undo restores the original group without another card"] = model.reviewInbox.emailCards[0].discoveries.count == 2 && model.reviewInbox.pendingCount == reviewBase
        model.emailSummaries.dismiss(reviewMail.0.id,model:model,expectedRegistration:registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(reviewMail.0,reviewMail.1))
        checks["whole-email dismissal clears the combined card without deleting proposal receipts"] = model.reviewInbox.emailCards.isEmpty && model.reviewInbox.standaloneDiscoveries.isEmpty && model.proactive.state.records.count == 2
        model.emailSummaries.undoDismiss(model)
        checks["whole-email Undo restores all attached concerns once"] = model.reviewInbox.emailCards.count == 1 && model.reviewInbox.emailCards[0].discoveries.count == 2 && model.reviewInbox.pendingCount == reviewBase
        try model.proactive.seedAdviceFixture([proposal],model:model)
        let creationRequest=NativeCreationRequest(id:UUID(uuidString:proposal.id)!,kind:.reminder,registration:registration)
        try model.nativeCreations.begin(creationRequest)
        checks["uncertain native save remains inside the counted card for outcome checking"] = model.reviewInbox.pendingCount == reviewBase && model.reviewCreationClaim(proposal)?.receipt == nil && model.reviewCreationClaim(proposal) != nil && model.reviewInbox.emailCards[0].discoveries == [proposal]
        try model.nativeCreations.complete(creationRequest,receipt:.init(requestID:creationRequest.id,registration:registration,kind:.reminder,itemID:"fictional-saved-reminder",title:"Fictional Orion reminder",destination:"Fixture",created:now,sourceScope:"fictional-list"))
        checks["verified creation leaves active Review while preserving its canonical receipt"] = model.reviewInbox.pendingCount == reviewBase && model.reviewInbox.discoveries.isEmpty && model.proactive.state.records.count == 1 && model.reviewCreationClaim(proposal)?.receipt != nil
        let planned=model.reviewInbox.handled.first{$0.0.id == "preview-1"}!
        var plannedProposal=proposal;plannedProposal.id=UUID().uuidString;plannedProposal.mailID=planned.0.id;plannedProposal.kind="remove";plannedProposal.evidence=planned.1.evidence
        plannedProposal.sourceRevision=planned.1.fingerprint;plannedProposal.sourceAssessmentRevision=planned.1.adviceRevision(replied:planned.0.replied)
        plannedProposal.proposedRemoval = .init(target:.event(model.paOrientation!.calendar.events[0],writable:true),connection:"Fictional separate proposal for the same exact review.",timeZoneID:TimeZone.current.identifier)
        try model.proactive.seedAdviceFixture([proposal,plannedProposal],model:model)
        checks["grouped native proposal retains planned context without a second history card"] = model.reviewInbox.emailCards.first{$0.id == planned.0.id}?.handling == planned.2 && !model.reviewInbox.handled.contains{$0.0.id == planned.0.id} && model.reviewInbox.pendingCount == reviewBase+1
        var uncertain=plannedProposal;uncertain.id=UUID().uuidString;uncertain.kind="reminder";uncertain.proposedRemoval=nil
        try model.proactive.seedAdviceFixture([uncertain],model:model)
        try model.nativeCreations.begin(.init(id:UUID(uuidString:uncertain.id)!,kind:.reminder,registration:registration))
        checks["native handled status cannot hide an uncertain canonical creation claim"] = model.proactive.visible(uncertain,model:model) && !model.proactive.canReview(uncertain.id,model:model) && model.proactive.sourceDetails(uncertain,model:model) != nil
        try model.proactive.seedAdviceFixture([plannedProposal],model:model)
        model.emailSummaries.keepForReview(planned.1.id,model:model)
        checks["Keep in review still overrides planned context on a grouped card"] = model.reviewInbox.emailCards.first{$0.id == planned.0.id}?.handling == nil && model.reviewInbox.emailCards.first{$0.id == planned.0.id}?.needsReview == true
        model.emailSummaries.keepForReview(planned.1.id,model:model,keep:false)
        let savedAssessments=model.emailSummaries.records
        var informational=reviewMail.1;informational.attention=false;informational.needsReply=false;informational.worthReading=false;informational.replyDraft=nil
        var completedProposal=proposal;completedProposal.id=UUID().uuidString;completedProposal.sourceAssessmentRevision=informational.adviceRevision(replied:false)
        try model.emailSummaries.seedAdviceFixture([informational]);try model.proactive.seedAdviceFixture([completedProposal],model:model)
        let completedRequest=NativeCreationRequest(id:UUID(uuidString:completedProposal.id)!,kind:.reminder,registration:registration)
        try model.nativeCreations.begin(completedRequest)
        try model.nativeCreations.complete(completedRequest,receipt:.init(requestID:completedRequest.id,registration:registration,kind:.reminder,itemID:"fictional-completed-only",title:"Fictional created reminder",destination:"Fixture",created:now,sourceScope:"fictional-list"))
        checks["completed-only quiet email group leaves the inbox with its receipt preserved"] = model.reviewInbox.emailCards.isEmpty && model.reviewInbox.pendingCount == 0 && model.reviewCreationClaim(completedProposal)?.receipt != nil
        informational.worthReading=true
        try model.emailSummaries.seedAdviceFixture([informational])
        checks["older informational reading judgements await quiet-policy recheck without filling Review"] = model.reviewInbox.emailCards.isEmpty && model.reviewInbox.pendingCount == 0 && model.emailSummaries.records.count == 1
        informational.reviewPolicyVersion=2
        try model.emailSummaries.seedAdviceFixture([informational])
        checks["freshly assessed worthwhile reading appears once without an invented task"] = model.reviewInbox.emailCards.count == 1 && model.reviewInbox.pendingCount == 1 && model.reviewInbox.emailCards[0].summary.attention == false
        try model.emailSummaries.seedAdviceFixture(savedAssessments);try model.proactive.seedAdviceFixture([proposal],model:model)
        _=model.assistant.queue.add(registration:registration,topicID:nil,prompt:"Fictional delegated work")
        let queued=model.assistant.queue.items.last!
        checks["ordinary queued work does not need human review"] = model.reviewInbox.pendingCount == reviewBase
        _=model.assistant.queue.mark(queued.id,.running)
        checks["running delegated work does not inflate review count"] = model.reviewInbox.pendingCount == reviewBase
        _=model.assistant.queue.mark(queued.id,.needsAnswer)
        checks["delegated question counts as needing review"] = model.reviewInbox.pendingCount == reviewBase+1
        _=model.assistant.queue.mark(queued.id,.interrupted)
        checks["interrupted delegated work counts as needing review"] = model.reviewInbox.pendingCount == reviewBase+1
        _=model.assistant.queue.mark(queued.id,.completed)
        checks["completed delegated work leaves review count"] = model.reviewInbox.pendingCount == reviewBase
        let reviewMailData=model.mailData;model.mailData = .init(messages:reviewMailData.messages,accounts:[],errors:[])
        checks["removed account withdraws unsupported review count"] = model.reviewInbox.pendingCount == 0
        model.mailData=reviewMailData
        checks.merge(try resolutionConsumerChecks(model),uniquingKeysWith:{$1})
        if let text=model.assistant.foregroundSnapshot(model),let orientation=try JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any] {
            checks["foreground orientation omits bulk Calendar, Reminders and email bodies"] = orientation["events"] == nil && orientation["reminders"] == nil && orientation["savedEmailSummaries"] == nil && orientation["recentEmailHeaders"] == nil
            checks["foreground orientation retains acknowledgements without a second preference payload"] = orientation["reviewAcknowledgements"] != nil && orientation["resolvedEmailRequests"] != nil && orientation["attentionPreferences"] == nil
            checks["foreground orientation marks source IDs as metadata and exposes typed detail reads"] = (orientation["coverage"] as? String)?.contains("not issued mutation") == true && (orientation["coverage"] as? String)?.contains("read_calendar/read_reminders") == true
            let accounts=orientation["mailAccounts"] as? [[String:String]] ?? []
            checks["foreground orientation excludes withdrawn Mail accounts"] = accounts.allSatisfy{row in row["id"].map{!model.assistant.excludedAccounts.contains($0)} == true}
        } else {checks["foreground orientation is available for permitted context"]=false}
        checks.merge(try activityOutcomeChecks(model),uniquingKeysWith:{$1})
        return ["projectionPerformance":["suggestions":40,"individualChecksMilliseconds":repeatedMilliseconds,"sharedProjectionMilliseconds":sharedMilliseconds],"completed":Date.now.ISO8601Format(),"requests":0,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"storage":"Fictional claims, messages and outputs in disposable SwiftData before source startup. No inference, native writes, permission changes or personal store writes. This tests actual consumer projections, not scheduler races or real message delivery."]
    }
}
#endif
