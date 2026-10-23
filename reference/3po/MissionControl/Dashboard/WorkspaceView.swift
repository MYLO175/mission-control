import SwiftUI
import AppKit

struct WorkspaceView: View {
    @Bindable var model: DashboardModel
    @AppStorage("workspaceSidebar") private var sidebarVisible = true
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAppearance") private var appearance = "system"
    @AppStorage("workspaceAccent") private var accent = "sage"
    @AppStorage("workspaceColorOverrides") private var colorOverrides = "{}"
    @AppStorage("workspaceToolbarHidden") private var toolbarHidden = ""
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false
    @State private var dashboardSymbol: String?
    @State private var naming: UUID?
    @State private var name = ""
    @State private var showName = false
    @State private var legacy = false
    @State private var focusedWidgetID: UUID?
    @State private var showColors = false
    private var store: WorkspaceStore { model.workspace }
    private var palette: WorkspacePalette { .resolved(raw:colorOverrides,mode:scheme == .dark ? "dark" : "light",theme:theme,accent:accent) }
    private var accentColor: Color { palette[.accent] }
    private var background: Color { palette[.canvas] }
    var body: some View {
        VStack(spacing:0) {
            if let report = model.validationReport { HStack { Text(report).font(.caption).textSelection(.enabled); Spacer(); Button { model.validationReport = nil } label: { Image(systemName:"xmark") }.buttonStyle(.borderless).help("Dismiss validation result") }.padding(10) }
            if let error = store.error { HStack { Label(error,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange); Spacer(); if store.readOnly { Button("Original dashboard") { legacy = true } } else { Button("Dismiss") { store.error = nil } } }.padding(10) }
            if let error = model.storageError ?? model.writeError { Text(error).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(10) }
            HStack(spacing:0) {
                sidebar.frame(width:sidebarVisible ? 190 : 56)
                GeometryReader { geometry in
                    let width = max(1,geometry.size.width-32), height = max(1,geometry.size.height-32)
                    let rows = GridRules.rows(store.selected)
                    let metrics = WorkspaceGeometry(width:width,height:height,rows:rows)
                    if store.selected.widgets.isEmpty {
                        VStack(spacing:14) { Image(systemName:"square.grid.2x2").font(.largeTitle).foregroundStyle(accentColor); Text("Make this dashboard yours").font(.title2.weight(.semibold)); Text("Add a widget, then move and resize it in Edit mode.").foregroundStyle(.secondary); addMenu }.frame(maxWidth:.infinity,maxHeight:.infinity)
                    } else if width < 900 && !editing && store.selected.widgets.count > 1 {
                        VStack(spacing:10) {
                            HStack {
                                Text("Focused view").font(.caption).foregroundStyle(.secondary)
                                Picker("Widget",selection:Binding(get:{ store.selected.widgets.first(where:{ $0.id == focusedWidgetID })?.id ?? store.selected.widgets.first!.id },set:{ focusedWidgetID = $0 })) {
                                    ForEach(store.selected.widgets) { widget in Text(focusedWidgetLabel(widget)).tag(widget.id) }
                                }.labelsHidden()
                                Spacer()
                            }
                            if let widget = store.selected.widgets.first(where:{ $0.id == focusedWidgetID }) ?? store.selected.widgets.first {
                                WorkspaceTile(model:model,store:store,widget:widgetBinding(widget),editing:false,metrics:WorkspaceGeometry(width:width,height:max(1,height-38),rows:rows),focused:true)
                            }
                        }.padding(16)
                    } else {
                        ZStack(alignment:.topLeading) {
                            if editing { Canvas { context,size in
                                for x in 0..<12 { for y in 0..<rows { context.fill(Path(ellipseIn:CGRect(x:Double(x)*metrics.xStep,y:Double(y)*metrics.yStep,width:3,height:3)),with:.color(.secondary.opacity(0.2))) } }
                            }.allowsHitTesting(false) }
                            ForEach(store.selected.widgets) { widget in
                                WorkspaceTile(model:model,store:store,widget:widgetBinding(widget),editing:editing,metrics:metrics)
                            }
                        }.frame(width:width,height:height,alignment:.topLeading).coordinateSpace(name:"workspaceGrid").padding(16)
                    }
                }.clipped()
                    .background(background,in:UnevenRoundedRectangle(topLeadingRadius:20,style:.continuous))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius:20,style:.continuous))
                    .padding(.top,8)

            }
        }.background(palette[.sidebar]).tint(accentColor).foregroundStyle(palette[.text]).environment(\.workspacePalette,palette).frame(minWidth:780,minHeight:580)
            .toolbar(id:ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") ? "mission-control.workspace.native-toolbar.review-fixture" : "mission-control.workspace.native-toolbar") { windowToolbar }
            .toolbarBackground(palette[.sidebar],for:.windowToolbar)
            .toolbarBackground(.visible,for:.windowToolbar)
            .windowToolbarFullScreenVisibility(.visible)
            .background(WorkspaceWindowColour(colour:NSColor(palette[.sidebar])))
            .focusedSceneValue(\.workspaceMenu,WorkspaceMenuActions(sidebar:$sidebarVisible,editing:$editing,newDashboard:newDashboard,addWidget:addWidget,customiseToolbar:customiseToolbar,customiseColors:{ showColors = true }))
            .sheet(isPresented:$showColors) { WorkspaceColorEditor() }
            .onGeometryChange(for:CGFloat.self) {$0.size.height} action:{model.reviewSheetHeight=max(420,min(660,$0-24))}
            .task { model.start() }
            .onChange(of:store.selected.id) { focusedWidgetID = nil }
            .onChange(of:model.activityNavigation?.id) {
                guard let request=model.activityNavigation,request.registration == model.chatGPT.activeID else {model.activityNavigation=nil;return}
                editing=false;focusedWidgetID=request.widgetID
                if request.projectID == nil {model.activityNavigation=nil}
            }
            .onChange(of:model.assistantFocusRequest?.id) {
                guard let request = model.assistantFocusRequest else { return }
                editing = false
                focusedWidgetID = request.widgetID
            }
            .sheet(isPresented:$showName) { VStack(alignment:.leading,spacing:16) { Text(naming == nil ? "New dashboard" : "Edit dashboard").font(.title2.weight(.semibold)); TextField("Name",text:$name).onSubmit { saveName() }; Text("Icon").font(.headline); LazyVGrid(columns:Array(repeating:GridItem(.fixed(38)),count:6),spacing:8) { ForEach(DashboardSymbols.choices,id:\.self) { symbol in Button { dashboardSymbol=symbol } label: { Image(systemName:symbol).frame(width:32,height:32).background(dashboardSymbol == symbol ? Color.accentColor.opacity(0.15) : Color.clear,in:RoundedRectangle(cornerRadius:7)) }.buttonStyle(.borderless).accessibilityLabel(symbol).help(symbol) } }; Button("Automatic icon") { dashboardSymbol=nil }.controlSize(.small); HStack { Spacer(); Button("Cancel") { showName = false }.keyboardShortcut(.cancelAction); Button("Save") { saveName() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } }.padding(24).frame(width:360) }
            .sheet(item:$model.reviewPresentation) { ProductionReviewConversationView(model:model,conversationID:$0.id).environment(\.workspacePalette,palette) }
            .sheet(isPresented:$model.showingAIHeartbeat) { BackgroundActivityView(model:model) }
            .sheet(item:$model.selectedMessage) { DashboardView(model:model).previewSheet($0) }
            .sheet(item:$model.editTarget) { NativeItemEditor(model:model,target:$0) }
            .sheet(item:$model.calendarRemovalReview) { CalendarRemovalReviewSheet(model:model,session:$0) }
            .sheet(isPresented:$legacy) { DashboardView(model:model).frame(width:1150,height:750) }
    }
    // Native toolbar identifiers own macOS persistence; dashboard layouts remain independent.
    @ToolbarContentBuilder private var windowToolbar: some CustomizableToolbarContent {
        Group {
        ToolbarItem(id:"sidebar",placement:.navigation) {
            Button { sidebarVisible.toggle() } label: { Label("Sidebar",systemImage:"sidebar.left") }.help(sidebarVisible ? "Collapse dashboard sidebar" : "Expand dashboard sidebar")
        }.customizationBehavior(.reorderable).sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible)
        ToolbarItem(id:"heartbeatProgress") {
            EmptyView()
        }.customizationBehavior(.disabled).sharedBackgroundVisibility(.hidden)
        ToolbarItem(id:"feedback") {
            // Retain the saved toolbar identity; feedback now lives in the pill.
            EmptyView()
        }.customizationBehavior(.disabled).sharedBackgroundVisibility(.hidden)
        ToolbarItem(id:"assistant",placement:.principal) {
            DashboardAIActivityPill(model:model,palette:palette,openChat:showAssistant).frame(height:46,alignment:.center)
        }.defaultCustomization(visible(.assistant) ? .visible : .hidden).sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible)
        ToolbarItem(id:"refresh",placement:.primaryAction) {
            Button { model.heartbeat.check(model,manual:true) } label: { Label("Run heartbeat",systemImage:"waveform.path.ecg") }
                .disabled(model.heartbeat.manualCheckBlockReason(model) != nil).help(model.heartbeat.manualCheckHelp(model)+" (⌘R)")
        }.defaultCustomization(visible(.refresh) ? .visible : .hidden).sharedBackgroundVisibility(.hidden)
        }
        Group {
        ToolbarItem(id:"addWidget",placement:.primaryAction) { addMenu }.defaultCustomization(visible(.addWidget) ? .visible : .hidden).sharedBackgroundVisibility(.hidden)
        ToolbarItem(id:"edit",placement:.primaryAction) {
            Button { editing.toggle() } label: { Label(editing ? "Done" : "Edit layout",systemImage:editing ? "checkmark" : "square.grid.2x2") }.help("Arrange widgets · Drag handle/corner, release to snap")
        }.defaultCustomization(visible(.edit) ? .visible : .hidden).sharedBackgroundVisibility(.hidden)
        ToolbarItem(id:"undo",placement:.primaryAction) {
            Button { model.undoLatest() } label: { Label(model.undoLabel,systemImage:"arrow.uturn.backward") }.disabled(model.latestUndo == nil || model.writing || model.assistant.busy).help(model.undoLabel)
        }.defaultCustomization(visible(.undo) ? .visible : .hidden).sharedBackgroundVisibility(.hidden)
        ToolbarItem(id:"appearance",placement:.primaryAction) {
            Menu {
                Picker("Appearance",selection:$appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Divider()
                Button("Customise colours…") { showColors = true }
            } label: { Label("Appearance",systemImage:"paintpalette") }
        }.defaultCustomization(visible(.appearance) ? .visible : .hidden).sharedBackgroundVisibility(.hidden)
        ToolbarItem(id:"customise",placement:.primaryAction) {
            Menu {
                Button("Customise toolbar…") { customiseToolbar() }
                Section("Actions") {
                    Toggle("Show sidebar",isOn:$sidebarVisible)
                    Button("Assistant") { showAssistant() }
                    Button("Run heartbeat") { model.heartbeat.check(model,manual:true) }.disabled(model.heartbeat.manualCheckBlockReason(model) != nil).help(model.heartbeat.manualCheckHelp(model))
                    Button("Refresh sources only") { model.refresh() }.help("Update cached sources without AI (⌥⌘R)")
                    Menu("Add widget") { widgetChoices }
                    Toggle("Edit layout",isOn:$editing)
                    Button(model.undoLabel) { model.undoLatest() }.disabled(model.latestUndo == nil || model.writing || model.assistant.busy)
                    SettingsLink { Text("Settings…") }
                }
            } label: { Label("Toolbar options",systemImage:"slider.horizontal.3") }
        }.customizationBehavior(.reorderable).sharedBackgroundVisibility(.hidden)
        ToolbarItem(id:"settings",placement:.primaryAction) { SettingsLink { Label("Settings",systemImage:"gearshape") } }.sharedBackgroundVisibility(.hidden)
        }
    }
    private func newDashboard() { naming = nil; dashboardSymbol=nil; name = "New dashboard"; showName = true }
    private func addWidget(_ kind: WidgetKind) { store.addWidget(kind); editing = true }
    private func customiseToolbar() { NSApp.keyWindow?.runToolbarCustomizationPalette(nil) }
    private func showAssistant() { model.openAssistantComposer() }
    private func visible(_ tool: WorkspaceTool) -> Bool { ToolbarRules.visible(tool,hidden:toolbarHidden) }
    private func focusedWidgetLabel(_ widget:WidgetPlacement)->String {
        let title=widget.kind?.title ?? "Widget"
        let matching=store.selected.widgets.filter{$0.kindRaw == widget.kindRaw}
        guard matching.count > 1,let index=matching.firstIndex(where:{$0.id == widget.id}) else {return title}
        return "\(title) \(index+1)"
    }
    private var widgetChoices: some View { ForEach(WidgetKind.allCases,id:\.self) { kind in Button { addWidget(kind) } label: { Label(kind.title,systemImage:kind.icon) } } }
    private var addMenu: some View {
        Menu { widgetChoices } label: { Label("Add widget",systemImage:"plus") }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:12) {
            if sidebarVisible {
                Text("3PO").font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(.secondary).padding(.horizontal,12).padding(.top,8)
            }
            ScrollView {
                VStack(spacing:4) {
                    ForEach(store.state.pages) { page in
                        Button { store.select(page.id) } label: {
                            WorkspacePageLabel(model:model,title:page.title,icon:page.displayIcon,expanded:sidebarVisible,showsReview:page.widgets.contains(where:{$0.kind == .tasks}))
                            .background(page.id == store.selected.id ? accentColor.opacity(0.14) : Color.clear,
                                        in:RoundedRectangle(cornerRadius:12,style:.continuous))
                            .contentShape(RoundedRectangle(cornerRadius:12,style:.continuous))
                        }.buttonStyle(.plain)
                            .contextMenu { Button("Edit name and icon…") { naming = page.id; name = page.title; dashboardSymbol=page.symbol; showName = true }; Button("Duplicate") { store.duplicate(page.id) }; Button("Move up") { store.movePage(page.id,offset:-1) }; Button("Move down") { store.movePage(page.id,offset:1) }; Divider(); Button("Remove dashboard") { store.removePage(page.id) }.disabled(store.state.pages.count == 1) }
                    }
                }
            }.scrollIndicators(.hidden)
            Button { newDashboard() } label: {
                HStack(spacing:10) {
                    Image(systemName:"plus").font(.system(size:17)).frame(width:22)
                    if sidebarVisible { Text("New dashboard"); Spacer(minLength:0) }
                }.padding(.horizontal,sidebarVisible ? 12 : 0)
                    .frame(maxWidth:.infinity,minHeight:40,alignment:sidebarVisible ? .leading : .center)
                    .contentShape(RoundedRectangle(cornerRadius:12,style:.continuous))
            }.buttonStyle(.plain).help("New dashboard").accessibilityLabel("New dashboard")
        }.padding(.horizontal,8).padding(.vertical,12)
    }
    private func saveName() { if let naming { store.configurePage(naming,title:name,symbol:dashboardSymbol) } else { store.addPage(name,symbol:dashboardSymbol) }; showName = false }
    private func widgetBinding(_ original: WidgetPlacement) -> Binding<WidgetPlacement> { Binding(get:{ store.selected.widgets.first { $0.id == original.id } ?? original },set:{ store.update($0) }) }
}
/// Observe heartbeat updates here so stage changes do not rebuild dashboard tiles.
private struct HeartbeatToolbarProgress:View {
    var heartbeat:HeartbeatService
    var palette:WorkspacePalette
    @State private var completion:PAHeartbeatProgress?
    var body:some View {
        Group {
            if let progress=heartbeat.busy ? heartbeat.progress : completion {
                HeartbeatProgressBar(progress:progress,palette:palette)
            }
        }
        .onChange(of:heartbeat.busy) { _,busy in
            completion = !busy && heartbeat.progress?.percentage == 100 ? heartbeat.progress : nil
        }
        .task(id:completion?.runID) {
            guard completion != nil else {return}
            do {try await Task.sleep(for:.milliseconds(1200))} catch {return}
            completion=nil
        }
    }
}
private struct HeartbeatProgressBar:View {
    var progress:PAHeartbeatProgress
    var palette:WorkspacePalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        HStack(spacing:8) {
            GeometryReader { geometry in
                ZStack(alignment:.leading) {
                    Capsule().fill(palette[.text].opacity(0.1))
                    Capsule().fill(palette[.accent])
                        .frame(width:geometry.size.width*Double(progress.percentage)/100)
                }
            }.frame(width:86,height:4)
            Text("\(progress.percentage)%")
                .font(.caption.monospacedDigit()).foregroundStyle(palette[.text].opacity(0.65))
                .frame(width:32,alignment:.trailing)
        }.frame(height:24)
            .animation(reduceMotion ? nil : .easeInOut(duration:0.25),value:progress.percentage)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("Heartbeat progress")
            .accessibilityValue("\(progress.percentage) percent, \(progress.stage)")
            .help("Heartbeat · \(progress.stage) · \(progress.percentage)% of stages finished")
    }
}
#if DEBUG
struct HeartbeatProgressPreviewScreen:View {
    var model:DashboardModel
    init(model:DashboardModel) {
        self.model=model
        // An empty fictional page mounts no widget-specific source collectors.
        if !model.workspace.state.pages.contains(where:{$0.title == "Heartbeat preview"}) {
            model.workspace.addPage("Heartbeat preview")
        }
    }
    var body:some View {
        WorkspaceView(model:model).task {
            HeartbeatProgressPreview.render()
            await model.heartbeat.previewProgress()
        }
    }
}
@MainActor enum HeartbeatProgressPreview {
    static func render() {
        for mode in ["light","dark"] {
            let palette=WorkspacePalette.resolved(raw:"{}",mode:mode,theme:"warm",accent:"sage")
            let view=VStack(alignment:.leading,spacing:24) {
                ForEach([0,50,100],id:\.self) { percent in
                    HStack {
                        Text("3PO").font(.caption.weight(.semibold)).foregroundStyle(palette[.text].opacity(0.65))
                        Spacer()
                        HeartbeatProgressBar(progress:previewProgress(percent),palette:palette)
                        Image(systemName:"waveform.path.ecg").foregroundStyle(palette[.text].opacity(0.65))
                    }
                }
            }.padding(20).frame(width:400).background(palette[.sidebar]).preferredColorScheme(mode == "dark" ? .dark : .light)
            let renderer=ImageRenderer(content:view);renderer.scale=2
            if let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) {
                try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-heartbeat-progress-"+mode+".png"),options:.atomic)
            }
        }
    }
    private static func previewProgress(_ percent:Int)->PAHeartbeatProgress {
        var value=PAHeartbeatProgress(runID:"fictional",steps:[])
        value.percentage=percent;value.stage="Today’s brief";return value
    }
}
#endif
/// This child observes Review inputs, never the selected page. Navigation only
/// changes the parent's decoration; data changes still update count and accessibility.
private struct WorkspacePageLabel:View {
    var model:DashboardModel
    var title:String
    var icon:String
    var expanded:Bool
    var showsReview:Bool
    var body:some View {
        if showsReview {
            // Read-only time-sensitive source validity, without source reads or AI.
            TimelineView(.periodic(from:.now,by:60)) {_ in label(count:model.reviewInboxPendingCount)}
        } else {label(count:0)}
    }
    private func label(count:Int)->some View {
        HStack(spacing:10) {
            Image(systemName:icon).font(.system(size:16)).frame(width:22)
                .overlay(alignment:.topTrailing) {if !expanded,showsReview {ReviewInboxBadge(count:count).offset(x:10,y:-10).accessibilityHidden(true)}}
            if expanded {Text(title).lineLimit(1);Spacer(minLength:0)}
            if expanded,showsReview {ReviewInboxBadge(count:count).accessibilityHidden(true)}
        }.font(.callout).padding(.horizontal,expanded ? 12 : 0)
            .frame(maxWidth:.infinity,minHeight:40,alignment:expanded ? .leading : .center)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(title+(showsReview && count > 0 ? ", \(count) items need review" : ""))
            .help(title+(showsReview && count > 0 ? " · \(count) items need review" : ""))
    }
}
private struct WorkspaceTile: View {
    @Environment(\.workspacePalette) private var themePalette
    @Environment(\.colorScheme) private var scheme
    private var palette: WorkspacePalette { themePalette.applying(widget.configuration.colourProfiles,mode:scheme == .dark ? "dark" : "light") }
    @State private var showWidgetColours = false
    @Bindable var model: DashboardModel
    @Bindable var store: WorkspaceStore
    @Binding var widget: WidgetPlacement
    var editing: Bool
    var metrics: WorkspaceGeometry
    var focused = false
    @State private var interaction: Interaction?
    @State private var readingMode = false
    private struct Interaction { var origin: GridRect; var translation: CGSize; var resizing: Bool }
    private var baseRect: GridRect { focused ? GridRect(x:0,y:0,w:12,h:metrics.rows) : widget.rect }
    private var baseFrame: CGRect { metrics.frame(baseRect) }
    private var target: GridRect {
        guard let interaction else { return baseRect }
        return metrics.target(origin:interaction.origin,dx:interaction.translation.width,dy:interaction.translation.height,resizing:interaction.resizing,minimumColumns:widget.kind?.minimumColumns ?? 3,minimumRows:widget.kind?.minimumRows ?? 4)
    }
    private var visual: CGRect {
        guard let interaction else { return baseFrame }
        return metrics.preview(origin:interaction.origin,dx:interaction.translation.width,dy:interaction.translation.height,resizing:interaction.resizing,minimumColumns:widget.kind?.minimumColumns ?? 3,minimumRows:widget.kind?.minimumRows ?? 4)
    }
    private var valid: Bool { GridRules.valid(target,among:store.selected.widgets,excluding:widget.id,rowLimit:metrics.rows) }
    private var configuration: Binding<WidgetConfiguration> { Binding(get:{ widget.configuration },set:{ widget.configuration = $0 }) }
    var body: some View {
        ZStack(alignment:.topLeading) {
            if interaction != nil {
                let destination = metrics.frame(target)
                RoundedRectangle(cornerRadius:16).fill((valid ? Color.accentColor : .red).opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius:16).stroke(valid ? Color.accentColor : .red,style:StrokeStyle(lineWidth:2,dash:[6,4])))
                    .frame(width:destination.width,height:destination.height).offset(x:destination.minX,y:destination.minY).allowsHitTesting(false)
            }
            VStack(spacing:0) {
                if editing {
                    HStack {
                        HStack { Image(systemName:"line.3.horizontal"); Text(widget.kind?.title ?? "Unavailable widget").font(.caption.weight(.semibold)); Spacer() }.contentShape(Rectangle()).gesture(gesture(resizing:false))
                        Button { showWidgetColours = true } label: { Image(systemName:"paintpalette") }.buttonStyle(.borderless).help("Widget colours").accessibilityLabel("\(widget.kind?.title ?? "Widget") colours")
                        Menu {
                            Button("Fill page") { store.fullPage(widget) }
                            Button("Move right") { adjust(x:1) }; Button("Move left") { adjust(x:-1) }; Button("Move down") { adjust(y:1) }; Button("Move up") { adjust(y:-1) }
                            Button("Wider") { adjust(w:1) }; Button("Narrower") { adjust(w:-1) }; Button("Taller") { adjust(h:1) }; Button("Shorter") { adjust(h:-1) }
                            Divider(); Button("Remove widget") { store.removeWidget(widget.id) }
                        } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:20).accessibilityLabel("\(widget.kind?.title ?? "Widget") layout actions")
                    }.padding(.horizontal,12).frame(height:34).background(Color.accentColor.opacity(0.08))
                }
                content.environment(\.workspacePalette,palette).foregroundStyle(palette[.text]).tint(palette[.accent]).allowsHitTesting(!editing).frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            // Keep content at its committed size during the gesture; only the preview shell follows the pointer.
            .frame(width:baseFrame.width,height:baseFrame.height,alignment:.topLeading)
            .frame(width:visual.width,height:visual.height,alignment:.topLeading)
            .background(palette[.widget],in:RoundedRectangle(cornerRadius:16))
            .clipShape(RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(editing ? (valid ? palette[.accent].opacity(0.6) : .red) : palette[.border],lineWidth:editing ? 2 : 1))
            .overlay(alignment:.bottomTrailing) { if editing { Image(systemName:"arrow.down.right.and.arrow.up.left").font(.caption.weight(.bold)).padding(9).background(.regularMaterial,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle()).gesture(gesture(resizing:true)).accessibilityLabel("Resize \(widget.kind?.title ?? "widget")") } }
            .shadow(color:.black.opacity(interaction == nil ? 0.025 : 0.12),radius:interaction == nil ? 8 : 14,y:3)
            .offset(x:visual.minX,y:visual.minY)
        }.frame(width:metrics.width,height:metrics.height,alignment:.topLeading).zIndex(interaction == nil ? 0 : 1)
            .sheet(isPresented:$showWidgetColours) { WidgetColourEditor(configuration:configuration,title:widget.kind?.title ?? "Widget") }
            .onChange(of:editing) { interaction = nil }
            .onChange(of:metrics.width) { interaction = nil }
            .onChange(of:metrics.height) { interaction = nil }
    }
    @ViewBuilder private var content: some View {
        switch widget.kind {
        case .calendar: CalendarWidgetView(model:model,configuration:configuration,widgetID:widget.id)
        case .reminders: DashboardView(model:model,widgetConfiguration:configuration).remindersPanel
        case .mail: DashboardView(model:model,widgetConfiguration:configuration).inboxPanel
        case .conversation: AssistantPanel(model:model,assistant:model.assistant,readingMode:$readingMode,supportsReadingMode:false,widgetID:widget.id,configuration:configuration)
        case .overview:
            TodayBriefView(model:model,briefings:model.briefings,configuration:configuration).padding(16)
        case .emailSummary: EmailOverviewView(model:model,summaries:model.emailSummaries,configuration:configuration).padding(16)
        case .memoryGraph: PALifeMapWidget(model:model,configuration:configuration).padding(16)
        case .tasks: PATasksView(model:model).padding(16)
        case .clock: DateClockWidget(configuration:configuration)
        case .weather: WeatherWidgetView(weather:model.weather).padding(16)
        case .projects: LifeProjectWidget(model:model,configuration:configuration,widgetID:widget.id).padding(16)
        case nil: ContentUnavailableView("Widget unavailable",systemImage:"square.dashed",description:Text("Its saved placement is preserved for a future app version."))
        }
    }
    private func gesture(resizing: Bool) -> some Gesture {
        DragGesture(minimumDistance:3,coordinateSpace:.named("workspaceGrid"))
            .onChanged { value in
                if interaction == nil { interaction = Interaction(origin:widget.rect,translation:.zero,resizing:resizing) }
                interaction?.translation = value.translation
            }
            .onEnded { _ in
                let destination = target
                withAnimation(.snappy(duration:0.18)) {
                    if valid && destination != widget.rect { var next = widget; next.rect = destination; store.update(next) }
                    interaction = nil
                }
            }
    }
    private func adjust(x: Int = 0,y: Int = 0,w: Int = 0,h: Int = 0) { var next = widget; next.rect.x += x; next.rect.y += y; next.rect.w = max(widget.kind?.minimumColumns ?? 3,next.rect.w+w); next.rect.h = max(widget.kind?.minimumRows ?? 4,next.rect.h+h); store.update(next) }
}
