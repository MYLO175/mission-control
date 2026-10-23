import Foundation
@main struct Checks {
    static func main() throws {
        var london = Calendar(identifier:.gregorian); london.timeZone = TimeZone(identifier:"Europe/London")!
        let date = try ActionRules.date("2026-10-02",dateOnly:true,calendar:london)
        assert(DateRules.localDate(date,calendar:london) == "2026-10-02")
        let opening=try ActionRules.date("2026-11-09",dateOnly:true,calendar:london)
        assert(DateRules.localDate(opening,calendar:london) == "2026-11-09")
        let refused=PAIntentFailure(reason:"Resolve the opening date before scheduling.")
        assert(refused.localizedDescription == "Resolve the opening date before scheduling.")
        assert(refused.note.contains("before executing"))
        assert(PAIntentFailure.guidance.contains("before any native save"))
        let overloaded=PAIntentFailure(reason:"ChatGPT request failed. (server_is_overloaded). No paid fallback or automatic retry.",kind:.unavailable)
        let stopped=overloaded.stoppedReply(receipts:[])
        assert(overloaded.kind == .unavailable && refused.kind == .refused)
        assert(stopped.contains("ChatGPT was temporarily overloaded") && stopped.contains("wasn’t attempted") && !stopped.contains("Reminders service"))
        let partial=overloaded.stoppedReply(receipts:["Created fictional event"])
        assert(partial.hasPrefix("Created fictional event\n\n") && !partial.contains("No change was made"),"Earlier verified changes must not be denied")
        let legacy="I couldn’t update it because the Reminders service was overloaded; no change was made."
        assert(PAIntentFailure.correctedLegacyReply(legacy,errors:[overloaded.note]) == stopped)
        assert(PAIntentFailure.correctedLegacyReply(legacy.replacingOccurrences(of:"’",with:"'"),errors:[overloaded.note]) == stopped,"Rendered typography must not decide whether a known failure is corrected")
        let formattedLegacy="I couldn't update it because the Reminders service was overloaded; **no change was made**."
        assert(PAIntentFailure.correctedLegacyReply(formattedLegacy,errors:[overloaded.note]) == stopped,"Preserved Markdown must not hide a proven pre-operation error")
        assert(PAIntentFailure.correctedLegacyReply(legacy,errors:nil) == legacy,"Do not rewrite an unsupported historical explanation")
        assert(PAIntentFailure.correctedLegacyReply("A native save failed; verify its outcome.",errors:[overloaded.note]) == "A native save failed; verify its outcome.")
        assert(PAIntentFailure.correctedLegacyReply(legacy,errors:["server_is_overloaded"]) == legacy,"A code without a pre-execution receipt is not proof no save occurred")
        let oldPartial="Created fictional event\n\n"+legacy
        assert(PAIntentFailure.correctedLegacyReply(oldPartial,errors:[overloaded.note]) == oldPartial,"Never erase a historical partial-success receipt")
        let receipt=String(repeating:"a",count:64),marker="Mission Control request "+String(repeating:"a",count:64)
        assert(NativeRequestNotes.creation(nil).isEmpty)
        assert(NativeRequestNotes.creation("Buy unscented pods") == "Buy unscented pods")
        assert(NativeRequestNotes.cleaned(marker,receiptKey:receipt) == "")
        assert(NativeRequestNotes.cleaned("Actual note\n"+marker+"\nMore notes",receiptKey:receipt) == "Actual note\nMore notes")
        assert(NativeRequestNotes.cleaned("Real note\r\n"+marker+"\r\nEnd",receiptKey:receipt) == "Real note\r\nEnd")
        assert(NativeRequestNotes.cleaned(marker,receiptKey:String(repeating:"b",count:64)) == nil)
        assert(NativeRequestNotes.cleaned("Reference: "+marker,receiptKey:receipt) == nil)
        assert(NativeRequestNotes.cleaned(marker,receiptKey:"not-a-receipt") == nil)
        let firstFold = try ActionRules.date("2026-10-25T01:30:00+01:00",dateOnly:false)
        let secondFold = try ActionRules.date("2026-10-25T01:30:00+00:00",dateOnly:false)
        assert(secondFold.timeIntervalSince(firstFold) == 3600)
        for raw in ["2026-02-30","2026-13-01","2026-1-01"] { var rejected = false; do { _ = try ActionRules.date(raw,dateOnly:true) } catch { rejected = true }; assert(rejected) }
        var rejected = false; do { _ = try ActionRules.date("2026-10-25T01:30:00",dateOnly:false) } catch { rejected = true }; assert(rejected)
        let draft = try JSONDecoder().decode(ActionDraft.self,from:Data(#"{"kind":"completeReminder","target":"native-id"}"#.utf8))
        try ActionRules.validate(draft)
        try ActionRules.validate(.init(kind:.editReminder,target:"issued-id",notes:"new notes"))
        try ActionRules.validate(.init(kind:.editReminder,target:"issued-id",title:"Sort out card",due:"undated",hasTime:false))
        try ActionRules.validate(.init(kind:.editEvent,target:"occurrence-id",notes:"Preparation",location:"New room"))
        try ActionRules.validate(.init(kind:.createEvent,title:"Disposable",start:"2026-10-04T14:00:00+01:00",end:"2026-10-04T14:30:00+01:00",allDay:false,location:"Test room"))
        try ActionRules.validate(.init(kind:.deleteEvent,target:"exact-occurrence",scope:"futureEvents"))
        try ActionRules.validate(.init(kind:.deleteReminder,target:"exact-reminder",scope:"reminderSeries"))
        try ActionRules.validate(.init(kind:.editEvent,target:"exact-occurrence",scope:"futureEvents",options:"{}"))
        for action in [ActionDraft(kind:.deleteEvent,target:"id",title:"Should not change"),ActionDraft(kind:.deleteReminder,target:"id",scope:"futureEvents"),ActionDraft(kind:.completeReminder,target:"id",options:"{}"),ActionDraft(kind:.createEvent,title:"test",start:"a",end:"b",allDay:false,scope:"futureEvents")] {do {try ActionRules.validate(action);assertionFailure("Unsupported mutation accepted")} catch {}}
        let key = ActionRules.key(registration:"account",request:"Complete fictional")
        let repeatedKey = ActionRules.key(registration:"account",request:"Complete fictional")
        let otherKey = ActionRules.key(registration:"other",request:"Complete fictional")
        assert(key == repeatedKey && key != otherKey)
        assert(key != ActionRules.key(registration:"account",request:"Complete fictional",selectedTarget:"explicit-other-item"))
        for raw in [#"{"kind":"sendEmail"}"#, #"{"kind":"completeReminder","target":"id","title":"changed"}"#, #"{"kind":"createEvent","title":"Missing dates"}"#, #"{"kind":"editEvent","target":"id","title":"Changed","scope":"series"}"#] {
            var rejected = false; do { let action = try JSONDecoder().decode(ActionDraft.self,from:Data(raw.utf8)); try ActionRules.validate(action) } catch { rejected = true }; assert(rejected)
        }
        print("PASS: typed tool operations and notes/location edits, valid local dates, invalid/ambiguous dates, DST folds, stable account-separated duplicate keys, unsupported operations and scopes")
    }
}
