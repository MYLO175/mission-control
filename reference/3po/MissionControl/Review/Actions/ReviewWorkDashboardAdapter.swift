import Foundation
import SwiftData
import AppKit
import CryptoKit

struct ReviewPreparedPayload:Codable,Equatable {
    var proposal:PADiscovery
    var approval:Data
    var source:ReviewWorkSource?
    var nativeRequest:NativeCreationRequest?
    var nativeFields:NativeEditDetails?
    var project:LifeItem?
    var draftEvidence:ReviewDraftEvidence?
    var nativeBaseline:NativeEditDetails?
    var nativeOperation:String?
    var nativeScope:String?
    var localDraft:String?
}
struct ReviewConversationPresentation:Identifiable {var id:UUID}
struct ReviewPreparedRow:Identifiable {
    var id:String
    var title:String
    var detail:String
    var destination:String
    var action:ReviewWorkAction?
    var error:String?
}

@MainActor extension DashboardModel {
    /// Group presentation aliases without rewriting their captured IDs or receipts.
    static func samePreparedReviewAction(_ left:ReviewWorkAction,_ right:ReviewWorkAction)->Bool {
        guard let a=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:left.payload),let b=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:right.payload),a.source != nil,a.source == b.source,
              (ProactiveRules.sameProposal(a.proposal,b.proposal) || (a.draftEvidence != nil && a.draftEvidence == b.draftEvidence && a.proposal.kind == b.proposal.kind && a.proposal.sourceTitle != nil && a.proposal.sourceTitle == b.proposal.sourceTitle && a.proposal.proposedDate == b.proposal.proposedDate && a.proposal.proposedProjectTask?.target.id == b.proposal.proposedProjectTask?.target.id)),a.nativeOperation == b.nativeOperation,a.nativeScope == b.nativeScope,a.nativeBaseline == b.nativeBaseline,a.localDraft == b.localDraft else {return false}
        if var x=a.nativeFields,var y=b.nativeFields {
            guard a.project == nil,b.project == nil else {return false}
            if a.nativeBaseline == nil {
                func sourceNotes(_ payload:ReviewPreparedPayload)->String {"Source: "+(payload.proposal.sourceLabel ?? payload.source?.title ?? "")+"\n"+payload.proposal.evidence}
                if x.notes == sourceNotes(a) {x.notes=""}
                if y.notes == sourceNotes(b) {y.notes=""}
                x.itemID="";y.itemID="";x.occurrenceID="";y.occurrenceID="";x.modified=nil;y.modified=nil
                if x.kind == .reminder {x.start = .distantPast;y.start = .distantPast;x.end = .distantPast;y.end = .distantPast}
            }
            return x == y
        }
        guard a.nativeFields == nil,b.nativeFields == nil else {return false}
        if let x=a.project,let y=b.project {
            let notesA=x.notes == a.proposal.evidence ? "" : x.notes,notesB=y.notes == b.proposal.evidence ? "" : y.notes
            return notesA == notesB && x.registration == y.registration && x.kind == y.kind && x.title == y.title && x.parentID == y.parentID && x.conversationID == y.conversationID && x.due == y.due && x.status == y.status && x.areas == y.areas && x.estimateMinutes == y.estimateMinutes}
        return a.project == nil && b.project == nil && a.localDraft != nil
    }
    static func reviewRowGroups(_ rows:[ReviewPreparedRow])->[[ReviewPreparedRow]] {
        var groups:[[ReviewPreparedRow]]=[]
        for row in rows {
            if let action=row.action,let index=groups.firstIndex(where:{$0.first?.action.map{samePreparedReviewAction($0,action)} == true}) {groups[index].append(row)}
            else {groups.append([row])}
        }
        return groups
    }
    var reviewConversationOwnsAssistant:Bool {
        guard assistant.busy,let id=reviewWork.activeID,let job=reviewWork.job(id) else {return false}
        return job.mode == .conversation && job.phase == .running && job.scope.registration == chatGPT.activeID && job.scope.storage == reviewStorageIdentity && assistant.requestConversationID == job.conversationID && assistant.requestTurnID == job.responseTurnID
    }
    var reviewStorageIdentity:String {container?.configurations.map{$0.url.absoluteString}.sorted().joined(separator:"|") ?? "unavailable"}
    func reviewWorkScope()->ReviewWorkScope {
        let wa=whatsapp.access(for:chatGPT.activeID)
        let choices=proactive.sourceSettingsScope(self)+"|"+String(wa.enabled)+"|"+String(wa.includeInSuggestions == true)+"|"+whatsapp.linkedIdentity+"|"+wa.chats.sorted().joined(separator:"|")
        return .init(registration:chatGPT.activeID,model:chatGPT.selectedModel,sourceChoices:choices,storage:reviewStorageIdentity)
    }
    func reviewPermits(_ source:ReviewWorkSource)->Bool {
        guard assistant.contextEnabled else {return false}
        if source.kind == "whatsapp" {
            let access=whatsapp.access(for:chatGPT.activeID)
            return access.enabled && access.includeInSuggestions == true && source.identity == whatsapp.linkedIdentity && source.chatID.map{access.chats.contains($0)} == true
        }
        return emailSummaries.enabled && source.accountID.map{id in !assistant.excludedAccounts.contains(id) && mailData.accounts.contains{$0.id == id}} == true
    }
    func reviewSource(_ record:PADiscovery)->ReviewWorkSource {
        let message=mailData.messages.first{$0.id == record.mailID} ?? emailSummaries.records.first{$0.id == record.mailID && $0.registration == record.registration}?.message
        return .init(key:record.sourceKind == "whatsapp" ? "whatsapp:"+(record.sourceIdentity ?? "")+":"+(record.sourceChatID ?? "")+":"+(record.sourceMessageID ?? record.mailID) : "mail:"+record.mailID,title:message?.subject ?? record.sourceTitle ?? "Review suggestion",kind:record.sourceKind ?? "mail",accountID:message?.accountID,messageID:record.mailID,identity:record.sourceIdentity,chatID:record.sourceChatID)
    }
    func reviewSource(_ conversation:AssistantConversation)->ReviewWorkSource? {
        guard let key=conversation.reviewKey else {return nil}
        return .init(key:key,title:conversation.title,kind:conversation.reviewSourceKind ?? "mail",accountID:conversation.reviewAccountID,messageID:conversation.reviewMessageID,identity:conversation.reviewSourceIdentity,chatID:conversation.reviewSourceChatID)
    }
    func reviewConversationAvailable(_ id:UUID)->Bool {assistant.conversation(id).flatMap(reviewSource).map(reviewPermits) == true}
    func openReviewConversation(_ records:[PADiscovery]) {
        guard let first=records.first,first.registration == chatGPT.activeID else {return}
        let source=reviewSource(first)
        guard reviewPermits(source) else {return}
        let seeds=records.map {record -> AssistantTurn in
            var turn=AssistantTurn(role:"assistant",content:(record.sourceTitle.map{$0+"\n"} ?? "")+record.message,completed:true,deliveryID:"discovery:"+record.id)
            turn.sourceMemoryIDs=record.memoryDependencies?.compactMap{UUID(uuidString:$0.id)}
            return turn
        }
        guard let id=assistant.openReview(key:source.key,title:source.title,sourceKind:source.kind,accountID:source.accountID,messageID:source.messageID,identity:source.identity,chatID:source.chatID,seeds:seeds) else {return}
        reviewPresentation = .init(id:id)
    }
    func reviewRecords(_ source:ReviewWorkSource)->[PADiscovery] {
        proactive.state.records.filter{record in record.registration == chatGPT.activeID && reviewSource(record).key == source.key && record.supersededBy == nil && record.retiredAt == nil && !record.dismissed}
    }
    func reviewSummaryDraft(_ source:ReviewWorkSource)->PADiscovery? {
        guard source.kind == "mail",let summary=emailSummaries.records.first(where:{$0.id == source.messageID && $0.registration == chatGPT.activeID}),let message=summary.message ?? mailData.messages.first(where:{$0.id == source.messageID && $0.accountID == source.accountID}),message.accountID == source.accountID,let draft=summary.replyDraft,!draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !reviewRecords(source).contains(where:{$0.replyDraft == draft}) else {return nil}
        let hash=SHA256.hash(data:Data((chatGPT.activeID+"|"+source.key+"|"+draft).utf8)).map{String(format:"%02x",$0)}.joined()
        let h=Array(hash.prefix(32))
        let id=[String(h[0..<8]),String(h[8..<12]),String(h[12..<16]),String(h[16..<20]),String(h[20..<32])].joined(separator:"-")
        return .init(id:id,registration:chatGPT.activeID,mailID:summary.id,kind:"reply",message:"Copy this saved reply draft to the clipboard for review in Mail.",evidence:summary.evidence,created:message.received,scope:proactive.sourceSettingsScope(self),sourceTitle:message.subject,replyDraft:draft)
    }
    func reviewActionRecords(_ source:ReviewWorkSource)->[PADiscovery] {
        var records=reviewRecords(source).filter{$0.kind != "update"}
        if let draft=reviewSummaryDraft(source) {records.append(draft)}
        return records
    }
    func reviewSummaryDraftCompleted(_ message:MailMessage)->Bool {
        let source=ReviewWorkSource(key:"mail:"+message.id,title:message.subject,kind:"mail",accountID:message.accountID,messageID:message.id)
        guard let draft=reviewSummaryDraft(source) else {return false}
        return reviewWork.jobs(chatGPT.activeID).contains{$0.source.key == source.key && $0.actions.contains{$0.id == draft.id && $0.phase == .saved}}
    }
    func preparedCreationRequest(_ record:PADiscovery)->NativeCreationRequest? {
        guard record.nativeTarget == nil,["calendar","reminder"].contains(record.kind),let id=UUID(uuidString:record.id),let snapshot=preparedApprovalSnapshot(record) else {return nil}
        let source=reviewSource(record),kind:NativeItemKind=record.kind == "calendar" ? .event : .reminder
        return .init(id:id,kind:kind,registration:record.registration,title:String((record.sourceTitle ?? source.title).prefix(500)),notes:"Source: "+(record.sourceLabel ?? source.title)+"\n"+record.evidence,discoveryID:record.id,discoveryApproval:snapshot,evidence:record.message+"\n\n"+record.evidence,requiresDateSelection:kind == .event,suggestedStart:record.proposedDate?.date(),suggestedEnd:record.proposedDate?.end.flatMap{record.proposedDate?.date($0)},suggestedHasTime:record.proposedDate?.hasTime,suggestedTimeZone:record.proposedDate?.timeZoneID)
    }
    func prepareReviewRow(_ record:PADiscovery,capturedDraft:Bool=false) async->ReviewPreparedRow {
        let title=record.sourceTitle ?? reviewSource(record).title
        var row=ReviewPreparedRow(id:record.id,title:title,detail:record.message,destination:"",action:nil)
        guard capturedDraft || currentPreparedApproval(record),let approval=preparedApprovalSnapshot(record) else {row.error="This suggestion changed. Reopen Review for its current version.";return row}
        do {
            var payload=ReviewPreparedPayload(proposal:record,approval:approval,source:reviewSource(record))
            if let removal=record.proposedRemoval {
                guard removal.valid,let event=(paOrientation?.calendar ?? calendarData).events.first(where:{$0.id == removal.target.itemID}) else {throw ActionFailure.message("The exact Calendar occurrence is unavailable. Ask below for a current alternative.")}
                let session=try await preparedReviewSession(.event(event),source:reviewSource(record))
                try validateCalendarRemoval(record,baseline:session.item)
                payload.nativeBaseline=session.item;payload.nativeOperation="remove";payload.nativeScope=NativeChangeScope.occurrence.rawValue
                row.title="Remove: "+removal.target.title;row.destination="Calendar · Only this occurrence"
                row.detail=session.item.start.formatted(date:.abbreviated,time:session.item.allDay ? .omitted : .shortened)+"\n"+record.message+"\nRemoval cannot be undone in 3PO."
            } else if record.proposedChange != nil {
                guard let target=dateReviewTarget(record) else {throw ActionFailure.message("The exact item or proposed date changed. Ask below for a current alternative.")}
                let review:NativeDateReview
                switch target {case .reviewEvent(_,let value),.reviewReminder(_,let value):review=value;default:throw ActionFailure.message("No exact native date change was captured.")}
                let session=try await preparedReviewSession(target,source:reviewSource(record)),edited=try review.applying(to:session.item)
                payload.nativeBaseline=session.item;payload.nativeFields=edited;payload.nativeOperation="change";payload.nativeScope=(edited.kind == .reminder && session.item.recurring ? NativeChangeScope.reminderSeries : .occurrence).rawValue
                row.title="Update: "+session.item.title;row.destination=edited.kind == .event ? "Calendar · Only this occurrence" : session.item.recurring ? "Reminders · Repeating reminder" : "Reminders"
                let old=session.item.kind == .event ? session.item.start : session.item.due,new=edited.kind == .event ? edited.start : edited.due
                row.detail=(old?.formatted(date:.abbreviated,time:.shortened) ?? "No date")+" → "+(new?.formatted(date:.abbreviated,time:review.hasTime ? .shortened : .omitted) ?? "No date")+"\n"+record.message
            } else if record.kind == "project" {
                guard let id=UUID(uuidString:record.id),!title.isEmpty else {throw ActionFailure.message("This space needs a concrete name before approval.")}
                payload.project = .init(id:id,registration:record.registration,kind:.space,title:String(title.prefix(160)),notes:record.evidence,due:record.proposedDate?.localDay)
                row.title="Create space: "+title;row.destination="Projects home · New space"
                row.detail="Name: "+title+"\n"+record.message
            } else if record.kind == "projectTask" {
                guard let target=record.proposedProjectTask?.target,let id=UUID(uuidString:record.id) else {row.error="Choose an existing project space below before adding this task.";return row}
                payload.project = .init(id:id,registration:record.registration,conversationID:target.conversationID,kind:.task,title:String(title.prefix(160)),parentID:target.id,notes:record.evidence,due:record.proposedDate?.localDay)
                row.destination="Task in "+target.title
                row.detail=(record.proposedDate?.localDay.map{"Due "+$0+"\n"} ?? "No deadline assigned\n")+record.message
            } else if record.kind == "reply",let draft=record.replyDraft,!draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                payload.localDraft=draft;row.title="Copy reply draft";row.destination="Clipboard · Unsent draft";row.detail=draft+"\nThis copies the draft. No email is sent."
            } else if let request=preparedCreationRequest(record) {
                guard !record.needsDateClarification,request.kind != .event || request.suggestedStart != nil else {row.error="The Calendar date needs clarification. Ask below before approving it.";return row}
                let scope=reviewWorkScope()
                let session:NativeEditSession
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {
                    guard let fixture=ReviewInboxEvaluation.previewSession(.create(request)) else {throw ActionFailure.message("No source-free destination fixture is available.")}
                    session=fixture
                } else {session=try await eventKit.creationSession(request)}
                #else
                session=try await eventKit.creationSession(request)
                #endif
                try Task.checkCancellation()
                guard scope.registration == chatGPT.activeID,scope.storage == reviewStorageIdentity,payload.source.map(reviewPermits) == true,capturedDraft || currentPreparedApproval(record) else {throw ActionFailure.message("The account, source access, storage or suggestion changed while preparing this plan.")}
                var fields=NativeCreationRules.applyingSuggestion(request,to:session.item)
                if let chosen=record.proposedCalendarDestination {
                    guard request.kind == .event,session.sources.contains(where:{chosen.matches($0) && !assistant.excludedCalendars.contains($0.id)}) else {throw ActionFailure.message("The proposed Calendar destination is no longer available for this account. Ask below for an alternative.")}
                    fields.sourceID=chosen.sourceID
                }
                guard let destination=session.sources.first(where:{$0.id == fields.sourceID && $0.writable}),!(request.kind == .event ? assistant.excludedCalendars : assistant.excludedLists).contains(destination.id) else {throw ActionFailure.message("Choose an enabled writable destination before approving this action.")}
                payload.nativeRequest=request;payload.nativeFields=fields
                row.destination=(request.kind == .event ? "Calendar · " : "Reminders · ")+destination.label
                if request.kind == .event {
                    var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:fields.timeZoneID) ?? .current
                    let end=fields.allDay ? calendar.date(byAdding:.day,value:-1,to:fields.end) ?? fields.end : fields.end
                    row.detail=fields.start.formatted(date:.abbreviated,time:fields.allDay ? .omitted : .shortened)+" to "+end.formatted(date:.abbreviated,time:fields.allDay ? .omitted : .shortened)+"\n"+record.message
                } else {row.detail=fields.due.map{$0.formatted(date:.abbreviated,time:fields.hasTime ? .shortened : .omitted)+"\n"+record.message} ?? "No due date\n"+record.message}
            } else {row.error="This action needs its existing detail/occurrence review. You can ask about it below.";return row}
            let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
            var concrete:[String:Any]=["approval":approval.base64EncodedString()]
            if let baseline=payload.nativeBaseline {concrete["baseline"]=try JSONSerialization.jsonObject(with:encoder.encode(baseline));concrete["operation"]=payload.nativeOperation;concrete["scope"]=payload.nativeScope}
            if let draft=payload.localDraft {concrete["localDraft"]=draft}
            if let fields=payload.nativeFields,let object=try JSONSerialization.jsonObject(with:encoder.encode(fields)) as? [String:Any] {
                let keys:Set<String>=["kind","sourceID","title","notes","location","start","end","allDay","due","hasTime","timeZoneID","url","priority","alarms","availability"]
                concrete["native"]=object.filter{keys.contains($0.key) && (fields.kind == .event || !["start","end"].contains($0.key))}
            }
            if let item=payload.project,let object=try JSONSerialization.jsonObject(with:encoder.encode(item)) as? [String:Any] {concrete["project"]=object.filter{["id","registration","conversationID","kind","title","parentID","notes","due"].contains($0.key)}}
            let key=try JSONSerialization.data(withJSONObject:concrete,options:[.sortedKeys]).base64EncodedString()
            row.action = .init(id:record.id,title:row.title,destination:row.destination,coalescingKey:key,payload:try encoder.encode(payload))
        } catch {row.error=error.localizedDescription}
        return row
    }
    private func preparedReviewSession(_ target:NativeEditTarget,source:ReviewWorkSource) async throws->NativeEditSession {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") || (ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") && !ProcessInfo.processInfo.arguments.contains("--removal-native")) {
            guard let session=ReviewInboxEvaluation.previewSession(target) else {throw ActionFailure.message("No fictional native session is available; live source access is disabled.")}
            return session
        }
        #endif
        let scope=reviewWorkScope(),session=try await eventKit.editSession(target)
        try Task.checkCancellation()
        guard scope.registration == chatGPT.activeID,scope.storage == reviewStorageIdentity,reviewPermits(source),
              !(session.item.kind == .event ? assistant.excludedCalendars : assistant.excludedLists).contains(session.item.sourceID) else {throw ActionFailure.message("The account, source access, storage or exact native destination changed while opening this plan.")}
        return session
    }
    /// The accepted displayed creation is the authority. Background reassessment
    /// cannot substitute another payload or veto it through an evidence revision.
    func acceptedPreparedApproval(_ payload:ReviewPreparedPayload)->Bool {
        let proposal=payload.proposal
        guard proposal.registration == chatGPT.activeID,
              reviewPermits(payload.source ?? reviewSource(proposal)),preparedApprovalSnapshot(proposal) == payload.approval,
              let identity=UUID(uuidString:proposal.id) else {return false}
        if let baseline=payload.nativeBaseline {
            guard currentPreparedApproval(proposal),baseline.writable else {return false}
            if payload.nativeOperation == "remove" {return proposal.proposedRemoval?.valid == true && payload.nativeScope == NativeChangeScope.occurrence.rawValue && baseline.kind == .event && payload.nativeFields == nil}
            return payload.nativeOperation == "change" && proposal.proposedChange != nil && payload.nativeFields?.kind == baseline.kind && payload.nativeScope == (baseline.kind == .reminder && baseline.recurring ? NativeChangeScope.reminderSeries : .occurrence).rawValue
        }
        guard proposal.nativeTarget == nil else {return false}
        if let draft=payload.localDraft {return proposal.kind == "reply" && proposal.replyDraft == draft && !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
        if let request=payload.nativeRequest,let fields=payload.nativeFields {
            guard ["calendar","reminder"].contains(proposal.kind),!proposal.needsDateClarification,
                  request.id == identity,request.registration == proposal.registration,request.discoveryID == proposal.id,
                  request.discoveryApproval == payload.approval,fields.kind == request.kind,
                  request.kind == (proposal.kind == "calendar" ? NativeItemKind.event : .reminder),
                  !(fields.kind == .event ? assistant.excludedCalendars : assistant.excludedLists).contains(fields.sourceID),
                  request.kind != .event || request.suggestedStart != nil else {return false}
            if let chosen=proposal.proposedCalendarDestination {return request.kind == .event && fields.sourceID == chosen.sourceID}
            return true
        }
        if let item=payload.project,let target=proposal.proposedProjectTask?.target {
            return proposal.kind == "projectTask" && item.id == identity && item.kind == .task && item.registration == proposal.registration && item.parentID == target.id && item.conversationID == target.conversationID
        }
        if let item=payload.project {return proposal.kind == "project" && item.id == identity && item.kind == .space && item.registration == proposal.registration && item.parentID == nil && item.conversationID == nil}
        return false
    }
    func inspectReviewAction(_ job:ReviewWorkJob,_ action:ReviewWorkAction)->ReviewWorkActionResult? {
        guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload),payload.proposal.registration == job.scope.registration else {return .init(phase:.failed,message:"The captured action payload is unavailable.")}
        if payload.nativeBaseline != nil {
            if let current=proactive.state.records.first(where:{$0.id == action.id && $0.registration == job.scope.registration}),preparedApprovalSnapshot(current) == payload.approval {
                if current.reviewState == "approved" {return .init(phase:.saved,message:payload.nativeOperation == "remove" ? "Removed "+(payload.nativeBaseline?.title ?? action.title) : "Updated "+(payload.nativeBaseline?.title ?? action.title),itemID:payload.nativeBaseline?.occurrenceID,location:payload.nativeBaseline?.kind.rawValue)}
                if current.reviewState == "pending" {return .init(phase:.uncertain,message:"This native change has an unconfirmed receipt. It will not be repeated.")}
            }
        }
        if payload.localDraft != nil,let saved=reviewWork.jobs(job.scope.registration).flatMap(\.actions).first(where:{$0.id == action.id && $0.phase == .saved && $0.payload == action.payload}) {return .init(phase:.saved,message:saved.result ?? "Copied reply draft",location:"clipboard")}
        if let request=payload.nativeRequest {
            if let receipt=nativeCreations.receipt(request) {return .init(phase:.saved,message:"Created "+receipt.title,itemID:receipt.itemID,location:request.kind.rawValue)}
            if let claim=nativeCreations.state.claims[request.key],!NativeCreationRules.retryAllowed(claim,request:request) {return .init(phase:.uncertain,message:"This save has an unconfirmed receipt. Check Calendar or Reminders; it will not be repeated.")}
            if action.phase == .uncertain {return .init(phase:.failed,message:"No native save was claimed. Reopen this exact plan before retrying.")}
        } else if let item=payload.project,let receipt=assistant.projects.receipt("project-suggestion:"+payload.proposal.id,registration:job.scope.registration) {
            return .init(phase:.saved,message:receipt.result,itemID:receipt.itemID?.uuidString ?? item.id.uuidString,location:"project")
        }
        return nil
    }
    func performReviewAction(_ job:ReviewWorkJob,_ action:ReviewWorkAction,valid:@escaping @MainActor ()->Bool)async throws->ReviewWorkActionResult {
        let payload=try JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)
        let source=payload.source ?? job.source
        guard source.key == job.source.key,source.kind == job.source.kind,source.accountID == job.source.accountID,source.identity == job.source.identity,source.chatID == job.source.chatID else {throw ActionFailure.message("The captured source account does not match this Review request.")}
        guard action.id == payload.proposal.id,valid(),heartbeat.deviceAvailable,reviewPermits(source),job.scope.storage == reviewStorageIdentity else {throw ActionFailure.message("The captured action, account, source access or destination choices changed. Reopen this plan.")}
        if let known=inspectReviewAction(job,action) {return known}
        guard acceptedPreparedApproval(payload) else {throw ActionFailure.message("The approved concrete action or exact native target changed. Reopen this plan.")}
        if let baseline=payload.nativeBaseline {
            if payload.nativeOperation == "remove" {
                try await saveCalendarRemoval(payload.proposal,baseline:baseline,selectedModel:job.scope.model,sourceScope:job.scope.sourceChoices,occurrenceConfirmed:true,additionalValidity:valid)
            } else if let edited=payload.nativeFields,let target=dateReviewTarget(payload.proposal) {
                let review:NativeDateReview
                switch target {case .reviewEvent(_,let value),.reviewReminder(_,let value):review=value;default:throw ActionFailure.message("The captured native change is unavailable.")}
                guard try review.applying(to:baseline) == edited,let scope=payload.nativeScope.flatMap(NativeChangeScope.init(rawValue:)) else {throw ActionFailure.message("The concrete native change or occurrence scope changed.")}
                try await saveNativeEdit(baseline:baseline,edited:edited,scope:scope,review:review,validity:valid)
            } else {throw ActionFailure.message("No exact native operation was captured.")}
        } else if let draft=payload.localDraft {
            #if DEBUG
            guard !ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") else {throw ActionFailure.message("Clipboard writes are disabled in this fictional preview.")}
            #endif
            guard valid() else {throw ActionFailure.message("This reply-copy request stopped.")}
            NSPasteboard.general.clearContents();guard NSPasteboard.general.setString(draft,forType:.string),NSPasteboard.general.string(forType:.string) == draft else {throw ActionFailure.message("The clipboard copy could not be confirmed.")}
            return .init(phase:.saved,message:"Copied reply draft; no email sent",location:"clipboard")
        } else if let request=payload.nativeRequest,let captured=payload.nativeFields {
            let session=try await eventKit.creationSession(request)
            try Task.checkCancellation()
            guard valid(),heartbeat.deviceAvailable,session.sources.contains(where:{$0.id == captured.sourceID && $0.writable}),payload.proposal.proposedCalendarDestination.map({chosen in session.sources.contains(where:chosen.matches)}) ?? true else {throw ActionFailure.message("The selected Calendar/list is no longer available or this request stopped.")}
            var edited=captured;edited.itemID=session.item.itemID;edited.occurrenceID=session.item.occurrenceID;edited.modified=session.item.modified;edited.writable=session.item.writable
            try await createNativeItem(request,baseline:session.item,edited:edited,dateSelected:true,additionalValidity:{valid() && self.heartbeat.deviceAvailable},acceptedSnapshot:payload)
        } else if let item=payload.project {
            try savePreparedProjectItem(item,proposal:payload.proposal,additionalValidity:{valid() && self.heartbeat.deviceAvailable},acceptedSnapshot:payload)
        } else {throw ActionFailure.message("No concrete creation was captured.")}
        guard let confirmed=inspectReviewAction(job,action),confirmed.phase == .saved else {throw ActionFailure.message("The save could not be confirmed. Inspect the original receipt before repeating it.")}
        return confirmed
    }
    func reviewWorkRuntime()->ReviewWorkRuntime {
        var runtime=ReviewWorkRuntime(scope:{self.reviewWorkScope()},ready:{self.reviewWorkReady},permits:{self.reviewPermits($0)},perform:{job,action,valid in try await self.performReviewAction(job,action,valid:valid)},inspect:{self.inspectReviewAction($0,$1)},converse:{job,valid in
            await withCheckedContinuation {continuation in
                var runtime=self.assistantRuntime()
                runtime.started={_ in}
                runtime.working={outcome in self.reviewActivityStarted(job,outcome:outcome)}
                runtime.prepareReviewActions={call,owned in try await self.prepareReviewActions(call,job:job,valid:{valid() && owned()})}
                runtime.executeReviewActions={call,owned,refresh in try await self.executeReviewActions(call,job:job,valid:{valid() && owned()},didSave:refresh)}
                runtime.reviewCreationGuard={call in try self.guardReviewCreation(call,job:job)}
                runtime.finished={outcome in
                    let classification=self.classifyAssistantOutcome(outcome)
                    continuation.resume(returning:.init(phase:classification.phase,message:classification.message,confirmedActions:classification.actions,error:classification.error))
                }
                let accepted=self.assistant.sendReview(runtime:runtime,conversationID:job.conversationID,prompt:job.human,humanTurnID:job.humanTurnID,responseTurnID:job.responseTurnID,query:job.source.title+" "+job.human,sourceContext:String(decoding:(try? JSONEncoder().encode(job.source)) ?? Data(),as:UTF8.self),humanControl:job.humanControl == true,selectionContext:self.reviewSelectionContext(job),submitted:job.created,focusAreas:job.focusAreas.compactMap(LifeArea.init(rawValue:)),capturedModel:job.scope.model,valid:{valid() && self.heartbeat.deviceAvailable})
                if !accepted {continuation.resume(returning:.init(phase:.failed,message:self.assistant.error ?? "The assistant is unavailable. Your Review reply is retained.",error:self.assistant.error))}
            }
        },cancelConversation:{self.assistant.cancel()},changed:{self.reviewJobChanged($0)})
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {
            runtime.ready={!self.heartbeat.busy && !self.assistant.busy && !self.writing}
            runtime.converse={_,_ in .init(phase:.failed,message:"This source-free preview does not call the AI. Your reply remains in the fictional review.",error:"AI is disabled for this preview.")}
            if ProcessInfo.processInfo.arguments.contains("--review-plan-update-preview") {
                runtime.converse={job,valid in
                    _=self.assistant.appendReview(job.human,conversationID:job.conversationID,turnID:job.humanTurnID,human:true)
                    if job.human.lowercased() == "hi" {
                        _=self.assistant.appendReview("Hi! How can I help?",conversationID:job.conversationID,turnID:job.responseTurnID)
                        return .init(phase:.completed,message:"Hi! How can I help?")
                    }
                    do {
                        guard let plan=self.reviewWork.plan(job.scope.registration,conversation:job.conversationID) else {throw ActionFailure.message("The fictional plan is unavailable.")}
                        if job.human.lowercased().hasPrefix("add selected project tasks") {
                            let ids=plan.actions.filter{plan.selected.contains($0.id) && $0.destination.hasPrefix("Task in")}.map(\.id)
                            let results=try await self.reviewWork.performCaptured(job.id,revision:plan.revision,actions:ids,valid:valid)
                            let count=results.filter{$0.phase == .saved}.count
                            _=self.assistant.appendReview("\(count) selected project tasks completed.",conversationID:job.conversationID,turnID:job.responseTurnID)
                            return .init(phase:count == ids.count ? .completed : .failed,message:"\(count) actions completed",confirmedActions:count)
                        }
                        let entries=plan.actions.map {action in
                            ReviewPlanTools.Entry(existingID:action.id,selected:action.destination.hasPrefix("Task in"))
                        }
                        let args=String(decoding:try JSONEncoder().encode(ReviewPlanTools.Input(revision:plan.revision,actions:entries)),as:UTF8.self)
                        _=try await self.prepareReviewActions(.init(id:UUID().uuidString,name:"prepare_review_actions",namespace:"pa",arguments:args),job:job,valid:valid)
                        _=self.assistant.appendReview("The project tasks are checked; Calendar entries are unchecked. Press Approve to add the selected tasks.",conversationID:job.conversationID,turnID:job.responseTurnID)
                        return .init(phase:.completed,message:"The project tasks are checked; Calendar entries are unchecked. Press Approve to add the selected tasks.")
                    } catch {return .init(phase:.failed,message:error.localizedDescription,error:error.localizedDescription)}
                }
            }
            runtime.perform={job,action,valid in
                let payload=try JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)
                guard payload.nativeRequest == nil,payload.project != nil else {throw ActionFailure.message("Apple writes are disabled in this source-free preview.")}
                return try await self.performReviewAction(job,action,valid:valid)
            }
        }
        #endif
        return runtime
    }
    var reviewWorkReady:Bool {
        let needsInference=reviewWork.jobs(chatGPT.activeID).first(where:{$0.phase == .queued})?.mode != .approval
        return !heartbeat.busy && !assistant.busy && !chatGPT.busy && (!needsInference || (!chatGPT.usagePaused && chatGPT.inferenceVerified)) && !writing && !proactive.busy && !emailSummaries.busy && emailSummaries.feedback.activeID == nil && !briefings.busy && !memoryLearning.busy && !sourceLearning.busy && !nativeSourceLearning.busy && !memoryMaintenance.busy && !lifeOrganisation.busy && !projectPlacement.busy && heartbeat.deviceAvailable && !heartbeat.reviewComposerActive
    }
    func scheduleReviewWork() {
        guard reviewQueuePump == nil,reviewWork.readable else {return}
        reviewQueuePump=Task { @MainActor [weak self] in
            guard let self else {return}
            defer {self.reviewQueuePump=nil}
            while !Task.isCancelled,self.reviewWork.readable,(self.reviewWork.waiting(self.chatGPT.activeID)>0 || self.reviewWork.busy) {
                self.reviewWork.drive(self.reviewWorkRuntime())
                do {try await Task.sleep(for:.milliseconds(250))} catch {return}
            }
        }
    }
    func reviewSelectionContext(_ job:ReviewWorkJob)->String {
        if let plan=reviewWork.plan(job.scope.registration,conversation:job.conversationID),let data=try? JSONEncoder().encode(plan.actions.compactMap {action->[String:String]? in
            guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload) else {return nil}
            return ["id":action.id,"title":action.title,"destination":action.destination,"kind":payload.proposal.kind,"operation":payload.nativeOperation ?? "create","scope":payload.nativeScope ?? "","occurrenceID":payload.nativeBaseline?.occurrenceID ?? "","start":payload.proposal.proposedDate?.start ?? "","end":payload.proposal.proposedDate?.end ?? "","projectID":payload.project?.parentID?.uuidString ?? "","selected":String(plan.selected.contains(action.id)),"submitted":String(reviewWork.reserved(action.id,registration:job.scope.registration))]
        }) {
            return "Current editable Review plan revision: "+plan.revision.uuidString+". These are checkbox draft proposals, not write authority. Selected means the human's current checkbox choice. "+String(decoding:data,as:UTF8.self)
        }
        guard job.selectionActive == true else {return ""}
        if job.actions.isEmpty {return "The currently displayed prepared plan has NO selected actions. Selection is draft context, never independent authority. Do not interpret a mere acknowledgement as approval of unselected proposals; ask which action the human wants. They may explicitly request another plan."}
        struct Selected:Encodable {var title:String;var destination:String;var date:DiscoveryProposedDate?;var taskDue:String?}
        let selected=job.actions.compactMap {action->Selected? in
            guard let payload=try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload) else {return nil}
            return .init(title:action.title,destination:action.destination,date:payload.proposal.proposedDate,taskDue:payload.project?.due)
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let json=(try? encoder.encode(selected)).map{String(decoding:$0,as:UTF8.self)} ?? "[]"
        return "Captured UI context: the human selected only these historical prepared proposals. Unselected earlier proposals are not included in an acknowledgement. This is the plan actually shown for this reply; selection alone never authorises a save. Resolve the current human request against it, checking current support before new advice. Selected proposals: "+json
    }
    func submitReview(_ text:String,conversationID:UUID,actions:[ReviewWorkAction],focus:[LifeArea],humanControl:Bool=false,selectionActive:Bool=false)->Bool {
        guard let conversation=assistant.conversation(conversationID),let source=reviewSource(conversation),reviewPermits(source),ConversationRules.acceptsPrompt(text) else {return false}
        let approval=["yes","yes please","yep","go ahead","do that","ok","okay","add these","approve"].contains(text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".! "))) || text.trimmingCharacters(in:.whitespacesAndNewlines) == "👍"
        let concreteApproval=approval && !actions.isEmpty
        if concreteApproval {
            guard !actions.isEmpty,actions.allSatisfy({action in (try? JSONDecoder().decode(ReviewPreparedPayload.self,from:action.payload)).map(acceptedPreparedApproval) == true}) else {reviewWork.error="Choose a current concrete action first, or ask below for the missing detail.";return false}
        }
        let job=ReviewWorkJob(conversationID:conversationID,scope:reviewWorkScope(),source:source,mode:concreteApproval ? .approval : .conversation,human:text,humanControl:humanControl ? true : nil,selectionActive:selectionActive ? true : nil,focusAreas:focus.map(\.rawValue),actions:actions)
        guard reviewWork.submit(job) else {return false}
        if !assistant.busy,!chatGPT.busy {foregroundSendStarted(interruptReview:false)}
        reviewJobChanged(job);scheduleReviewWork();return true
    }
}
