import Foundation
import CryptoKit

struct ReviewDraftEvidence:Codable,Equatable {
    var basis:String
    var sourceRevision:String?
    var bodyDigest:String?
    var humanTurnID:UUID?
    var memoryDependencies:[MemoryDependency]
}

@MainActor extension DashboardModel {
    func guardReviewCreation(_ call:PAFunctionCall,job:ReviewWorkJob)throws {
        guard let plan=reviewWork.plan(job.scope.registration,conversation:job.conversationID),let args=try? PAToolProtocol.arguments(call) else {return}
        let payloads=plan.actions.compactMap{try? JSONDecoder().decode(ReviewPreparedPayload.self,from:$0.payload)}
        let matches:Bool
        if call.name == "create_life_items" {
            matches=(args["items"] as? [[String:Any]] ?? []).contains {entry in payloads.contains{payload in
                guard let item=payload.project else {return false}
                return entry["kind"] as? String == item.kind.rawValue && entry["title"] as? String == item.title && (entry["parent"] as? String).flatMap(UUID.init(uuidString:)) == item.parentID && entry["due"] as? String == item.due
            }}
        } else if ["change_calendar","change_reminder"].contains(call.name),args["operation"] as? String == "create" {
            matches=payloads.contains {payload in
                guard payload.nativeBaseline == nil,let fields=payload.nativeFields else {return false}
                let kind=call.name == "change_calendar" ? NativeItemKind.event : .reminder
                guard fields.kind == kind,args["title"] as? String == fields.title else {return false}
                let input=kind == .event ? args["start"] as? String : args["due"] as? String
                return input == payload.proposal.proposedDate?.start && (args["destination"] as? String == nil || args["destination"] as? String == fields.sourceID)
            }
        } else {matches=false}
        if matches {throw ActionFailure.message("This creation is already represented by an issued Review action. Use execute_review_actions with its current ID and revision, so its checkbox and canonical receipt are completed together. Do not create a second copy.")}
    }
    func executeReviewActions(_ call:PAFunctionCall,job:ReviewWorkJob,valid:@escaping NativeWriteValidity,didSave:@escaping @MainActor (Bool)->Void) async throws->ReviewActionExecution {
        let input=try ReviewPlanTools.execution(call)
        guard valid(),let plan=reviewWork.plan(job.scope.registration,conversation:job.conversationID),plan.revision == input.revision,
              Set(input.actions).isSubset(of:Set(plan.actions.map(\.id))) else {throw ActionFailure.message("The exact Review plan changed. Re-read its issued actions before acting.")}
        try PAToolProtocol.evidence(input.authorization,human:job.human)
        let actions=plan.actions.filter{input.actions.contains($0.id)}
        for (index,action) in actions.enumerated() where actions.prefix(index).contains(where:{Self.samePreparedReviewAction($0,action)}) {
            throw ActionFailure.message("These IDs describe the same prepared action. Choose one current action ID; no changes were made.")
        }
        let targets=try actions.map {action->[String:Any] in
            let payload=try JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)
            return ["id":action.id,"kind":payload.proposal.kind,"title":action.title,"destination":action.destination,"start":payload.proposal.proposedDate?.start as Any? ?? NSNull(),"end":payload.proposal.proposedDate?.end as Any? ?? NSNull(),"project":payload.project?.parentID?.uuidString as Any? ?? NSNull(),"operation":payload.nativeOperation as Any? ?? NSNull(),"scope":payload.nativeScope as Any? ?? NSNull(),"occurrenceID":payload.nativeBaseline?.occurrenceID as Any? ?? NSNull(),"sourceID":payload.nativeBaseline?.sourceID as Any? ?? NSNull()]
        }
        let target=String(decoding:try JSONSerialization.data(withJSONObject:targets,options:[.sortedKeys]),as:UTF8.self)
        let args:[String:Any]=["revision":input.revision.uuidString,"actions":input.actions,"authorization":input.authorization]
        let history=assistant.conversation(job.conversationID)?.turns.filter{$0.completed}.suffix(8).map{["role":$0.role,"content":$0.content]} ?? []
        _=try await PAToolAuthorization.check(call:call,args:args,human:job.human,history:history,target:target,model:self)
        guard valid() else {throw ActionFailure.message("This request changed before any action was issued.")}
        let results=try await reviewWork.performCaptured(job.id,revision:input.revision,actions:input.actions,valid:valid,didSave:{action in
            let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)
            didSave(payload?.project != nil)
        })
        let confirmed=Dictionary(uniqueKeysWithValues:results.filter{$0.phase == .saved}.map{($0.id,$0.result ?? "Action completed")})
        let uncertain=results.filter{$0.phase == .uncertain || $0.phase == .working}.count
        let failure=results.first{$0.phase == .failed || $0.phase == .uncertain}?.result ?? (confirmed.count == input.actions.count ? nil : "The remaining actions stopped before a confirmed save.")
        let output=String(decoding:try JSONSerialization.data(withJSONObject:["verified":failure == nil,"completedActionIDs":confirmed.keys.sorted(),"results":confirmed,"uncertain":uncertain,"error":failure as Any? ?? NSNull()],options:[.sortedKeys]),as:UTF8.self)
        return .init(output:output,confirmed:confirmed,uncertain:uncertain,failure:failure)
    }
    func reviewPlanRow(_ action:ReviewWorkAction)->ReviewPreparedRow? {
        guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload) else {return nil}
        var detail=payload.proposal.message
        if let draft=payload.localDraft {detail=draft+"\nThis copies the draft. No email is sent."}
        else if let baseline=payload.nativeBaseline,payload.nativeOperation == "remove" {detail=baseline.start.formatted(date:.abbreviated,time:baseline.allDay ? .omitted : .shortened)+"\n"+detail+"\nRemoval cannot be undone in 3PO."}
        else if let baseline=payload.nativeBaseline,let fields=payload.nativeFields {
            let old=baseline.kind == .event ? baseline.start : baseline.due,new=fields.kind == .event ? fields.start : fields.due
            let timed=fields.kind == .event ? !fields.allDay : fields.hasTime
            detail=(old?.formatted(date:.abbreviated,time:timed ? .shortened : .omitted) ?? "No date")+" → "+(new?.formatted(date:.abbreviated,time:timed ? .shortened : .omitted) ?? "No date")+"\n"+detail
        }
        else if let item=payload.project {detail=(item.due.map{"Due "+$0} ?? "No deadline assigned")+"\n"+detail}
        else if let fields=payload.nativeFields {
            if fields.kind == .event {
                var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:fields.timeZoneID) ?? .current
                let end=fields.allDay ? calendar.date(byAdding:.day,value:-1,to:fields.end) ?? fields.end : fields.end
                detail=fields.start.formatted(date:.abbreviated,time:fields.allDay ? .omitted : .shortened)+" to "+end.formatted(date:.abbreviated,time:fields.allDay ? .omitted : .shortened)+"\n"+detail
            } else {detail=(fields.due.map{$0.formatted(date:.abbreviated,time:fields.hasTime ? .shortened : .omitted)} ?? "No due date")+"\n"+detail}
        }
        return .init(id:action.id,title:action.title,detail:detail,destination:action.destination,action:action)
    }

    func prepareReviewActions(_ call:PAFunctionCall,job:ReviewWorkJob,valid:@escaping NativeWriteValidity) async throws->String {
        guard call.arguments.utf8.count <= 32_000,valid(),reviewPermits(job.source),
              let plan=reviewWork.plan(job.scope.registration,conversation:job.conversationID) else {throw ActionFailure.message("The current Review plan is unavailable. Reopen this review.")}
        let input=try ReviewPlanTools.input(call)
        guard input.revision == plan.revision,input.actions.count <= 24 else {throw ActionFailure.message("The checkbox choices changed while this reply was running. The newer plan is retained.")}
        var sourceText:String?
        var sourceRevision:String?
        var sourceStillCurrent:()->Bool={true}
        if input.actions.contains(where:{$0.basis == "source"}) {
            if job.source.kind == "whatsapp" {
                guard let message=whatsapp.messages.first(where:{$0.id == job.source.messageID && $0.chat == job.source.chatID}) else {throw ActionFailure.message("The exact source message is unavailable for new advice.")}
                sourceText=message.text
                let revision=SourceContextRules.revision(message)
                sourceRevision=revision
                sourceStillCurrent={self.whatsapp.messages.contains{$0.id == message.id && $0.chat == message.chat && SourceContextRules.revision($0) == revision}}
            } else {
                guard let message=mailData.messages.first(where:{$0.id == job.source.messageID && $0.accountID == job.source.accountID}) else {throw ActionFailure.message("The exact email is unavailable for new advice.")}
                #if DEBUG
                guard !ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") else {throw ActionFailure.message("Source reads are disabled in this fictional preview.")}
                #endif
                let revision=ReviewInferenceGuard.mailSource(message)
                sourceRevision=revision
                let body=try await mail.body(accountID:message.accountID,messageID:message.messageID,expectedInternetMessageID:message.internetMessageID,mailboxName:message.mailboxName)
                sourceText=String(body.prefix(16000))
                sourceStillCurrent={self.mailData.messages.contains{$0.id == message.id && ReviewInferenceGuard.mailSource($0) == revision}}
            }
        }
        guard valid(),sourceStillCurrent() else {throw ActionFailure.message("The source or request changed before these suggestions were prepared.")}
        var actions=plan.actions.filter{reviewWork.reserved($0.id,registration:job.scope.registration)}
        var selected=Set<String>()
        var seen=Set<String>()
        for entry in input.actions {
            try Task.checkCancellation()
            let old=entry.existingID.flatMap{id in plan.actions.first{$0.id == id}}
            guard entry.existingID == nil || old != nil else {throw ActionFailure.message("Use only suggestion IDs issued in this Review plan.")}
            if let old {guard seen.insert(old.id).inserted else {throw ActionFailure.message("A suggestion ID was repeated in this plan.")}}
            if let old,entry.kind == nil,entry.title == nil,entry.start == nil,entry.end == nil,entry.hasTime == nil,entry.projectID == nil {
                if !actions.contains(where:{$0.id == old.id}) {actions.append(old)}
                if entry.selected {selected.insert(old.id)}
                continue
            }
            if let old,reviewWork.reserved(old.id,registration:job.scope.registration) {throw ActionFailure.message("An already submitted action cannot be changed or repeated. Its receipts are retained.")}
            let previous=old.flatMap{try? JSONDecoder().decode(ReviewPreparedPayload.self,from:$0.payload)}
            guard previous?.nativeBaseline == nil,previous?.localDraft == nil else {throw ActionFailure.message("This action affects an existing item or a saved reply. Use its exact item with the ordinary action tools for the human's requested change; do not replace it with a new creation.")}
            let kind=entry.kind ?? previous?.proposal.kind ?? ""
            let title=(entry.title ?? previous?.proposal.sourceTitle ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
            guard ["calendar","reminder","projectTask","project"].contains(kind),!title.isEmpty,title.count <= 160,
                  let basis=entry.basis,["source","human"].contains(basis),let evidence=MemoryEvidence.match(entry.evidence,human:basis == "human" ? job.human : sourceText ?? ""),evidence.count <= 4000 else {throw ActionFailure.message("A new or changed suggestion needs a concrete title and an exact supporting source or human quote.")}
            if previous == nil || title != previous?.proposal.sourceTitle {
                let filler:Set<String>=["a","an","the","to","in","for","of","and","with","add","create","task","event","reminder","please","it","that","this","my"]
                func terms(_ value:String)->Set<String> {Set(value.lowercased().split{!$0.isLetter && !$0.isNumber}.map(String.init)).subtracting(filler)}
                guard !terms(title).intersection(terms(evidence)).isEmpty else {throw ActionFailure.message("The proposed task needs a quote supporting what it is about. A greeting or unrelated quote cannot create a new suggestion.")}
            }
            var record=previous?.proposal ?? PADiscovery(id:UUID().uuidString,registration:job.scope.registration,mailID:job.source.messageID ?? "",kind:kind,message:"",evidence:evidence,created:.now,scope:job.scope.sourceChoices)
            // A changed draft has a fresh operation identity; captured/submitted payloads remain immutable.
            record.id=UUID().uuidString;record.kind=kind;record.sourceTitle=title;record.message=basis == "human" ? "Requested in this Review conversation." : "Suggested from the source; choose whether to add it."
            record.evidence=evidence;record.sourceKind=job.source.kind;record.sourceIdentity=job.source.identity;record.sourceChatID=job.source.chatID;record.sourceMessageID=job.source.messageID
            record.created = .now;record.proposedChange=nil;record.proposedRemoval=nil;record.reviewState=nil;record.dismissed=false
            if let start=entry.start ?? previous?.proposal.proposedDate?.start {
                let date=DiscoveryProposedDate(start:start,end:entry.end ?? previous?.proposal.proposedDate?.end,hasTime:entry.hasTime ?? previous?.proposal.proposedDate?.hasTime ?? false,timeZoneID:job.timeZoneID ?? TimeZone.current.identifier)
                guard date.rejection() == nil,date.valid,date.end.map({date.rejection($0) == nil}) ?? true,!SourceDateGrounding.needsWeekAnchor(evidence),!["projectTask","project"].contains(kind) || !date.hasTime else {throw ActionFailure.message("This suggested date needs clarification. The prior plan is retained.")}
                record.proposedDate=date
                if previous == nil || entry.start != nil || entry.end != nil || entry.hasTime != nil {
                    if let rejection=ReviewPlanDateRules.rejection(quote:evidence,basis:basis,human:job.human,title:title,kind:kind,start:date.start,end:date.end,hasTime:date.hasTime,now:job.created,timeZoneID:date.timeZoneID) {throw ActionFailure.message(rejection)}
                }
            } else if previous == nil {record.proposedDate=nil}
            if kind == "calendar",record.proposedDate == nil {throw ActionFailure.message("A Calendar suggestion needs a concrete date.")}
            if kind == "projectTask" {
                guard let id=(entry.projectID.flatMap(UUID.init(uuidString:)) ?? previous?.project?.parentID),let parent=assistant.projects.items(job.scope.registration,includeTopics:true).first(where:{$0.id == id && $0.kind == .space}) else {throw ActionFailure.message("Read or choose an existing project space before suggesting its task.")}
                record.proposedProjectTask = .init(target:.init(id:parent.id,revision:parent.revision,title:parent.title,conversationID:parent.conversationID),connection:"Proposed in this source's Review conversation.")
            } else {record.proposedProjectTask=nil}
            if let previous,let old,Self.sameReviewCreation(previous.proposal,record) {
                actions.append(old);if entry.selected {selected.insert(old.id)};continue
            }
            if let duplicate=actions.first(where:{action in (try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)).map{Self.sameReviewCreation($0.proposal,record)} == true}) {if entry.selected {selected.insert(duplicate.id)};continue}
            let chosen=assistant.conversation(job.conversationID)?.turns.first{$0.id == job.responseTurnID}?.contextCapture?.memoryIDs ?? []
            let selection=assistant.memory.selection(job.scope.registration,conversationID:nil,includeTopics:true,query:job.source.title+" "+job.human,focus:job.focusAreas.compactMap(LifeArea.init(rawValue:)),now:job.created)
            let dependencies=MemoryDependencyRules.capture(selection.records.filter{($0["id"].flatMap(UUID.init(uuidString:))).map(chosen.contains) == true})
            record.memoryDependencies=dependencies;record.sourceRevision=basis == "source" ? sourceRevision : nil;record.sourceAssessmentRevision=nil
            let row=await prepareReviewRow(record,capturedDraft:true)
            guard valid(),sourceStillCurrent(),reviewWork.plan(job.scope.registration,conversation:job.conversationID)?.revision == plan.revision,
                  let action=row.action else {throw ActionFailure.message(row.error ?? "This request changed while preparing the suggestions.")}
            var captured=action
            var payload=try JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)
            payload.draftEvidence = .init(basis:basis,sourceRevision:basis == "source" ? sourceRevision : nil,bodyDigest:basis == "source" ? sourceText.map{SHA256.hash(data:Data($0.utf8)).map{String(format:"%02x",$0)}.joined()} : nil,humanTurnID:basis == "human" ? job.humanTurnID : nil,memoryDependencies:dependencies)
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];captured.payload=try encoder.encode(payload)
            actions.append(captured)
        }
        guard actions.count <= 24,valid(),sourceStillCurrent() else {throw ActionFailure.message("This plan is unavailable or too large. The prior suggestions are retained.")}
        var updated=ReviewWorkPlan(conversationID:plan.conversationID,scope:job.scope,source:job.source,actions:actions,selected:selected.sorted())
        updated.presentationVersion=ReviewSelectionRules.version;updated.seenProposalIDs=plan.seenProposalIDs ?? reviewActionRecords(job.source).map(\.id);updated.unpreparedProposalIDs=[]
        guard reviewWork.savePlan(updated,expected:plan.revision) else {throw ActionFailure.message(reviewWork.error ?? "The suggestions could not be saved.")}
        return String(decoding:try JSONSerialization.data(withJSONObject:["draftOnly":true,"nativeWrites":0,"projectWrites":0,"suggestions":actions.count,"selected":selected.count,"revision":updated.revision.uuidString,"message":"The checkbox suggestions were updated. Nothing was executed. The approval button approves the checked actions."],options:[.sortedKeys]),as:UTF8.self)
    }
    private static func sameReviewCreation(_ lhs:PADiscovery,_ rhs:PADiscovery)->Bool {
        lhs.kind == rhs.kind && lhs.sourceTitle == rhs.sourceTitle && lhs.proposedDate == rhs.proposedDate && lhs.evidence == rhs.evidence && lhs.proposedProjectTask?.target.id == rhs.proposedProjectTask?.target.id
    }
}
