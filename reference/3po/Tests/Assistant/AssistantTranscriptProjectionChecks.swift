import Foundation
import Observation

@MainActor @Observable private final class TranscriptFixture {
    var feed: AssistantConversation
    var permitted = true
    var acknowledged = false
    var unrelated = 0
    init(_ feed: AssistantConversation) { self.feed = feed }
}
private final class TranscriptCounter: @unchecked Sendable { var value = 0 }

enum AssistantTranscriptProjectionChecks {
    @MainActor static func run() {
        let origin = Date(timeIntervalSince1970: 1_790_000_000), account = "fictional-transcript"
        var feed = AssistantConversation(accountID: account, title: "Fixture")
        feed.turns = (0..<150).map { number in .init(role: number.isMultiple(of: 3) ? "user" : "assistant", content: "Turn \(number)", completed: true, created: origin.addingTimeInterval(Double(number)*600)) }
        feed.turns[80].created = nil
        var topic = AssistantConversation(accountID: account, title: "Legacy topic")
        topic.turns = [.init(role: "user", content: "Legacy topic turn", completed: true, created: origin)]
        feed.turns.append(.init(role: "assistant", content: "Scoped", completed: true, created: origin, contextID: topic.id))
        feed.turns.append(.init(role: "assistant", content: "Interview only", completed: true, created: origin, profileSessionID: UUID()))
        let delivery = AssistantTurn(role: "assistant", content: "Source-backed delivery", completed: true, deliveryID: "discovery:fixture", created: origin.addingTimeInterval(200_000))
        feed.turns.append(delivery)
        let live = AssistantTurn(role: "assistant", content: "", completed: false, created: origin.addingTimeInterval(300_000))
        feed.turns.append(live)
        let state = TranscriptFixture(feed), cache = AssistantTranscriptProjectionCache(), calls = TranscriptCounter()
        var revision = UUID()
        func visible(_ turn: AssistantTurn) -> Bool {
            calls.value += 1
            return turn.deliveryID == nil || (state.permitted && !state.acknowledged)
        }
        func page(limit: Int = 40, selected: AssistantConversation? = nil, registration: String = account) -> AssistantTranscriptPage {
            cache.value(owner: state, revision: revision, registration: registration, feed: state.feed, topic: selected, activeTurnID: live.id, limit: limit, visible: visible)
        }
        func expected(_ selected: AssistantConversation? = nil) -> [AssistantTranscriptRow] {
            ConversationRules.transcript(ConversationRules.thread(feed: state.feed, topic: selected).filter { $0.profileSessionID == nil }, visible: { $0.deliveryID == nil || (state.permitted && !state.acknowledged) })
        }
        func same(_ actual: [AssistantTranscriptRow], _ expected: [AssistantTranscriptRow]) -> Bool {
            actual.count == expected.count && zip(actual, expected).allSatisfy { $0.turn == $1.turn && $0.separator == $1.separator }
        }
        precondition(same(page().rows, Array(expected().suffix(40))), "Sorted/paginated rows and preceding human/day separators remain exact")
        precondition(same(page(limit: 80).rows, Array(expected().suffix(80))), "Earlier history uses cached full visibility and correct preceding separators")
        precondition(cache.threadBuilds == 1 && cache.rowBuilds == 1 && calls.value == 2, "Pagination never reloads/sorts history; only displayed delivery support is revalidated")
        for number in 0..<200 {
            state.feed.turns[state.feed.turns.count-1].content = "Partial update \(number)"
            let value = page()
            precondition(value.rows.last?.turn.content == "Partial update \(number)" && value.lastVisibleTurn?.content == "Partial update \(number)")
        }
        precondition(cache.threadBuilds == 1 && cache.rowBuilds == 1 && calls.value == 202, "200 partial text updates recheck one displayed delivery, never ordinary history/separators")
        let observed = TranscriptCounter()
        withObservationTracking { _ = page() } onChange: { observed.value += 1 }
        state.permitted = false
        precondition(observed.value == 1, "Real Observation support withdrawal invalidates the presentation synchronously")
        let withdrawn = page()
        precondition(!withdrawn.rows.contains { $0.id == delivery.id } && same(withdrawn.rows, Array(expected().suffix(40))))
        precondition(cache.threadBuilds == 1 && cache.rowBuilds == 2, "Support changes rebuild visibility without sorting the transcript again")
        state.permitted = true
        precondition(page().rows.contains { $0.id == delivery.id }, "Restoring permission is re-observed after a withdrawn result")
        state.acknowledged = true
        precondition(!page().rows.contains { $0.id == delivery.id }, "Acknowledgement changes withdraw a saved delivery independently of transcript revision")
        state.acknowledged = false
        _ = page()
        let callsBefore = calls.value
        state.unrelated += 1
        _ = page()
        precondition(calls.value == callsBefore+1 && cache.threadBuilds == 1, "Unrelated state only revalidates the displayed delivery, without rebuilding history")
        precondition(page(registration: "other-account").rows.isEmpty, "Account changes cannot return cached or supplied foreign content")
        precondition(same(page(selected: topic).rows, Array(expected(topic).suffix(40))), "Legacy tagged and dedicated topic turns preserve exact sort and scope")
        _ = page()
        state.feed.turns[0].content = "Saved completed-turn correction"; revision = UUID()
        precondition(page(limit: 500).rows.contains { $0.turn.content == "Saved completed-turn correction" }, "Committed metadata/prose changes invalidate completed rows")
        state.feed.turns.append(.init(role: "user", content: "Next human", completed: true, created: origin.addingTimeInterval(400_000))); revision = UUID()
        precondition(page().lastThreadTurnID == state.feed.turns.last?.id && same(page().rows, Array(expected().suffix(40))))
        var changedCalendar = Calendar(identifier: .gregorian); changedCalendar.timeZone = TimeZone(secondsFromGMT: 12*3600)!
        let changed = cache.value(owner: state, revision: revision, registration: account, feed: state.feed, topic: nil, activeTurnID: nil, limit: 40, calendar: changedCalendar, visible: visible)
        let changedExpected = ConversationRules.transcript(ConversationRules.thread(feed: state.feed, topic: nil).filter { $0.profileSessionID == nil }, visible: { _ in true }, calendar: changedCalendar)
        precondition(same(changed.rows, Array(changedExpected.suffix(40))), "Timezone/calendar changes rebuild date separators")

        // A non-observable wall-clock expiry still cannot leave a displayed
        // source-backed row visible; a backwards clock rechecks hidden support.
        let temporal = AssistantTranscriptProjectionCache(), stamp = UUID()
        var timeAllows = true
        func temporalPage() -> AssistantTranscriptPage {
            temporal.value(owner: state, revision: stamp, registration: account, feed: state.feed, topic: nil, activeTurnID: live.id, limit: 40, visible: { _ in timeAllows })
        }
        _ = temporalPage()
        timeAllows = false
        precondition(!temporalPage().rows.contains { $0.id == delivery.id }, "Unobserved temporal expiry is checked before display")
        timeAllows = true
        precondition(temporalPage().rows.contains { $0.id == delivery.id }, "Backwards clock changes re-evaluate hidden temporal support")

        var scroll = AssistantTranscriptScrollState()
        scroll.update(distanceFromBottom: 500, userScrolling: false)
        precondition(scroll.followsBottom, "Content growth cannot detach an existing bottom follower")
        scroll.update(distanceFromBottom: 500, userScrolling: true)
        precondition(!scroll.followsBottom, "Scrolling to older messages suspends automatic following")
        scroll.update(distanceFromBottom: 700, userScrolling: false)
        precondition(!scroll.followsBottom, "Later deltas preserve the older-message reading position")
        scroll.update(distanceFromBottom: 50, userScrolling: true)
        precondition(scroll.followsBottom, "Returning near the bottom resumes following")
        scroll.update(distanceFromBottom: .infinity, userScrolling: true)
        precondition(!scroll.followsBottom); scroll.reset(); precondition(scroll.followsBottom)
        scroll.pause(); precondition(!scroll.followsBottom, "Explicit Earlier conversation reading suspends following even if the old page fitted the viewport")

        for count in [100, 1_000, 10_000] {
            var history = AssistantConversation(accountID: account, title: "Benchmark")
            history.turns = (0..<count).map { number in .init(role: number.isMultiple(of: 3) ? "user" : "assistant", content: "Saved turn \(number)", completed: true, created: origin.addingTimeInterval(Double(number)*600)) }
            history.turns[history.turns.count-1].completed = false
            let owner = TranscriptFixture(history), projection = AssistantTranscriptProjectionCache(), fixedRevision = UUID(), activeID = history.turns.last!.id
            var baseline: [Double] = []
            for _ in 0..<3 {
                let start = DispatchTime.now().uptimeNanoseconds
                let reference = ConversationRules.transcript(ConversationRules.thread(feed: history, topic: nil).filter { $0.profileSessionID == nil }, visible: { _ in true })
                baseline.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000)
                precondition(reference.count == count)
            }
            let coldStart = DispatchTime.now().uptimeNanoseconds
            let first = projection.value(owner: owner, revision: fixedRevision, registration: account, feed: history, topic: nil, activeTurnID: activeID, limit: 40, visible: { _ in true })
            let cold = Double(DispatchTime.now().uptimeNanoseconds-coldStart)/1_000_000
            precondition(first.totalCount == count && first.rows.count == min(40, count))
            var warm: [Double] = []
            for number in 0..<200 {
                history.turns[history.turns.count-1].content = "Stream \(number)"
                let start = DispatchTime.now().uptimeNanoseconds
                let value = projection.value(owner: owner, revision: fixedRevision, registration: account, feed: history, topic: nil, activeTurnID: activeID, limit: 40, visible: { _ in preconditionFailure("Ordinary deltas cannot re-evaluate history visibility") })
                warm.append(Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000)
                precondition(value.rows.last?.turn.content == "Stream \(number)")
            }
            precondition(projection.threadBuilds == 1 && projection.rowBuilds == 1)
            baseline.sort(); warm.sort()
            print(String(format: "TRANSCRIPT n=%d previous median=%.3fms cold=%.3fms streaming median=%.6fms p95=%.6fms (200 deltas; one history/separator build)", count, baseline[1], cold, warm[100], warm[189]))
        }
        print("PASS: transcript exact order/visibility/pagination/separators, real Observation withdrawal/restore, scope/metadata invalidation, 200-delta bounded projection and user-controlled bottom following")
    }
}
