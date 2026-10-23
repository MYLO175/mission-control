import Foundation
import Observation

/// One additive local authority; saving/restoring creates history rather than rewriting earlier versions.
@MainActor @Observable final class ReviewPolicyStore {
    private struct State: Codable, Equatable {var schema = 1; var versions: [ReviewPolicyVersion] = []}
    private var state = State()
    private(set) var readable = true
    private(set) var error: String?
    @ObservationIgnored private let load: () throws -> Data?
    @ObservationIgnored private let persist: ((Data, Data?) throws -> Void)?
    var writable: Bool {readable && persist != nil}
    init(load: @escaping () throws -> Data?, persist: ((Data, Data?) throws -> Void)?) {
        self.load = load; self.persist = persist
        do {if let data = try load() {state = try Self.decode(data)}}
        catch {readable = false; self.error = "Saved Review policy could not be read. Original records are preserved; editing and new Review assessment are unavailable."}
    }
    private static func decode(_ data: Data) throws -> State {
        let value = try JSONDecoder().decode(State.self, from: data)
        guard value.schema == 1, Set(value.versions.map(\.id)).count == value.versions.count,
              value.versions.allSatisfy({!$0.registration.isEmpty && ReviewPolicyRules.validText($0.text)}) else {throw SummaryFailure.invalid}
        return value
    }
    func policy(_ registration: String) -> ReviewPolicyCapture {
        state.versions.last(where: {$0.registration == registration})?.capture ?? .init(registration: registration, revision: ReviewPolicyRules.defaultRevision, text: ReviewPolicyRules.defaultText, isDefault: true)
    }
    func matches(_ capture: ReviewPolicyCapture) -> Bool {readable && policy(capture.registration) == capture}
    func history(_ registration: String) -> [ReviewPolicyVersion] {Array(state.versions.filter {$0.registration == registration}.reversed())}
    @discardableResult func save(_ text: String, registration: String, expected: ReviewPolicyCapture, reset: Bool = false, restoredFrom: UUID? = nil) -> Bool {
        guard writable, let persist else {error = error ?? "Review policy storage is unavailable."; return false}
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !registration.isEmpty, expected.registration == registration, matches(expected) else {error = "The account or Review policy changed. Reopen it before saving."; return false}
        guard ReviewPolicyRules.validText(trimmed) else {error = "Write a Review policy of at most \(ReviewPolicyRules.textLimit) characters."; return false}
        if let restoredFrom, !history(registration).contains(where: {$0.id == restoredFrom && $0.text == trimmed}) {error = "That Review policy version is unavailable."; return false}
        var next = state
        next.versions.append(.init(registration: registration, text: trimmed, isDefault: reset, restoredFrom: restoredFrom))
        var persisted = false
        do {
            // Check on-disk ownership before overwriting an independently saved version.
            let originalData = try load()
            let current = try originalData.map(Self.decode) ?? State()
            guard current == state else {state = current; error = "The saved Review policy changed. Reopen it before saving."; return false}
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(next)
            try persist(data, originalData)
            persisted = true
            guard try load() == data else {readable = false; error = "Review policy save needs checking. Reopen the app before editing it again."; return false}
            state = next; error = nil; return true
        } catch {if persisted {readable = false}; self.error = "Review policy could not be saved. Your text is still here."; return false}
    }
    @discardableResult func reset(_ registration: String, expected: ReviewPolicyCapture) -> Bool {
        save(ReviewPolicyRules.defaultText, registration: registration, expected: expected, reset: true)
    }
    @discardableResult func restore(_ version: ReviewPolicyVersion, expected: ReviewPolicyCapture) -> Bool {
        guard history(expected.registration).contains(version), version.registration == expected.registration else {error = "That Review policy version belongs to a different account or is unavailable."; return false}
        return save(version.text, registration: expected.registration, expected: expected, reset: version.isDefault, restoredFrom: version.id)
    }
}
