import SwiftUI
import AppKit
struct DictationView: View {
    @Bindable var dictation: DictationService
    var use: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Dictate a message").font(.title2.weight(.semibold))
            Text(dictation.status).font(.callout).foregroundStyle(.secondary)
            TextEditor(text:$dictation.transcript).font(.body).frame(minHeight:140)
                .disabled(dictation.recording || dictation.preparing || dictation.finishing)
                .accessibilityLabel("Editable dictation transcript")
            HStack {
                if dictation.recording { Button("Stop") { dictation.stop() } }
                else { Button("Start dictation") { Task { await dictation.start() } }.disabled(dictation.preparing || dictation.finishing) }
                if dictation.preparing || dictation.finishing { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dictation.cancel(); dismiss() }
                Button("Use transcript") { use(dictation.transcript); dictation.cancel(); dismiss() }
                    .disabled(dictation.recording || dictation.preparing || dictation.finishing || dictation.transcript.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            Text("Speech stays on this Mac. Using the transcript puts it in the message field; you choose when to send.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width:500).onDisappear { dictation.cancel() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.sessionDidResignActiveNotification)) { _ in dictation.cancel() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.willSleepNotification)) { _ in dictation.cancel() }
    }
}
