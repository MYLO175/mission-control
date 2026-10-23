import Foundation

struct PAFunctionCall {
    var id: String
    var name: String
    var namespace: String?
    var arguments: String
}
struct PAResponse {
    var text: String
    var output: [[String:Any]]
    var calls: [PAFunctionCall]
}
struct ChatGPTStream {
    var allowsTools = false
    private(set) var output: [[String:Any]] = []
    private(set) var calls: [PAFunctionCall] = []
    enum Failure: Error { case invalid, oversized, failed(String), incomplete, interrupted }
    private(set) var text = ""
    private(set) var errorParam: String?
    private(set) var responseID: String?
    private(set) var reportedTokens: AIReportedTokens?
    private var completed = false
    /// Only the fully validated terminal response ends transport. Item completion
    /// and [DONE] alone never authorise text acceptance or tool execution.
    var responseCompleted: Bool { completed }
    private var finishedItems: [(Int,[String:Any])] = []
    private var eventKinds: [String] = []
    var diagnostic: String { "completed=\(completed), events=" + eventKinds.suffix(12).joined(separator:",") + ", output=" + output.compactMap { $0["type"] as? String }.joined(separator:",") }
    private var eventData: [String] = []
    private var byteLine = Data()
    private var sawCR = false
    /// The response.completed event is the transport boundary; an SSE connection
    /// may remain open afterwards. Validate ownership once more before acceptance.
    @MainActor mutating func read<Bytes: AsyncSequence>(from bytes: Bytes, validate: () throws -> Void,
                                                       onDelta: (String) -> Void) async throws -> String where Bytes.Element == UInt8 {
        for try await value in bytes {
            try Task.checkCancellation()
            try validate()
            if let delta = try byte(value) { onDelta(delta) }
            if responseCompleted { break }
        }
        try Task.checkCancellation()
        try validate()
        return try finishBytes()
    }
    // SSE framing uses ASCII CR/LF, never Unicode separators inside JSON strings.
    mutating func byte(_ value: UInt8) throws -> String? {
        if value == 10 && sawCR { sawCR = false; return nil }
        if value == 10 || value == 13 {
            sawCR = value == 13
            guard let text = String(data:byteLine,encoding:.utf8) else { throw Failure.invalid }
            byteLine.removeAll(keepingCapacity:true)
            return try line(text)
        }
        sawCR = false
        byteLine.append(value)
        guard byteLine.count <= 1_000_000 else { throw Failure.oversized }
        return nil
    }
    mutating func finishBytes() throws -> String {
        if !byteLine.isEmpty {
            guard let text = String(data:byteLine,encoding:.utf8) else { throw Failure.invalid }
            byteLine.removeAll()
            _ = try line(text)
        }
        return try finish()
    }
    mutating func line(_ line: String) throws -> String? {
        if line.isEmpty { return try consume() }
        guard line.hasPrefix("data:") else { return nil }
        eventData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        let payload = eventData.joined(separator: "\n")
        guard payload.utf8.count <= 1_000_000 else { throw Failure.oversized }
        if payload == "[DONE]" { return try consume() }
        if let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) { return try consume(parsed: event) }
        return nil
    }
    private mutating func consume(parsed: Any? = nil) throws -> String? {
        guard !eventData.isEmpty else { return nil }
        let payload = eventData.joined(separator: "\n"); eventData = []
        if payload == "[DONE]" { return nil }
        guard let event = (parsed ?? (try? JSONSerialization.jsonObject(with:Data(payload.utf8)))) as? [String:Any], let type = event["type"] as? String else { throw Failure.invalid }
        if let response = event["response"] as? [String:Any], let id = response["id"] as? String { responseID = id }
        if type.count < 100, type.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "_" || $0 == ".") }) { eventKinds.append(type); if eventKinds.count > 12 { eventKinds.removeFirst() } }
        switch type {
        case "response.output_text.delta":
            guard !completed, let delta = event["delta"] as? String else { throw Failure.invalid }
            text += delta; return delta
        case "response.output_item.done":
            if allowsTools {
                guard !completed, let item = event["item"] as? [String:Any], let index = event["output_index"] as? Int, index >= 0,
                      !finishedItems.contains(where:{ $0.0 == index }), finishedItems.count < 32 else { throw Failure.invalid }
                finishedItems.append((index,item))
            }
        case "response.completed":
            guard !completed else { throw Failure.invalid }
            reportedTokens = AIReportedTokens.parse((event["response"] as? [String:Any])?["usage"])
            let terminalItems = (event["response"] as? [String:Any])?["output"] as? [[String:Any]] ?? []
            let items = terminalItems.isEmpty && allowsTools ? finishedItems.sorted { $0.0 < $1.0 }.map { $0.1 } : terminalItems
            if !items.isEmpty {
                guard try JSONSerialization.data(withJSONObject:items).count <= 1_000_000 else { throw Failure.oversized }
                output = items
                for item in items where item["type"] as? String == "function_call" {
                    guard allowsTools, item["status"] as? String == "completed",
                          let id = item["call_id"] as? String, !id.isEmpty,
                          let name = item["name"] as? String, !name.isEmpty,
                          let arguments = item["arguments"] as? String, arguments.utf8.count <= 32_000,
                          (try? JSONSerialization.jsonObject(with:Data(arguments.utf8))) is [String:Any],
                          !calls.contains(where:{ $0.id == id }), calls.count < 12 else { throw Failure.invalid }
                    calls.append(.init(id:id,name:name,namespace:item["namespace"] as? String,arguments:arguments))
                }
                let finalText = items.filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String:Any]] ?? [] }.compactMap { $0["text"] as? String }.joined()
                // Completed output is authoritative even if the provider sent only
                // part of the message through output_text.delta events.
                if !finalText.isEmpty { text = finalText }
            }
            completed = true
        case "response.failed", "error":
            let root = event["response"] as? [String:Any] ?? event
            let error = root["error"] as? [String:Any] ?? root
            errorParam = error["param"] as? String
            throw Failure.failed(error["code"] as? String ?? "response_failed")
        case "response.incomplete": throw Failure.incomplete
        default: break
        }
        return nil
    }
    mutating func finish() throws -> String {
        _ = try consume()
        guard completed, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (allowsTools && !calls.isEmpty) else { throw Failure.interrupted }
        return text
    }
}
