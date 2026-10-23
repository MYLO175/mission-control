import SwiftUI
struct BriefingView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    @State private var selectedRecord = ""
    var body: some View {
        DisclosureGroup("Saved briefings") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Prepare today") { briefings.check(model, manual: true) }.disabled(model.chatGPT.usagePaused || briefings.busy || model.chatGPT.busy || !model.chatGPT.inferenceVerified)
                    if briefings.busy { ProgressView().controlSize(.small); Button("Stop") { briefings.cancel() } }
                }
                if let error = briefings.error { Text(error).font(.caption).foregroundStyle(.orange) }
                let records = briefings.records(model)
                if !records.isEmpty {
                    Picker("Saved briefing", selection: $selectedRecord) {
                        Text("Latest").tag("")
                        ForEach(records) { Text($0.day).tag($0.id) }
                    }
                }
                if let record = records.first(where: { $0.id == selectedRecord }) ?? records.first {
                    Text(record.day).font(.headline)
                    if let note=briefings.displayNote(record,model:model) { Text(note).font(.caption).foregroundStyle(.secondary) }
                    Text(record.coverage).font(.caption).foregroundStyle(.secondary)
                    MemoryAdviceEvidenceView(model:model,registration:record.registration,dependencies:record.memoryDependencies,use:.brief)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(record.items) { item in
                                Text(PAProse.display(item.text)).textSelection(.enabled)
                                ForEach(item.sourceIDs, id: \.self) { id in
                                    if let source = record.sources.first(where: { $0.id == id }) {
                                        if ["mail","mailResolution"].contains(source.kind), let message = model.mailData.messages.first(where: { $0.id == (source.originalID ?? id) }) ?? model.emailSummaries.sourceAssessments(model).first(where: { $0.0.id == (source.originalID ?? id) })?.0, !model.assistant.excludedAccounts.contains(message.accountID) {
                                            Button(source.label) { model.select(message) }.buttonStyle(.link).font(.caption)
                                        } else if source.kind == "whatsapp" { WhatsAppBriefSource(service:model.whatsapp,registration:model.chatGPT.activeID,source:source) }
                                        else { Text(source.label).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                Divider()
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 220)
                } else { Text("Today’s brief updates with each heartbeat. You can also prepare it manually.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
struct BriefingSettings: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    var body: some View {
        Section("Today’s brief") {
            Text("Updated with each heartbeat using your permitted sources and the current time. Refresh it from the widget or ask 3PO whenever you want a manual update. There is no separate morning timer.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
