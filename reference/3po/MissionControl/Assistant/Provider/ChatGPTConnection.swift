import Foundation
import AppKit
import SwiftUI
import Observation
import Security

private struct ChatGPTRegistration: Codable, Identifiable {
    var id: String { clientID }
    var clientID: String
    var subject: String
    var email: String
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var scopes: [String]
    var expiry: Date
    var verifiedModel: String?
    var verifiedAt: Date?
}
struct ChatGPTModel: Identifiable {
    var id: String
    var name: String
}
private enum ChatGPTKeychain {
    static let query: [String:Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.mylomichael.missioncontrol.chatgpt", kSecAttrAccount as String: "registrations"]
    static func read() throws -> Data? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ChatGPTError.message("Keychain access failed (\(status)).") }
        return value as? Data
    }
    static func write(_ data: Data) throws {
        let updates = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ChatGPTError.message("Credentials could not be saved in Keychain (\(status)).") }
    }
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor @Observable final class ChatGPTConnection: PAInferenceConnection {
    var accounts: [ChatGPTAccountLabel] = []
    var activeID: String = UserDefaults.standard.string(forKey: "chatgptActiveClient") ?? ""
    var models: [ChatGPTModel] = []
    var selectedModel = UserDefaults.standard.string(forKey: "assistantModel") ?? "gpt-5.6-sol"
    var busy = false
    var message = "Not connected. The dashboard works without ChatGPT."
    var inferenceVerified = false
    var diagnostic = UserDefaults.standard.string(forKey: "chatgptLastDiagnostic") ?? ""
    private var responseRequestID: String?
    private var responseHTTPStatus = 0
    private var responseModel = ""
    @ObservationIgnored weak var usageStore: AIUsageStore?
    private var blockedAccounts = Set(UserDefaults.standard.stringArray(forKey: "chatgptBlockedAccounts") ?? []) { didSet { UserDefaults.standard.set(Array(blockedAccounts), forKey: "chatgptBlockedAccounts") } }
    var usagePaused: Bool { blockedAccounts.contains(activeID) }
    private var registrations: [ChatGPTRegistration] = []
    private var task: Task<Void, Never>?
    private var callback: ChatGPTCallback?
    private let redirectDelegate = NoRedirects()
    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 120
        return URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }()
    init() {
        do {
            if let data = try ChatGPTKeychain.read() { registrations = try JSONDecoder().decode([ChatGPTRegistration].self, from: data) }
            labels()
            if let active = current, !active.accessToken.isEmpty {
                inferenceVerified = active.verifiedModel != nil
                message = inferenceVerified ? "Subscription inference previously verified. Ready to use your plan." : "Signed in. Completed inference has not been checked this launch."
            }
        } catch { message = error.localizedDescription }
    }
    struct ChatGPTAccountLabel: Identifiable { let id: String; let name: String }
    private var current: ChatGPTRegistration? { registrations.first { $0.clientID == activeID } }
    var hasSession: Bool { !(current?.accessToken.isEmpty ?? true) }
    private func labels() {
        accounts = registrations.map { .init(id: $0.clientID, name: ($0.email.isEmpty ? "ChatGPT account" : $0.email) + " · " + String($0.clientID.suffix(6))) }
    }
    private func save(_ registration: ChatGPTRegistration, select: Bool = true) throws {
        var updated = registrations.filter { $0.clientID != registration.clientID }; updated.append(registration)
        try ChatGPTKeychain.write(JSONEncoder().encode(updated))
        registrations = updated; if select { activeID = registration.clientID }; labels()
        UserDefaults.standard.set(activeID, forKey: "chatgptActiveClient")
    }
    func switchAccount() { models = []; inferenceVerified = current?.verifiedModel != nil; message = hasSession ? "Signed in. Run the connection test for this account." : "Continue with ChatGPT to reconnect this account."; UserDefaults.standard.set(activeID, forKey: "chatgptActiveClient") }
    func cancel() { task?.cancel(); callback?.cancel() }
    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true; inferenceVerified = false
        task = Task {
            defer { busy = false; callback = nil }
            do { try await operation() }
            catch is CancellationError { message = "Cancelled. Your dashboard is still available." }
            catch { message = error.localizedDescription }
        }
    }
    private func request(_ url: String, fields: [String:String]? = nil, token: String? = nil) async throws -> Data {
        let registration = activeID
        var request = URLRequest(url: URL(string: url)!)
        if let fields { request.httpMethod = "POST"; request.httpBody = ChatGPTOAuth.form(fields); request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        responseRequestID = nil; responseHTTPStatus = 0; responseModel = ""
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse { responseRequestID = http.value(forHTTPHeaderField:"x-request-id"); responseHTTPStatus = http.statusCode }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let status=(response as? HTTPURLResponse)?.statusCode ?? 0
            let code=errorCode(data)
            if ChatGPTRecovery.terminalRefresh(code:code,status:status,grant:fields?["grant_type"]),
               let failedToken=fields?["refresh_token"], let client=fields?["client_id"],
               var rejected=registrations.first(where:{$0.clientID == client && $0.refreshToken == failedToken}) {
                // Preserve client/subject ownership so reconnect keeps transcripts and sources.
                rejected.accessToken=""; rejected.refreshToken=""; rejected.idToken=""; rejected.scopes=[]
                rejected.expiry = .distantPast; rejected.verifiedAt=nil; rejected.verifiedModel=nil
                if activeID == client { inferenceVerified=false; models=[] }
                let failure=apiError(data,status:status,registration:client)
                do { try save(rejected,select:false) }
                catch {
                    // Fail closed in this process even if Keychain refuses the update.
                    registrations.removeAll { $0.clientID == client }; registrations.append(rejected); labels()
                    throw ChatGPTError.message("ChatGPT rejected the renewable session. Local renewal is stopped, but Keychain could not save that state. Your dashboard and account identity are retained. Continue with ChatGPT to reconnect.")
                }
                throw ChatGPTError.message(failure.localizedDescription + " The unusable tokens were cleared; Continue with ChatGPT to reconnect the same account. Your chats and source choices are retained.")
            }
            throw apiError(data,status:status,registration:registration)
        }
        return data
    }
    private func errorCode(_ data: Data) -> String {
        let root=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        return (root?["error"] as? [String:Any])?["code"] as? String ?? root?["error"] as? String ?? "request_failed"
    }
    private func apiError(_ data: Data, status: Int, registration: String? = nil) -> ChatGPTError {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any]
        let error = root?["error"]
        let code = errorCode(data)
        return responseError(code, status: status, param:(error as? [String:Any])?["param"] as? String, shape:error is [String:Any] ? "HTTP error object" : root?["detail"] != nil ? "HTTP admission detail" : "HTTP other body",registration:registration)
    }
    private func responseError(_ raw: String, status: Int = 0, param: String? = nil, shape: String = "stream error", registration: String? = nil) -> ChatGPTError {
        let code = ChatGPTRecovery.safe(raw, fallback:"request_failed")
        blockedAccounts = ChatGPTRecovery.blocked(after:code,registration:registration ?? activeID,existing:blockedAccounts)
        diagnostic = "Time: \(Date.now.ISO8601Format())\nModel: \(ChatGPTRecovery.safe(responseModel))\nHTTP: \(status == 0 ? responseHTTPStatus : status)\nStage: \(shape)\nCode: \(code)\nParameter: \(ChatGPTRecovery.safe(param))\nRequest reference: \(ChatGPTRecovery.safe(responseRequestID))"
        UserDefaults.standard.set(diagnostic, forKey:"chatgptLastDiagnostic")
        return .message(ChatGPTRecovery.message(code:code,status:status) + " (" + code + "). No paid fallback or automatic retry.")
    }
    private func validateIdentity(_ token: String, client: String, nonce: String?) async throws -> [String:Any] {
        let data = try await request(ChatGPTOAuth.issuer + "/.well-known/jwks.json")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String:Any], let keys = object["keys"] as? [[String:Any]] else { throw ChatGPTError.message("Identity signing keys unavailable.") }
        return try ChatGPTOAuth.verify(token, client: client, nonce: nonce, jwks: keys)
    }
    func signIn(addAccount: Bool = false) {
        run {
            self.message = "Complete sign-in and plan permission in your browser."
            let previous = addAccount ? nil : self.current
            let state = try ChatGPTOAuth.random(), nonce = try ChatGPTOAuth.random(), verifier = try ChatGPTOAuth.random()
            let server = ChatGPTCallback(state: state); self.callback = server
            let redirect = try await server.start()
            defer { server.cancel() }
            let hostKey = "chatgptHostID"
            let host = UserDefaults.standard.string(forKey: hostKey) ?? "urn:uuid:" + UUID().uuidString.lowercased()
            UserDefaults.standard.set(host, forKey: hostKey)
            var fields = ["client_id": previous?.clientID ?? "dynamic_agent_client", "ext_agent_host_id": host, "response_type": "code", "redirect_uri": redirect.absoluteString, "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct", "resource": ChatGPTOAuth.resource, "state": state, "nonce": nonce, "code_challenge_method": "S256", "code_challenge": ChatGPTOAuth.challenge(verifier)]
            if previous == nil { fields["agent_name_hint"] = "Mission Control" }
            if let previous, !previous.idToken.isEmpty { fields["id_token_hint"] = previous.idToken }
            var authorize = URLComponents(string: ChatGPTOAuth.issuer + "/api/accounts/authorize")!
            authorize.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let url = authorize.url, NSWorkspace.shared.open(url) else { throw ChatGPTError.message("Could not open the sign-in browser.") }
            let values = try await server.wait()
            try Task.checkCancellation()
            if values["error"] != nil { throw ChatGPTError.message("ChatGPT authorization was declined. No sources have been sent.") }
            let client: String
            if let previous {
                guard values["client_id"] == nil || values["client_id"] == previous.clientID else { throw ChatGPTError.message("Callback returned a different client registration.") }; client = previous.clientID
            } else {
                guard let issued = values["client_id"], !issued.isEmpty, issued != "dynamic_agent_client" else { throw ChatGPTError.message("Registration did not return an issued client ID.") }; client = issued
            }
            guard let code = values["code"], !code.isEmpty else { throw ChatGPTError.message("Sign-in returned no authorization code.") }
            let data = try await self.request(ChatGPTOAuth.issuer + "/api/accounts/oauth/token", fields: ["grant_type":"authorization_code", "client_id":client, "code":code, "code_verifier":verifier, "redirect_uri":redirect.absoluteString, "resource":ChatGPTOAuth.resource])
            guard let tokens = try JSONSerialization.jsonObject(with: data) as? [String:Any], let idToken = tokens["id_token"] as? String, let access = tokens["access_token"] as? String, (tokens["token_type"] as? String)?.lowercased() == "bearer" else { throw ChatGPTError.message("Sign-in returned an incomplete token set.") }
            let identity = try await self.validateIdentity(idToken, client: client, nonce: nonce)
            let subject = identity["sub"] as! String
            guard previous == nil || previous?.subject == subject else { throw ChatGPTError.message("Signed-in identity does not match the selected registration.") }
            let scopes = (tokens["scope"] as? String ?? "").split(separator: " ").map(String.init)
            try self.save(.init(clientID: client, subject: subject, email: identity["email"] as? String ?? "", accessToken: access, refreshToken: tokens["refresh_token"] as? String ?? "", idToken: idToken, scopes: scopes, expiry: .now.addingTimeInterval(tokens["expires_in"] as? Double ?? 3600)))
            guard scopes.contains("chatgpt.tokens.use.direct") else { throw ChatGPTError.message("Signed in, but ChatGPT plan use was not granted. No inference has run.") }
            try await self.loadModels()
            if self.models.contains(where: { $0.id == "gpt-6.1-sol" }) { self.selectedModel = "gpt-6.1-sol"; try await self.verifyInference() }
            else { self.selectedModel = ""; self.message = "Signed in. Select an available model and test completed inference." }
        }
    }
    private func access(forceRenewal: Bool = false) async throws -> String {
        guard var account = current, !account.accessToken.isEmpty, account.scopes.contains("chatgpt.tokens.use.direct") else { throw ChatGPTError.message("Continue with ChatGPT and enable plan usage first.") }
        if forceRenewal || account.expiry.timeIntervalSinceNow < 120 {
            guard !account.refreshToken.isEmpty else { throw ChatGPTError.message("Please sign in again to renew this session.") }
            let data = try await request(ChatGPTOAuth.issuer + "/api/accounts/oauth/token", fields: ["grant_type":"refresh_token", "client_id":account.clientID, "refresh_token":account.refreshToken, "resource":ChatGPTOAuth.resource])
            guard let tokens = try JSONSerialization.jsonObject(with: data) as? [String:Any], let access = tokens["access_token"] as? String, (tokens["token_type"] as? String)?.lowercased() == "bearer" else { throw ChatGPTError.message("Session renewal returned an incomplete token set.") }
            if let id = tokens["id_token"] as? String {
                let identity = try await validateIdentity(id, client: account.clientID, nonce: nil)
                guard identity["sub"] as? String == account.subject else { throw ChatGPTError.message("Renewed identity did not match the account.") }; account.idToken = id
            }
            account.accessToken = access; account.refreshToken = tokens["refresh_token"] as? String ?? account.refreshToken
            account.expiry = .now.addingTimeInterval(tokens["expires_in"] as? Double ?? 3600)
            if let scope = tokens["scope"] as? String { account.scopes = scope.split(separator: " ").map(String.init) }
            try save(account,select:false)
            guard account.scopes.contains("chatgpt.tokens.use.direct") else { throw ChatGPTError.message("ChatGPT plan permission is no longer enabled.") }
        }
        guard activeID == account.clientID else { throw ChatGPTError.message("The selected ChatGPT account changed during renewal; no source request sent for the new account.") }
        return account.accessToken
    }
    private func loadModels() async throws {
        let registration = activeID
        let token = try await access()
        let data = try await request(ChatGPTOAuth.resource + "/models", token: token)
        guard activeID == registration else { throw ChatGPTError.message("The selected account changed; its model catalog was not replaced.") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String:Any], let list = root["models"] as? [[String:Any]] else { throw ChatGPTError.message("Account model catalog had an unexpected format.") }
        models = list.compactMap { value in guard value["visibility"] as? String == "list", let slug = value["slug"] as? String else { return nil }; return .init(id: slug, name: value["display_name"] as? String ?? slug) }
    }
    func testConnection() { run { try await self.loadModels(); try await self.verifyInference() } }
    func refreshModels() {
        guard !busy else { return };busy=true
        task=Task {
            defer { busy=false }
            do { try await loadModels();message="Account model list refreshed. Your selected model is unchanged; no inference request was made." }
            catch { message=error.localizedDescription }
        }
    }
    #if DEBUG
    /// Explicit diagnostic, before source startup. Never changes the selected/verified model.
    func inspectLunaAccess() async throws->[String:Any] {
        guard !busy,!usagePaused,hasSession else { throw ChatGPTError.message("Account access is unavailable or busy.") }
        let selected=selectedModel,registration=activeID
        busy=true;defer {busy=false}
        try await loadModels()
        guard selectedModel == selected,activeID == registration else {throw ChatGPTError.message("Account/model changed during the check.")}
        var result:[String:Any]=["checked":Date.now.ISO8601Format(),"requested":"gpt-6-luna","selectedModel":selected,"offered":models.map(\.id),"listed":models.contains{$0.id == "gpt-6-luna"},"completedInference":false,"personalSourcesSent":false]
        if models.contains(where:{$0.id == "gpt-6-luna"}) {
            let reply=try await performResponse(input:[["role":"user","content":"Reply with exactly: Luna access works."]],instructions:nil,model:"gpt-6-luna",effort:"medium",purpose:.connectionCheck,onDelta:nil)
            result["completedInference"]=true;result["reply"]=reply
        }
        return result
    }
    #endif
    func renewSession() { run {
        _ = try await self.access(forceRenewal: true)
        self.inferenceVerified = self.current?.verifiedModel != nil
        self.message = "Session renewed and saved in Keychain. Your source settings are unchanged."
    } }
    private func verifyInference() async throws {
        guard models.contains(where: { $0.id == selectedModel }) else { throw ChatGPTError.message("Choose an available model before testing.") }
        let registration = activeID, model = selectedModel
        message = "Checking completed inference with \(model)…"
        _ = try await performResponse(input: [["role":"user", "content":"Reply with exactly: Mission Control connection works."]], instructions: nil, model: model, effort: "medium", purpose: .connectionCheck, onDelta: nil)
        guard activeID == registration, selectedModel == model, var account = current else { throw ChatGPTError.message("The active account or model changed; verification was not transferred.") }
        account.verifiedModel = model; account.verifiedAt = .now
        try save(account)
        UserDefaults.standard.set(selectedModel, forKey: "assistantModel")
        blockedAccounts.remove(activeID)
        inferenceVerified = true; message = "Completed subscription inference verified with \(selectedModel). Personal sources were not sent."
    }
    func streamResponse(input: [[String:String]], instructions: String, model: String? = nil, effort: String = "medium", purpose: AIRequestPurpose = .conversation, onDelta: @escaping (String) -> Void) async throws -> String {
        guard !busy else { throw ChatGPTError.message("Another ChatGPT operation is in progress.") }
        guard !usagePaused else { throw ChatGPTError.message("Subscription requests are paused after a usage failure. Use Check access in Settings once access is available.") }
        guard hasSession, inferenceVerified else { throw ChatGPTError.message("Verify completed subscription inference in Settings first.") }
        busy = true
        defer { busy = false }
        let registration = activeID, requestedModel = model ?? selectedModel
        if models.isEmpty { try await loadModels() }
        guard activeID == registration else { throw ChatGPTError.message("The selected account changed before inference; no source request sent.") }
        guard ["low", "medium", "high"].contains(effort), models.contains(where: { $0.id == requestedModel }) else { throw ChatGPTError.message("The selected model or reasoning level is unavailable. Check Settings.") }
        return try await performResponse(input: input, instructions: instructions, model: requestedModel, effort: effort, purpose: purpose, onDelta: onDelta)
    }
    func toolResponse(input: [[String:Any]], instructions: String, tools: [[String:Any]], model: String, purpose: AIRequestPurpose = .conversation, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        try await toolResponse(input: input, instructions: instructions, tools: tools, model: model, effort: "medium", purpose: purpose, onDelta: onDelta)
    }
    func toolResponse(input: [[String:Any]], instructions: String, tools: [[String:Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        guard !busy, !usagePaused, hasSession, inferenceVerified else { throw ChatGPTError.message("Subscription access is unavailable or another request is in progress.") }
        busy = true; defer { busy = false }
        let registration = activeID
        if models.isEmpty { try await loadModels() }
        guard activeID == registration, models.contains(where:{ $0.id == model }), ["low", "medium", "high"].contains(effort) else { throw ChatGPTError.message("The selected account/model or reasoning level is unavailable.") }
        return try await performToolResponse(input:input,instructions:instructions,model:model,effort:effort,tools:tools,purpose:purpose,onDelta:onDelta)
    }
    private func performResponse(input: [[String:String]], instructions: String?, model: String, effort: String, purpose: AIRequestPurpose = .conversation, onDelta: ((String) -> Void)?) async throws -> String {
        try await performToolResponse(input:input.map { $0 as [String:Any] },instructions:instructions,model:model,effort:effort,tools:[],purpose:purpose,onDelta:onDelta).text
    }
    private func performToolResponse(input: [[String:Any]], instructions: String?, model: String, effort: String, tools: [[String:Any]], purpose: AIRequestPurpose = .conversation, onDelta: ((String) -> Void)?) async throws -> PAResponse {
        #if DEBUG
        let requestClock = ProcessInfo.processInfo.systemUptime
        #endif
        let registration = activeID
        let token = try await access()
        guard activeID == registration else { throw ChatGPTError.message("The selected account changed before inference; no source request sent.") }
        var request = URLRequest(url: URL(string: ChatGPTOAuth.resource + "/responses")!)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String:Any] = ["model":model, "input":input, "store":false, "stream":true, "reasoning":["effort":effort]]
        // Stable opaque accounting/routing hint; no prompt prose or credentials in the key.
        // The provider still controls cache residency and may report a miss.
        body["prompt_cache_key"] = "3po:" + ChatGPTOAuth.challenge("prompt-prefix-v1:" + registration + ":" + model + ":" + purpose.rawValue)
        if let instructions, !instructions.isEmpty { body["instructions"] = instructions }
        if !tools.isEmpty {
            body["tools"] = tools; body["parallel_tool_calls"] = false
            body["include"] = ["reasoning.encrypted_content"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        responseRequestID = nil; responseHTTPStatus = 0; responseModel = model
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120; configuration.timeoutIntervalForResource = 180
        let inferenceSession = URLSession(configuration:configuration,delegate:NoRedirects(),delegateQueue:nil)
        let deadline = InferenceDeadline(session:inferenceSession)
        defer { deadline.stop(); inferenceSession.invalidateAndCancel() }
        let usageID = usageStore?.begin(registration: registration, model: model, purpose: purpose)
        do {
        #if DEBUG
        let streamClock=ProcessInfo.processInfo.systemUptime
        let requestSetupSeconds=streamClock-requestClock
        #endif
        let (bytes, response) = try await inferenceSession.bytes(for: request)
        #if DEBUG
        let responseHeadersSeconds=ProcessInfo.processInfo.systemUptime-streamClock
        #endif
        if let http = response as? HTTPURLResponse { responseRequestID = http.value(forHTTPHeaderField:"x-request-id"); responseHTTPStatus = http.statusCode }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            var data = Data(); for try await byte in bytes { if data.count < 8192 { data.append(byte) } else { break } }
            throw apiError(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0,registration:registration)
        }
        var stream = ChatGPTStream(allowsTools:!tools.isEmpty)
        #if DEBUG
        var firstDelta:Double?,lastDelta:Double?,callbackSeconds=0.0,deltaCount=0
        #endif
        do {
            let text = try await stream.read(from: bytes, validate: {
                guard activeID == registration else { throw ChatGPTError.message("The selected account changed; the old response was stopped.") }
            }, onDelta: { delta in
                #if DEBUG
                let arrived=ProcessInfo.processInfo.systemUptime
                if firstDelta == nil {firstDelta=arrived-streamClock}
                lastDelta=arrived-streamClock;deltaCount += 1
                #endif
                onDelta?(delta)
                #if DEBUG
                callbackSeconds += ProcessInfo.processInfo.systemUptime-arrived
                #endif
            })
            usageStore?.finish(usageID, outcome: .completed, tokens: stream.reportedTokens, httpStatus: responseHTTPStatus)
            #if DEBUG
            if let flag=ProcessInfo.processInfo.arguments.firstIndex(of:"--stream-profile-path"),ProcessInfo.processInfo.arguments.indices.contains(flag+1) {
                let path=ProcessInfo.processInfo.arguments[flag+1]
                let report:[String:Any] = ["model":model,"effort":effort,"toolCount":(tools.first?["tools"] as? [[String:Any]])?.count ?? 0,"requestSetupSeconds":requestSetupSeconds,"responseHeadersSeconds":responseHeadersSeconds,"streamSeconds":ProcessInfo.processInfo.systemUptime-streamClock,"firstDeltaSeconds":firstDelta as Any? ?? NSNull(),"lastDeltaSeconds":lastDelta as Any? ?? NSNull(),"callbackSeconds":callbackSeconds,"deltaCount":deltaCount,"inputTokens":stream.reportedTokens?.input as Any? ?? NSNull(),"outputTokens":stream.reportedTokens?.output as Any? ?? NSNull()]
                if path.hasPrefix("/private/tmp/"),let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]) {try? data.write(to:URL(fileURLWithPath:path),options:.atomic)}
            }
            #endif
            return PAResponse(text:text,output:stream.output,calls:stream.calls)
        } catch let failure as ChatGPTStream.Failure {
            switch failure {
            case .failed(let code):
                if responseRequestID == nil { responseRequestID = stream.responseID }
                throw responseError(code, param:stream.errorParam,registration:registration)
            case .incomplete: throw ChatGPTError.message("Inference was incomplete. Partial output is not a completed response.")
            case .interrupted: throw ChatGPTError.message("Stream ended without completed, nonempty inference." + (tools.isEmpty ? "" : " Tool transport: " + stream.diagnostic))
            case .invalid: throw ChatGPTError.message("Invalid response stream event.")
            case .oversized: throw ChatGPTError.message("Response stream event exceeded its safety limit.")
            }
        }
        } catch {
            usageStore?.finish(usageID, outcome: Task.isCancelled || activeID != registration ? .interrupted : .failed, httpStatus: responseHTTPStatus)
            if deadline.didExpire { throw ChatGPTError.message("The subscription response exceeded three minutes without completing. Partial output was not accepted; no automatic retry or paid fallback. Try again once when ready.") }
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    func signOut() {
        run {
            guard var account = self.current else { return }
            var revoked = false
            if !account.refreshToken.isEmpty {
                do {
                    let discovery = try await self.request(ChatGPTOAuth.issuer + "/.well-known/openid-configuration")
                    let root = try JSONSerialization.jsonObject(with: discovery) as? [String:Any]
                    if let endpoint = root?["revocation_endpoint"] as? String, let url = URL(string: endpoint), url.scheme == "https", url.host == "auth.openai.com" {
                        _ = try await self.request(endpoint, fields: ["token":account.refreshToken, "token_type_hint":"refresh_token", "client_id":account.clientID]); revoked = true
                    }
                } catch { /* Clear locally and explicitly report unconfirmed remote revocation. */ }
            }
            account.accessToken = ""; account.refreshToken = ""; account.idToken = ""; account.scopes = []; account.expiry = .distantPast; account.verifiedModel = nil; account.verifiedAt = nil
            try self.save(account); self.models = []
            self.message = revoked ? "Signed out; renewable session revoked." : "Signed out locally. Remote revocation was not confirmed; disconnect 3PO in ChatGPT Settings if needed."
        }
    }
}

struct ChatGPTConnectionView: View {
    @Bindable var connection: ChatGPTConnection
    var body: some View {
        Section("ChatGPT account") {
            if !connection.accounts.isEmpty {
                Picker("Account", selection: $connection.activeID) { ForEach(connection.accounts) { Text($0.name).tag($0.id) } }.disabled(connection.busy).onChange(of: connection.activeID) { connection.switchAccount() }
            }
            Text("3PO uses the documented ChatGPT sign-in and subscription connection. The explicit access check sends one short, source-free inference request. No API key or separate API billing is used.").font(.caption)
            Text(connection.message).font(.callout).textSelection(.enabled).id(connection.message)
            if !connection.models.isEmpty { Picker("Model", selection: $connection.selectedModel) { Text("Select model").tag(""); ForEach(connection.models) { Text($0.name).tag($0.id) } }.disabled(connection.busy).onChange(of: connection.selectedModel) { UserDefaults.standard.set(connection.selectedModel, forKey: "assistantModel") } }
            HStack {
                Button("Continue with ChatGPT") { connection.signIn() }.disabled(connection.busy)
                if !connection.accounts.isEmpty { Button("Add account") { connection.signIn(addAccount: true) }.disabled(connection.busy) }
            }
            HStack {
                Button("Refresh models · no AI") { connection.refreshModels() }.disabled(connection.busy || !connection.hasSession)
                Button("Check account access · 1 request") { connection.testConnection() }.disabled(connection.busy || !connection.hasSession)
                Button("Renew session") { connection.renewSession() }.disabled(connection.busy || !connection.hasSession)
                Button("Sign out") { connection.signOut() }.disabled(connection.busy || !connection.hasSession)
                if connection.busy { ProgressView().controlSize(.small); Button("Cancel") { connection.cancel() } }
            }
            if connection.usagePaused { Text("The last subscription request was rejected, so background AI is paused. Check access makes one source-free inference request.").font(.caption).foregroundStyle(.orange) }
            if !connection.diagnostic.isEmpty {
                VStack(alignment:.leading,spacing:6) {
                    Text("Last failure details").font(.caption.weight(.semibold))
                    Text(connection.diagnostic).font(.caption).textSelection(.enabled)
                    Button("Copy failure details") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(connection.diagnostic,forType:.string) }
                    Text("Contains only time, model, error fields and request reference. No credentials, prompts or personal sources.").font(.caption)
                }
            }
            Link("Manage usage and app access in ChatGPT",destination:URL(string:"https://chatgpt.com/settings/usage")!)
            Text("Availability and limits are set by your ChatGPT account. A completed access check confirms that subscription inference is available to 3PO now.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
