import Foundation
import EventKit

extension EventKitService: NativeActionWriting { }
extension EventKitService {
    private func equivalentDue(_ left: DateComponents?, _ right: DateComponents?) -> Bool {
        guard let left, let right else { return left == nil && right == nil }
        guard (left.hour != nil) == (right.hour != nil) else { return false }
        if left.hour == nil { return left.year == right.year && left.month == right.month && left.day == right.day }
        var leftCalendar = left.calendar ?? Calendar.current; leftCalendar.timeZone = left.timeZone ?? .current
        var rightCalendar = right.calendar ?? Calendar.current; rightCalendar.timeZone = right.timeZone ?? .current
        return leftCalendar.date(from:left) == rightCalendar.date(from:right)
    }
    func apply(_ draft: ActionDraft, reminder expected: TaskItem?, event expectedEvent: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>, valid: NativeWriteValidity? = nil, expectedDetails: NativeEditDetails? = nil) async throws -> ActionResult {
        do { return try await applyChecked(draft, reminder:expected, event:expectedEvent, marker:marker, allowedCalendars:allowedCalendars, allowedLists:allowedLists,valid:valid,expectedDetails:expectedDetails) }
        catch { store.reset(); throw error }
    }
    private func applyChecked(_ draft: ActionDraft, reminder expected: TaskItem?, event expectedEvent: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>, valid: NativeWriteValidity? = nil, expectedDetails: NativeEditDetails? = nil) async throws -> ActionResult {
        try ActionRules.validate(draft)
        switch draft.kind {
        case .deleteEvent,.deleteReminder: throw ActionFailure.message("Deletion requires the fresh native tool path.")
        case .createReminder, .editReminder, .completeReminder:
            try await access(.reminder)
            let item: EKReminder
            if draft.kind == .createReminder {
                guard draft.target == nil, let title = draft.title, !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.count <= 500 else { throw ActionFailure.message("Specify the new reminder's title.") }
                let writable = store.calendars(for:.reminder).filter { allowedLists.contains($0.calendarIdentifier) && $0.allowsContentModifications }
                let destination: EKCalendar?
                if let id = draft.destination { destination = writable.first { $0.calendarIdentifier == id } }
                else {
                    let matches = writable.filter { $0.title == "To do" }
                    guard matches.count == 1 else { throw ActionFailure.message("Choose a writable reminder list; the default To do list is unavailable or ambiguous.") }
                    destination = matches[0]
                }
                guard let destination else { throw IntegrationError.readOnly }
                item = EKReminder(eventStore:store); item.calendar = destination; item.title = title
                item.notes = NativeRequestNotes.creation(draft.notes)
            } else {
                guard let expected, draft.target == expected.id, allowedLists.contains(expected.listID),
                      let found = store.calendarItem(withIdentifier:expected.id) as? EKReminder,
                      !found.isCompleted, found.title == expected.title, found.calendar.calendarIdentifier == expected.listID else { throw IntegrationError.missing }
                guard found.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
                let components = found.dueDateComponents
                var calendar = components?.calendar ?? Calendar.current; calendar.timeZone = components?.timeZone ?? .current
                let due = components.flatMap { calendar.date(from:$0) }
                guard due == expected.due, (components?.hour != nil) == expected.hasTime, found.hasRecurrenceRules == expected.recurring else { throw IntegrationError.missing }
                if draft.kind == .completeReminder {
                    guard draft.title == nil, draft.destination == nil, draft.due == nil else { throw ActionFailure.message("Completion cannot also edit a reminder.") }
                    let token = try await complete(id:expected.id,valid:valid,expected:expectedDetails)
                    return .init(message:"Completed reminder: " + expected.title, undoToken:token, itemID:expected.id)
                }
                guard !found.hasRecurrenceRules else { throw ActionFailure.message("Editing a recurring reminder series is not supported yet; completion and Undo are available.") }
                item = found
            }
            if draft.kind == .editReminder, let title = draft.title {
                guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.count <= 500 else { throw ActionFailure.message("The reminder title is invalid.") }
                item.title = title
            }
            if let destination = draft.destination, draft.kind == .editReminder {
                guard allowedLists.contains(destination), let list = store.calendar(withIdentifier:destination), list.type != .subscription, list.allowedEntityTypes.contains(.reminder), list.allowsContentModifications else { throw IntegrationError.readOnly }
                item.calendar = list
            }
            if let due = draft.due {
                if due == "undated" { item.dueDateComponents = nil }
                else {
                    guard let hasTime = draft.hasTime else { throw ActionFailure.message("Specify whether the due date includes a time.") }
                    let date = try ActionRules.date(due,dateOnly:!hasTime)
                    item.dueDateComponents = Calendar.current.dateComponents(hasTime ? [.year,.month,.day,.hour,.minute,.second,.timeZone] : [.year,.month,.day],from:date)
                }
            }
            if let notes = draft.notes { item.notes = notes.isEmpty ? nil : notes }
            let title = item.title, calendarID = item.calendar.calendarIdentifier, due = item.dueDateComponents, notes = item.notes ?? ""
            do { try store.save(item,commit:true) } catch { store.reset(); throw error }
            guard let saved = store.calendarItem(withIdentifier:item.calendarItemIdentifier) as? EKReminder, !saved.isCompleted, saved.title == title, (saved.notes ?? "") == notes, saved.calendar.calendarIdentifier == calendarID, equivalentDue(saved.dueDateComponents,due) else { throw IntegrationError.verification }
            return .init(message:(draft.kind == .createReminder ? "Created reminder: " : "Updated reminder: ") + (title ?? "Untitled"),itemID:saved.calendarItemIdentifier)
        case .createEvent, .editEvent:
            try await access(.event)
            let item: EKEvent
            if draft.kind == .createEvent {
                guard draft.target == nil, let title = draft.title, !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.count <= 500 else { throw ActionFailure.message("Specify the event's title.") }
                let destination = draft.destination.flatMap { store.calendar(withIdentifier:$0) } ?? store.defaultCalendarForNewEvents
                guard let destination, allowedCalendars.contains(destination.calendarIdentifier), destination.allowsContentModifications, destination.allowedEntityTypes.contains(.event) else { throw IntegrationError.readOnly }
                item = EKEvent(eventStore:store); item.calendar = destination; item.title = title; item.notes = NativeRequestNotes.creation(draft.notes)
            } else {
                guard let expectedEvent, draft.target == expectedEvent.id, allowedCalendars.contains(expectedEvent.calendarID), let calendar = store.calendar(withIdentifier:expectedEvent.calendarID) else { throw IntegrationError.missing }
                let matches = store.events(matching:store.predicateForEvents(withStart:expectedEvent.start.addingTimeInterval(-1),end:expectedEvent.end.addingTimeInterval(1),calendars:[calendar])).filter { DateRules.occurrenceID($0.eventIdentifier ?? $0.calendarItemIdentifier,start:$0.startDate) == expectedEvent.id }
                guard matches.count == 1, let found = matches.first, found.title == expectedEvent.title, found.startDate == expectedEvent.start, found.endDate == expectedEvent.end, found.isAllDay == expectedEvent.allDay else { throw IntegrationError.missing }
                guard found.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
                guard !found.hasRecurrenceRules || draft.scope == "occurrence" else { throw ActionFailure.message("Specify the single recurring occurrence. Series edits are deferred.") }
                item = found
            }
            if let title = draft.title { guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.count <= 500 else { throw ActionFailure.message("Invalid event title.") }; item.title = title }
            if let destination = draft.destination, draft.kind == .editEvent {
                guard allowedCalendars.contains(destination), let calendar = store.calendar(withIdentifier:destination), calendar.allowedEntityTypes.contains(.event), calendar.allowsContentModifications else { throw IntegrationError.readOnly }
                item.calendar = calendar
            }
            let allDay = draft.allDay ?? item.isAllDay
            if draft.kind == .editEvent, allDay != item.isAllDay, (draft.start == nil || draft.end == nil) { throw ActionFailure.message("Changing all-day status requires explicit start and end dates.") }
            if let start = draft.start {
                let newStart = try ActionRules.date(start,dateOnly:allDay)
                if draft.kind == .editEvent, draft.end == nil {
                    if allDay { let days = Calendar.current.dateComponents([.day],from:item.startDate,to:item.endDate).day!; item.endDate = Calendar.current.date(byAdding:.day,value:days,to:newStart) }
                    else { item.endDate = newStart.addingTimeInterval(item.endDate.timeIntervalSince(item.startDate)) }
                }
                item.startDate = newStart
            }
            if let end = draft.end { item.endDate = try ActionRules.date(end,dateOnly:allDay) }
            guard item.startDate != nil, item.endDate != nil, item.endDate > item.startDate, item.endDate.timeIntervalSince(item.startDate) <= 366 * 86400 else { throw ActionFailure.message("Specify a valid event start and end; no duration was guessed.") }
            if draft.kind == .createEvent || draft.start != nil || draft.end != nil || draft.allDay != nil { item.timeZone = allDay ? .current : TimeZone(secondsFromGMT:0) }
            item.isAllDay = allDay
            if let notes = draft.notes { item.notes = notes.isEmpty ? nil : notes }
            if let location = draft.location { item.location = location.isEmpty ? nil : location }
            let expectedStart = item.startDate, expectedEnd = item.endDate, title = item.title, calendarID = item.calendar.calendarIdentifier, notes = item.notes ?? "", location = item.location ?? ""
            if allDay { item.endDate = expectedEnd!.addingTimeInterval(-1) }
            do { try store.save(item,span:.thisEvent,commit:true) } catch { store.reset(); throw error }
            let matches = store.events(matching:store.predicateForEvents(withStart:expectedStart!.addingTimeInterval(-1),end:expectedEnd!.addingTimeInterval(1),calendars:[item.calendar])).filter { $0.calendarItemIdentifier == item.calendarItemIdentifier && $0.startDate == expectedStart }
            guard matches.count == 1, let saved = matches.first, saved.title == title, (saved.notes ?? "") == notes, (saved.location ?? "") == location, editorDetails(saved).end == expectedEnd, saved.isAllDay == allDay, saved.calendar.calendarIdentifier == calendarID else { throw IntegrationError.verification }
            return .init(message:(draft.kind == .createEvent ? "Created event: " : "Updated event: ") + (title ?? "Untitled"),itemID:saved.calendarItemIdentifier)
        }
    }
    #if DEBUG
    func removeActionFixture(id: String, title: String, marker: String, expectedNotes:String? = nil) throws {
        // Tool-edit Undo can restore the original UUID title. Keep cleanup limited
        // to the exact tracked item and its unchanged, private creation marker.
        let prefix = "Mission Control tool validation "
        let suffix = title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count).prefix(36)) : ""
        let original = UUID(uuidString:suffix) == nil ? nil : prefix + suffix
        guard let item = store.calendarItem(withIdentifier:id),
              item.title == title || (original != nil && item.title == original),
              (item.notes ?? "") == (expectedNotes ?? "Mission Control request " + marker) else { throw IntegrationError.missing }
        if let reminder = item as? EKReminder { try store.remove(reminder,commit:true) }
        else if let event = item as? EKEvent { try store.remove(event,span:.thisEvent,commit:true) }
        guard store.calendarItem(withIdentifier:id) == nil else { throw IntegrationError.verification }
    }
    func validateDisposableActions() async throws -> String {
        try await access(.reminder); try await access(.event)
        guard let list = store.defaultCalendarForNewReminders(), list.allowsContentModifications,
              let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { throw IntegrationError.readOnly }
        let marker = UUID().uuidString, title = "Mission Control native action validation " + marker
        var fixtures: [(String,String,String)] = []
        var report = ""
        var stage = "reminder creation"
        do {
            var create = ActionDraft(kind:.createReminder,destination:list.calendarIdentifier,title:title,notes:"Mission Control request " + marker+"-1")
            let first = try await apply(create,reminder:nil,event:nil,marker:marker+"-1",allowedCalendars:[],allowedLists:[list.calendarIdentifier])
            create.notes="Mission Control request " + marker+"-2"
            let second = try await apply(create,reminder:nil,event:nil,marker:marker+"-2",allowedCalendars:[],allowedLists:[list.calendarIdentifier])
            guard let firstID = first.itemID, let secondID = second.itemID, firstID != secondID else { throw IntegrationError.verification }
            fixtures += [(firstID,title,marker+"-1"),(secondID,title,marker+"-2")]
            let snapshot = try await reminders()
            guard let expected = snapshot.reminders.first(where: { $0.id == firstID }) else { throw IntegrationError.missing }
            stage = "identity completion and Undo"
            let completed = try await apply(.init(kind:.completeReminder,target:firstID),reminder:expected,event:nil,marker:marker,allowedCalendars:[],allowedLists:[list.calendarIdentifier])
            guard let token = completed.undoToken, (store.calendarItem(withIdentifier:secondID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            try await undo(token:token)
            stage = "date-only reminder edit"
            _ = try await apply(.init(kind:.editReminder,target:firstID,title:title+" edited",due:DateRules.localDate(.now),hasTime:false),reminder:expected,event:nil,marker:marker,allowedCalendars:[],allowedLists:[list.calendarIdentifier])
            fixtures[0].1 = title+" edited"
            guard let editedReminder = try await reminders().reminders.first(where: { $0.id == firstID }) else { throw IntegrationError.missing }
            stage = "timed reminder edit"
            _ = try await apply(.init(kind:.editReminder,target:firstID,due:Date.now.addingTimeInterval(7200).ISO8601Format(),hasTime:true),reminder:editedReminder,event:nil,marker:marker,allowedCalendars:[],allowedLists:[list.calendarIdentifier])
            var staleRejected = false
            do { _ = try await apply(.init(kind:.completeReminder,target:firstID),reminder:expected,event:nil,marker:marker,allowedCalendars:[],allowedLists:[list.calendarIdentifier]) } catch { staleRejected = true }
            guard staleRejected, (store.calendarItem(withIdentifier:secondID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            stage = "timed event creation"
            let start = Date.now.addingTimeInterval(3600), end = start.addingTimeInterval(1800)
            let eventResult = try await apply(.init(kind:.createEvent,destination:calendar.calendarIdentifier,title:title,start:start.ISO8601Format(),end:end.ISO8601Format(),allDay:false,notes:"Mission Control request " + marker+"-event"),reminder:nil,event:nil,marker:marker+"-event",allowedCalendars:[calendar.calendarIdentifier],allowedLists:[])
            guard let eventID = eventResult.itemID else { throw IntegrationError.verification }
            fixtures.append((eventID,title,marker+"-event"))
            let events = try await self.calendar(from:start.addingTimeInterval(-1),to:end.addingTimeInterval(1))
            guard let native = store.calendarItem(withIdentifier:eventID) as? EKEvent,
                  let expectedEvent = events.events.first(where: { $0.id == DateRules.occurrenceID(native.eventIdentifier ?? native.calendarItemIdentifier,start:native.startDate) }) else { throw IntegrationError.verification }
            stage = "duration-preserving event edit"
            _ = try await apply(.init(kind:.editEvent,target:expectedEvent.id,title:title+" edited event",start:expectedEvent.start.addingTimeInterval(86400).ISO8601Format()),reminder:nil,event:expectedEvent,marker:marker,allowedCalendars:[calendar.calendarIdentifier],allowedLists:[])
            fixtures[2].1 = title+" edited event"
            stage = "all-day event creation"
            let today = Calendar.current.startOfDay(for:.now), tomorrow = Calendar.current.date(byAdding:.day,value:1,to:today)!
            let allDay = try await apply(.init(kind:.createEvent,destination:calendar.calendarIdentifier,title:title,start:DateRules.localDate(today),end:DateRules.localDate(tomorrow),allDay:true,notes:"Mission Control request " + marker+"-allday"),reminder:nil,event:nil,marker:marker+"-allday",allowedCalendars:[calendar.calendarIdentifier],allowedLists:[])
            guard let allDayID = allDay.itemID else { throw IntegrationError.verification }
            fixtures.append((allDayID,title,marker+"-allday"))
            report = "PASS action reminder create/edit/date-only/timed due/identity completion/Undo, duplicate isolation, stale-target rejection, timed/all-day event creation and duration-preserving event edit."
        } catch { report = "FAIL action check (" + stage + "): " + error.localizedDescription }
        // Discover only this run's exact UUID markers in case a save succeeded but verification threw.
        let markers = [marker+"-1",marker+"-2",marker+"-event",marker+"-allday"]
        let notes = Dictionary(uniqueKeysWithValues:markers.map { ("Mission Control request "+$0,$0) })
        let savedReminders: [EKReminder] = await withCheckedContinuation { continuation in store.fetchReminders(matching:store.predicateForReminders(in:[list])) { continuation.resume(returning:$0 ?? []) } }
        let lower = Calendar.current.startOfDay(for:.now), upper = Calendar.current.date(byAdding:.day,value:4,to:lower)!
        let savedEvents = store.events(matching:store.predicateForEvents(withStart:lower,end:upper,calendars:[calendar]))
        for item in (savedReminders as [EKCalendarItem]) + (savedEvents as [EKCalendarItem]) {
            if let note = item.notes, let itemMarker = notes[note], !fixtures.contains(where: { $0.0 == item.calendarItemIdentifier }) { fixtures.append((item.calendarItemIdentifier,item.title ?? "",itemMarker)) }
        }
        var failures = 0
        for fixture in fixtures {
            guard let remaining = store.calendarItem(withIdentifier:fixture.0) else { continue }
            do { try removeActionFixture(id:fixture.0,title:remaining.title ?? fixture.1,marker:fixture.2) } catch { failures += 1 }
        }
        return report + (failures == 0 ? " Disposable items cleaned and absence verified." : " Cleanup failed for \(failures) tracked fixtures; inspect Apple apps.")
    }
    #endif
}
