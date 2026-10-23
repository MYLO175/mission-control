import SwiftUI
import AppKit

struct AIUsageView: View {
    @Bindable var model: DashboardModel
    @State private var window: AIUsageWindow = .today
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let store = model.aiUsage
            let records = store.records(registration: model.chatGPT.activeID, window: window, now: timeline.date)
            let summary = AIUsageRules.summary(records)
            Form {
            Section("3PO activity") {
                Picker("Show", selection: $window) { ForEach(AIUsageWindow.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                LabeledContent("AI calls started", value: summary.calls.formatted())
                LabeledContent("Completed", value: summary.completed.formatted())
                LabeledContent("Failed / stopped", value: "\(summary.failed) / \(summary.interrupted)")
                if summary.running > 0 { LabeledContent("In progress", value: summary.running.formatted()) }
                Text("One message or background review can use several AI calls, including tool follow-ups and action checks. These are calls made by 3PO for the selected account; they do not show ChatGPT or Codex activity.").font(.caption).foregroundStyle(.secondary)
                Text("Tracking began " + store.state.trackingStarted.formatted(date: .abbreviated, time: .shortened) + ". Earlier activity is not reconstructed.").font(.caption).foregroundStyle(.secondary)
                if let date = store.state.truncatedBefore, date >= window.start(now: timeline.date) { Text("Some older calls in this range were removed by the local retention limit; totals are partial.").font(.caption).foregroundStyle(.orange) }
                if let error = store.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("What used those calls") {
                if records.isEmpty { Text("No recorded calls in this range.").foregroundStyle(.secondary) }
                ForEach(AIRequestPurpose.allCases.filter { purpose in records.contains { $0.purpose == purpose } }) { purpose in
                    LabeledContent(purpose.title, value: records.filter { $0.purpose == purpose }.count.formatted())
                }
            }
            Section("Reported model usage") {
                if summary.reportedCalls > 0 {
                    LabeledContent("Input tokens", value: summary.input.formatted())
                    LabeledContent("Output tokens", value: summary.output.formatted())
                    LabeledContent("Total reported tokens", value: summary.total.formatted())
                    Text("Reported for \(summary.reportedCalls) of \(summary.calls) calls. Missing counts are unknown, including interrupted calls. Tokens measure processed text, images and generated output; they are not a percentage of your subscription allowance.").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Token details") {
                        LabeledContent("Cached input (included above)", value: summary.cachedReportedCalls == 0 ? "Not reported" : summary.cachedInput.formatted())
                        LabeledContent("Input prepared for cache (included above)", value: summary.cacheWriteReportedCalls == 0 ? "Not reported" : summary.cacheWriteInput.formatted())
                        Text("Cache reads reported for \(summary.cachedReportedCalls) calls; cache writes for \(summary.cacheWriteReportedCalls). Missing cache counts are unknown. Prepared input is not proof that a later request reused it.").font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Reasoning output (included above)", value: summary.reasoningOutput.formatted())
                    }
                } else { Text("The provider has not reported token counts for these calls. Call counts are still available.").foregroundStyle(.secondary) }
            }
            Section("Your ChatGPT allowance") {
                Text("This connection does not provide a verified remaining-allowance percentage. Open ChatGPT Usage for account-wide limits and available controls. Local call limits control 3PO's work; they are separate from your plan allowance.").font(.callout)
                Button("Manage ChatGPT usage") { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/settings/usage")!) }
                if model.chatGPT.usagePaused { Text("New AI requests are paused after an allowance failure. Source collection and completed results are retained.").font(.caption).foregroundStyle(.orange) }
                Text("Usage history contains only dates, model names, categories, outcomes and reported counts. No conversations, source content or credentials are stored here. Up to 30 days / 5,000 calls are kept locally.").font(.caption).foregroundStyle(.secondary)
            }
            }.formStyle(.grouped)
        }
    }
}
