import Foundation

enum PAEngineToolResult {
    case output(String, succeeded: Bool)
    case stopped
}
enum PAEngineResult {
    case completed(String)
    case stopped
}

/// Foreground transport and tool rounds, independent of views, native sources and
/// storage. The caller supplies owned context, inference and verified execution.
@MainActor final class PAConversationEngine {
    typealias Inference = ([[String: Any]], @escaping (String) -> Void) async throws -> PAResponse
    typealias Execution = (PAFunctionCall) async throws -> PAEngineToolResult

    func run(base: [[String: Any]], allowedTools: Set<String>? = nil,
             valid: @escaping () -> Bool, invalidationReason: () -> String = {"the request context changed"}, receipts: () -> [String],
             streamingAllowed: @escaping () -> Bool = { true },
             infer: Inference, execute: Execution,
             progress: (String) -> Void, partial: @escaping (String) -> Void,
             toolRound: () -> Void, attempted: (PAFunctionCall) -> Void,
             toolFinished: () -> Void) async throws -> PAEngineResult {
        var run = PAForegroundRun(), firstRound = true
        while true {
            try Task.checkCancellation()
            guard valid() else { throw ActionFailure.message("The request stopped because \(invalidationReason()). Remaining work was stopped.") }
            let input = try run.input(base: base, receipts: receipts())
            progress(firstRound ? "Thinking…" : "Working on your request…")
            firstRound = false
            var text = ""
            var acceptingDeltas = true
            var streamingRevoked = false
            let response: PAResponse
            do {
                response = try await infer(input) { delta in
                    guard acceptingDeltas, !Task.isCancelled, !streamingRevoked else { return }
                    // Provisional display checks ownership/access only. Full evidence
                    // validation runs at inference and tool boundaries, not per word.
                    guard streamingAllowed() else { streamingRevoked = true; return }
                    text += delta; partial(text)
                }
                acceptingDeltas = false
            } catch {
                acceptingDeltas = false
                throw error
            }
            try Task.checkCancellation()
            guard !streamingRevoked else { throw ActionFailure.message("The reply stopped because its account, storage or source access changed. No new tool executed.") }
            guard valid() else { throw ActionFailure.message("The request stopped because \(invalidationReason()). No new tool executed.") }
            if response.calls.isEmpty { return .completed(response.text) }
            var items = response.output, results: [[String: Any]] = [], successes = 0
            toolRound()
            for call in response.calls {
                try Task.checkCancellation()
                guard valid() else { throw ActionFailure.message("The request stopped because \(invalidationReason()). Remaining work was stopped.") }
                try run.accept(call)
                if let allowedTools, !allowedTools.contains(call.name) {
                    throw ActionFailure.message("That action is unavailable in memory setup. Use your PA chat for tasks.")
                }
                progress("Using " + call.name.replacingOccurrences(of: "_", with: " ") + "…")
                attempted(call)
                let output: String
                switch try await execute(call) {
                case .stopped: return .stopped
                case .output(let value, let succeeded):
                    output = value
                    if succeeded { successes += 1 }
                }
                guard valid() else { throw ActionFailure.message("The request stopped because \(invalidationReason()). Check any saved receipt before repeating.") }
                items.append(["type": "function_call_output", "call_id": call.id, "output": output])
                results.append(["name": call.name, "arguments": (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8))) ?? call.arguments, "output": output])
                toolFinished()
            }
            try run.finish(items, results: results, successes: successes)
        }
    }
}
