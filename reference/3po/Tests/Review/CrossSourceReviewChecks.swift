import Foundation

/// Fictional unseen wording exercises selection and result contracts, not model quality.
enum CrossSourceReviewChecks {
    static func run() throws {
        let instant=Date(timeIntervalSince1970:1791000000)
        func card(_ id:String,_ title:String,_ quote:String)->PADiscovery {
            PADiscovery(id:id,registration:"A",mailID:"mail-"+id,kind:"calendar",message:"Review this proposal",evidence:quote,created:instant,scope:"scope",sourceTitle:title,sourceDate:instant)
        }
        let unrelated=(0..<20).map{card("unrelated-\($0)","Expense \($0)","Receipt for purchase \($0)")}
        let launch=card("launch","Lark demonstration rehearsal","Lark prototype rehearsal in lab Delta on 20 October.")
        let received=DiscoveryCandidate(alias:"wa_0",mailID:"chat-message",evidence:"",followUpEvidence:"",sourceKind:"whatsapp",sourceChatID:"lab",sourceIdentity:"linked",sourceText:"The Lark prototype rehearsal in lab Delta is moved to 22 October.",sourceDate:instant.addingTimeInterval(600))
        let selected=ProactiveRules.reconsiderationBatch(unrelated+[launch],progress:.init(),context:"current",sources:[received])
        precondition(selected.count == 12 && selected.first?.id == launch.id,"An older relevant Mail concern is supplied alongside a new WhatsApp correction")
        precondition(selected.filter{$0.id.hasPrefix("unrelated-")}.count == 11,"Unrelated pending work continues to receive fair reconsideration")
        let singleName=DiscoveryCandidate(alias:"wa_1",mailID:"other-message",evidence:"Lark has a new bicycle.",followUpEvidence:"")
        precondition(!ProactiveRules.reconsiderationBatch(unrelated+[launch],progress:.init(),context:"current",sources:[singleName]).contains{$0.id == launch.id},"A shared name alone cannot promote a historical card")
        var sourceRevision=received;sourceRevision.mailID=launch.mailID;sourceRevision.sourceKind=nil;sourceRevision.sourceIdentity=nil;sourceRevision.sourceChatID=nil;sourceRevision.sourceText="Corrected venue details."
        precondition(ProactiveRules.reconsiderationBatch(unrelated+[launch],progress:.init(),context:"current",sources:[sourceRevision]).first?.id == launch.id,"Exact source identity survives complete rewording")
        precondition(ProactiveRules.reconsiderationBatch([launch],progress:.init(),context:"c",limit:0,sources:[received]).isEmpty)
        var progress=ProactiveProgress()
        for _ in 0..<8 {
            let batch=ProactiveRules.reconsiderationBatch(unrelated+[launch],progress:progress,context:"current",sources:[received])
            progress=ProactiveRules.recordingReconsideration(progress,reviewed:batch,active:unrelated+[launch],context:"current")
        }
        precondition((unrelated+[launch]).allSatisfy{progress.reviewedProposalContexts?[$0.id] == "current"},"A repeatedly relevant topic cannot starve unrelated cards")

        let baseline=DiscoveryNativeTarget(kind:"event",itemID:"occurrence-1",sourceID:"calendar-A",title:"Lark demonstration",start:instant,end:instant.addingTimeInterval(3600),hasTime:false,writable:true,recurring:false,fingerprint:"exact-native-v1")
        var pending=launch;pending.kind="change";pending.proposedChange = .init(target:baseline,newDate:"2026-10-22",hasTime:false,connection:"Email postpones the same lab rehearsal",timeZoneID:TimeZone.current.identifier)
        var repeated=pending;repeated.id="whatsapp-duplicate";repeated.mailID=received.mailID;repeated.sourceKind="whatsapp";repeated.sourceIdentity="linked";repeated.sourceChatID="lab";repeated.sourceMessageID="message";repeated.evidence="The Lark prototype rehearsal in lab Delta is moved to 22 October.";repeated.proposedChange?.connection="WhatsApp repeats the exact same correction"
        func retained(_ value:PADiscovery,_ old:PADiscovery=pending,_ comparable:Set<String>?=nil)->Bool {
            !ProactiveRules.unreported([value],prior:[old],comparablePendingIDs:comparable ?? [old.id]).isEmpty
        }
        precondition(!retained(repeated),"Independent Mail and WhatsApp quotes cannot duplicate an exact pending native edit")
        precondition(retained(repeated,pending,[]),"A prior whose current evidence was not checked cannot suppress a new source")
        var changed=repeated;changed.proposedChange?.newDate="2026-10-23";precondition(retained(changed),"A later changed date remains eligible")
        changed=repeated;changed.proposedChange?.target.itemID="occurrence-2";precondition(retained(changed),"Same title/time in another occurrence remains distinct")
        changed=repeated;changed.proposedChange?.target.sourceID="calendar-B";precondition(retained(changed),"A different Calendar remains distinct")
        changed=repeated;changed.proposedChange?.target.fingerprint="new-revision";precondition(retained(changed),"A changed native baseline remains distinct")
        changed=repeated;changed.registration="B";precondition(retained(changed),"Accounts never share duplicate suppression")
        changed=repeated;changed.replaces=[pending.id];changed.replacementReason="Later exact correction";precondition(retained(changed),"Explicit validated replacement must update the history chain")
        var old=pending;old.reviewState="pending";precondition(retained(repeated,old),"An attempted or uncertain operation is not an unattempted proposal")
        old=pending;old.reviewState="approved";precondition(retained(repeated,old))
        old=pending;old.dismissed=true;precondition(retained(repeated,old),"Acknowledgement cannot imply completion of a new source")
        old=pending;old.retiredAt=instant;precondition(retained(repeated,old))
        precondition(ProactiveRules.unreported([pending,repeated],prior:[]).count == 1,"One comparison also retains one exact native action")
        var removal=pending;removal.kind="remove";removal.proposedChange=nil;removal.proposedRemoval = .init(target:baseline,connection:"Email cancellation",timeZoneID:TimeZone.current.identifier)
        var repeatedRemoval=repeated;repeatedRemoval.kind="remove";repeatedRemoval.proposedChange=nil;repeatedRemoval.proposedRemoval = .init(target:baseline,connection:"WhatsApp cancellation",timeZoneID:TimeZone.current.identifier)
        precondition(!retained(repeatedRemoval,removal),"The same exact occurrence cannot have two pending removals")
        repeatedRemoval.proposedRemoval?.scope="series";precondition(retained(repeatedRemoval,removal),"Scope is part of the exact action")
        var anotherCreation=launch;anotherCreation.id="same-title-separate";anotherCreation.mailID="separate-source";anotherCreation.sourceKind="whatsapp";anotherCreation.sourceIdentity="linked";anotherCreation.sourceChatID="other-group"
        precondition(retained(anotherCreation,launch),"Title, participant and date cannot deterministically merge separate creations")

        let dateProposal=DiscoveryProposedDate(start:"2026-10-22",end:"2026-10-23",hasTime:false,timeZoneID:TimeZone.current.identifier)
        var window=launch;window.proposedDate=dateProposal
        let row=ProactiveRules.earlierRows(["review_0":window],targets:[:])[0]
        precondition(row["endDate"] as? String == "2026-10-23" && row["timeZone"] as? String == TimeZone.current.identifier,"Historical creation context retains the whole proposed date window")
        precondition(row["historicalProposal"] as? Bool == true && row["source"] as? String == "mail")

        let correction=#"{"suggestions":[{"mailID":"wa_0","kind":"change","message":"The lab rehearsal has moved.","evidence":"The Lark prototype rehearsal in lab Delta is moved to 22 October.","targetID":"event_0","newDate":"2026-10-22","hasTime":false,"connection":"Exact Lark rehearsal and lab match the earlier email.","replaces":["review_0"],"replacementReason":"Later WhatsApp correction identifies the same lab rehearsal."}]}"#
        var previous=pending;previous.proposedChange?.newDate="2026-10-20"
        let decoded=try ProactiveRules.decode(correction,candidates:[received],registration:"A",scope:"scope",now:instant.addingTimeInterval(900),targets:["event_0":baseline],earlier:["review_0":previous])
        let chain=try ProactiveRules.reconciled(decoded,prior:[previous],issued:["review_0":previous],now:instant.addingTimeInterval(900),permittedEarlier:[previous.id])
        precondition(chain[0].supersededBy == decoded[0].id && chain[1].replaces == [previous.id],"A supported Mail/WhatsApp correction updates one advice chain without a native write")
        var otherOccurrence=baseline;otherOccurrence.itemID="other-occurrence"
        do {
            _=try ProactiveRules.decode(correction,candidates:[received],registration:"A",scope:"scope",now:instant.addingTimeInterval(900),targets:["event_0":otherOccurrence],earlier:["review_0":previous])
            preconditionFailure("Common title cannot redirect a correction to another occurrence")
        } catch {}
        var cancellation=received;cancellation.sourceText="The Lark prototype rehearsal in lab Delta is cancelled.";cancellation.sourceDate=instant.addingTimeInterval(1200)
        let cancelled=#"{"suggestions":[{"mailID":"wa_0","kind":"remove","message":"The lab rehearsal is cancelled.","evidence":"The Lark prototype rehearsal in lab Delta is cancelled.","targetID":"event_0","scope":"occurrence","connection":"Exact earlier lab rehearsal.","replaces":["review_0"],"replacementReason":"Later WhatsApp cancels this exact lab rehearsal."}]}"#
        let cancelRows=try ProactiveRules.decode(cancelled,candidates:[cancellation],registration:"A",scope:"scope",now:instant.addingTimeInterval(1500),targets:["event_0":baseline],earlier:["review_0":previous])
        precondition(cancelRows[0].proposedRemoval?.target == baseline && cancelRows[0].replaces == [previous.id],"Cancellation retains exact occurrence approval and historical provenance")
        print("PASS cross-source Review: bounded relevant/fair context, exact Mail/WhatsApp native duplicates, corrections/cancellations and separate same-title situations; no model or native writes")
    }
}
