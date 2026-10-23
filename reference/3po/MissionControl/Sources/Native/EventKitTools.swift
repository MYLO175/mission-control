import Foundation
import EventKit

extension NativeEditDetails {
    mutating func applyToolOptions(_ raw: String?) throws {
        guard let raw,let object=try JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] else { return }
        if let values=object["recurrence"] as? [[String:Any]] {
            recurrenceRules = try values.map { value in
                let days=(value["weekdays"] as? [[String:Int]] ?? []).map { NativeRepeatDay(weekday:$0["weekday"] ?? 0,week:$0["week"] ?? 0) }
                let end = try (value["endDate"] as? String).map { try ActionRules.date($0,dateOnly:false) }
                return NativeRecurrence(frequency:value["frequency"] as? String ?? "",interval:value["interval"] as? Int ?? 0,weekdays:days,monthDays:value["monthDays"] as? [Int] ?? [],months:value["months"] as? [Int] ?? [],yearWeeks:value["yearWeeks"] as? [Int] ?? [],yearDays:value["yearDays"] as? [Int] ?? [],positions:value["positions"] as? [Int] ?? [],endDate:end,count:value["count"] as? Int ?? 0)
            }
        }
        if let values=object["alerts"] as? [[String:Any]] {
            alarms = try values.map { value in
                let absolute = try (value["absolute"] as? String).map { try ActionRules.date($0,dateOnly:false) }
                return NativeTimeAlarm(absolute:absolute,offset:-(value["minutesBefore"] as? Double ?? 0)*60)
            }
        }
        if let value=object["url"] as? String { url=value }
        if let value=object["timeZone"] as? String { guard kind == .event && !allDay else {throw ActionFailure.message("Editable time zones apply to timed Calendar events; reminder and date-only controls use local dates/times.")};guard TimeZone(identifier:value) != nil else { throw ActionFailure.message("Unknown time zone.") };timeZoneID=value }
        if let value=object["priority"] as? String { guard kind == .reminder,let priority=["none":0,"high":1,"medium":5,"low":9][value] else {throw ActionFailure.message("Priority applies to Reminders only.")};self.priority=priority }
        if let value=object["availability"] as? String { guard kind == .event,let availability=["busy":0,"free":1,"tentative":2,"unavailable":3][value] else {throw ActionFailure.message("Availability applies to Calendar only.")};self.availability=availability }
    }
    mutating func applyToolFields(_ draft: ActionDraft) throws {
        if let title=draft.title {self.title=title}
        if let notes=draft.notes {self.notes=notes}
        if let location=draft.location {self.location=location}
        if let destination=draft.destination {sourceID=destination}
        if kind == .reminder,let due=draft.due {
            if due == "undated" { self.due=nil;hasTime=false }
            else {guard let timed=draft.hasTime else {throw ActionFailure.message("Specify whether the due date includes a time.")};self.due=try ActionRules.date(due,dateOnly:!timed);hasTime=timed}
        }
        if kind == .event {
            let allDay=draft.allDay ?? self.allDay
            guard allDay == self.allDay || draft.start != nil && draft.end != nil else {throw ActionFailure.message("Changing all-day status requires both boundaries.")}
            self.allDay=allDay
            if let start=draft.start {self=NativeEditRules.movingStart(self,to:try ActionRules.date(start,dateOnly:allDay))}
            if let end=draft.end {self.end=try ActionRules.date(end,dateOnly:allDay)}
        }
        try applyToolOptions(draft.options)
    }
}
extension EventKitService {
    func applyTool(_ draft: ActionDraft, reminder: TaskItem?, event: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>, expectedDetails: NativeEditDetails? = nil, valid: NativeWriteValidity? = nil) async throws -> ActionResult {
        var enteredWriter = false
        do {
            try ActionRules.validate(draft)
            guard (draft.notes?.count ?? 0) <= 10_000, (draft.location?.count ?? 0) <= 2000 else {throw ActionFailure.message("Notes/location exceed supported size.")}
            if draft.kind == .completeReminder {
                guard let reminder, draft.target == reminder.id, allowedLists.contains(reminder.listID) else { throw IntegrationError.missing }
                let baseline = try await editSession(.reminder(reminder)).item
                if let expectedDetails { guard baseline == expectedDetails else { throw IntegrationError.missing } }
                enteredWriter = true
                let token = try await complete(id: reminder.id, valid: valid, expected: baseline)
                return .init(message: "Completed reminder: " + reminder.title, undoToken: token, itemID: reminder.id)
            }
            if draft.kind == .createEvent || draft.kind == .createReminder {
                let request=NativeCreationRequest(kind:draft.kind == .createEvent ? .event : .reminder,registration:"tool",title:draft.title ?? "",notes:NativeRequestNotes.creation(draft.notes))
                let session=try await creationSession(request),baseline=session.item
                var edited=baseline;try edited.applyToolFields(draft)
                guard (edited.kind == .event ? allowedCalendars : allowedLists).contains(edited.sourceID) else {throw IntegrationError.readOnly}
                enteredWriter = true
                let receipt=try await createItem(request:request,baseline:baseline,edited:edited,scope:"tool",valid:valid)
                return .init(message:"Created " + (edited.kind == .event ? "event: " : "reminder: ") + receipt.title,itemID:receipt.itemID)
            }
            let target: NativeEditTarget
            if draft.kind == .editReminder || draft.kind == .deleteReminder {
                guard let reminder,allowedLists.contains(reminder.listID) else {throw IntegrationError.readOnly};target = .reminder(reminder)
            } else {guard let event,allowedCalendars.contains(event.calendarID) else {throw IntegrationError.readOnly};target = .event(event)}
            let baseline=try await editSession(target).item
            if let expectedDetails {guard baseline == expectedDetails else {throw IntegrationError.missing}}
            guard baseline.canEdit else {throw IntegrationError.readOnly}
            let scope: NativeChangeScope
            if baseline.recurring {
                guard let raw=draft.scope,let resolved=NativeChangeScope(rawValue:raw) else {throw ActionFailure.message(baseline.kind == .event ? "Choose only this event or this and all future events." : "Choose the repeating reminder; its edit/delete affects future repeats.")};scope=resolved
            } else {scope = .occurrence;guard draft.scope == nil || draft.scope == "occurrence" else {throw ActionFailure.message("This item is not recurring.")}}
            if draft.kind == .deleteEvent || draft.kind == .deleteReminder {enteredWriter = true;return .init(message:try await deleteItem(baseline:baseline,scope:scope,valid:valid),itemID:baseline.itemID)}
            var edited=baseline;try edited.applyToolFields(draft)
            enteredWriter = true
            let saved=try await saveEdit(baseline:baseline,edited:edited,scope:scope,valid:valid)
            let undo=NativeEditRules.supportsUndo(baseline:baseline,edited:edited,scope:scope) ? NativeEditUndo(original:baseline,saved:saved) : nil
            return .init(message:"Updated " + (baseline.kind == .event ? "event: " : "reminder: ") + saved.title + (scope == .futureEvents ? " (this and all future events)" : scope == .reminderSeries ? " (repeating reminder)" : ""),itemID:saved.itemID,nativeUndo:undo)
        } catch {
            if !enteredWriter { throw NativePreSaveFailure(message: error.localizedDescription) }
            throw error
        }
    }
}

#if DEBUG
extension EventKitService {
    func validateCleanNotes() async -> [String:Int] {
        let nonce=UUID().uuidString,prefix="Mission Control notes validation "
        var checks=["blankReminder":0,"blankEvent":0,"suppliedNotesPreserved":0,"cleanupPreservedNotes":0,"cleanupErrors":0,"errors":0]
        creationNotesCheckIDs=[]
        do {
            guard EKEventStore.authorizationStatus(for:.reminder) == .fullAccess,EKEventStore.authorizationStatus(for:.event) == .fullAccess else {throw IntegrationError.denied("existing native access")}
            store.reset()
            let lists=Set(store.calendars(for:.reminder).filter{$0.allowsContentModifications}.map(\.calendarIdentifier)),calendars=Set(store.calendars(for:.event).filter{$0.allowsContentModifications}.map(\.calendarIdentifier))
            let reminder=try await applyTool(.init(kind:.createReminder,title:prefix+nonce+" reminder",hasTime:false),reminder:nil,event:nil,marker:String(repeating:"1",count:64),allowedCalendars:calendars,allowedLists:lists)
            guard let reminderID=reminder.itemID else {throw IntegrationError.verification}
            store.reset();checks["blankReminder"]=(store.calendarItem(withIdentifier:reminderID)?.notes ?? "").isEmpty ? 1 : 0
            let start=Date.now.addingTimeInterval(3600)
            let event=try await applyTool(.init(kind:.createEvent,title:prefix+nonce+" event",start:start.ISO8601Format(),end:start.addingTimeInterval(1800).ISO8601Format(),allDay:false),reminder:nil,event:nil,marker:String(repeating:"2",count:64),allowedCalendars:calendars,allowedLists:lists)
            guard let eventID=event.itemID else {throw IntegrationError.verification}
            store.reset();checks["blankEvent"]=(store.calendarItem(withIdentifier:eventID)?.notes ?? "").isEmpty ? 1 : 0
            let key=String(repeating:"3",count:64),notes="Real fixture notes\nMission Control request "+String(repeating:"3",count:64)+"\nRetain this line"
            let supplied=try await applyTool(.init(kind:.createReminder,title:prefix+nonce+" supplied",hasTime:false,notes:notes),reminder:nil,event:nil,marker:key,allowedCalendars:calendars,allowedLists:lists)
            guard let suppliedID=supplied.itemID else {throw IntegrationError.verification}
            store.reset();checks["suppliedNotesPreserved"]=store.calendarItem(withIdentifier:suppliedID)?.notes == notes ? 1 : 0
            let cleared=try await clearRequestMarker(id:suppliedID,receiptKey:key,valid:{true})
            store.reset();checks["cleanupPreservedNotes"]=cleared == .reminder && store.calendarItem(withIdentifier:suppliedID)?.notes == "Real fixture notes\nRetain this line" ? 1 : 0
        } catch {checks["errors",default:0] += 1}
        for id in creationNotesCheckIDs {
            do {
                store.reset();guard let item=store.calendarItem(withIdentifier:id) else {continue}
                guard item.title?.hasPrefix(prefix+nonce) == true else {throw IntegrationError.missing}
                if let reminder=item as? EKReminder {try store.remove(reminder,commit:true)}
                else if let event=item as? EKEvent {try store.remove(event,span:.thisEvent,commit:true)}
                store.reset();guard store.calendarItem(withIdentifier:id) == nil else {throw IntegrationError.verification}
            } catch {checks["cleanupErrors",default:0] += 1}
        }
        creationNotesCheckIDs=[];return checks
    }
    /// Own saved item identity and exact receipt marker, never title matching.
    func clearRequestMarker(id:String,receiptKey:String,eventScope:NativeChangeScope? = nil,valid:@escaping NativeWriteValidity) async throws -> NativeItemKind? {
        store.reset()
        guard var item=store.calendarItem(withIdentifier:id),NativeRequestNotes.cleaned(item.notes ?? "",receiptKey:receiptKey) != nil else {return nil}
        if let event=item as? EKEvent,event.hasRecurrenceRules {
            guard eventScope != nil else {throw ActionFailure.message("Recurring Calendar notes need an explicit scope.")}
            let now=Date.now,end=Calendar.current.date(byAdding:.day,value:90,to:now)!
            let upcoming=store.events(matching:store.predicateForEvents(withStart:now,end:end,calendars:[event.calendar])).filter{$0.calendarItemIdentifier == id && $0.startDate >= now}.sorted{$0.startDate < $1.startDate}
            guard let next=upcoming.first else {throw ActionFailure.message("No next occurrence in the bounded calendar range; nothing changed.")}
            item=next
        }
        guard let cleaned=NativeRequestNotes.cleaned(item.notes ?? "",receiptKey:receiptKey) else {return nil}
        let baseline=editorDetails(item)
        guard baseline.writable else {throw IntegrationError.readOnly}
        if let reminder=item as? EKReminder,reminder.isCompleted {throw IntegrationError.missing}
        var edited=baseline;edited.notes=cleaned
        let scope=baseline.kind == .reminder && baseline.recurring ? NativeChangeScope.reminderSeries : baseline.kind == .event && baseline.recurring ? eventScope! : .occurrence
        let saved=try await saveEdit(baseline:baseline,edited:edited,scope:scope,valid:valid)
        guard saved.notes == cleaned else {throw IntegrationError.verification}
        return baseline.kind
    }
}
#endif
