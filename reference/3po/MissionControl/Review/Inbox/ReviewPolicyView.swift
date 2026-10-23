import SwiftUI

/// Edits the same policy used by email and background Review; feedback remains canonical memory.
struct ReviewPolicyView: View {
    @Bindable var model: DashboardModel
    private let registration: String
    private let storage: ObjectIdentifier?
    @Environment(\.dismiss) private var dismiss
    @State private var expected: ReviewPolicyCapture
    @State private var text: String
    @State private var selectedVersion: ReviewPolicyVersion?
    @State private var resetting = false
    @State private var showFeedback = false
    @State private var error: String?
    init(model: DashboardModel) {
        self.model = model
        registration = model.chatGPT.activeID
        storage = model.container.map(ObjectIdentifier.init)
        let capture = model.emailSummaries.policy(model.chatGPT.activeID)
        _expected = State(initialValue: capture); _text = State(initialValue: capture.text)
    }
    private var feedback: [PAMemory] {
        model.assistant.memory.reviewPreferences(registration).filter {MemoryRules.inScope($0, conversationID: nil, includeTopics: true)}
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review guidance").font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Button("Save") {save()}.keyboardShortcut(.defaultAction)
                    .disabled(!ReviewPolicyRules.validText(text) || !model.emailSummaries.reviewPolicies.writable || registration.isEmpty)
            }
            Text("Describe what deserves your attention. This guidance applies whenever 3PO reviews new information. Your source access and action approvals stay separate.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your Review policy").font(.headline)
                    TextEditor(text: $text).font(.body).frame(minHeight: 210).padding(6).border(Color.secondary.opacity(0.25)).accessibilityLabel("Review policy Markdown")
                    HStack {
                        Text("Plain text or Markdown · \(text.count)/\(ReviewPolicyRules.textLimit)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Use default") {text = ReviewPolicyRules.defaultText; selectedVersion = nil; resetting = true}
                    }.controlSize(.small)
                    DisclosureGroup("Policy history") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.emailSummaries.policyHistory(registration)) {version in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(version.created.formatted(date: .abbreviated, time: .shortened)).font(.caption.weight(.semibold))
                                        if version.id.uuidString == expected.revision {Text("Current").font(.caption).foregroundStyle(.secondary)}
                                        Spacer()
                                        Button("Use this version") {text = version.text; resetting = false; selectedVersion = version}.controlSize(.small)
                                    }
                                    Text(version.text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            }
                            if model.emailSummaries.policyHistory(registration).isEmpty {Text("Your first saved edit will appear here. Restoring creates a new version.").font(.caption).foregroundStyle(.secondary)}
                        }.padding(.top, 6)
                    }
                    Divider()
                    HStack {Text("What your feedback has taught 3PO").font(.headline); Spacer(); Button("Manage feedback…") {showFeedback = true}.controlSize(.small)}
                    Text("These saved preferences keep their original words, scope and history. They guide relevant messages alongside your policy; opening this page does not reinterpret emails.").font(.caption).foregroundStyle(.secondary)
                    ForEach(feedback) {value in
                        VStack(alignment: .leading, spacing: 5) {
                            if let topic = value.reviewContext, !topic.isEmpty {Text(topic).font(.callout.weight(.semibold))}
                            Text(value.text).font(.callout).textSelection(.enabled)
                            Text(value.conversationID == nil ? "Shared Review feedback" : "Earlier conversation scope").font(.caption).foregroundStyle(.secondary)
                            if let original = value.reviewFeedback, value.reviewInterpretation != nil {
                                DisclosureGroup("Your original feedback") {Text(original).font(.caption).textSelection(.enabled)}.font(.caption)
                            }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if feedback.isEmpty {Text("Use Feedback on a Review item to explain what matters. Dismiss acknowledges the item without teaching a preference.").font(.caption).foregroundStyle(.secondary)}
                    if !model.assistant.memory.enabled {Text("Memory use is paused. Your policy still applies; saved feedback becomes available when memory use resumes.").font(.caption).foregroundStyle(.secondary)}
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = error ?? model.emailSummaries.reviewPolicies.error {Text(error).font(.caption).foregroundStyle(.orange)}
        }.padding(24).frame(width: 680, height: 660)
        .sheet(isPresented: $showFeedback) {ReviewRelevancePreferencesView(model: model)}
        .onChange(of: model.chatGPT.activeID) {dismiss()}
    }
    private func save() {
        guard registration == model.chatGPT.activeID, storage == model.container.map(ObjectIdentifier.init) else {error = "The account changed. Reopen Review guidance before saving."; return}
        let saved: Bool
        if resetting && text == ReviewPolicyRules.defaultText {saved = model.emailSummaries.resetPolicy(registration: registration, expected: expected)}
        else if let selectedVersion, text == selectedVersion.text {saved = model.emailSummaries.restorePolicy(selectedVersion, expected: expected)}
        else {saved = model.emailSummaries.savePolicy(text, registration: registration, expected: expected)}
        guard saved else {error = model.emailSummaries.reviewPolicies.error; return}
        expected = model.emailSummaries.policy(registration); dismiss()
    }
}
