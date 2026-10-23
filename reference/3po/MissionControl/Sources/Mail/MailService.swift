import Foundation

struct MailAccount: Codable, Identifiable, Sendable {
    let id: String
    let title: String
}
enum MailFolderRole: String, Codable, Sendable { case inbox, sent, archive }
struct MailFolder: Codable, Identifiable, Sendable {
    let id: String
    let accountID: String
    let account: String
    let name: String
    let role: MailFolderRole
}
struct MailFolderDiscovery: Codable, Sendable { let folders: [MailFolder]; let accounts: [MailAccount]; let errors: [String] }

struct MailMessage: Codable, Identifiable, Sendable {
    let id: String
    let accountID: String
    let account: String
    let messageID: Int
    let internetMessageID: String
    let sender: String
    let subject: String
    let received: Date
    let unread: Bool
    let replied: Bool
    let flagged: Bool
    let mailboxName: String?
    let mailboxRole: MailFolderRole?
    let recipients: [String]?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        accountID = try values.decode(String.self, forKey: .accountID)
        account = try values.decode(String.self, forKey: .account)
        messageID = try values.decode(Int.self, forKey: .messageID)
        internetMessageID = try values.decode(String.self, forKey: .internetMessageID)
        sender = try values.decode(String.self, forKey: .sender)
        subject = try values.decode(String.self, forKey: .subject)
        if let receivedString = try? values.decode(String.self, forKey: .received) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsedDate = formatter.date(from: receivedString) {
                received = parsedDate
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                guard let parsedDate = formatter.date(from: receivedString) else {
                    throw DecodingError.dataCorruptedError(forKey: .received, in: values, debugDescription: "Invalid ISO8601 date")
                }
                received = parsedDate
            }
        } else if let referenceSeconds = try? values.decode(Double.self, forKey: .received) {
            // JSONEncoder's synthesized Date representation is seconds since 2001-01-01.
            received = Date(timeIntervalSinceReferenceDate: referenceSeconds)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .received, in: values, debugDescription: "Expected ISO8601 string or encoded Date")
        }
        unread = try values.decode(Bool.self, forKey: .unread)
        replied = try values.decode(Bool.self, forKey: .replied)
        flagged = try values.decode(Bool.self, forKey: .flagged)
        mailboxName = try values.decodeIfPresent(String.self,forKey:.mailboxName)
        mailboxRole = try values.decodeIfPresent(MailFolderRole.self,forKey:.mailboxRole)
        recipients = try values.decodeIfPresent([String].self,forKey:.recipients)
    }
}

struct MailSnapshot: Codable, Sendable {
    let messages: [MailMessage]
    let accounts: [MailAccount]
    let errors: [String]
    var timedOut: Bool? = nil
}

extension MailSnapshot {
    func retainingFailedAccounts(from previous: MailSnapshot, now: Date = .now) -> MailSnapshot {
        let known = accounts + previous.accounts
        let failed = Set(known.filter { account in errors.contains { $0.hasPrefix("Account " + account.id + ":") } }.map(\.id))
        let retainAll = errors.contains { $0.hasPrefix("Mail:") }
        let successful = Set(accounts.map(\.id)).subtracting(failed)
        let retained = previous.messages.filter { (retainAll || failed.contains($0.accountID)) && !successful.contains($0.accountID) }
        var byID: [String: MailMessage] = [:]
        for message in retained + messages where message.received >= now.addingTimeInterval(-30 * 86400) { byID[message.id] = message }
        var byAccount: [String: MailAccount] = [:]
        for account in previous.accounts where retainAll || failed.contains(account.id) { byAccount[account.id] = account }
        for account in accounts { byAccount[account.id] = account }
        return MailSnapshot(messages: byID.values.sorted { $0.received > $1.received }, accounts: byAccount.values.sorted { $0.title < $1.title }, errors: errors, timedOut: timedOut)
    }
}

actor MailService {
    private let scriptURL: URL?
    private let timeout: TimeInterval

    init(scriptURL: URL? = Bundle.main.url(forResource: "MailReader", withExtension: "js"), timeout: TimeInterval = 45) {
        self.scriptURL = scriptURL
        self.timeout = timeout
    }

    func headers() async throws -> MailSnapshot {
        let discovery = try JSONDecoder().decode(MailDiscovery.self, from: run(arguments: ["operation": "probe"]))
        var messages: [MailMessage] = []
        var errors = discovery.errors
        var timedOut = false
        // Each account has its own serial helper and timeout. Preserve a healthy
        // account's result even if the other account stalls or denies access.
        for account in discovery.accounts {
            do {
                let data = try run(arguments: ["operation": "headers", "accountID": account.id])
                let snapshot = try JSONDecoder().decode(MailSnapshot.self, from: data)
                messages.append(contentsOf: snapshot.messages)
                errors.append(contentsOf: snapshot.errors)
            } catch {
                if case MailServiceError.timedOut = error { timedOut = true }
                errors.append("Account \(account.id): \(error.localizedDescription)")
            }
        }
        return MailSnapshot(messages: messages.sorted { $0.received > $1.received }, accounts: discovery.accounts, errors: errors, timedOut: timedOut)
    }

    func discoverAccounts() async throws -> MailDiscovery {
        try JSONDecoder().decode(MailDiscovery.self, from: run(arguments: ["operation": "probe"]))
    }
    func discoverSearchFolders() async throws -> MailFolderDiscovery {
        try JSONDecoder().decode(MailFolderDiscovery.self,from:run(arguments:["operation":"folders"]))
    }
    #if DEBUG
    func validateDates() async throws -> String {
        let day=Calendar.current.startOfDay(for:.now),end=Calendar.current.date(byAdding:.day,value:1,to:day)!
        return String(decoding:try run(arguments:["operation":"probe-dates","start":day.timeIntervalSince1970,"end":end.timeIntervalSince1970]),as:UTF8.self)
    }
    func validateMonitoring() async throws -> [String:Any] {
        let discovery = try await discoverAccounts()
        let initial = Date.now
        var reports: [[String:Any]] = []
        // Disposable state, aggregate-only output, no inference or personal cache
        // mutation. Two small arrival scans and one targeted header page/account.
        for account in discovery.accounts.prefix(4) {
            do {
                let window = MailWindowProgress(id:"monitor:"+account.id,accountID:account.id,start:initial.addingTimeInterval(-660),end:initial.addingTimeInterval(-60))
                var state = MailIndexState(); state.monitors = [window]
                var snapshot = MailSnapshot(messages:[],accounts:[account],errors:[])
                let first = try await batch(accountID:account.id,window:window)
                snapshot = state.apply(first,to:window.id,snapshot:snapshot)
                state = try JSONDecoder().decode(MailIndexState.self,from:JSONEncoder().encode(state))
                state.prepare(accounts:[account])
                guard let next = state.monitor(account.id) else { throw IntegrationError.verification }
                let second = try await batch(accountID:account.id,window:next)
                _ = state.apply(second,to:next.id,snapshot:snapshot)
                let searchWindow = MailWindowProgress(id:"search",accountID:account.id,start:initial.addingTimeInterval(-86400),end:initial,mailboxRole:.inbox)
                let search = try await batch(accountID:account.id,window:searchWindow,searchTerms:["Engineering"])
                reports.append(["firstHeaders":first.messages.count,"secondHeaders":second.messages.count,"secondRangeSeconds":next.end.timeIntervalSince(next.start),"resumedExactCursor":!first.complete! ? next.messageIDs == first.messageIDs && next.offset == first.nextOffset : true,"keywordHeaders":search.messages.count,"keywordPageComplete":search.complete == true,"keywordsVerified":search.messages.allSatisfy { $0.subject.localizedCaseInsensitiveContains("Engineering") || $0.sender.localizedCaseInsensitiveContains("Engineering") }])
            } catch { reports.append(["unavailable":true]) }
        }
        return ["accounts":discovery.accounts.count,"discoveryErrors":discovery.errors.count,"checks":reports,"elapsedSeconds":Date.now.timeIntervalSince(initial),"personalCacheChanged":false,"inferenceRequests":0]
    }
    func validateSearchFolders() async throws -> String {
        let discovery = try await discoverSearchFolders()
        var checks: [String] = ["\(discovery.accounts.count) accounts, \(discovery.folders.count) discovered Inbox/Sent/Archive folders"]
        let end = Calendar.current.startOfDay(for:.now)
        for role in [MailFolderRole.sent,.archive] {
            let folders = Array(discovery.folders.filter { $0.role == role }.prefix(2))
            guard !folders.isEmpty else { checks.append(role.rawValue + ": unavailable (not guessed)"); continue }
            var matched: MailMessage?, pageCount = 0, headerCount = 0
            search: for dayOffset in 1...2 {
                let day = Calendar.current.date(byAdding:.day,value:-dayOffset,to:end)!, next = Calendar.current.date(byAdding:.day,value:1,to:day)!
                for folder in folders {
                    let page = try await batch(accountID:folder.accountID,window:.init(id:"fixture",accountID:folder.accountID,start:day,end:next,mailboxName:folder.name,mailboxRole:folder.role))
                    pageCount += 1; headerCount += page.messages.count
                    if let message = page.messages.first { matched = message; break search }
                }
            }
            if let message = matched {
                _ = try await body(accountID:message.accountID,messageID:message.messageID,expectedInternetMessageID:message.internetMessageID,mailboxName:message.mailboxName)
                checks.append(role.rawValue + ": \(headerCount) headers across \(pageCount) bounded pages, one identity/read-state-verified body")
            } else { checks.append(role.rawValue + ": \(pageCount) empty one-day windows; body untested") }
        }
        return "PASS bounded Mail folder reads: " + checks.joined(separator:"; ") + (discovery.errors.isEmpty ? "." : ". Some account metadata unavailable; coverage partial.")
    }
    #endif

    func batch(accountID: String, window: MailWindowProgress, searchTerms: [String]? = nil, knownMessages: [MailMessage]? = nil) async throws -> MailBatch {
        var arguments: [String: Any] = ["operation": "batch", "accountID": accountID,
            "start": window.start.timeIntervalSince1970, "end": window.end.timeIntervalSince1970,
            "offset": window.offset, "limit": 20]
        if let ids = window.messageIDs { arguments["messageIDs"] = ids }
        if let name = window.mailboxName { arguments["mailboxName"] = name }
        if let role = window.mailboxRole { arguments["mailboxRole"] = role.rawValue }
        if let searchTerms { arguments["searchTerms"] = searchTerms }
        if window.messageIDs == nil, let knownMessages {
            arguments["knownMessages"] = Dictionary(knownMessages.filter { $0.accountID == accountID && $0.received >= window.start && $0.received < window.end && !$0.internetMessageID.isEmpty && $0.internetMessageID.utf8.count <= 300 }.prefix(500).map { (String($0.messageID),$0.internetMessageID) },uniquingKeysWith:{ _,new in new })
        }
        let response = try JSONDecoder().decode(MailBatch.self, from: run(arguments: arguments))
        if let error = response.errors.first { throw MailServiceError.mail(error) }
        guard let ids = response.messageIDs, let offset = response.nextOffset, let complete = response.complete,
              offset >= window.offset, offset <= ids.count, Set(ids).count == ids.count,
              response.messages.count == offset-window.offset,
              response.messages.map(\.messageID) == Array(ids[window.offset..<offset]),
              response.messages.allSatisfy({ $0.accountID == accountID && $0.received >= window.start && $0.received < window.end }),
              Set(response.retainedIDs ?? []).count == (response.retainedIDs ?? []).count,
              (response.retainedIDs ?? []).allSatisfy({ retained in !ids.contains(retained) && (knownMessages ?? []).contains { $0.accountID == accountID && $0.messageID == retained } }),
              complete == (offset == ids.count), complete || offset > window.offset else {
            throw MailServiceError.process("Mail returned incomplete batch metadata")
        }
        return response
    }

    func body(accountID: String, messageID: Int, expectedInternetMessageID: String? = nil, mailboxName: String? = nil) async throws -> String {
        var arguments: [String:Any] = [
            "operation": "body",
            "accountID": accountID,
            "messageID": messageID
        ]
        if let mailboxName { arguments["mailboxName"] = mailboxName }
        if let expectedInternetMessageID, !expectedInternetMessageID.isEmpty { arguments["expectedInternetMessageID"] = expectedInternetMessageID }
        let data = try run(arguments:arguments)
        let response = try JSONDecoder().decode(BodyResponse.self, from: data)
        if let error = response.errors.first {
            throw MailServiceError.mail(error)
        }
        if let expected = expectedInternetMessageID, !expected.isEmpty, expected != response.internetMessageID {
            throw MailServiceError.mail("This message changed or moved. Refresh the inbox before previewing it.")
        }
        guard let before = response.unreadBefore, let after = response.unreadAfter else {
            throw MailServiceError.mail("Mail read state could not be verified. No preview was returned.")
        }
        if before != after {
            throw MailServiceError.mail("Mail changed the read state during preview retrieval. Refresh Mail before continuing.")
        }
        return response.body
    }

    private func run(arguments: [String: Any]) throws -> Data {
        try Task.checkCancellation()
        guard let scriptURL, FileManager.default.isReadableFile(atPath: scriptURL.path) else {
            throw MailServiceError.scriptUnavailable
        }
        let inputData = try JSONSerialization.data(withJSONObject: arguments)
        guard let input = String(data: inputData, encoding: .utf8) else {
            throw MailServiceError.invalidInput
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", scriptURL.path, input]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Drain both pipes as the process runs so a large inbox cannot block osascript.
        let outputData = LockedData()
        let errorData = LockedData()
        let outputRead = DispatchSemaphore(value: 0)
        let errorRead = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            outputData.set(outputPipe.fileHandleForReading.readDataToEndOfFile())
            outputRead.signal()
        }
        DispatchQueue.global(qos: .utility).async {
            errorData.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            errorRead.signal()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForWriting.closeFile()
            errorPipe.fileHandleForWriting.closeFile()
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
            throw MailServiceError.launch(error.localizedDescription)
        }

        // Keep this actor's Mail bridge serial, but allow a stopped parent to
        // release its child promptly instead of holding it until the timeout.
        let deadline = DispatchTime.now() + timeout
        var interrupted = false
        while exited.wait(timeout:min(deadline,.now() + 0.1)) == .timedOut {
            if Task.isCancelled || DispatchTime.now() >= deadline {interrupted=true;break}
        }
        if interrupted {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                let killer = Process()
                killer.executableURL = URL(fileURLWithPath: "/bin/kill")
                killer.arguments = ["-KILL", String(process.processIdentifier)]
                do {
                    try killer.run()
                    killer.waitUntilExit()
                    _ = exited.wait(timeout: .now() + 2)
                } catch {
                    // Preserve the timeout result if the fallback kill command cannot launch.
                }
            }
            try Task.checkCancellation()
            throw MailServiceError.timedOut
        }
        try Task.checkCancellation()
        _ = outputRead.wait(timeout: .now() + 2)
        _ = errorRead.wait(timeout: .now() + 2)

        let stdout = outputData.get()
        let stderr = errorData.get()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw MailServiceError.process(detail.isEmpty ? "osascript exited with status \(process.terminationStatus)" : detail)
        }
        guard !stdout.isEmpty else {
            throw MailServiceError.process("osascript returned no JSON")
        }
        return stdout
    }
}

struct MailDiscovery: Decodable, Sendable {
    let accounts: [MailAccount]
    let errors: [String]
    var unavailableAccounts: [MailAccount]? = nil
    var accountErrors: [String:String]? = nil

    /// Partial discovery preserves failed identities and cached lanes without
    /// letting one account withhold the successful accounts' arrival checks.
    func collection(retaining previous: [MailAccount]) throws -> (accounts:[MailAccount], healthy:[MailAccount], failures:[String:String]) {
        let known=Dictionary((previous+(unavailableAccounts ?? [])+accounts).map{($0.id,$0)},uniquingKeysWith:{_,new in new})
        var failures=accountErrors ?? [:]
        for error in errors {
            if let id=known.keys.first(where:{error.hasPrefix("Account "+$0+":")}) {failures[id]=error}
            else if !failures.values.contains(error) {throw MailServiceError.mail(error)}
        }
        let healthy=accounts.filter{failures[$0.id] == nil}
        let retained=known.values.filter{failures[$0.id] != nil}
        let all=Dictionary((Array(retained)+healthy).map{($0.id,$0)},uniquingKeysWith:{_,new in new}).values.sorted{$0.id < $1.id}
        return (all,healthy,failures)
    }
}

private struct BodyResponse: Decodable {
    let body: String
    let internetMessageID: String
    let unreadBefore: Bool?
    let unreadAfter: Bool?
    let errors: [String]
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

enum MailServiceError: LocalizedError {
    case scriptUnavailable
    case invalidInput
    case launch(String)
    case timedOut
    case process(String)
    case mail(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "MailReader.js was not found in the app bundle."
        case .invalidInput:
            return "Could not encode the Mail request."
        case .launch(let message):
            return "Could not start Mail reader: \(message)"
        case .timedOut:
            return "Mail did not respond within 45 seconds."
        case .process(let message), .mail(let message):
            return message
        }
    }
}
