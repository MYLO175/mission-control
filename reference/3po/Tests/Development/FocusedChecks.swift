import Foundation

@main struct FocusedChecks {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        func event(_ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
            .init(id: "id", calendarID: "source", title: "Test", start: start, end: end, allDay: allDay, location: "", sourceLabel: "Test")
        }
        let dstDay = date(2026, 10, 25)
        assert(DateRules.day(dstDay, calendar: calendar).duration == 25*3600)
        let springDay = date(2026, 3, 29)
        assert(DateRules.day(springDay, calendar: calendar).duration == 23*3600)
        let overnight = event(date(2026, 10, 24, 23), date(2026, 10, 25, 2))
        assert(DateRules.overlaps(overnight, day: date(2026, 10, 24), calendar: calendar))
        assert(DateRules.overlaps(overnight, day: dstDay, calendar: calendar))
        assert(!DateRules.overlaps(overnight, day: date(2026, 10, 26), calendar: calendar))
        let allDay = event(dstDay, date(2026, 10, 26), allDay: true)
        assert(DateRules.overlaps(allDay, day: dstDay, calendar: calendar))
        assert(!DateRules.overlaps(allDay, day: date(2026, 10, 26), calendar: calendar))
        let zeroLength = event(date(2026, 10, 25, 12), date(2026, 10, 25, 12))
        assert(DateRules.overlaps(zeroLength, day: dstDay, calendar: calendar))
        assert(DateRules.occurrenceID("recurring", start: dstDay) != DateRules.occurrenceID("recurring", start: date(2026, 10, 26)))
        func reminder(_ id: String, _ due: Date?, timed: Bool = false) -> TaskItem {
            .init(id: id, listID: "list", title: "Duplicate title", due: due, hasTime: timed, sourceLabel: "Test", writable: true, recurring: false)
        }
        let now = date(2026, 10, 25, 12)
        let early = reminder("1", date(2026, 10, 25, 10), timed: true)
        let today = reminder("2", dstDay)
        let future = reminder("3", date(2026, 10, 26))
        let undated = reminder("4", nil)
        assert(DateRules.group(early, now: now, calendar: calendar) == "Overdue")
        assert(DateRules.group(today, now: now, calendar: calendar) == "Today")
        assert(DateRules.group(future, now: now, calendar: calendar) == "Upcoming")
        assert(DateRules.group(undated, now: now, calendar: calendar) == "Undated")
        assert(DateRules.ordered([undated, future, early, today]).map(\.id) == ["2", "1", "3", "4"])
        assert(Set([early, today].map(\.id)).count == 2)
        do { try SampleReminderService().complete(id: "task"); assertionFailure("Sample read-only source must reject writes") }
        catch IntegrationError.readOnly { }
        let fixture = #"{"messages":[{"id":"a:1","accountID":"a","account":"Example","messageID":1,"internetMessageID":"id@example.invalid","sender":"Test","subject":"Test","received":"2026-10-01T12:00:00.000Z","unread":true,"replied":false,"flagged":true}],"accounts":[{"id":"a","title":"Example"}],"errors":[]}"#.data(using: .utf8)!
        let mail = try JSONDecoder().decode(MailSnapshot.self, from: fixture)
        let restored = try JSONDecoder().decode(MailSnapshot.self, from: JSONEncoder().encode(mail))
        assert(restored.messages[0].received == mail.messages[0].received)
        assert(restored.messages[0].unread && restored.messages[0].flagged)
        let partial = MailSnapshot(messages: [], accounts: [MailAccount(id: "a", title: "Example")], errors: ["Account a: timed out"])
        let retained = partial.retainingFailedAccounts(from: mail, now: Date(timeIntervalSince1970: 1790942400))
        assert(retained.messages.map(\.id) == ["a:1"])
        let successEmpty = MailSnapshot(messages: [], accounts: mail.accounts, errors: [])
        assert(successEmpty.retainingFailedAccounts(from: mail).messages.isEmpty, "Successful empty account must remove disappeared messages")
        assert(partial.retainingFailedAccounts(from: mail, now: Date(timeIntervalSince1970: 1794000000)).messages.isEmpty, "Expired stale data must leave the 30-day window")
        let isolated = FileManager.default.temporaryDirectory.appendingPathComponent("missioncontrol-isolated-\(UUID()).js")
        let encoded = String(data: try JSONEncoder().encode(mail), encoding: .utf8)!
        let isolatedScript = """
        function run(argv) {
            var input = JSON.parse(argv[0]);
            if (input.operation === 'body') return JSON.stringify({body:'Fixture',internetMessageID:'other@example.invalid',unreadBefore:true,unreadAfter:true,errors:[]});
            if (input.operation === 'probe') return JSON.stringify({accounts: [{id:'a',title:'Example'},{id:'b',title:'Failed account'}], errors:[]});
            if (input.accountID === 'b') { delay(2); return '{}'; }
            return JSON.stringify(\(encoded));
        }
        """
        try isolatedScript.write(to: isolated, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: isolated) }
        let isolatedService = MailService(scriptURL: isolated, timeout: 0.7)
        do {
            _ = try await isolatedService.body(accountID: "a", messageID: 1, expectedInternetMessageID: "expected@example.invalid")
            assertionFailure("Preview must reject mismatched message identity")
        } catch MailServiceError.mail(let detail) { assert(detail.contains("changed or moved")) }
        let isolatedResult = try await isolatedService.headers()
        assert(isolatedResult.messages.count == 1 && isolatedResult.accounts.count == 2)
        assert(isolatedResult.timedOut == true && isolatedResult.errors.first?.hasPrefix("Account b:") == true)
        let oldSource = try JSONDecoder().decode(SourceOption.self, from: Data(#"{"id":"old","title":"To do","account":"Example","writable":true}"#.utf8))
        assert(oldSource.color == nil, "Old source caches must still decode")
        let batchNow = date(2026, 10, 2, 12)
        var indexing = MailIndexState()
        indexing.prepare(accounts: mail.accounts, now: batchNow, calendar: calendar)
        let window = indexing.windows.first { $0.start <= mail.messages[0].received && $0.end > mail.messages[0].received }!
        func fixtureMessage(_ id: Int) throws -> MailMessage {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(mail.messages[0])) as! [String: Any]
            json["id"] = "a:\(id)"; json["messageID"] = id
            return try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: json))
        }
        let prior = MailSnapshot(messages: [try fixtureMessage(3)], accounts: mail.accounts, errors: [])
        let firstPage = MailBatch(messages: mail.messages, messageIDs: [1,2], nextOffset: 1, complete: false, errors: [])
        let partialPage = indexing.apply(firstPage, to: window.id, snapshot: prior, now: batchNow)
        assert(Set(partialPage.messages.map(\.id)) == ["a:1", "a:3"], "Partial pages must not erase unvisited cached rows")
        indexing = try JSONDecoder().decode(MailIndexState.self, from: JSONEncoder().encode(indexing))
        let resumed = indexing.windows.first { $0.id == window.id }!
        assert(resumed.offset == 1 && resumed.messageIDs == [1,2] && resumed.seenIDs == ["a:1"])
        let secondPage = MailBatch(messages: [try fixtureMessage(2)], messageIDs: [1,2], nextOffset: 2, complete: true, errors: [])
        let finished = indexing.apply(secondPage, to: window.id, snapshot: partialPage, now: batchNow)
        assert(Set(finished.messages.map(\.id)) == ["a:1", "a:2"], "Complete window must remove disappeared messages")
        var dstIndex = MailIndexState()
        dstIndex.prepare(accounts: mail.accounts, now: date(2026, 10, 25, 12), calendar: calendar)
        assert(dstIndex.windows.contains { $0.start == dstDay && $0.end.timeIntervalSince($0.start) == 25*3600 })
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("missioncontrol-timeout-\(UUID()).js")
        try "function run(argv) { delay(10); return '{}'; }".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let service = MailService(scriptURL: tmp, timeout: 0.1)
        do { _ = try await service.headers(); assertionFailure("Timeout must fail") }
        catch MailServiceError.timedOut { }
        catch { throw error }
        print("PASS: DST/overnight/all-day/zero duration, occurrence identity, reminder grouping/order/duplicate identity, read-only write rejection, Mail cache round-trip/unread flags, helper timeout/account isolation/cache reconciliation/preview identity, persisted batch resume/reconciliation/DST windows/old source caches.")
    }
}
