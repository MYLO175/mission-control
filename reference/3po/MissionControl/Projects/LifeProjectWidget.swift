import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum LifeProjectPresentation: String, CaseIterable, Identifiable {
    // Raw values are saved layout/tool identities; only display names change.
    case overview = "Overview", list = "List", board = "Board", outline = "Outline", deadlines = "Deadlines"
    var id: String { rawValue }
    var title:String { switch self { case .overview:"Folders";case .outline:"Tree";default:rawValue } }
    var symbol:String { switch self { case .overview:"rectangle.grid.2x2";case .list:"list.bullet";case .board:"rectangle.split.3x1";case .outline:"list.bullet.indent";case .deadlines:"calendar" } }
}
struct LifeProjectWidget: View {
    @Bindable var model: DashboardModel
    var configuration: Binding<WidgetConfiguration>
    var widgetID:UUID? = nil
    var showsHeader = true
    var topicScope:UUID? = nil
    var previewRegistration: String? = nil
    var focusAreas: [LifeArea] = []
    @Environment(\.workspacePalette) private var palette
    @State private var navigation = LifeProjectNavigation()
    @State private var unfiled=false
    @State private var notesEditing: LifeNoteEditing?
    @State private var editing: LifeItem?
    @State private var linking: LifeItem?
    @State private var inspecting=false
    @State private var contextProject:LifeItem?
    @State private var nextContextProject:LifeItem?
    @State private var notice: String?
    @State private var moving:LifeItem?
    @State private var deleting:LifeItem?
    @State private var showDeleted=false
    @State private var matching:LifeItem?
    @State private var drag:LifeProjectDrag?
    @State private var dropHover:String?
    @State private var hoveredFolder:UUID?
    @State private var folderDrag:LifeFolderDrag?
    @State private var folderFrames:[UUID:CGRect]=[:]
    @State private var folderInsertion:LifeFolderInsertion?
    @State private var boardDrag:LifeBoardDrag?
    @State private var stageFrames:[String:CGRect]=[:]
    @State private var availableWidth:CGFloat=300
    @State private var viewportHeight:CGFloat=0
    @State private var precedingNotesHeight:CGFloat=0
    @State private var boardScroll=LifeBoardScrollController()
    private var registration: String { previewRegistration ?? model.chatGPT.activeID }
    private var store: LifeWorkspaceStore { model.assistant.projects }
    @State private var projectionCache = LifeProjectProjectionCache()
    private var index: LifeProjectIndex {
        projectionCache.value(owner:store,revision:store.revision,registration:registration,topic:topicScope,focusAreas:focusAreas) {
            store.items(registration,topic:topicScope)
        }
    }
    private var items: [LifeItem] { index.items }
    private var savedRoot: UUID? { configuration.wrappedValue.projectRoots?[registration].flatMap(UUID.init(uuidString:)) }
    private var currentID: UUID? { navigation.destination(startingAt:savedRoot) }
    private var current: LifeItem? { currentID.flatMap { index.byID[$0] } }
    private var atHome:Bool { current == nil && !unfiled }
    private var presentation: LifeProjectPresentation {
        let saved=currentID.flatMap{configuration.wrappedValue.projectFolderViews?[registration]?[$0.uuidString]}
        return LifeProjectPresentation(rawValue:saved ?? configuration.wrappedValue.projectView ?? "") ?? .overview
    }
    private var unfinished: Bool { configuration.wrappedValue.projectOnlyUnfinished == true }
    private var children:[LifeItem] { index.children(of:current?.id,unfinished:unfinished) }
    private var folders:[LifeItem] { children.filter{!$0.kind.isWork} }
    private var work:[LifeItem] { children.filter{$0.kind.isWork && $0.status != .archived} }
    private var looseWork:[LifeItem] { index.children(of:nil).filter{$0.kind.isWork} }
    private var filtered:[LifeItem] { unfiled ? children.filter{$0.kind.isWork} : atHome ? folders : children }
    private func shows(_ section:ProjectPageSection)->Bool {
        guard let current,!current.kind.isWork else {return true}
        return configuration.wrappedValue.showsProjectSection(section,registration:registration,folder:current.id)
    }
    private var displayed:[LifeItem] {filtered.filter{shows($0.kind.isWork ? .tasks : .spaces)}}
    private var viewTitle:String { !shows(.tasks) && (presentation == .overview || presentation == .board) ? "Folders" : presentation == .overview && !atHome ? "Board" : presentation.title }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:24) { pageHeading;Spacer(minLength:12);controls }
                VStack(alignment:.leading,spacing:12) { pageHeading;HStack { Spacer();controls } }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment:.leading,spacing:22) {
                        if let current { projectPage(current) }
                        if atHome { folderGrid(folders,includeUnfiled:true) }
                        else if current?.kind.isWork != true {
                            if filtered.isEmpty && (shows(.spaces) || shows(.tasks)) {
                                Text(unfinished ? "No unfinished work here." : "This folder is empty.").font(.callout).foregroundStyle(.secondary).padding(.vertical,12)
                            }
                            switch presentation {
                            case .overview,.board:
                                if !unfiled && shows(.spaces) && !folders.isEmpty { folderGrid(folders) }
                                if shows(.tasks) { board }
                            case .list:
                                if shows(.spaces) { rows(filtered.filter{!$0.kind.isWork}) }
                                if shows(.tasks) { taskList }
                            case .outline: outline
                            case .deadlines: deadlines
                            }
                        }
                    }.onGeometryChange(for:CGFloat.self) {$0.size.height} action:{precedingNotesHeight=$0}
                    if let current,shows(.notes) {
                        LifeNotesSection(model:model,item:current,availableWidth:availableWidth,availableHeight:viewportHeight-precedingNotesHeight-30) {notesEditing=$0}
                    }
                    if atHome && folders.isEmpty && looseWork.isEmpty {
                        Button { add(.space) } label: { Label("New space",systemImage:"plus").padding(.vertical,20) }.buttonStyle(.plain).foregroundStyle(palette[.accent]).disabled(store.readOnly || registration.isEmpty)
                    }
                    if let error = store.error ?? notice { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom,8)
            }.onGeometryChange(for:CGFloat.self) {$0.size.height} action:{viewportHeight=$0}
            .id((current?.id.uuidString ?? (unfiled ? "unfiled" : "home"))+":"+presentation.rawValue)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $editing) { item in LifeItemEditor(model: model, item: item) { editing = nil } }
        .sheet(item: $notesEditing) { capture in LifeProjectNotesSheet(model:model,capture:capture) }
        .sheet(item:$matching) { item in LifeIdentitySheet(model:model,item:item) { matching=nil } }
        .sheet(item:$moving) { item in LifeMoveSheet(model:model,item:item) { moving=nil } }
        .sheet(item:$deleting) { item in LifeDeleteSheet(model:model,item:item) { deleting=nil } }
        .sheet(isPresented:$showDeleted) { LifeRecentlyDeleted(model:model,registration:registration) }
        .sheet(item: $linking) { item in LifeItemLinkEditor(model: model, item: item) { linking = nil } }
        .sheet(item:$contextProject) { item in ContextPagesView(model:model,registration:item.registration,projectID:item.id) }
        .sheet(isPresented:$inspecting,onDismiss:{
            if let nextContextProject { contextProject=nextContextProject;self.nextContextProject=nil }
        }) {
            VStack(alignment:.leading,spacing:16) {
                HStack { Text("Connections & organisation").font(.title2.weight(.semibold));Spacer();Button("Done") { inspecting=false } }
                if let current { Text(current.title).font(.callout).foregroundStyle(.secondary);ScrollView { details(current) } }
            }.padding(24).frame(width:540,height:460)
        }
        .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { availableWidth=$0 }
        .onAppear {consumeActivityNavigation()}
        .onChange(of:model.activityNavigation?.id) {consumeActivityNavigation()}
        .onChange(of: registration) { boardScroll.stop();navigation = .init(); unfiled=false;notesEditing=nil; editing = nil; linking = nil;moving=nil;deleting=nil;matching=nil;drag=nil;folderDrag=nil;folderInsertion=nil;boardDrag=nil;dropHover=nil;showDeleted=false;inspecting=false;contextProject=nil;nextContextProject=nil; notice = nil }
        .onChange(of:store.revision) { navigation.reconcile(items:items);boardScroll.stop();boardDrag=nil;folderInsertion=nil;dropHover=nil }
        .onChange(of:focusAreas) { navigation.reconcile(items:items);resetPage() }
        .onChange(of: savedRoot) { navigation = .init();unfiled=false;resetPage() }
    }
    private var controls:some View {
        HStack(spacing:14) {
            if !atHome,current?.kind.isWork != true {
                Menu {
                    ForEach([LifeProjectPresentation.overview,.list,.board]) { view in
                        Toggle(view == .overview ? "Folders & tasks" : view.title,isOn:Binding(get:{presentation == view},set:{if $0 { setPresentation(view) }}))
                    }
                    Menu("More views") { Button("Tree") { setPresentation(.outline) };Button("Deadlines") { setPresentation(.deadlines) } }
                    Divider()
                    Toggle("Hide finished tasks", isOn: Binding(get: { unfinished }, set: { value in var config = configuration.wrappedValue; config.projectOnlyUnfinished = value; configuration.wrappedValue = config }))
                } label: { HStack(spacing:5) { Image(systemName:presentation.symbol);if availableWidth >= 420 { Text(viewTitle) };if unfinished { Image(systemName:"line.3.horizontal.decrease").font(.caption2) } }.font(.callout) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Project view: " + viewTitle)
            }
            if current?.kind.isWork != true {
                Menu {
                    ForEach(LifeItemKind.allCases) { kind in Button(kind.title) { add(kind) } }
                } label: { Image(systemName:"plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Add to this folder").disabled(registration.isEmpty || store.readOnly)
            }
            Menu {
                if let current {
                    if !current.kind.isWork {
                        Menu("Show on this page") {
                            ForEach(ProjectPageSection.allCases) {section in
                                Toggle(section.title,isOn:sectionBinding(section,item:current))
                            }
                        }
                        Divider()
                    }
                    Button("Edit details…") { editing=current };Button("Edit notes…") { notesEditing=LifeNoteEditing(item:current,noteID:current.notes.isEmpty ? nil : current.id) }
                    if !current.kind.isWork { Button("Context and purpose…") { contextProject=current } }
                    Button("Connections & organisation…") { inspecting=true }
                    Button("Move…") { moving=current }
                    Divider()
                    Toggle(current.kind.isWork ? "Open this task by default" : "Open this folder by default",isOn:Binding(get:{savedRoot == current.id},set:{setRoot($0 ? current.id : nil)}))
                    Button("Delete…",role:.destructive) { deleting=current }
                }
                if savedRoot != nil { Button("Open Projects home by default") { setRoot(nil) };Divider() }
                Button("Recently deleted…") { showDeleted=true }
            } label: { Image(systemName:"ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Folder options")
        }.foregroundStyle(palette[.accent])
    }
    private func sectionBinding(_ section:ProjectPageSection,item:LifeItem)->Binding<Bool> {
        Binding(get:{configuration.wrappedValue.showsProjectSection(section,registration:item.registration,folder:item.id)},set:{visible in
            guard registration == item.registration,current?.id == item.id else {return}
            var config=configuration.wrappedValue
            config.setProjectSection(section,visible:visible,registration:item.registration,folder:item.id)
            configuration.wrappedValue=config;resetPage()
        })
    }
    private var pageProgress:LifeTaskProgress {
        if let current,!current.kind.isWork { return index.progress(under:current.id) }
        return LifeTaskProgress(items:unfiled ? looseWork : [])
    }
    private var pageHeading:some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:24) {
                breadcrumbs
                if pageProgress.total > 0 { LifeTaskProgressView(progress:pageProgress).frame(width:144) }
            }
            VStack(alignment:.leading,spacing:12) {
                breadcrumbs
                if pageProgress.total > 0 { LifeTaskProgressView(progress:pageProgress).frame(width:120) }
            }
        }
    }
    private var breadcrumbs:some View {
        let path=current.map{index.path($0)} ?? []
        return ViewThatFits(in:.horizontal) {
            breadcrumbPath(path,compact:false)
            breadcrumbPath(path,compact:true)
        }
    }
    private func breadcrumbPath(_ path:[LifeItem],compact:Bool)->some View {
        HStack(spacing:8) {
            Button { navigateHome() } label: {
                if atHome { Label("Projects",systemImage:"folder").font(showsHeader ? .title3.weight(.semibold) : .callout.weight(.semibold)) }
                else { Image(systemName:"house").font(.callout) }
            }.buttonStyle(.plain).help("Projects home").accessibilityLabel("Projects home")
            if compact,path.count > 1 {
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                Menu { ForEach(path.dropLast()) { item in Button(item.title) { open(item) } } } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Parent folders")
            }
            ForEach(compact ? Array(path.suffix(1)) : path) { item in
                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                Button(item.title) { open(item) }.buttonStyle(.plain).font(.callout.weight(item.id == current?.id ? .semibold : .regular)).foregroundStyle(item.id == current?.id ? palette[.text] : palette[.text].opacity(0.65)).lineLimit(1).help(item.title)
            }
            if unfiled { Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary);Text("Unfiled tasks").font(.callout.weight(.semibold)) }
        }.fixedSize(horizontal:!compact,vertical:false)
    }
    private func setPresentation(_ value:LifeProjectPresentation) {
        var config=configuration.wrappedValue
        if let currentID { var accounts=config.projectFolderViews ?? [:];var folders=accounts[registration] ?? [:];folders[currentID.uuidString]=value.rawValue;accounts[registration]=folders;config.projectFolderViews=accounts }
        else {config.projectView=value.rawValue}
        configuration.wrappedValue=config
    }
    private func resetPage() { notice=nil;inspecting=false;boardScroll.stop();boardDrag=nil;folderDrag=nil;folderInsertion=nil;drag=nil;dropHover=nil }
    private func consumeActivityNavigation() {
        guard let request=model.activityNavigation,request.registration == registration,request.widgetID == widgetID,let id=request.projectID else {return}
        model.activityNavigation=nil
        guard let item=index.byID[id] else {notice="This saved project is no longer available.";return}
        open(item)
    }
    private func navigateHome() { navigation.home();unfiled=false;resetPage() }
    private func setRoot(_ id: UUID?) {
        var config = configuration.wrappedValue
        if config.projectRoots == nil { config.projectRoots = [:] }
        config.projectRoots?[registration] = id?.uuidString ?? ""; configuration.wrappedValue = config
        navigation = .init();unfiled=false;resetPage()
    }
    private func open(_ item: LifeItem) { navigation.open(item.id);unfiled=false;resetPage() }
    private func add(_ kind:LifeItemKind,stage:LifeTaskStage = .todo) {
        var item=LifeItem(registration:registration,conversationID:current?.conversationID ?? topicScope,kind:kind,title:"",parentID:current?.id,areas:current?.areas ?? Array(focusAreas.prefix(3)))
        if kind.isWork { item.status=stage.status }
        editing=item
    }
    private func complete(_ item:LifeItem) { setStatus(item,item.status == .done ? .planned : .done) }
    private func setStatus(_ item:LifeItem,_ status:LifeItemStatus) {
        guard registration == model.chatGPT.activeID,item.registration == registration else { return }
        var value=item;value.status=status
        do { _ = try store.save(value,expected:item.revision);notice=nil } catch { notice=error.localizedDescription }
    }
    @ViewBuilder private func projectPage(_ item:LifeItem)->some View {
        if item.kind.isWork || item.due != nil || item.estimateMinutes != nil {
            VStack(alignment:.leading,spacing:14) {
                if item.kind.isWork {
                    Text(item.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Picker("Stage",selection:Binding(get:{item.status},set:{setStatus(item,$0)})) {
                        ForEach(LifeTaskStage.allCases) { Text($0.rawValue).tag($0.status) }
                        if item.status == .waiting || item.status == .archived { Text(item.status.title).tag(item.status) }
                    }.pickerStyle(.segmented).disabled(store.readOnly)
                }
                if item.due != nil || item.estimateMinutes != nil {
                    ViewThatFits(in:.horizontal) { HStack(spacing:12) { properties(item) };VStack(alignment:.leading,spacing:4) { properties(item) } }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    @ViewBuilder private func properties(_ item:LifeItem)->some View {
        if let due=item.due { Label(LifeWorkspaceRules.displayDate(due),systemImage:"calendar") }
        if let minutes=item.estimateMinutes { Label("\(minutes) min",systemImage:"clock") }
    }
    private func folderGrid(_ values:[LifeItem],includeUnfiled:Bool=false)->some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:min(160,max(80,availableWidth))),spacing:20,alignment:.top)],alignment:.leading,spacing:18) {
            ForEach(values) { item in
                interactive(item,filing:false) {
                    Button { open(item) } label: { folderTile(item) }.buttonStyle(.plain)
                }
                .background(GeometryReader { proxy in Color.clear.preference(key:LifeFolderFrames.self,value:[item.id:proxy.frame(in:.named("project-folders"))]) })
                .overlay(alignment:folderInsertion?.after == true ? .trailing : .leading) {
                    if folderInsertion?.target == item.id {
                        Capsule().fill(palette[.accent]).frame(width:3).padding(.vertical,12).offset(x:folderInsertion?.after == true ? 10 : -10).allowsHitTesting(false)
                    }
                }
                .highPriorityGesture(folderGesture(item))
                .offset(folderDrag?.capture.id == item.id ? folderDrag?.translation ?? .zero : .zero)
                .zIndex(folderDrag?.capture.id == item.id ? 1 : 0)
                .accessibilityHint("Drag to reorder. More options include Move earlier and Move later.")
            }
            if includeUnfiled,!looseWork.isEmpty {
                Button { navigation.home();unfiled=true;resetPage() } label: {
                    VStack(spacing:12) {
                        Image(systemName:"tray.fill").font(.system(size:42)).foregroundStyle(palette[.text].opacity(0.35)).frame(height:52)
                        Text("Unfiled tasks").font(.callout.weight(.medium)).foregroundStyle(palette[.text])
                        Text("\(looseWork.count)").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical,16).frame(maxWidth:.infinity,minHeight:140,alignment:.top).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .coordinateSpace(name:"project-folders")
        .onPreferenceChange(LifeFolderFrames.self) { folderFrames=$0 }
        .onDisappear { folderDrag=nil;folderInsertion=nil }
    }
    private func folderTile(_ item:LifeItem)->some View {
        VStack(spacing:12) {
            Image(systemName:item.icon ?? "folder.fill").font(.system(size:48,weight:.regular)).foregroundStyle(palette[.accent].opacity(0.85))
            Text(item.title).font(.callout.weight(.medium)).foregroundStyle(palette[.text]).multilineTextAlignment(.center).lineLimit(3).frame(maxWidth:.infinity)
            let progress=index.progress(under:item.id)
            if progress.total > 0 { LifeTaskProgressView(progress:progress,compact:true).frame(maxWidth:96) }
            else { let count=index.children(of:item.id).count;Text(count == 0 ? "" : "\(count) inside").font(.caption2).foregroundStyle(.secondary) }
        }.padding(.vertical,16).padding(.horizontal,8).frame(maxWidth:.infinity,minHeight:140,alignment:.top)
            .background(palette[.input].opacity(folderDrag?.capture.id == item.id ? 0.8 : hoveredFolder == item.id ? 0.35 : 0),in:RoundedRectangle(cornerRadius:12))
            .contentShape(RoundedRectangle(cornerRadius:12))
            .onHover { inside in hoveredFolder=inside ? item.id : hoveredFolder == item.id ? nil : hoveredFolder }
    }
    private func reorderPeers(_ item:LifeItem)->[LifeItem] {
        folders.filter{$0.parentID == item.parentID && $0.conversationID == item.conversationID}
    }
    private func folderGesture(_ item:LifeItem)->some Gesture {
        DragGesture(minimumDistance:6,coordinateSpace:.named("project-folders"))
            .onChanged { value in
                guard !store.readOnly,registration == model.chatGPT.activeID else { return }
                if folderDrag == nil {
                    folderDrag = .init(capture:.init(id:item.id,registration:registration,revision:store.revision),page:current?.id,parent:item.parentID,peers:reorderPeers(item).map(\.id),frames:folderFrames,translation:.zero)
                }
                guard let captured=folderDrag,captured.capture.id == item.id,captured.capture.revision == store.revision else { return }
                folderDrag?.translation=value.translation
                folderInsertion=LifeFolderOrder.insertion(at:value.location,dragging:item.id,orderedIDs:captured.peers,frames:captured.frames)
            }
            .onEnded { value in
                defer { folderDrag=nil;folderInsertion=nil }
                guard let captured=folderDrag,captured.capture.id == item.id,
                      let insertion=LifeFolderOrder.insertion(at:value.location,dragging:item.id,orderedIDs:captured.peers,frames:captured.frames) else { return }
                do {
                    try LifeFolderReorder.apply(item.id,before:insertion.before,parent:captured.parent,capturedPage:captured.page,currentPage:current?.id,registration:captured.capture.registration,activeRegistration:model.chatGPT.activeID,capturedIDs:Set(captured.peers),currentIDs:Set(reorderPeers(item).map(\.id)),expectedRevision:captured.capture.revision,store:store)
                    notice=nil
                } catch { notice=error.localizedDescription }
            }
    }
    private func moveFolder(_ item:LifeItem,earlier:Bool) {
        let peers=reorderPeers(item)
        guard let index=peers.firstIndex(where:{$0.id == item.id}),earlier ? index > 0 : index+1 < peers.count else { return }
        let before=earlier ? peers[index-1].id : peers.dropFirst(index+2).first?.id
        do {
            try LifeFolderReorder.apply(item.id,before:before,parent:item.parentID,capturedPage:current?.id,currentPage:current?.id,registration:registration,activeRegistration:model.chatGPT.activeID,capturedIDs:Set(peers.map(\.id)),currentIDs:Set(peers.map(\.id)),expectedRevision:store.revision,store:store)
            notice=nil
        } catch { notice=error.localizedDescription }
    }
    private func card(_ item:LifeItem,filing:Bool=true,showStage:Bool=true)->some View {
        interactive(item,filing:filing) {
            HStack(alignment:.top,spacing:9) {
                if item.kind.isWork {
                    Button { complete(item) } label:{Image(systemName:item.status == .done ? "checkmark.circle.fill" : "circle").font(.body).foregroundStyle(item.status == .done ? LifeTaskStage.done.color : palette[.text].opacity(0.4))}.buttonStyle(.plain).accessibilityLabel((item.status == .done ? "Mark incomplete: " : "Complete task: ")+item.title).help("Changes this workspace task only").disabled(store.readOnly).padding(.top,2)
                } else { Image(systemName:item.displaySymbol).foregroundStyle(palette[.accent]).padding(.top,2) }
                Group {
                    VStack(alignment:.leading,spacing:5) {
                        Text(item.title).font(.callout.weight(.medium)).foregroundStyle(palette[.text]).fixedSize(horizontal:false,vertical:true)
                        if showStage && item.kind.isWork || item.status == .waiting { Text(item.status.title).font(.caption).foregroundStyle(.secondary) }
                        HStack(spacing:8) { properties(item) }.font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                }.contentShape(Rectangle()).onTapGesture { open(item) }.accessibilityAddTraits(.isButton).accessibilityAction { open(item) }
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(palette[.input].opacity(0.5),in:RoundedRectangle(cornerRadius:9))
        }
    }
    @ViewBuilder private func interactive<Content:View>(_ item:LifeItem,filing:Bool=true,@ViewBuilder content:()->Content)->some View {
        let actions=content().contentShape(Rectangle())
            .contextMenu {
                Button("Open") { open(item) }
                if !item.kind.isWork {
                    let peers=reorderPeers(item)
                    Button("Move earlier") { moveFolder(item,earlier:true) }.disabled(store.readOnly || peers.first?.id == item.id || !peers.contains{$0.id == item.id})
                    Button("Move later") { moveFolder(item,earlier:false) }.disabled(store.readOnly || peers.last?.id == item.id || !peers.contains{$0.id == item.id})
                }
                if item.kind.isWork { Menu("Stage") { ForEach(LifeTaskStage.allCases) { stage in Button(stage.rawValue) { setStatus(item,stage.status) } } } }
                Button("Edit details…") { editing=item };Button("Edit notes…") { notesEditing=LifeNoteEditing(item:item,noteID:item.notes.isEmpty ? nil : item.id) };Button("Move…") { moving=item };Button("Link something…") { linking=item };Button("Match PA understanding…") { matching=item };Divider();Button("Delete…",role:.destructive) { deleting=item }
            }
        if filing {
            actions.onDrag { drag = .init(id:item.id,registration:registration,revision:store.revision);let provider=NSItemProvider();provider.registerDataRepresentation(forTypeIdentifier:LifeProjectDrag.type.identifier,visibility:.ownProcess) { complete in complete(Data(item.id.uuidString.utf8),nil);return nil };return provider }.onDrop(of:[LifeProjectDrag.type],delegate:LifeProjectDrop(target:item.id,parent:item.kind.isWork ? item.parentID : item.id,before:item.kind.isWork ? item.id : nil,drag:$drag,hover:$dropHover,key:item.id.uuidString,store:store,activeRegistration:{model.chatGPT.activeID},report:{notice=$0}))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(dropHover == item.id.uuidString ? palette[.accent] : .clear,lineWidth:2))
        } else {actions}
    }
    private func rows(_ values: [LifeItem]) -> some View { LazyVStack(alignment:.leading,spacing:7) { ForEach(values) { card($0) } } }
    private func collapsed(_ id:UUID)->Bool { configuration.wrappedValue.projectCollapsed?[registration]?.contains(id.uuidString) == true }
    private func toggle(_ id:UUID) { var config=configuration.wrappedValue;var values=Set(config.projectCollapsed?[registration] ?? []);if !values.insert(id.uuidString).inserted { values.remove(id.uuidString) };if config.projectCollapsed == nil { config.projectCollapsed=[:] };config.projectCollapsed?[registration]=values.sorted();configuration.wrappedValue=config }
    private var outlineItems:[LifeItem] {
        guard !unfiled else { return work }
        var result:[LifeItem]=[]
        func visit(_ parent:UUID?) {
            for item in index.children(of:parent,unfinished:unfinished) {
                let visible=shows(item.kind.isWork ? .tasks : .spaces)
                if visible {result.append(item)}
                if !visible || !collapsed(item.id) {visit(item.id)}
            }
        }
        visit(current?.id);return result
    }
    private var outline:some View {
        LazyVStack(alignment:.leading,spacing:4) {
            ForEach(Array(outlineItems.prefix(120))) { item in
                let depth=max(0,index.path(item).count-(current.map{index.path($0).count} ?? 0)-1)
                VStack(spacing:0) {
                    if drag != nil { Rectangle().fill(dropHover == "before:"+item.id.uuidString ? palette[.accent] : palette[.border].opacity(0.4)).frame(height:6)
                        .onDrop(of:[LifeProjectDrag.type],delegate:LifeProjectDrop(target:item.id,parent:item.parentID,before:item.id,drag:$drag,hover:$dropHover,key:"before:"+item.id.uuidString,store:store,activeRegistration:{model.chatGPT.activeID},report:{notice=$0})) }
                    HStack(spacing:5) {
                        if !index.children(of:item.id).isEmpty { Button { toggle(item.id) } label:{Image(systemName:collapsed(item.id) ? "chevron.right" : "chevron.down").frame(width:16)}.buttonStyle(.plain).accessibilityLabel((collapsed(item.id) ? "Expand " : "Collapse ")+item.title) }
                        else { Color.clear.frame(width:16,height:1) }
                        card(item)
                    }
                }.padding(.leading,CGFloat(min(depth,8))*14)
            }
            if outlineItems.count > 120 { Text("Showing 120 items. Open a folder to see more.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func stageHeader(_ stage:LifeTaskStage,count:Int)->some View {
        HStack(spacing:7) {
            Circle().fill(stage.color).frame(width:7,height:7)
            Text(stage.rawValue).font(.caption.weight(.semibold))
            Text(String(count)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Spacer(minLength:4)
            Button { add(.task,stage:stage) } label: { Image(systemName:"plus").font(.system(size:12,weight:.medium)).frame(width:24,height:24).contentShape(RoundedRectangle(cornerRadius:6)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Add a task to "+stage.rawValue).accessibilityLabel("Add task: "+stage.rawValue).disabled(store.readOnly || registration.isEmpty)
        }.padding(.horizontal,3)
    }
    private var taskList:some View {
        VStack(alignment:.leading,spacing:18) {
            ForEach(LifeTaskStage.allCases) { stage in
                let tasks=work.filter{LifeTaskStage.stage(for:$0.status) == stage}
                VStack(alignment:.leading,spacing:8) { stageHeader(stage,count:tasks.count);rows(tasks) }
            }
            let archived=filtered.filter{$0.kind.isWork && $0.status == .archived}
            if !archived.isEmpty { Text("Archived").font(.caption).foregroundStyle(.secondary);rows(archived) }
        }
    }
    private var board:some View {
        let columns=availableWidth >= 560 ? 3 : availableWidth >= 380 ? 2 : 1
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(minimum:0),alignment:.top),count:columns),alignment:.leading,spacing:12) {
            ForEach(LifeTaskStage.allCases) { stage in
                let tasks=work.filter{LifeTaskStage.stage(for:$0.status) == stage}
                VStack(alignment:.leading,spacing:9) {
                    stageHeader(stage,count:tasks.count)
                    ForEach(tasks) { item in
                        card(item,filing:false,showStage:false)
                            .highPriorityGesture(boardGesture(item))
                            .offset(boardDrag?.capture.id == item.id ? boardDrag?.translation ?? .zero : .zero)
                            .zIndex(boardDrag?.capture.id == item.id ? 1 : 0)
                    }
                    if tasks.isEmpty { Color.clear.frame(height:28) }
                    Spacer(minLength:12)
                }.padding(9).frame(maxWidth:.infinity,minHeight:150,maxHeight:.infinity,alignment:.topLeading).contentShape(Rectangle()).background(stage.color.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
                    .overlay(RoundedRectangle(cornerRadius:12).stroke(dropHover == "stage:"+stage.id ? stage.color : .clear,lineWidth:2))
                    .background(GeometryReader { proxy in Color.clear.preference(key:LifeBoardStageFrames.self,value:[stage.id:proxy.frame(in:.named("project-board"))]) })
                    .zIndex(tasks.contains(where:{$0.id == boardDrag?.capture.id}) ? 1 : 0)
            }
        }.background(LifeBoardScrollProbe(controller:boardScroll).allowsHitTesting(false)).coordinateSpace(name:"project-board").onPreferenceChange(LifeBoardStageFrames.self) { stageFrames=$0 }.onDisappear { boardScroll.stop();boardDrag=nil;dropHover=nil }
    }
    private func boardGesture(_ item:LifeItem)->some Gesture {
        DragGesture(minimumDistance:6,coordinateSpace:.named("project-board"))
            .onChanged { value in
                guard !store.readOnly,registration == model.chatGPT.activeID else { return }
                if boardDrag == nil { boardDrag = .init(capture:.init(id:item.id,registration:registration,revision:store.revision),parent:current?.id,permittedIDs:Set(work.map(\.id)),translation:.zero) }
                guard boardDrag?.capture.id == item.id else { return }
                boardDrag?.translation=value.translation
                dropHover=LifeTaskStage.allCases.first(where:{stageFrames[$0.id]?.contains(value.location) == true}).map{"stage:"+$0.id}
                boardScroll.track(value.location) { delta,point in
                    guard boardDrag?.capture.id == item.id,boardDrag?.capture.revision == store.revision,registration == model.chatGPT.activeID else {boardScroll.stop();return}
                    boardDrag?.translation.height += delta
                    dropHover=LifeTaskStage.allCases.first(where:{stageFrames[$0.id]?.contains(point) == true}).map{"stage:"+$0.id}
                }
            }
            .onEnded { value in
                let location=boardScroll.currentPoint() ?? value.location
                defer { boardScroll.stop();boardDrag=nil;dropHover=nil }
                guard let captured=boardDrag,captured.capture.id == item.id,
                      let stage=LifeTaskStage.allCases.first(where:{stageFrames[$0.id]?.contains(location) == true}) else { return }
                do {
                    try LifeTaskStageChange.applyDrag(captured.capture.id,stage:stage,capturedParent:captured.parent,currentParent:current?.id,registration:captured.capture.registration,activeRegistration:model.chatGPT.activeID,capturedIDs:captured.permittedIDs,currentIDs:Set(work.map(\.id)),expectedRevision:captured.capture.revision,store:store)
                    notice=nil
                } catch { notice=error.localizedDescription }
            }
    }
    private var deadlines:some View {
        VStack(alignment:.leading,spacing:10) {
            let dates=Set(displayed.compactMap(\.due)).sorted()
            ForEach(dates,id:\.self) { due in Text(LifeWorkspaceRules.displayDate(due)).font(.caption).foregroundStyle(.secondary);rows(displayed.filter{$0.due == due}) }
            let undated=displayed.filter{$0.due == nil}
            if !undated.isEmpty { Text("No deadline").font(.caption).foregroundStyle(.secondary);rows(undated) }
        }
    }
    @ViewBuilder private func details(_ item: LifeItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let placement=item.placement {
                Text("Where this belongs").font(.headline)
                if let question=placement.question,placement.status == "question" {
                    Text(question).font(.callout)
                    ForEach(placement.choices) { choice in Button(choice.label) { model.projectPlacement.choose(choice,for:item,model:model) }.controlSize(.small) }
                } else if ["paused","unplaced"].contains(placement.status) {
                    Text("The PA hasn’t finished suggesting a home for this item.").font(.callout).foregroundStyle(.secondary)
                    Button("Suggest a folder") { model.projectPlacement.retry(item,model:model) }.disabled(model.projectPlacement.busy)
                    if !placement.reason.isEmpty { DisclosureGroup("Details") { Text(placement.reason).font(.caption).textSelection(.enabled) } }
                } else if !placement.reason.isEmpty { Text(placement.reason).font(.callout).foregroundStyle(.secondary) }
                if placement.parentPinned { Label("You chose this folder",systemImage:"pin.fill").font(.caption).foregroundStyle(.secondary) }
            }
            if !item.kind.isWork {
                Button("Context and purpose…") { nextContextProject=item;inspecting=false }.controlSize(.small)
            }
            HStack { Button("Link something…") { inspecting=false;linking=item };Button("Match PA understanding…") { inspecting=false;matching=item } }.controlSize(.small)
            if let evidence=item.humanEvidence { DisclosureGroup("Created from your PA conversation") { Text(evidence).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.font(.caption) }
            let understanding=model.assistant.memory.notebook(registration,topic:item.conversationID)
            let factIDs=understanding.anchors.first{$0.id == "life:"+item.id.uuidString}?.memoryIDs ?? []
            let facts=understanding.notes.flatMap(\.records).filter{factIDs.contains($0.id)}
            if !facts.isEmpty {
                let count=Set(facts.map(\.id)).count
                DisclosureGroup("PA understanding · \(count) \(count == 1 ? "fact" : "facts")") {
                    ForEach(Array(Dictionary(facts.map{($0.id,$0)},uniquingKeysWith:{a,_ in a}).values.sorted{$0.id.uuidString < $1.id.uuidString}.prefix(12))) { fact in
                        VStack(alignment:.leading,spacing:3) { Text(fact.text).font(.callout).textSelection(.enabled);Text(fact.attribution).font(.caption).foregroundStyle(.secondary);PAMemoryEvidenceView(record:fact,sourcePermitted:model.assistant.memory.permittedRecords.contains{$0.id == fact.id}) }.padding(.vertical,4)
                    }
                }.font(.caption)
            }
            let links=store.state.links.filter{$0.from == item.id && $0.registration == registration}
            ForEach(links) { link in
                if let target=LifeWorkspaceContext.resolve(link.target,model:model,registration:registration,topic:item.conversationID,includeTopics:false) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:3) {
                            Text(link.relation.title).font(.caption).foregroundStyle(.secondary)
                            if link.target.kind == .item,let id=UUID(uuidString:link.target.id),let node=index.byID[id] { Button(target.title) { open(node) }.buttonStyle(.plain).font(.callout).lineLimit(3) }
                            else { Text(target.title).font(.callout).lineLimit(3).textSelection(.enabled) }
                            Text(target.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            if link.inferred == true { Text("PA connection"+(link.reason.map{" · "+$0} ?? "")).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
                        }
                        Spacer()
                        Button { do { try store.unlink(link.id,registration:registration,expectedRevision:store.revision) } catch { notice=error.localizedDescription } } label:{Image(systemName:"link.badge.plus").rotationEffect(.degrees(45))}.buttonStyle(.plain).accessibilityLabel("Remove relationship")
                    }.padding(8).background(palette[.input].opacity(0.5),in:RoundedRectangle(cornerRadius:8))
                } else {
                    HStack { Text(link.relation.title+" · source unavailable").font(.caption).foregroundStyle(.secondary);Spacer();Button("Unlink") { do { try store.unlink(link.id,registration:registration,expectedRevision:store.revision) } catch { notice=error.localizedDescription } }.font(.caption).buttonStyle(.plain) }
                }
            }
            if let notice { Text(notice).font(.caption).foregroundStyle(.orange) }
        }
    }
}

extension LifeTaskStage {
    var color:Color { switch self { case .todo:Color(red:0.80,green:0.34,blue:0.32);case .inProgress:Color(red:0.81,green:0.59,blue:0.23);case .done:Color(red:0.32,green:0.65,blue:0.45) } }
}
struct LifeTaskProgressView:View {
    let progress:LifeTaskProgress
    var compact=false
    private var summary:String {
        LifeTaskStage.allCases.enumerated().map { "\($0.element.rawValue): \(progress.counts[$0.offset])" }.joined(separator:", ")
    }
    var body:some View {
        GeometryReader { proxy in
            HStack(spacing:0) { ForEach(Array(LifeTaskStage.allCases.enumerated()),id:\.element.id) { index,stage in
                if progress.counts[index] > 0 { stage.color.frame(width:proxy.size.width*Double(progress.counts[index])/Double(max(1,progress.total))) }
            } }.clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07),lineWidth:0.5))
        }.frame(height:compact ? 7 : 12)
            .accessibilityElement(children:.ignore).accessibilityLabel("Task progress").accessibilityValue(summary)
            .help(summary+". Includes tasks in subfolders.")
    }
}

struct LifeItemEditor: View {
    @Bindable var model: DashboardModel
    @State var item: LifeItem
    var close: () -> Void
    var reviewedSuggestion:PADiscovery? = nil
    @State private var error: String?
    @State private var saving=false
    @State private var dueEnabled = false
    @State private var dueDate = Date.now
    @State private var estimate = ""
    @State private var parentChanged=false
    private var original: LifeItem? { model.assistant.projects.state.items.first { $0.id == item.id } }
    @State private var expected: UUID?
    private var parents: [LifeItem] {
        let all = model.assistant.projects.items(item.registration, topic: item.conversationID)
        let forbidden = LifeWorkspaceRules.descendants(item.id, in: all).union([item.id])
        return all.filter { !$0.kind.isWork && !forbidden.contains($0.id) && $0.conversationID == item.conversationID }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text((expected == nil ? "New " : "Edit ") + item.kind.title.lowercased()).font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $item.title)
                Picker("Type", selection: Binding(get: { item.kind.workspaceKind }, set: { kind in
                    // Opening an old course/project as a space keeps its exact memory association.
                    if kind != item.kind.workspaceKind { item.kind = kind }
                })) { ForEach(LifeItemKind.allCases) { Text($0.title).tag($0) } }
                if !item.kind.isWork {
                    Picker("Icon",selection:$item.icon) {
                        Label("Default",systemImage:item.kind.symbol).tag(Optional<String>.none)
                        ForEach(LifeProjectIcons.symbols,id:\.self) { symbol in Label(LifeProjectIcons.title(symbol),systemImage:symbol).tag(Optional(symbol)) }
                    }
                }
                Picker("Inside", selection: $item.parentID) {
                    Text("Projects home").tag(Optional<UUID>.none)
                    ForEach(parents) { parent in Text(LifeItemQuery.path(parent, in: parents).map(\.title).joined(separator: " / ")).tag(Optional(parent.id)) }
                }
                Picker("Stage", selection: $item.status) {
                    ForEach(LifeTaskStage.allCases) { Text($0.rawValue).tag($0.status) }
                    if item.status == .waiting || item.status == .archived { Text(item.status.title).tag(item.status) }
                }
                Toggle("Deadline", isOn: $dueEnabled)
                if dueEnabled { DatePicker("Due", selection: $dueDate, displayedComponents: .date) }
                TextField("Estimate (minutes, optional)", text: $estimate)
                Menu {
                    ForEach(LifeArea.allCases.filter { $0 != .unsorted }) { area in
                        Toggle(area.title, isOn: Binding(get: { item.areas.contains(area) }, set: { selected in
                            if selected, item.areas.count < 3 { item.areas.append(area) } else { item.areas.removeAll { $0 == area } }
                        }))
                    }
                } label: { LabeledContent("Life areas", value: item.areas.isEmpty ? "None" : item.areas.map(\.title).joined(separator: ", ")) }
                TextField("Notes", text: $item.notes, axis: .vertical).lineLimit(4...8)
            }.formStyle(.grouped).disabled(saving)
            if item.kind.isWork { Text("Project tasks are separate from Apple Reminders.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack { Button("Cancel", action: close).keyboardShortcut(.cancelAction).disabled(saving); Spacer(); Button(reviewedSuggestion == nil ? "Save" : "Approve and save") { Task {await save()} }.keyboardShortcut(.defaultAction).disabled(saving || item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.registration != model.chatGPT.activeID) }
        }.padding(24).frame(width: 500).frame(maxHeight: 720).interactiveDismissDisabled(saving)
        .onChange(of:item.parentID) { parentChanged=true }
        .onAppear {
            expected = original == nil ? nil : item.revision
            dueEnabled = item.due != nil
            if let due = item.due { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; if let parsed = formatter.date(from: due) { dueDate = parsed } }
            estimate = item.estimateMinutes.map(String.init) ?? ""
        }
    }
    private func save() async {
        guard !saving else {return};saving=true;defer{saving=false}
        guard item.registration == model.chatGPT.activeID else { error = "Account changed; your draft has not been saved."; return }
        let value = estimate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, Int(value).map({ (1...100000).contains($0) }) != true { error = "Enter a positive estimate in minutes, or leave it empty."; return }
        if [.space,.project,.section,.task,.milestone,.resource].contains(item.kind) { item.ownership="workspace" }
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.due = dueEnabled ? DateRules.localDate(dueDate) : nil; item.estimateMinutes = Int(value)
        if item.kind == .project,parentChanged { item.placement = .init(status:"placed",reason:"Your chosen home is pinned.",parentPinned:true) }
        do {
            if let proposal=reviewedSuggestion {
                guard expected == nil else {throw LifeWorkspaceFailure.message("This task already exists. Reopen it to edit it.")}
                try model.savePreparedProjectItem(item,proposal:proposal)
            } else { _ = try model.assistant.projects.save(item, expected: expected) }
            model.projectPlacement.check(model);close()
        } catch { self.error = error.localizedDescription }
    }
}

struct LifeItemLinkEditor: View {
    @Bindable var model: DashboardModel
    let item: LifeItem
    var close: () -> Void
    @State private var search = ""
    @State private var kind: LifeReferenceKind = .item
    @State private var relation: LifeRelation = .related
    @State private var selected: LifeReference?
    @State private var error: String?
    private var options: [LifeLinkOption] {
        LifeWorkspaceContext.options(model, registration: item.registration, topic: item.conversationID, includeTopics: false).filter {
            $0.reference.kind == kind && $0.reference.id != item.id.uuidString && (search.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Link to " + item.title).font(.title2.weight(.semibold)).lineLimit(2)
            Picker("Relationship", selection: $relation) { ForEach(LifeRelation.allCases.filter{$0 != .identifies}) { Text($0.title).tag($0) } }
            Picker("Look in", selection: $kind) { ForEach(LifeReferenceKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            TextField("Find an item", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(options.prefix(100)) { option in
                        Button { selected = option.reference } label: {
                            HStack(alignment: .top) {
                                Image(systemName: selected == option.reference ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 4) { Text(option.title).lineLimit(3); Text(option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                Spacer()
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if options.isEmpty { Text("No matching items in current access and cached coverage.").foregroundStyle(.secondary) }
                }
            }.frame(maxWidth: .infinity, minHeight: 180, maxHeight: 340)
            Text("Creates a relationship here. The linked source stays unchanged.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button("Cancel", action: close).keyboardShortcut(.cancelAction); Spacer()
                Button("Link") {
                    guard item.registration == model.chatGPT.activeID, let selected, LifeWorkspaceContext.resolve(selected, model: model, registration: item.registration, topic: item.conversationID, includeTopics: false) != nil else { error = "The account, source or item changed. Choose a current item."; return }
                    do { _ = try model.assistant.projects.link(.init(registration: item.registration, conversationID: item.conversationID, from: item.id, relation: relation, target: selected), expected: item.revision); close() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(selected == nil || item.registration != model.chatGPT.activeID)
            }
        }.padding(24).frame(width: 500)
        .onChange(of: kind) { selected = nil }
    }
}

/// The gesture still owns drop validation; this only scrolls the enclosing project viewport.
@MainActor private final class LifeBoardScrollController {
    weak var probe:NSView?
    private var timer:Timer?
    private var viewportPoint:CGPoint?
    private var changed:((CGFloat,CGPoint)->Void)?
    #if DEBUG
    private var fixtureChecked=false
    func checkFixtureIfRequested() {
        guard !fixtureChecked,ProcessInfo.processInfo.arguments.contains("--preview-projects"),ProcessInfo.processInfo.arguments.contains("--check-board-scroll") else {return}
        fixtureChecked=true
        Task { [weak self] in
            try? await Task.sleep(for:.milliseconds(250))
            guard let self,let probe,let scroll=probe.enclosingScrollView else {
                try? Data("{\"error\":\"Project board probe did not attach to a native scroll viewport\"}".utf8).write(to:EvaluationOutput.url("/tmp/missioncontrol-board-scroll-evaluation.json"));return
            }
            let clip=scroll.contentView,before=clip.bounds.origin
            let point=probe.convert(CGPoint(x:clip.bounds.midX,y:clip.bounds.maxY-1),from:clip)
            var moves=0,pointerValid=true
            track(point) {delta,local in
                moves+=1
                let converted=probe.convert(local,to:clip)
                pointerValid = pointerValid && abs(converted.y-clip.bounds.maxY+1) < 1 && delta > 0
            }
            for _ in 0..<12 {step()}
            let after=clip.bounds.origin
            stop();step()
            let checks=["probe owns the project viewport":scroll.documentView != nil,"edge tracking advances the real native viewport":after.y > before.y && moves > 0,"drag point remains at the viewport edge during scrolling":pointerValid,"stop prevents another scroll step":clip.bounds.origin == after,"scrolling remains within content bounds":after.y <= max(0,(scroll.documentView?.bounds.height ?? 0)-clip.bounds.height)]
            clip.scroll(to:before);scroll.reflectScrolledClipView(clip)
            let report:[String:Any]=["checks":checks,"passed":checks.values.filter{$0}.count,"total":checks.count,"scrollSteps":moves,"advancedPoints":after.y-before.y,"nativeChanges":0,"storage":"Fictional preview; real project scroll controller/viewport, no task gesture or status save"]
            if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-board-scroll-evaluation.json"))}
        }
    }
    #endif
    func track(_ point:CGPoint,changed:@escaping(CGFloat,CGPoint)->Void) {
        guard let probe,let scroll=probe.enclosingScrollView else {return}
        let clip=scroll.contentView,converted=probe.convert(point,to:clip)
        viewportPoint=CGPoint(x:converted.x-clip.bounds.minX,y:converted.y-clip.bounds.minY)
        self.changed=changed
        guard timer == nil else {return}
        let tick=Timer(timeInterval:0.04,repeats:true) { [weak self] _ in
            MainActor.assumeIsolated {self?.step()}
        }
        timer=tick;RunLoop.main.add(tick,forMode:.common)
    }
    func currentPoint()->CGPoint? {
        guard let probe,let clip=probe.enclosingScrollView?.contentView,let point=viewportPoint else {return nil}
        return probe.convert(CGPoint(x:point.x+clip.bounds.minX,y:point.y+clip.bounds.minY),from:clip)
    }
    private func step() {
        guard let probe,let scroll=probe.enclosingScrollView,let document=scroll.documentView,let point=viewportPoint else {stop();return}
        let clip=scroll.contentView,bounds=clip.bounds
        let delta=LifeBoardScrollRules.step(pointerY:point.y,height:bounds.height,offset:bounds.minY,contentHeight:document.bounds.height)
        guard delta != 0 else {return}
        clip.scroll(to:CGPoint(x:bounds.minX,y:bounds.minY+delta));scroll.reflectScrolledClipView(clip)
        if let local=currentPoint() {changed?(delta,local)}
    }
    func stop() {timer?.invalidate();timer=nil;changed=nil;viewportPoint=nil}
}
private struct LifeBoardScrollProbe:NSViewRepresentable {
    let controller:LifeBoardScrollController
    final class Probe:NSView {override var isFlipped:Bool {true}}
    func makeNSView(context:Context)->Probe {let view=Probe();controller.probe=view;return view}
    func updateNSView(_ view:Probe,context:Context) {
        controller.probe=view
        #if DEBUG
        controller.checkFixtureIfRequested()
        #endif
    }
    static func dismantleNSView(_ view:Probe,coordinator:()) { }
}
