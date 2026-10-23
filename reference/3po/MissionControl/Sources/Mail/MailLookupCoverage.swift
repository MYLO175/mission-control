import Foundation

enum MailLookupCoverage {
    static func folderKey(_ window: MailWindowProgress) -> String {
        // Structured identity avoids collisions from mailbox names containing separators.
        let parts = [window.accountID,window.mailboxRole?.rawValue ?? "inbox",window.mailboxName ?? ""]
        return String(decoding:(try? JSONEncoder().encode(parts)) ?? Data(),as:UTF8.self)
    }
    static func next(_ windows: [MailWindowProgress], failedFolders: Set<String>) -> Int? {
        windows.firstIndex { !$0.complete && !failedFolders.contains(folderKey($0)) }
    }
    static func hasMore(_ windows: [MailWindowProgress], failedFolders: Set<String>, results: [MailMessage], delivered: Set<String>) -> Bool {
        next(windows,failedFolders:failedFolders) != nil || results.contains { !delivered.contains($0.id) }
    }
    static func status(_ windows: [MailWindowProgress], failedFolders: Set<String>, matched: Int, failedBodies: Int, hasMore: Bool) -> String {
        let complete = windows.filter(\.complete).count
        let unavailable = windows.filter { !$0.complete && failedFolders.contains(folderKey($0)) }.count
        let warning = unavailable > 0 || failedBodies > 0
        return "\(complete)/\(windows.count) account/mailbox/date windows searched · \(matched) header keyword matches. " + (hasMore ? "Partial; Continue mail search reads another bounded batch. " : warning ? "Available reads finished; requested coverage remains partial. " : "Requested header search complete. ") + (unavailable > 0 ? "\(unavailable) windows unavailable. " : "") + (failedBodies > 0 ? "\(failedBodies) matched previews unavailable; only headers were supplied. " : "") + (warning ? "Retry unavailable mail reads only when ready." : "")
    }
}
