#if DEBUG
import SwiftUI
import AppKit

@MainActor enum LifeProjectPreview {
    static func seed(_ model: DashboardModel) -> (String, LifeItem, LifeItem, LifeItem)? {
        let registration = model.chatGPT.activeID.isEmpty ? "fictional-preview" : model.chatGPT.activeID
        let university = LifeItem(registration:registration, kind:.organisation, title:"Example University", areas:[.studies])
        let engineering = LifeItem(registration:registration, kind:.course, title:"Engineering", parentID:university.id, areas:[.studies])
        var project = LifeItem(registration:registration, kind:.project, title:"Sensor Garden", parentID:engineering.id, notes:"A fictional sensor prototype, from research to a tested baseline.", status:.active, areas:[.studies,.projects])
        project.notes="Project overview\nA fictional sensor prototype, from research to a tested baseline."
        project.notesFormatting = .init(length:project.notes.utf16.count,runs:[.init(location:0,length:16,size:22,bold:true,italic:false)])
        project.additionalNotes=[
            .init(text:"Ideas to explore\n•\tTry a smaller sensor\n•\tCompare two capture angles\n•\tKeep the setup repeatable"),
            .init(text:"Meeting notes\nBring the prototype and the latest measurements.\nDiscuss what made the baseline reliable.\nAgree the next experiment.\nRecord uncertainties and follow-up questions.\nKeep this fictional note available without pushing the task board down the page.\nThis final line stays visible when the page has room.")
        ]
        let research = LifeItem(registration:registration, kind:.section, title:"Research", parentID:project.id, areas:[.studies])
        let paper = LifeItem(registration:registration, kind:.task, title:"Read the baseline paper", parentID:research.id, status:.done, due:"2026-10-08", estimateMinutes:45)
        let baseline = LifeItem(registration:registration, kind:.task, title:"Build the first working baseline", parentID:project.id, status:.active, due:"2026-10-12", estimateMinutes:120)
        let experiments = LifeItem(registration:registration, kind:.task, title:"Run the first experiments", parentID:project.id, status:.planned, due:"2026-10-14", estimateMinutes:90)
        let module = LifeItem(registration:registration, kind:.course, title:"Signals and systems", parentID:engineering.id, areas:[.studies])
        let waiting=LifeItem(registration:registration,kind:.task,title:"Get the sensor specification",parentID:project.id,status:.waiting)
        let archived=LifeItem(registration:registration,kind:.task,title:"Old prototype",parentID:project.id,status:.archived)
        let unfiled=LifeItem(registration:registration,kind:.task,title:"Unfiled task stays accessible",areas:[.administration])
        let personal=LifeItem(registration:registration,kind:.area,title:"Personal projects",areas:[.projects])
        do {
            _ = try model.assistant.projects.create([university,engineering,project,research,paper,baseline,experiments,module,waiting,archived,unfiled,personal], receipt:.init(id:"preview-only", registration:registration, result:"Fictional preview", itemID:university.id))
        } catch { return nil }
        if ProcessInfo.processInfo.arguments.contains("--long-board") {
            let extra=(1...32).map{LifeItem(registration:registration,kind:.task,title:"Fictional board task \($0)",parentID:project.id,status:.planned)}
            do {
                for start in stride(from:0,to:extra.count,by:12) {
                    _=try model.assistant.projects.create(Array(extra[start..<min(start+12,extra.count)]),receipt:.init(id:"preview-long-board-\(start)",registration:registration,result:"Fictional long board",itemID:project.id))
                }
            } catch {return nil}
        }
        var memory=PAMemory(registration:registration,text:"Sensor Garden is my Engineering project at Example University.",kind:.context,provenance:"Fictional preview",evidence:"Sensor Garden is my Engineering project at Example University.",certainty:.stated,connections:[.init(subject:"Me",relation:"works on",object:"Sensor Garden",evidence:"Sensor Garden is my Engineering project at Example University.")])
        memory.organisation = .init(areas:[.studies],connections:[.init(connection:"0",subjectKind:.person,objectKind:.project,subjectIsSelf:true,objectIsSelf:false)])
        var earlier=memory;earlier.id=UUID();earlier.text="Sensor Garden is my weekend hobby project.";earlier.evidence=earlier.text;earlier.created=Date.now.addingTimeInterval(-86400);earlier.supersededBy=memory.id
        memory.supersedes=earlier.id
        _=model.assistant.memory.put(earlier)
        _ = model.assistant.memory.put(memory)
        return (registration, university, engineering, project)
    }
    static func render(_ model: DashboardModel) async {
        guard let (registration,university,engineering,project) = seed(model) else { return }
        let previews:[(String,CGFloat,CGFloat,String,String,UUID?)]=[
            ("notes-roomy",1100,1200,"dark","Overview",project.id),
            ("notes-only",740,900,"light","Overview",project.id),
            ("folders-only",900,650,"dark","Overview",engineering.id),
            ("tasks-only",900,650,"dark","Overview",project.id),
            ("notes-dark",1100,940,"dark","Overview",project.id),
            ("wide-dark",1100,650,"dark","Overview",engineering.id),
            ("deep-dark",900,500,"dark","Overview",project.id),
            ("home",620,500,"light","Overview",nil),
            ("home-dark",620,500,"dark","Deadlines",nil),
            ("compact",240,500,"dark","Overview",engineering.id),
            ("list",520,570,"light","List",project.id),
            ("life-map",CGFloat(620),CGFloat(500),"light","LifeMap",engineering.id),
            ("overview",CGFloat(620),CGFloat(500),"light","Overview",engineering.id),
            ("detail",CGFloat(520),CGFloat(570),"dark","Overview",project.id),
            ("narrow",CGFloat(300),CGFloat(400),"dark","Overview",engineering.id),
            ("board",CGFloat(740),CGFloat(490),"light","Board",project.id),
            ("leaf",CGFloat(740),CGFloat(430),"dark","Overview",model.assistant.projects.items(registration).first{$0.title == "Research"}?.id),
            ("empty",CGFloat(520),CGFloat(380),"light","Overview",model.assistant.projects.items(registration).first{$0.title == "Signals and systems"}?.id),
            ("outline",CGFloat(500),CGFloat(600),"dark","Outline",university.id),
            ("deadlines",CGFloat(420),CGFloat(360),"light","Deadlines",project.id)
        ]
        for (name,width,height,mode,view,root) in previews {
            var overrides = WorkspaceColorOverrides(); overrides.profiles = WorkspaceColorTheme.threePO.profiles
            let palette = WorkspacePalette.resolved(raw:overrides.encoded, mode:mode, theme:"warm", accent:"sage")
            var config = WidgetConfiguration(); config.projectRoots = [registration:root?.uuidString ?? ""]; config.projectView = view
            if let root {
                let hidden:[ProjectPageSection]=name == "folders-only" ? [.tasks,.notes] : name == "tasks-only" ? [.spaces,.notes] : name == "notes-only" ? [.spaces,.tasks] : []
                for section in hidden {config.setProjectSection(section,visible:false,registration:registration,folder:root)}
            }
            let widget = view == "LifeMap" ? AnyView(PALifeMapWidget(model:model,configuration:.constant(config))) : AnyView(LifeProjectWidget(model:model, configuration:.constant(config), previewRegistration:registration))
            let content = widget
                .padding(16).frame(width:width,height:height).foregroundStyle(palette[.text]).background(palette[.widget],in:RoundedRectangle(cornerRadius:16))
                .environment(\.workspacePalette,palette).tint(palette[.accent]).preferredColorScheme(mode == "dark" ? .dark : .light)
            // ImageRenderer omits AppKit-backed controls/ScrollView content. Capture a real
            // native hosting view with exclusively fictional data instead.
            let hosting = NSHostingView(rootView:content)
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height), styleMask:[.borderless], backing:.buffered, defer:false)
            window.isReleasedWhenClosed = false; window.contentView = hosting
            window.appearance = NSAppearance(named:mode == "dark" ? .darkAqua : .aqua)
            window.center(); window.orderFront(nil)
            try? await Task.sleep(for:.milliseconds(300))
            hosting.layoutSubtreeIfNeeded(); hosting.displayIfNeeded()
            if let bitmap = hosting.bitmapImageRepForCachingDisplay(in:hosting.bounds) {
                hosting.cacheDisplay(in:hosting.bounds, to:bitmap)
                if let data = bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-project-" + name + ".png"),options:.atomic) }
            }
            window.close()
        }
    }
}
struct LifeProjectInteractivePreview: View {
    @Bindable var model: DashboardModel
    @State private var configuration = WidgetConfiguration()
    @State private var registration = ""
    @State private var lifeMap=false
    @State private var chat=false
    @State private var reading=false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("Fictional project preview · disposable storage").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Life map",isOn:$lifeMap).toggleStyle(.button)
                Toggle("PA chat",isOn:$chat).toggleStyle(.button)
                Button("Undo project edit") { try? model.assistant.projects.undo(registration) }.disabled(model.assistant.projects.undoDate(registration) == nil)
            }
            if chat { AssistantPanel(model:model,assistant:model.assistant,readingMode:$reading,configuration:$configuration) } else if lifeMap { PALifeMapWidget(model:model,configuration:$configuration) } else { LifeProjectWidget(model:model,configuration:$configuration,previewRegistration:registration) }
        }.padding(20).frame(minWidth:350,minHeight:500)
        .task {
            guard registration.isEmpty, let (identity,_,engineering,project) = LifeProjectPreview.seed(model) else { return }
            model.assistant.seedWorkflowPreview()
            registration = identity; configuration.projectRoots = [identity:(ProcessInfo.processInfo.arguments.contains("--check-board-scroll") ? project.id : engineering.id).uuidString]
        }
    }
}
#endif
