import Foundation
import EventKit

extension EventKitService {
    func creationSession(_ request: NativeCreationRequest) async throws -> NativeEditSession {
        let type: EKEntityType = request.kind == .event ? .event : .reminder
        try await access(type); store.reset()
        let choices = store.calendars(for:type).filter { $0.allowsContentModifications }
        let toDo = choices.filter { $0.title == "To do" }
        let preferred = request.kind == .event ? store.defaultCalendarForNewEvents : (toDo.count == 1 ? toDo[0] : store.defaultCalendarForNewReminders())
        guard let destination = preferred, choices.contains(where:{ $0.calendarIdentifier == destination.calendarIdentifier }) else { throw IntegrationError.readOnly }
        let calendar = Calendar.current
        let date = request.preferredDate ?? .now
        let start = calendar.isDateInToday(date) ? calendar.nextDate(after:.now,matching:DateComponents(minute:0,second:0),matchingPolicy:.nextTime)! : calendar.date(bySettingHour:9,minute:0,second:0,of:date)!
        let item = NativeEditDetails(kind:request.kind,itemID:request.id.uuidString,occurrenceID:request.id.uuidString,sourceID:destination.calendarIdentifier,title:request.title,notes:request.notes,start:start,end:start.addingTimeInterval(3600),due:request.kind == .reminder ? request.preferredDate.map { calendar.startOfDay(for:$0) } : nil,writable:true)
        return NativeEditSession(item:item,sources:choices.map(option).sorted { $0.label < $1.label })
    }
    func createItem(request: NativeCreationRequest, baseline: NativeEditDetails, edited: NativeEditDetails, scope: String, valid: NativeWriteValidity? = nil) async throws -> NativeCreationReceipt {
        var saveAttempted = false
        do {
            try NativeCreationRules.validate(request:request,baseline:baseline,edited:edited)
            let type: EKEntityType = request.kind == .event ? .event : .reminder
            try await access(type)
            if let valid {guard await valid() else {throw ActionFailure.message("Account or assistant controls changed before creation; nothing created.")}}
            try Task.checkCancellation();store.reset()
            guard let destination = store.calendar(withIdentifier:edited.sourceID), destination.allowsContentModifications, destination.allowedEntityTypes.contains(request.kind == .event ? .event : .reminder) else { throw IntegrationError.readOnly }
            let identifier: String
            if request.kind == .event {
                let event = EKEvent(eventStore:store)
                event.calendar = destination; event.title = edited.title; event.notes = edited.notes.isEmpty ? nil : edited.notes
                event.location = edited.location.isEmpty ? nil : edited.location
                event.timeZone = TimeZone(identifier:edited.timeZoneID) ?? .current; event.isAllDay = edited.allDay
                event.startDate = edited.start; event.endDate = edited.allDay ? edited.end.addingTimeInterval(-1) : edited.end
                try applyExtendedFields(edited,baseline:nil,to:event)
                saveAttempted = true
                try store.save(event,span:.thisEvent,commit:true); identifier = event.calendarItemIdentifier
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--validate-clean-notes") { creationNotesCheckIDs.append(identifier) }
                #endif
                store.reset()
                guard let savedCalendar = store.calendar(withIdentifier:edited.sourceID) else { throw IntegrationError.verification }
                let matches = store.events(matching:store.predicateForEvents(withStart:edited.start.addingTimeInterval(-1),end:edited.end.addingTimeInterval(1),calendars:[savedCalendar])).filter { $0.calendarItemIdentifier == identifier && $0.startDate == edited.start }
                guard matches.count == 1, let saved = matches.first else { throw IntegrationError.verification }
                let value = editorDetails(saved)
                try verifyExtendedFields(value,expected:edited,baseline:nil)
                guard value.title == edited.title, value.notes == edited.notes, value.location == edited.location, value.end == edited.end, value.allDay == edited.allDay, value.sourceID == edited.sourceID else { throw IntegrationError.verification }
            } else {
                let reminder = EKReminder(eventStore:store)
                reminder.calendar = destination; reminder.title = edited.title; reminder.notes = edited.notes.isEmpty ? nil : edited.notes
                var calendar = Calendar.current; calendar.timeZone = TimeZone(identifier:edited.timeZoneID) ?? .current
                reminder.dueDateComponents = edited.due.map { calendar.dateComponents(edited.hasTime ? [.year,.month,.day,.hour,.minute,.second,.timeZone] : [.year,.month,.day],from:$0) }
                try applyExtendedFields(edited,baseline:nil,to:reminder)
                saveAttempted = true
                try store.save(reminder,commit:true); identifier = reminder.calendarItemIdentifier
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--validate-clean-notes") { creationNotesCheckIDs.append(identifier) }
                #endif
                store.reset()
                guard let saved = store.calendarItem(withIdentifier:identifier) as? EKReminder, !saved.isCompleted else { throw IntegrationError.verification }
                let value = editorDetails(saved)
                try verifyExtendedFields(value,expected:edited,baseline:nil)
                guard value.title == edited.title, value.notes == edited.notes, value.sourceID == edited.sourceID, value.hasTime == edited.hasTime else { throw IntegrationError.verification }
                if edited.hasTime { guard value.due == edited.due else { throw IntegrationError.verification } }
                else { guard value.due.map({ DateRules.localDate($0) }) == edited.due.map({ DateRules.localDate($0) }) else { throw IntegrationError.verification } }
            }
            return NativeCreationReceipt(requestID:request.id,registration:request.registration,kind:request.kind,itemID:identifier,title:edited.title,destination:option(destination).label,created:.now,sourceScope:scope)
        } catch {
            store.reset()
            if !saveAttempted { throw NativePreSaveFailure(message: error.localizedDescription) }
            throw error
        }
    }
}
