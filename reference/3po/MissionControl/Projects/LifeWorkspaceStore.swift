import Foundation
import SwiftData
import Observation

struct LifeWorkspaceEditUndo {
    var before: LifeItem
    var savedRevision: UUID
    var created = Date.now
    var others: [LifeItem] = []
    var versions: [UUID:UUID] = [:]
    var preservesPlacement = false
}

@MainActor @Observable final class LifeWorkspaceStore {
    private(set) var state = LifeWorkspaceState()
    private(set) var revision = UUID()
    private(set) var error: String?
    private let container: ModelContainer?
    private var writable = true
    private var edits: [String:LifeWorkspaceEditUndo] = [:]
    private var loadedBytes: Data?
    var readOnly: Bool { !writable || container == nil }
    func undoEdit(_ registration: String) -> LifeWorkspaceEditUndo? {
        guard let ticket = edits[registration], state.items.contains(where: { $0.id == ticket.before.id && $0.registration == registration && $0.revision == ticket.savedRevision }), ticket.versions.allSatisfy({ id,version in state.items.contains{$0.id == id && $0.registration == registration && $0.revision == version} }) else { return nil }
        return ticket
    }
    func undoDate(_ registration: String) -> Date? { undoEdit(registration)?.created }
    func undo(_ registration: String, receipt: LifeWorkspaceReceipt? = nil) throws {
        guard let ticket = undoEdit(registration) else { throw LifeWorkspaceFailure.message("No unchanged project edit remains to undo. Creation and relationship changes are outside this Undo.") }
        var candidate=state
        for var before in [ticket.before]+ticket.others { if !ticket.preservesPlacement,["pending","running"].contains(before.placement?.status ?? "") { before.placement?.status="paused";before.placement?.reason="Organisation was undone. Continue explicitly to reconsider." };if !ticket.preservesPlacement,before.kind == .project { before.placement?.parentPinned=true };guard let index=candidate.items.firstIndex(where:{$0.id == before.id}) else { throw LifeWorkspaceFailure.message("Undo item unavailable.") };before.revision=UUID();before.updated = .now;candidate.items[index]=before }
        try addReceipt(receipt,to:&candidate);try persist(candidate);edits.removeValue(forKey:registration)
    }
    init(container: ModelContainer?) {
        self.container = container
        do {
            if let record = try LocalRecordRepository.read("lifeWorkspace", container: container) {
                let value = try JSONDecoder().decode(LifeWorkspaceState.self, from: record)
                try LifeWorkspaceRules.validate(value); state = value; loadedBytes = record
                if state.items.contains(where:{$0.placement?.status == "running"}) {
                    var recovered=state
                    for index in recovered.items.indices where recovered.items[index].placement?.status == "running" {
                        recovered.items[index].placement?.status="paused";recovered.items[index].placement?.reason="Placement was interrupted. Continue explicitly to try again."
                        recovered.items[index].revision=UUID()
                    }
                    try persist(recovered)
                }

            }
        } catch { writable = false; self.error = "Projects could not be read. Their saved record is preserved; editing is disabled." }
    }
    func items(_ registration: String, topic: UUID? = nil, includeTopics: Bool = false, includeDeleted: Bool = false) -> [LifeItem] {
        LifeWorkspaceRules.ordered(state.items.filter { (includeDeleted || $0.deletedAt == nil) && LifeWorkspaceRules.scoped($0, registration: registration, topic: topic, includeTopics: includeTopics) })
    }
    /// A single revision-checked atomic structural edit, with exact multi-record Undo.
    private func structural(_ before: [LifeItem], candidate: LifeWorkspaceState, receipt: LifeWorkspaceReceipt? = nil, preservesPlacement:Bool=false) throws {
        try persistWithReceipt(candidate,receipt:receipt)
        if let first=before.first { edits[first.registration] = .init(before:first,savedRevision:state.items.first{$0.id == first.id}!.revision,others:Array(before.dropFirst()),versions:[:],preservesPlacement:preservesPlacement)
            // Capture each actual saved revision, never infer identity from a label.
            edits[first.registration]?.versions=Dictionary(uniqueKeysWithValues:before.compactMap{old in state.items.first{$0.id == old.id}.map{(old.id,$0.revision)}})
        }
    }
    private func persistWithReceipt(_ value:LifeWorkspaceState,receipt:LifeWorkspaceReceipt?) throws { var value=value;try addReceipt(receipt,to:&value);try persist(value) }
    func move(_ id:UUID,registration:String,parent:UUID?,before sibling:UUID? = nil,expectedRevision:UUID,receipt:LifeWorkspaceReceipt? = nil) throws {
        if self.receipt(receipt?.id,registration:registration) != nil { return }
        guard revision == expectedRevision,let item=items(registration,includeTopics:true).first(where:{$0.id == id}),parent != id else { throw LifeWorkspaceFailure.message("Structure changed. Read it again before moving.") }
        let all=items(registration,topic:item.conversationID)
        if let parent { guard all.contains(where:{$0.id == parent && !$0.kind.isWork && $0.conversationID == item.conversationID}),!LifeWorkspaceRules.descendants(id,in:all).contains(parent) else { throw LifeWorkspaceFailure.message("Choose a space outside this branch in the same scope.") } }
        var siblings=all.filter{$0.parentID == parent && $0.id != id && $0.conversationID == item.conversationID}
        if let sibling { guard let offset=siblings.firstIndex(where:{$0.id == sibling}) else { throw LifeWorkspaceFailure.message("Insertion target changed.") };siblings.insert(item,at:offset) } else { siblings.append(item) }
        var candidate=state,before:[LifeItem]=[]
        for (order,var value) in siblings.enumerated() {
            guard let index=candidate.items.firstIndex(where:{$0.id == value.id}) else { continue }
            if value.id == id { value.parentID=parent; if value.kind == .project { value.placement = .init(status:"placed",reason:"Your chosen home is pinned.",parentPinned:true) } }
            if value != candidate.items[index] || value.sortOrder != order { before.append(candidate.items[index]);if value.placement?.status == "running" { value.placement?.status="paused";value.placement?.reason="Filing changed during placement. Continue explicitly to reconsider." };value.sortOrder=order;value.revision=UUID();value.updated = .now;candidate.items[index]=value }
        }
        if !before.isEmpty { try structural(before,candidate:candidate,receipt:receipt) } else if receipt != nil { try persistWithReceipt(state,receipt:receipt) }
    }
    /// Preserve parent/placement metadata while reusing the exact structural Undo path.
    func reorderFolder(_ id:UUID,registration:String,before sibling:UUID?,expectedRevision:UUID)throws {
        guard revision == expectedRevision,let item=items(registration,includeTopics:true).first(where:{$0.id == id}),!item.kind.isWork else { throw LifeWorkspaceFailure.message("The folder order changed.") }
        let siblings=state.items.filter{$0.registration == registration && $0.parentID == item.parentID && $0.conversationID == item.conversationID && $0.deletedAt == nil}
        let old=LifeWorkspaceRules.ordered(siblings).filter{!$0.kind.isWork}
        var peers=old.filter{$0.id != id}
        if let sibling {
            guard let index=peers.firstIndex(where:{$0.id == sibling}) else { throw LifeWorkspaceFailure.message("The insertion folder changed.") }
            peers.insert(item,at:index)
        } else { peers.append(item) }
        guard peers.map(\.id) != old.map(\.id) else {return}
        guard !old.contains(where:{$0.placement?.status == "running"}) else { throw LifeWorkspaceFailure.message("Folder organisation is running. Wait until it finishes before reordering.") }
        // Reuse folder slots; task records and their editor/operation revisions stay exact.
        let positions=Dictionary(uniqueKeysWithValues:siblings.enumerated().map{($0.element.id,$0.offset)})
        var slots=old.map{$0.sortOrder ?? positions[$0.id] ?? 0}.sorted()
        for index in slots.indices.dropFirst() where slots[index] <= slots[index-1] {
            guard slots[index-1] < Int.max else { throw LifeWorkspaceFailure.message("This folder order cannot be adjusted.") }
            slots[index]=slots[index-1]+1
        }
        var candidate=state,originals:[LifeItem]=[]
        for (order,var value) in peers.enumerated() {
            guard value.sortOrder != slots[order],let index=candidate.items.firstIndex(where:{$0.id == value.id}) else {continue}
            originals.append(candidate.items[index]);value.sortOrder=slots[order];value.revision=UUID();value.updated = .now;candidate.items[index]=value
        }
        try structural(originals,candidate:candidate,preservesPlacement:true)
    }
    func trash(_ id:UUID,registration:String,keepChildren:Bool,expectedRevision:UUID,receipt:LifeWorkspaceReceipt? = nil) throws {
        if self.receipt(receipt?.id,registration:registration) != nil { return }
        guard revision == expectedRevision,let item=items(registration,includeTopics:true).first(where:{$0.id == id}) else { throw LifeWorkspaceFailure.message("This branch changed. Reopen before deleting.") }
        let active=items(registration,includeTopics:true),ids=keepChildren ? Set([id]) : LifeWorkspaceRules.descendants(id,in:active).union([id])
        var candidate=state,before:[LifeItem]=[]
        for index in candidate.items.indices where ids.contains(candidate.items[index].id) || (keepChildren && candidate.items[index].parentID == id && candidate.items[index].deletedAt == nil) {
            before.append(candidate.items[index]);candidate.items[index].revision=UUID();candidate.items[index].updated = .now
            if ids.contains(candidate.items[index].id) { candidate.items[index].deletedAt = .now;candidate.items[index].deletedRoot=id;if candidate.items[index].placement != nil { candidate.items[index].placement?.status="paused";candidate.items[index].placement?.reason="Project is in Recently deleted." } }
            else { candidate.items[index].parentID=item.parentID;candidate.items[index].sortOrder=nil }
        }
        try structural(before,candidate:candidate,receipt:receipt)
    }
    func restore(_ id:UUID,registration:String,expectedRevision:UUID,receipt:LifeWorkspaceReceipt? = nil) throws {
        if self.receipt(receipt?.id,registration:registration) != nil { return }
        guard revision == expectedRevision,let root=state.items.first(where:{$0.id == id && $0.registration == registration && $0.deletedAt != nil}) else { throw LifeWorkspaceFailure.message("Deleted branch changed. Reopen Recently deleted.") }
        let batch=root.deletedRoot ?? root.id
        var candidate=state,before:[LifeItem]=[]
        // A child ID authorises only that subtree, never its unrequested siblings.
        let subtree = LifeWorkspaceRules.descendants(id, in: state.items).union([id])
        let ids=Set(state.items.filter{$0.registration == registration && $0.deletedRoot == batch && $0.deletedAt != nil && subtree.contains($0.id)}.map(\.id)).union([id])
        for index in candidate.items.indices where ids.contains(candidate.items[index].id) {
            before.append(candidate.items[index]);candidate.items[index].deletedAt=nil;candidate.items[index].deletedRoot=nil;candidate.items[index].revision=UUID();candidate.items[index].updated = .now
            if let parent=candidate.items[index].parentID,!ids.contains(parent),state.items.first(where:{$0.id == parent})?.deletedAt != nil { candidate.items[index].parentID=nil;candidate.items[index].sortOrder=nil }
        }
        try structural(before,candidate:candidate,receipt:receipt)
    }
    func receipt(_ key: String?, registration: String) -> LifeWorkspaceReceipt? {
        key.flatMap { key in state.receipts.first { $0.id == key && $0.registration == registration } }
    }
    @discardableResult func save(_ value: LifeItem, expected: UUID?, receipt: LifeWorkspaceReceipt? = nil, notesFormattingIsCurrent:Bool=false) throws -> LifeItem {
        if let prior = self.receipt(receipt?.id, registration: value.registration), let id = prior.itemID, let item = state.items.first(where: { $0.id == id && $0.registration == value.registration }) { return item }
        var candidate = state, item = value
        var before: LifeItem?
        if let index = candidate.items.firstIndex(where: { $0.id == item.id }) {
            let old = candidate.items[index]
            guard old.registration == item.registration && old.conversationID == item.conversationID && old.revision == expected && old.deletedAt == nil else { throw LifeWorkspaceFailure.message("This item changed while you were editing. Reopen it before saving.") }
            if !notesFormattingIsCurrent,item.notes != old.notes && item.notesFormatting == old.notesFormatting {item.notesFormatting=nil}
            if var notes=item.additionalNotes {
                for index in notes.indices {
                    if !notesFormattingIsCurrent,let previous=old.additionalNotes?.first(where:{$0.id == notes[index].id}),notes[index].text != previous.text,notes[index].formatting == previous.formatting {notes[index].formatting=nil}
                }
                item.additionalNotes=notes
            }
            try LifeWorkspaceRules.validateChange(item, from: old, in: candidate.items)
            if item.placement?.status == "running" { item.placement?.status="paused";item.placement?.reason="Project edited during placement. Continue explicitly to reconsider it." }
            if item.parentID != old.parentID { item.sortOrder=candidate.items.filter{$0.registration == item.registration && $0.conversationID == item.conversationID && $0.parentID == item.parentID && $0.deletedAt == nil}.count }
            item.created = old.created; item.updated = .now; item.revision = UUID(); candidate.items[index] = item
            before = old
        } else {
            guard expected == nil else { throw LifeWorkspaceFailure.message("The item is no longer available.") }
            try LifeWorkspaceRules.validateChange(item, from: nil, in: candidate.items)
            if candidate.items.contains(where: { $0.registration == item.registration && $0.conversationID == item.conversationID && $0.parentID == item.parentID && $0.kind.workspaceKind == item.kind.workspaceKind && LifeWorkspaceRules.key($0.title) == LifeWorkspaceRules.key(item.title) }) {
                throw LifeWorkspaceFailure.message("That item already exists here. Open it rather than adding another copy.")
            }
            item.updated = .now;item.ownership = item.ownership ?? "workspace";item.sortOrder = max(candidate.items.filter{$0.parentID == item.parentID && $0.registration == item.registration}.count,(candidate.items.filter{$0.parentID == item.parentID && $0.registration == item.registration}.compactMap(\.sortOrder).max() ?? -1)+1); candidate.items.append(item)
        }
        try addReceipt(receipt, to: &candidate); try persist(candidate)
        if let before { edits[item.registration] = .init(before:before, savedRevision:item.revision) }
        return item
    }
    /// Batch creation is atomic, including references to earlier entries in the same batch.
    func create(_ items: [LifeItem], receipt: LifeWorkspaceReceipt,links:[LifeItemLink]=[]) throws -> [LifeItem] {
        if self.receipt(receipt.id, registration: receipt.registration) != nil {
            throw LifeWorkspaceFailure.message("This batch is already saved. Read projects to inspect it; do not recreate it.")
        }
        guard (1...12).contains(items.count), items.allSatisfy({ $0.registration == receipt.registration }) else { throw LifeWorkspaceFailure.message("Create between one and twelve items for this account.") }
        var candidate = state
        for item in items {
            try LifeWorkspaceRules.validateChange(item, from: nil, in: candidate.items + items)
            guard !candidate.items.contains(where: { $0.id == item.id || ($0.registration == item.registration && $0.conversationID == item.conversationID && $0.kind.workspaceKind == item.kind.workspaceKind && $0.parentID == item.parentID && LifeWorkspaceRules.key($0.title) == LifeWorkspaceRules.key(item.title)) }) else { throw LifeWorkspaceFailure.message("An item in this batch already exists here. Read the current structure before adding it.") }
            var item=item;item.ownership = item.ownership ?? "workspace";candidate.items.append(item)
        }
        candidate.links.append(contentsOf:links)
        try addReceipt(receipt, to: &candidate); try persist(candidate); return items.compactMap{value in state.items.first{$0.id == value.id}}
    }
    @discardableResult func link(_ value: LifeItemLink, expected: UUID, receipt: LifeWorkspaceReceipt? = nil) throws -> LifeItemLink {
        guard let owner = state.items.first(where: { $0.id == value.from && $0.registration == value.registration && $0.conversationID == value.conversationID }), owner.revision == expected else { throw LifeWorkspaceFailure.message("Read the current project before linking it.") }
        if let existing = state.links.first(where: { $0.from == value.from && $0.relation == value.relation && $0.target == value.target }) {
            if let receipt, self.receipt(receipt.id, registration: value.registration) == nil { var candidate = state; try addReceipt(receipt, to: &candidate); try persist(candidate) }
            return existing
        }
        var candidate = state; candidate.links.append(value)
        try addReceipt(receipt, to: &candidate); try persist(candidate); return value
    }
    func unlink(_ id: UUID, registration: String, expectedRevision: UUID, receipt: LifeWorkspaceReceipt? = nil) throws {
        if self.receipt(receipt?.id, registration: registration) != nil { return }
        guard revision == expectedRevision, state.links.contains(where: { $0.id == id && $0.registration == registration }) else { throw LifeWorkspaceFailure.message("This relationship changed. Read it again before removing it.") }
        var candidate = state; candidate.links.removeAll { $0.id == id && $0.registration == registration }
        try addReceipt(receipt, to: &candidate); try persist(candidate)
    }

    @discardableResult func placementStatus(_ id:UUID,expected:UUID,status:String,reason:String) throws -> LifeItem {
        guard let index=state.items.firstIndex(where:{$0.id == id && $0.revision == expected && $0.placement != nil && $0.deletedAt == nil}) else { throw LifeWorkspaceFailure.message("Project changed before placement. Saved work is kept.") }
        var candidate=state;candidate.items[index].placement?.status=status;candidate.items[index].placement?.reason=reason;candidate.items[index].revision=UUID()
        try persist(candidate);return candidate.items[index]
    }
    @discardableResult func applyPlacement(_ plan:LifePlacementPlan,to project:LifeItem,expectedRevision:UUID,anchors:[LifeItem]=[]) throws -> LifeItem {
        guard revision == expectedRevision,let index=state.items.firstIndex(where:{$0.id == project.id && $0.revision == project.revision && $0.deletedAt == nil}),let request=project.placement else { throw LifeWorkspaceFailure.message("Life map changed during placement. Existing organisation is kept.") }
        guard !request.parentPinned || plan.parent == project.parentID else { throw LifeWorkspaceFailure.message("Your chosen parent is pinned.") }
        let operation="placement:"+project.id.uuidString+":"+request.requestID.uuidString
        guard receipt(operation,registration:project.registration) == nil else { throw LifeWorkspaceFailure.message("This placement already has a saved result.") }
        var candidate=state,item=project
        guard anchors.count <= 8,anchors.allSatisfy({ anchor in anchor.ownership == "life" && [.organisation,.course].contains(anchor.kind) && anchor.registration == project.registration && anchor.conversationID == project.conversationID && !state.items.contains(where:{$0.id == anchor.id}) }) else { throw LifeWorkspaceFailure.message("Unsupported candidate anchors.") }
        candidate.items.append(contentsOf:anchors)
        item.placement?.status=plan.decision == "clear" ? "placed" : plan.decision == "ambiguous" ? "question" : "unplaced"
        item.placement?.reason=plan.reason;item.placement?.question=plan.question;item.placement?.choices=plan.choices
        if plan.decision != "ambiguous" {
            if !request.parentPinned { item.parentID=plan.parent }
            if item.areas.isEmpty { item.areas=plan.areas }
            for proposed in plan.links {
                let link=LifeItemLink(registration:item.registration,conversationID:item.conversationID,from:item.id,relation:proposed.relation,target:.init(kind:.item,id:proposed.target.uuidString),inferred:true,reason:plan.reason)
                if !candidate.links.contains(where:{$0.from == link.from && $0.relation == link.relation && $0.target == link.target}) { candidate.links.append(link) }
            }
            for binding in plan.bindings {
                let link=LifeItemLink(registration:item.registration,conversationID:item.conversationID,from:item.id,relation:.identifies,target:.init(kind:.memory,id:binding.memory.uuidString,containerID:binding.entity),inferred:true,reason:plan.reason)
                if !candidate.links.contains(where:{$0.from == link.from && $0.relation == link.relation && $0.target == link.target}) { candidate.links.append(link) }
            }
        }
        item.revision=UUID();item.updated = .now;candidate.items[index]=item
        try addReceipt(.init(id:operation,registration:item.registration,result:plan.reason,itemID:item.id),to:&candidate);try persist(candidate)
        if project.parentID != item.parentID { var before=project;before.placement?.status="paused";before.placement?.reason="Automatic placement was undone. Your chosen home takes priority.";before.placement?.parentPinned=true;edits[item.registration] = .init(before:before,savedRevision:item.revision) }
        return item
    }
    private func addReceipt(_ receipt: LifeWorkspaceReceipt?, to value: inout LifeWorkspaceState) throws {
        guard let receipt else { return }
        guard !value.receipts.contains(where: { $0.id == receipt.id }) else { throw LifeWorkspaceFailure.message("This operation already has a saved receipt. Read its result before continuing.") }
        // Operation identities are durable replay barriers. Result prose may be
        // compacted separately, but never evict an identity by history length.
        value.receipts.append(receipt)
    }
    private func persist(_ value: LifeWorkspaceState) throws {
        guard writable, let container else { throw LifeWorkspaceFailure.message(error ?? "Project storage is unavailable. Your changes have not been saved.") }
        try LifeWorkspaceRules.validate(value)
        do {
            let bytes = try LocalRecordCoding.preservingUnknown(value, original: loadedBytes)
            try LocalRecordRepository(container: container).write(["lifeWorkspace": bytes], expected: ["lifeWorkspace": LocalRecordVersion(loadedBytes)])
            loadedBytes = bytes
            state = value; revision = UUID(); error = nil
        } catch { self.error = "Projects could not be saved. Your editing draft is kept."; throw LifeWorkspaceFailure.message(self.error!) }
    }
}

/// Board moves only change a currently permitted task's local stage, at its captured folder revision.
@MainActor enum LifeTaskStageChange {
    static func applyDrag(_ id:UUID,stage:LifeTaskStage,capturedParent:UUID?,currentParent:UUID?,registration:String,activeRegistration:String,capturedIDs:Set<UUID>,currentIDs:Set<UUID>,expectedRevision:UUID,store:LifeWorkspaceStore)throws {
        guard registration == activeRegistration,capturedParent == currentParent else {
            throw LifeWorkspaceFailure.message("This folder changed. Try moving the task again.")
        }
        try apply(id,stage:stage,parent:capturedParent,registration:registration,permittedIDs:capturedIDs.intersection(currentIDs),expectedRevision:expectedRevision,store:store)
    }
    static func apply(_ id:UUID,stage:LifeTaskStage,parent:UUID?,registration:String,permittedIDs:Set<UUID>,expectedRevision:UUID,store:LifeWorkspaceStore)throws {
        guard store.revision == expectedRevision,permittedIDs.contains(id),let item=store.items(registration,includeTopics:true).first(where:{$0.id == id}),item.kind.isWork,item.parentID == parent,item.status != .archived else {
            throw LifeWorkspaceFailure.message("This folder changed. Try moving the task again.")
        }
        guard item.status != stage.status else { return }
        var value=item;value.status=stage.status
        _ = try store.save(value,expected:item.revision)
    }
}

/// Reordering is an exact sibling-only local edit. Moving into another folder stays explicit.
@MainActor enum LifeFolderReorder {
    static func apply(_ id:UUID,before:UUID?,parent:UUID?,capturedPage:UUID?,currentPage:UUID?,registration:String,activeRegistration:String,capturedIDs:Set<UUID>,currentIDs:Set<UUID>,expectedRevision:UUID,store:LifeWorkspaceStore)throws {
        let permitted=capturedIDs.intersection(currentIDs)
        guard registration == activeRegistration,capturedPage == currentPage,store.revision == expectedRevision,permitted.contains(id),
              let item=store.items(registration,includeTopics:true).first(where:{$0.id == id}),!item.kind.isWork,item.parentID == parent else {
            throw LifeWorkspaceFailure.message("This folder changed. Try reordering it again.")
        }
        if let before {
            guard before != id,permitted.contains(before),store.items(registration,includeTopics:true).contains(where:{$0.id == before && !$0.kind.isWork && $0.parentID == parent && $0.conversationID == item.conversationID}) else {
                throw LifeWorkspaceFailure.message("The folder order changed. Try reordering it again.")
            }
        }
        // A missing legacy parent must never turn a reorder into an implicit filing operation.
        if let parent,!store.items(registration,topic:item.conversationID).contains(where:{$0.id == parent}) {
            throw LifeWorkspaceFailure.message("Choose a current parent with Move before reordering this folder.")
        }
        try store.reorderFolder(id,registration:registration,before:before,expectedRevision:expectedRevision)
    }
}
