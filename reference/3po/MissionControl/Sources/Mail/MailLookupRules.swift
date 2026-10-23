import Foundation

struct MailLookupPlan: Codable {
    var message: String
    var terms: [String]?
    var start: String?
    var end: String?
}
enum MailLookupRules {
    static func roles(_ request: String) -> Set<MailFolderRole> {
        let value = request.lowercased()
        var roles: Set<MailFolderRole> = []
        if value.range(of:#"\b(?:sent (?:mail|emails?|messages?|folder|mailbox)|(?:i|we) (?:have )?(?:sent|emailed))\b"#,options:.regularExpression) != nil { roles.insert(.sent) }
        if value.range(of:#"\barchiv(?:e|es|ed)\b"#,options:.regularExpression) != nil { roles.insert(.archive) }
        if value.range(of:#"\binbox\b"#,options:.regularExpression) != nil { roles.insert(.inbox) }
        return roles.isEmpty ? [.inbox,.sent,.archive] : roles
    }
    static func answerRequest(original: String) -> String {
        "Answer this original mail question using the newly retrieved search evidence: \(original). The app has already performed this bounded search. Explain the findings and remaining coverage; do not treat this as a request to operate Mail yourself."
    }
    static func retriesUnavailable(_ request: String) -> Bool {
        request.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".!")) == "retry unavailable mail reads"
    }
    static func retryRequested(_ request: String) -> Bool {
        request.range(of:#"\b(?:retry|try again|search again|check again|have another go)\b"#,options:[.regularExpression,.caseInsensitive]) != nil
    }
    static func continues(_ request: String) -> Bool {
        retriesUnavailable(request) || request.lowercased().contains("continue") && requested(request)
    }
    static func requested(_ request: String) -> Bool {
        if retriesUnavailable(request) { return true }
        let value = request.lowercased()
        let mail = value.range(of:#"\b(?:email|emails|mail|inbox)\b"#,options:.regularExpression) != nil || value.range(of:#"\b(?:i|we) (?:have )?(?:sent|emailed)\b"#,options:.regularExpression) != nil
        return mail && value.range(of:#"\b(?:find|search|old|earlier|last|when|what|look|continue)\b"#,options:.regularExpression) != nil
    }
    static func terms(_ plan: MailLookupPlan, request: String) throws -> [String] {
        guard !request.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, let terms = plan.terms, !terms.isEmpty, terms.count <= 5,
              terms.allSatisfy({ $0.trimmingCharacters(in:.whitespacesAndNewlines).count >= 2 && $0.count <= 80 && !["email","emails","mail","inbox","find","search","old","earlier","last","the","from","to","sent","archive","archived"].contains($0.lowercased()) }) else {
            throw ActionFailure.message("Choose one to five meaningful Mail search keywords. This is an app search-plan validation error; Apple Mail has not been queried.")
        }
        // Read-only search can correct spelling and expand a topic. Literal
        // current-human evidence remains mandatory for writes, not header reads.
        return terms.map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
    }
    static func matches(_ message: MailMessage, terms: [String]) -> Bool {
        terms.contains { term in message.subject.localizedCaseInsensitiveContains(term) || message.sender.localizedCaseInsensitiveContains(term) || (message.mailboxRole == .sent && (message.recipients ?? []).contains(where:{ $0.localizedCaseInsensitiveContains(term) })) }
    }
}
