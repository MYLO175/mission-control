import Foundation

@main struct ReviewInferenceGuardChecks {
    static func main() throws {
        var count=0
        func check(_ value:Bool,_ text:String) {precondition(value,text);count += 1}
        let now=Date(timeIntervalSince1970:1_792_150_000)
        let source=SourceOption(id:"calendar",title:"Fictional",account:"Example",writable:true)
        let event=AgendaEvent(id:"event@1",calendarID:source.id,title:"Orion prototype",start:now,end:now.addingTimeInterval(3600),allDay:false,location:"Lab",sourceLabel:source.label,modified:now)
        let task=TaskItem(id:"task",listID:"list",title:"Prepare Orion",due:now,hasTime:true,sourceLabel:"Example",writable:true,recurring:false,modified:now)
        let done=CompletedReminder(item:task,completedAt:now)
        let emptyReminders=ReminderSnapshot(sources:[],reminders:[])
        func rows(_ events:[AgendaEvent]=[event],_ tasks:[TaskItem]=[task],_ completed:[CompletedReminder]=[done],writable:Bool=true)->[String:String] {
            var selected=source;selected.writable=writable
            return ReviewInferenceGuard.nativeRows(calendar:.init(sources:[selected],events:events),reminders:.init(sources:[],reminders:tasks),completed:completed,excludedCalendars:[],excludedLists:[])
        }
        let captured=rows()
        var another=event;another.id="other";another.title="Garden watering"
        check(ReviewInferenceGuard.available(captured,current:rows([another,event])),"An unrelated newly collected event cannot invalidate supplied records")
        check(ReviewInferenceGuard.available(captured,current:rows([event,another],[task],[done])),"Collection ordering is irrelevant")
        for field in ["title","start","end","occurrence","source","modified"] {
            var changed=event
            switch field {case "title":changed.title="Changed";case "start":changed.start += 900;case "end":changed.end += 900;case "occurrence":changed.id="event@2";case "source":changed.calendarID="another";default:changed.modified=now.addingTimeInterval(1)}
            check(!ReviewInferenceGuard.available(captured,current:rows([changed])),"Changed exact \(field) invalidates supplied native evidence")
        }
        check(!ReviewInferenceGuard.available(captured,current:rows([],[],[])),"Missing exact supplied records are not an empty successful result")
        check(!ReviewInferenceGuard.available(captured,current:rows(writable:false)),"Source writability remains captured")
        check(!ReviewInferenceGuard.nativeAvailable(captured,current:rows([event,another])),"A newly admitted native item changes duplicate/absence context")
        check(ReviewInferenceGuard.nativeAvailable(captured,current:rows()),"Unchanged admitted native records survive collection refresh")
        var completed=done;completed.completedAt += 1
        check(!ReviewInferenceGuard.available(captured,current:rows([event],[task],[completed])),"Exact completion date is supporting evidence")
        check(!ReviewInferenceGuard.available(captured,current:rows([event],[task],[])),"Undoing a supplied completion invalidates its receipt")
        check(ReviewInferenceGuard.available([:],current:rows()),"An empty supplied set never adopts new rows")
        let withdrawn=ReviewInferenceGuard.nativeRows(calendar:.init(sources:[source],events:[event]),reminders:emptyReminders,completed:[],excludedCalendars:[source.id],excludedLists:[])
        check(!ReviewInferenceGuard.available(["event:"+event.id:captured["event:"+event.id]!],current:withdrawn),"Exact source withdrawal excludes its evidence")
        let base:[String:Any]=["id":"mail","accountID":"account","account":"Example","messageID":1,"internetMessageID":"mail@example.invalid","sender":"Fictional sender","subject":"Orion prototype","received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
        func mail(_ changes:[String:Any]=[:])throws->MailMessage {try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:base.merging(changes,uniquingKeysWith:{$1})))}
        let receipt=ReviewInferenceGuard.mailSource(try mail())
        for changes:[String:Any] in [["unread":false],["flagged":true],["mailboxName":"Archive","mailboxRole":"archive"],["account":"Renamed display label"]] {
            check(ReviewInferenceGuard.mailSource(try mail(changes)) == receipt,"Mail bookkeeping cannot change fetched source ownership")
        }
        for changes:[String:Any] in [["id":"different"],["accountID":"other"],["messageID":2],["internetMessageID":"other@example.invalid"],["sender":"Different sender"],["subject":"Different subject"],["replied":true],["received":now.addingTimeInterval(1).ISO8601Format()]] {
            check(ReviewInferenceGuard.mailSource(try mail(changes)) != receipt,"Mail identity, supplied headers and meaningful reply state remain exact")
        }
        check(ReviewInferenceGuard.available(["project:A":"version-1"],current:["project:A":"version-1","project:B":"new"]),"An unrelated project revision is irrelevant")
        check(!ReviewInferenceGuard.available(["project:A":"version-1"],current:["project:A":"version-2"]),"Supplied project payload remains guarded")
        check(!ReviewInferenceGuard.available(["proposal:A":"version-1"],current:[:]),"A supplied pending proposal must remain the same captured record")
        let currentHistorical=["old-a":"v1","old-b":"v2"]
        check(ReviewInferenceGuard.eligibleHistorical(["old-a":"v1","old-b":"v1"],current:currentHistorical,permitted:["old-a","old-b"]) == ["old-a"],"An altered historical row loses only its own replacement authority")
        check(ReviewInferenceGuard.eligibleHistorical(["old-a":"v1"],current:currentHistorical,permitted:[]).isEmpty,"Withdrawn historical support cannot author replacements")
        let fresh=WhatsAppWindowDependency(chatID:"fresh",linkedIdentity:"device",fingerprint:"fresh-window")
        let oldA=WhatsAppWindowDependency(chatID:"old-a",linkedIdentity:"device",fingerprint:"old-a-window")
        let oldB=WhatsAppWindowDependency(chatID:"old-b",linkedIdentity:"device",fingerprint:"old-b-window")
        let prior=["proposal-a":[oldA],"proposal-b":[oldB]]
        check(ReviewInferenceGuard.comparisonDependencies(fresh:[fresh],replaced:[],prior:prior) == [fresh],"Unreferenced historical WhatsApp rows cannot poison fresh advice")
        check(ReviewInferenceGuard.comparisonDependencies(fresh:[fresh],replaced:["proposal-a"],prior:prior) == [fresh,oldA],"A replacement retains precisely its claimed prior conversation context")
        check(ReviewInferenceGuard.comparisonDependencies(fresh:[fresh],replaced:["proposal-a","proposal-a"],prior:prior) == [fresh,oldA],"Repeated prior aliases do not duplicate source receipts")
        check(ReviewInferenceGuard.comparisonDependencies(fresh:[fresh,oldA],replaced:["proposal-a"],prior:prior) == [fresh,oldA],"Fresh same-chat windows remain canonical and are not widened")
        let output:[String:Any]=["suggestions":[["mailID":"mail_0","kind":"update"],["mailID":"mail_1","kind":"reminder"],["mailID":"wa_0","kind":"reply"]],"handled":[["mailID":"mail_0"],["mailID":"mail_1"]],"resolved":[["mailID":"mail_0","confirmationID":"mail_1"],["mailID":"mail_1","confirmationID":"mail_0"]],"retirements":[["reviewID":"review_0"],["reviewID":"review_1"]]]
        let response=String(decoding:try JSONSerialization.data(withJSONObject:output),as:UTF8.self)
        let filtered=try ReviewInferenceGuard.currentAttentionRows(response,dismissedSources:["mail_0"],dismissedReviews:["review_0"])
        let object=try JSONSerialization.jsonObject(with:Data(filtered.response.utf8)) as! [String:Any]
        check((object["suggestions"] as? [[String:String]])?.map{$0["mailID"]!} == ["mail_1","wa_0"],"A dismissed Mail source withholds only its own suggestions")
        check((object["handled"] as? [[String:String]])?.map{$0["mailID"]!} == ["mail_1"],"A dismissed request cannot acquire new handling metadata")
        let resolved=object["resolved"] as? [[String:String]]
        check(resolved?.count == 1 && resolved?.first?["confirmationID"] == "mail_0","Dismiss does not invalidate truthful confirmation evidence for another request")
        check((object["retirements"] as? [[String:String]])?.map{$0["reviewID"]!} == ["review_1"],"Whole-source dismissal withholds only that source's issued retirements")
        check(!filtered.limited,"A short completed output stays uncapped")
        let unchanged=try ReviewInferenceGuard.currentAttentionRows(response,dismissedSources:[])
        check(unchanged.response == response,"An unrelated Dismiss needs no response rewrite")
        var capped=output;capped["suggestions"]=Array(repeating:["mailID":"mail_0","kind":"update"],count:24)
        let cappedResponse=String(decoding:try JSONSerialization.data(withJSONObject:capped),as:UTF8.self)
        let cappedFiltered=try ReviewInferenceGuard.currentAttentionRows(cappedResponse,dismissedSources:["mail_0"])
        let cappedObject=try JSONSerialization.jsonObject(with:Data(cappedFiltered.response.utf8)) as! [String:Any]
        check(cappedFiltered.limited && (cappedObject["suggestions"] as? [[String:String]])?.isEmpty == true,"Filtering a dismissed source cannot hide the original result's24row truncation")
        var invalid=output;invalid["suggestions"]=[["kind":"update"],["mailID":"unknown","kind":"update"]]
        let invalidResponse=String(decoding:try JSONSerialization.data(withJSONObject:invalid),as:UTF8.self)
        let preserved=try ReviewInferenceGuard.currentAttentionRows(invalidResponse,dismissedSources:["mail_0"])
        let preservedObject=try JSONSerialization.jsonObject(with:Data(preserved.response.utf8)) as! [String:Any]
        check((preservedObject["suggestions"] as? [[String:String]])?.count == 2,"Unassociated malformed rows remain available for existing strict diagnostics")
        print("PASS Review inference receipts: \(count) checks; exact native/source/occurrence/completion and supplied rows, irrelevant additions/bookkeeping, no AI or native access.")
    }
}
