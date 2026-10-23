import Foundation

/// Only the documented quota code proves a subscription-limit rejection.
/// A generic 429 or usage-check outage must not permanently latch quota state.
enum ChatGPTRecovery {
    static func terminalRefresh(code: String, status: Int, grant: String?) -> Bool {
        guard grant == "refresh_token", (400..<500).contains(status) else { return false }
        return ["invalid_grant","invalid_refresh_token","token_expired","refresh_token_expired","refresh_token_invalidated","refresh_token_reused"].contains(code)
    }
    static func quota(_ code: String) -> Bool { code == "subscription_sharing_usage_limit_exceeded" }
    static func blocked(after code: String, registration: String, existing: Set<String>) -> Set<String> {
        guard quota(code), !registration.isEmpty else { return existing }
        return existing.union([registration])
    }
    static func safe(_ value: String?, fallback: String = "unavailable") -> String {
        guard let value, !value.isEmpty, value.count <= 160,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-.[]".contains($0)) }) else { return fallback }
        return value
    }
    static func message(code: String, status: Int) -> String {
        if quota(code) { return "OpenAI rejected 3PO's ChatGPT plan allowance. This does not prove your whole plan is empty. Check the selected account's app limit in ChatGPT Usage, then Check access after it resets or changes." }
        if code == "server_is_overloaded" { return "ChatGPT is temporarily overloaded. Try again later. Your session is retained; this is not confirmed subscription quota exhaustion." }
        if code == "subscription_sharing_usage_unavailable" || code == "subscription_sharing_user_unavailable" || status == 503 { return "OpenAI could not check subscription access or the service is temporarily unavailable. Your session is retained. Try again later; this is not confirmed quota exhaustion." }
        if status == 429 { return "OpenAI temporarily rate-limited this request. Try again later. This is not confirmed subscription quota exhaustion." }
        if code.contains("not_eligible") { return "This account or workspace is not eligible for ChatGPT plan usage. The dashboard remains available." }
        if status == 401 || code == "invalid_grant" { return "The subscription session was rejected. Check the selected account and renew the session in Settings." }
        return "ChatGPT request failed. The dashboard remains available."
    }
}
