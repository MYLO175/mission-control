import Foundation

/// Human-owned feature instructions. These never grant source access or permission to act.
struct ReviewPolicyCapture: Codable, Equatable {
    var registration: String
    var revision: String
    var text: String
    var isDefault: Bool
    var input: [String: String] {
        ["registration": registration, "revision": revision, "text": text, "origin": isDefault ? "3PO default" : "Human-edited Review policy"]
    }
}
struct ReviewPolicyVersion: Codable, Equatable, Identifiable {
    var id = UUID()
    var registration: String
    var text: String
    var isDefault: Bool
    var created = Date.now
    var restoredFrom: UUID? = nil
    var capture: ReviewPolicyCapture {
        .init(registration: registration, revision: id.uuidString, text: text, isDefault: isDefault)
    }
}
struct ReviewPolicyReference: Codable, Equatable {
    var registration: String
    var revision: String
    init(_ capture: ReviewPolicyCapture) {registration = capture.registration; revision = capture.revision}
    func matches(_ capture: ReviewPolicyCapture) -> Bool {registration == capture.registration && revision == capture.revision}
}
/// Exact policy and human Review preferences actually supplied, including quiet/negative decisions.
struct EmailReviewContextReceipt: Codable, Equatable {
    var policy: ReviewPolicyReference
    var preferences: [MemoryDependency]
    // Discovery may notice newly relevant preferences without replacing the exact receipts above.
    var discoveryRevision: String?
    var contextPageDependencies: [String: String]? = nil
    init(policy: ReviewPolicyCapture, memories: [[String: String]], discoveryRevision: String?, contextPageDependencies: [String: String]? = nil) {
        self.policy = .init(policy)
        preferences = MemoryDependencyRules.capture(memories.filter {$0["purpose"] == "review preference"})
        self.discoveryRevision = discoveryRevision
        self.contextPageDependencies = contextPageDependencies
    }
}
struct EmailPolicyRelevance: Codable, Equatable {
    var reason: String
    var policyQuote: String
    var sourceQuote: String
    var policy: ReviewPolicyReference?
}
