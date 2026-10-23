import SwiftUI

struct AIActivityNavigation:Identifiable {var id=UUID();var registration:String;var widgetID:UUID;var projectID:UUID?}

@MainActor extension DashboardModel {
    func classifyAssistantOutcome(_ outcome:AssistantTurnOutcome)->(phase:ReviewWorkPhase,message:String,actions:Int,error:String?) {
        let phase=ReviewWorkPhase(rawValue:outcome.phase) ?? .failed
        let failures=outcome.errors.filter{!$0.isEmpty}
        let message=failures.isEmpty ? (phase == .completed && outcome.confirmedActions > 0 ? AIActivityWork.completed(outcome.attemptedTools,receipts:outcome.receipts,confirmed:outcome.confirmedActions) : outcome.message) : failures.joined(separator:" · ")
        return (phase,message,outcome.confirmedActions,failures.isEmpty ? nil : message)
    }
    func assistantActivityStarted(_ outcome:AssistantTurnOutcome) {
        guard AIActivityWork.includes(outcome.attemptedTools,confirmed:outcome.confirmedActions,unconfirmed:outcome.unconfirmedActions) else {return}
        if aiActivity.state.records.contains(where:{$0.registration == outcome.registration && $0.id == "action:"+outcome.responseTurnID.uuidString}) {return}
        let created=assistant.activityContext(outcome.conversationID)?.turnDates[outcome.humanTurnID] ?? .now
        _=aiActivity.upsert(.init(id:"action:"+outcome.responseTurnID.uuidString,registration:outcome.registration,kind:.action,state:.running,title:"3PO actions",message:"Working on your request…",created:created,destination:.assistant(targetID:outcome.conversationID.uuidString)))
    }
    func heartbeatActivityStarted(_ registration:String,_ id:String,_ date:Date) {
        _=aiActivity.upsert(.init(id:"heartbeat:"+id,registration:registration,kind:.heartbeat,state:.running,title:"Heartbeat",message:"Heartbeat running…",created:date,destination:.heartbeat(targetID:id)))
    }
    func assistantActivityFinished(_ outcome:AssistantTurnOutcome) {
        guard AIActivityWork.includes(outcome.attemptedTools,confirmed:outcome.confirmedActions,unconfirmed:outcome.unconfirmedActions) else {return}
        let result=classifyAssistantOutcome(outcome)
        let state=AIActivityStatus(rawValue:result.phase.rawValue) ?? (result.phase == .completed ? .succeeded : .failed)
        let created=assistant.activityContext(outcome.conversationID)?.turnDates[outcome.humanTurnID] ?? .now
        let message=state == .succeeded ? AIActivityWork.completed(outcome.attemptedTools,receipts:outcome.receipts,confirmed:outcome.confirmedActions) : state == .uncertain ? "A save needs checking. "+(result.error ?? "Confirmed actions are retained; the unconfirmed action will not be repeated.") : result.message
        _=aiActivity.upsert(.init(id:"action:"+outcome.responseTurnID.uuidString,registration:outcome.registration,kind:.action,state:state,title:"3PO actions",message:message,created:created,finished:.now,destination:.assistant(targetID:outcome.conversationID.uuidString)))
    }
    func reviewJobChanged(_ job:ReviewWorkJob) {
        let state=AIActivityStatus(rawValue:job.phase.rawValue) ?? (job.phase == .completed ? .succeeded : .failed)
        let message=job.phase == .queued ? "Queued · "+job.source.title : job.phase == .running ? "Working on "+job.source.title : [job.message,job.error].compactMap{$0}.joined(separator:" · ")
        let eventID="review:"+job.id.uuidString+":"+job.responseTurnID.uuidString
        let old=aiActivity.state.records.first{$0.registration == job.scope.registration && $0.id == eventID}
        let tools=assistant.activityContext(job.conversationID)?.attemptedTools[job.responseTurnID] ?? []
        let work=job.mode == .approval || AIActivityWork.includes(tools,confirmed:job.savedCount)
        if job.phase != .queued,(work || old != nil),!(state == .running && old?.state == .running) {
            _=aiActivity.upsert(.init(id:eventID,registration:job.scope.registration,kind:.review,state:state,title:job.source.title,message:state == .running ? "Working on "+job.source.title : message.isEmpty ? state.title : message,created:job.created,finished:job.finished,destination:.review(targetID:job.conversationID.uuidString)))
        }
        if job.phase.isFinished,!reviewWork.busy {assistant.continueForegroundAfterReview(runtime:assistantRuntime())}
        if job.mode == .approval,job.phase.isFinished {
            _=assistant.appendReview(job.human,conversationID:job.conversationID,turnID:job.humanTurnID,human:true)
            _=assistant.appendReview(message,conversationID:job.conversationID,turnID:job.responseTurnID)
        }
    }
    func reviewActivityStarted(_ job:ReviewWorkJob,outcome:AssistantTurnOutcome) {
        guard AIActivityWork.includes(outcome.attemptedTools),reviewPermits(job.source) else {return}
        let id="review:"+job.id.uuidString+":"+job.responseTurnID.uuidString
        guard !aiActivity.state.records.contains(where:{$0.registration == job.scope.registration && $0.id == id}) else {return}
        _=aiActivity.upsert(.init(id:id,registration:job.scope.registration,kind:.review,state:.running,title:job.source.title,message:"Working on "+job.source.title,created:job.created,destination:.review(targetID:job.conversationID.uuidString)))
    }
    func heartbeatActivityFinished(_ registration:String,_ run:PAReviewRun) {
        let failed=run.failure != nil || ["failed","interrupted","suspended","paused"].contains(run.phase)
        let state:AIActivityStatus=run.phase == "suspended" || run.phase == "interrupted" ? .interrupted : run.phase == "paused" ? .stopped : failed ? (run.briefUpdated == true ? .partial : .failed) : .succeeded
        let message=[run.summary,run.failure].compactMap{$0}.joined(separator:" · ")
        _=aiActivity.upsert(.init(id:"heartbeat:"+run.id,registration:registration,kind:.heartbeat,state:state,title:"Heartbeat",message:message,progress:state == .succeeded ? 1 : nil,created:run.started,finished:run.finished,destination:.heartbeat(targetID:run.id)))
        scheduleReviewWork()
    }
    var currentAIActivity:AIActivityRecord? {
        let registration=chatGPT.activeID
        let records=aiActivity.state.records
        if heartbeat.busy,heartbeat.activeRegistration == registration,let runID=heartbeat.ownedRunID {
            let progress=heartbeat.progress.flatMap{$0.runID == runID ? $0 : nil}
            let eventID="heartbeat:"+runID
            let saved=records.first{$0.registration == registration && $0.id == eventID && $0.kind == .heartbeat}
            let started=saved?.created ?? heartbeat.state.accounts[registration]?.reviews?.first{$0.id == runID}?.started ?? .now
            return .init(id:eventID,registration:registration,kind:.heartbeat,state:.running,title:"Heartbeat",message:progress?.stage ?? heartbeat.status,progress:progress.map{Double($0.percentage)/100},created:started,destination:.heartbeat(targetID:runID))
        }
        if let id=reviewWork.activeID,let job=reviewWork.job(id),job.scope.registration == registration,job.phase == .running,reviewPermits(job.source) {
            let tools=assistant.activityContext(job.conversationID)?.attemptedTools[job.responseTurnID] ?? []
            guard job.mode == .approval || AIActivityWork.includes(tools) else {return nil}
            let eventID="review:"+job.id.uuidString+":"+job.responseTurnID.uuidString
            let message=job.mode == .approval ? "Saving actions · \(job.savedCount) of \(job.actions.count)" : AIActivityWork.running(tools)
            return .init(id:eventID,registration:registration,kind:.review,state:.running,title:job.source.title,message:message,progress:job.mode == .approval && !job.actions.isEmpty ? Double(job.savedCount)/Double(job.actions.count) : nil,created:job.created,destination:.review(targetID:job.conversationID.uuidString))
        }
        if assistant.busy,let turnID=assistant.requestTurnID,
           let saved=records.first(where:{$0.registration == registration && ($0.kind == .action && $0.id == "action:"+turnID.uuidString || $0.kind == .review && $0.id.hasSuffix(":"+turnID.uuidString))}),activityVisible(saved) {
            var current=saved
            current.state = .running;current.finished=nil;current.progress=nil
            current.message=assistant.toolStatus.isEmpty ? saved.message : assistant.toolStatus
            return current
        }
        if let id=emailSummaries.feedback.activeID,
           let job=emailSummaries.feedback.records.first(where:{$0.id == id && $0.registration == registration && [.learning,.saving].contains($0.state)}) {
            let eventID="feedback:"+job.id.uuidString+(job.activityAttemptID.map{":"+$0.uuidString} ?? "")
            let current=AIActivityRecord(id:eventID,registration:registration,kind:.feedback,state:.running,title:job.about.isEmpty ? "Review feedback" : job.about,message:job.status,created:job.created,destination:.feedback(targetID:job.id.uuidString))
            return activityVisible(current) ? current : nil
        }
        return nil
    }
    func syncFeedbackActivity() {
        for job in emailSummaries.feedback.items(chatGPT.activeID) {
            let status:AIActivityStatus
            switch job.state {case .queued:status = .queued;case .learning,.saving:status = .running;case .saved:status = .succeeded;case .failed:status = .failed;case .interrupted:status = .interrupted;case .stopped:status = .stopped}
            let message=job.error ?? (status == .succeeded ? "Your feedback was saved" : status == .queued ? "Feedback queued for the next heartbeat" : "Working on your feedback…")
            _=aiActivity.upsert(.init(id:"feedback:"+job.id.uuidString+(job.activityAttemptID.map{":"+$0.uuidString} ?? ""),registration:job.registration,kind:.feedback,state:status,title:job.about.isEmpty ? "Review feedback" : job.about,message:message,created:job.created,destination:.feedback(targetID:job.id.uuidString)))
        }
    }
    func reviewCompletedActions(_ source:ReviewWorkSource)->Int {
        guard reviewPermits(source) else {return 0}
        let saved=Set(proactive.state.records.filter{$0.registration == chatGPT.activeID && reviewSource($0).key == source.key && reviewDiscoveryCompleted($0)}.map(\.id))
        let work=reviewWork.jobs(chatGPT.activeID).filter{$0.source.key == source.key}
        return saved.union(work.flatMap{$0.actions.filter{$0.phase == .saved}.map(\.id)}).count+work.filter{$0.mode == .conversation}.reduce(0){$0+($1.conversationActionCount ?? 0)}
    }
    func openReviewSource(_ message:MailMessage) {
        let records=proactive.state.records.filter{$0.registration == chatGPT.activeID && $0.mailID == message.id && $0.sourceKind != "whatsapp"}
        if !records.isEmpty {openReviewConversation(records);return}
        let source=ReviewWorkSource(key:"mail:"+message.id,title:message.subject,kind:"mail",accountID:message.accountID,messageID:message.id)
        guard reviewPermits(source) else {return}
        let summary=emailSummaries.records.first{$0.id == message.id && $0.registration == chatGPT.activeID}
        let seeds=summary.map{[AssistantTurn(role:"assistant",content:$0.summary,completed:true,deliveryID:"summary:"+message.id)]} ?? []
        guard let id=assistant.openReview(key:source.key,title:source.title,sourceKind:source.kind,accountID:source.accountID,messageID:source.messageID,identity:nil,chatID:nil,seeds:seeds) else {return}
        reviewPresentation = .init(id:id)
    }
    func activityVisible(_ record:AIActivityRecord)->Bool {
        guard record.registration == chatGPT.activeID else {return false}
        if record.kind == .chat {
            guard record.id.hasPrefix("chat:"),let turn=UUID(uuidString:String(record.id.dropFirst(5))),case let .assistant(id)=record.destination,let id,let conversation=UUID(uuidString:id),let context=assistant.activityContext(conversation) else {return false}
            return AIActivityWork.includes(context.attemptedTools[turn] ?? [])
        }
        if case let .review(id)=record.destination,let id,let uuid=UUID(uuidString:id) {
            guard let context=assistant.activityContext(uuid),let key=context.reviewKey else {return false}
            if record.kind == .review {
                let event=record.id.hasPrefix("review:") ? String(record.id.dropFirst(7)).split(separator:":",omittingEmptySubsequences:false) : []
                guard let first=event.first,let jobID=UUID(uuidString:String(first)),let job=reviewWork.job(jobID) else {return false}
                let responseID=event.count == 2 ? UUID(uuidString:String(event[1])) : nil
                guard job.mode == .approval || responseID.map({AIActivityWork.includes(context.attemptedTools[$0] ?? [],confirmed:$0 == job.responseTurnID ? job.savedCount : 0)}) == true else {return false}
            }
            return reviewPermits(.init(key:key,title:context.title,kind:context.reviewSourceKind ?? "mail",accountID:context.reviewAccountID,messageID:context.reviewMessageID,identity:context.reviewSourceIdentity,chatID:context.reviewSourceChatID))
        }
        if case let .feedback(id)=record.destination,let id,let uuid=UUID(uuidString:id),let job=emailSummaries.feedback.records.first(where:{$0.id == uuid && $0.registration == chatGPT.activeID}) {return reviewPermits(.init(key:"mail:"+job.messageID,title:job.about,kind:"mail",accountID:job.accountID,messageID:job.messageID))}
        return record.registration == chatGPT.activeID
    }
    func activityPresentation(_ record:AIActivityRecord)->AIActivityRecord {
        guard record.registration == chatGPT.activeID else {return record}
        if case let .assistant(id)=record.destination,let conversation=id.flatMap(UUID.init(uuidString:)),let context=assistant.activityContext(conversation) {
            if context.resolvedActivityIDs.contains(record.id) {
                var result=record;result.state = .resolved;result.message="Resolved by a later correction";return result
            }
            if record.id.hasPrefix("action:"),let response=UUID(uuidString:String(record.id.dropFirst(7))),let outcome=context.actionResults[response],outcome.succeeded,(context.unresolvedActionErrors[response] ?? []).isEmpty {
                var result=record;result.state = .succeeded;result.message=AIActivitySummary.text(outcome.receipts.joined(separator:" · "));return result
            }
        }
        if record.state == .succeeded {
            var result=record
            if record.kind == .review {
                let parts=record.id.split(separator:":")
                if parts.count == 3,let id=UUID(uuidString:String(parts[1])),let response=UUID(uuidString:String(parts[2])),let job=reviewWork.job(id),job.responseTurnID == response,job.phase == .completed {
                    let saved=job.actions.filter{$0.phase == .saved}
                    if job.savedCount == 1,let action=saved.first,let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload) {
                        let label:String
                        if let baseline=payload.nativeBaseline {label=(baseline.kind == .event ? "Calendar event" : "Reminder")+(payload.nativeOperation == "remove" ? " removed" : " updated")}
                        else if let request=payload.nativeRequest {label=request.kind == .event ? "Calendar event created" : "Reminder created"}
                        else if let project=payload.project {label=project.kind == .space ? "Space created" : "Task created"}
                        else if payload.localDraft != nil {label="Reply draft copied"}
                        else {return result}
                        let title=payload.project?.title ?? payload.nativeFields?.title ?? payload.nativeBaseline?.title ?? action.title
                        result.message=payload.localDraft != nil ? label : label+": "+title
                        return result
                    }
                }
            }
            var hint:String?
            if case let .review(id)=record.destination,let conversation=id.flatMap(UUID.init(uuidString:)) {
                let parts=record.id.split(separator:":")
                if parts.count == 3,let response=UUID(uuidString:String(parts[2])) {
                    let tools=assistant.activityContext(conversation)?.attemptedTools[response] ?? []
                    if tools.contains("change_reminder"),!tools.contains("change_calendar") {hint="Reminder"}
                    else if tools.contains("change_calendar"),!tools.contains("change_reminder") {hint="Calendar event"}
                }
            }
            result.message=AIActivitySummary.text(record.message,hint:hint)
            return result
        }
        guard record.state.needsAttention,let destination=record.destination else {return record}
        let response:UUID?,conversation:UUID?
        switch destination {
        case .assistant(let id):
            conversation=id.flatMap(UUID.init(uuidString:))
            response=record.id.hasPrefix("action:") ? UUID(uuidString:String(record.id.dropFirst(7))) : record.id.hasPrefix("chat:") ? UUID(uuidString:String(record.id.dropFirst(5))) : nil
        case .review(let id):
            conversation=id.flatMap(UUID.init(uuidString:))
            let parts=record.id.split(separator:":")
            response=parts.count == 3 ? UUID(uuidString:String(parts[2])) : nil
            // Accepted replies update the old question even while waiting behind a heartbeat.
            if let conversation,let jobID=parts.dropFirst().first.flatMap({UUID(uuidString:String($0))}) {
                let jobs=reviewWork.jobs(record.registration,conversation:conversation)
                if let index=jobs.firstIndex(where:{$0.id == jobID}) {
                    let job=jobs[index]
                    if record.state.isFailure,job.responseTurnID != response,job.phase == .completed,!job.actions.isEmpty,job.actions.allSatisfy({$0.phase == .saved}) {
                        var resolved=record;resolved.state = .resolved;return resolved
                    }
                    if record.state == .needsAnswer,index+1 < jobs.count {return repliedActivity(record)}
                }
            }
        case .feedback(let id):
            let parts=record.id.split(separator:":")
            guard record.kind == .feedback,record.state.isFailure,parts.first == "feedback",[2,3].contains(parts.count),let jobID=id.flatMap(UUID.init(uuidString:)),parts[1] == Substring(jobID.uuidString),let job=emailSummaries.feedback.records.first(where:{$0.id == jobID && $0.registration == record.registration}),job.state == .saved,emailSummaries.feedbackMemory(job,model:self) != nil else {return record}
            var resolved=record;resolved.state = .resolved;return resolved
        default:return record
        }
        guard record.state == .needsAnswer,let conversation,let response,assistant.activityContext(conversation)?.repliesAfter[response] != nil else {return record}
        return repliedActivity(record)
    }
    private func repliedActivity(_ record:AIActivityRecord)->AIActivityRecord {
        var result=record;result.state = .replied
        let prefix="Needs your answer: "
        if result.message.lowercased().hasPrefix(prefix.lowercased()) {result.message=String(result.message.dropFirst(prefix.count))}
        return result
    }
    func relatedActivityDestinations(_ record:AIActivityRecord)->[AIActivityDestination] {
        guard record.kind == .review,record.id.hasPrefix("review:"),let id=UUID(uuidString:String(record.id.dropFirst(7).prefix(36))),let job=reviewWork.job(id),job.scope.registration == chatGPT.activeID,reviewPermits(job.source) else {return []}
        var destinations:[AIActivityDestination]=[]
        for action in job.actions where action.phase == .saved || action.phase == .uncertain {
            guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload) else {continue}
            let destination:AIActivityDestination
            if let item=payload.project {destination = .project(targetID:item.parentID?.uuidString ?? item.id.uuidString)}
            else if payload.nativeRequest?.kind == .event || payload.nativeBaseline?.kind == .event {destination = .calendar(targetID:action.itemID)}
            else if payload.localDraft != nil {continue}
            else {destination = .reminders(targetID:action.itemID)}
            if !destinations.contains(where:{$0.title == destination.title}) {destinations.append(destination)}
        }
        return destinations
    }
    func openAIActivityDestination(_ destination:AIActivityDestination) {
        switch destination {
        case .review(let id): if let id,let uuid=UUID(uuidString:id),reviewConversationAvailable(uuid) {reviewPresentation = .init(id:uuid)}
        case .assistant: openAssistantComposer()
        case .heartbeat,.feedback:showingAIHeartbeat=true
        case .project(let id):showActivityWidget(.projects,project:id.flatMap(UUID.init(uuidString:)))
        case .calendar:showActivityWidget(.calendar)
        case .reminders:showActivityWidget(.reminders)
        }
    }
    func showActivityWidget(_ kind:WidgetKind,project:UUID?=nil) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"),[WidgetKind.calendar,.reminders].contains(kind) {return}
        #endif
        if let page=workspace.state.pages.first(where:{$0.widgets.contains{$0.kind == kind}}) {workspace.select(page.id)}
        else {workspace.addPage(kind.title);workspace.addWidget(kind);if let widget=workspace.selected.widgets.first {workspace.fullPage(widget)}}
        if let widget=workspace.selected.widgets.first(where:{$0.kind == kind}) {activityNavigation = .init(registration:chatGPT.activeID,widgetID:widget.id,projectID:project)}
    }
}
private extension ReviewWorkPhase {var isFinished:Bool {self != .running && self != .queued}}

#if DEBUG
@MainActor enum AIActivityWorkPreview {
    static func seed(_ model:DashboardModel) {
        if ProcessInfo.processInfo.arguments.contains("--heartbeat-failure-preview") {
            let registration=model.chatGPT.activeID,now=Date.now
            let runs:[(String,String,Bool,String?)]=[
                ("failed","failed",false,"Fictional provider unavailable; no brief was saved."),
                ("partial","failed",true,"Fictional memory analysis failed; the completed brief is saved."),
                ("succeeded","idle",true,nil),
                ("sleep","suspended",false,"The Mac went to sleep or the laptop closed."),
                ("stopped","interrupted",false,"Stopped before the remaining work finished."),
                ("waiting","waiting",false,nil)
            ]
            for (index,value) in runs.enumerated() {
                let run=PAReviewRun(id:"fictional-heartbeat-"+value.0,started:now.addingTimeInterval(Double(index)-20),finished:now.addingTimeInterval(Double(index)-10),manual:false,phase:value.1,detail:"Fictional heartbeat",briefUpdated:value.2,failure:value.3)
                model.heartbeatActivityFinished(registration,run)
            }
            let saved=model.aiActivity.records(registration)
            precondition(saved.count == runs.count,"All heartbeat outcomes remain saved")
            precondition(Set(AIActivitySummary.recent(saved,current:nil,registration:registration).map(\.id)) == ["heartbeat:fictional-heartbeat-failed","heartbeat:fictional-heartbeat-partial"],"Only actual failed/partial heartbeats appear in Activity")
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--pill-feedback-preview") {
            model.showFeedback("Completed: Claim my refund")
            precondition(model.aiActivity.state.records.isEmpty,"Manual feedback must not enter AI Activity")
            return
        }
        let registration=model.chatGPT.activeID,conversation=model.assistant.openPA() ?? UUID()
        _=model.aiActivity.upsert(.init(id:"chat:"+UUID().uuidString,registration:registration,kind:.chat,state:.succeeded,title:"3PO chat",message:"Hello! How can I help?",destination:.assistant(targetID:conversation.uuidString)))
        model.assistantActivityFinished(.init(registration:registration,conversationID:conversation,humanTurnID:UUID(),responseTurnID:UUID(),phase:"completed",message:"This ordinary greeting must stay out of activity",receipts:[],errors:[]))
        model.assistantActivityFinished(.init(registration:registration,conversationID:conversation,humanTurnID:UUID(),responseTurnID:UUID(),phase:"completed",message:"This general chat prose must not replace the action receipt",receipts:["Added two dated project tasks"],errors:[],confirmedActions:2,attemptedTools:["create_life_items"]))
        if !ProcessInfo.processInfo.arguments.contains("--pill-success-preview") {
            model.assistantActivityFinished(.init(registration:registration,conversationID:conversation,humanTurnID:UUID(),responseTurnID:UUID(),phase:"failed",message:"General reply prose",receipts:[],errors:["The requested Calendar update failed. No event was saved."],attemptedTools:["change_calendar"]))
        }
        if ProcessInfo.processInfo.arguments.contains("--pill-answer-preview") {
            let id=model.assistant.openReview(key:"fictional-pill-question",title:"Fictional Calendar request",sourceKind:"mail",accountID:"fictional-mail",messageID:"fictional-question",identity:nil,chatID:nil,seeds:[])!
            let response=UUID()
            _=model.assistant.appendReview("Which 30-minute time should I use?",conversationID:id,turnID:response)
            model.assistantActivityFinished(.init(registration:registration,conversationID:id,humanTurnID:UUID(),responseTurnID:response,phase:"needsAnswer",message:"Which 30-minute time should I use?",receipts:[],errors:[],attemptedTools:["change_calendar"]))
        }
        let expected=(ProcessInfo.processInfo.arguments.contains("--pill-success-preview") ? 2 : 3)+(ProcessInfo.processInfo.arguments.contains("--pill-answer-preview") ? 1 : 0)
        precondition(model.aiActivity.state.records.count == expected,"The greeting creates no new activity; legacy output is retained")
    }
}
#endif

/// Fine-grained observation keeps progress updates out of the dashboard tile tree.
struct DashboardAIActivityPill:View {
    var model:DashboardModel
    var palette:WorkspacePalette
    var openChat:()->Void
    var body:some View {
        AIActivityPill(store:model.aiActivity,registration:model.chatGPT.activeID,current:model.currentAIActivity,feedback:model.nativeWriteFeedback,palette:palette,openChat:openChat,openDestination:model.openAIActivityDestination,isVisible:model.activityVisible,relatedDestinations:model.relatedActivityDestinations,presentation:model.activityPresentation)
            .task {model.syncFeedbackActivity()}
            .onChange(of:model.chatGPT.activeID) {model.syncFeedbackActivity();model.scheduleReviewWork()}
            .onChange(of:model.emailSummaries.feedback.records) {model.syncFeedbackActivity()}
    }
}
