import Foundation
@main struct Checks {
    @MainActor static func main() async throws {
        assert(ChatGPTRecovery.quota("subscription_sharing_usage_limit_exceeded"))
        let first = ChatGPTRecovery.blocked(after:"subscription_sharing_usage_limit_exceeded",registration:"request-account",existing:[])
        assert(first == ["request-account"] && !first.contains("new-active-account"))
        assert(ChatGPTRecovery.blocked(after:"rate_limit_exceeded",registration:"request-account",existing:[]) == [])
        assert(ChatGPTRecovery.blocked(after:"subscription_sharing_usage_limit_exceeded",registration:"",existing:[]) == [])
        assert(!ChatGPTRecovery.quota("subscription_sharing_usage_unavailable"))
        assert(!ChatGPTRecovery.quota("rate_limit_exceeded"))
        assert(!ChatGPTRecovery.quota("server_is_overloaded"))
        assert(ChatGPTRecovery.blocked(after:"server_is_overloaded",registration:"request-account",existing:[]) == [])
        for status in [0,200,429,503] {assert(ChatGPTRecovery.message(code:"server_is_overloaded",status:status).contains("ChatGPT is temporarily overloaded"))}
        assert(ChatGPTRecovery.message(code:"rate_limit_exceeded",status:429).contains("not confirmed"))
        assert(ChatGPTRecovery.message(code:"subscription_sharing_usage_unavailable",status:503).contains("session is retained"))
        assert(ChatGPTRecovery.safe("req_test-123") == "req_test-123")
        assert(ChatGPTRecovery.safe("Bearer private token") == "unavailable")
        for code in ["invalid_grant","invalid_refresh_token","token_expired","refresh_token_expired","refresh_token_invalidated","refresh_token_reused"] {
            assert(ChatGPTRecovery.terminalRefresh(code:code,status:400,grant:"refresh_token"))
            assert(!ChatGPTRecovery.terminalRefresh(code:code,status:503,grant:"refresh_token"))
            assert(!ChatGPTRecovery.terminalRefresh(code:code,status:400,grant:"authorization_code"))
        }
        for code in ["invalid_client","subscription_sharing_usage_limit_exceeded","subscription_sharing_usage_unavailable","request_failed"] {
            assert(!ChatGPTRecovery.terminalRefresh(code:code,status:401,grant:"refresh_token"))
        }
        var quotaFailure = ChatGPTStream()
        do {
            _ = try quotaFailure.line(#"data: {"type":"response.failed","response":{"id":"resp_test123","error":{"code":"subscription_sharing_usage_limit_exceeded","param":"model"}}}"#)
            assertionFailure("Quota failure must throw")
        } catch ChatGPTStream.Failure.failed(let code) {
            assert(code == "subscription_sharing_usage_limit_exceeded")
            assert(quotaFailure.errorParam == "model")
            assert(quotaFailure.responseID == "resp_test123")
        }
        var stream = ChatGPTStream()
        let ignored = try stream.line("event: response.output_text.delta"); assert(ignored == nil)
        let delta = try stream.line(#"data: {"type":"response.output_text.delta","delta":"Hello"}"#)
        assert(delta == "Hello")
        _ = try stream.line(#"data: {"type":"response.completed"}"#)
        _ = try stream.line("data: [DONE]")
        let result = try stream.finish(); assert(result == "Hello")
        for lines in [[], [#"data: {"type":"response.output_text.delta","delta":"Partial"}"#], [#"data: {"type":"response.completed"}"#], [#"data: {"type":"response.incomplete"}"#], [#"data: {"type":"response.failed","response":{"error":{"code":"usage_limit_reached"}}}"#], ["data: malformed", ""]] {
            var failed = ChatGPTStream(); var rejected = false
            do { for line in lines { _ = try failed.line(line) }; _ = try failed.finish() } catch { rejected = true }
            assert(rejected, "Must reject interrupted, empty, incomplete, failed or malformed streams")
        }
        var multiline = ChatGPTStream()
        _ = try multiline.line(#"data: {"type":"response.output_text.delta","delta":"#)
        _ = try multiline.line(#"data: "Two lines"}"#)
        _ = try multiline.line(#"data: {"type":"response.completed"}"#)
        let multi = try multiline.finish(); assert(multi == "Two lines")
        let unicode = "A\u{2028}B\u{2029}C\u{0085}D £ 🛰️"
        let payload = String(data:try JSONSerialization.data(withJSONObject:["type":"response.output_text.delta","delta":unicode]),encoding:.utf8)!
        for separator in ["\n","\r\n","\r"] {
            var framed = ChatGPTStream()
            let wire = "data: " + payload + separator + separator + "data: {\"type\":\"response.completed\"}" + separator + separator
            var deltas = ""
            for byte in wire.utf8 { if let value = try framed.byte(byte) { deltas += value } }
            let completed = try framed.finishBytes()
            assert(deltas == unicode && completed == unicode)
        }
        var badUTF8 = ChatGPTStream(), invalidUTF8Rejected = false
        do { _ = try badUTF8.byte(255); _ = try badUTF8.byte(10) } catch { invalidUTF8Rejected = true }
        assert(invalidUTF8Rejected)
        var counted = ChatGPTStream()
        _ = try counted.line(#"data: {"type":"response.output_text.delta","delta":"Answer"}"#)
        _ = try counted.line(#"data: {"type":"response.created","response":{"usage":{"input_tokens":999,"output_tokens":1,"total_tokens":1000}}}"#)
        assert(counted.reportedTokens == nil, "Only completed-response metadata counts")
        _ = try counted.line(#"data: {"type":"response.completed","response":{"usage":{"input_tokens":100,"output_tokens":20,"total_tokens":120,"input_tokens_details":{"cached_tokens":40},"output_tokens_details":{"reasoning_tokens":12}}}}"#)
        let countedAnswer = try counted.finish(); assert(countedAnswer == "Answer")
        assert(counted.reportedTokens == .init(input:100,output:20,total:120,cachedInput:40,reasoningOutput:12))
        var badCounts = ChatGPTStream()
        _ = try badCounts.line(#"data: {"type":"response.output_text.delta","delta":"Valid answer"}"#)
        _ = try badCounts.line(#"data: {"type":"response.completed","response":{"usage":{"input_tokens":true,"output_tokens":20,"total_tokens":21}}}"#)
        let uncountedAnswer = try badCounts.finish(); assert(uncountedAnswer == "Valid answer" && badCounts.reportedTokens == nil, "Bad optional counts must not reject an answer")
        // Real production reader, with a deliberately open SSE tail (no EOF).
        var openTail: AsyncStream<UInt8>.Continuation!
        let openBytes=AsyncStream<UInt8> { openTail=$0 }
        defer { openTail.finish() }
        let terminalWire=#"data: {"type":"response.output_text.delta","delta":"Partial"}"#+"\n\n"+#"data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"text":"Authoritative final"}]}],"usage":{"input_tokens":10,"output_tokens":4,"total_tokens":14}}}"#+"\n\n"
        for byte in terminalWire.utf8 {openTail.yield(byte)}
        var reader=ChatGPTStream(),partials="",ownershipChecks=0
        let openAnswer=try await reader.read(from:openBytes,validate:{ownershipChecks += 1},onDelta:{partials += $0})
        assert(openAnswer == "Authoritative final" && partials == "Partial" && reader.responseCompleted && ownershipChecks > 1)
        assert(reader.reportedTokens?.output == 4,"Completion accepts exact terminal usage before HTTP EOF")
        for revoke in [false,true] {
            var continuation:AsyncStream<UInt8>.Continuation!
            let bytes=AsyncStream<UInt8> {continuation=$0}
            let incompleteWire=#"data: {"type":"response.output_text.delta","delta":"Partial"}"#+"\n\n"+#"data: [DONE]"#+"\n\n"
            for byte in incompleteWire.utf8 {continuation.yield(byte)}
            continuation.finish()
            var candidate=ChatGPTStream(),owned=true,rejected=false
            do {_=try await candidate.read(from:bytes,validate:{if !owned {throw CancellationError()}},onDelta:{_ in if revoke {owned=false}})} catch {rejected=true}
            assert(rejected && !candidate.responseCompleted,"Missing completion and ownership withdrawal cannot accept a partial response")
        }
        print("PASS: SSE deltas, terminal completion, multiline events, interruption, failed/incomplete/empty/malformed rejection")
    }
}
