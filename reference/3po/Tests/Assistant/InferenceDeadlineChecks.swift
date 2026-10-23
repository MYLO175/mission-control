import Foundation
private final class UnfinishedStream: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Type":"text/event-stream"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("data: {\"type\":\"response.created\"}\n\n".utf8))
        // Deliberately never sends finish; no network or real credentials.
    }
    override func stopLoading() {}
}
@main struct Checks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [UnfinishedStream.self]
        let session = URLSession(configuration:config), deadline = InferenceDeadline(session:session,seconds:0.2)
        var completed = false
        do { let (bytes,_) = try await session.bytes(from:URL(string:"https://fixture.invalid/stream")!); for try await _ in bytes {}; completed = true } catch { precondition(deadline.didExpire) }
        precondition(!completed && deadline.didExpire); deadline.stop()
        let other = URLSession(configuration:.ephemeral), stopped = InferenceDeadline(session:other,seconds:0.05)
        stopped.stop(); try await Task.sleep(for:.milliseconds(100)); precondition(!stopped.didExpire); other.invalidateAndCancel()
        print("PASS: unfinished SSE terminated at total deadline; stopped/completed request does not expire. No network/credentials used.")
    }
}
