import Foundation

@main struct ConversationEngineChecks {
    @MainActor static func main() async throws {
        var checked = 0
        func check(_ value: Bool) { checked += 1; precondition(value, "Engine contract \(checked) failed") }
        let base: [[String: Any]] = [["role": "user", "content": "Fictional request"]]
        func call(_ id: String, _ argument: Int = 0, name: String = "read_memory") -> PAFunctionCall {
            .init(id: id, name: name, namespace: "pa", arguments: "{\"offset\":\(argument)}")
        }
        func tools(_ value: PAFunctionCall) -> PAResponse {
            .init(text: "", output: [["type":"reasoning", "encrypted_content":"fictional-opaque"], ["type":"function_call", "call_id":value.id, "name":value.name, "arguments":value.arguments]], calls: [value])
        }
        var requested = 0, executed = 0, attempts = 0, finished = 0
        var deltas: [String] = [], receipts: [String] = [], replayed = false
        var oldDelta: ((String) -> Void)?
        let engine = PAConversationEngine()
        var fullChecks=0,lightChecks=0,displayed=0
        _ = try await engine.run(base:base,valid:{fullChecks += 1;return true},receipts:{[]},streamingAllowed:{lightChecks += 1;return true},infer:{_,delta in
            for _ in 0..<500 {delta("word ")}
            return .init(text:"Authoritative completed reply",output:[],calls:[])
        },execute:{_ in check(false);return .stopped},progress:{_ in},partial:{_ in displayed += 1},toolRound:{},attempted:{_ in},toolFinished:{})
        check(fullChecks == 2 && lightChecks == 500 && displayed == 500)
        var streamAccess=true,afterRevocation=0
        do {
            _ = try await engine.run(base:base,valid:{true},receipts:{[]},streamingAllowed:{streamAccess},infer:{_,delta in
                delta("Visible");streamAccess=false;delta("Hidden");streamAccess=true;delta("Still hidden")
                return tools(call("must-not-run"))
            },execute:{_ in afterRevocation += 1;return .stopped},progress:{_ in},partial:{_ in},toolRound:{},attempted:{_ in},toolFinished:{})
            check(false)
        } catch {check(afterRevocation == 0)}
        let result = try await engine.run(base: base, valid: { true }, receipts: { receipts }, infer: { input, delta in
            requested += 1
            if requested == 1 { oldDelta = delta; delta("Provisional"); return tools(call("first")) }
            oldDelta?("Late earlier round")
            replayed = input.contains { $0["encrypted_content"] as? String == "fictional-opaque" } && input.contains { $0["type"] as? String == "function_call_output" && $0["call_id"] as? String == "first" }
            delta("Partial final"); return .init(text: "Completed final", output: [], calls: [])
        }, execute: { _ in executed += 1; receipts.append("Verified fixture receipt"); return .output("fixture output", succeeded: true) }, progress: { _ in }, partial: { deltas.append($0) }, toolRound: {}, attempted: { _ in attempts += 1 }, toolFinished: { finished += 1 })
        if case .completed(let text) = result { check(text == "Completed final") } else { check(false) }
        check(requested == 2 && executed == 1 && attempts == 1 && finished == 1)
        check(replayed && deltas == ["Provisional", "Partial final"])
        oldDelta?("Late completed request")
        check(deltas == ["Provisional", "Partial final"])

        var owned = true; executed = 0
        do {
            _ = try await engine.run(base: base, valid: { owned }, invalidationReason: {"the selected AI model changed"}, receipts: { [] }, infer: { _, _ in owned = false; return tools(call("late")) }, execute: { _ in executed += 1; return .output("wrong", succeeded: true) }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
            check(false)
        } catch { check(executed == 0 && error.localizedDescription.contains("the selected AI model changed") && error.localizedDescription.contains("No new tool executed")) }

        requested = 0; executed = 0
        let stopped = try await engine.run(base: base, valid: { true }, receipts: { [] }, infer: { _, _ in requested += 1; return tools(call("question")) }, execute: { _ in executed += 1; return .stopped }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
        if case .stopped = stopped { check(requested == 1 && executed == 1) } else { check(false) }

        executed = 0
        do {
            _ = try await engine.run(base: base, allowedTools: ["read_memory"], valid: { true }, receipts: { [] }, infer: { _, _ in tools(call("write", name: "change_calendar")) }, execute: { _ in executed += 1; return .output("wrong", succeeded: true) }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
            check(false)
        } catch { check(executed == 0 && error.localizedDescription.contains("memory setup")) }

        executed = 0
        do {
            _ = try await engine.run(base: base, valid: { true }, receipts: { [] }, infer: { _, _ in tools(call("duplicate")) }, execute: { _ in executed += 1; return .output("same", succeeded: true) }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
            check(false)
        } catch { check(executed == 1 && error.localizedDescription.contains("repeated tool call")) }

        requested = 0; executed = 0
        do {
            _ = try await engine.run(base: base, valid: { true }, receipts: { [] }, infer: { _, _ in requested += 1; return tools(call("loop-\(requested)")) }, execute: { _ in executed += 1; return .output("unchanged", succeeded: false) }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
            check(false)
        } catch { check(executed == 3 && error.localizedDescription.contains("without making progress")) }

        requested = 0; executed = 0
        let long = try await engine.run(base: base, valid: { true }, receipts: { [] }, infer: { _, _ in
            requested += 1
            return requested <= 70 ? tools(call("distinct-\(requested)", requested)) : .init(text: "All 70 complete", output: [], calls: [])
        }, execute: { value in executed += 1; return .output(value.arguments, succeeded: true) }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
        if case .completed(let text) = long { check(executed == 70 && requested == 71 && text == "All 70 complete") } else { check(false) }

        let cancelled = Task { @MainActor in
            _ = try await engine.run(base: base, valid: { true }, receipts: { [] }, infer: { _, _ in try Task.checkCancellation(); return tools(call("cancelled")) }, execute: { _ in check(false); return .stopped }, progress: { _ in }, partial: { _ in }, toolRound: {}, attempted: { _ in }, toolFinished: {})
        }
        cancelled.cancel()
        do { try await cancelled.value; check(false) } catch is CancellationError { check(true) }
        print("Conversation engine: \(checked)/\(checked) contracts passed without a dashboard, native sources, storage, model or credentials.")
    }
}
