import Foundation
import EventKit

#if DEBUG
struct CalendarRemovalFixture {
    var calendarID:String
    var marker:String
    var start:Date
    var end:Date
    var itemIDs:[String:String]
}
extension EventKitService {
    func makeRemovalFixture()throws->CalendarRemovalFixture {
        guard EKEventStore.authorizationStatus(for:.event) == .fullAccess else {throw IntegrationError.denied("Existing Calendar permission required for disposable check")}
        store.reset()
        guard let source=store.defaultCalendarForNewEvents?.source else {throw IntegrationError.readOnly}
        let marker="3PO removal validation "+UUID().uuidString
        let calendar=EKCalendar(for:.event,eventStore:store);calendar.title=marker;calendar.source=source
        try store.saveCalendar(calendar,commit:true)
        let start=Calendar.current.startOfDay(for:.now),end=Calendar.current.date(byAdding:.day,value:8,to:start)!
        var fixture=CalendarRemovalFixture(calendarID:calendar.calendarIdentifier,marker:marker,start:start,end:end,itemIDs:[:])
        do {
            for (key,day,allDay) in [("single",1,false),("repeat",2,false),("allDay",6,true)] {
                let event=EKEvent(eventStore:store);event.calendar=calendar;event.title="Orion Computer Vision lecture · "+key;event.notes=marker
                let date=Calendar.current.date(byAdding:.day,value:day,to:start)!
                event.startDate=allDay ? date : date.addingTimeInterval(14*3600)
                event.endDate=allDay ? date.addingTimeInterval(86400-1) : event.startDate.addingTimeInterval(3600)
                event.isAllDay=allDay
                if key == "repeat" {event.recurrenceRules=[EKRecurrenceRule(recurrenceWith:.daily,interval:1,end:EKRecurrenceEnd(occurrenceCount:3))]}
                try store.save(event,span:.thisEvent,commit:true);fixture.itemIDs[key]=event.calendarItemIdentifier
            }
            return fixture
        } catch {try? removeRemovalFixture(fixture);throw error}
    }
    private func removalFixtureItems(_ fixture:CalendarRemovalFixture,key:String)throws->[EKEvent] {
        store.reset()
        guard let calendar=store.calendar(withIdentifier:fixture.calendarID),calendar.title == fixture.marker,let id=fixture.itemIDs[key] else {throw IntegrationError.missing}
        return store.events(matching:store.predicateForEvents(withStart:fixture.start,end:fixture.end,calendars:[calendar])).filter{$0.calendarItemIdentifier == id && ($0.notes == fixture.marker || $0.notes == fixture.marker+" external edit")}.sorted{$0.startDate < $1.startDate}
    }
    func removalFixtureEvent(_ fixture:CalendarRemovalFixture,key:String,index:Int = 0)throws->AgendaEvent {
        let values=try removalFixtureItems(fixture,key:key)
        guard values.indices.contains(index) else {throw IntegrationError.missing}
        let event=values[index]
        return AgendaEvent(id:DateRules.occurrenceID(event.eventIdentifier ?? event.calendarItemIdentifier,start:event.startDate),calendarID:fixture.calendarID,title:event.title,start:event.startDate,end:event.endDate,allDay:event.isAllDay,location:event.location ?? "",sourceLabel:fixture.marker,modified:event.lastModifiedDate,memoryItemID:event.calendarItemIdentifier)
    }
    func removalFixtureCount(_ fixture:CalendarRemovalFixture,key:String)throws->Int {try removalFixtureItems(fixture,key:key).count}
    func changeRemovalFixture(_ fixture:CalendarRemovalFixture,key:String)throws {
        guard let event=try removalFixtureItems(fixture,key:key).first else {throw IntegrationError.missing}
        event.notes=fixture.marker+" external edit";try store.save(event,span:.thisEvent,commit:true);store.reset()
    }
    func removeRemovalFixture(_ fixture:CalendarRemovalFixture)throws {
        store.reset()
        guard let calendar=store.calendar(withIdentifier:fixture.calendarID),calendar.title == fixture.marker else {throw IntegrationError.missing}
        let items=store.events(matching:store.predicateForEvents(withStart:fixture.start,end:fixture.end,calendars:[calendar]))
        guard items.allSatisfy({$0.notes == fixture.marker || $0.notes == fixture.marker+" external edit"}) else {throw IntegrationError.verification}
        try store.removeCalendar(calendar,commit:true);store.reset()
        guard store.calendar(withIdentifier:fixture.calendarID) == nil else {throw IntegrationError.verification}
    }
}
#endif

extension EventKitService {
    func editorDetails(_ item: EKCalendarItem) -> NativeEditDetails {
        var value = NativeEditDetails(kind:item is EKEvent ? .event : .reminder,itemID:item.calendarItemIdentifier,occurrenceID:item.calendarItemIdentifier,sourceID:item.calendar.calendarIdentifier,title:item.title ?? "",notes:item.notes ?? "",recurring:item.hasRecurrenceRules,writable:item.calendar.allowsContentModifications,modified:item.lastModifiedDate)
        value.recurrenceRules = (item.recurrenceRules ?? []).map(NativeRecurrence.init)
        value.url = item.url?.absoluteString ?? ""
        value.alarms = (item.alarms ?? []).filter { $0.structuredLocation == nil && $0.emailAddress == nil && $0.soundName == nil && $0.type.rawValue == 0 }.map { NativeTimeAlarm(absolute:$0.absoluteDate,offset:$0.relativeOffset) }
        value.otherAlarmSignatures = (item.alarms ?? []).map { alarm in
            [alarm.absoluteDate.map { String($0.timeIntervalSince1970) } ?? "",String(alarm.relativeOffset),String(alarm.proximity.rawValue),alarm.structuredLocation?.title ?? "",alarm.structuredLocation?.geoLocation.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? "",String(alarm.structuredLocation?.radius ?? 0),alarm.emailAddress ?? "",alarm.soundName ?? "",String(alarm.type.rawValue)].joined(separator:"|")
        }.sorted()
        if let event = item as? EKEvent {
            value.occurrenceID = DateRules.occurrenceID(event.eventIdentifier ?? event.calendarItemIdentifier,start:event.startDate)
            value.availability = event.availability.rawValue
            value.start = event.startDate; value.end = event.endDate; value.allDay = event.isAllDay; value.location = event.location ?? ""
            if event.isAllDay {
                let endDay = Calendar.current.startOfDay(for:event.endDate)
                if event.endDate != endDay { value.end = Calendar.current.date(byAdding:.day,value:1,to:endDay)! }
            }
            value.timeZoneID = event.isAllDay ? TimeZone.current.identifier : (event.timeZone?.identifier ?? TimeZone.current.identifier)
        } else if let reminder = item as? EKReminder {
            value.priority = Int(reminder.priority)
            var calendar = reminder.dueDateComponents?.calendar ?? Calendar.current
            calendar.timeZone = reminder.dueDateComponents?.timeZone ?? .current
            value.due = reminder.dueDateComponents.flatMap { calendar.date(from:$0) }
            value.hasTime = reminder.dueDateComponents?.hour != nil; value.timeZoneID = calendar.timeZone.identifier
        }
        return value
    }
    func editorEvent(_ id: String, sourceID: String, start: Date, end: Date) throws -> EKEvent {
        guard let source = store.calendar(withIdentifier:sourceID) else { throw IntegrationError.missing }
        let matches = store.events(matching:store.predicateForEvents(withStart:start.addingTimeInterval(-1),end:max(end,start).addingTimeInterval(1),calendars:[source])).filter { DateRules.occurrenceID($0.eventIdentifier ?? $0.calendarItemIdentifier,start:$0.startDate) == id }
        guard matches.count == 1, let event = matches.first else { throw IntegrationError.missing }; return event
    }
    func editSession(_ target: NativeEditTarget) async throws -> NativeEditSession {
        switch target {
        case .create(let request): return try await creationSession(request)
        case .event(let expected),.reviewEvent(let expected,_):
            try await access(.event); store.reset()
            let event = try editorEvent(expected.id,sourceID:expected.calendarID,start:expected.start,end:expected.end)
            guard (event.title ?? "Untitled event") == expected.title, event.startDate == expected.start, event.endDate == expected.end, event.isAllDay == expected.allDay, (event.location ?? "") == expected.location else { throw IntegrationError.missing }
            return NativeEditSession(item:editorDetails(event),sources:store.calendars(for:.event).map(option))
        case .reminder(let expected),.reviewReminder(let expected,_):
            try await access(.reminder); store.reset()
            guard let reminder = store.calendarItem(withIdentifier:expected.id) as? EKReminder, !reminder.isCompleted else { throw IntegrationError.missing }
            let details = editorDetails(reminder)
            try NativeCompletionRules.validateDisplayed(expected, details: details)
            return NativeEditSession(item:details,sources:store.calendars(for:.reminder).map(option))
        }
    }
    @discardableResult func saveEdit(baseline: NativeEditDetails, edited: NativeEditDetails, scope: NativeChangeScope = .occurrence, valid: NativeWriteValidity? = nil, claim:NativeWriteClaim? = nil) async throws -> NativeEditDetails {
        var saveAttempted=false
        do {
            #if DEBUG
            nativeCheckMismatch=nil
            #endif
            try NativeEditRules.validate(edited,baseline:baseline)
            try NativeEditRules.validateScope(scope,baseline:baseline,edited:edited)
            try await access(baseline.kind == .event ? .event : .reminder)
            if let valid {guard await valid() else {throw ActionFailure.message("Account or assistant controls changed before saving; no native change attempted.")}}
            try Task.checkCancellation()
            store.reset()
            let verified: NativeEditDetails
            var native: EKCalendarItem
            if baseline.kind == .event { native = try editorEvent(baseline.occurrenceID,sourceID:baseline.sourceID,start:baseline.start,end:baseline.end) }
            else {
                guard let reminder = store.calendarItem(withIdentifier:baseline.itemID) as? EKReminder, !reminder.isCompleted else {
                    #if DEBUG
                    nativeCheckMismatch="native reminder lookup"
                    #endif
                    throw IntegrationError.missing
                }; native = reminder
            }
            // Compare all exposed fields and revision before mutating, including notes not held in dashboard caches.
            let fresh=editorDetails(native)
            guard fresh == baseline else {
                #if DEBUG
                nativeCheckMismatch=NativeEditRules.differingFields(fresh,baseline).joined(separator:", ")
                #endif
                throw IntegrationError.missing
            }
            guard var destination = store.calendar(withIdentifier:edited.sourceID), destination.allowsContentModifications,
                  destination.allowedEntityTypes.contains(baseline.kind == .event ? .event : .reminder) else { throw IntegrationError.readOnly }
            if let claim {
                try await claim()
                try Task.checkCancellation()
                // The claim hops to MainActor. Re-fetch after that suspension, before mutation.
                store.reset()
                if baseline.kind == .event { native=try editorEvent(baseline.occurrenceID,sourceID:baseline.sourceID,start:baseline.start,end:baseline.end) }
                else { guard let current=store.calendarItem(withIdentifier:baseline.itemID) as? EKReminder,!current.isCompleted else {throw IntegrationError.missing};native=current }
                guard editorDetails(native) == baseline else {throw IntegrationError.missing}
                guard let currentDestination=store.calendar(withIdentifier:edited.sourceID),currentDestination.allowsContentModifications,currentDestination.allowedEntityTypes.contains(baseline.kind == .event ? .event : .reminder) else {throw IntegrationError.readOnly}
                destination=currentDestination
            }
            native.title = edited.title; native.notes = edited.notes.isEmpty ? nil : edited.notes; native.calendar = destination
            if let event = native as? EKEvent {
                event.location = edited.location.isEmpty ? nil : edited.location
                if edited.start != baseline.start || edited.end != baseline.end || edited.allDay != baseline.allDay || edited.timeZoneID != baseline.timeZoneID {
                    if edited.timeZoneID != baseline.timeZoneID || edited.allDay != baseline.allDay {
                        event.timeZone = TimeZone(identifier:edited.timeZoneID) ?? .current
                    }
                    event.isAllDay = edited.allDay
                    // EventKit normalises dates when changing all-day/time-zone state.
                    // Set the requested boundaries after that conversion.
                    event.startDate = edited.start; event.endDate = edited.allDay ? edited.end.addingTimeInterval(-1) : edited.end
                }
                try applyExtendedFields(edited,baseline:baseline,to:event)
                saveAttempted=true
                try store.save(event,span:scope == .futureEvents ? .futureEvents : .thisEvent,commit:true)
                let matches = store.events(matching:store.predicateForEvents(withStart:edited.start.addingTimeInterval(-1),end:edited.end.addingTimeInterval(1),calendars:[destination])).filter { $0.calendarItemIdentifier == event.calendarItemIdentifier && $0.startDate == edited.start }
                guard matches.count == 1, let saved = matches.first else {
                    #if DEBUG
                    throw ActionFailure.message("Event verification found \(matches.count) exact start/identity matches (all-day: \(edited.allDay)).")
                    #else
                    throw IntegrationError.verification
                    #endif
                }
                guard saved.title == edited.title, (saved.notes ?? "") == edited.notes, (saved.location ?? "") == edited.location, editorDetails(saved).end == edited.end, saved.isAllDay == edited.allDay else {
                    #if DEBUG
                    throw ActionFailure.message("Event verification mismatch: title=\(saved.title == edited.title), notes=\((saved.notes ?? "") == edited.notes), location=\((saved.location ?? "") == edited.location), end=\(editorDetails(saved).end == edited.end), allDay=\(saved.isAllDay == edited.allDay).")
                    #else
                    throw IntegrationError.verification
                    #endif
                }
                verified = editorDetails(saved)
                try verifyExtendedFields(verified,expected:edited,baseline:baseline)
            } else if let reminder = native as? EKReminder {
                if edited.due != baseline.due || edited.hasTime != baseline.hasTime {
                    var calendar = Calendar.current; calendar.timeZone = TimeZone(identifier:edited.timeZoneID) ?? .current
                    reminder.dueDateComponents = edited.due.map { calendar.dateComponents(edited.hasTime ? [.year,.month,.day,.hour,.minute,.second,.timeZone] : [.year,.month,.day],from:$0) }
                }
                try applyExtendedFields(edited,baseline:baseline,to:reminder)
                saveAttempted=true
                try store.save(reminder,commit:true)
                guard let saved = store.calendarItem(withIdentifier:reminder.calendarItemIdentifier) as? EKReminder, !saved.isCompleted else { throw IntegrationError.verification }
                let details = editorDetails(saved)
                guard details.title == edited.title, details.notes == edited.notes, details.sourceID == edited.sourceID, details.hasTime == edited.hasTime else { throw IntegrationError.verification }
                if edited.hasTime { guard details.due == edited.due else { throw IntegrationError.verification } }
                else { let savedDay = details.due.map { DateRules.localDate($0) }, editedDay = edited.due.map { DateRules.localDate($0) }; guard savedDay == editedDay else { throw IntegrationError.verification } }
                try verifyExtendedFields(details,expected:edited,baseline:baseline)
                verified = details
            }
            else { throw IntegrationError.missing }
            return verified
        } catch { store.reset();if !saveAttempted {throw NativePreSaveFailure(message:error.localizedDescription)};throw error }
    }
    func undoEdit(_ undo: NativeEditUndo) async throws {
        // saveEdit compares the complete saved revision before restoring exact fields.
        try await saveEdit(baseline:undo.saved,edited:NativeEditRules.restoring(undo))
    }
    #if DEBUG
    func mutateReviewFixture(_ id:String,marker:String) throws {
        store.reset();guard let item=store.calendarItem(withIdentifier:id) as? EKReminder,item.notes == marker,item.title == marker else {throw IntegrationError.verification}
        item.notes=marker+" external edit";try store.save(item,commit:true)
    }
    func validateReviewClaim() async throws->[String:Bool] {
        guard EKEventStore.authorizationStatus(for:.reminder) == .fullAccess else {throw IntegrationError.denied("Existing Reminders permission required for disposable check")}
        store.reset();guard let list=store.defaultCalendarForNewReminders(),list.allowsContentModifications else {throw IntegrationError.readOnly}
        let marker="Mission Control review validation "+UUID().uuidString
        let fixture=EKReminder(eventStore:store);fixture.calendar=list;fixture.title=marker;fixture.notes=marker
        try store.save(fixture,commit:true);let id=fixture.calendarItemIdentifier
        func cleanup() throws {
            store.reset();guard let item=store.calendarItem(withIdentifier:id) as? EKReminder,item.title == marker,item.notes == marker || item.notes == marker+" external edit" else {throw IntegrationError.verification}
            try store.remove(item,commit:true);store.reset();guard store.calendarItem(withIdentifier:id) == nil else {throw IntegrationError.verification}
        }
        do {
            store.reset();guard let original=store.calendarItem(withIdentifier:id) else {throw IntegrationError.missing}
            let baseline=editorDetails(original);var edited=baseline;edited.due=Calendar.current.startOfDay(for:.now.addingTimeInterval(86400));edited.hasTime=false
            var checks:[String:Bool]=[:]
            do {_=try await saveEdit(baseline:baseline,edited:edited,valid:{false},claim:{});checks["source revocation blocks native save"]=false} catch {checks["source revocation blocks native save"]=true}
            do {_=try await saveEdit(baseline:baseline,edited:edited,claim:{throw ActionFailure.message("Fictional source changed before claim")});checks["claim refusal is a known pre-save failure"]=false} catch is NativePreSaveFailure {checks["claim refusal is a known pre-save failure"]=true}
            let mutate:NativeWriteClaim = {try await self.mutateReviewFixture(id,marker:marker)}
            do {_=try await saveEdit(baseline:baseline,edited:edited,claim:mutate);checks["target change during actor hop rejects stale save"]=false} catch is NativePreSaveFailure {checks["target change during actor hop rejects stale save"]=true}
            store.reset();guard let current=store.calendarItem(withIdentifier:id) else {throw IntegrationError.missing}
            let changed=editorDetails(current)
            checks["outside fixture edit preserved and date untouched"]=changed.notes == marker+" external edit" && changed.due == baseline.due
            var fresh=changed;fresh.due=edited.due;fresh.hasTime=false
            let saved=try await saveEdit(baseline:changed,edited:fresh,claim:{})
            checks["approved fresh save verified"]=saved.due.map{DateRules.localDate($0)} == fresh.due.map{DateRules.localDate($0)} && saved.notes == changed.notes
            try await undoEdit(.init(original:changed,saved:saved))
            try cleanup();checks["disposable fixture removed and absence verified"]=true
            return checks
        } catch {try? cleanup();throw error}
    }
    func validateNativeEditors() async throws -> String {
        try await access(.event); try await access(.reminder)
        guard let list = store.defaultCalendarForNewReminders(), list.allowsContentModifications,
              let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else { throw IntegrationError.readOnly }
        let marker = "Mission Control editor validation " + UUID().uuidString
        var fixtures: [(String,NativeItemKind)] = []
        var stage = "create reminder fixtures"
        let fixtureStart = Calendar.current.startOfDay(for:.now)
        let fixtureEnd = Calendar.current.date(byAdding:.day,value:5,to:fixtureStart)!
        func cleanup() throws {
            for (id,kind) in fixtures where kind == .reminder {
                guard let item = store.calendarItem(withIdentifier:id), item.notes?.hasPrefix(marker) == true else { throw IntegrationError.verification }
                if kind == .reminder, let reminder = item as? EKReminder { try store.remove(reminder,commit:true) }
                guard store.calendarItem(withIdentifier:id) == nil else { throw IntegrationError.verification }
            }
            // A detached occurrence can acquire a new ID. Reconcile only this UUID's
            // own notes marker in the fixture calendar/range, never titles.
            for _ in 0..<10 {
                let remaining = store.events(matching:store.predicateForEvents(withStart:fixtureStart,end:fixtureEnd,calendars:[calendar])).filter { $0.notes?.hasPrefix(marker) == true }.sorted { $0.startDate < $1.startDate }
                guard let event = remaining.first else { break }
                try store.remove(event,span:event.hasRecurrenceRules ? .futureEvents : .thisEvent,commit:true)
            }
            guard store.events(matching:store.predicateForEvents(withStart:fixtureStart,end:fixtureEnd,calendars:[calendar])).allSatisfy({ $0.notes?.hasPrefix(marker) != true }) else { throw IntegrationError.verification }
            fixtures = []
        }
        do {
            for _ in 0..<2 {
                let item = EKReminder(eventStore:store); item.title = marker; item.notes = marker; item.calendar = list
                try store.save(item,commit:true); fixtures.append((item.calendarItemIdentifier,.reminder))
            }
            guard let reminder = try await reminders().reminders.first(where:{ $0.id == fixtures[0].0 }) else { throw IntegrationError.missing }
            let baseline = try await editSession(.reminder(reminder)).item
            var edit = baseline; edit.title += " edited"; edit.notes += "\nEditor notes"; edit.due = Calendar.current.startOfDay(for:.now); edit.hasTime = false
            stage = "save date-only reminder"; try await saveEdit(baseline:baseline,edited:edit)
            store.reset()
            guard let other = store.calendarItem(withIdentifier:fixtures[1].0) as? EKReminder, other.title == marker, other.notes == marker, other.dueDateComponents == nil else { throw IntegrationError.verification }
            let current = editorDetails(store.calendarItem(withIdentifier:fixtures[0].0)!)
            var timed = current; timed.due = Date(timeIntervalSince1970:floor(Date.now.addingTimeInterval(7200).timeIntervalSince1970)); timed.hasTime = true
            stage = "save timed reminder"; try await saveEdit(baseline:current,edited:timed)
            store.reset()
            var staleRejected = false
            do { try await saveEdit(baseline:baseline,edited:edit) } catch is NativePreSaveFailure { staleRejected = true }
            guard staleRejected else { throw IntegrationError.verification }
            let timedCurrent = editorDetails(store.calendarItem(withIdentifier:fixtures[0].0)!)
            var undated = timedCurrent; undated.due = nil; undated.hasTime = false
            stage = "save undated reminder"; let undatedSaved = try await saveEdit(baseline:timedCurrent,edited:undated)
            stage = "undo reminder edit"; try await undoEdit(.init(original:timedCurrent,saved:undatedSaved))
            store.reset()
            guard let undoReminder = store.calendarItem(withIdentifier:fixtures[0].0) as? EKReminder, editorDetails(undoReminder).due == timedCurrent.due, editorDetails(undoReminder).hasTime == timedCurrent.hasTime else { throw IntegrationError.verification }
            let event = EKEvent(eventStore:store); event.title = marker; event.notes = marker; event.calendar = calendar
            event.startDate = Date(timeIntervalSince1970:floor(Date.now.addingTimeInterval(86400).timeIntervalSince1970)); event.endDate = event.startDate.addingTimeInterval(3600)
            try store.save(event,span:.thisEvent,commit:true); fixtures.append((event.calendarItemIdentifier,.event))
            stage = "read persisted event fixture"
            let fixtureEventID=event.calendarItemIdentifier,fixtureEventStart=event.startDate!,fixtureEventEnd=event.endDate!
            store.reset()
            let persistedEvents=store.events(matching:store.predicateForEvents(withStart:fixtureEventStart.addingTimeInterval(-1),end:fixtureEventEnd.addingTimeInterval(1),calendars:[calendar])).filter{$0.calendarItemIdentifier == fixtureEventID && $0.startDate == fixtureEventStart}
            guard persistedEvents.count == 1 else {throw IntegrationError.verification}
            let eventBaseline = editorDetails(persistedEvents[0])
            var eventEdit = eventBaseline; eventEdit.title += " edited"; eventEdit.notes += "\nEditor notes"; eventEdit.location = "Fictional test room";eventEdit.timeZoneID="America/New_York"
            eventEdit.start = eventEdit.start.addingTimeInterval(3600); eventEdit.end = eventEdit.end.addingTimeInterval(3600)
            stage = "save timed event"; try await saveEdit(baseline:eventBaseline,edited:eventEdit)
            store.reset()
            guard let savedEvent = store.calendarItem(withIdentifier:fixtures[2].0) as? EKEvent else { throw IntegrationError.verification }
            let eventCurrent = editorDetails(savedEvent)
            let wholeDay = NativeEditRules.allDay(eventCurrent,enabled:true)
            stage = "save all-day event"; let wholeSaved = try await saveEdit(baseline:eventCurrent,edited:wholeDay)
            stage = "undo event edit"; try await undoEdit(.init(original:eventCurrent,saved:wholeSaved))
            store.reset()
            guard let undoEvent = store.calendarItem(withIdentifier:fixtures[2].0) as? EKEvent, !undoEvent.isAllDay, undoEvent.startDate == eventCurrent.start, editorDetails(undoEvent).end == eventCurrent.end else { throw IntegrationError.verification }
            store.reset()
            guard let changed = store.calendarItem(withIdentifier:fixtures[2].0) as? EKEvent else { throw IntegrationError.verification }
            let beforeExternalChange = editorDetails(changed)
            changed.notes = marker + "\nExternal fixture change"; try store.save(changed,span:.thisEvent,commit:true)
            var rejectedExternal = false
            do { try await undoEdit(.init(original:eventBaseline,saved:beforeExternalChange)) } catch is NativePreSaveFailure { rejectedExternal = true }
            guard rejectedExternal else { throw IntegrationError.verification }
            stage = "edit one recurring occurrence"
            let series = EKEvent(eventStore:store); series.calendar = calendar; series.title = marker; series.notes = marker
            series.startDate = Calendar.current.date(byAdding:.day,value:2,to:fixtureStart)!.addingTimeInterval(12*3600); series.endDate = series.startDate.addingTimeInterval(3600)
            series.addRecurrenceRule(EKRecurrenceRule(recurrenceWith:.daily,interval:1,end:EKRecurrenceEnd(occurrenceCount:2)))
            try store.save(series,span:.thisEvent,commit:true); store.reset()
            let occurrences = store.events(matching:store.predicateForEvents(withStart:series.startDate,end:fixtureEnd,calendars:[calendar])).filter { $0.notes == marker }.sorted { $0.startDate < $1.startDate }
            guard occurrences.count == 2 else { throw IntegrationError.verification }
            let occurrence = editorDetails(occurrences[0]); var one = occurrence; one.title += " selected occurrence"
            try await saveEdit(baseline:occurrence,edited:one); store.reset()
            let after = store.events(matching:store.predicateForEvents(withStart:occurrence.start,end:fixtureEnd,calendars:[calendar])).filter { $0.notes == marker }.sorted { $0.startDate < $1.startDate }
            guard after.count == 2, after[0].title == one.title, after[1].title == marker, after[1].startDate == occurrences[1].startDate else { throw IntegrationError.verification }
            stage = "create forever repeat and delete future events"
            let forever = EKEvent(eventStore:store); forever.calendar=calendar;forever.title=marker;forever.notes=marker
            forever.startDate=Calendar.current.date(byAdding:.day,value:1,to:fixtureStart)!.addingTimeInterval(8*3600);forever.endDate=forever.startDate.addingTimeInterval(1800)
            forever.addRecurrenceRule(EKRecurrenceRule(recurrenceWith:.daily,interval:1,end:nil));try store.save(forever,span:.thisEvent,commit:true);store.reset()
            let foreverItems=store.events(matching:store.predicateForEvents(withStart:forever.startDate,end:fixtureEnd,calendars:[calendar])).filter{$0.calendarItemIdentifier == forever.calendarItemIdentifier}.sorted{$0.startDate < $1.startDate}
            guard foreverItems.count >= 3 else {throw IntegrationError.verification}
            let futureBaseline=editorDetails(foreverItems[1])
            var futureEdit=futureBaseline;futureEdit.location="Fictional future room";futureEdit.alarms=[.init(offset:-600)];futureEdit.url="https://example.com/test"
            let futureSaved=try await saveEdit(baseline:futureBaseline,edited:futureEdit,scope:.futureEvents)
            store.reset()
            let preserved=store.events(matching:store.predicateForEvents(withStart:foreverItems[0].startDate,end:foreverItems[0].endDate,calendars:[calendar])).filter{$0.calendarItemIdentifier == foreverItems[0].calendarItemIdentifier && $0.startDate == foreverItems[0].startDate}
            guard preserved.count == 1,(preserved[0].location ?? "").isEmpty else {throw IntegrationError.verification}
            let issuedFuture=AgendaEvent(id:futureSaved.occurrenceID,calendarID:futureSaved.sourceID,title:futureSaved.title,start:futureSaved.start,end:futureSaved.end,allDay:futureSaved.allDay,location:futureSaved.location,sourceLabel:"Disposable fixture")
            let deletionDraft=ActionDraft(kind:.deleteEvent,target:issuedFuture.id,scope:"futureEvents")
            var lateControlRejected=false
            do {_ = try await applyTool(deletionDraft,reminder:nil,event:issuedFuture,marker:marker,allowedCalendars:[calendar.calendarIdentifier],allowedLists:[],expectedDetails:futureSaved,valid:{false})} catch {lateControlRejected=true}
            guard lateControlRejected else {throw IntegrationError.verification}
            _ = try await applyTool(deletionDraft,reminder:nil,event:issuedFuture,marker:marker,allowedCalendars:[calendar.calendarIdentifier],allowedLists:[],expectedDetails:futureSaved)
            store.reset()
            let earlier=store.events(matching:store.predicateForEvents(withStart:foreverItems[0].startDate,end:foreverItems[0].endDate,calendars:[calendar])).filter{$0.notes == marker && $0.startDate == foreverItems[0].startDate}
            guard earlier.count == 1 else {throw IntegrationError.verification}
            stage = "recurring reminder creation and edit"
            let repeating=EKReminder(eventStore:store);repeating.calendar=list;repeating.title=marker;repeating.notes=marker
            repeating.dueDateComponents=Calendar.current.dateComponents([.year,.month,.day],from:fixtureStart)
            repeating.addRecurrenceRule(try NativeRecurrence(frequency:"monthly",monthDays:[-1],count:4).native());try store.save(repeating,commit:true);fixtures.append((repeating.calendarItemIdentifier,.reminder));store.reset()
            let repeatingBase=editorDetails(store.calendarItem(withIdentifier:repeating.calendarItemIdentifier)!)
            var repeatingEdit=repeatingBase;repeatingEdit.priority=1;repeatingEdit.url="https://example.com/reminder";repeatingEdit.alarms=[.init(absolute:fixtureStart.addingTimeInterval(10*3600))]
            repeatingEdit.recurrenceRules=[.init(frequency:"weekly",interval:2,weekdays:[.init(weekday:2)],count:5)]
            let repeatingSaved=try await saveEdit(baseline:repeatingBase,edited:repeatingEdit,scope:.reminderSeries)
            stage = "stale deletion rejection"
            var rejectedDelete=false
            do {_ = try await deleteItem(baseline:repeatingBase,scope:.reminderSeries)} catch is NativePreSaveFailure {rejectedDelete=true}
            guard rejectedDelete else {throw IntegrationError.verification}
            _ = try await deleteItem(baseline:repeatingSaved,scope:.reminderSeries);fixtures.removeAll{$0.0 == repeatingSaved.itemID}
            stage = "native form repeat creation"
            let creation=NativeCreationRequest(kind:.event,registration:"disposable",preferredDate:Calendar.current.date(byAdding:.day,value:1,to:fixtureStart),title:marker,notes:marker)
            let creationBase=try await creationSession(creation).item
            var creationEdit=creationBase;creationEdit.sourceID=calendar.calendarIdentifier;creationEdit.recurrenceRules=[.init(frequency:"weekly",count:3)]
            let repeatOptions=String(data:try JSONSerialization.data(withJSONObject:["recurrence":[["frequency":"weekly","interval":1,"weekdays":[],"monthDays":[],"months":[],"yearWeeks":[],"yearDays":[],"positions":[],"endDate":NSNull(),"count":3]]]),encoding:.utf8)!
            _ = try await applyTool(.init(kind:.createEvent,destination:calendar.calendarIdentifier,title:marker,start:creationEdit.start.ISO8601Format(),end:creationEdit.end.ISO8601Format(),allDay:false,notes:marker,options:repeatOptions),reminder:nil,event:nil,marker:marker,allowedCalendars:[calendar.calendarIdentifier],allowedLists:[])
            stage = "cleanup"; try cleanup()
            return "PASS native editors: duplicate identity, notes, reminder/event edit Undo, date-only/timed/undated reminder, event title/location/time/all-day, single recurring occurrence, future-event edit/delete preserving earlier occurrence, forever recurrence, PA native adapter repeat creation/default weekday and future deletion, late-control refusal, reminder recurrence/priority/URL/alerts, stale-delete rejection, stale/external-change Undo refusal; fixtures removed and absence verified."
        } catch {
            do { try cleanup() } catch { throw ActionFailure.message("Native editor validation failed and fixture cleanup needs review. Only UUID-marked editor fixtures were touched.") }
            throw ActionFailure.message("Native editor check (" + stage + "): " + error.localizedDescription + (nativeCheckMismatch.map { " Compared fields: " + $0 + "." } ?? "") + " Fixtures removed.")
        }
    }
    #endif

}

extension NativeRecurrence {
    init(_ rule: EKRecurrenceRule) {
        self.init(frequency:["daily","weekly","monthly","yearly"][rule.frequency.rawValue],interval:rule.interval,weekdays:(rule.daysOfTheWeek ?? []).map { NativeRepeatDay(weekday:$0.dayOfTheWeek.rawValue,week:$0.weekNumber) },monthDays:(rule.daysOfTheMonth ?? []).map(\.intValue),months:(rule.monthsOfTheYear ?? []).map(\.intValue),yearWeeks:(rule.weeksOfTheYear ?? []).map(\.intValue),yearDays:(rule.daysOfTheYear ?? []).map(\.intValue),positions:(rule.setPositions ?? []).map(\.intValue),endDate:rule.recurrenceEnd?.endDate,count:rule.recurrenceEnd?.occurrenceCount ?? 0,calendarIdentifier:rule.calendarIdentifier,firstWeekday:rule.firstDayOfTheWeek)
    }
    func native() throws -> EKRecurrenceRule {
        try validate()
        guard calendarIdentifier == "gregorian" else { throw ActionFailure.message("This calendar system's repeat rule must be changed in Apple Calendar; it is preserved by other edits.") }
        let frequency: EKRecurrenceFrequency = ["daily":.daily,"weekly":.weekly,"monthly":.monthly,"yearly":.yearly][frequency]!
        let end = endDate.map { EKRecurrenceEnd(end:$0) } ?? (count > 0 ? EKRecurrenceEnd(occurrenceCount:count) : nil)
        func numbers(_ values: [Int]) -> [NSNumber]? { values.isEmpty ? nil : values.map { NSNumber(value:$0) } }
        return EKRecurrenceRule(recurrenceWith:frequency,interval:interval,daysOfTheWeek:weekdays.isEmpty ? nil : weekdays.map { EKRecurrenceDayOfWeek(EKWeekday(rawValue:$0.weekday)!,weekNumber:$0.week) },daysOfTheMonth:numbers(monthDays),monthsOfTheYear:numbers(months),weeksOfTheYear:numbers(yearWeeks),daysOfTheYear:numbers(yearDays),setPositions:numbers(positions),end:end)
    }
}
extension EventKitService {
    func applyExtendedFields(_ edited: NativeEditDetails, baseline: NativeEditDetails?, to item: EKCalendarItem) throws {
        if baseline == nil || edited.url != baseline?.url { item.url = edited.url.isEmpty ? nil : URL(string:edited.url) }
        if baseline == nil || edited.recurrenceRules != baseline?.recurrenceRules { item.recurrenceRules = try edited.recurrenceRules.map { try $0.native() } }
        if baseline == nil || edited.alarms != baseline?.alarms {
            // Preserve non-time alerts, including geofences, email and sound configuration.
            let preserved = (item.alarms ?? []).filter { $0.structuredLocation != nil || $0.emailAddress != nil || $0.soundName != nil || $0.type.rawValue != 0 }
            item.alarms = preserved + edited.alarms.map { $0.absolute.map { EKAlarm(absoluteDate:$0) } ?? EKAlarm(relativeOffset:$0.offset) }
        }
        if let reminder = item as? EKReminder, baseline == nil || edited.priority != baseline?.priority { reminder.priority = edited.priority }
        if let event = item as? EKEvent, baseline == nil || edited.availability != baseline?.availability {
            if let availability = EKEventAvailability(rawValue:edited.availability), availability != .notSupported {
                guard event.calendar.supportedEventAvailabilities.rawValue & (1 << edited.availability) != 0 else {throw ActionFailure.message("This calendar does not support the requested availability.")}
                event.availability = availability
            }
        }
    }
    func verifyExtendedFields(_ saved: NativeEditDetails, expected: NativeEditDetails, baseline: NativeEditDetails?) throws {
        func verify(_ matches:Bool,_ field:String) throws {if !matches {throw ActionFailure.message("The saved " + field + " could not be verified. Refresh before retrying.")}}
        try verify(saved.url == expected.url,"URL")
        try verify(saved.priority == expected.priority,"priority")
        if expected.kind == .event && !expected.allDay && (baseline == nil || expected.timeZoneID != baseline?.timeZoneID) {
            guard let requested=TimeZone(identifier:expected.timeZoneID),let actual=TimeZone(identifier:saved.timeZoneID) else {throw IntegrationError.verification}
            try verify(requested == actual || (requested as NSTimeZone).data == (actual as NSTimeZone).data,"time zone")
        }
        // All-day/date conversion can legitimately normalise the provider's default
        // alerts. Check an explicitly changed alert list, then retain fresh readback.
        if baseline == nil ? !expected.alarms.isEmpty : expected.alarms != baseline?.alarms {
            try verify(saved.alarms == expected.alarms,"time alerts")
        }
        if expected.availability != -1 { try verify(saved.availability == expected.availability,"availability") }
        // Native providers may fill in implicit BYDAY/BYMONTH and first-weekday values.
        if baseline == nil || expected.recurrenceRules != baseline?.recurrenceRules {
            let native = try expected.recurrenceRules.map { NativeRecurrence(try $0.native()) }
            try verify(saved.recurrenceRules == native,"repeat pattern")
        }
    }
    func deleteItem(baseline: NativeEditDetails, scope: NativeChangeScope, valid: NativeWriteValidity? = nil, claim:NativeWriteClaim? = nil) async throws -> String {
        var removalAttempted=false
        do {
            try NativeEditRules.validateDeletion(scope,baseline:baseline)
            try await access(baseline.kind == .event ? .event : .reminder)
            if let valid {guard await valid() else {throw ActionFailure.message("Account, source or assistant controls changed before deletion; nothing removed.")}}
            try Task.checkCancellation();store.reset()
            func currentItem()throws->EKCalendarItem {
                if baseline.kind == .event {return try editorEvent(baseline.occurrenceID,sourceID:baseline.sourceID,start:baseline.start,end:baseline.end)}
                guard let reminder=store.calendarItem(withIdentifier:baseline.itemID) as? EKReminder,!reminder.isCompleted else {throw IntegrationError.missing}
                return reminder
            }
            var native=try currentItem()
            guard editorDetails(native) == baseline else {throw IntegrationError.missing}
            if let claim {try await claim();try Task.checkCancellation()}
            // Claim/validity can suspend. Recheck ownership and every native field afterwards.
            if let valid {guard await valid() else {throw ActionFailure.message("Account, source or assistant controls changed before deletion; nothing removed.")}}
            try Task.checkCancellation();store.reset();native=try currentItem()
            guard editorDetails(native) == baseline else {throw IntegrationError.missing}
            if let event=native as? EKEvent {
                removalAttempted=true
                try store.remove(event,span:scope == .futureEvents ? .futureEvents : .thisEvent,commit:true)
                store.reset()
                guard let calendar=store.calendar(withIdentifier:baseline.sourceID) else {throw IntegrationError.verification}
                let end=scope == .futureEvents ? Calendar.current.date(byAdding:.year,value:4,to:baseline.start)! : baseline.end.addingTimeInterval(1)
                let remaining=store.events(matching:store.predicateForEvents(withStart:baseline.start.addingTimeInterval(-1),end:end,calendars:[calendar]))
                guard !remaining.contains(where:{candidate in
                    scope == .futureEvents ? candidate.calendarItemIdentifier == baseline.itemID && candidate.startDate >= baseline.start : DateRules.occurrenceID(candidate.eventIdentifier ?? candidate.calendarItemIdentifier,start:candidate.startDate) == baseline.occurrenceID
                }) else {throw IntegrationError.verification}
            } else if let reminder=native as? EKReminder {
                removalAttempted=true
                try store.remove(reminder,commit:true);store.reset()
                guard store.calendarItem(withIdentifier:baseline.itemID) == nil else {throw IntegrationError.verification}
            } else {throw IntegrationError.missing}
            return baseline.kind == .event ? (scope == .futureEvents ? "Deleted this and all future events: " : "Deleted event: ") + baseline.title : (baseline.recurring ? "Deleted repeating reminder: " : "Deleted reminder: ") + baseline.title
        } catch {
            store.reset()
            if !removalAttempted {throw NativePreSaveFailure(message:error.localizedDescription)}
            throw ActionFailure.message(error.localizedDescription + " Check Apple Calendar or Reminders before trying again; this removal will not be repeated automatically.")
        }
    }
}

#if DEBUG
struct CalendarDragFixture {
    var calendarID: String
    var marker: String
    var date: Date
}
extension EventKitService {
    func makeCalendarDragFixture() async throws -> CalendarDragFixture {
        try await access(.event); store.reset()
        guard let source=store.defaultCalendarForNewEvents?.source else { throw IntegrationError.readOnly }
        let marker="3PO drag validation " + UUID().uuidString
        let calendar=EKCalendar(for:.event,eventStore:store); calendar.title=marker; calendar.source=source
        try store.saveCalendar(calendar,commit:true)
        let day=Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:.now))!
        let fixture=CalendarDragFixture(calendarID:calendar.calendarIdentifier,marker:marker,date:day)
        do {
            for (title,hour,recurring) in [("Drag check",9,false),("Repeating drag check",11,true),("Overlap check",9,false)] {
                let event=EKEvent(eventStore:store); event.calendar=calendar; event.title=title; event.notes=marker
                event.startDate=Calendar.current.date(bySettingHour:hour,minute:title == "Overlap check" ? 30 : 0,second:0,of:day)!
                event.endDate=event.startDate.addingTimeInterval(3600); event.location="Disposable test room"
                if title != "Drag check" { event.timeZone = .current }; event.addAlarm(EKAlarm(relativeOffset:-600))
                if recurring { event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith:.daily,interval:1,end:EKRecurrenceEnd(occurrenceCount:3))) }
                try store.save(event,span:.thisEvent,commit:true)
            }
            return fixture
        } catch { try? removeCalendarDragFixture(fixture); throw error }
    }
    func calendarDragSnapshot(_ fixture: CalendarDragFixture,range: DateInterval) throws -> CalendarSnapshot {
        store.reset()
        guard let calendar=store.calendar(withIdentifier:fixture.calendarID),calendar.title == fixture.marker else { throw IntegrationError.missing }
        let events=store.events(matching:store.predicateForEvents(withStart:range.start,end:range.end,calendars:[calendar])).filter { $0.notes == fixture.marker }.map { event in
            AgendaEvent(id:DateRules.occurrenceID(event.eventIdentifier ?? event.calendarItemIdentifier,start:event.startDate),calendarID:calendar.calendarIdentifier,title:event.title,start:event.startDate,end:event.endDate,allDay:event.isAllDay,location:event.location ?? "",sourceLabel:"Disposable check",modified:event.lastModifiedDate,memoryItemID:event.calendarItemIdentifier)
        }
        return CalendarSnapshot(sources:[option(calendar)],events:events)
    }
    func removeCalendarDragFixture(_ fixture: CalendarDragFixture) throws {
        store.reset()
        guard let calendar=store.calendar(withIdentifier:fixture.calendarID),calendar.title == fixture.marker else { throw IntegrationError.missing }
        let range=DateInterval(start:fixture.date.addingTimeInterval(-86400),end:fixture.date.addingTimeInterval(5*86400))
        guard store.events(matching:store.predicateForEvents(withStart:range.start,end:range.end,calendars:[calendar])).allSatisfy({$0.notes == fixture.marker}) else { throw IntegrationError.verification }
        try store.removeCalendar(calendar,commit:true); store.reset()
        guard store.calendar(withIdentifier:fixture.calendarID) == nil else { throw IntegrationError.verification }
        try Data("PASS: disposable Calendar and its marked occurrences removed; absence verified.".utf8).write(to:URL(fileURLWithPath:"/tmp/missioncontrol-calendar-drag-cleanup.txt"),options:.atomic)
    }
    func calendarDragTimeZone(_ fixture: CalendarDragFixture,event: AgendaEvent) throws -> String? {
        store.reset()
        guard event.calendarID == fixture.calendarID else { throw IntegrationError.missing }
        let native=try editorEvent(event.id,sourceID:event.calendarID,start:event.start,end:event.end)
        guard native.notes == fixture.marker else { throw IntegrationError.missing }
        return native.timeZone?.identifier
    }
}
#endif
