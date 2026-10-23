import Foundation

// Deterministic local fixtures: no Apple-app permissions, writes or network requests.
struct SampleCalendarService {
    func snapshot(now: Date = .now) -> CalendarSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let source = SourceOption(id: "sample", title: "Personal", account: "Sample account", writable: false)
        return .init(sources: [source], events: [
            .init(id: "all", calendarID: source.id, title: "Project day", start: today, end: calendar.date(byAdding: .day, value: 1, to: today)!, allDay: true, location: "", sourceLabel: source.label),
            .init(id: "review", calendarID: source.id, title: "Design review", start: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!, end: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!, allDay: false, location: "Studio", sourceLabel: source.label)])
    }
}
struct SampleReminderService {
    func snapshot(now: Date = .now) -> ReminderSnapshot {
        let source = SourceOption(id: "sample", title: "Personal", account: "Sample account", writable: false)
        return .init(sources: [source], reminders: [.init(id: "task", listID: source.id, title: "Review Mission Control", due: Calendar.current.startOfDay(for: now), hasTime: false, sourceLabel: source.label, writable: false, recurring: false)])
    }
    func complete(id: String) throws { throw IntegrationError.readOnly }
}
struct SampleMailService {
    func snapshot() -> MailSnapshot { .init(messages: [], accounts: [], errors: []) }
}
