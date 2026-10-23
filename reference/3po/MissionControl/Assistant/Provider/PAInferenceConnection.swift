import Foundation

/// Foreground and learning inference state, independent of credentials, settings UI
/// and the transport implementation. The production connection owns those details.
@MainActor protocol PAInferenceConnection: AnyObject {
    var activeID: String { get }
    var selectedModel: String { get }
    var busy: Bool { get }
    var usagePaused: Bool { get }
    var inferenceVerified: Bool { get }
    var hasSession: Bool { get }
    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse
}

extension PAInferenceConnection {
    /// Existing implementations retain their normal effort unless they support an explicit level.
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        try await toolResponse(input: input, instructions: instructions, tools: tools, model: model, purpose: purpose, onDelta: onDelta)
    }
    func streamResponse(input: [[String: String]], instructions: String, model: String? = nil, effort: String = "medium", purpose: AIRequestPurpose = .conversation, onDelta: @escaping (String) -> Void) async throws -> String {
        try await streamResponse(input: input, instructions: instructions, model: model, effort: effort, purpose: purpose, onDelta: onDelta)
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose = .conversation, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        try await toolResponse(input: input, instructions: instructions, tools: tools, model: model, purpose: purpose, onDelta: onDelta)
    }
}
