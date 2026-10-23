import Foundation
@main struct ReviewInboxChecks {
    @MainActor static func main() async throws {
        try await ReviewFeedbackChecks.run()
        let now=Date.now,quote="The Orion prototype report deadline has moved to 20 October 2026."
        let targetTask=TaskItem(id:"exact-orion",listID:"studies",title:"Submit Orion prototype report",due:Calendar.current.date(from:DateComponents(year:2026,month:10,day:16)),hasTime:false,sourceLabel:"Studies",writable:true,recurring:false,modified:now)
        let target=DiscoveryNativeTarget.reminder(targetTask)
        let candidate=DiscoveryCandidate(alias:"wa_0",mailID:"opaque-message",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:"studies",sourceMessageID:"message",sourceIdentity:"linked",sourceRevision:"rev1",sourceLabel:"Orion project",sourceText:quote)
        let json=#"{"suggestions":[{"mailID":"wa_0","kind":"change","targetID":"reminder_0","newDate":"2026-10-20","hasTime":false,"connection":"The same distinctive Orion report is named in the message and reminder.","message":"The Orion message moves the deadline from 16 to 20 October. Review the reminder date?","evidence":"The Orion prototype report deadline has moved to 20 October 2026."}]}"#
        func decode(_ text:String,_ targets:[String:DiscoveryNativeTarget] = ["reminder_0":target]) throws->[PADiscovery] {try ProactiveRules.decode(text,candidates:[candidate],registration:"account",scope:"scope",now:now,targets:targets)}
        var actionFixture=PADiscovery(id:UUID().uuidString,registration:"account",mailID:"fictional-safety-guidance",kind:"calendar",message:"Receipt confirmed; read the supplied guidance.",evidence:"Read the supplied guidance.",created:now,scope:"scope",sourceTitle:"Fictional safety guidance")
        precondition(!ProactiveReviewRules.hasSuggestedAction(actionFixture),"Informational Calendar-labelled concerns without a date do not offer Explore")
        actionFixture.proposedDate = .init(start:"2026-10-20",hasTime:false,timeZoneID:TimeZone.current.identifier)
        precondition(ProactiveReviewRules.hasSuggestedAction(actionFixture),"A concrete Calendar date retains Explore")
        actionFixture.proposedDate?.start="2026-02-30"
        precondition(!ProactiveReviewRules.hasSuggestedAction(actionFixture),"An impossible date is not a concrete action")
        actionFixture.kind="reminder";actionFixture.proposedDate=nil
        precondition(ProactiveReviewRules.hasSuggestedAction(actionFixture),"Undated Reminder actions stay available")
        actionFixture.kind="reply"
        precondition(!ProactiveReviewRules.hasSuggestedAction(actionFixture),"Reply labels without a saved draft do not offer Explore")
        actionFixture.replyDraft="  ";precondition(!ProactiveReviewRules.hasSuggestedAction(actionFixture),"Whitespace-only drafts are not actions")
        actionFixture.replyDraft="Thanks for the update.";precondition(ProactiveReviewRules.hasSuggestedAction(actionFixture),"Saved reply copies retain Explore")
        actionFixture.kind="update";precondition(!ProactiveReviewRules.hasSuggestedAction(actionFixture),"Background context alone never offers Explore")
        actionFixture.kind="project";precondition(ProactiveReviewRules.hasSuggestedAction(actionFixture),"Concrete new spaces retain Explore")
        actionFixture.kind="projectTask";precondition(!ProactiveReviewRules.hasSuggestedAction(actionFixture),"Project tasks need a captured destination")
        actionFixture.proposedProjectTask = .init(target:.init(id:UUID(),revision:UUID(),title:"Fictional project"),connection:"Named project")
        precondition(ProactiveReviewRules.hasSuggestedAction(actionFixture),"Tasks in a captured project retain Explore")
        var repeated=actionFixture;repeated.kind="reminder";repeated.proposedProjectTask=nil;repeated.replyDraft=nil;repeated.sourceRevision="same-source";repeated.sourceAssessmentRevision="same-assessment"
        var alias=repeated;alias.id=UUID().uuidString;alias.evidence="Another exact quotation about that same task."
        precondition(ProactiveRules.sameProposal(repeated,alias),"Same named action from one source assessment coalesces across quoted explanations")
        alias.sourceAssessmentRevision="different-assessment";precondition(!ProactiveRules.sameProposal(repeated,alias),"Unverified historical quote rewrites do not imply equivalence")
        alias=repeated;alias.id=UUID().uuidString;alias.evidence="Another quotation";alias.proposedDate = .init(start:"2026-10-20",hasTime:false,timeZoneID:TimeZone.current.identifier)
        precondition(!ProactiveRules.sameProposal(repeated,alias),"A different due date remains a distinct proposed action")
        alias=repeated;alias.evidence="Another quotation";alias.kind="calendar";precondition(!ProactiveRules.sameProposal(repeated,alias),"Calendar and Reminder destinations never coalesce")
        alias=repeated;alias.evidence="Another quotation";alias.mailID="another-message";precondition(!ProactiveRules.sameProposal(repeated,alias),"Different source messages retain distinct quote evidence")
        let record=try decode(json)[0],change=record.proposedChange!
        precondition(ProactiveReviewRules.hasSuggestedAction(record),"Exact native changes retain Explore")
        precondition(change.target.itemID == targetTask.id && change.target.sourceID == "studies" && DateRules.localDate(change.date()!) == "2026-10-20")
        precondition(change.target.matches(events:[],reminders:[targetTask],excludedCalendars:[],excludedLists:[]))
        var moved=targetTask;moved.due=change.date()
        precondition(!change.target.matches(events:[],reminders:[moved],excludedCalendars:[],excludedLists:[]))
        moved=targetTask;moved.modified=now.addingTimeInterval(1)
        precondition(!change.target.matches(events:[],reminders:[moved],excludedCalendars:[],excludedLists:[]))
        precondition(!change.target.matches(events:[],reminders:[targetTask],excludedCalendars:[],excludedLists:["studies"]))
        func reject(_ text:String,_ targets:[String:DiscoveryNativeTarget] = ["reminder_0":target]) {do {_=try decode(text,targets);fatalError("Unexpected proposal accepted")}catch{}}
        reject(json.replacingOccurrences(of:"reminder_0",with:"invented"))
        reject(json.replacingOccurrences(of:"2026-10-20",with:"2026-02-30"))
        reject(json.replacingOccurrences(of:quote,with:"invented evidence"))
        reject(json.replacingOccurrences(of:"\"change\"",with:"\"delete\""))
        var readOnly=target;readOnly.writable=false;reject(json,["reminder_0":readOnly])
        reject(json.replacingOccurrences(of:"2026-10-20",with:"2026-10-16"))
        var changed=record;changed.proposedChange?.newDate="2026-10-21"
        precondition(ProactiveRules.unreported([record],prior:[record]).isEmpty)
        precondition(ProactiveRules.unreported([changed],prior:[record]).count == 1)
        var previousUpdate=record;previousUpdate.kind="update";previousUpdate.proposedChange=nil
        precondition(ProactiveRules.unreported([record],prior:[previousUpdate]).count == 1)
        var otherZone=record;otherZone.proposedChange?.timeZoneID="Pacific/Honolulu"
        precondition(ProactiveRules.unreported([record],prior:[otherZone]).count == 1)
        precondition(otherZone.proposedChange?.date() == nil)
        var many=ProactiveProgress();many.delivered=10000
        precondition(ProactiveRules.allowed(many,now:now,manual:true))
        precondition(ProactiveRules.allowed(many,now:now,heartbeat:true,comparisonLimit:96))
        var stopped=many;stopped.paused=true;stopped.lastAttempt=now;stopped.attempts=1
        precondition(!ProactiveRules.allowed(stopped,now:now,heartbeat:true,comparisonLimit:96,cooldown:3600))
        precondition(ProactiveRules.allowed(stopped,now:now.addingTimeInterval(3600),heartbeat:true,comparisonLimit:96,cooldown:3600),"A fresh due heartbeat can recover a failed comparison")
        precondition(!ProactiveRules.allowed(stopped,now:now.addingTimeInterval(3600)),"Independent discovery retains explicit retry policy")
        stopped.attempts=96
        precondition(!ProactiveRules.allowed(stopped,now:now.addingTimeInterval(3600),heartbeat:true,comparisonLimit:96,cooldown:3600),"Recovery cannot bypass comparison allowance")
        // Removal requires one issued writable Calendar occurrence and explicit occurrence scope.
        let cancellation="The Orion Computer Vision lecture on 12 October 2026 at 14:00 is postponed. A new date will be announced later."
        let event=AgendaEvent(id:"exact-lecture-occurrence",calendarID:"studies",title:"Orion Computer Vision lecture",start:now.addingTimeInterval(86400),end:now.addingTimeInterval(90000),allDay:false,location:"Room 1",sourceLabel:"Studies",modified:now)
        let eventTarget=DiscoveryNativeTarget.event(event,writable:true)
        var cancelledCandidate=candidate;cancelledCandidate.sourceText=cancellation;cancelledCandidate.sourceDate=now
        let removalJSON=#"{"suggestions":[{"mailID":"wa_0","kind":"remove","targetID":"event_0","scope":"occurrence","connection":"The distinctive Orion lecture and its old slot match this event; it has been postponed with no replacement date.","message":"Remove this postponed lecture from Calendar?","evidence":"The Orion Computer Vision lecture on 12 October 2026 at 14:00 is postponed. A new date will be announced later."}]}"#
        func decodeRemoval(_ text:String,_ issued:[String:DiscoveryNativeTarget] = ["event_0":eventTarget],earlier:[String:PADiscovery] = [:])throws->[PADiscovery] {
            try ProactiveRules.decode(text,candidates:[cancelledCandidate],registration:"account",scope:"scope",now:now,targets:issued,earlier:earlier)
        }
        func rejectRemoval(_ text:String,_ issued:[String:DiscoveryNativeTarget] = ["event_0":eventTarget],earlier:[String:PADiscovery] = [:]) {
            do {_=try decodeRemoval(text,issued,earlier:earlier);fatalError("Unsupported removal accepted")}catch{}
        }
        let removalRecord=try decodeRemoval(removalJSON)[0]
        precondition(removalRecord.proposedChange == nil && removalRecord.proposedRemoval?.valid == true && removalRecord.nativeTarget == eventTarget)
        func withoutField(_ text:String,_ field:String)throws->String {
            var payload=try JSONSerialization.jsonObject(with:Data(text.utf8)) as! [String:Any]
            var suggestions=payload["suggestions"] as! [[String:Any]];suggestions[0].removeValue(forKey:field);payload["suggestions"]=suggestions
            return String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self)
        }
        let noRemovalProse=try withoutField(removalJSON,"message")
        let localQuestion=try decodeRemoval(noRemovalProse)[0]
        precondition(localQuestion.proposedRemoval == removalRecord.proposedRemoval && localQuestion.message == "Remove this cancelled or postponed occurrence from Calendar?","A valid removal still presents a local approval question if optional model prose is absent")
        reject(try withoutField(json,"message"))
        precondition(removalRecord.proposedRemoval?.scope == "occurrence")
        rejectRemoval(removalJSON.replacingOccurrences(of:"event_0",with:"invented"))
        rejectRemoval(removalJSON,["event_0":target]) // No Reminder removal in background review.
        var lockedEvent=eventTarget;lockedEvent.writable=false;rejectRemoval(removalJSON,["event_0":lockedEvent])
        rejectRemoval(removalJSON.replacingOccurrences(of:"occurrence",with:"futureEvents"))
        rejectRemoval(try withoutField(removalJSON,"scope"))
        rejectRemoval(removalJSON.replacingOccurrences(of:#""scope":"occurrence""#,with:#""scope":"occurrence","newDate":"2026-10-20""#))
        rejectRemoval(removalJSON.replacingOccurrences(of:cancellation,with:"Invented cancellation"))
        precondition(removalRecord.nativeTarget!.matches(events:[event],reminders:[],excludedCalendars:[],excludedLists:[]))
        var externalEvent=event;externalEvent.location="Room 2"
        precondition(!removalRecord.nativeTarget!.matches(events:[externalEvent],reminders:[],excludedCalendars:[],excludedLists:[]))
        precondition(!removalRecord.nativeTarget!.matches(events:[event],reminders:[],excludedCalendars:["studies"],excludedLists:[]))
        precondition(ProactiveRules.unreported([removalRecord],prior:[removalRecord]).isEmpty)
        var notice=removalRecord;notice.kind="update";notice.proposedRemoval=nil;notice.created=now.addingTimeInterval(-3600);notice.sourceDate=notice.created
        precondition(ProactiveRules.unreported([removalRecord],prior:[notice]).count == 1)
        var dateProposal=record;dateProposal.proposedChange?.target=eventTarget
        precondition(!ProactiveRules.sameProposal(dateProposal,removalRecord))
        var wrongZone=removalRecord;wrongZone.proposedRemoval?.timeZoneID="Pacific/Honolulu"
        precondition(wrongZone.proposedRemoval?.valid == false && !ProactiveRules.sameProposal(wrongZone,removalRecord))
        let replacementJSON=removalJSON.replacingOccurrences(of:#""scope":"occurrence""#,with:#""scope":"occurrence","replaces":["review_0"],"replacementReason":"The newer explicit postponement makes the old date proposal obsolete.""#)
        var oldDate=dateProposal;oldDate.created=notice.created;oldDate.sourceDate=notice.created
        let replacement=try decodeRemoval(replacementJSON,earlier:["review_0":oldDate])[0]
        let reconciled=try ProactiveRules.reconciled([replacement],prior:[oldDate],issued:["review_0":oldDate],now:now)
        precondition(reconciled[0].supersededBy == replacement.id && reconciled[0].proposedChange == oldDate.proposedChange)
        var unrelated=oldDate;unrelated.proposedChange?.target.itemID="other-occurrence"
        rejectRemoval(replacementJSON,earlier:["review_0":unrelated])
        var unchangedUpdate=removalRecord;unchangedUpdate.kind="update";unchangedUpdate.proposedRemoval=nil
        let upgrade=try decodeRemoval(replacementJSON,earlier:["review_0":unchangedUpdate])[0]
        precondition(upgrade.replaces == [unchangedUpdate.id],"An existing update can become an actionable removal from its same exact source")
        unchangedUpdate.evidence="A different concern from that message."
        rejectRemoval(replacementJSON,earlier:["review_0":unchangedUpdate])
        let removalRoundtrip=try JSONDecoder().decode(ProactiveState.self,from:JSONEncoder().encode(ProactiveState(records:[removalRecord])))
        precondition(removalRoundtrip.records == [removalRecord])
        var ambiguousRemoval=removalRecord;ambiguousRemoval.evidence=weekQuoteForRemoval()
        precondition(ProactiveRules.reviewProjection(ambiguousRemoval).proposedRemoval == nil)
        func weekQuoteForRemoval()->String {"The Orion lecture on Wednesday of week one is cancelled."}
        let versions=Dictionary(uniqueKeysWithValues:(0..<8).map{(ProactiveRules.sourceKey("whatsapp",String($0)),"v1")})
        let firstKeys=Set((0..<3).map{ProactiveRules.sourceKey("whatsapp",String($0))})
        let limited=ProactiveRules.completing(many,versions:versions,context:"epoch",limited:true,reportedKeys:firstKeys)
        precondition(limited.assessedSourceVersions?.isEmpty == true,"A saturated compound result leaves all sources eligible for completion")
        precondition(!ProactiveRules.assessed(limited,kind:"whatsapp",id:"7",revision:"v1",context:"epoch"))
        let quiet=ProactiveRules.completing(limited,versions:versions,context:"epoch",limited:false,reportedKeys:[])
        precondition(quiet.assessedSourceVersions?.count == 8)
        precondition(ProactiveRules.assessed(quiet,kind:"whatsapp",id:"7",revision:"v1",context:"epoch"))
        precondition(!ProactiveRules.assessed(quiet,kind:"whatsapp",id:"7",revision:"v2",context:"epoch"))
        precondition(!ProactiveRules.assessed(quiet,kind:"whatsapp",id:"7",revision:"v1",context:"changed-native-context"))
        let restored=try JSONDecoder().decode(ProactiveState.self,from:JSONEncoder().encode(ProactiveState(accounts:["account":quiet],records:[record])))
        precondition(restored.records == [record] && restored.accounts["account"]?.assessedSourceVersions == quiet.assessedSourceVersions)
        var legacy=record;legacy.proposedChange=nil;legacy.reviewState=nil;legacy.reviewedAt=nil
        let legacyRoundtrip=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(legacy));precondition(legacyRoundtrip.proposedChange == nil)
        let timed=DiscoveryDateChange(target:target,newDate:"2026-10-20T17:00:00+01:00",hasTime:true,connection:"Exact quoted time",timeZoneID:TimeZone.current.identifier)
        precondition(timed.date() == ISO8601DateFormatter().date(from:"2026-10-20T16:00:00Z"))
        let weekQuote="The form deadline has moved to Wednesday of week one."
        var weekCandidate=candidate;weekCandidate.sourceText=weekQuote
        let weekJSON=json.replacingOccurrences(of:quote,with:weekQuote)
        let grounded=try ProactiveRules.decode(weekJSON,candidates:[weekCandidate],registration:"account",scope:"scope",now:now,targets:["reminder_0":target])[0]
        precondition(grounded.kind == "update" && grounded.proposedChange == nil && grounded.message.contains("Date needs clarification"))
        precondition(grounded.evidence == weekQuote && grounded.sourceRevision == candidate.sourceRevision)
        var oldWeek=record;oldWeek.evidence=weekQuote
        let projected=ProactiveRules.reviewProjection(oldWeek)
        precondition(projected.id == oldWeek.id && projected.kind == "update" && projected.proposedChange == nil && oldWeek.proposedChange != nil)
        precondition(projected.sourceAssessmentRevision == oldWeek.sourceAssessmentRevision && projected.evidence == oldWeek.evidence)
        oldWeek.reviewState="pending";precondition(ProactiveRules.reviewProjection(oldWeek) == oldWeek,"An uncertain save receipt must remain inspectable")
        oldWeek.reviewState="approved";precondition(ProactiveRules.reviewProjection(oldWeek) == oldWeek,"An approved receipt must never be rewritten")
        precondition(ProactiveRules.reviewProjection(record) == record,"An explicitly dated source remains reviewable")
        // A source stays pending across capped responses, exhausted allowance and
        // restart. Simulated responses use the real decoder and persisted receipts.
        var review=PAHeartbeatAccount(),timeline=ProactiveState(accounts:["fixture":.init()])
        let mailVersions=Dictionary(uniqueKeysWithValues:(0..<8).map{(ProactiveRules.sourceKey("mail","fixture-\($0)"),"v1")})
        var issued=0
        func round(_ time:Date)throws {
            let day=BriefingRules.day(time)
            guard PAHeartbeatRules.due(review,now:time,day:day,allowance:2) else {return}
            let progress=timeline.accounts["fixture"]!
            let waiting=(0..<8).filter{!ProactiveRules.assessed(progress,kind:"mail",id:"fixture-\($0)",revision:"v1",context:"stable")}
            review.checked=time
            guard !waiting.isEmpty else {
                review=PAHeartbeatRules.quiet(review,fingerprint:"stable",ready:[],pending:false);return
            }
            do {review=try PAHeartbeatRules.claim(review,day:day,limit:2)} catch is HeartbeatBudgetExhausted {
                review=PAHeartbeatRules.deferred(review,now:time,reason:.allowance);return
            }
            issued += 1
            let batch=Array(waiting.prefix(3)),candidates=batch.map{DiscoveryCandidate(alias:"mail_\($0)",mailID:"fixture-\($0)",evidence:"Submit fictional report \($0) by 20 October 2026.",followUpEvidence:"",sourceRevision:"v1")}
            let payload:[String:Any]=["suggestions":candidates.map{["mailID":$0.alias,"kind":"reminder","message":"Review this fictional report submission?","evidence":$0.evidence]}]
            let rows=try ProactiveRules.decode(String(decoding:try JSONSerialization.data(withJSONObject:payload),as:UTF8.self),candidates:candidates,registration:"fixture",scope:"fixture",now:time)
            timeline.records += ProactiveRules.unreported(rows,prior:timeline.records)
            timeline.accounts["fixture"]=ProactiveRules.completing(progress,versions:mailVersions.filter{key,_ in batch.contains{key == ProactiveRules.sourceKey("mail","fixture-\($0)")}},context:"stable",limited:batch.count >= 24,reportedKeys:Set(batch.map{ProactiveRules.sourceKey("mail","fixture-\($0)")}))
            review.phase="idle";review.assessed=time;review.pending=timeline.accounts["fixture"]!.assessedSourceVersions?.count != 8
            review=PAHeartbeatRules.clearWait(review)
            timeline=try JSONDecoder().decode(ProactiveState.self,from:JSONEncoder().encode(timeline))
            review=PAHeartbeatRules.recovered(try JSONDecoder().decode(PAHeartbeatAccount.self,from:JSONEncoder().encode(review)),now:time)
        }
        let start=ISO8601DateFormatter().date(from:"2026-10-07T08:00:00Z")!
        try round(start);precondition(timeline.records.count == 3 && review.pending == true)
        try round(start.addingTimeInterval(3600));precondition(timeline.records.count == 6 && review.calls == 2 && review.pending == true)
        try round(start.addingTimeInterval(7200));precondition(issued == 2 && review.retryReason == "allowance" && review.pending == true)
        let nextDay=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:start))!
        try round(nextDay);precondition(issued == 3 && timeline.records.count == 8 && review.calls == 1 && review.pending == false)
        for hour in 1...48 {try round(nextDay.addingTimeInterval(Double(hour)*3600))}
        precondition(issued == 3 && timeline.records.count == 8 && Set(timeline.records.map(\.mailID)).count == 8 && review.pending == false,"Quiet multi-day checks must neither repeat requests nor lose capped sources")
        let mail=try JSONDecoder().decode(MailMessage.self,from:Data(#"{"id":"mail-ack","accountID":"provider","account":"Fictional","messageID":1,"internetMessageID":"ack@example.invalid","sender":"Tutor","subject":"Orion report","received":"2026-10-07T09:00:00Z","unread":true,"replied":false,"flagged":false}"#.utf8))
        let assessment=EmailSummary(id:mail.id,registration:"account",fingerprint:EmailSummary.fingerprint(mail),summary:"Submit the report.",attention:true,reason:"Report requested",evidence:"Submit the report.",bodyFingerprint:"body-v1",message:mail)
        var ack=record;ack.sourceKind=nil;ack.mailID=mail.id;ack.sourceRevision=assessment.fingerprint;ack.sourceAssessmentRevision=assessment.adviceRevision(replied:false);ack.dismissed=true;ack.dismissedAt=now;ack.dismissedSourceVersion=ReviewAcknowledgementRules.emailVersion(mail,assessment)
        precondition(ReviewAcknowledgementRules.matches(ack,message:mail,summary:assessment,registration:"account"))
        var regenerated=assessment;regenerated.summary="Different generated wording for the same request."
        precondition(ReviewAcknowledgementRules.matches(ack,message:mail,summary:regenerated,registration:"account"),"Regenerated wording is not a new concern")
        regenerated.bodyFingerprint="body-v2"
        precondition(!ReviewAcknowledgementRules.matches(ack,message:mail,summary:regenerated,registration:"account"),"Changed source content can need attention")
        precondition(!ReviewAcknowledgementRules.matches(ack,message:mail,summary:assessment,registration:"another-account"))
        let newMail=try JSONDecoder().decode(MailMessage.self,from:Data(#"{"id":"new-mail","accountID":"provider","account":"Fictional","messageID":2,"internetMessageID":"new@example.invalid","sender":"Tutor","subject":"Orion report","received":"2026-10-07T10:00:00Z","unread":true,"replied":false,"flagged":false}"#.utf8))
        precondition(!ReviewAcknowledgementRules.matches(ack,message:newMail,summary:assessment,registration:"account"),"Same sender and title do not acknowledge a new message")
        precondition(ReviewInboxRules.belongs(ack,to:mail,summary:assessment),"Exact current email and its background receipt share a card")
        var grouping=ack;grouping.registration="another-account"
        precondition(!ReviewInboxRules.belongs(grouping,to:mail,summary:assessment),"Another registration cannot be grouped into this card")
        grouping=ack;grouping.sourceKind="whatsapp"
        precondition(!ReviewInboxRules.belongs(grouping,to:mail,summary:assessment),"WhatsApp and Mail are separate exact sources")
        grouping=ack;grouping.sourceRevision="stale-source"
        precondition(!ReviewInboxRules.belongs(grouping,to:mail,summary:assessment))
        grouping=ack;grouping.sourceAssessmentRevision="stale-assessment"
        precondition(!ReviewInboxRules.belongs(grouping,to:mail,summary:assessment))
        var otherAssessment=assessment;otherAssessment.id=newMail.id;otherAssessment.message=newMail;otherAssessment.fingerprint=EmailSummary.fingerprint(newMail)
        precondition(!ReviewInboxRules.belongs(ack,to:newMail,summary:otherAssessment),"Same subject and sender cannot collapse distinct emails")
        grouping=ack;grouping.sourceRevision=nil;grouping.sourceAssessmentRevision=nil
        precondition(ReviewInboxRules.belongs(grouping,to:mail,summary:assessment),"Legacy exact-source records retain their presentation")
        var regeneratedProposal=ack;regeneratedProposal.dismissed=false;regeneratedProposal.sourceAssessmentRevision="regenerated-assessment"
        let acknowledgedVersions=[ProactiveRules.sourceKey("mail",mail.id):ReviewAcknowledgementRules.emailVersion(mail,assessment)]
        precondition(ProactiveRules.unreported([regeneratedProposal],prior:[ack],dismissedVersions:acknowledgedVersions).isEmpty,"Same exact dismissed concern stays acknowledged after prose regeneration")
        var sibling=regeneratedProposal;sibling.proposedChange=nil;sibling.kind="reminder";sibling.evidence="Return the separate safety form."
        precondition(ProactiveRules.unreported([sibling],prior:[ack],dismissedVersions:acknowledgedVersions).count == 1,"A dismissed date change cannot hide a separate action")
        var firstAction=ack;firstAction.proposedChange=nil;firstAction.kind="reminder"
        precondition(ProactiveRules.unreported([sibling],prior:[firstAction],dismissedVersions:acknowledgedVersions).count == 1,"Two reminder concerns with different source quotes stay distinct")
        var undone=ack;undone.dismissed=false
        precondition(!ReviewAcknowledgementRules.matches(undone,message:mail,summary:assessment,registration:"account"),"Undo restores eligibility")
        let restoredAck=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(ack))
        precondition(restoredAck.dismissedAt == now && restoredAck.dismissedSourceVersion == ack.dismissedSourceVersion && restoredAck.proposedChange == record.proposedChange && restoredAck.reviewState == nil)
        let wa=WhatsAppReadMessage(id:"message",chat:"studies",sender:"Tutor",text:quote,sentByMe:false,time:now.timeIntervalSince1970*1000)
        var waAck=record;waAck.dismissed=true;waAck.sourceRevision=SourceContextRules.revision(wa)
        precondition(ReviewAcknowledgementRules.matches(waAck,message:wa,registration:"account",identity:"linked"))
        precondition(!ReviewAcknowledgementRules.matches(waAck,message:wa,registration:"account",identity:"different-device"))
        let editedWA=WhatsAppReadMessage(id:wa.id,chat:wa.chat,sender:wa.sender,text:"A new report deadline.",sentByMe:false,time:wa.time)
        precondition(!ReviewAcknowledgementRules.matches(waAck,message:editedWA,registration:"account",identity:"linked"))
        print("PASS review inbox: exact evidence/native guards, persistent acknowledgement, regenerated wording, changed content, new messages, account/WhatsApp identity, Undo, bounded scheduling and legacy decode. No native writes or AI.")
    }
}
