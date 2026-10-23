import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main()throws {
        let now=Date.now,registration="fictional"
        let calendar=SourceOption(id:"calendar",title:"University",account:"Fictional",writable:true,providerID:"provider")
        var event=AgendaEvent(id:"occurrence",calendarID:calendar.id,title:"Orion engineering supervision",start:now.addingTimeInterval(86400),end:now.addingTimeInterval(90000),allDay:false,location:"Private address excluded",sourceLabel:calendar.label,modified:now.addingTimeInterval(-3600),memoryItemID:"stable-occurrence")
        func calendarItem()->NativeLearningItem { NativeSourceAdapters.calendar(.init(start:now,end:now.addingTimeInterval(90*86400),refreshed:now,calendar:.init(sources:[calendar],events:[event])),sources:[],now:now).first! }
        let first=calendarItem()
        precondition(first.id == NativeLearningRules.hash(first.identity),"Stored source IDs retain the original canonical identity hash")
        var identityEdit=first
        identityEdit.identity.itemID="fictional-new-exact-item"
        precondition(identityEdit.id != first.id && identityEdit.id == NativeLearningRules.hash(identityEdit.identity),"Nested identity edits refresh the exact source ID")
        identityEdit.identity=first.identity
        precondition(identityEdit == first,"Restoring an identity restores exact value equality without changing the original copy")
        identityEdit.revision="changed-source-content"
        precondition(identityEdit.id == first.id,"A content revision does not change source identity")
        var composedIdentity=first;composedIdentity.identity.itemID="\u{00e9}"
        var decomposedIdentity=composedIdentity;decomposedIdentity.identity.itemID="e\u{0301}"
        precondition(composedIdentity == decomposedIdentity && composedIdentity.id != decomposedIdentity.id,"Canonical Unicode value equality cannot hide an exact-byte identity hash change")
        precondition(decomposedIdentity.id == NativeLearningRules.hash(decomposedIdentity.identity),"Every identity assignment retains the original exact hash, including equivalent Unicode spellings")
        let mailProjection=MailLearningProjectionCache()
        var mailKey=MailLearningProjectionKey(collectionRevision:1,summaryRevision:1,registration:registration,excluded:[])
        var mailBuilds=0
        let expiry=now.addingTimeInterval(10)
        for _ in 0..<200 {_=mailProjection.items(key:mailKey,now:now,until:expiry){mailBuilds += 1;return [first]}}
        precondition(mailBuilds == 1,"Repeated unchanged Mail quote projections build once")
        mailKey.collectionRevision += 1;_=mailProjection.items(key:mailKey,now:now,until:expiry){mailBuilds += 1;return []}
        mailKey.summaryRevision += 1;_=mailProjection.items(key:mailKey,now:now,until:expiry){mailBuilds += 1;return []}
        mailKey.registration="other";_=mailProjection.items(key:mailKey,now:now,until:expiry){mailBuilds += 1;return []}
        mailKey.excluded=["account"];_=mailProjection.items(key:mailKey,now:now,until:expiry){mailBuilds += 1;return []}
        precondition(mailBuilds == 5,"Mail/index, every summary update, ownership and source exclusions invalidate formatted quote projections")
        _=mailProjection.items(key:mailKey,now:expiry,until:expiry){mailBuilds += 1;return [first]}
        precondition(mailBuilds == 6,"Exact quote expiry rebuilds rather than retaining a result across the boundary")
        _=mailProjection.items(key:mailKey,now:expiry.addingTimeInterval(1),until:expiry.addingTimeInterval(86400)){mailBuilds += 1;return []}
        _=mailProjection.items(key:mailKey,now:now.addingTimeInterval(-1),until:expiry){mailBuilds += 1;return []}
        precondition(mailBuilds == 8,"The first post-expiry callback and clock rollback rebuild current quote eligibility")
        precondition(MailLearningProjectionCache.deadline(checked:[now.addingTimeInterval(-86390)],now:expiry) == expiry,"An inclusive 24-hour edge is never cached beyond that instant")
        precondition(MailLearningProjectionCache.deadline(checked:[expiry],now:now) == expiry,"Future checked timestamps invalidate when they become current")
        let projection=NativeLearningProjectionCache()
        var projectionKey=NativeLearningProjectionKey(collectionRevision:1,excluded:[],timezone:"Europe/London",locale:"en_GB:gregorian",day:Calendar.current.startOfDay(for:now))
        var projectionBuilds=0
        for _ in 0..<200 {
            precondition(projection.items(.calendar,key:projectionKey){projectionBuilds += 1;return [first]} == [first])
        }
        precondition(projectionBuilds == 1,"Repeated permission checks reuse unchanged source prose rather than recreating date formatters and hashes")
        projectionKey.collectionRevision += 1
        _=projection.items(.calendar,key:projectionKey){projectionBuilds += 1;return []}
        precondition(projectionBuilds == 2,"A collected source change invalidates the projection")
        projectionKey.excluded=[calendar.id]
        precondition(projection.items(.calendar,key:projectionKey){projectionBuilds += 1;return []}.isEmpty && projectionBuilds == 3,"Source exclusion cannot reuse earlier permitted items")
        projectionKey.timezone="UTC";_=projection.items(.calendar,key:projectionKey){projectionBuilds += 1;return []}
        projectionKey.locale="fr_FR:gregorian";_=projection.items(.calendar,key:projectionKey){projectionBuilds += 1;return []}
        projectionKey.day=projectionKey.day.addingTimeInterval(86400);_=projection.items(.calendar,key:projectionKey){projectionBuilds += 1;return []}
        precondition(projectionBuilds == 6,"Timezone, locale and day changes rebuild source formatting")
        _=projection.items(.reminder,key:projectionKey){projectionBuilds += 1;return []}
        precondition(projectionBuilds == 7,"Native source kinds keep separate projections")
        precondition(!NativeSourceAdapters.fresh(.init(lastSuccess:now.addingTimeInterval(-1801)),now:now),"Current freshness gates reject old coverage even when projected items were cached")
        let validation=NativeLearningValidationBatch()
        var accessReads=0
        validation.withSnapshot {
            for _ in 0..<200 {_=validation.items(.calendar){accessReads += 1;return [first]}}
            validation.withSnapshot {_=validation.items(.calendar){accessReads += 1;return nil}}
        }
        precondition(accessReads == 1,"One synchronous validation decision captures each native kind once, including nested consumers")
        validation.withSnapshot {precondition(validation.items(.calendar){accessReads += 1;return nil} == nil)}
        precondition(accessReads == 2,"A later decision rechecks access and cannot reuse a withdrawn source")
        _=validation.items(.calendar){accessReads += 1;return [first]}
        _=validation.items(.calendar){accessReads += 1;return [first]}
        precondition(accessReads == 4,"Calls outside a validation decision never cache source access")
        let factID=UUID();var membershipReads=0
        validation.withSnapshot {
            for _ in 0..<200 {precondition(validation.permittedMemory{membershipReads += 1;return [factID]} == [factID])}
            validation.withSnapshot {precondition(validation.permittedMemory{membershipReads += 1;return []} == [factID])}
        }
        precondition(membershipReads == 1,"All current-memory consumers share membership only within one synchronous decision")
        validation.withSnapshot {precondition(validation.permittedMemory{membershipReads += 1;return []}.isEmpty)}
        precondition(membershipReads == 2,"The next decision immediately observes a withdrawn source memory")
        _=validation.permittedMemory{membershipReads += 1;return [factID]};_=validation.permittedMemory{membershipReads += 1;return []}
        precondition(membershipReads == 4,"Calls outside a decision cannot reuse source-memory authority")
        precondition(!first.text.contains(event.location))
        var progress=NativeLearningRules.collecting(.init(enabled:true),items:[first],now:now)
        precondition(NativeLearningRules.batch([first],progress:progress,manual:false).isEmpty,"First opt-in is baseline")
        precondition(NativeLearningRules.batch([first],progress:progress,manual:true) == [first],"Explicit review may assess baseline")
        progress=NativeLearningRules.completing(progress,items:[first],now:now)
        precondition(NativeLearningRules.batch([first],progress:progress,manual:true).isEmpty,"Already assessed versions aren't replayed")
        let store=PAMemoryStore(container:try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true)))
        var current=[first],permitted=true
        store.sourceIsPermitted={permitted && NativeLearningRules.permitted($0,items:current)}
        func output(_ item:NativeLearningItem,_ quote:String,previous:UUID? = nil)->String {
            var fact:[String:Any]=["itemID":item.id,"text":"Calendar records " + quote,"quote":quote,"kind":"context","areas":["studies"]]
            if let previous { fact["updatesMemoryID"]=previous.uuidString }
            return String(decoding:try! JSONSerialization.data(withJSONObject:["facts":[fact]]),as:UTF8.self)
        }
        let initial=NativeLearningRules.decode(output(first,event.title),items:[first],candidates:[],registration:registration,now:now)!.first!
        precondition(store.putSources([initial],evidenceTexts:[first.identity:first.text],expectedRevision:store.revision))
        event.title="Orion engineering supervision with revised preparation";event.modified=now.addingTimeInterval(1)
        let changed=calendarItem();current=[changed]
        precondition(changed.identity == first.identity && changed.revision != first.revision && changed.date == first.date)
        precondition(store.permittedRecords.isEmpty,"An edited exact item excludes its old belief before another assessment")
        precondition(NativeLearningRules.batch([changed],progress:progress,manual:false) == [changed])
        var absentProgress=NativeLearningRules.collecting(progress,items:[],now:now)
        var returning=changed;returning.changed=now.addingTimeInterval(-40*86400)
        absentProgress=NativeLearningRules.collecting(absentProgress,items:[returning],now:now)
        precondition(NativeLearningRules.batch([returning],progress:absentProgress,manual:false).isEmpty && NativeLearningRules.batch([returning],progress:absentProgress,manual:true) == [returning],"An old changed version returning to a partial window is baseline")
        var waitingProgress=NativeLearningRules.collecting(progress,items:[changed],now:now.addingTimeInterval(2))
        waitingProgress=NativeLearningRules.collecting(waitingProgress,items:[changed],now:now.addingTimeInterval(8*86400))
        precondition(NativeLearningRules.batch([changed],progress:waitingProgress,manual:false) == [changed],"A known continuously available delta survives budget waiting")
        let updated=NativeLearningRules.decode(output(changed,event.title,previous:initial.id),items:[changed],candidates:[initial],registration:registration,now:now.addingTimeInterval(2))!.first!
        let revision=store.revision
        precondition(!store.putSources([updated],evidenceTexts:[changed.identity:changed.text],expectedRevision:revision),"Replacing a stale version requires an issued exact old-evidence receipt")
        precondition(store.putSources([updated],evidenceTexts:[changed.identity:changed.text],expectedRevision:revision,replacementSources:[initial.id:initial.source!]))
        precondition(store.context(registration).count == 1 && store.context(registration).first?["text"] == updated.text)
        precondition(store.versionFamily(updated.id).count == 2 && store.records.first(where:{$0.id == initial.id})?.source == initial.source,"History keeps the earlier exact quote")
        event.start=event.start.addingTimeInterval(-3600);event.id="new-dashboard-occurrence";event.modified=now.addingTimeInterval(3)
        let moved=calendarItem();current=[moved]
        let move=NativeLearningRules.decode(output(moved,event.title,previous:updated.id),items:[moved],candidates:[updated],registration:registration,now:now.addingTimeInterval(4))!.first!
        precondition(moved.identity == changed.identity && store.putSources([move],evidenceTexts:[moved.identity:moved.text],expectedRevision:store.revision,replacementSources:[updated.id:updated.source!]) && store.versionFamily(move.id).count == 3)
        var anotherOccurrence=event;anotherOccurrence.memoryItemID="stable-other-occurrence"
        let two=NativeSourceAdapters.calendar(.init(start:now,end:now.addingTimeInterval(90*86400),refreshed:now,calendar:.init(sources:[calendar],events:[event,anotherOccurrence])),sources:[],now:now)
        precondition(two.count == 2 && two[0].identity != two[1].identity)
        permitted=false;precondition(store.context(registration).isEmpty);permitted=true
        current=[];precondition(store.context(registration).isEmpty,"Missing source means unknown, never completion")
        current=[changed]
        precondition(NativeLearningRules.decode(output(changed,"A fabricated quote"),items:[changed],candidates:[],registration:registration,now:now) == nil)
        var different=changed;different.identity.itemID="unrelated"
        precondition(NativeLearningRules.decode(output(different,event.title,previous:updated.id),items:[different],candidates:[updated],registration:registration,now:now.addingTimeInterval(3)) == nil)
        var confirmed=updated;confirmed.explicit=true
        precondition(!NativeLearningRules.replaceable(confirmed,by:first,registration:registration,now:now.addingTimeInterval(3)))
        var pinned=updated;pinned.organisation?.manual=true
        precondition(!NativeLearningRules.replaceable(pinned,by:first,registration:registration,now:now.addingTimeInterval(3)))
        var old=first;old.identity.itemID="old-arrival";old.changed=now.addingTimeInterval(-86400*40)
        progress=NativeLearningRules.collecting(progress,items:[old],now:now.addingTimeInterval(3))
        precondition(NativeLearningRules.batch([old],progress:progress,manual:false).isEmpty,"Old entries entering a partial window don't start historical indexing")
        var new=first;new.identity.itemID="new-arrival";new.changed=now.addingTimeInterval(3)
        progress=NativeLearningRules.collecting(progress,items:[new],now:now.addingTimeInterval(4))
        precondition(NativeLearningRules.batch([new],progress:progress,manual:false) == [new])
        let list=SourceOption(id:"list",title:"To do",account:"Fictional",writable:true,providerID:"provider")
        var reminder=TaskItem(id:"reminder",listID:list.id,title:"Prepare Orion draft",due:now,hasTime:false,sourceLabel:list.label,writable:true,recurring:false,modified:now)
        let reminderA=NativeSourceAdapters.reminders(.init(sources:[list],reminders:[reminder]),excluded:[]).first!
        reminder.due=now.addingTimeInterval(-86400)
        let reminderB=NativeSourceAdapters.reminders(.init(sources:[list],reminders:[reminder]),excluded:[]).first!
        precondition(reminderA.identity == reminderB.identity && reminderA.revision != reminderB.revision && reminderB.text.contains(DateRules.localDate(reminder.due!)))
        precondition(NativeSourceAdapters.reminders(.init(sources:[list],reminders:[reminder]),excluded:[list.id]).isEmpty)
        func mail(unread:Bool=true,replied:Bool=false,subject:String="Orion draft")throws->MailMessage {
            let value:[String:Any]=["id":"native","accountID":"account","account":"Fictional","messageID":1,"internetMessageID":"internet","sender":"Alex","subject":subject,"received":now.timeIntervalSinceReferenceDate,"unread":unread,"replied":replied,"flagged":false]
            return try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:value))
        }
        let message=try mail()
        var summary=EmailSummary(id:message.id,registration:registration,fingerprint:EmailSummary.fingerprint(message),summary:"Never raw evidence",attention:true,reason:"Never raw evidence",evidence:"The Orion draft is due Monday.",bodyFingerprint:"body-a",bodyCheckedAt:now,message:message)
        func mailItems(_ messages:[MailMessage]=[message],_ excluded:Set<String>=[])->[NativeLearningItem] { NativeSourceAdapters.mail(messages,summaries:[summary],registration:registration,excluded:excluded,now:now) }
        let mailA=mailItems().first!
        summary.observedBodyFingerprint="changed-body"
        precondition(mailItems().isEmpty,"Known stale source bodies cannot seed memory")
        summary.observedBodyFingerprint=nil
        summary.actionEvidence=[summary.evidence,"The final review is on 16 May 2027."]
        let compound=mailItems().first!
        precondition(compound.text.contains("The final review is on 16 May 2027."))
        precondition(compound.text.components(separatedBy:summary.evidence).count == 2,"Exact duplicate quotes occur once")
        summary.actionEvidence=(0..<12).map{"Action \($0): "+String(repeating:"é",count:450)}
        let bounded=mailItems().first!
        precondition(bounded.text.utf8.count <= 2400 && bounded.text.contains(summary.evidence),"Bounded quote selection retains useful evidence instead of dropping the entire email")
        summary.actionEvidence=nil
        precondition(!mailA.text.contains(summary.summary))
        let flags=try mail(unread:false,replied:true)
        precondition(mailItems([flags]).first == mailA,"Read/replied flags aren't evidence changes or completion")
        summary.evidence="The Orion draft is due Tuesday.";summary.bodyFingerprint="body-b"
        let mailB=mailItems().first!
        precondition(mailA.identity == mailB.identity && mailA.date == mailB.date && mailA.revision != mailB.revision)
        let mailMemory=NativeLearningRules.decode(output(mailA,"The Orion draft is due Monday."),items:[mailA],candidates:[],registration:registration,now:now)!.first!
        precondition(NativeLearningRules.decode(output(mailB,summary.evidence,previous:mailMemory.id),items:[mailB],candidates:[mailMemory],registration:registration,now:now.addingTimeInterval(1)) != nil,"Same received date accepts an observed body-version update")
        var oldMail=mailA;oldMail.date=now.addingTimeInterval(-30*86400)
        var mailProgress=NativeLearningRules.collecting(.init(enabled:true),items:[oldMail],now:now.addingTimeInterval(-60))
        mailProgress=NativeLearningRules.completing(mailProgress,items:[oldMail],now:now)
        var editedOldMail=oldMail;editedOldMail.revision=mailB.revision;editedOldMail.changed=now
        mailProgress=NativeLearningRules.collecting(mailProgress,items:[editedOldMail],now:now)
        precondition(NativeLearningRules.batch([editedOldMail],progress:mailProgress,manual:false) == [editedOldMail])
        var unseenOldMail=editedOldMail;unseenOldMail.identity.itemID="unseen-old-mail"
        mailProgress=NativeLearningRules.collecting(mailProgress,items:[unseenOldMail],now:now)
        precondition(NativeLearningRules.batch([unseenOldMail],progress:mailProgress,manual:false).isEmpty,"A newly assessed old email isn't an automatic history sweep")
        precondition(mailItems([message,message]).isEmpty && mailItems([message],[message.accountID]).isEmpty)
        var index=MailIndexState()
        let accounts=[MailAccount(id:message.accountID,title:"Fictional")]
        index.discovered(now:now);index.prepare(accounts:accounts,now:now)
        let page=index.monitor(message.accountID)!
        var snapshot=index.apply(MailBatch(messages:[message],messageIDs:[message.messageID,42],nextOffset:1,complete:false,errors:[]),to:page.id,snapshot:MailSnapshot(messages:[],accounts:accounts,errors:[]),now:now)
        index.failed(message.accountID,detail:"Fictional partial-page issue",now:now)
        let captured=MailReviewScope.collected(index:index,snapshot:snapshot,excluded:[])
        func collected()->[NativeLearningItem] {NativeSourceAdapters.collectedMail(snapshot,index:index,summaries:[summary],registration:registration,excluded:[],now:now,scope:captured)}
        precondition(collected().count == 1,"Verified partial collected pages survive existing collection errors without another read")
        index.failed(message.accountID,detail:"New source failure",now:now.addingTimeInterval(1))
        precondition(collected().isEmpty,"New in-flight account failure withdraws that account's learning evidence")
        let live=MailReviewScope.collected(index:index,snapshot:snapshot,excluded:[])
        snapshot=MailSnapshot(messages:snapshot.messages,accounts:[],errors:[])
        precondition(NativeSourceAdapters.collectedMail(snapshot,index:index,summaries:[summary],registration:registration,excluded:[],now:now,scope:live).isEmpty,"Removed accounts cannot retain source memory support")
        let changedHeader=try mail(subject:"Changed exact subject")
        snapshot=MailSnapshot(messages:[changedHeader],accounts:accounts,errors:[])
        precondition(NativeSourceAdapters.collectedMail(snapshot,index:index,summaries:[summary],registration:registration,excluded:[],now:now,scope:live).isEmpty,"Header changes reject stale exact assessments")
        summary.bodyCheckedAt=now.addingTimeInterval(-86401);precondition(mailItems().isEmpty)
        summary.bodyCheckedAt=now;summary.fingerprint="different";precondition(mailItems().isEmpty)
        precondition(!NativeSourceAdapters.fresh(.init(lastSuccess:now,error:"failed"),now:now) && !NativeSourceAdapters.fresh(.init(lastSuccess:now.addingTimeInterval(-1801)),now:now))
        precondition(NativeLearningRules.key(registration,.mail) != NativeLearningRules.key("other",.mail) && !NativeLearningRules.key(registration,.mail).contains(registration))
        let receipt=NativeLearningRules.receipt(registration,mailB)
        precondition(store.putSources([],evidenceTexts:[:],expectedRevision:store.revision,assessmentIDs:[receipt]) && store.sourceAssessmentDate(receipt) != nil)
        let encoded=try JSONEncoder().encode(progress),decoded=try JSONDecoder().decode(NativeLearningProgress.self,from:encoded)
        precondition(decoded.assessed == progress.assessed && !String(decoding:encoded,as:UTF8.self).contains(event.title))
        let legacy=try JSONDecoder().decode(SourceOption.self,from:JSONEncoder().encode(SourceOption(id:"legacy",title:"Legacy",account:"Account",writable:true)))
        precondition(legacy.providerID == nil)
        print("PASS native-source baselines/deltas, exact same-item history, permissions, partial coverage, Mail quote/body versions, no historical replay and opaque receipts")
    }
}
