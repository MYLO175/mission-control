import Foundation
import EventKit
import AppKit

actor EventKitService: NativeSourceReading {
    #if DEBUG
    var nativeCheckMismatch: String?
    var creationNotesCheckIDs: [String] = []
    #endif
    let store = EKEventStore()
    private struct CompletionRecord {
        let originalID: String
        let originalDue: DateComponents?
        let saved: NativeCompletionSnapshot
        let detached: NativeCompletionSnapshot?
    }
    private var undoItems: [String: CompletionRecord] = [:]
    private func fetchedReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await NativeSourceRead.fetchCancellableSnapshot(source: "Reminders", fetch: { completion in
            let token = store.fetchReminders(matching: predicate, completion: completion)
            return { Task { self.cancelReminderFetch(token) } }
        })
    }
    private func cancelReminderFetch(_ token: Any) {
        store.cancelFetchRequest(token)
    }
    private func completionSnapshot(_ reminder: EKReminder) -> NativeCompletionSnapshot {
        .init(details: editorDetails(reminder), dueComponents: reminder.dueDateComponents,
              completed: reminder.isCompleted, completionDate: reminder.completionDate)
    }
    private func allReminders(in calendar: EKCalendar) async throws -> [EKReminder] {
        try await fetchedReminders(matching: store.predicateForReminders(in: [calendar]))
    }
    func access(_ type: EKEntityType) async throws {
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess { return }
        if status == .denied || status == .restricted { throw IntegrationError.denied(type == .event ? "Calendar" : "Reminders") }
        let granted = type == .event ? try await store.requestFullAccessToEvents() : try await store.requestFullAccessToReminders()
        if !granted { throw IntegrationError.denied(type == .event ? "Calendar" : "Reminders") }
    }
    func option(_ calendar: EKCalendar) -> SourceOption {
        let color: SourceRGB?
        if let sRGB = NSColor(cgColor: calendar.cgColor)?.usingColorSpace(.sRGB) {
            color = SourceRGB(red: Double(sRGB.redComponent), green: Double(sRGB.greenComponent), blue: Double(sRGB.blueComponent))
        } else {
            color = nil
        }
        return .init(id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source.title, writable: calendar.allowsContentModifications, color: color, providerID:calendar.source.sourceIdentifier)
    }
    func calendar(from start: Date, to end: Date) async throws -> CalendarSnapshot {
        try await access(.event)
        let calendars = store.calendars(for: .event)
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars)).map { event in
            let memoryID:String?
            if event.hasRecurrenceRules || event.isDetached {
                if let external=event.calendarItemExternalIdentifier,!external.isEmpty,let original=event.occurrenceDate { memoryID=DateRules.occurrenceID(external,start:original) }
                else { memoryID=nil }
            } else { memoryID=event.calendarItemIdentifier }
            return AgendaEvent(id: DateRules.occurrenceID(event.eventIdentifier ?? event.calendarItemIdentifier, start: event.startDate), calendarID: event.calendar.calendarIdentifier, title: event.title ?? "Untitled event", start: event.startDate, end: event.endDate, allDay: event.isAllDay, location: event.location ?? "", sourceLabel: option(event.calendar).label, modified:event.lastModifiedDate,memoryItemID:memoryID)
        }.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
        return .init(sources: calendars.map(option).sorted { $0.label < $1.label }, events: events)
    }
    func reminders() async throws -> ReminderSnapshot {
        try await access(.reminder)
        let calendars = store.calendars(for: .reminder)
        let items = try await fetchedReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars))
        let reminders = items.map { item in
            let components = item.dueDateComponents
            var calendar = components?.calendar ?? Calendar.current
            calendar.timeZone = components?.timeZone ?? .current
            let due = components.flatMap { calendar.date(from: $0) }
            return TaskItem(id: item.calendarItemIdentifier, listID: item.calendar.calendarIdentifier, title: item.title ?? "Untitled reminder", due: due, hasTime: components?.hour != nil, sourceLabel: option(item.calendar).label, writable: item.calendar.allowsContentModifications, recurring: item.hasRecurrenceRules, modified:item.lastModifiedDate)
        }
        return .init(sources: calendars.map(option).sorted { $0.label < $1.label }, reminders: DateRules.ordered(reminders))
    }
    /// Recent completion evidence under existing access; never request background permission.
    func completedReminders(excluded:Set<String>,now:Date = .now) async throws->[CompletedReminder] {
        guard EKEventStore.authorizationStatus(for:.reminder) == .fullAccess else {throw IntegrationError.denied("Reminders")}
        let calendars=store.calendars(for:.reminder).filter{!excluded.contains($0.calendarIdentifier)}
        guard !calendars.isEmpty else {return []}
        let predicate=store.predicateForCompletedReminders(withCompletionDateStarting:now.addingTimeInterval(-30*86400),ending:now,calendars:calendars)
        let items = try await fetchedReminders(matching: predicate)
        return Array(items.filter{$0.isCompleted && $0.completionDate != nil}.sorted{($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast)}.prefix(80)).compactMap { item in
            guard let completed=item.completionDate else {return nil}
            let components=item.dueDateComponents
            var calendar=components?.calendar ?? Calendar.current;calendar.timeZone=components?.timeZone ?? .current
            let value=TaskItem(id:item.calendarItemIdentifier,listID:item.calendar.calendarIdentifier,title:item.title ?? "Untitled reminder",due:components.flatMap{calendar.date(from:$0)},hasTime:components?.hour != nil,sourceLabel:option(item.calendar).label,writable:item.calendar.allowsContentModifications,recurring:item.hasRecurrenceRules,modified:item.lastModifiedDate)
            return .init(item:value,completedAt:completed)
        }
    }
    func complete(id: String, valid: NativeWriteValidity? = nil, expected: NativeEditDetails? = nil) async throws -> String {
        var saveAttempted = false
        do {
            try await access(.reminder)
            guard let item = store.calendarItem(withIdentifier: id) as? EKReminder, !item.isCompleted else { throw IntegrationError.missing }
            guard item.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
            let baseline = expected ?? editorDetails(item)
            guard editorDetails(item) == baseline else { throw IntegrationError.missing }
            let originalDue = item.dueDateComponents
            let title = item.title
            let notes = item.notes
            let calendar = item.calendar!
            let wasRecurring = item.hasRecurrenceRules
            let priorIDs = wasRecurring ? Set(try await allReminders(in: calendar).map(\.calendarItemIdentifier)) : []
            if let valid {guard await valid() else {throw ActionFailure.message("Account, source or assistant controls changed before completion; nothing completed.")}}
            try Task.checkCancellation()
            // Permission/recurrence reads and the main-actor ownership callback can
            // yield. Re-fetch and compare the complete captured record after all of
            // them; never complete a newly edited occurrence under an old approval.
            store.reset()
            guard let current = store.calendarItem(withIdentifier:id) as? EKReminder,
                  !current.isCompleted, editorDetails(current) == baseline else { throw IntegrationError.missing }
            guard current.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
            let saveStarted = Date.now
            current.isCompleted = true
            saveAttempted = true
            do { try store.save(current, commit: true) } catch { store.reset(); throw error }
            store.reset()
            guard let saved = store.calendarItem(withIdentifier: id) as? EKReminder else { throw IntegrationError.verification }
            let savedSnapshot = completionSnapshot(saved)
            var detached: NativeCompletionSnapshot?
            if !saved.isCompleted {
                // EventKit advances the original series and creates a detached completed occurrence.
                guard wasRecurring, saved.dueDateComponents != originalDue else { throw IntegrationError.verification }
                let after: [EKReminder]
                do { after = try await allReminders(in: saved.calendar) }
                catch { throw IntegrationError.verification }
                let candidates = after.filter {
                    !priorIDs.contains($0.calendarItemIdentifier) && $0.isCompleted &&
                    $0.dueDateComponents == originalDue && $0.title == title && $0.notes == notes &&
                    ($0.completionDate ?? .distantPast) >= saveStarted.addingTimeInterval(-2)
                }
                guard candidates.count == 1 else { throw IntegrationError.verification }
                detached = completionSnapshot(candidates[0])
                guard let unchanged = store.calendarItem(withIdentifier: id) as? EKReminder,
                      completionSnapshot(unchanged) == savedSnapshot else { throw IntegrationError.verification }
            }
            let token = UUID().uuidString
            undoItems = [token: CompletionRecord(originalID: id, originalDue: originalDue, saved: savedSnapshot, detached: detached)]
            return token
        } catch {
            store.reset()
            if !saveAttempted { throw NativePreSaveFailure(message: error.localizedDescription) }
            throw error
        }
    }
    func undo(token: String) async throws {
        store.reset()
        guard let record = undoItems[token], let item = store.calendarItem(withIdentifier: record.originalID) as? EKReminder else { throw IntegrationError.missing }
        guard item.calendar.allowsContentModifications else { throw IntegrationError.readOnly }
        let detached = record.detached.flatMap { store.calendarItem(withIdentifier: $0.details.itemID) as? EKReminder }
        try NativeCompletionRules.validateUndo(saved: record.saved, current: completionSnapshot(item),
                                              detached: record.detached, currentDetached: detached.map(completionSnapshot))
        if let detachedID = record.detached?.details.itemID {
            guard !item.isCompleted, item.dueDateComponents == record.saved.dueComponents,
                  let detached, detached.isCompleted,
                  detached.dueDateComponents == record.originalDue,
                  detached.calendar.calendarIdentifier == item.calendar.calendarIdentifier else { throw IntegrationError.missing }
            item.dueDateComponents = record.originalDue
            item.isCompleted = false
            do {
                try store.save(item, commit: false)
                try store.remove(detached, commit: false)
                try store.commit()
            } catch { store.reset(); throw error }
            guard let restored = store.calendarItem(withIdentifier: record.originalID) as? EKReminder,
                  !restored.isCompleted, restored.dueDateComponents == record.originalDue,
                  store.calendarItem(withIdentifier: detachedID) == nil else { throw IntegrationError.verification }
        } else {
            guard item.isCompleted else { throw IntegrationError.missing }
            item.isCompleted = false
            do { try store.save(item, commit: true) } catch { store.reset(); throw error }
            guard let restored = store.calendarItem(withIdentifier: record.originalID) as? EKReminder, !restored.isCompleted else { throw IntegrationError.verification }
        }
        undoItems.removeValue(forKey: token)
    }
    // Developer-only acceptance check, invoked by an explicit launch argument.
    // Every write and cleanup is restricted to freshly created UUID-marked items.
    func validateDisposableReminders() async throws -> String {
        try await access(.reminder)
        guard let destination = store.calendars(for: .reminder).first(where: { $0.title == "To do" && $0.allowsContentModifications }) ?? store.defaultCalendarForNewReminders(), destination.allowsContentModifications else { throw IntegrationError.readOnly }
        let marker = "Mission Control validation " + UUID().uuidString
        var created: [EKReminder] = []
        func create(recurring: Bool) throws -> EKReminder {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = destination
            reminder.title = marker + (recurring ? " recurring" : " duplicate")
            reminder.notes = marker
            if recurring {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 3)))
            }
            try store.save(reminder, commit: true)
            created.append(reminder)
            return reminder
        }
        var result = ""
        do {
            let first = try create(recurring: false)
            let second = try create(recurring: false)
            let firstID = first.calendarItemIdentifier
            let secondID = second.calendarItemIdentifier
            let token = try await complete(id: firstID)
            guard (store.calendarItem(withIdentifier: secondID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            try await undo(token: token)
            guard (store.calendarItem(withIdentifier: firstID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            result = "PASS duplicate-title completion and Undo; "
            let recurring = try create(recurring: true)
            let recurringID = recurring.calendarItemIdentifier
            let beforeExternal = recurring.calendarItemExternalIdentifier
            let beforeDue = recurring.dueDateComponents
            let recurringToken: String
            do { recurringToken = try await complete(id: recurringID) }
            catch {
                do {
                    let diagnostic = try await allReminders(in: destination)
                    let matching = diagnostic.filter { $0.notes == marker && $0.title.hasSuffix(" recurring") }
                    result += "Recurring metadata: " + matching.map { item in
                        "originalID=\(item.calendarItemIdentifier == recurringID), sameExternal=\(item.calendarItemExternalIdentifier == beforeExternal), completed=\(item.isCompleted), sameDue=\(item.dueDateComponents == beforeDue)"
                    }.joined(separator: " | ") + "; "
                } catch { result += "Recurring metadata unavailable: " + error.localizedDescription + "; " }
                throw error
            }
            try await undo(token: recurringToken)
            guard (store.calendarItem(withIdentifier: recurringID) as? EKReminder)?.isCompleted == false else { throw IntegrationError.verification }
            let recurrenceRows = try await allReminders(in: destination).filter { $0.notes == marker && $0.title.hasSuffix(" recurring") }
            guard recurrenceRows.count == 1, !recurrenceRows[0].isCompleted, recurrenceRows[0].dueDateComponents == beforeDue else { throw IntegrationError.verification }
            result += "PASS recurring completion and Undo (one restored occurrence, no duplicate)."
        } catch { result += "FAIL: " + error.localizedDescription }
        var cleanupErrors = 0
        do {
            let all = try await allReminders(in: destination)
            for item in all where item.notes == marker {
                do { try store.remove(item, commit: true) } catch { cleanupErrors += 1 }
            }
        } catch { cleanupErrors += 1 }
        // Freshly saved objects may precede EventKit's async fetch snapshot.
        for item in created {
            if let remaining = store.calendarItem(withIdentifier: item.calendarItemIdentifier) as? EKReminder, remaining.notes == marker {
                do { try store.remove(remaining, commit: true) } catch { cleanupErrors += 1 }
            }
        }
        return result + (cleanupErrors == 0 ? " Disposable items cleaned up." : " Cleanup failures: \(cleanupErrors). Remove only Mission Control validation items in Reminders.")
    }

    func validateDisposableCalendarEvents() async throws -> String {
        try await access(.event)
        guard let destination = store.defaultCalendarForNewEvents, destination.allowsContentModifications else { throw IntegrationError.readOnly }
        let marker = "Mission Control calendar validation " + UUID().uuidString
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        var created: [EKEvent] = []
        func create(_ kind: String, start: Date, end: Date, allDay: Bool = false, recurring: Bool = false) throws {
            let event = EKEvent(eventStore: store)
            event.calendar = destination; event.title = marker + " " + kind; event.notes = marker
            // Use UTC for a fold-hour fixture: EventKit otherwise converts
            // the two equal local clock times into a zero-duration event.
            event.timeZone = kind == "DST" ? TimeZone(secondsFromGMT: 0)! : calendar.timeZone
            event.startDate = start; event.endDate = end
            event.isAllDay = allDay
            if recurring { event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 2))) }
            try store.save(event, span: .thisEvent, commit: true)
            created.append(event)
        }
        var result = ""
        do {
            try create("timed", start: day.addingTimeInterval(9*3600), end: day.addingTimeInterval(10*3600))
            try create("all-day", start: day, end: nextDay, allDay: true)
            try create("overnight", start: calendar.date(bySettingHour: 23, minute: 30, second: 0, of: day)!, end: calendar.date(bySettingHour: 1, minute: 0, second: 0, of: nextDay)!)
            try create("recurring", start: day.addingTimeInterval(13*3600), end: day.addingTimeInterval(13*3600+1800), recurring: true)
            let end = calendar.date(byAdding: .day, value: 3, to: day)!
            let snapshot = try await self.calendar(from: day, to: end)
            let fixtures = snapshot.events.filter { $0.calendarID == destination.calendarIdentifier && $0.title.hasPrefix(marker) }
            guard fixtures.count == 5, Set(fixtures.map(\.id)).count == 5,
                  fixtures.filter(\.allDay).count == 1,
                  fixtures.filter({ DateRules.overlaps($0, day: nextDay) }).count == 2 else { throw NSError(domain: "CalendarCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "counts total=\(fixtures.count), unique=\(Set(fixtures.map(\.id)).count), allDay=\(fixtures.filter(\.allDay).count), nextDay=\(fixtures.filter({ DateRules.overlaps($0, day: nextDay) }).count)"]) }
            for original in created where !original.hasRecurrenceRules {
                guard fixtures.contains(where: { $0.id == DateRules.occurrenceID(original.eventIdentifier, start: original.startDate) && $0.start == original.startDate && $0.end == original.endDate && $0.allDay == original.isAllDay }) else { throw NSError(domain: "CalendarCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Original timed/all-day/overnight round-trip mismatch"]) }
            }
            var daylightResult = ""
            if let transition = calendar.timeZone.nextDaylightSavingTimeTransition(after: day) {
                let exactTransition = Date(timeIntervalSince1970: transition.timeIntervalSince1970.rounded())
                let start = exactTransition.addingTimeInterval(-1800), finish = exactTransition.addingTimeInterval(1800)
                try create("DST", start: start, end: finish)
                let dstEvent = created.last!
                let dstSnapshot = try await self.calendar(from: start.addingTimeInterval(-3600), to: finish.addingTimeInterval(3600))
                guard dstSnapshot.events.contains(where: { $0.id == DateRules.occurrenceID(dstEvent.eventIdentifier, start: start) && $0.start == start && $0.end == finish && $0.end.timeIntervalSince($0.start) == 3600 }) else { throw NSError(domain: "CalendarCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "DST round-trip mismatch: saved start delta=\(dstEvent.startDate.timeIntervalSince(start)), end delta=\(dstEvent.endDate.timeIntervalSince(finish)), read count=\(dstSnapshot.events.filter { $0.title.hasPrefix(marker) }.count), read metadata=\(dstSnapshot.events.filter { $0.title.hasPrefix(marker) }.map { "start delta=\($0.start.timeIntervalSince(start)), end delta=\($0.end.timeIntervalSince(finish)), duration=\($0.end.timeIntervalSince($0.start)), sameID=\($0.id == DateRules.occurrenceID(dstEvent.eventIdentifier, start: start))" }.joined(separator: "; "))"]) }
                daylightResult = " DST UTC round-trip passed."
            }
            result = "PASS actual EventKit timed/all-day/overnight/recurring reads and distinct occurrence IDs." + daylightResult
        } catch { result = "FAIL Calendar fixture check: " + error.localizedDescription }
        var cleanupFailures = 0
        for original in created {
            guard let id = original.eventIdentifier else { cleanupFailures += 1; continue }
            if let item = store.event(withIdentifier: id), item.notes == marker, item.calendar.calendarIdentifier == destination.calendarIdentifier {
                do { try store.remove(item, span: item.hasRecurrenceRules ? .futureEvents : .thisEvent, commit: true) }
                catch { cleanupFailures += 1 }
            }
        }
        let cleanupEnd = max(calendar.date(byAdding: .day, value: 3, to: day)!, created.map(\.endDate).max() ?? day)
        let leftovers = store.events(matching: store.predicateForEvents(withStart: day, end: cleanupEnd.addingTimeInterval(1), calendars: [destination])).filter { $0.notes == marker }
        return result + (cleanupFailures == 0 && leftovers.isEmpty ? " Disposable events cleaned up." : " Cleanup incomplete: remove only UUID-marked Mission Control calendar validation events.")
    }

}
