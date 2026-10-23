import Foundation
import Network

/// Loopback only. Never writes authorization codes or callback URLs to logs.
final class ChatGPTCallback: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MissionControl.oauth.callback")
    private var listener: NWListener?
    private var waiter: CheckedContinuation<[String:String], Error>?
    private var result: Result<[String:String], Error>?
    private var startResolved = false // confined to queue
    private let state: String
    init(state: String) { self.state = state }
    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { status in
                switch status {
                case .ready: if !self.startResolved, let port = listener.port { self.startResolved = true; continuation.resume(returning: port) }
                case .failed(let error): if !self.startResolved { self.startResolved = true; continuation.resume(throwing: error) }; self.finish(.failure(ChatGPTError.message("The sign-in listener failed.")))
                case .cancelled: if !self.startResolved { self.startResolved = true; continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                self.receive(connection, accumulated: Data())
                self.queue.asyncAfter(deadline: .now()+10) { connection.cancel() }
            }
            listener.start(queue: queue)
        }
        queue.asyncAfter(deadline: .now()+300) { self.finish(.failure(ChatGPTError.message("Sign-in timed out. Continue with ChatGPT to try again."))) }
        return URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!
    }
    func wait() async throws -> [String:String] {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { if let result = self.result { continuation.resume(with: result) } else { self.waiter = continuation } }
            }
        }, onCancel: { self.cancel() })
    }
    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }
    private func finish(_ value: Result<[String:String], Error>) {
        guard result == nil else { return }
        result = value; listener?.cancel(); waiter?.resume(with: value); waiter = nil
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, complete, error in
            let buffer = accumulated + (data ?? Data())
            guard error == nil, buffer.count <= 16384 else { connection.cancel(); return }
            if let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") {
                let pieces = (text.components(separatedBy: "\r\n").first ?? "").split(separator: " ")
                var values: [String:String]?
                if pieces.count == 3, pieces[0] == "GET", pieces[1].hasPrefix("/auth/callback?"),
                   let url = URL(string: "http://127.0.0.1" + pieces[1]) { values = try? ChatGPTOAuth.query(url, expectedState: self.state) }
                let success = values != nil
                let body = success ? "3PO received your sign-in. You can return to the app." : "Invalid sign-in callback. Return to 3PO and try again."
                let reply = "HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                if let values { self.finish(.success(values)) }
            } else if !complete { self.receive(connection, accumulated: buffer) }
            else { connection.cancel() }
        }
    }
}
