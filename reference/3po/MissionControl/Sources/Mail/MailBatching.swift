import Foundation

struct MailWindowProgress: Codable, Identifiable, Sendable {
    var id: String
    var accountID: String
    var start: Date
    var end: Date
    var offset = 0
    var messageIDs: [Int]?
    var seenIDs: Set<String> = []
    var complete = false
    var lastSuccess: Date?
    var mailboxName: String? = nil
    var mailboxRole: MailFolderRole? = nil
}

struct MailBatch: Decodable, Sendable {
    var messages: [MailMessage]
    var messageIDs: [Int]?
    var nextOffset: Int?
    var complete: Bool?
    var errors: [String]
    var retainedIDs: [Int]? = nil
}

struct MailIndexState: Codable {
    var windows: [MailWindowProgress] = []
    // Optional fields preserve existing checkpoints and interrupted day cursors.
    var monitors: [MailWindowProgress]? = nil
    var lastBackground: [String:Date]? = nil
    var lastAudit: [String:Date]? = nil
    var retryAfter: [String:Date]? = nil
    var failures: [String:Int]? = nil
    var accountErrors: [String:String]? = nil
    var discoveryChecked:Date? = nil
    var discoveryError:String? = nil

    mutating func discovered(error:String? = nil,now:Date = .now) {
        discoveryChecked=now;discoveryError=error
    }

    mutating func prepare(accounts: [MailAccount], now: Date = .now, calendar: Calendar = .current, lastCheck: Date? = nil) {
        let cutoff = now.addingTimeInterval(-30 * 86400)
        let old = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { _,new in new })
        windows = accounts.flatMap { account -> [MailWindowProgress] in
            var result: [MailWindowProgress] = []
            var day = calendar.startOfDay(for: now)
            while calendar.date(byAdding: .day, value: 1, to: day)! > cutoff {
                let end = calendar.date(byAdding: .day, value: 1, to: day)!
                let id = account.id + "@" + String(day.timeIntervalSince1970)
                var window = old[id] ?? MailWindowProgress(id: id, accountID: account.id, start: max(day, cutoff), end: end)
                window.start = max(day, cutoff)
                window.end = end
                result.append(window)
                day = calendar.date(byAdding: .day, value: -1, to: day)!
            }
            return result
        }
        let previous = monitors ?? []
        monitors = accounts.map { account in
            let id = "monitor:" + account.id
            if let saved = previous.first(where:{ $0.accountID == account.id }) {
                // Never expand or replace an interrupted page's range/IDs.
                if !saved.complete || now.timeIntervalSince(saved.end) < 30 { return saved }
                // Received timestamps can precede local delivery by hours. Recheck
                // recent identities, hydrating only new/replaced messages.
                return MailWindowProgress(id:id,accountID:account.id,start:max(cutoff,min(saved.end.addingTimeInterval(-600),now.addingTimeInterval(-48*3600))),end:now)
            }
            // First connection/migration checks recent arrivals; a known offline
            // gap is included once, rather than rebuilding history every refresh.
            let start = min(now.addingTimeInterval(-48*3600),lastCheck ?? now)
            return MailWindowProgress(id:id,accountID:account.id,start:max(cutoff,start),end:now)
        }
        let enabled = Set(accounts.map(\.id))
        retryAfter = (retryAfter ?? [:]).filter { enabled.contains($0.key) }
        failures = (failures ?? [:]).filter { enabled.contains($0.key) }
        accountErrors = (accountErrors ?? [:]).filter { enabled.contains($0.key) }
        lastBackground = (lastBackground ?? [:]).filter { enabled.contains($0.key) }
        lastAudit = (lastAudit ?? [:]).filter { enabled.contains($0.key) }
        // Nominate one due reconciliation window per account, never reset the
        // whole month. Recent days catch flags/late sync hourly; older days weekly.
        for account in accounts where available(account.id,now:now) {
            guard now.timeIntervalSince(lastAudit?[account.id] ?? .distantPast) >= 900 else { continue }
            let due = windows.indices.filter { index in
                let w = windows[index]
                let interval: TimeInterval = w.end > now.addingTimeInterval(-48*3600) ? 3600 : 7*86400
                return w.accountID == account.id && w.complete && now.timeIntervalSince(w.lastSuccess ?? .distantPast) >= interval
            }.sorted { (windows[$0].lastSuccess ?? .distantPast) < (windows[$1].lastSuccess ?? .distantPast) }
            if let index = due.first {
                windows[index].complete = false; windows[index].offset = 0
                windows[index].messageIDs = nil; windows[index].seenIDs = []
                lastAudit?[account.id] = now
            }
        }
    }

    func available(_ account: String, now: Date = .now) -> Bool { (retryAfter?[account] ?? .distantPast) <= now }
    func monitor(_ account: String) -> MailWindowProgress? { monitors?.first { $0.accountID == account && !$0.complete } }
    mutating func background(_ account: String, now: Date = .now) -> MailWindowProgress? {
        guard now.timeIntervalSince(lastBackground?[account] ?? .distantPast) >= 300,
              let window = windows.filter({ $0.accountID == account && !$0.complete }).sorted(by:{ $0.start > $1.start }).first else { return nil }
        if lastBackground == nil { lastBackground = [:] }; lastBackground?[account] = now
        return window
    }
    mutating func failed(_ account: String, detail: String, now: Date = .now) {
        if failures == nil { failures = [:] }; if retryAfter == nil { retryAfter = [:] }; if accountErrors == nil { accountErrors = [:] }
        let count = min(6,(failures?[account] ?? 0)+1); failures?[account] = count
        retryAfter?[account] = now.addingTimeInterval(min(1800,60*pow(2,Double(count-1))))
        accountErrors?[account] = detail
    }
    mutating func resume() { retryAfter = [:]; failures = [:]; accountErrors = [:] }
    mutating func resetCursor(_ id: String) {
        if let index = windows.firstIndex(where:{ $0.id == id }) { windows[index].offset = 0; windows[index].messageIDs = nil; windows[index].seenIDs = [] }
        if let index = monitors?.firstIndex(where:{ $0.id == id }) { monitors?[index].offset = 0; monitors?[index].messageIDs = nil; monitors?[index].seenIDs = [] }
    }

    mutating func apply(_ batch: MailBatch, to id: String, snapshot: MailSnapshot, now: Date = .now) -> MailSnapshot {
        let isMonitor = monitors?.contains(where:{ $0.id == id }) == true
        var collection = isMonitor ? (monitors ?? []) : windows
        guard let index = collection.firstIndex(where: { $0.id == id }) else { return snapshot }
        collection[index].messageIDs = batch.messageIDs
        collection[index].offset = batch.nextOffset ?? 0
        collection[index].seenIDs.formUnion(batch.messages.map(\.id))
        collection[index].seenIDs.formUnion((batch.retainedIDs ?? []).map { collection[index].accountID + ":" + String($0) })
        collection[index].complete = batch.complete == true
        collection[index].lastSuccess = now
        let window = collection[index]
        if isMonitor { monitors = collection } else { windows = collection }
        if window.complete { failures?[window.accountID] = nil; retryAfter?[window.accountID] = nil; accountErrors?[window.accountID] = nil }
        var records = Dictionary(snapshot.messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in batch.messages { records[message.id] = message }
        if window.complete {
            records = records.filter { _, message in
                message.accountID != window.accountID || message.received < window.start || message.received >= window.end || window.seenIDs.contains(message.id)
            }
        }
        let enabled = Set(snapshot.accounts.map(\.id))
        return MailSnapshot(messages: records.values.filter { enabled.contains($0.accountID) && $0.received >= now.addingTimeInterval(-30 * 86400) }.sorted { $0.received > $1.received }, accounts: snapshot.accounts, errors: [])
    }

    var pending: Bool { windows.contains { !$0.complete } }
    func coverage(accounts: [MailAccount]) -> String {
        accounts.map { account in
            let days = windows.filter { $0.accountID == account.id }
            let monitoring = monitors?.first(where:{ $0.accountID == account.id })
            let state = accountErrors?[account.id] != nil ? "retry pending" : monitoring?.complete == true ? "monitoring" : "checking arrivals"
            return "\(account.title) · \(state) · cache \(days.filter(\.complete).count)/\(days.count) days"
        }.joined(separator: "  ·  ")
    }
}

struct MailCheckpoint: Codable {
    var snapshot: MailSnapshot
    var index: MailIndexState
}

// Explicit fresh-check scopes and heartbeat's independently collected cache have
// separate coverage contracts. Both retain account and exact-message guards.
struct MailReviewWindow:Equatable {
    var start:Date
    var end:Date
    var checked:Date
}
struct MailReviewScope:Equatable {
    var windows:[String:MailReviewWindow] = [:]
    var issues:[String:String] = [:]
    var discoveryFailed=false
    var usesCollectedMail=false
    var capturedFailures:[String:Int] = [:]
    var capturedRetries:[String:Date] = [:]
    var accountIDs:Set<String> {Set(windows.keys)}
    var pending:Bool {discoveryFailed || !issues.isEmpty}
    static func collected(index:MailIndexState,snapshot:MailSnapshot,excluded:Set<String>)->MailReviewScope {
        var value=MailReviewScope();value.usesCollectedMail=true
        value.discoveryFailed=index.discoveryError != nil || index.discoveryChecked == nil
        let pages=(index.monitors ?? [])+index.windows
        for account in snapshot.accounts where !excluded.contains(account.id) {
            // A successful partial page is usable too. Completion describes
            // coverage, not whether its already collected headers can be analysed.
            if let page=pages.filter({$0.accountID == account.id && $0.lastSuccess != nil}).max(by:{($0.lastSuccess ?? .distantPast) < ($1.lastSuccess ?? .distantPast)}),let checked=page.lastSuccess {
                value.windows[account.id] = .init(start:page.start,end:page.end,checked:checked)
                value.capturedFailures[account.id]=index.failures?[account.id] ?? 0
                value.capturedRetries[account.id]=index.retryAfter?[account.id]
            }
            if let error=index.accountErrors?[account.id] {value.issues[account.id]=String(error.prefix(300))}
            else if value.discoveryFailed {value.issues[account.id]="Background account discovery unavailable"}
            else if index.monitors?.first(where:{$0.accountID == account.id})?.complete != true {value.issues[account.id]="Background arrival check unfinished"}
            else if value.windows[account.id] == nil {value.issues[account.id]="No collected Mail available yet"}
        }
        return value
    }
    func coverage(accounts:[MailAccount])->String {
        guard usesCollectedMail else {return "Freshly checked Mail accounts: \(accountIDs.count); unavailable/pending: \(issues.count). "}
        let dates=windows.keys.sorted().map{id in
            (accounts.first{$0.id == id}?.title ?? "Mail account")+": last successful batch "+windows[id]!.checked.ISO8601Format()
        }.joined(separator:"; ")
        return "Collected Mail available from \(accountIDs.count) account(s); background collection issues: \(issues.count). \(dates). Heartbeat did not refresh Mail. Coverage may be partial or outdated; do not infer an empty or fully checked inbox. "
    }
    static func capture(index:MailIndexState,snapshot:MailSnapshot,excluded:Set<String>,since:Date)->MailReviewScope {
        var value=MailReviewScope()
        let discovered=index.discoveryError == nil && (index.discoveryChecked ?? .distantPast) >= since.addingTimeInterval(-30)
        value.discoveryFailed = !discovered
        for account in snapshot.accounts where !excluded.contains(account.id) {
            if !discovered {value.issues[account.id]="Account discovery unavailable";continue}
            if let error=index.accountErrors?[account.id] {value.issues[account.id]=String(error.prefix(300));continue}
            guard let monitor=index.monitors?.first(where:{$0.accountID == account.id}),monitor.complete,
                  let checked=monitor.lastSuccess,checked >= since.addingTimeInterval(-30),monitor.end >= since.addingTimeInterval(-30) else {value.issues[account.id]="Arrival check unfinished";continue}
            value.windows[account.id] = .init(start:monitor.start,end:monitor.end,checked:checked)
        }
        return value
    }
    func permits(_ accountID:String,index:MailIndexState,snapshot:MailSnapshot,excluded:Set<String>)->Bool {
        if usesCollectedMail {
            // Pre-existing collection errors do not discard verified cached
            // headers. A new read failure still narrows an in-flight assessment.
            let sameFailure=index.retryAfter?[accountID] == nil || index.retryAfter?[accountID] == capturedRetries[accountID]
            return windows[accountID] != nil && !excluded.contains(accountID) && snapshot.accounts.contains{$0.id == accountID} && sameFailure && (index.failures?[accountID] ?? 0) <= (capturedFailures[accountID] ?? 0)
        }
        guard let captured=windows[accountID],index.discoveryError == nil,!excluded.contains(accountID),
              snapshot.accounts.contains(where:{$0.id == accountID}),index.accountErrors?[accountID] == nil,
              let current=index.monitors?.first(where:{$0.accountID == accountID}),current.complete,
              current.end >= captured.end,(current.lastSuccess ?? .distantPast) >= captured.checked else {return false}
        return true
    }
    func available(index:MailIndexState,snapshot:MailSnapshot,excluded:Set<String>)->MailReviewScope {
        var value=self
        if usesCollectedMail {
            let current=Self.collected(index:index,snapshot:snapshot,excluded:excluded)
            value.issues=current.issues;value.discoveryFailed=current.discoveryFailed
        }
        for id in windows.keys where !permits(id,index:index,snapshot:snapshot,excluded:excluded) {
            value.windows[id]=nil;value.issues[id]=String((index.accountErrors?[id] ?? "Account changed or is unavailable").prefix(300))
        }
        return value
    }
}
