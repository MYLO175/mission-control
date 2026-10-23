import SwiftUI
struct PALifeMapWidget: View {
    @Bindable var model:DashboardModel
    var configuration:Binding<WidgetConfiguration>
    @State private var selected:PAMemory?
    @State private var selectedArea:LifeArea?
    private var presentation:String { ["Map","Notes","Structure"].contains(configuration.wrappedValue.lifeMapView ?? "") ? configuration.wrappedValue.lifeMapView! : "Map" }
    private var presentationBinding:Binding<String> { Binding(get:{presentation},set:{ view in var config=configuration.wrappedValue;config.lifeMapView=view;configuration.wrappedValue=config }) }
    @State private var areaDetails:LifeArea?
    @State private var areaMemory:PAMemory?
    @State private var detailOrganising:PAMemory?
    @State private var detailPlanReports:PAMemory?
    @State private var detailShowMemory=false
    @State private var showContext=false
    private var topic:UUID? { nil }
    private var focusAreas:[LifeArea] {
        if let saved=configuration.wrappedValue.lifeFocusSelections?[model.chatGPT.activeID] { return LifeFocusRules.normalised(saved) }
        let legacy=configuration.wrappedValue.paTopicSelections?[model.chatGPT.activeID].flatMap(UUID.init(uuidString:))
        return model.assistant.conversation(legacy)?.notebookAreas ?? []
    }
    private var focusBinding:Binding<[LifeArea]> { Binding(get:{focusAreas},set:{ areas in
        var value=configuration.wrappedValue;if value.lifeFocusSelections == nil { value.lifeFocusSelections=[:] }
        value.lifeFocusSelections?[model.chatGPT.activeID]=areas.map(\.rawValue);configuration.wrappedValue=value;selectedArea=nil;areaDetails=nil;areaMemory=nil
    }) }
    private var notebook:LifeNotebook { model.assistant.memory.notebook(model.chatGPT.activeID,includeTopics:true) }
    private var notes:[LifeAreaNote] { notebook.notes.filter { focusAreas.isEmpty || focusAreas.contains($0.area) } }
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack { Label("Life map",systemImage:"point.3.connected.trianglepath.dotted").font(.title3.weight(.semibold));Spacer()
                LifeFocusPicker(selection:focusBinding).frame(maxWidth:160,alignment:.trailing)
            }
            .fixedSize(horizontal:false,vertical:true)
            Picker("Life map view",selection:presentationBinding) { Text("Map").tag("Map");Text("Notes").tag("Notes");Text("Projects").tag("Structure") }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth:270).fixedSize(horizontal:false,vertical:true)
            if presentation == "Structure" {
                LifeProjectWidget(model:model,configuration:configuration,showsHeader:false,focusAreas:focusAreas)
            } else if !model.assistant.memory.enabled && notebook.anchors.isEmpty {
                Text("Saved memory is off. Enable it in Context → Supporting facts and controls to use your life notebook.").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if notes.isEmpty {
                Text("Your life notebook grows from useful things you tell your PA. Set up your profile in the PA menu, or organise saved memories below.").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else if presentation == "Map" {
                LifeNotebookMapView(notebook:notebook,notes:notes,selectedArea:Binding(get:{selectedArea},set:{ selectedArea=$0;areaDetails=$0 }),fitsAvailableSpace:true)
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:16) { ForEach(notes) { note in LifeNotebookAreaView(notebook:notebook,note:note) { selected=$0 } } }
                        .frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            if presentation != "Structure" { HStack {
                Text("\(Set(notes.flatMap { $0.records.map(\.id) }).count) available facts").font(.caption).foregroundStyle(.secondary).lineLimit(1).help(model.lifeOrganisation.summary(model))
                Spacer()
                Menu("Context") {
                    Button("Context pages and instructions…") { showContext=true }
                    if model.lifeOrganisation.busy { Button("Stop organising") { model.lifeOrganisation.cancel() } }
                    else { Button("Organise supporting facts · AI") { model.lifeOrganisation.check(model,manual:true,topic:topic) }.disabled(!model.assistant.memory.enabled || !model.assistant.memory.learningEnabled || model.chatGPT.busy || model.assistant.busy || !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused) }
                }
            }.controlSize(.small) }
            if presentation != "Structure",let error=model.lifeOrganisation.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(isPresented:$showContext) { ContextPagesView(model:model,registration:model.chatGPT.activeID) }
        .sheet(item:$areaDetails) { area in
            LifeMapAreaDetails(model:model,registration:model.chatGPT.activeID,area:area) { areaMemory=$0 }
                .sheet(item:$areaMemory) { memory in memoryDetails(memory,fromArea:true) }
        }
        .sheet(item:$selected) { memory in memoryDetails(memory)
        }
        .onChange(of:model.chatGPT.activeID) { selected=nil;areaDetails=nil;areaMemory=nil;detailOrganising=nil;detailPlanReports=nil;detailShowMemory=false;showContext=false;selectedArea=nil }
    }
    private func memoryDetails(_ memory:PAMemory,fromArea:Bool=false)->some View {
            VStack(alignment:.leading,spacing:14) {
                ScrollView { LifeMemoryInspection(model:model,id:memory.id).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:540)
                if memory.kind == .commitment { Button("Remembered plan reports…") { detailPlanReports=memory } }
                HStack { Button("Close") { if fromArea { areaMemory=nil } else { selected=nil } };Button("Organise") { detailOrganising=memory };Spacer();Button("Supporting facts…") { detailShowMemory=true } }
            }.padding(24).frame(width:480)
                .sheet(item:$detailOrganising) { memory in LifeOrganisationEditor(memory:model.assistant.memory,record:memory) }
                .sheet(item:$detailPlanReports) { memory in CommitmentReportsView(memory:model.assistant.memory,recordID:memory.id,registration:memory.registration) }
                .sheet(isPresented:$detailShowMemory) { PAMemoryView(memory:model.assistant.memory,registration:model.chatGPT.activeID,conversationID:topic,topicTitle:model.assistant.conversation(topic)?.title,learning:model.memoryLearning,assistant:model.assistant,checkContext:{model.memoryLearning.check(model,manual:true)},organisation:model.lifeOrganisation,organiseContext:{model.lifeOrganisation.check(model,manual:true,topic:topic)},model:model,focusAreas:focusAreas) }

    }
}

/// The map inspects saved beliefs; it neither broadens recall nor edits project content.
private struct LifeMemoryInspection:View {
    var model:DashboardModel
    var id:UUID
    private var store:PAMemoryStore {model.assistant.memory}
    private var permitted:Set<UUID> {Set(store.permittedRecords.map(\.id))}
    private var record:PAMemory? {store.records.first{$0.id == id && $0.registration == model.chatGPT.activeID}}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            if let record {
                Text(record.source != nil && !permitted.contains(record.id) ? "Source-derived fact unavailable" : record.text).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(record.attribution).font(.caption).foregroundStyle(.secondary)
                if let row=MemoryInspection.rows([record],permitted:permitted,registration:record.registration).first {
                    VStack(alignment:.leading,spacing:4) {
                        Label(!store.enabled && row.availability == .available ? "Memory use paused" : row.availability.title,systemImage:row.availability == .available ? "checkmark.circle" : "clock").font(.callout.weight(.medium))
                        Text(!store.enabled && row.availability == .available ? "Saved for inspection. PA recall resumes when memory use is enabled." : row.availability.explanation).font(.caption).foregroundStyle(.secondary)
                    }
                }
                PAMemoryEvidenceView(record:record,sourcePermitted:permitted.contains(record.id))
                if record.source == nil || permitted.contains(record.id) {
                    ForEach(Array((record.connections ?? []).enumerated()),id:\.offset) { _,edge in Text(edge.subject+" → "+edge.relation+" → "+edge.object).font(.callout) }
                }
                let history=store.lineage(id)
                if history.count > 1 {
                    DisclosureGroup("Version history (\(history.count))") {
                        ForEach(Array(history.suffix(12))) { version in
                            VStack(alignment:.leading,spacing:5) {
                                Text((version.supersededBy == nil ? "Current belief" : "Earlier version")+" · "+version.reviewed.formatted(date:.abbreviated,time:.shortened)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                Text(version.source != nil && !permitted.contains(version.id) ? "Source-derived fact unavailable" : version.text).textSelection(.enabled)
                                Text(version.attribution).font(.caption).foregroundStyle(.secondary)
                                PAMemoryEvidenceView(record:version,sourcePermitted:permitted.contains(version.id))
                            }.padding(.vertical,6)
                        }
                        if history.count > 12 {Text("The latest 12 versions are shown. Manage memories to inspect the full history.").font(.caption).foregroundStyle(.secondary)}
                    }
                }
            } else {Text("This memory is no longer saved.").foregroundStyle(.secondary)}
        }
    }
}

struct LifeMapAreaDetails:View {
    @Bindable var model:DashboardModel
    var registration:String
    var area:LifeArea
    var inspect:(PAMemory)->Void
    @State private var openedID:UUID?
    @State private var configuration=WidgetConfiguration()
    @Environment(\.dismiss) private var dismiss
    private var notebook:LifeNotebook { model.assistant.memory.notebook(registration,includeTopics:true) }
    private var allItems:[LifeItem] { model.assistant.projects.items(registration,includeTopics:true) }
    private var items:[LifeItem] { LifeAreaWorkspace.items(area,notebook:notebook,items:allItems) }
    private var opened:LifeItem? { allItems.first{$0.id == openedID} }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Label(area.title,systemImage:area.symbol).font(.title3.weight(.semibold));Spacer();Button("Done") { dismiss() } }
            if openedID != nil {
                Button { openedID=nil } label: { Label("Back to " + area.title,systemImage:"chevron.left") }.buttonStyle(.plain).font(.callout)
                if let opened {
                    LifeProjectWidget(model:model,configuration:$configuration,showsHeader:false,topicScope:opened.conversationID).id(opened.id)
                } else { ContentUnavailableView("Item unavailable",systemImage:"folder",description:Text("This item may have been moved or deleted. Return to the area to see its current items.")) }
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        Text("Saved workspace items · \(items.count)").font(.headline)
                        Text("Your folders, projects, notes and work items. Open one to see its contents.").font(.caption).foregroundStyle(.secondary)
                        if items.isEmpty { Text("No saved workspace items in this area yet.").font(.callout).foregroundStyle(.secondary) }
                        ForEach(items) { item in
                            Button {
                                configuration.projectRoots=[registration:item.id.uuidString];openedID=item.id
                            } label: {
                                HStack(alignment:.top,spacing:10) {
                                    Image(systemName:item.kind.symbol).foregroundStyle(area.colour).frame(width:20)
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(item.title).font(.callout.weight(.semibold)).frame(maxWidth:.infinity,alignment:.leading)
                                        let count=allItems.filter{$0.parentID == item.id}.count
                                        Text(item.kind.title + (count > 0 ? " · \(count) inside" : "")).font(.caption).foregroundStyle(.secondary)
                                        let parents=LifeItemQuery.path(item,in:allItems).dropLast().map(\.title)
                                        if !parents.isEmpty { Text(parents.joined(separator:" / ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                    Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(10).background(area.colour.opacity(0.05),in:RoundedRectangle(cornerRadius:9))
                            }.buttonStyle(.plain).accessibilityLabel("Open \(item.kind.title): \(item.title)")
                        }
                        Divider().padding(.vertical,4)
                        if let note=notebook.notes.first(where:{$0.area == area}) {
                            LifeNotebookAreaView(notebook:notebook,note:note,inspect:inspect,showsHeading:false,showsSectionLabels:true)
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }
        }.padding(24).frame(width:560,height:640)
        .onChange(of:model.chatGPT.activeID) { dismiss() }
    }
}
