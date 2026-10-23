import Foundation

enum NativeSourceAdapters {
    static func fresh(_ health:SourceHealth,now:Date)->Bool {
        !health.loading && health.error == nil && health.lastSuccess.map{now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) <= 1800} == true
    }
    static func calendar(_ orientation:PAOrientation,sources:Set<String>,now:Date)->[NativeLearningItem] {
        let events=orientation.events(excluding:sources)
        let counts=Dictionary(grouping:events,by:{NativeLearningRules.hash([$0.calendarID,$0.memoryItemID ?? ""])}).mapValues(\.count)
        return events.compactMap { event in
            guard let provider=orientation.calendar.sources.first(where:{$0.id == event.calendarID})?.providerID,!provider.isEmpty,
                  let itemID=event.memoryItemID,!itemID.isEmpty,counts[NativeLearningRules.hash([event.calendarID,itemID])] == 1 else { return nil }
            let text="Calendar entry: \(event.title)\nStart: \(event.allDay ? DateRules.localDate(event.start) : DateRules.localTimestamp(event.start))\nEnd (exclusive): \(event.allDay ? DateRules.localDate(event.end) : DateRules.localTimestamp(event.end))\nAll day: \(event.allDay)\nCalendar: \(event.sourceLabel)"
            let identity=MemorySourceIdentity(kind:.calendar,accountID:provider,containerID:event.calendarID,itemID:itemID)
            guard identity.valid,text.utf8.count <= 2400 else { return nil }
            return .init(identity:identity,revision:NativeLearningRules.hash([text,event.modified?.ISO8601Format() ?? ""]),label:String(event.sourceLabel.prefix(300)),text:text,date:event.start,changed:event.modified)
        }
    }
    static func reminders(_ snapshot:ReminderSnapshot,excluded:Set<String>)->[NativeLearningItem] {
        Array(snapshot.reminders.filter{!excluded.contains($0.listID)}.prefix(200)).compactMap { item in
            guard let provider=snapshot.sources.first(where:{$0.id == item.listID})?.providerID,!provider.isEmpty else { return nil }
            let text="Incomplete reminder: \(item.title)\nDue: \(DateRules.reminderDue(item))\nList: \(item.sourceLabel)\nRecurring: \(item.recurring)"
            let identity=MemorySourceIdentity(kind:.reminder,accountID:provider,containerID:item.listID,itemID:item.id)
            guard identity.valid,text.utf8.count <= 2400 else { return nil }
            return .init(identity:identity,revision:NativeLearningRules.hash([text,item.modified?.ISO8601Format() ?? ""]),label:String(item.sourceLabel.prefix(300)),text:text,date:item.due,changed:item.modified)
        }
    }
    /// Use independently collected account lanes. A new failure narrows a captured run;
    /// an existing partial-page warning does not erase exact cached source evidence.
    static func collectedMail(_ snapshot:MailSnapshot,index:MailIndexState,summaries:[EmailSummary],registration:String,excluded:Set<String>,now:Date,scope:MailReviewScope? = nil)->[NativeLearningItem] {
        let captured=scope ?? MailReviewScope.collected(index:index,snapshot:snapshot,excluded:excluded)
        let permitted=snapshot.messages.filter{captured.permits($0.accountID,index:index,snapshot:snapshot,excluded:excluded)}
        return mail(permitted,summaries:summaries,registration:registration,excluded:excluded,now:now)
    }
    static func mail(_ messages:[MailMessage],summaries:[EmailSummary],registration:String,excluded:Set<String>,now:Date)->[NativeLearningItem] {
        let counts=Dictionary(grouping:messages.filter{!excluded.contains($0.accountID)},by:{NativeLearningRules.hash([$0.accountID,$0.internetMessageID])}).mapValues(\.count)
        return Array(messages.filter{!excluded.contains($0.accountID)}.sorted{($0.received,$0.id) > ($1.received,$1.id)}.prefix(200)).compactMap { message in
            guard !message.internetMessageID.isEmpty,counts[NativeLearningRules.hash([message.accountID,message.internetMessageID])] == 1,
                  let summary=summaries.first(where:{$0.registration == registration && $0.id == message.id && $0.fingerprint == EmailSummary.fingerprint(message)}),
                  let body=summary.bodyFingerprint,!body.isEmpty,(summary.observedBodyFingerprint == nil || summary.observedBodyFingerprint == body),let checked=summary.bodyCheckedAt,now.timeIntervalSince(checked) >= 0,now.timeIntervalSince(checked) <= 86400 else { return nil }
            let header="Email sender: \(message.sender)\nSubject: \(message.subject)\nReceived: \(message.received.ISO8601Format())\nExact retained excerpts:\n"
            var quotes:[String]=[],bytes=header.utf8.count
            for quote in [summary.evidence,summary.followUpEvidence ?? ""] + (summary.actionEvidence ?? []) {
                guard (8...500).contains(quote.count),!quotes.contains(quote),bytes+quote.utf8.count+1 <= 2400 else {continue}
                quotes.append(quote);bytes += quote.utf8.count+1
            }
            guard !quotes.isEmpty else {return nil}
            let text=header+quotes.joined(separator:"\n")
            let identity=MemorySourceIdentity(kind:.mail,accountID:message.accountID,containerID:message.accountID,itemID:message.internetMessageID)
            guard identity.valid,text.utf8.count <= 2400 else { return nil }
            return .init(identity:identity,revision:NativeLearningRules.hash([text,body]),label:String(("Mail · " + message.account).prefix(300)),text:text,date:message.received,changed:checked)
        }
    }
}
