import Foundation
@main struct NativeEditChecks {
    static func main() throws {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Europe/London")!
        func date(_ day: Int, _ hour: Int = 0) -> Date { calendar.date(from:DateComponents(year:2026,month:10,day:day,hour:hour))! }
        let base = NativeEditDetails(kind:.event,itemID:"stable",occurrenceID:"occurrence",sourceID:"calendar",title:"Same title",notes:"Original notes",start:date(25,1),end:date(25,3),writable:true)
        let displayed = TaskItem(id:"recurring",listID:"list",title:"Prepare report",due:date(24),hasTime:false,sourceLabel:"Fictional",writable:true,recurring:true,modified:date(23))
        let displayedDetails = NativeEditDetails(kind:.reminder,itemID:displayed.id,occurrenceID:displayed.id,sourceID:displayed.listID,title:displayed.title,notes:"Exact notes",due:displayed.due,recurring:true,writable:true,modified:displayed.modified)
        try NativeCompletionRules.validateDisplayed(displayed, details: displayedDetails)
        func rejectsDisplayed(_ value: NativeEditDetails) { do { try NativeCompletionRules.validateDisplayed(displayed, details:value); preconditionFailure("Stale displayed completion accepted") } catch {} }
        var advanced = displayedDetails; advanced.due = date(25); rejectsDisplayed(advanced)
        advanced = displayedDetails; advanced.title = "Changed title"; rejectsDisplayed(advanced)
        advanced = displayedDetails; advanced.sourceID = "moved-list"; rejectsDisplayed(advanced)
        advanced = displayedDetails; advanced.modified = date(24); rejectsDisplayed(advanced)
        let completion = NativeCompletionSnapshot(details:displayedDetails,dueComponents:calendar.dateComponents([.year,.month,.day],from:date(24)),completed:true,completionDate:date(24,10))
        try NativeCompletionRules.validateUndo(saved:completion,current:completion,detached:nil,currentDetached:nil)
        func rejectsCompletionUndo(_ current:NativeCompletionSnapshot,_ expectedDetached:NativeCompletionSnapshot? = nil,_ actualDetached:NativeCompletionSnapshot? = nil) {do {try NativeCompletionRules.validateUndo(saved:completion,current:current,detached:expectedDetached,currentDetached:actualDetached);preconditionFailure("Stale completion Undo accepted")} catch {}}
        var laterCompletion=completion;laterCompletion.completionDate=date(24,11);rejectsCompletionUndo(laterCompletion)
        laterCompletion=completion;laterCompletion.details.notes="External notes";rejectsCompletionUndo(laterCompletion)
        laterCompletion=completion;laterCompletion.details.recurrenceRules=[.init(frequency:"weekly")];rejectsCompletionUndo(laterCompletion)
        laterCompletion=completion;laterCompletion.details.sourceID="moved-list";rejectsCompletionUndo(laterCompletion)
        rejectsCompletionUndo(completion,completion,nil)
        laterCompletion=completion;laterCompletion.details.notes="External detached edit";rejectsCompletionUndo(completion,completion,laterCompletion)
        try NativeCompletionRules.validateUndo(saved:completion,current:completion,detached:completion,currentDetached:completion)
        var draft = base; draft.title = "Updated"; draft.notes = "Updated notes"; try NativeEditRules.validate(draft,baseline:base)
        func rejects(_ value: NativeEditDetails, _ original: NativeEditDetails) { do { try NativeEditRules.validate(value,baseline:original); preconditionFailure("Invalid edit accepted") } catch {} }
        var wrong = draft; wrong.itemID = "duplicate-title-other-ID"; rejects(wrong,base)
        wrong = draft; wrong.occurrenceID = "other-occurrence"; rejects(wrong,base)
        wrong = draft; wrong.end = wrong.start; rejects(wrong,base)
        wrong = draft; wrong.title = " \n"; rejects(wrong,base)
        var readOnly = base; readOnly.writable = false; rejects(draft,readOnly)
        var repeatedOriginal=base; repeatedOriginal.recurring=true; repeatedOriginal.recurrenceRules=[.init(frequency:"daily",count:3)]
        var detached=base; detached.start=detached.start.addingTimeInterval(3600); detached.end=detached.end.addingTimeInterval(3600); detached.occurrenceID="detached"; detached.modified=Date.now
        let restoredOccurrence=try NativeEditRules.restoring(.init(original:repeatedOriginal,saved:detached))
        precondition(restoredOccurrence.start == base.start && restoredOccurrence.end == base.end && restoredOccurrence.recurrenceRules.isEmpty && !restoredOccurrence.recurring)
        try NativeEditRules.validateScope(.occurrence,baseline:detached,edited:restoredOccurrence)
        var recurring = base; recurring.recurring = true; var move = recurring; move.sourceID = "different"; try NativeEditRules.validate(move,baseline:recurring)
        let proposal = NativeEventMoveProposal(occurrenceID:base.occurrenceID,sourceID:base.sourceID,originalStart:base.start,originalEnd:base.end,start:date(26,23))
        let moved = try NativeEditRules.moved(base,proposal:proposal)
        precondition(moved.start == proposal.start && moved.end.timeIntervalSince(moved.start) == base.end.timeIntervalSince(base.start))
        precondition(moved.notes == base.notes && moved.sourceID == base.sourceID && moved.timeZoneID == base.timeZoneID && moved.occurrenceID == base.occurrenceID)
        func rejectsMove(_ value: NativeEditDetails, _ proposed: NativeEventMoveProposal) { do { _ = try NativeEditRules.moved(value,proposal:proposed); preconditionFailure("Invalid move accepted") } catch {} }
        var changed = base; changed.start = changed.start.addingTimeInterval(60); rejectsMove(changed,proposal)
        rejectsMove(readOnly,proposal)
        var wrongProposal = proposal; wrongProposal.occurrenceID = "duplicate-other-occurrence"; rejectsMove(base,wrongProposal)
        wrongProposal = proposal; wrongProposal.sourceID = "other-calendar"; rejectsMove(base,wrongProposal)
        let movedRecurring = try NativeEditRules.moved(recurring,proposal:proposal); precondition(movedRecurring.recurring && movedRecurring.sourceID == recurring.sourceID)
        var verified = moved; verified.itemID = "verified-native-ID"; verified.occurrenceID = "verified-moved-occurrence"; verified.modified = .now
        let restored = try NativeEditRules.restoring(NativeEditUndo(original:base,saved:verified))
        precondition(restored.start == base.start && restored.end == base.end && restored.notes == base.notes)
        precondition(restored.itemID == verified.itemID && restored.occurrenceID == verified.occurrenceID && restored.modified == verified.modified)
        var unavailableUndo = verified; unavailableUndo.writable = false
        do { _ = try NativeEditRules.restoring(.init(original:base,saved:unavailableUndo)); preconditionFailure("Read-only Undo accepted") } catch {}
        let allDay = NativeEditRules.allDay(base,enabled:true,calendar:calendar)
        precondition(allDay.start == date(25) && allDay.end == date(26))
        precondition(allDay.end.timeIntervalSince(allDay.start) == 25*3600, "DST all-day duration follows calendar boundaries")
        let shiftedDay = NativeEditRules.movingStart(allDay,to:date(26,10),calendar:calendar)
        precondition(shiftedDay.start == date(26) && shiftedDay.end == date(27) && shiftedDay.end.timeIntervalSince(shiftedDay.start) == 24*3600)
        var multipleDays = allDay; multipleDays.start = date(24); multipleDays.end = date(27)
        let shiftedMultiple = NativeEditRules.movingStart(multipleDays,to:date(28,11),calendar:calendar)
        precondition(shiftedMultiple.start == date(28) && shiftedMultiple.end == date(31))
        let shiftedTimed = NativeEditRules.movingStart(base,to:date(26,22),calendar:calendar)
        precondition(shiftedTimed.end.timeIntervalSince(shiftedTimed.start) == base.end.timeIntervalSince(base.start))
        precondition(shiftedTimed.notes == base.notes && shiftedTimed.timeZoneID == base.timeZoneID && shiftedTimed.itemID == base.itemID)
        let approval=NativeDateReview(discoveryID:"proposal",registration:"account",date:date(26,22),hasTime:true,expectedModified:base.modified,evidence:"Fictional source")
        let approved=try approval.applying(to:base)
        precondition(approved == shiftedTimed,"Direct approval changes only the proposed start while preserving duration and all other fields")
        func rejectsApproval(_ review:NativeDateReview,_ item:NativeEditDetails) {do {_ = try review.applying(to:item);preconditionFailure("Invalid approval accepted")} catch {}}
        var stale=base;stale.modified = .now;rejectsApproval(approval,stale)
        var exact=approval
        exact.expectedOccurrenceID=base.occurrenceID;exact.expectedSourceID=base.sourceID;exact.expectedTitle=base.title
        exact.expectedStart=base.start;exact.expectedEnd=base.end;exact.expectedHasTime = !base.allDay
        let exactApproved=try exact.applying(to:base);precondition(exactApproved == shiftedTimed)
        var wrongTarget=base;wrongTarget.occurrenceID="another-occurrence";rejectsApproval(exact,wrongTarget)
        wrongTarget=base;wrongTarget.sourceID="another-calendar";rejectsApproval(exact,wrongTarget)
        wrongTarget=base;wrongTarget.title="Changed title without timestamp";rejectsApproval(exact,wrongTarget)
        wrongTarget=base;wrongTarget.start=base.start.addingTimeInterval(60);rejectsApproval(exact,wrongTarget)
        rejectsApproval(approval,readOnly)
        var wrongTime=approval;wrongTime.hasTime=false;rejectsApproval(wrongTime,base)
        var dayReview=approval;dayReview.hasTime=false;dayReview.date=Calendar.current.startOfDay(for:date(28))
        let approvedDays=try dayReview.applying(to:multipleDays)
        precondition(Calendar.current.dateComponents([.day],from:approvedDays.start,to:approvedDays.end).day == 3 && approvedDays.notes == multipleDays.notes)
        var midnight = base; midnight.start = date(24,20); midnight.end = date(25)
        let midnightDay = NativeEditRules.allDay(midnight,enabled:true,calendar:calendar)
        precondition(midnightDay.start == date(24) && midnightDay.end == date(25), "Exclusive midnight endpoint is preserved")
        precondition(NativeEditRules.allDay(allDay,enabled:true,calendar:calendar) == allDay)
        let timed = NativeEditRules.allDay(allDay,enabled:false,calendar:calendar)
        precondition(timed.end.timeIntervalSince(timed.start) == 3600 && calendar.component(.hour,from:timed.start) == 9)
        let reminder = NativeEditDetails(kind:.reminder,itemID:"reminder",occurrenceID:"reminder",sourceID:"list",title:"Same title",notes:"",writable:true)
        var due = reminder; due.hasTime = true; rejects(due,reminder)
        due.due = date(25,8); try NativeEditRules.validate(due,baseline:reminder)
        let reminderReview=NativeDateReview(discoveryID:"reminder-proposal",registration:"account",date:date(26,8),hasTime:true,expectedModified:due.modified,evidence:"Fictional source")
        let approvedReminder=try reminderReview.applying(to:due)
        var expectedReminder=due;expectedReminder.due=date(26,8)
        precondition(approvedReminder == expectedReminder,"Reminder approval preserves title, notes, identity, list and other native fields")
        var recurringReminder = reminder; recurringReminder.recurring = true
        try NativeEditRules.validate(recurringReminder,baseline:recurringReminder)
        try NativeEditRules.validateDeletion(.reminderSeries,baseline:recurringReminder)
        func rejectsScope(_ scope:NativeChangeScope,_ baseline:NativeEditDetails,_ edited:NativeEditDetails) { do {try NativeEditRules.validateScope(scope,baseline:baseline,edited:edited);preconditionFailure("Invalid scope accepted")} catch {} }
        rejectsScope(.occurrence,recurring,move)
        try NativeEditRules.validateScope(.futureEvents,baseline:recurring,edited:move)
        rejectsScope(.occurrence,recurringReminder,recurringReminder)
        rejectsScope(.futureEvents,base,base)
        rejectsScope(.reminderSeries,recurring,recurring)
        try NativeEditRules.validateDeletion(.futureEvents,baseline:recurring)
        try NativeEditRules.validateDeletion(.occurrence,baseline:recurring)
        var repeated=recurring;repeated.recurrenceRules=[.init(frequency:"weekly",interval:2,weekdays:[.init(weekday:2),.init(weekday:6)])]
        rejectsScope(.occurrence,recurring,repeated)
        try NativeEditRules.validateScope(.futureEvents,baseline:recurring,edited:repeated)
        precondition(!NativeEditRules.supportsUndo(baseline:recurring,edited:repeated,scope:.futureEvents))
        try repeated.recurrenceRules[0].validate()
        for rule in [NativeRecurrence(interval:0),NativeRecurrence(frequency:"weekly",weekdays:[.init(weekday:2,week:1)]),NativeRecurrence(frequency:"monthly",monthDays:[0]),NativeRecurrence(frequency:"yearly",months:[13]),NativeRecurrence(endDate:.now,count:4)] {do {try rule.validate();preconditionFailure("Invalid recurrence accepted")} catch {}}
        try NativeRecurrence(frequency:"monthly",weekdays:[.init(weekday:6,week:-1)]).validate()
        try NativeRecurrence(frequency:"monthly",monthDays:[-1]).validate()
        var repeatDue=recurringReminder;repeatDue.recurrenceRules=[.init()];rejects(repeatDue,reminder)
        repeatDue.due=date(25);try NativeEditRules.validate(repeatDue,baseline:reminder)
        var imported=recurring;imported.recurrenceRules=[.init(calendarIdentifier:"hebrew")]
        var replaceImported=imported;replaceImported.recurrenceRules=[.init()]
        rejectsScope(.futureEvents,imported,replaceImported)
        var renameImported=imported;renameImported.title="Renamed"
        try NativeEditRules.validate(renameImported,baseline:imported)
        try NativeEditRules.validateScope(.futureEvents,baseline:imported,edited:renameImported)
        replaceImported.recurrenceRules=[];try NativeEditRules.validateScope(.futureEvents,baseline:imported,edited:replaceImported)
        var tooMany=base;tooMany.alarms=[.init(offset:.infinity)];rejects(tooMany,base)
        var outside=base;outside.priority=10;rejects(outside,base)
        var link=base;link.url="javascript:alert(1)";rejects(link,base)
        precondition(reminder == NativeEditDetails(kind:.reminder,itemID:"reminder",occurrenceID:"reminder",sourceID:"list",title:"Same title",notes:"",writable:true), "Reminder baseline fields are stable across fresh reads")
        print("PASS: edit identity, stale-field comparison foundation, read-only/recurrence rules, date validation, deterministic reminder baseline and inclusive all-day/DST boundaries")
    }
}
