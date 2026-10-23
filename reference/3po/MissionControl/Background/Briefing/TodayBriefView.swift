import SwiftUI

struct TodayBriefView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    var configuration:Binding<WidgetConfiguration>? = nil
    @State private var showMemory=false
    @State private var showSources=false
    @State private var legacyShowsWeather=true
    @State private var editingPrompt:BriefPromptEdit?
    private var record:DailyBriefing? {briefings.savedToday(model) ?? briefings.current(model)}
    private var showsWeather:Binding<Bool> {
        Binding(get:{configuration?.wrappedValue.briefShowsWeather ?? legacyShowsWeather},set:{value in
            if let configuration {configuration.wrappedValue.briefShowsWeather=value}
            else {legacyShowsWeather=value}
        })
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) {
                Label("Today’s brief",systemImage:"sun.max").font(.title3.weight(.semibold)).lineLimit(1).layoutPriority(1)
                Spacer(minLength:4)
                if let record {
                    ViewThatFits(in:.horizontal) {
                        Text("Updated \(record.created.formatted(date:.omitted,time:.shortened))")
                        Text(record.created.formatted(date:.omitted,time:.shortened))
                    }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .help("Updated \(record.created.formatted(date:.abbreviated,time:.shortened)). Refreshes with each heartbeat.")
                        .accessibilityLabel("Brief updated \(record.created.formatted(date:.omitted,time:.shortened))")
                }
                if briefings.busy { ProgressView().controlSize(.small); Button("Stop") { briefings.cancel() }.fixedSize() }
                else { Button { briefings.updateToday(model) } label: { Image(systemName:"arrow.clockwise") }.help(!briefings.hasCurrentToday(model) ? "Prepare today’s brief using AI" : "Refresh today’s brief using AI and fresh sources").accessibilityLabel(!briefings.hasCurrentToday(model) ? "Prepare today’s brief" : "Refresh today’s brief").disabled(model.heartbeat.busy) }
                Menu {
                    Toggle("Show weather",isOn:showsWeather)
                    Divider()
                    Button("Edit brief prompt…") {editingPrompt=BriefPromptEdit(capture:briefings.writingPrompt(model.chatGPT.activeID))}.disabled(model.chatGPT.activeID.isEmpty)
                } label: {Image(systemName:"ellipsis")}
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Brief options").accessibilityLabel("Brief options")
            }.buttonStyle(.borderless)
            if model.heartbeat.busy && !briefings.busy {Text("The heartbeat will update your brief shortly…").font(.caption).foregroundStyle(.secondary)}
            if briefings.busy { Text(briefings.phase.isEmpty ? "Preparing today’s brief…" : briefings.phase).font(.caption).foregroundStyle(.secondary) }
            if let record {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if showsWeather.wrappedValue {WeatherBriefCard(weather:model.weather)}
                        BriefFreshnessNote(model:model,briefings:briefings,record:record)
                        let prose=BriefingRules.displayProse(record)
                        Text((try? AttributedString(markdown:prose,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(prose)).font(.callout).lineSpacing(5).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                        DisclosureGroup("Sources and coverage",isExpanded:$showSources) {
                            if showSources {VStack(alignment:.leading,spacing:10) {
                                Text(record.coverage).font(.caption).foregroundStyle(.secondary)
                                MemoryAdviceEvidenceView(model:model,registration:record.registration,dependencies:record.memoryDependencies,use:.brief)
                                ForEach(record.items) { item in
                                    let text=PAProse.display(item.text)
                                    Text((try? AttributedString(markdown:text,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(text)).font(.caption)
                                    ForEach(item.sourceIDs,id:\.self) { id in
                                        if let source = record.sources.first(where: { $0.id == id }) {
                                            if source.kind == "mail", let message = model.reviewInbox.highlights.first(where:{ $0.0.id == source.originalID })?.0 { Button(source.label) { model.select(message) }.buttonStyle(.link).font(.caption) }
                                            else if source.kind == "weather" { Link(source.label,destination:WeatherRules.provider).font(.caption) }
                                            else if source.kind == "whatsapp" { WhatsAppBriefSource(service:model.whatsapp,registration:model.chatGPT.activeID,source:source) }
                                            else if source.kind == "memory" { Button(source.label) { showMemory=true }.buttonStyle(.link).font(.caption) }
                                            else { Label(source.label,systemImage:source.kind == "calendar" ? "calendar" : "checklist").font(.caption).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                            }.padding(.top,8)}
                        }.font(.caption)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            } else {
                if showsWeather.wrappedValue {WeatherBriefCard(weather:model.weather)}
                ContentUnavailableView("Your day at a glance",systemImage:"sun.horizon",description:Text(!model.assistant.contextEnabled ? "Enable assistant source context in Settings." : briefings.busy ? "Your PA is preparing today’s brief…" : model.chatGPT.usagePaused ? "Subscription access is paused. Your Apple sources remain available." : "Updated with each heartbeat. Refresh here for a manual update."))
            }
            if let error = briefings.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if model.chatGPT.usagePaused { Button("Check subscription access") { model.chatGPT.testConnection() }.controlSize(.small).disabled(model.chatGPT.busy || model.assistant.busy) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(isPresented:$showMemory) { PAMemoryView(memory:model.assistant.memory,registration:model.chatGPT.activeID,model:model) }
        .sheet(item:$editingPrompt) {edit in BriefPromptEditor(model:model,briefings:briefings,capture:edit.capture)}
        .onChange(of:model.chatGPT.activeID) { showMemory=false;editingPrompt=nil }
    }
}

/// Dated display only. Current evidence checks belong to new AI requests.
private struct BriefFreshnessNote:View {
    var model:DashboardModel
    var briefings:BriefingService
    var record:DailyBriefing
    var body:some View {
        if let note=briefings.displayNote(record,model:model) {
                Label(note,systemImage:"clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
        }
    }
}

private struct BriefPromptEdit:Identifiable {
    let id=UUID()
    var capture:BriefWritingPrompt
}
struct BriefPromptEditor:View {
    @Bindable var model:DashboardModel
    @Bindable var briefings:BriefingService
    let capture:BriefWritingPrompt
    @Environment(\.dismiss) private var dismiss
    @State private var draft:String
    @State private var error:String?
    init(model:DashboardModel,briefings:BriefingService,capture:BriefWritingPrompt) {
        self.model=model;self.briefings=briefings;self.capture=capture
        _draft=State(initialValue:capture.text)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Brief prompt").font(.title2.weight(.semibold))
            Text("Choose what your PA focuses on and how it writes. Applies to your next refresh or heartbeat across all brief widgets.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text:$draft).font(.body).padding(8).frame(minHeight:280)
                .background(.background,in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).stroke(.quaternary))
                .accessibilityLabel("Brief writing prompt")
            Text("Current-time greetings, source checks and approval rules stay built in.").font(.caption).foregroundStyle(.secondary)
            if let error {Text(error).font(.caption).foregroundStyle(.orange)}
            HStack {
                Button("Use default") {draft=BriefingRules.defaultWritingPrompt;error=nil}.disabled(draft == BriefingRules.defaultWritingPrompt)
                Spacer()
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {try briefings.saveWritingPrompt(draft,expected:capture,model:model);dismiss()}
                    catch {self.error=error.localizedDescription}
                }.keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || draft.trimmingCharacters(in:.whitespacesAndNewlines).count > BriefingRules.writingPromptLimit || capture.registration != model.chatGPT.activeID)
            }
        }.padding(24).frame(width:620,height:520)
    }
}
