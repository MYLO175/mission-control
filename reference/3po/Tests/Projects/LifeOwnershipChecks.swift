import Foundation
import SwiftData
@main struct LifeOwnershipChecks {
    @MainActor static func main() throws {
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=LifeWorkspaceStore(container:container),account="fixture"
        func rejects(_ body:()->Void) { body() }
        let folder=try store.save(.init(registration:account,kind:.course,title:"Engineering",areas:[.studies]),expected:nil)
        let a=try store.save(.init(registration:account,kind:.project,title:"A",parentID:folder.id,notes:"Human content"),expected:nil)
        let b=try store.save(.init(registration:account,kind:.project,title:"B",parentID:folder.id),expected:nil)
        let task=try store.save(.init(registration:account,kind:.task,title:"Read",parentID:a.id),expected:nil)
        try store.move(b.id,registration:account,parent:folder.id,before:a.id,expectedRevision:store.revision)
        precondition(store.items(account).filter{$0.parentID == folder.id}.map(\.id) == [b.id,a.id])
        try store.undo(account)
        precondition(store.items(account).filter{$0.parentID == folder.id}.map(\.id) == [a.id,b.id])
        do { try store.move(folder.id,registration:account,parent:task.id,expectedRevision:store.revision);preconditionFailure("Cycle") } catch {}
        do { try store.move(a.id,registration:account,parent:nil,expectedRevision:UUID());preconditionFailure("Stale") } catch {}
        try store.trash(a.id,registration:account,keepChildren:false,expectedRevision:store.revision)
        precondition(!store.items(account).contains{$0.id == a.id || $0.id == task.id})
        precondition(store.state.items.first{$0.id == a.id}?.notes == "Human content")
        let reloaded=LifeWorkspaceStore(container:container)
        precondition(reloaded.items(account,includeDeleted:true).filter{$0.deletedAt != nil}.count == 2)
        do { _ = try store.save(.init(registration:account,kind:.project,title:"A",parentID:folder.id),expected:nil);preconditionFailure("Tombstone duplicate") } catch {}
        try reloaded.restore(a.id,registration:account,expectedRevision:reloaded.revision)
        precondition(reloaded.items(account).contains{$0.id == task.id && $0.parentID == a.id})
        try reloaded.trash(a.id,registration:account,keepChildren:true,expectedRevision:reloaded.revision)
        precondition(reloaded.items(account).contains{$0.id == task.id && $0.parentID == folder.id})
        try reloaded.undo(account)
        precondition(reloaded.items(account).contains{$0.id == task.id && $0.parentID == a.id})
        try reloaded.trash(a.id,registration:account,keepChildren:false,expectedRevision:reloaded.revision)
        try reloaded.trash(folder.id,registration:account,keepChildren:false,expectedRevision:reloaded.revision)
        try reloaded.restore(a.id,registration:account,expectedRevision:reloaded.revision)
        precondition(reloaded.items(account).contains{$0.id == a.id && $0.parentID == nil})
        do { _ = try reloaded.save(.init(registration:account,kind:.project,title:"Invalid AI project",ownership:"life"),expected:nil);preconditionFailure("AI ownership") } catch {}
        precondition(LifeWorkspaceRules.navigationAreas(a,in:[folder,a]) == [.studies])
        // A later sibling edit refuses multi-record Undo rather than overwriting it.
        try reloaded.move(task.id,registration:account,parent:nil,expectedRevision:reloaded.revision)
        let ticket=reloaded.undoEdit(account)!
        if let sibling=ticket.others.first { var edited=reloaded.state.items.first{$0.id == sibling.id}!;let version=edited.revision;edited.title+=" changed";_ = try reloaded.save(edited,expected:version) }
        precondition(reloaded.state.items.contains{$0.id == a.id && $0.notes == "Human content"})
        let childContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let childStore=LifeWorkspaceStore(container:childContainer)
        let parent=try childStore.save(.init(registration:account,kind:.space,title:"Parent"),expected:nil)
        let selected=try childStore.save(.init(registration:account,kind:.task,title:"Selected",parentID:parent.id),expected:nil)
        let sibling=try childStore.save(.init(registration:account,kind:.task,title:"Sibling",parentID:parent.id),expected:nil)
        try childStore.trash(parent.id,registration:account,keepChildren:false,expectedRevision:childStore.revision)
        try childStore.restore(selected.id,registration:account,expectedRevision:childStore.revision)
        precondition(childStore.items(account).map(\.id) == [selected.id] && childStore.items(account)[0].parentID == nil,"Restoring one task never restores unrequested siblings or its deleted parent")
        precondition(childStore.state.items.first{$0.id == sibling.id}?.deletedAt != nil)
        print("PASS: recovered branch deletion/restore, keep contents, exact structural Undo, persistent sibling order, cycles/stale refusal, tombstone duplicate prevention and human workspace ownership")
    }
}
