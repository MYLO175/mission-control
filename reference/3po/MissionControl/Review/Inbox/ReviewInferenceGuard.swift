import Foundation
import CryptoKit

/// Exact supplied input receipts; store revisions and newly collected unrelated
/// rows are not dependencies of an already running Review inference.
enum ReviewInferenceGuard {
    static func fingerprint<T:Encodable>(_ value:T)->String {
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return SHA256.hash(data:(try? encoder.encode(value)) ?? Data()).map{String(format:"%02x",$0)}.joined()
    }
    static func available(_ captured:[String:String],current:[String:String])->Bool {
        captured.allSatisfy{current[$0.key] == $0.value}
    }
    /// A historical row can author a replacement only while its exact issued
    /// snapshot and purpose-specific support remain usable. Unreferenced rows
    /// never become dependencies of otherwise fresh output.
    static func eligibleHistorical(_ captured:[String:String],current:[String:String],permitted:Set<String>)->Set<String> {
        Set(captured.keys.filter{permitted.contains($0) && current[$0] == captured[$0]})
    }
    static func comparisonDependencies(fresh:[WhatsAppWindowDependency],replaced:[String],prior:[String:[WhatsAppWindowDependency]])->[WhatsAppWindowDependency] {
        var result:[WhatsAppWindowDependency]=[],seen=Set<String>()
        for value in fresh where seen.insert(value.chatID).inserted {result.append(value)}
        for id in Set(replaced).sorted() {
            for value in (prior[id] ?? []).sorted(by:{$0.chatID < $1.chatID}) where seen.insert(value.chatID).inserted {result.append(value)}
        }
        return result
    }
    /// Apply the latest exact human acknowledgements to a validated completed
    /// envelope. A dismissed request is withheld, while sibling sources and a
    /// dismissed message's use as truthful confirmation evidence remain intact.
    static func currentAttentionRows(_ response:String,dismissedSources:Set<String>,dismissedReviews:Set<String> = [])throws->(response:String,limited:Bool) {
        guard var object=try JSONSerialization.jsonObject(with:Data(response.utf8)) as? [String:Any],
              let suggestions=object["suggestions"] as? [[String:Any]] else {throw CocoaError(.fileReadCorruptFile)}
        let limited=suggestions.count >= 24
        guard !dismissedSources.isEmpty || !dismissedReviews.isEmpty else {return (response,limited)}
        for section in ["suggestions","handled","resolved"] {
            guard let rows=object[section] as? [[String:Any]] else {throw CocoaError(.fileReadCorruptFile)}
            object[section]=rows.filter{row in !((row["mailID"] as? String).map(dismissedSources.contains) ?? false)}
        }
        if let rows=object["retirements"] as? [[String:Any]] {
            object["retirements"]=rows.filter{row in !((row["reviewID"] as? String).map(dismissedReviews.contains) ?? false)}
        }
        return (String(decoding:try JSONSerialization.data(withJSONObject:object,options:.sortedKeys),as:UTF8.self),limited)
    }
    /// Native absence/duplicate reasoning uses the whole admitted bounded set:
    /// a newly admitted row matters, whereas an excluded or after-cap row does not.
    static func nativeAvailable(_ captured:[String:String],current:[String:String])->Bool {captured == current}
    /// Read/unread, flags, account display labels and mailbox placement do not
    /// change fetched source text or its ownership. Reply state remains relevant.
    static func mailSource(_ message:MailMessage)->String {
        fingerprint([message.id,message.accountID,String(message.messageID),message.internetMessageID,message.sender,message.subject,message.received.ISO8601Format(),String(message.replied)] + (message.recipients ?? []))
    }
    static func nativeRows(calendar:CalendarSnapshot,reminders:ReminderSnapshot,completed:[CompletedReminder],excludedCalendars:Set<String>,excludedLists:Set<String>)->[String:String] {
        var result:[String:String]=[:]
        for item in calendar.events where !excludedCalendars.contains(item.calendarID) {
            result["event:"+item.id]=fingerprint([fingerprint(item),String(calendar.sources.first{$0.id == item.calendarID}?.writable == true)])
        }
        for item in reminders.reminders where !excludedLists.contains(item.listID) {result["reminder:"+item.id]=fingerprint(item)}
        for item in completed where !excludedLists.contains(item.item.listID) {result["completed:"+item.item.id]=fingerprint(item)}
        return result
    }
}
