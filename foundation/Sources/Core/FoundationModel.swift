import Foundation
import Observation

@MainActor @Observable final class FoundationModel {
    let preview: Bool
    let connection: ChatGPTConnection?
    private(set) var state = WorkspaceState()
    private(set) var storageBlocked = false
    var selection = "chat"
    var isRunning = false
    var liveText = ""
    var notice = ""
    @ObservationIgnored private let store: WorkspaceStore?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()

    init(preview: Bool) {
        self.preview = preview
        // This branch precedes all credential/file/network initialization.
        if preview {
            connection = nil; store = nil
            var account = AccountWorkspace()
            account.messages = [
                .init(role: "user", text: "Help me make some room for the work that matters today."),
                .init(role: "assistant", text: "Let's keep it simple. What is the one thing you'd like to have moved forward by this evening?"),
                .init(role: "user", text: "Finish the outline for my design project, and leave time for a walk."),
                .init(role: "assistant", text: "Start with a quiet hour for the outline. Pick the three points it needs to make, then write a rough first pass.\n\nAfter that, take your walk before deciding what deserves the rest of the day.")]
            account.priorities = "Finish the design project outline. Take a walk. Keep the afternoon flexible."
            account.brief = .init(text: "Make room for one meaningful piece of work.\n\nYour focus is the design project outline. Start with its three main points and aim for a useful first pass.\n\nLeave space for a walk and keep your afternoon flexible.", created: Date(timeIntervalSince1970: 1792756800))
            state.accounts["preview"] = account
        } else {
            connection = ChatGPTConnection()
            let storage = WorkspaceStore(directory: AppIdentity.dataDirectory)
            store = storage
            do { state = try storage.load() }
            catch { storageBlocked = true; notice = "Your saved workspace could not be opened. It has been preserved. " + error.localizedDescription }
        }
    }
    var accountID: String { preview ? "preview" : connection?.activeID ?? "" }
    var account: AccountWorkspace { state.accounts[accountID] ?? AccountWorkspace() }
    var messages: [ChatMessage] { account.messages }
    var brief: DailyBrief? { account.brief }
    var draft: String {
        get { account.draft }
        set { updateAccount { $0.draft = newValue } }
    }
    var priorities: String {
        get { account.priorities }
        set { updateAccount { $0.priorities = newValue } }
    }
    var ready: Bool { !preview && !storageBlocked && !isRunning && connection?.inferenceVerified == true && connection?.busy == false && connection?.usagePaused == false }
    private func updateAccount(id: String? = nil, _ update: (inout AccountWorkspace) -> Void) {
        guard !storageBlocked else { return }
        let owner = id ?? accountID
        var value = state.accounts[owner] ?? AccountWorkspace()
        update(&value); state.accounts[owner] = value
        guard let store else { return }
        do { try store.save(state) }
        catch { storageBlocked = true; notice = "Your workspace could not be saved. Further changes are paused. " + error.localizedDescription }
    }
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !text.isEmpty, text.count <= 20_000 else { return }
        updateAccount { $0.messages.append(.init(role: "user", text: text)); $0.draft = "" }
        guard !storageBlocked else { return }
        start(brief: false)
    }
    func generateBrief() { guard ready else { return }; start(brief: true) }
    func stop() { task?.cancel() }
    private func start(brief: Bool) {
        guard let connection else { return }
        let owner = accountID, model = connection.selectedModel, token = UUID()
        requestID = token; isRunning = true; liveText = ""; notice = ""
        var input = ConversationRules.context(account.messages)
        let time = Date.now.formatted(date: .complete, time: .shortened)
        var instructions = "You are \(AppIdentity.name), a helpful personal workspace assistant. Be warm, clear and concise. You have only the supplied conversation and user-entered priorities. No external sources or action tools are connected. Never claim to have read calendars, email or files, changed records, or scheduled work. Current local time is \(time), timezone \(TimeZone.current.identifier)."
        if brief {
            instructions += " Write a short daily brief using only the supplied priorities and conversation. Distinguish suggestions from commitments. Do not invent appointments, deadlines, weather or external coverage."
            input.append(["role": "user", "content": "Please write today's brief. My priorities: " + account.priorities])
        }
        let purpose: AIRequestPurpose = brief ? .brief : .conversation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.requestID == token { self.isRunning = false; self.liveText = ""; self.task = nil } }
            do {
                let response = try await connection.streamResponse(input: input, instructions: instructions,
                    model: model, purpose: purpose) { [weak self] delta in
                        guard let self, self.requestID == token, self.accountID == owner, !Task.isCancelled else { return }
                        self.liveText += delta
                    }
                try Task.checkCancellation()
                guard self.requestID == token, self.accountID == owner else { throw CancellationError() }
                self.updateAccount(id: owner) { value in
                    if brief { value.brief = .init(text: response, created: .now) }
                    else { value.messages.append(.init(role: "assistant", text: response)) }
                }
            } catch {
                guard self.requestID == token else { return }
                if !brief, !self.liveText.isEmpty {
                    let partial = self.liveText
                    self.updateAccount(id: owner) { $0.messages.append(.init(role: "assistant", text: partial, completed: false)) }
                }
                self.notice = Task.isCancelled ? "Stopped. You can send another message when ready." : error.localizedDescription
            }
        }
    }
}
