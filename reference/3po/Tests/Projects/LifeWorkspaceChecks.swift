import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LifeWorkspaceStore(container: container)
        func rejects(_ body: () throws -> Void) { var rejected = false; do { try body() } catch { rejected = true }; precondition(rejected) }
        precondition(LifeItemKind.allCases == [.space, .task], "Only spaces and tasks are offered for new content")
        for raw in ["area", "organisation", "course", "project", "section", "person", "goal", "resource", "task", "milestone", "space"] {
            let kind = LifeItemKind(rawValue: raw)!
            let legacy = LifeItem(registration: "compatibility", kind: kind, title: raw, notes: "Retained notes", status: .active, due: "2026-10-10", areas: [.studies], sortOrder: 4, icon: "book.closed")
            let roundTrip = try JSONDecoder().decode(LifeItem.self, from: JSONEncoder().encode(legacy))
            precondition(roundTrip == legacy && roundTrip.kind.rawValue == raw, "Reading an old item never rewrites its identity/revision/content")
            precondition(kind.title == (kind.isWork ? "Task" : "Space") && kind.workspaceKind == (kind.isWork ? .task : .space))
        }
        precondition(LifeBoardScrollRules.step(pointerY:300,height:600,offset:100,contentHeight:2000) == 0)
        precondition(LifeBoardScrollRules.step(pointerY:599,height:600,offset:100,contentHeight:2000) > 0)
        precondition(LifeBoardScrollRules.step(pointerY:1,height:600,offset:100,contentHeight:2000) < 0)
        precondition(LifeBoardScrollRules.step(pointerY:1,height:600,offset:0,contentHeight:2000) == 0)
        precondition(LifeBoardScrollRules.step(pointerY:599,height:600,offset:1400,contentHeight:2000) == 0)
        precondition(LifeBoardScrollRules.step(pointerY:700,height:600,offset:100,contentHeight:2000) == 0)
        let iconItem=LifeItem(registration:"icons",kind:.project,title:"Research",icon:"lightbulb")
        _=try store.save(iconItem,expected:nil)
        precondition(LifeWorkspaceStore(container:container).state.items.first{$0.id == iconItem.id}?.displaySymbol == "lightbulb")
        var badIcon=iconItem;badIcon.icon="unissued-symbol";rejects {_ = try store.save(badIcon,expected:iconItem.revision)}
        let root = try store.save(LifeItem(registration: "fictional-a", kind: .organisation, title: "Example university"), expected: nil)
        let course = try store.save(LifeItem(registration: "fictional-a", kind: .course, title: "Engineering", parentID: root.id), expected: nil)
        let task = try store.save(LifeItem(registration: "fictional-a", kind: .task, title: "Read paper", parentID: course.id, due: "2026-10-10", estimateMinutes: 45), expected: nil)
        precondition(LifeWorkspaceRules.descendants(root.id, in: store.state.items) == [course.id, task.id])
        let reloaded = LifeWorkspaceStore(container: container)
        precondition(reloaded.state == store.state && reloaded.items("fictional-b").isEmpty)
        var moved = root; moved.parentID = task.id
        rejects { _ = try store.save(moved, expected: root.revision) }
        precondition(store.state == reloaded.state, "Cycle rejection is atomic")
        let beforeInvalid = store.state
        rejects { _ = try store.save(LifeItem(registration: "fictional-a", kind: .space, title: "Inside a task", parentID: task.id), expected: nil) }
        rejects { try store.move(course.id, registration: "fictional-a", parent: task.id, expectedRevision: store.revision) }
        var convert = course; convert.kind = .task
        rejects { _ = try store.save(convert, expected: course.revision) }
        rejects { _ = try store.save(LifeItem(registration: "fictional-a", kind: .space, title: "Engineering", parentID: root.id), expected: nil) }
        precondition(store.state == beforeInvalid, "Invalid hierarchy/type/legacy duplicate changes leave storage untouched")
        let containerTask = LifeItem(registration: "fictional-a", kind: .task, title: "Cannot contain children")
        let invalidNested = LifeItem(registration: "fictional-a", kind: .space, title: "Nested", parentID: containerTask.id)
        rejects { _ = try store.create([containerTask, invalidNested], receipt: .init(id: "invalid-task-parent", registration: "fictional-a", result: "", itemID: nil)) }
        precondition(store.state == beforeInvalid && store.receipt("invalid-task-parent", registration: "fictional-a") == nil)
        let space = LifeItem(registration: "spaces", kind: .space, title: "Study", notes: "General notes")
        let childSpace = LifeItem(registration: "spaces", kind: .space, title: "Modules", parentID: space.id)
        let localTask = LifeItem(registration: "spaces", kind: .task, title: "Prepare notes", parentID: childSpace.id)
        _ = try store.create([space, childSpace, localTask], receipt: .init(id: "spaces-batch", registration: "spaces", result: "Saved hierarchy", itemID: space.id))
        let spaceReload = LifeWorkspaceStore(container: container)
        precondition(spaceReload.items("spaces").count == 3 && LifeItemQuery.path(localTask, in: spaceReload.items("spaces")).map(\.title) == ["Study", "Modules", "Prepare notes"])
        precondition(spaceReload.state.items.first { $0.id == course.id } == course, "Saving new spaces does not migrate unrelated legacy records")
        var other = LifeItem(registration: "fictional-b", kind: .project, title: "Private project", parentID: root.id)
        rejects { _ = try store.save(other, expected: nil) }; other.parentID = nil; _ = try store.save(other, expected: nil)
        let scoped = LifeItem(registration: "fictional-a", conversationID: UUID(), kind: .project, title: "Legacy scope")
        _ = try store.save(scoped, expected: nil)
        precondition(!store.items("fictional-a").contains(where: { $0.id == scoped.id }))
        precondition(store.items("fictional-a", includeTopics: true).contains(where: { $0.id == scoped.id }))
        var revised = task; revised.title = "Read two papers"; revised.status = .active
        let saved = try store.save(revised, expected: task.revision)
        rejects { _ = try store.save(revised, expected: task.revision) }
        precondition(saved.id == task.id && saved.revision != task.revision)
        precondition(store.undoDate("fictional-a") != nil && store.undoDate("fictional-b") == nil)
        precondition(LifeItemQuery(root: course.id, query: "Engineering", unfinished: true, dueBefore: "2026-10-12", maxMinutes: 60).matching(store.items("fictional-a")).map(\.id) == [task.id])
        precondition(LifeItemQuery(root: course.id, query: "", dueBefore: "2026-10-09").matching(store.items("fictional-a")).isEmpty)
        precondition(LifeItemQuery.path(saved, in: store.items("fictional-a")).map(\.id) == [root.id, course.id, task.id])
        // Folder browsing never flattens descendants; PA branch search still can.
        let visible=store.items("fictional-a")
        precondition(LifeFolderContents.children(of:root.id,in:visible).map(\.id) == [course.id])
        precondition(LifeFolderContents.children(of:course.id,in:visible).map(\.id) == [task.id])
        precondition(LifeFolderContents.children(of:nil,in:visible).map(\.id) == [root.id])
        let waiting=LifeItem(registration:"fictional-a",kind:.task,title:"Waiting",parentID:course.id,status:.waiting)
        let done=LifeItem(registration:"fictional-a",kind:.milestone,title:"Done",parentID:course.id,status:.done)
        let archived=LifeItem(registration:"fictional-a",kind:.task,title:"Archived",parentID:course.id,status:.archived)
        let deleted=LifeItem(registration:"fictional-a",kind:.task,title:"Deleted",parentID:course.id,deletedAt:.now)
        let stages=visible+[waiting,done,archived,deleted]
        let progress=LifeFolderContents.progress(under:root.id,in:stages)
        precondition(progress.counts == [1,1,1] && progress.percentages == [34,33,33])
        precondition(LifeTaskProgress(items:[]).percentages == [0,0,0])
        precondition(LifeFolderContents.children(of:course.id,in:stages,unfinished:true).map(\.id) == [task.id,waiting.id])
        precondition(LifeFolderContents.children(of:root.id,in:stages,unfinished:true).map(\.id) == [course.id], "Filtering finished tasks cannot hide their parent folder")
        precondition(waiting.status == .waiting && archived.status == .archived, "Presentation does not migrate legacy states")
        let orphan=LifeItem(registration:"fictional-a",kind:.task,title:"Retained unfiled task",parentID:UUID())
        precondition(LifeFolderContents.children(of:nil,in:[orphan]).map(\.id) == [orphan.id])
        var bad = saved; bad.due = "2026-02-30"; rejects { _ = try store.save(bad, expected: saved.revision) }
        bad.due = "2026-10-10T10:00:00Z"; rejects { _ = try store.save(bad, expected: saved.revision) }
        precondition(LifeWorkspaceRules.dateValid("2028-02-29") && !LifeWorkspaceRules.dateValid("2026-2-1"))
        let dependency = LifeItemLink(registration: "fictional-a", from: course.id, relation: .dependsOn, target: .init(kind: .item, id: saved.id.uuidString))
        _ = try store.link(dependency, expected: course.revision)
        rejects { _ = try store.link(.init(registration: "fictional-a", from: saved.id, relation: .dependsOn, target: .init(kind: .item, id: course.id.uuidString)), expected: saved.revision) }
        rejects { _ = try store.link(.init(registration: "fictional-a", from: root.id, relation: .partOf, target: .init(kind: .item, id: saved.id.uuidString)), expected: root.revision) }
        rejects { _ = try store.link(.init(registration: "fictional-a", from: course.id, relation: .related, target: .init(kind: .item, id: other.id.uuidString)), expected: course.revision) }
        let missing = LifeWorkspaceStore(container: nil); rejects { _ = try missing.save(root, expected: nil) }; precondition(missing.state.items.isEmpty)
        let batchParent = LifeItem(registration: "fictional-a", kind: .project, title: "Batch project")
        let batchChild = LifeItem(registration: "fictional-a", kind: .section, title: "Research", parentID: batchParent.id)
        let receipt = LifeWorkspaceReceipt(id: "fictional-operation", registration: "fictional-a", result: "Created two items", itemID: batchParent.id)
        _ = try store.create([batchParent, batchChild], receipt: receipt)
        let count = store.state.items.count
        rejects { _ = try store.create([batchParent, batchChild], receipt: receipt) }
        precondition(store.state.items.count == count && LifeWorkspaceStore(container: container).receipt(receipt.id, registration: "fictional-a") != nil)
        let invalidChild = LifeItem(registration: "fictional-a", kind: .task, title: "Bad child", parentID: UUID())
        rejects { _ = try store.create([LifeItem(registration: "fictional-a", kind: .project, title: "Should not remain"), invalidChild], receipt: .init(id: "invalid", registration: "fictional-a", result: "", itemID: nil)) }
        precondition(store.state.items.count == count, "Invalid batch saves nothing")
        let stale = store.revision
        _ = try store.save(LifeItem(registration: "fictional-a", kind: .resource, title: "Reference"), expected: nil)
        rejects { try store.unlink(dependency.id, registration: "fictional-a", expectedRevision: stale) }
        try store.unlink(dependency.id, registration: "fictional-a", expectedRevision: store.revision)
        precondition(!store.state.links.contains(where: { $0.id == dependency.id }))
        var renamed = saved; renamed.title = "Changed for Undo"
        _ = try store.save(renamed, expected:saved.revision)
        try store.undo("fictional-a")
        precondition(store.state.items.first(where: { $0.id == saved.id })?.title == saved.title && store.undoDate("fictional-a") == nil)
        rejects { try store.undo("fictional-a") }
        precondition(LifeWorkspaceStore(container:container).undoDate("fictional-a") == nil, "Project Undo is session-only")
        // Browsing must not mutate a widget's separately saved starting page.
        let bookmark=course.id
        var navigation=LifeProjectNavigation()
        precondition(navigation.destination(startingAt:bookmark) == course.id)
        navigation.open(task.id)
        navigation.back(startingAt:bookmark,items:store.items("fictional-a"))
        precondition(navigation.destination(startingAt:bookmark) == course.id)
        navigation.back(startingAt:bookmark,items:store.items("fictional-a"))
        precondition(navigation.destination(startingAt:bookmark) == root.id)
        navigation.home()
        precondition(navigation.destination(startingAt:bookmark) == nil && bookmark == course.id)
        navigation.open(task.id)
        navigation.reconcile(items:store.items("fictional-a").filter{$0.id != task.id})
        precondition(navigation.destination(startingAt:bookmark) == nil, "Missing/deleted/focus-hidden page returns home, not the bookmark")
        navigation = .init()
        precondition(navigation.destination(startingAt:bookmark) == bookmark, "Remount/account reset uses its own saved starting page")
        let notesOriginal=store.items("fictional-a").first{$0.id == task.id}!
        var external=notesOriginal;external.title="Renamed while notes draft was open"
        let externalSaved=try store.save(external,expected:notesOriginal.revision)
        var notesDraft=notesOriginal;notesDraft.notes="Unsubmitted ideas"
        rejects { _ = try store.save(notesDraft,expected:notesOriginal.revision) }
        precondition(store.items("fictional-a").first{$0.id == task.id} == externalSaved, "Stale notes cannot overwrite another edit")
        var freshNotes=externalSaved;freshNotes.notes="My saved plan"
        let notesSaved=try store.save(freshNotes,expected:externalSaved.revision)
        precondition(notesSaved.id == task.id && notesSaved.title == externalSaved.title && notesSaved.notes == "My saved plan")
        try store.undo("fictional-a")
        precondition(store.items("fictional-a").first{$0.id == task.id}?.notes == notesOriginal.notes)
        let beforeStage=store.items("fictional-a").first{$0.id == task.id}!
        let stageRevision=store.revision
        rejects { try LifeTaskStageChange.apply(task.id,stage:.done,parent:root.id,registration:"fictional-a",permittedIDs:[task.id],expectedRevision:stageRevision,store:store) }
        rejects { try LifeTaskStageChange.apply(task.id,stage:.done,parent:course.id,registration:"fictional-b",permittedIDs:[task.id],expectedRevision:stageRevision,store:store) }
        rejects { try LifeTaskStageChange.apply(task.id,stage:.done,parent:course.id,registration:"fictional-a",permittedIDs:[],expectedRevision:stageRevision,store:store) }
        rejects {try LifeTaskStageChange.applyDrag(task.id,stage:.done,capturedParent:course.id,currentParent:course.id,registration:"fictional-a",activeRegistration:"fictional-b",capturedIDs:[task.id],currentIDs:[task.id],expectedRevision:stageRevision,store:store)}
        rejects {try LifeTaskStageChange.applyDrag(task.id,stage:.done,capturedParent:course.id,currentParent:root.id,registration:"fictional-a",activeRegistration:"fictional-a",capturedIDs:[task.id],currentIDs:[task.id],expectedRevision:stageRevision,store:store)}
        rejects {try LifeTaskStageChange.applyDrag(task.id,stage:.done,capturedParent:course.id,currentParent:course.id,registration:"fictional-a",activeRegistration:"fictional-a",capturedIDs:[task.id],currentIDs:[],expectedRevision:stageRevision,store:store)}
        precondition(store.revision == stageRevision,"A changed account, page or permission must not save any task")
        try LifeTaskStageChange.applyDrag(task.id,stage:.done,capturedParent:course.id,currentParent:course.id,registration:"fictional-a",activeRegistration:"fictional-a",capturedIDs:[task.id],currentIDs:[task.id],expectedRevision:stageRevision,store:store)
        let afterStage=store.items("fictional-a").first{$0.id == task.id}!
        precondition(afterStage.status == .done && afterStage.parentID == beforeStage.parentID && afterStage.notes == beforeStage.notes)
        rejects { try LifeTaskStageChange.apply(task.id,stage:.todo,parent:course.id,registration:"fictional-a",permittedIDs:[task.id],expectedRevision:stageRevision,store:store) }
        try store.undo("fictional-a")
        precondition(store.items("fictional-a").first{$0.id == task.id}?.status == beforeStage.status)
        // Folder reordering retains identities/contents, persists, and supports exact Undo.
        let orderContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let ordering=LifeWorkspaceStore(container:orderContainer)
        let folder=try ordering.save(LifeItem(registration:"order",kind:.space,title:"Home"),expected:nil)
        let first=try ordering.save(LifeItem(registration:"order",kind:.project,title:"First",parentID:folder.id,notes:"Preserved",placement:.init(status:"paused",reason:"Keep this receipt",parentPinned:false)),expected:nil)
        let second=try ordering.save(LifeItem(registration:"order",kind:.space,title:"Second",parentID:folder.id),expected:nil)
        let third=try ordering.save(LifeItem(registration:"order",kind:.space,title:"Third",parentID:folder.id),expected:nil)
        let nested=try ordering.save(LifeItem(registration:"order",kind:.task,title:"Nested task",parentID:first.id,status:.done),expected:nil)
        let peers:Set<UUID>=[first.id,second.id,third.id]
        let captured=ordering.revision,originalOrder=ordering.state
        func reorder(_ id:UUID,_ before:UUID?,account:String="order",page:UUID?=nil,ids:Set<UUID>?=nil,revision:UUID?=nil)throws {
            try LifeFolderReorder.apply(id,before:before,parent:folder.id,capturedPage:folder.id,currentPage:page ?? folder.id,registration:"order",activeRegistration:account,capturedIDs:peers,currentIDs:ids ?? peers,expectedRevision:revision ?? ordering.revision,store:ordering)
        }
        rejects {try reorder(third.id,first.id,account:"other")}
        rejects {try reorder(third.id,first.id,page:first.id)}
        rejects {try reorder(third.id,first.id,ids:[first.id,second.id])}
        rejects {try reorder(third.id,nested.id)}
        precondition(ordering.state == originalOrder,"Account/page/visibility and non-folder targets cannot change folder order")
        try reorder(third.id,first.id)
        let reordered=LifeFolderContents.children(of:folder.id,in:ordering.items("order"))
        precondition(reordered.map(\.id) == [third.id,first.id,second.id])
        precondition(reordered.first{$0.id == first.id}?.placement == first.placement && reordered.first{$0.id == first.id}?.notes == first.notes)
        precondition(ordering.state.items.first{$0.id == nested.id} == nested,"Reordering never edits folder contents or task stages")
        precondition(LifeWorkspaceStore(container:orderContainer).state == ordering.state,"Folder order survives repository reload")
        rejects {try reorder(second.id,third.id,revision:captured)}
        try ordering.undo("order")
        precondition(LifeFolderContents.children(of:folder.id,in:ordering.items("order")).map(\.id) == [first.id,second.id,third.id])
        precondition(ordering.state.items.first{$0.id == first.id}?.placement == first.placement,"Reorder Undo must not pin or resume a legacy placement request")
        try reorder(first.id,nil)
        precondition(LifeFolderContents.children(of:folder.id,in:ordering.items("order")).map(\.id) == [second.id,third.id,first.id])
        let noOpRevision=ordering.revision
        try reorder(first.id,nil)
        precondition(ordering.revision == noOpRevision,"Dropping in the existing slot is a no-op")
        let directTask=try ordering.save(LifeItem(registration:"order",kind:.task,title:"Sibling task",parentID:folder.id,status:.active),expected:nil)
        try ordering.move(third.id,registration:"order",parent:folder.id,expectedRevision:ordering.revision)
        let taskBeforeReorder=ordering.state.items.first{$0.id == directTask.id}!
        let middleRevision=ordering.revision
        try reorder(second.id,first.id)
        precondition(ordering.revision == middleRevision,"An unchanged visible folder order is a no-op even with interleaved tasks")
        try reorder(first.id,second.id)
        precondition(ordering.state.items.first{$0.id == directTask.id} == taskBeforeReorder,"Sibling task records/revisions remain byte-exact")
        var running=ordering.items("order").first{$0.id == first.id}!
        running.placement = .init(status:"running",reason:"Active placement",parentPinned:false)
        _=try ordering.save(running,expected:running.revision)
        // save() deliberately pauses running placement; use the production transition to start it.
        let paused=ordering.items("order").first{$0.id == first.id}!
        try ordering.placementStatus(first.id,expected:paused.revision,status:"running",reason:"Active placement")
        let beforeRunning=ordering.state
        rejects {try reorder(first.id,nil)}
        precondition(ordering.state == beforeRunning,"An active placement is never stranded by a reorder")
        let frames=[first.id:CGRect(x:0,y:0,width:160,height:140),second.id:CGRect(x:180,y:0,width:160,height:140),third.id:CGRect(x:0,y:160,width:160,height:140)]
        precondition(LifeFolderOrder.insertion(at:CGPoint(x:190,y:60),dragging:first.id,orderedIDs:[first.id,second.id,third.id],frames:frames)?.before == second.id)
        precondition(LifeFolderOrder.insertion(at:CGPoint(x:330,y:60),dragging:first.id,orderedIDs:[first.id,second.id,third.id],frames:frames)?.before == third.id)
        precondition(LifeFolderOrder.insertion(at:CGPoint(x:150,y:200),dragging:first.id,orderedIDs:[first.id,second.id,third.id],frames:frames)?.before == nil)
        precondition(LifeFolderOrder.insertion(at:CGPoint(x:400,y:400),dragging:first.id,orderedIDs:[first.id,second.id,third.id],frames:frames) == nil,"Outside release never saves")
        // Optional rich text and independent note cards preserve the original plain note.
        let notesOwner=try store.save(LifeItem(registration:"notes",kind:.space,title:"Notes owner",notes:"Original note"),expected:nil)
        let styled=LifeNoteFormatting(length:notesOwner.notes.utf16.count,runs:[.init(location:0,length:8,size:22,bold:true,italic:false)])
        var noteItem=notesOwner;noteItem.notesFormatting=styled
        let extraNote=LifeNote(text:"Independent sticky note",formatting:.init(length:23,runs:[.init(location:0,length:11,size:15,bold:false,italic:true)]))
        noteItem.additionalNotes=[extraNote]
        let savedNotes=try store.save(noteItem,expected:notesOwner.revision)
        precondition(savedNotes.noteCards.map(\.id) == [notesOwner.id,extraNote.id] && savedNotes.notes == notesOwner.notes)
        precondition(LifeWorkspaceStore(container:container).state.items.first{$0.id == savedNotes.id} == savedNotes)
        precondition(LifeItemQuery(query:"sticky").matching(store.items("notes")).map(\.id) == [notesOwner.id])
        var sameLength=savedNotes;sameLength.notes="Jriginal note"
        let richSaved=try store.save(sameLength,expected:savedNotes.revision,notesFormattingIsCurrent:true)
        precondition(richSaved.notesFormatting == styled,"Same-length rich text edits must retain unchanged font runs")
        var sameExtra=richSaved;sameExtra.additionalNotes?[0].text="Jndependent sticky note"
        let extraRichSaved=try store.save(sameExtra,expected:richSaved.revision,notesFormattingIsCurrent:true)
        precondition(extraRichSaved.additionalNotes?[0].formatting == extraNote.formatting)
        var unrelated=extraRichSaved;unrelated.title="Renamed notes owner"
        let renamedNotes=try store.save(unrelated,expected:extraRichSaved.revision)
        precondition(renamedNotes.notesFormatting == styled && renamedNotes.additionalNotes == extraRichSaved.additionalNotes)
        var staleNotes=savedNotes;staleNotes.notes="Stale overwrite"
        rejects {_=try store.save(staleNotes,expected:savedNotes.revision)}
        var plainEdit=renamedNotes;plainEdit.notes="Updated by the plain editor"
        let plainSaved=try store.save(plainEdit,expected:renamedNotes.revision)
        precondition(plainSaved.notesFormatting == nil && plainSaved.additionalNotes == extraRichSaved.additionalNotes,"Plain edits clear only stale formatting, retaining sibling notes")
        var deleteNote=plainSaved;deleteNote.additionalNotes=[]
        _=try store.save(deleteNote,expected:plainSaved.revision)
        try store.undo("notes")
        let restoredNotes=store.items("notes").first{$0.id == notesOwner.id}!
        precondition(restoredNotes.additionalNotes == extraRichSaved.additionalNotes,"Note deletion Undo restores the same note identities and formatting")
        var badFormat=restoredNotes;badFormat.notesFormatting=styled
        rejects {_=try store.save(badFormat,expected:restoredNotes.revision)}
        var duplicateNote=restoredNotes;duplicateNote.additionalNotes=[extraNote,extraNote]
        rejects {_=try store.save(duplicateNote,expected:restoredNotes.revision)}
        // Corrupt/unsupported storage stays intact and cannot be replaced by an empty state.
        let broken = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let bytes = Data("{\"version\":99,\"items\":[],\"links\":[],\"receipts\":[]}".utf8)
        broken.mainContext.insert(CachedDashboard(key: "lifeWorkspace", data: bytes)); try broken.mainContext.save()
        let unavailable = LifeWorkspaceStore(container: broken)
        rejects { _ = try unavailable.save(root, expected: nil) }
        let preserved = try broken.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first!.data
        precondition(preserved == bytes)
        // Competing loaded snapshots must reject rather than overwrite newer data.
        let ownedContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let ownerA=LifeWorkspaceStore(container:ownedContainer),ownerB=LifeWorkspaceStore(container:ownedContainer)
        let firstOwned=try ownerA.save(.init(registration:"owners",kind:.space,title:"First owner"),expected:nil)
        rejects {_=try ownerB.save(.init(registration:"owners",kind:.space,title:"Stale owner"),expected:nil)}
        precondition(LifeWorkspaceStore(container:ownedContainer).state.items.map(\.id) == [firstOwned.id])
        // Preserve future additive metadata at every retained identity, including
        // nested note formatting, without resurrecting a deliberately nil field.
        let futureContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let futureNote=LifeNote(text:"Future note",formatting:.init(length:11,runs:[.init(location:0,length:11,size:15,bold:true,italic:false)]))
        let futureItem=LifeItem(registration:"future",kind:.space,title:"Future",additionalNotes:[futureNote])
        var future=try JSONSerialization.jsonObject(with:JSONEncoder().encode(LifeWorkspaceState(items:[futureItem]))) as! [String:Any]
        future["futureEnvelope"]="Retain me"
        var futureItems=future["items"] as! [[String:Any]];futureItems[0]["futureItem"]=["value":42];futureItems[0]["id"]=futureItem.id.uuidString.lowercased()
        var futureNotes=futureItems[0]["additionalNotes"] as! [[String:Any]];futureNotes[0]["futureNote"]="Retain note metadata";futureNotes[0]["id"]=futureNote.id.uuidString.lowercased()
        var format=futureNotes[0]["formatting"] as! [String:Any];format["futureFormatting"]=true
        futureNotes[0]["formatting"]=format;futureItems[0]["additionalNotes"]=futureNotes;future["items"]=futureItems
        try LocalRecordRepository(container:futureContainer).write(["lifeWorkspace":JSONSerialization.data(withJSONObject:future)])
        let futureStore=LifeWorkspaceStore(container:futureContainer)
        var revisedFuture=futureStore.state.items[0];revisedFuture.title="Ordinary edit"
        _=try futureStore.save(revisedFuture,expected:revisedFuture.revision)
        let roundtrip=try JSONSerialization.jsonObject(with:LocalRecordRepository(container:futureContainer).read("lifeWorkspace")!) as! [String:Any]
        let savedFuture=(roundtrip["items"] as! [[String:Any]])[0],savedFutureNote=(savedFuture["additionalNotes"] as! [[String:Any]])[0]
        precondition(roundtrip["futureEnvelope"] as? String == "Retain me" && savedFuture["futureItem"] != nil && savedFutureNote["futureNote"] != nil && (savedFutureNote["formatting"] as! [String:Any])["futureFormatting"] as? Bool == true)
        // Crossing the former history cap must retain every operation identity.
        let receiptContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let history=(0..<2000).map{LifeWorkspaceReceipt(id:"operation-\($0)",registration:"history",result:"Saved",itemID:nil)}
        try LocalRecordRepository(container:receiptContainer).save(LifeWorkspaceState(receipts:history),key:"lifeWorkspace")
        let receiptStore=LifeWorkspaceStore(container:receiptContainer)
        _=try receiptStore.create([.init(registration:"history",kind:.task,title:"New task")],receipt:.init(id:"operation-2000",registration:"history",result:"Saved",itemID:nil))
        precondition(LifeWorkspaceStore(container:receiptContainer).receipt("operation-0",registration:"history") != nil)
        rejects {_=try receiptStore.create([.init(registration:"history",kind:.task,title:"Replay")],receipt:history[0])}
        let deletedHistory=(0..<5000).map {index -> LifeItem in
            var item=LifeItem(registration:"archive",kind:.task,title:"Retained \(index)");item.deletedAt = .now;item.deletedRoot=item.id;return item
        }
        try LifeWorkspaceRules.validate(LifeWorkspaceState(items:deletedHistory+[.init(registration:"archive",kind:.task,title:"Active task")]))
        try LifeWorkspaceIndexChecks.run()
        print("PASS: project persistence, identity, scope, dates, hierarchy, receipts, corrupt-store preservation, bookmarks, stale notes/Undo, direct folder contents, legacy stages, exact progress, guarded board changes/Undo folder ordering/reload/metadata/Undo/gesture targets, styled/multiple notes/reload/stale edits and note deletion Undo")
    }
}
