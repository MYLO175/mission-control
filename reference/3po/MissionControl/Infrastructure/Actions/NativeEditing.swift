import Foundation

typealias NativeWriteValidity = @MainActor @Sendable () -> Bool
typealias NativeWriteClaim = @MainActor @Sendable () async throws -> Void
struct NativePreSaveFailure:LocalizedError { var message:String;var errorDescription:String? {message} }

enum NativeItemKind: String, Codable { case event, reminder }
enum NativeEditTarget: Identifiable {
    case event(AgendaEvent), reminder(TaskItem)
    case create(NativeCreationRequest)
    case reviewEvent(AgendaEvent,NativeDateReview), reviewReminder(TaskItem,NativeDateReview)
    var id: String { switch self { case .event(let value): return "event:" + value.id; case .reminder(let value): return "reminder:" + value.id; case .create(let request): return "create:" + request.id.uuidString;case .reviewEvent(_,let review),.reviewReminder(_,let review): return "review:"+review.discoveryID } }
}
struct NativeDateReview {
    var discoveryID:String
    var registration:String
    var date:Date
    var hasTime:Bool
    var expectedModified:Date?
    var evidence:String
    var discoveryApproval:Data? = nil
    var expectedOccurrenceID:String? = nil
    var expectedSourceID:String? = nil
    var expectedTitle:String? = nil
    var expectedStart:Date? = nil
    var expectedEnd:Date? = nil
    var expectedDue:Date? = nil
    var expectedHasTime:Bool? = nil
    func applying(to item:NativeEditDetails) throws -> NativeEditDetails {
        guard item.modified == expectedModified,
              expectedOccurrenceID.map({$0 == item.occurrenceID}) ?? true,
              expectedSourceID.map({$0 == item.sourceID}) ?? true,
              expectedTitle.map({$0 == item.title}) ?? true,
              expectedStart.map({$0 == item.start}) ?? true,
              expectedEnd.map({$0 == item.end}) ?? true,
              expectedHasTime.map({$0 == (item.kind == .event ? !item.allDay : item.hasTime)}) ?? true,
              expectedOccurrenceID == nil || item.kind == .event || item.due == expectedDue else { throw ActionFailure.message("The Apple item changed. Check for a fresh proposal before approving it.") }
        guard date.timeIntervalSinceReferenceDate.isFinite else { throw ActionFailure.message("The proposed date is invalid.") }
        var edited=item
        if item.kind == .event {
            guard hasTime == !item.allDay else { throw ActionFailure.message("The proposal changes the event's time format; review it again.") }
            edited=NativeEditRules.movingStart(item,to:date)
        } else { edited.due=date;edited.hasTime=hasTime }
        try NativeEditRules.validate(edited,baseline:item)
        return edited
    }
}
struct NativeEditDetails: Codable, Equatable {
    var kind: NativeItemKind
    var itemID: String
    var occurrenceID: String
    var sourceID: String
    var title: String
    var notes: String
    var location: String = ""
    var start: Date = .distantPast
    var end: Date = .distantPast
    var allDay = false
    var due: Date?
    var hasTime = false
    var timeZoneID: String = TimeZone.current.identifier
    var recurring = false
    var writable = false
    var modified: Date?
    var recurrenceRules: [NativeRecurrence] = []
    var alarms: [NativeTimeAlarm] = []
    var otherAlarmSignatures: [String] = []
    var url = ""
    var priority: Int = 0
    var availability: Int = -1
    var canEdit: Bool { writable }
}
struct NativeEditSession { var item: NativeEditDetails; var sources: [SourceOption] }
struct NativeEditUndo {
    var original: NativeEditDetails
    var saved: NativeEditDetails
    var created = Date.now
}
struct NativeCompletionSnapshot: Equatable {
    var details: NativeEditDetails
    var dueComponents: DateComponents?
    var completed: Bool
    var completionDate: Date?
}
enum NativeCompletionRules {
    static func validateDisplayed(_ expected: TaskItem, details: NativeEditDetails) throws {
        guard details.kind == .reminder, details.itemID == expected.id,
              details.sourceID == expected.listID,
              (details.title.isEmpty ? "Untitled reminder" : details.title) == expected.title,
              details.due == expected.due, details.hasTime == expected.hasTime,
              details.recurring == expected.recurring, details.modified == expected.modified,
              details.writable == expected.writable else { throw IntegrationError.missing }
    }
    static func validateUndo(saved: NativeCompletionSnapshot, current: NativeCompletionSnapshot,
                             detached: NativeCompletionSnapshot?, currentDetached: NativeCompletionSnapshot?) throws {
        guard saved == current, detached == currentDetached else { throw IntegrationError.missing }
    }
}
struct NativeEventMoveProposal {
    var occurrenceID: String
    var sourceID: String
    var originalStart: Date
    var originalEnd: Date
    var start: Date
}
enum NativeEditRules {
    static func restoring(_ undo: NativeEditUndo) throws -> NativeEditDetails {
        guard undo.original.kind == undo.saved.kind else { throw IntegrationError.missing }
        var restored = undo.original
        restored.itemID = undo.saved.itemID; restored.occurrenceID = undo.saved.occurrenceID
        restored.modified = undo.saved.modified
        // EventKit detaches a single moved occurrence from its series. The
        // supported receipt never changed repeat rules; restoring the old
        // series rule here would create repetition or be refused by Apple.
        if restored.kind == .event, restored.recurring, restored.recurrenceRules != undo.saved.recurrenceRules {
            restored.recurring=undo.saved.recurring; restored.recurrenceRules=undo.saved.recurrenceRules
        }
        try validate(restored,baseline:undo.saved); return restored
    }
    static func movingStart(_ item: NativeEditDetails, to start: Date, calendar: Calendar = .current) -> NativeEditDetails {
        var value = item
        if item.allDay {
            let days = max(1,calendar.dateComponents([.day],from:calendar.startOfDay(for:item.start),to:calendar.startOfDay(for:item.end)).day ?? 1)
            value.start = calendar.startOfDay(for:start)
            value.end = calendar.date(byAdding:.day,value:days,to:value.start)!
        } else {
            value.start = start; value.end = start.addingTimeInterval(item.end.timeIntervalSince(item.start))
        }
        return value
    }
    static func moved(_ baseline: NativeEditDetails, proposal: NativeEventMoveProposal) throws -> NativeEditDetails {
        guard baseline.kind == .event, !baseline.allDay, baseline.canEdit,
              baseline.occurrenceID == proposal.occurrenceID, baseline.sourceID == proposal.sourceID,
              baseline.start == proposal.originalStart, baseline.end == proposal.originalEnd else { throw IntegrationError.missing }
        let edited = movingStart(baseline,to:proposal.start)
        try validate(edited,baseline:baseline); return edited
    }
    static func validate(_ value: NativeEditDetails, baseline: NativeEditDetails) throws {
        guard baseline.canEdit else { throw IntegrationError.readOnly }
        guard value.itemID == baseline.itemID, value.kind == baseline.kind, value.occurrenceID == baseline.occurrenceID else { throw IntegrationError.missing }
        guard !value.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, value.title.count <= 500,
              value.notes.count <= 50_000, value.location.count <= 2000 else { throw ActionFailure.message("Enter a title of up to 500 characters, location up to 2,000 and notes up to 50,000.") }
        guard value.recurrenceRules.count <= 8, value.alarms.count <= 8, (0...9).contains(value.priority), [-1,0,1,2,3].contains(value.availability), value.alarms.allSatisfy({ $0.offset.isFinite && abs($0.offset) <= 366 * 86400 }) else { throw ActionFailure.message("Invalid repeat, priority, availability or alert options.") }
        if value.recurrenceRules != baseline.recurrenceRules {
            for rule in value.recurrenceRules {
                try rule.validate()
                let anchor=value.kind == .event ? value.start : value.due
                if let end=rule.endDate,let anchor,end < anchor {throw ActionFailure.message("The last repeat date must not precede the event start or reminder due date.")}
            }
        }
        if value.url != baseline.url && !value.url.isEmpty { guard let url = URL(string:value.url), ["https","http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw ActionFailure.message("Enter a valid http or https URL.") } }
        if value.kind == .reminder && !value.recurrenceRules.isEmpty && value.due == nil { throw ActionFailure.message("Repeating reminders need a due date.") }
        if value.kind == .event {
            guard value.end > value.start, value.end.timeIntervalSince(value.start) <= 366 * 86400 else { throw ActionFailure.message("The event must end after it starts and last no more than a year.") }
            if value.allDay { guard Calendar.current.startOfDay(for:value.start) == value.start, Calendar.current.startOfDay(for:value.end) == value.end else { throw ActionFailure.message("All-day events use whole calendar days.") } }

        } else if value.due == nil && value.hasTime { throw ActionFailure.message("Choose a due date before adding a time.") }
    }
    static func allDay(_ item: NativeEditDetails, enabled: Bool, calendar: Calendar = .current) -> NativeEditDetails {
        guard item.allDay != enabled else { return item }
        var result = item; result.allDay = enabled
        if enabled {
            result.start = calendar.startOfDay(for:item.start)
            let endDay = calendar.startOfDay(for:item.end)
            let firstExclusive = calendar.date(byAdding:.day,value:1,to:result.start)!
            result.end = item.end == endDay ? max(firstExclusive,endDay) : calendar.date(byAdding:.day,value:1,to:max(result.start,endDay))!
        } else {
            result.start = calendar.date(bySettingHour:9,minute:0,second:0,of:item.start)!
            result.end = result.start.addingTimeInterval(3600)
        }
        result.timeZoneID = calendar.timeZone.identifier; return result
    }
}

struct NativeRepeatDay: Codable, Equatable {
    var weekday: Int
    var week: Int = 0
}
struct NativeRecurrence: Codable, Equatable {
    var frequency: String = "weekly"
    var interval: Int = 1
    var weekdays: [NativeRepeatDay] = []
    var monthDays: [Int] = []
    var months: [Int] = []
    var yearWeeks: [Int] = []
    var yearDays: [Int] = []
    var positions: [Int] = []
    var endDate: Date?
    var count: Int = 0
    var calendarIdentifier: String = "gregorian"
    var firstWeekday: Int = 0
    var summary: String {
        let unit = ["daily":"day","weekly":"week","monthly":"month","yearly":"year"][frequency] ?? frequency
        return "Every \(interval) \(unit)\(interval == 1 ? "" : "s")" + (count > 0 ? " · \(count) occurrences" : endDate.map { " · until " + DateRules.localDate($0) } ?? " · forever")
    }
    func validate() throws {
        func valid(_ values: [Int], max: Int, negative: Bool = true) -> Bool { values.count <= 366 && Set(values).count == values.count && values.allSatisfy { $0 != 0 && $0 <= max && $0 >= (negative ? -max : 1) } }
        guard ["daily","weekly","monthly","yearly"].contains(frequency), (1...999).contains(interval), count >= 0, count <= 100_000, count == 0 || endDate == nil,
              weekdays.count <= 53, Set(weekdays.map { "\($0.weekday):\($0.week)" }).count == weekdays.count,
              weekdays.allSatisfy({ (1...7).contains($0.weekday) && (-53...53).contains($0.week) }),
              valid(monthDays,max:31), valid(months,max:12,negative:false), valid(yearWeeks,max:53), valid(yearDays,max:366), valid(positions,max:366) else { throw ActionFailure.message("The repeat pattern contains an invalid interval, day or end condition.") }
        guard frequency != "daily" || weekdays.isEmpty,
              frequency != "weekly" || weekdays.allSatisfy({ $0.week == 0 }),
              monthDays.isEmpty || frequency == "monthly", months.isEmpty || frequency == "yearly",
              yearWeeks.isEmpty && yearDays.isEmpty || frequency == "yearly",
              positions.isEmpty || !(weekdays.isEmpty && monthDays.isEmpty && months.isEmpty && yearWeeks.isEmpty && yearDays.isEmpty) else { throw ActionFailure.message("These repeat options do not apply to the selected frequency.") }
    }
}
enum NativeChangeScope: String, CaseIterable { case occurrence, futureEvents, reminderSeries }
struct NativeTimeAlarm: Codable, Equatable {
    var absolute: Date?
    var offset: Double = 0
}

extension NativeEditRules {
    static func validateScope(_ scope: NativeChangeScope, baseline: NativeEditDetails, edited: NativeEditDetails) throws {
        if edited.recurrenceRules != baseline.recurrenceRules && !edited.recurrenceRules.isEmpty && baseline.recurrenceRules.contains(where:{$0.calendarIdentifier != "gregorian"}) {
            throw ActionFailure.message("Change this calendar system's repeat pattern in Apple Calendar or Reminders. Other details, removing repetition and native deletion remain available.")
        }
        if baseline.kind == .event {
            guard scope != .reminderSeries, baseline.recurring || scope == .occurrence else { throw ActionFailure.message("Future-event scope requires a repeating event.") }
            if baseline.recurring && edited.sourceID != baseline.sourceID && scope != .futureEvents { throw ActionFailure.message("Moving a repeating event to another calendar applies to this and future events.") }
            if baseline.recurring && edited.recurrenceRules != baseline.recurrenceRules && scope != .futureEvents { throw ActionFailure.message("Changing repeat rules applies to this and future events; choose that scope.") }
        } else {
            guard baseline.recurring ? scope == .reminderSeries : scope == .occurrence else { throw ActionFailure.message("A repeating reminder is one native series; choose repeating-reminder scope.") }
        }
    }
    static func validateDeletion(_ scope: NativeChangeScope, baseline: NativeEditDetails) throws {
        guard baseline.writable else { throw IntegrationError.readOnly }
        try validateScope(scope,baseline:baseline,edited:baseline)
    }
    static func supportsUndo(baseline: NativeEditDetails, edited: NativeEditDetails, scope: NativeChangeScope) -> Bool {
        !baseline.recurring && edited.recurrenceRules.isEmpty && scope == .occurrence || baseline.kind == .event && scope == .occurrence && baseline.recurrenceRules == edited.recurrenceRules
    }
}

#if DEBUG
extension NativeEditRules {
    static func differingFields(_ a:NativeEditDetails,_ b:NativeEditDetails) -> [String] {
        [("identity",a.itemID == b.itemID && a.occurrenceID == b.occurrenceID),("source",a.sourceID == b.sourceID),("title",a.title == b.title),("notes",a.notes == b.notes),("location",a.location == b.location),("dates",a.start == b.start && a.end == b.end && a.due == b.due),("time flags",a.allDay == b.allDay && a.hasTime == b.hasTime),("timezone",a.timeZoneID == b.timeZoneID),("recurring",a.recurring == b.recurring),("repeat rules",a.recurrenceRules == b.recurrenceRules),("revision",a.modified == b.modified),("writable",a.writable == b.writable),("alarms",a.alarms == b.alarms && a.otherAlarmSignatures == b.otherAlarmSignatures),("url",a.url == b.url),("priority",a.priority == b.priority),("availability",a.availability == b.availability)].filter{!$0.1}.map{$0.0}
    }
}
#endif
