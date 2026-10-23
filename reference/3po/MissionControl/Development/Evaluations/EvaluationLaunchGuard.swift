import Foundation

/// Checked before creating any dashboard/services. A Release or old candidate
/// cannot silently turn an intended diagnostic into personal application startup.
enum EvaluationLaunchGuard {
    enum Decision: Equatable { case proceed; case exit(code: Int32, output: String) }
    static let protocolVersion = 1
    static let modes: [[String]] = [
        ["--validate-review-inbox","--working-context-model"],
        ["--validate-review-inbox","--working-context-model","--context-pages-only"],
        ["--validate-memory-inspection", "--prompt-cache-only", "--warm-boundary-only"],
        ["--validate-review-inbox","--reminder-completion-native"],
        ["--validate-review-inbox","--chat-approval-only"],
        ["--preview-chat-approval"],
        ["--validate-review-inbox","--email-work-only","--retirement-contract"],
        [
                "--validate-advice-context"
        ],
        [
                "--validate-review-inbox",
                "--scheduler-only"
        ],
        [
                "--validate-review-inbox",
                "--calendar-removal-only"
        ],
        [
                "--validate-review-inbox",
                "--calendar-removal-only",
                "--removal-native"
        ],
        [
                "--validate-commitment-reports"
        ],
        [
                "--validate-review-inbox",
                "--email-resolution-only"
        ],
        [
                "--validate-native-memory"
        ],
        [
                "--validate-review-inbox",
                "--relevance-only"
        ],
        [
                "--validate-review-inbox",
                "--calendar-removal-only",
                "--removal-model"
        ]
]
    private static let primaryFlags: Set<String> = [
        "--preview-chat-approval",
        "--inspect-luna-access",
        "--cleanup-request-markers",
        "--preview-calendar-drag",
        "--preview-images",
        "--preview-life-and-plans",
        "--preview-memory-inspection",
        "--preview-memory-review",
        "--preview-projects",
        "--preview-review-inbox",
        "--preview-review-conversation",
        "--preview-settings",
        "--preview-source-timeline",
        "--render-life-map",
        "--render-projects",
        "--render-weather",
        "--validate-advice-context",
        "--validate-clean-notes",
        "--validate-commitment-reports",
        "--validate-focus-workflow",
        "--validate-images",
        "--validate-life-notebook",
        "--validate-live",
        "--validate-mail-dates",
        "--validate-mail-monitoring",
        "--validate-memory-inspection",
        "--validate-native-capabilities",
        "--validate-native-editors",
        "--validate-native-memory",
        "--validate-ownership",
        "--validate-placement",
        "--validate-projects",
        "--validate-review-inbox",
        "--validate-source-context",
        "--validate-source-timeline"
]
    static func decision(arguments: [String], isDebug: Bool) -> Decision {
        if arguments.contains("--evaluation-handshake") {
            let value: [String: Any] = ["protocol": protocolVersion, "debug": isDebug,
                "bundleID": "com.mylomichael.missioncontrol", "modes": isDebug ? modes : []]
            guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let output = String(data: data, encoding: .utf8) else {
                return .exit(code: 70, output: "Evaluation handshake could not be encoded.\n")
            }
            return .exit(code: 0, output: output + "\n")
        }
        let requested = arguments.filter { $0.hasPrefix("--validate-") || $0.hasPrefix("--preview-") || $0.hasPrefix("--render-") || $0.hasPrefix("--evaluation-") || $0.hasPrefix("--inspect-") || $0.hasPrefix("--cleanup-") }
        guard !requested.isEmpty else { return .proceed }
        guard isDebug else { return .exit(code: 64, output: "Developer evaluation requires a DEBUG candidate; no application services started.\n") }
        guard requested.count == 1, let flag = requested.first, primaryFlags.contains(flag) else {
            return .exit(code: 64, output: "Unknown or conflicting developer mode; no application services started.\n")
        }
        return .proceed
    }
}
