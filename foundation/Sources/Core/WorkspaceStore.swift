import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: String
    var text: String
    var created = Date.now
    var completed = true
}
struct DailyBrief: Codable {
    var text: String
    var created: Date
}
struct AccountWorkspace: Codable {
    var messages: [ChatMessage] = []
    var draft = ""
    var priorities = ""
    var brief: DailyBrief?
}
struct WorkspaceState: Codable {
    var schemaVersion = 1
    var accounts: [String: AccountWorkspace] = [:]
}
enum WorkspaceFailure: LocalizedError {
    case unsupported, oversized
    var errorDescription: String? {
        switch self {
        case .unsupported: "This workspace uses an unsupported format. Its file has been preserved."
        case .oversized: "This workspace is too large to open safely. Its file has been preserved."
        }
    }
}
struct WorkspaceStore {
    let directory: URL
    var file: URL { directory.appendingPathComponent("workspace.json") }
    func load() throws -> WorkspaceState {
        guard FileManager.default.fileExists(atPath: file.path) else { return WorkspaceState() }
        let data = try Data(contentsOf: file)
        guard data.count <= 16_000_000 else { throw WorkspaceFailure.oversized }
        let state = try JSONDecoder().decode(WorkspaceState.self, from: data)
        guard state.schemaVersion == 1 else { throw WorkspaceFailure.unsupported }
        return state
    }
    func save(_ state: WorkspaceState) throws {
        guard state.schemaVersion == 1 else { throw WorkspaceFailure.unsupported }
        let data = try JSONEncoder().encode(state)
        guard data.count <= 16_000_000 else { throw WorkspaceFailure.oversized }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
enum ConversationRules {
    static func context(_ messages: [ChatMessage]) -> [[String: String]] {
        var selected: [ChatMessage] = [], characters = 0
        for message in messages.suffix(40).reversed() where message.completed && ["user", "assistant"].contains(message.role) {
            if characters + message.text.count > 60_000 { break }
            selected.append(message); characters += message.text.count
        }
        return selected.reversed().map { ["role": $0.role, "content": $0.text] }
    }
}
