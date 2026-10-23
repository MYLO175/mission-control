import SwiftUI
import UniformTypeIdentifiers

struct LifeProjectDrag {
    static let type=UTType(exportedAs:"com.mylomichael.missioncontrol.life-item")
    var id:UUID;var registration:String;var revision:UUID
}
struct LifeFolderDrag {
    var capture:LifeProjectDrag
    var page:UUID?
    var parent:UUID?
    var peers:[UUID]
    var frames:[UUID:CGRect]
    var translation:CGSize
}
struct LifeFolderFrames:PreferenceKey {
    static let defaultValue:[UUID:CGRect]=[:]
    static func reduce(value:inout [UUID:CGRect],nextValue:()->[UUID:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{$1}) }
}
struct LifeBoardDrag {
    var capture:LifeProjectDrag
    var parent:UUID?
    var permittedIDs:Set<UUID>
    var translation:CGSize
}
struct LifeBoardStageFrames:PreferenceKey {
    static let defaultValue:[String:CGRect]=[:]
    static func reduce(value:inout [String:CGRect],nextValue:()->[String:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{$1}) }
}
struct LifeProjectDrop:DropDelegate {
    var target:UUID?;var parent:UUID?;var before:UUID?
    @Binding var drag:LifeProjectDrag?
    @Binding var hover:String?
    var key:String
    var store:LifeWorkspaceStore
    var activeRegistration:()->String
    var report:(String)->Void
    var enabled=true
    func validateDrop(info:DropInfo)->Bool { enabled && info.hasItemsConforming(to:[LifeProjectDrag.type.identifier]) && drag != nil && drag?.id != target && drag?.registration == activeRegistration() }
    func dropEntered(info:DropInfo) { if validateDrop(info:info) { hover=key } }
    func dropExited(info:DropInfo) { if hover == key { hover=nil } }
    func dropUpdated(info:DropInfo)->DropProposal? { validateDrop(info:info) ? .init(operation:.move) : .init(operation:.forbidden) }
    func performDrop(info:DropInfo)->Bool {
        guard let captured=drag,validateDrop(info:info) else { return false }
        defer { drag=nil;hover=nil }
        do { try store.move(captured.id,registration:captured.registration,parent:parent,before:before,expectedRevision:captured.revision);return true }
        catch { report(error.localizedDescription);return false }
    }
}
struct LifeDeleteSheet:View {
    @Bindable var model:DashboardModel
    let item:LifeItem
    var close:()->Void
    @State private var revision:UUID?
    @State private var error:String?
    private var descendants:Int { LifeWorkspaceRules.descendants(item.id,in:model.assistant.projects.items(item.registration,includeTopics:true)).count }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Delete “\(item.title)”?").font(.title2.weight(.semibold))
            Text("It will move to Recently deleted with its saved identity and links. Calendar, Reminders and historical memory stay saved.").font(.callout)
            if descendants > 0 { Text("This branch contains \(descendants) items.").foregroundStyle(.secondary);Button("Delete folder, keep contents") { remove(true) };Text("Contents move to this folder’s parent.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Button("Cancel",action:close).keyboardShortcut(.cancelAction);Spacer();Button(descendants > 0 ? "Move entire branch to Recently deleted" : "Move to Recently deleted",role:.destructive) { remove(false) } }
        }.padding(24).frame(width:480).onAppear { revision=model.assistant.projects.revision }
    }
    private func remove(_ keep:Bool) {
        guard item.registration == model.chatGPT.activeID,let revision else { error="Account changed. Reopen this item.";return }
        do { try model.assistant.projects.trash(item.id,registration:item.registration,keepChildren:keep,expectedRevision:revision);close() } catch { self.error=error.localizedDescription }
    }
}
struct LifeMoveSheet:View {
    @Bindable var model:DashboardModel
    let item:LifeItem
    var close:()->Void
    @State private var parent:UUID?
    @State private var before:UUID?
    @State private var revision:UUID?
    @State private var error:String?
    private var all:[LifeItem] { model.assistant.projects.items(item.registration,topic:item.conversationID).filter{$0.conversationID == item.conversationID} }
    private var parents:[LifeItem] { let descendants=LifeWorkspaceRules.descendants(item.id,in:all);return all.filter{$0.id != item.id && !descendants.contains($0.id) && !$0.kind.isWork} }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Move “\(item.title)”").font(.title2.weight(.semibold))
            Picker("Into",selection:$parent) { Text("Projects home").tag(Optional<UUID>.none);ForEach(parents) { value in Text(LifeItemQuery.path(value,in:all).map(\.title).joined(separator:" / ")).tag(Optional(value.id)) } }
            Picker("Position",selection:$before) { Text("At the end").tag(Optional<UUID>.none);ForEach(all.filter{$0.parentID == parent && $0.id != item.id}) { value in Text("Before "+value.title).tag(Optional(value.id)) } }
            Text("Contents and relationships move with this item. The PA keeps the folder you choose.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack { Button("Cancel",action:close).keyboardShortcut(.cancelAction);Spacer();Button("Move") { move() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:500).onAppear { parent=item.parentID;revision=model.assistant.projects.revision }.onChange(of:parent) { before=nil }
    }
    private func move() {
        guard item.registration == model.chatGPT.activeID,let revision else { error="Account changed. Reopen this item.";return }
        do { try model.assistant.projects.move(item.id,registration:item.registration,parent:parent,before:before,expectedRevision:revision);close() } catch { self.error=error.localizedDescription }
    }
}
struct LifeRecentlyDeleted:View {
    @Bindable var model:DashboardModel
    let registration:String
    @Environment(\.dismiss) private var dismiss
    @State private var error:String?
    private var deleted:[LifeItem] { model.assistant.projects.items(registration,includeTopics:true,includeDeleted:true).filter{$0.deletedAt != nil} }
    private var roots:[LifeItem] { deleted.filter{item in item.id == item.deletedRoot || !deleted.contains(where:{$0.id == item.deletedRoot})} }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Recently deleted").font(.title2.weight(.semibold));Spacer();Button("Done") { dismiss() } }
            Text("Restore keeps the same items, contents and relationships. Nothing is permanently erased here.").font(.caption).foregroundStyle(.secondary)
            ScrollView { LazyVStack(alignment:.leading,spacing:12) {
                ForEach(roots) { item in HStack { Label(item.title,systemImage:item.kind.symbol);Spacer();Button("Restore") { do { guard registration == model.chatGPT.activeID else { throw LifeWorkspaceFailure.message("Account changed.") };try model.assistant.projects.restore(item.id,registration:registration,expectedRevision:model.assistant.projects.revision) } catch { self.error=error.localizedDescription } } } }
                if deleted.isEmpty { Text("No deleted projects or items.").foregroundStyle(.secondary) }
            } }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width:560,height:440)
    }
}

/// Human-reviewed identity metadata; original memory facts and evidence never change.
struct LifeIdentitySheet:View {
    @Bindable var model:DashboardModel
    let item:LifeItem
    var close:()->Void
    @State private var revision:UUID?
    @State private var error:String?
    private var notebook:LifeNotebook { LifeNotebook.build(model.assistant.memory.enabled ? model.assistant.memory.permittedRecords.filter{$0.source == nil} : [],registration:item.registration,topic:item.conversationID) }
    private var entities:[LifeEntity] { notebook.entities.filter{(item.kind == .space ? $0.kind != .concept : $0.kind.rawValue == item.kind.rawValue) && $0.kind != .person && $0.id != LifeNotebook.selfID && $0.id.hasPrefix((item.conversationID?.uuidString ?? "shared")+":")} }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Match PA understanding").font(.title2.weight(.semibold));Spacer();Button("Done",action:close) }
            Text("Choose a saved description of the same “\(item.title)”. This links its identity to your existing item; original facts and evidence stay saved. Similar names alone do not establish a match.").font(.callout)
            ScrollView { LazyVStack(alignment:.leading,spacing:12) { ForEach(entities) { entity in
                VStack(alignment:.leading,spacing:5) {
                    HStack { Text(entity.label).font(.headline);Spacer();Button(item.notebookEntityID == entity.id ? "Matched" : "Match") { match(entity) }.disabled(item.notebookEntityID == entity.id || issue(entity) != nil) }
                    if let issue=issue(entity) { Text(issue).font(.caption).foregroundStyle(.secondary) }
                    ForEach(notebook.notes.flatMap(\.records).filter{entity.memoryIDs.contains($0.id)}.prefix(3)) { Text($0.text).font(.caption).foregroundStyle(.secondary) }
                }.padding(10).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
            };if entities.isEmpty { Text("No matching saved descriptions available.").foregroundStyle(.secondary) } } }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width:560,height:470).onAppear { revision=model.assistant.memory.revision }
    }
    private func issue(_ entity:LifeEntity)->String? {
        if let other=model.assistant.projects.items(item.registration,topic:item.conversationID).first(where:{other in other.id != item.id && other.kind.workspaceKind == item.kind.workspaceKind && (other.notebookEntityID == entity.id || model.assistant.projects.state.links.contains(where:{$0.from == other.id && $0.target.containerID == entity.id && $0.relation == .identifies}))}) { return "Already associated with "+other.title+". Resolve duplicate items with Move/Delete before matching; neither is merged silently." }
        return nil
    }
    private func match(_ entity:LifeEntity) {
        guard issue(entity) == nil,item.registration == model.chatGPT.activeID,revision == model.assistant.memory.revision,entities.contains(where:{$0.id == entity.id}) else { error="Account or memory changed. Reopen this view.";return }
        var value=item;value.notebookEntityID=entity.id
        do { _ = try model.assistant.projects.save(value,expected:item.revision);close() } catch { self.error=error.localizedDescription }
    }
}
