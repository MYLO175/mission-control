import SwiftUI
import ServiceManagement
import AppKit

struct DashboardView: View {
    @Bindable var model: DashboardModel
    var widgetConfiguration: Binding<WidgetConfiguration>? = nil
    @AppStorage("showEmailSources") private var showEmailSources = false
    @AppStorage("assistantExpanded") private var assistantExpanded = false
    @AppStorage("assistantReadingMode") private var assistantReadingMode = false
    @AppStorage("reminderGroupingMode") private var legacyReminderGroupingMode = "lists"
    @State private var legacyCollapsedReminderLists:[String:Set<String>]=[:]
    private var reminderGroupingMode: String { widgetConfiguration?.wrappedValue.reminderGrouping ?? legacyReminderGroupingMode }
    private var reminderGroupingBinding: Binding<String> { widgetConfiguration.map { binding in Binding(get:{ binding.wrappedValue.reminderGrouping },set:{ binding.wrappedValue.reminderGrouping = $0 }) } ?? $legacyReminderGroupingMode }
    private var listExclusions: Binding<Set<String>> { widgetConfiguration.map { binding in Binding(get:{ binding.wrappedValue.sourceExclusions },set:{ binding.wrappedValue.sourceExclusions = $0 }) } ?? $model.excludedLists }
    private var accountExclusions: Binding<Set<String>> { widgetConfiguration.map { binding in Binding(get:{ binding.wrappedValue.sourceExclusions },set:{ binding.wrappedValue.sourceExclusions = $0 }) } ?? $model.excludedAccounts }
    private var visibleReminders: [TaskItem] { model.reminderData.reminders.filter { !listExclusions.wrappedValue.contains($0.listID) } }
    private func reminderListExpanded(_ listID:String)->Binding<Bool> {
        let registration=model.chatGPT.activeID
        return Binding(get:{
            if let widgetConfiguration {return !(widgetConfiguration.wrappedValue.reminderCollapsedLists?[registration] ?? []).contains(listID)}
            return !(legacyCollapsedReminderLists[registration] ?? []).contains(listID)
        },set:{expanded in
            if let widgetConfiguration {
                var value=widgetConfiguration.wrappedValue
                var collapsed=Set(value.reminderCollapsedLists?[registration] ?? [])
                if expanded {collapsed.remove(listID)} else {collapsed.insert(listID)}
                if value.reminderCollapsedLists == nil {value.reminderCollapsedLists=[:]}
                value.reminderCollapsedLists?[registration]=collapsed.sorted()
                widgetConfiguration.wrappedValue=value
            } else {
                if expanded {legacyCollapsedReminderLists[registration,default:[]].remove(listID)}
                else {legacyCollapsedReminderLists[registration,default:[]].insert(listID)}
            }
        })
    }
    private var visibleMessages: [MailMessage] { model.mailData.messages.filter { !accountExclusions.wrappedValue.contains($0.accountID) }.sorted { $0.received > $1.received } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("3PO").font(.system(size: 26, weight: .semibold, design: .rounded))
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(context.date.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if ProcessInfo.processInfo.arguments.contains("--sample") { Text("Sample data").foregroundStyle(.secondary) }
                Button { assistantExpanded.toggle() } label: { Label("Assistant", systemImage: "sparkles") }.keyboardShortcut("j",modifiers:.command).help("Show or hide Assistant (⌘J)")
                Button { model.heartbeat.check(model,manual:true) } label: { Label("Run heartbeat", systemImage: "waveform.path.ecg") }.keyboardShortcut("r",modifiers:.command)
                    .disabled(model.heartbeat.manualCheckBlockReason(model) != nil).help(model.heartbeat.manualCheckHelp(model)+" (⌘R)")
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
            }.padding(24)
            Divider()
            if let report = model.validationReport { Text(report).font(.callout).padding(10).textSelection(.enabled).id(report) }
            if let error = model.storageError { errorBanner(error) }
            if let error = model.writeError { errorBanner(error) }
            if model.undoToken != nil {
                HStack {
                    Label("Completed: \(model.undoTitle)", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Undo") { model.undo() }.disabled(model.writing)
                    Button { model.undoToken = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }.font(.callout).padding(12).background(.green.opacity(0.08))
            }
            GeometryReader { geometry in
                VStack(spacing:0) {
                Group {
                if geometry.size.width >= 1040 {
                    HStack(alignment: .top, spacing: 14) {
                        calendarPanel.frame(width: max(320, geometry.size.width * 0.31))
                        remindersPanel.frame(width: max(260, geometry.size.width * 0.25))
                        emailOverview.frame(maxWidth: .infinity)
                    }.padding(16)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            emailOverview.frame(height: 400)
                            HStack(alignment: .top, spacing: 14) { calendarPanel; remindersPanel }.frame(height: 440)
                        }.padding(14)
                    }
                }
                }.frame(maxHeight:.infinity)
                if assistantExpanded {
                    AssistantPanel(model:model,assistant:model.assistant,readingMode:$assistantReadingMode)
                        .frame(height:min(assistantReadingMode ? 420 : 280,geometry.size.height * (assistantReadingMode ? 0.7 : 0.55)))
                }
                }
            }
            HStack {
                Text("Daily overview").font(.caption)
                Spacer()
                Text(model.assistant.contextEnabled ? "Apple apps remain the source of truth · Assistant context enabled" : "Apple apps remain the source of truth · AI context off").font(.caption)
            }.foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
        }.frame(minWidth: 780, minHeight: 580).background(Color(nsColor: .windowBackgroundColor)).task { model.start() }
        .sheet(item: $model.selectedMessage) { message in previewSheet(message) }
        .sheet(item: $model.editTarget) { NativeItemEditor(model:model,target:$0) }
    }
    var emailOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label("Your overview", systemImage: "sparkles").font(.title3.weight(.semibold)); Spacer(); Toggle("Sources", isOn: $showEmailSources).toggleStyle(.button).controlSize(.small) }
            if !showEmailSources { TodayBriefView(model:model,briefings:model.briefings) }
            if showEmailSources { inboxPanel }
            else { DisclosureGroup("Email follow-ups") { EmailOverviewView(model:model,summaries:model.emailSummaries).frame(maxHeight:220) } }
        }.panelStyle()
    }
    func errorBanner(_ text: String) -> some View {
        HStack { Image(systemName: "exclamationmark.triangle"); Text(text).textSelection(.enabled); Spacer() }.font(.callout).foregroundStyle(.orange).padding(10)
    }
    func panelHeader(_ title: String, icon: String, health: SourceHealth, loadingLabel: String = "Refreshing…") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Label(title, systemImage: icon).font(.title3.weight(.semibold)); Spacer(); if health.loading { ProgressView().controlSize(.small) } }
            Text(health.loading ? loadingLabel : health.detail).font(.caption).foregroundStyle(health.error == nil ? Color.secondary : Color.orange).lineLimit(3).textSelection(.enabled)
        }
    }
    func sourceMenu(_ title: String, sources: [SourceOption], exclusions: Binding<Set<String>>) -> some View {
        Menu {
            Button("Enable all") { exclusions.wrappedValue = [] }
            Divider()
            ForEach(sources) { source in
                Toggle(isOn: Binding(get: { !exclusions.wrappedValue.contains(source.id) }, set: { enabled in
                    if enabled { exclusions.wrappedValue.remove(source.id) } else { exclusions.wrappedValue.insert(source.id) }
                })) {
                    HStack(spacing: 7) {
                        Circle().fill(sourceColor(source.id, explicit: source.color)).frame(width: 8, height: 8)
                        Text(source.displayLabel)
                    }
                }
            }
        } label: { Label(title, systemImage: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).controlSize(.small).disabled(sources.isEmpty)
    }
    func sourceColor(_ id: String, explicit: SourceRGB? = nil) -> Color {
        if let explicit {
            return Color(red: explicit.red, green: explicit.green, blue: explicit.blue)
        }
        let hash = id.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.48, brightness: 0.78)
    }
    func reminderSource(_ id: String) -> SourceOption? {
        model.reminderData.sources.first { $0.id == id }
    }
    func reminderListLabel(_ id: String) -> String {
        reminderSource(id)?.displayLabel ?? visibleReminders.first(where: { $0.listID == id })?.sourceLabel ?? "Reminders"
    }
    var visibleReminderListIDs: [String] {
        Array(Set(visibleReminders.map(\.listID))).sorted { left, right in
            let leftDefault = reminderSource(left)?.title.caseInsensitiveCompare("To do") == .orderedSame
            let rightDefault = reminderSource(right)?.title.caseInsensitiveCompare("To do") == .orderedSame
            if leftDefault != rightDefault { return leftDefault }
            return reminderListLabel(left) < reminderListLabel(right)
        }
    }
    var calendarPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader("Calendar", icon: "calendar", health: model.calendarHealth)
            sourceMenu("Calendars", sources: model.calendarData.sources, exclusions: $model.excludedCalendars)
            HStack {
                Button { moveDate(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                DatePicker("Date", selection: Binding(get: { model.selectedDate }, set: { model.navigate($0) }), displayedComponents: .date).labelsHidden()
                Button { moveDate(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button("Today") { model.navigate(.now) }.controlSize(.small)
            }
            HStack(spacing: 4) {
                ForEach(0..<7) { index in
                    let date = Calendar.current.date(byAdding: .day, value: index, to: model.selectedDate)!
                    let count = model.visibleEvents.filter { DateRules.overlaps($0, day: date) }.count
                    Button { model.navigate(date) } label: { VStack(spacing: 4) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day())).font(.callout.weight(.medium))
                        Text("\(count)").font(.caption2).foregroundStyle(count == 0 ? Color.secondary : Color.accentColor)
                    }.frame(maxWidth: .infinity).padding(.vertical, 7).background(index == 0 ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(count) events")
                }
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<2) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: offset, to: model.selectedDate)!
                        let events = model.visibleEvents.filter { DateRules.overlaps($0, day: day) }
                        Text(day.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold)).padding(.top, 4)
                        if events.isEmpty { Text("No events").font(.callout).foregroundStyle(.secondary) }
                        let allDay = events.filter(\.allDay)
                        let timed = events.filter { !$0.allDay }
                        if !allDay.isEmpty {
                            Text("ALL DAY").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(allDay) { eventRow($0, day: day) }
                        }
                        ForEach(timed) { eventRow($0, day: day) }
                        if offset == 0 { Divider().padding(.vertical, 4) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.panelStyle()
    }
    func moveDate(_ delta: Int) { model.navigate(Calendar.current.date(byAdding: .day, value: delta, to: model.selectedDate)!) }
    func eventRow(_ event: AgendaEvent, day: Date) -> some View {
        let color = sourceColor(event.calendarID, explicit: model.calendarData.sources.first(where: { $0.id == event.calendarID })?.color)
        return HStack(alignment: .top, spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                if !event.allDay {
                    Text(eventTime(event, day: day)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(event.title).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if !event.location.isEmpty { Label(event.location, systemImage: "location").font(.caption).foregroundStyle(.secondary) }
                Text(event.sourceLabel).font(.caption2).foregroundStyle(color)
            }
            Spacer(minLength: 0)
            Button { model.editTarget = .event(event) } label: { Image(systemName:"pencil") }.buttonStyle(.borderless).help("Edit event").accessibilityLabel("Edit event: " + event.title).disabled(model.writing)
        }.padding(.vertical, 3)
    }
    func eventTime(_ event: AgendaEvent, day: Date) -> String {
        let calendar = Calendar.current
        let start = calendar.isDate(event.start, inSameDayAs: day) ? event.start.formatted(date: .omitted, time: .shortened) : event.start.formatted(date: .abbreviated, time: .shortened)
        let end = calendar.isDate(event.end, inSameDayAs: day) ? event.end.formatted(date: .omitted, time: .shortened) : event.end.formatted(date: .abbreviated, time: .shortened)
        if calendar.timeZone.secondsFromGMT(for: event.start) != calendar.timeZone.secondsFromGMT(for: event.end) {
            let startZone = calendar.timeZone.abbreviation(for: event.start) ?? ""
            let endZone = calendar.timeZone.abbreviation(for: event.end) ?? ""
            return "\(start) \(startZone) – \(end) \(endZone)"
        }
        return "\(start) – \(end)"
    }
    var remindersPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing:8) { Label("Reminders",systemImage:"checklist").font(.title3.weight(.semibold)); SourceStatusIndicator(title:"Reminders",health:model.reminderHealth); Spacer(); Button { model.newNativeItem(.reminder) } label: { Image(systemName:"plus") }.buttonStyle(.borderless).help("New reminder").accessibilityLabel("New reminder").disabled(model.writing) }
            if let error = model.reminderHealth.error { Text((model.reminderHealth.lastSuccess == nil ? "" : "Stale · ") + error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            HStack(spacing: 8) {
                sourceMenu("Lists", sources: model.reminderData.sources, exclusions: listExclusions)
                Spacer(minLength: 0)
                Picker("Group reminders", selection: reminderGroupingBinding) {
                    Text("Lists").tag("lists")
                    Text("Due date").tag("due")
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if reminderGroupingMode == "lists" {
                        ForEach(visibleReminderListIDs, id: \.self) { listID in
                            let items = DateRules.ordered(visibleReminders.filter { $0.listID == listID })
                            DisclosureGroup(isExpanded:reminderListExpanded(listID)) {
                                VStack(alignment:.leading,spacing:12) {
                                    ForEach(items) { item in
                                        reminderRow(item, showSource: false, showOverdueBadge: true)
                                    }
                                }.padding(.top,8)
                            } label: {
                                HStack {
                                    Text(reminderListLabel(listID)).font(.subheadline.weight(.semibold)).foregroundStyle(sourceColor(listID, explicit: reminderSource(listID)?.color)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(items.count)").foregroundStyle(.secondary).font(.caption)
                                }
                            }.tint(sourceColor(listID,explicit:reminderSource(listID)?.color))
                            Divider()
                        }
                    } else {
                        ForEach(["Overdue", "Today", "Upcoming", "Undated"], id: \.self) { group in
                            let items = visibleReminders.filter { DateRules.group($0) == group }
                            HStack { Text(group).font(.subheadline.weight(.semibold)); Spacer(); Text("\(items.count)").foregroundStyle(.secondary).font(.caption) }
                            ForEach(items) { item in
                                reminderRow(item, showSource: true, showOverdueBadge: false)
                            }
                            Divider()
                        }
                    }
                }
            }
        }.panelStyle()
    }
    func reminderRow(_ item: TaskItem, showSource: Bool, showOverdueBadge: Bool) -> some View {
        let overdue = DateRules.group(item) == "Overdue"
        return HStack(alignment: .top, spacing: 8) {
            Button { model.complete(item) } label: { Image(systemName: item.writable ? "circle" : "lock.circle").font(.title3) }
                .buttonStyle(.plain).disabled(!item.writable || model.writing).help(item.writable ? "Complete reminder" : "Read-only list")
            Button { model.editTarget = .reminder(item) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(item.title).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if showOverdueBadge && overdue {
                        Text("Overdue").font(.caption2.weight(.medium)).foregroundStyle(.orange).padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                if let due = item.due { Text(due.formatted(date: .abbreviated, time: item.hasTime ? .shortened : .omitted)).font(.caption).foregroundStyle(overdue ? Color.orange : Color.secondary) }
                if showSource || item.recurring {
                    HStack(spacing: 4) {
                        if showSource { Text(item.sourceLabel) }
                        if item.recurring { Image(systemName: "repeat") }
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Edit reminder").accessibilityLabel("Edit reminder: " + item.title).disabled(model.writing)
        }.padding(.vertical, 3)
    }
    private var mailStatusSummary:String {
        let accounts=model.mailData.accounts.filter{model.mailIndex.accountErrors?[$0.id] != nil}.map(\.title)
        let label=accounts.isEmpty ? "Mail" : accounts.joined(separator:", ")
        let slow=model.mailHealth.error?.contains("did not respond") == true
        let explanation=slow ? "is taking longer to respond" : "couldn’t refresh"
        return label+" "+explanation+". "+(visibleMessages.isEmpty ? "Open the status dot for details." : "Showing saved mail.")
    }
    var inboxPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing:8) {
                Label("Inbox",systemImage:"tray").font(.title3.weight(.semibold))
                SourceStatusIndicator(title:"Mail",health:model.mailHealth,coverage:model.mailCoverage,refresh:{model.mailIndex.resume();Task {await model.refreshMail()}})
                Spacer()
            }
            if model.mailHealth.error != nil {
                Text(mailStatusSummary).font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)
            }
            HStack {
                Menu {
                    Button("Enable all") { accountExclusions.wrappedValue = [] }
                    Divider()
                    ForEach(model.mailData.accounts) { account in
                        Toggle("\(account.title) · Inbox", isOn: Binding(get: { !accountExclusions.wrappedValue.contains(account.id) }, set: { enabled in
                            if enabled { accountExclusions.wrappedValue.remove(account.id) } else { accountExclusions.wrappedValue.insert(account.id) }
                        }))
                    }
                } label: { Label("Mailboxes", systemImage: "line.3.horizontal.decrease") }.controlSize(.small)
                Spacer()
                Text("Last 30 days · \(visibleMessages.count)").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if visibleMessages.isEmpty {
                ContentUnavailableView("No inbox messages", systemImage: "tray", description: Text(model.mailHealth.error == nil ? "Recent messages appear here after Mail connects." : "Check the Mail connection status above."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleMessages) { message in
                            Button { model.select(message) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline) {
                                        if message.unread { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                                        Text(message.sender).font(.callout.weight(message.unread ? .semibold : .regular)).lineLimit(1)
                                        Spacer(minLength: 4)
                                        if message.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange) }
                                        if message.replied { Image(systemName: "arrowshape.turn.up.left").foregroundStyle(.secondary) }
                                    }
                                    Text(message.subject.isEmpty ? "(No subject)" : message.subject).font(.callout).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    HStack { Text(message.account).lineLimit(1); Spacer(); Text(message.received.formatted(date: .abbreviated, time: .shortened)) }.font(.caption2).foregroundStyle(.secondary)
                                }.padding(.vertical, 11).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }.panelStyle()
    }
    func previewSheet(_ message: MailMessage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(message.subject.isEmpty ? "(No subject)" : message.subject).font(.title2.weight(.semibold)); Spacer(); Button("Done") { model.selectedMessage = nil }.keyboardShortcut(.cancelAction) }
            Text(message.sender).textSelection(.enabled)
            Text("\(message.account) · \(message.mailboxName ?? "Inbox") · \(message.received.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            Divider()
            if model.previewLoading { ProgressView("Loading plain-text preview…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error = model.previewError { ContentUnavailableView("Preview unavailable", systemImage: "exclamationmark.triangle", description: Text(error)) }
            else { ScrollView { Text(model.preview).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            Divider()
            HStack { Text("Previews are read locally.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Open in Mail") { model.openMessage(message) } }
        }.padding(24).frame(width: 700, height: 580)
    }
}
private extension View {
    func panelStyle() -> some View {
        modifier(DashboardPanelStyle())
    }
}
private struct DashboardPanelStyle: ViewModifier {
    @Environment(\.workspacePalette) private var palette
    func body(content: Content) -> some View {
        content.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette[.widget], in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette[.border]))
            .shadow(color:.black.opacity(0.025),radius:8,x:0,y:3)
    }
}
struct SettingsView: View {
    @Bindable var model: DashboardModel
    @AppStorage("settingsSelectedPage") private var selectedPage = "General"
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?
    @State private var inspectMemory=false
    @Environment(\.openWindow) private var openWindow
    private let pages = ["General", "Connections", "Assistant", "Background", "Memory", "Usage", "Help"]
    var body: some View {
        NavigationSplitView {
            List(selection:selectionBinding) {
                ForEach(pages,id:\.self) { page in
                    NavigationLink(value:page) { Label(page == "Memory" ? "Context" : page,systemImage:icon(for:page)) }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .accessibilityLabel("Settings sections")
        } detail: {
            Group {
            if selectedPage == "Usage" { AIUsageView(model:model) }
            else {
            Form {
                switch selectedPage {
                case "General":
                    Section("Startup") {
                        Toggle("Launch at login", isOn: $enabled).onChange(of: enabled) { _, value in
                            do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; error = nil }
                            catch { self.error = error.localizedDescription }
                            enabled = SMAppService.mainApp.status == .enabled
                            if SMAppService.mainApp.status == .requiresApproval { error = "Allow 3PO in System Settings → General → Login Items." }
                        }
                        Text("Closing the dashboard keeps the menu bar app running. Choose Quit to stop it.").font(.caption).foregroundStyle(.secondary)
                        if let error { Text(error).foregroundStyle(.orange) }
                    }
                    Section("Local sources") {
                        Text("Calendar and Reminders are read from macOS. Reminders remains the source of truth for to-do and shopping tasks. Apple Mail is read-only. Refresh collects source changes locally and makes no AI calls.").font(.callout)
                        Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
                    }
                case "Connections":
                    ChatGPTConnectionView(connection:model.chatGPT)
                    WhatsAppSettings(service:model.whatsapp,registration:model.chatGPT.activeID,heartbeatReviewEnabled:model.heartbeat.whatsappEnabled)
                    WeatherSettings(weather:model.weather)
                case "Assistant":
                    AssistantSourceSettings(model:model,assistant:model.assistant,page:.assistant)
                case "Background":
                    AssistantSourceSettings(model:model,assistant:model.assistant,page:.background)
                    EmailSummarySettings(model:model,summaries:model.emailSummaries)
                    BriefingSettings(model:model,briefings:model.briefings)
                case "Memory":
                    Section("Context pages and instructions") {
                        Button("Open Context pages") { inspectMemory=true }
                        Text("Read the overview, project pages, working changes and feature instructions. Supporting facts, history and learning controls remain available inside. Opening Context makes no AI request.").font(.caption).foregroundStyle(.secondary)
                    }
                    AssistantSourceSettings(model:model,assistant:model.assistant,page:.memory)
                case "Help":
                    PAHelpSections(model:model) { openWindow(id:"help") }
                default:
                    Section("Settings") { Text("Choose a section from the sidebar.") }
                }
            }
            .formStyle(.grouped)
            }
            }
            .padding(.horizontal,12)
            .padding(.vertical,8)
            .accessibilityLabel("\(selectedPage == "Memory" ? "Context" : selectedPage) settings")
        }
        .frame(minWidth:760,minHeight:620)
        .sheet(isPresented:$inspectMemory) { ContextPagesView(model:model,registration:model.chatGPT.activeID) }
        .onChange(of:model.chatGPT.activeID) { inspectMemory=false }
    }
    private func icon(for page:String)->String {
        switch page {
        case "General": "gearshape"
        case "Connections": "link"
        case "Assistant": "sparkles"
        case "Background": "clock.arrow.circlepath"
        case "Memory": "brain"
        case "Usage": "chart.bar"
        default: "questionmark.circle"
        }
    }
    private var selectionBinding:Binding<String?> {
        Binding(get:{selectedPage},set:{selectedPage=$0 ?? "General"})
    }
}

struct PAHelpView:View {
    @Bindable var model:DashboardModel
    var body:some View {
        Form { PAHelpSections(model:model) }
            .formStyle(.grouped)
            .frame(minWidth:620,minHeight:560)
    }
}

struct PAHelpSections:View {
    @Bindable var model:DashboardModel
    var openHelpWindow:(()->Void)? = nil
    var body:some View {
        Group {
            Section("How 3PO works") {
                Text("Heartbeat: refresh enabled sources → review what matters → update your brief and Review inbox → you approve changes.").font(.headline)
                Text("The toolbar pulse button (⌘R) runs a heartbeat now. Refresh sources only (⌥⌘R) is in the Dashboard menu and uses no AI. Mail checks every five minutes while open; Calendar and Reminders react to native changes; connected WhatsApp receives messages continuously.").font(.callout)
                Text("Calendar, Reminders, Mail and WhatsApp refresh do not start inference. Reviews use only enabled sources and show partial coverage when history or access is limited.").font(.callout)
                Text("3PO does not send email or WhatsApp messages. Imported messages can inform a suggestion, but never authorise a Calendar or Reminders change.").font(.callout)
            }
            Section("Sources and memory") {
                Text("Calendar and Reminders use macOS access; Reminders is the to-do and shopping source of truth. Apple Mail is read-only. WhatsApp is optional and uses selected chats from its received-text cache; it is an unofficial linked-device connection and can be interrupted.").font(.callout)
                Text("Reading, brief inclusion, task suggestions, and context learning have separate controls. Missing cached content means the evidence is unavailable, not that it was deleted or completed. Saved source memories stay attributed and provisional until you confirm them.").font(.callout)
                Text("Only context permitted for the active account and selected chats can be used. Conversation learning is separate from source learning. Turning memory off stops its use in PA replies; it does not delete saved records.").font(.callout)
            }
            Section("Context pages and supporting facts") {
                Text("Collect → remember useful facts → connect them to your life and projects → recall what matters → keep it current.").font(.headline)
                Text("Open Context from the PA menu, Settings or Life map. The overview, project and topic pages sit alongside Working changes and editable feature instructions. Supporting facts and controls retains original evidence, corrections, history, a local recall preview and memory review. New PA replies expose Context details; older replies keep their original records.").font(.callout)
                Text("The PA keeps useful personal facts, preferences and relationships with their original evidence. It retrieves a bounded selection relevant to your question and Focus, rather than sending the whole notebook each time. Focus guides relevance; it never grants source access.").font(.callout)
                Text("Human corrections keep a version history. Retire sets human context aside without deleting evidence; Restore brings the same fact back. Resolve handles remembered commitments, while your projects and Apple reminders keep their own state. Unpinned organisation can be revisited after 30 days within the existing allowance; it never changes fact wording, confirms a belief or deletes one.").font(.callout)
                Text("Projects are durable parts of the same notebook. Exact saved bindings and memory links guide recall even after a project rename or a fact correction. Similar names alone are not an identity match. The Life map shows available facts and workspace anchors; inspect evidence and excluded records through Context → Supporting facts and controls.").font(.callout)
                Text("Life map items are your saved workspace entries. Open an area to see and browse its folders, projects, notes and work items separately from remembered concepts/facts. For a remembered commitment, Plan reports lets you explicitly connect accounts of the same plan; their evidence and uncertainty remain separate. Reported cancellation or completion does not update Calendar or Reminders.").font(.callout)
                Text("Learning is selective: conversation learning, optional source learning, organisation and optional weekly memory review share four automatic passes per day with a 30-minute cooldown. Receiving a message does not mean the AI has assessed it. Source learning shows baseline, waiting and assessed versions, and versions that left its bounded window.").font(.callout)
                Text("Calendar, Reminders and Mail have separate memory opt-ins in Settings → Context. Calendar uses fresh 90-day orientation, Reminders uses incomplete items, and Mail uses exact retained quotes from recently assessed emails. Each pass is bounded. Existing content starts as a baseline; Review once explicitly assesses a small batch. Normal Refresh still makes no AI calls.").font(.callout)
                Text("Memory Review flags possible duplicates, conflicts and stale provisional assumptions. Weekly review is optional; Review now is explicit. You inspect/correct facts or choose a reversible retirement. Similar names never silently merge people or projects.").font(.callout)
                Text("New briefs and Tasks suggestions can use permitted source memories. Sources and coverage → Memory supplied shows the facts they received, with evidence. Changed facts, withdrawn access, revised email assessments or later WhatsApp replies can set advice aside. Refresh prepares the current brief using available sources.").font(.callout)
            }
            Section("Background review and usage") {
                Text(model.heartbeat.statusFor(model.chatGPT.activeID)).font(.callout).foregroundStyle(.secondary)
                Text(model.emailSummaries.enabled ? "Incoming email assessment is on. It starts from new mail and coverage can be partial." : "Incoming email assessment is off.").font(.callout).foregroundStyle(.secondary)
                Text("Mail collection can continue without AI. A review can use multiple model calls; the advanced daily call cap applies to email and proactive communication review only. It is separate from your ChatGPT account's subscription availability.").font(.callout)
                Text("Mail accounts are reviewed independently after their arrival checks finish. Unavailable accounts keep their cache and pending work; their old emails and source memories do not enter the fresh comparison. Settings → Background shows which accounts were reviewed and which are waiting. Email assessment can continue while a Calendar/Reminders comparison is waiting. Source collection retries unavailable accounts. A failed heartbeat keeps completed work and checks fresh information at the next scheduled interval.").font(.callout)
                Text("Useful observations, missing plans and proposed date changes appear in Review inbox, without adding background messages to normal chat. A distinctive message can suggest changing an existing event or reminder even without a manual plan connection. The card shows the exact quote, proposed date and inferred connection. Approve applies that change; Dismiss leaves the original unchanged. View/edit opens the original item with the proposed change prefilled. Repeating items need an occurrence or series choice before approval. Ambiguous targets stay informational. There is no daily cap on useful inbox items.").font(.callout)
                Text("Open it from Dashboard → Open Review inbox or add the Review inbox widget. Settings → Background controls heartbeats, which review sources and update Today’s brief. Failed heartbeats try again at the next interval. Settings → Context controls selective learning, organisation and optional weekly memory review. Delegated work resumes through Continue queue.").font(.callout)
                Text("3PO works while the app is running and the Mac is awake. Missed heartbeats catch up once on opening or waking. Interrupted foreground requests and queued work need explicit continuation; uncertain writes are never replayed automatically.").font(.callout)
                Link("Manage ChatGPT usage",destination:URL(string:"https://chatgpt.com/settings/usage")!)
            }
            if let openHelpWindow {
                Section { Button("Open Help in its own window",action:openHelpWindow) }
            }
        }
    }
}
