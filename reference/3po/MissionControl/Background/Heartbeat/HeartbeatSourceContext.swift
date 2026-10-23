import Foundation
import EventKit

/// Read-only views of independently collected snapshots. These helpers never
/// start a collector. A known native change invalidates the old collection until
/// the background reader has caught up; an unrelated collection error does not.
@MainActor extension DashboardModel {
    func heartbeatCalendar() throws -> CalendarSnapshot {
        guard EKEventStore.authorizationStatus(for:.event) == .fullAccess,let paOrientation, orientationCollectionRevision == sourceRevision,
              paOrientation.end > Date.now else {
            throw NativeSourceReadError.unavailable("Saved Calendar context is not current; background collection is pending.")
        }
        return paOrientation.calendar
    }
    func heartbeatReminders() throws -> ReminderSnapshot {
        guard EKEventStore.authorizationStatus(for:.reminder) == .fullAccess,reminderHealth.lastSuccess != nil, reminderCollectionRevision == sourceRevision else {
            throw NativeSourceReadError.unavailable("Saved Reminders context is not current; background collection is pending.")
        }
        return reminderData
    }
    var heartbeatNativeReady:Bool { (try? heartbeatCalendar()) != nil && (try? heartbeatReminders()) != nil }
    var heartbeatSourceCoverage:String {
        func note(_ name:String,_ health:SourceHealth)->String {
            name+": "+(health.lastSuccess.map{"last collected "+DateRules.localTimestamp($0)} ?? "not collected")+(health.error == nil ? "" : "; background collection has an issue")
        }
        return [note("Calendar",paOrientationHealth),note("Reminders",reminderHealth)].joined(separator:". ")+". Saved snapshots; missing items are not proof of absence."
    }
}
