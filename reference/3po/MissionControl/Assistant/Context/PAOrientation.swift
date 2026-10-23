import Foundation

struct PAOrientation: Codable {
    var start: Date
    var end: Date
    var refreshed: Date
    var calendar: CalendarSnapshot
    func coverage(now: Date = .now, limit: Int = 200, enabledCount: Int) -> String {
        let stale = Calendar.current.isDate(refreshed,inSameDayAs:now) ? "" : "Cached from an earlier day. "
        return stale + "Calendar window " + DateRules.localDate(start) + " to " + DateRules.localDate(end) + " (end exclusive); \(enabledCount) enabled events, first \(limit) supplied. Events outside this window/cap are not represented."
    }
    func events(excluding: Set<String>, limit: Int = 200) -> [AgendaEvent] {
        Array(calendar.events.filter { !excluding.contains($0.calendarID) }.sorted { ($0.start,$0.title,$0.id) < ($1.start,$1.title,$1.id) }.prefix(limit))
    }
}
