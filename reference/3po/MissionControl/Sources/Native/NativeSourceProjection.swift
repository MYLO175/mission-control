import Foundation
import EventKit

extension DashboardModel {
    /// Pure local projection. A missing item is unknown; this never fetches sources or infers.
    func nativeLearningItems(_ kind:MemorySourceKind,now:Date = .now)->[NativeLearningItem]? {
        nativeLearningValidation.items(kind) {projectedNativeLearningItems(kind,now:now)}
    }
    private func projectedNativeLearningItems(_ kind:MemorySourceKind,now:Date)->[NativeLearningItem]? {
        guard assistant.contextEnabled,!ProcessInfo.processInfo.arguments.contains("--sample") else { return nil }
        switch kind {
        case .calendar:
            guard orientationCollectionRevision == sourceRevision,EKEventStore.authorizationStatus(for:.event) == .fullAccess,NativeSourceAdapters.fresh(paOrientationHealth,now:now),let orientation=paOrientation,Calendar.current.isDate(orientation.refreshed,inSameDayAs:now) else { return nil }
            let key=nativeLearningProjectionKey(excluded:assistant.excludedCalendars,now:now)
            return nativeLearningProjectionCache.items(kind,key:key) {NativeSourceAdapters.calendar(orientation,sources:assistant.excludedCalendars,now:now)}
        case .reminder:
            guard reminderCollectionRevision == sourceRevision,EKEventStore.authorizationStatus(for:.reminder) == .fullAccess,NativeSourceAdapters.fresh(reminderHealth,now:now) else { return nil }
            let key=nativeLearningProjectionKey(excluded:assistant.excludedLists,now:now)
            return nativeLearningProjectionCache.items(kind,key:key) {NativeSourceAdapters.reminders(reminderData,excluded:assistant.excludedLists)}
        case .mail:
            let key=MailLearningProjectionKey(collectionRevision:mailLearningProjectionRevision,summaryRevision:emailSummaries.sourceProjectionRevision,registration:chatGPT.activeID,excluded:assistant.excludedAccounts)
            // Rebuild at the next future checked-time or 24-hour expiry, and after a clock rollback.
            let boundary=MailLearningProjectionCache.deadline(checked:emailSummaries.records.compactMap(\.bodyCheckedAt),now:now)
            return mailLearningProjectionCache.items(key:key,now:now,until:boundary) {NativeSourceAdapters.collectedMail(mailData,index:mailIndex,summaries:emailSummaries.records,registration:chatGPT.activeID,excluded:assistant.excludedAccounts,now:now)}
        case .whatsapp:return nil
        }
    }
    private func nativeLearningProjectionKey(excluded:Set<String>,now:Date)->NativeLearningProjectionKey {
        .init(collectionRevision:nativeLearningProjectionRevision,excluded:excluded,timezone:TimeZone.current.identifier+":"+String(TimeZone.current.secondsFromGMT(for:now)),locale:Locale.current.identifier+":"+String(describing:Calendar.current.identifier),day:Calendar.current.startOfDay(for:now))
    }
}
