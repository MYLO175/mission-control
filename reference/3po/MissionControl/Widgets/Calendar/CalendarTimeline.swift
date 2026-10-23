import Foundation

struct CalendarTimelineSegment: Identifiable {
    var id: String { event.id }
    var event: AgendaEvent
    var start: Date
    var end: Date
    var lane: Int
    var lanes: Int
}
enum CalendarTimelineLayout {
    static func segments(_ events: [AgendaEvent], interval: DateInterval) -> [CalendarTimelineSegment] {
        let clipped = events.filter { !$0.allDay && $0.start < interval.end && ($0.end > interval.start || $0.end == $0.start && $0.start >= interval.start) }
            .sorted { ($0.start,$0.end,$0.id) < ($1.start,$1.end,$1.id) }
        var output: [CalendarTimelineSegment] = [], group: [CalendarTimelineSegment] = [], laneEnds: [Date] = [], groupEnd = interval.start
        func finish() { for var item in group { item.lanes = laneEnds.count; output.append(item) }; group = []; laneEnds = [] }
        for event in clipped {
            let start = max(event.start,interval.start), end = min(max(event.end,start),interval.end)
            // Minimum visual height is also reserved for collision layout.
            let visualEnd = min(interval.end,max(end,start.addingTimeInterval(CalendarTimelineFocus.minimumEventHeight/CalendarTimelineFocus.hourHeight*3600)))
            if !group.isEmpty && start >= groupEnd { finish(); groupEnd = interval.start }
            let lane = laneEnds.firstIndex(where: { $0 <= start }) ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(visualEnd) } else { laneEnds[lane] = visualEnd }
            groupEnd = max(groupEnd,visualEnd)
            group.append(.init(event:event,start:start,end:end,lane:lane,lanes:1))
        }
        finish(); return output
    }
}

// Clock-based focus preserves daylight-saving days rather than assuming 24 hours.
enum CalendarTimelineFocus {
    static let hourHeight = 52.0
    static let minimumEventHeight = 20.0
    static func columnWidth(available: Double, days: Int) -> Double {
        max(days == 1 ? 220 : 125,(available - Double(max(0,days-1))*8)/Double(max(1,days)))
    }
    static func hour(on day: Date, now: Date, events: [AgendaEvent], calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for:day)
        let target: Int
        if calendar.isDate(day,inSameDayAs:now) {
            target = min(17,max(8,calendar.component(.hour,from:now)-1))
        } else {
            let first = events.filter { !$0.allDay && DateRules.overlaps($0,day:day,calendar:calendar) }.map { max($0.start,start) }.min()
            target = first.map { min(8,max(0,calendar.component(.hour,from:$0)-1)) } ?? 8
        }
        return calendar.date(bySettingHour:target,minute:0,second:0,of:start) ?? start
    }
    static func anchor(_ date: Date) -> String { "calendar-hour:" + String(Int(date.timeIntervalSince1970)) }
    static func workingHours(on day: Date, calendar: Calendar = .current) -> DateInterval {
        DateInterval(start:calendar.date(bySettingHour:9,minute:0,second:0,of:day)!,end:calendar.date(bySettingHour:18,minute:0,second:0,of:day)!)
    }
}

enum CalendarTimelineMove {
    static func destination(start: Date, day: Date, dx: Double, dy: Double, columnWidth: Double, visibleDays: Int, range: DateInterval, calendar: Calendar = .current) -> Date? {
        guard let target = translated(start:max(start,calendar.startOfDay(for:day)),day:day,dx:dx,dy:dy,columnWidth:columnWidth,visibleDays:visibleDays,range:range,calendar:calendar), let displayed = self.start(on:target.day,y:target.y,calendar:calendar) else { return nil }
        // Overnight cards may be clipped at midnight. Move the real start by
        // the displayed segment's delta instead of shortening the event.
        return displayed.addingTimeInterval(min(0,start.timeIntervalSince(calendar.startOfDay(for:day))))
    }
    static func translated(start: Date, day: Date, dx: Double, dy: Double, columnWidth: Double, visibleDays: Int, range: DateInterval, calendar: Calendar = .current) -> (day: Date,y: Double)? {
        guard dx.isFinite, dy.isFinite, columnWidth > 0, visibleDays > 0, range.contains(day), let interval = calendar.dateInterval(of:.day,for:day) else { return nil }
        let columns = visibleDays == 1 ? 0 : Int(max(-Double(visibleDays),min(Double(visibleDays),(dx/(columnWidth+8)).rounded())))
        guard let targetDay = calendar.date(byAdding:.day,value:columns,to:day), range.contains(targetDay) else { return nil }
        let y = max(0,start.timeIntervalSince(interval.start)/3600*CalendarTimelineFocus.hourHeight + dy)
        return (targetDay,y)
    }
    /// Snap elapsed timeline coordinates, preserving both occurrences of repeated DST hours.
    static func start(on day: Date, y: Double, calendar: Calendar = .current) -> Date? {
        guard y.isFinite, y >= 0, let interval = calendar.dateInterval(of:.day,for:day) else { return nil }
        let elapsed = (y / CalendarTimelineFocus.hourHeight * 3600 / 900).rounded() * 900
        return interval.start.addingTimeInterval(min(max(0,elapsed),interval.duration-900))
    }
}
