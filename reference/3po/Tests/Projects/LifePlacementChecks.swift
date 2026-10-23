import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let registration="fictional"
        func rejects(_ body:() throws->Void) { var bad=false;do { try body() } catch { bad=true };precondition(bad) }
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=LifeWorkspaceStore(container:container)
        let university=LifeItem(registration:registration,kind:.organisation,title:"Example University",areas:[.studies])
        let course=LifeItem(registration:registration,kind:.course,title:"Engineering",parentID:university.id,areas:[.studies])
        var project=LifeItem(registration:registration,kind:.project,title:"Sensor Garden",notes:"Research\nImplementation\nEvaluation",placement:.init())
        _ = try store.create([university,course,project],receipt:.init(id:"initial",registration:registration,result:"",itemID:project.id))
        let section=try store.save(LifeItem(registration:registration,kind:.section,title:"Research",parentID:project.id),expected:nil)
        let connection=MemoryConnection(subject:"Me",relation:"works on",object:"Sensor Garden",evidence:"My project is Sensor Garden")
        var memory=PAMemory(registration:registration,text:"My project is Sensor Garden",kind:.context,provenance:"Fictional",sourceTurnID:"fictional",evidence:"My project is Sensor Garden",certainty:.stated,connections:[connection])
        memory.organisation = .init(areas:[.studies],connections:[.init(connection:"0",subjectKind:.person,objectKind:.project,subjectIsSelf:true,objectIsSelf:false)])
        let notebook=LifeNotebook.build([memory],registration:registration)
        let memoryEntity = notebook.entities.first { $0.kind == .project }!
        var genericSpace = LifeItem(registration: registration, kind: .space, title: "Sensor Garden", notes: "My folder", areas: [.studies])
        let unboundSpace = notebook.integrating([genericSpace], links: [])
        precondition(unboundSpace.entities.contains { $0.id == memoryEntity.id } && unboundSpace.entities.first { $0.id == "life:" + genericSpace.id.uuidString }?.kind == .concept, "A same-name generic space must not infer a memory identity")
        genericSpace.notebookEntityID = memoryEntity.id; genericSpace.title = "My renamed research"
        let boundSpace = notebook.integrating([genericSpace], links: [])
        precondition(boundSpace.entities.filter { $0.kind == .project }.count == 1 && boundSpace.entities.first { $0.id == "life:" + genericSpace.id.uuidString }?.memoryIDs == [memory.id], "An exact reviewed identity survives generic space type and renaming")
        precondition(boundSpace.links.first { $0.memoryID == memory.id }?.to == "life:" + genericSpace.id.uuidString && boundSpace.anchors.first?.kind == "space")
        let withdrawn = LifeNotebook.build([], registration: registration).integrating([genericSpace], links: [])
        precondition(withdrawn.entities.first { $0.id == "life:" + genericSpace.id.uuidString }?.memoryIDs.isEmpty == true)
        genericSpace.conversationID = UUID()
        precondition(notebook.integrating([genericSpace], links: []).entities.contains { $0.id == memoryEntity.id }, "A space cannot bind an identity from another topic")
        let raw:[String:Any]=["decision":"clear","parent":course.id.uuidString,"reason":"Your Engineering project belongs under Engineering.","areas":["studies"],"links":[],"bindings":[],"question":NSNull(),"choices":[]]
        let text=String(data:try JSONSerialization.data(withJSONObject:raw),encoding:.utf8)!
        project=try store.placementStatus(project.id,expected:project.revision,status:"running",reason:"Test")
        let plan=try LifePlacementRules.decode(text,project:project,items:store.items(registration),notebook:notebook)
        precondition(plan.bindings.count == 1)
        let before=store.revision
        let placed=try store.applyPlacement(plan,to:project,expectedRevision:before)
        precondition(placed.parentID == course.id && placed.notes == project.notes && store.state.items.first{$0.id == section.id}?.parentID == project.id)
        let unified=notebook.integrating(store.items(registration),links:store.state.links)
        precondition(unified.entities.filter{$0.kind == .project}.count == 1 && unified.entities.first{$0.id == "life:"+project.id.uuidString}?.memoryIDs == [memory.id])
        var renamed=placed;renamed.title="Signal Garden"
        let revised=try store.save(renamed,expected:placed.revision)
        let afterRename=notebook.integrating(store.items(registration),links:store.state.links)
        precondition(afterRename.entities.first{$0.id == "life:"+project.id.uuidString}?.label == revised.title && afterRename.entities.filter{$0.kind == .project}.count == 1)
        precondition(afterRename.links.first{$0.memoryID == memory.id}?.to == "life:"+project.id.uuidString)
        let disabled=LifeNotebook.build([],registration:registration).integrating(store.items(registration),links:store.state.links)
        precondition(disabled.entities.first{$0.id == "life:"+project.id.uuidString}?.memoryIDs.isEmpty == true)
        precondition(afterRename.context(query:"Signal Garden",maxBytes:8000).utf8.count <= 8000)
        precondition(afterRename.context(query:nil,maxBytes:120).utf8.count <= 120)
        var pinned=project;pinned.placement?.parentPinned=true
        rejects { _ = try LifePlacementRules.decode(text,project:pinned,items:store.items(registration),notebook:notebook) }
        var bad=raw;bad["parent"]=section.id.uuidString
        rejects { _ = try LifePlacementRules.decode(String(data:try JSONSerialization.data(withJSONObject:bad),encoding:.utf8)!,project:project,items:store.items(registration),notebook:notebook) }
        rejects { _ = try store.applyPlacement(plan,to:project,expectedRevision:before) }
        // Ambiguity stores one question without moving the project or inventing work.
        var question=raw;question["decision"]="ambiguous";question["parent"]=NSNull();question["question"]="Which home fits this project?";question["choices"]=[["parent":course.id.uuidString,"label":"Engineering"],["parent":NSNull(),"label":"Personal projects"]] as [[String:Any]]
        let answer=try LifePlacementRules.decode(String(data:try JSONSerialization.data(withJSONObject:question),encoding:.utf8)!,project:project,items:store.items(registration),notebook:notebook)
        precondition(answer.choices.count == 2 && answer.links.isEmpty && answer.bindings.isEmpty)
        var known=PAMemory(registration:registration,text:"I study Engineering at Example University",kind:.context,provenance:"Fictional",evidence:"I study Engineering at Example University",certainty:.stated,connections:[.init(subject:"Me",relation:"studies",object:"Engineering",evidence:"I study Engineering at Example University"),.init(subject:"Me",relation:"studies at",object:"Example University",evidence:"I study Engineering at Example University")])
        known.organisation = .init(areas:[.studies],connections:[.init(connection:"0",subjectKind:.person,objectKind:.course,subjectIsSelf:true,objectIsSelf:false),.init(connection:"1",subjectKind:.person,objectKind:.organisation,subjectIsSelf:true,objectIsSelf:false)])
        let knownNotebook=LifeNotebook.build([known],registration:registration)
        let candidates=LifePlacementRules.candidates(project:project,items:[project],notebook:knownNotebook)
        let knownCourse=candidates.first{$0.kind == .course}!,knownUniversity=candidates.first{$0.kind == .organisation}!
        precondition(knownCourse.parentID == knownUniversity.id && candidates.count == 3)
        precondition(LifePlacementRules.candidates(project:project,items:[project],notebook:knownNotebook).map(\.id) == candidates.map(\.id))
        var changedUniversity=knownUniversity;changedUniversity.title="Renamed university"
        precondition(knownNotebook.integrating([changedUniversity,knownCourse],links:[]).entities.filter{$0.kind == .organisation}.count == 1)
        let reload=LifeWorkspaceStore(container:container);precondition(reload.state == store.state)
        // Interrupted jobs recover paused and never automatically replay.
        var running=LifeItem(registration:registration,kind:.project,title:"Interrupted",placement:.init(status:"running"))
        running=try store.save(running,expected:nil)
        precondition(LifeWorkspaceStore(container:container).state.items.first{$0.id == running.id}?.placement?.status == "paused")
        print("PASS: placement identities, preserved content/children, pinned parents, ambiguity, stale plans, memory permission projection, bounds and interrupted recovery")
    }
}
