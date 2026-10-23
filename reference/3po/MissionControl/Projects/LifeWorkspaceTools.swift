import Foundation
import CryptoKit

/// One foreground turn issues optimistic record identities. Its ledger shares durable storage with manual edits.
@MainActor final class LifeWorkspaceToolSession {
    let model: DashboardModel
    let registration: String
    let topic: UUID?
    let includeTopics: Bool
    let turnID: UUID
    private(set) var issued: [UUID:LifeItem] = [:]
    private var issuedLinks: [UUID:LifeItemLink] = [:]
    private var issuedWidgets: [UUID:WidgetPlacement] = [:]
    private let evaluationStore: LifeWorkspaceStore?
    private var store: LifeWorkspaceStore { evaluationStore ?? model.assistant.projects }
    private var approvalReferenceIDs = Set<UUID>()
    struct Capture: Codable {
        var issued: [UUID:LifeItem]
        // Retained for approvals saved before exact relationship captures.
        var links: [UUID:UUID]
        var widgets: [UUID:WidgetPlacement]
        var exactRelationships: [UUID:LifeItemLink]? = nil
    }
    init(model: DashboardModel, registration: String, topic: UUID?, includeTopics: Bool, turnID: UUID, evaluationStore: LifeWorkspaceStore? = nil) {
        self.evaluationStore = evaluationStore
        self.model = model; self.registration = registration; self.topic = topic; self.includeTopics = includeTopics; self.turnID = turnID
    }
    private func json(_ value: Any) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)! }
    private func operationKey(_ call: PAFunctionCall, args: [String:Any]) throws -> String {
        let canonical = try JSONSerialization.data(withJSONObject: ["name":call.name, "arguments":args, "registration":registration, "topic":topic?.uuidString ?? "shared", "turn":turnID.uuidString], options: [.sortedKeys])
        return "life:" + SHA256.hash(data: canonical).map { String(format:"%02x", $0) }.joined()
    }
    private func hasReceipt(_ call: PAFunctionCall, args: [String:Any]) throws -> Bool {
        guard LifeWorkspaceTools.mutations.contains(call.name) else { return false }
        return store.receipt(try operationKey(call,args:args),registration:registration) != nil
    }
    func completedReceipt(_ call: PAFunctionCall, args: [String:Any]) throws -> String? {
        guard registration == model.chatGPT.activeID else { throw LifeWorkspaceFailure.message("Account changed; project operation stopped.") }
        guard LifeWorkspaceTools.mutations.contains(call.name),let receipt = store.receipt(try operationKey(call,args:args),registration:registration) else { return nil }
        return try json(["saved":true,"alreadySaved":true,"result":receipt.result,"instruction":"This operation already has a durable receipt. Read current records before doing anything else."])
    }
    /// References come only from the proposed operation, never title matching or
    /// a search across old conversation prose. Non-item source IDs stay separate.
    private func exactReferences(_ call: PAFunctionCall, args: [String:Any]) throws -> [UUID:Bool] {
        var result: [UUID:Bool] = [:] // true requires a parentable space
        func add(_ token: Any?, parent: Bool = false) throws {
            guard let token = token as? String else { return }
            guard let id = UUID(uuidString:token) else { throw LifeWorkspaceFailure.message("Use the exact project item identity returned by a current read.") }
            result[id] = (result[id] ?? false) || parent
        }
        switch call.name {
        case "create_life_items":
            for (index, entry) in (args["items"] as? [[String:Any]] ?? []).enumerated() {
                if let token = entry["parent"] as? String, token.hasPrefix("batch:") {
                    guard let parent = Int(token.dropFirst(6)), parent >= 0, parent < index else { throw LifeWorkspaceFailure.message("A batch parent must refer to an earlier item in this batch.") }
                } else { try add(entry["parent"],parent:true) }
            }
        case "change_life_item":
            try add(args["id"])
            if args["move"] as? Bool == true { try add(args["parent"],parent:true) }
        case "delete_life_item", "restore_life_item": try add(args["id"])
        case "reorder_life_item":
            try add(args["id"]); try add(args["parent"],parent:true); try add(args["before"])
        case "link_life_item":
            try add(args["from"])
            if args["kind"] as? String == "item" { try add(args["id"]) }
        case "undo_life_edit":
            guard let ticket = store.undoEdit(registration) else { throw LifeWorkspaceFailure.message("There is no unchanged local project edit available to undo.") }
            try add(ticket.before.id.uuidString)
        case "show_project_view": try add(args["root"],parent:true)
        case "read_life_items": try add(args["root"])
        default: break
        }
        return result
    }
    /// Local read preparation precedes semantic checking. Previously issued
    /// stale targets are rejected rather than silently rebased onto new content.
    func prepareExactReferences(_ call: PAFunctionCall, args: [String:Any]) throws {
        guard registration == model.chatGPT.activeID else { throw LifeWorkspaceFailure.message("Account changed; project operation stopped.") }
        if try hasReceipt(call,args:args) { return }
        let restoring = call.name == "restore_life_item"
        let all = store.items(registration,topic:topic,includeTopics:includeTopics,includeDeleted:restoring)
        var references = try exactReferences(call,args:args)
        if call.name == "unlink_life_item" {
            guard let id = (args["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let link = currentRelationship(id),
                  issuedLinks[id].map({ $0 == link }) ?? true else { throw LifeWorkspaceFailure.message("Read the exact current relationship before removing it.") }
            references[link.from] = false
            issuedLinks[id] = link
        }
        for (id,parent) in references {
            guard let item = all.first(where: { $0.id == id }),
                  restoring ? item.deletedAt != nil : item.deletedAt == nil,
                  !parent || !item.kind.isWork,
                  issued[id].map({ $0.revision == item.revision }) ?? true else {
                throw LifeWorkspaceFailure.message("The exact project item is unavailable or changed. Read its current state before changing or linking it.")
            }
        }
        var prepared = Set(references.keys)
        for id in references.keys {
            if let item = all.first(where: { $0.id == id }) {
                prepared.formUnion(LifeItemQuery.path(item,in:all).map(\.id))
                if call.name == "create_life_items" { prepared.formUnion(all.filter { $0.parentID == id && $0.deletedAt == nil }.prefix(20).map(\.id)) }
            }
        }
        guard prepared.count <= 80 else { throw LifeWorkspaceFailure.message("The requested project references exceed the bounded read allowance. Read a smaller branch first.") }
        // Parentless creation still inspects the existing structure locally.
        if call.name == "create_life_items", references.isEmpty {
            prepared.formUnion(all.prefix(60).map(\.id))
        }
        for item in all where prepared.contains(item.id) {
            if issued[item.id] == nil { issued[item.id] = item }
        }
        approvalReferenceIDs = prepared
        if call.name == "show_project_view" {
            guard let id = (args["widget"] as? String).flatMap(UUID.init(uuidString:)),
                  let widget = model.workspace.selected.widgets.first(where: { $0.id == id && $0.kind == .projects }),
                  issuedWidgets[id].map({ $0 == widget }) ?? true else { throw LifeWorkspaceFailure.message("The exact Projects widget is unavailable or changed.") }
            issuedWidgets[id] = widget
        }
    }
    func approvalCapture() -> Capture {
        let ordered = issued.keys.sorted { left,right in
            if approvalReferenceIDs.contains(left) != approvalReferenceIDs.contains(right) { return approvalReferenceIDs.contains(left) }
            return left.uuidString < right.uuidString
        }
        let retained = Dictionary(uniqueKeysWithValues:ordered.prefix(80).compactMap { id in issued[id].map { (id,$0) } })
        return .init(issued:retained,links:[:],widgets:issuedWidgets,exactRelationships:issuedLinks)
    }
    /// Approval adopts only captured identities. A creation's destination keeps
    /// its identity when descriptive fields change; edits retain exact revisions.
    func restoreApprovalCapture(_ value: Capture, call: PAFunctionCall, args: [String:Any]) throws {
        guard registration == model.chatGPT.activeID else { throw LifeWorkspaceFailure.message("Account changed; project approval stopped.") }
        if try hasReceipt(call,args:args) { return }
        guard value.issued.count <= 80 else { throw LifeWorkspaceFailure.message("The captured project read exceeds its bounded allowance.") }
        let references = try exactReferences(call,args:args)
        let all = store.items(registration,topic:topic,includeTopics:includeTopics,includeDeleted:call.name == "restore_life_item")
        var restored: [UUID:LifeItem] = [:]
        for (id,old) in value.issued {
            guard old.id == id,let item = all.first(where: { $0.id == id }),item.registration == old.registration,item.conversationID == old.conversationID else { continue }
            if item.revision == old.revision { restored[id] = item }
            else if call.name == "create_life_items",references[id] == true,item.deletedAt == nil,!item.kind.isWork { restored[id] = item }
        }
        for (id,parent) in references {
            guard let item = restored[id],call.name == "restore_life_item" ? item.deletedAt != nil : item.deletedAt == nil,!parent || !item.kind.isWork else {
                throw LifeWorkspaceFailure.message("The approved project target changed or is unavailable. Review its current state before saving.")
            }
        }
        let restoredLinks: [UUID:LifeItemLink]
        if let exact = value.exactRelationships {
            restoredLinks = exact.filter { id, link in link.id == id && currentRelationship(id) == link }
        } else {
            // Old approvals contain no relationship payload. Their original store
            // stamp must still match before adopting any current exact identity.
            restoredLinks = value.links.reduce(into:[:]) { result, entry in
                if entry.value == store.revision, let link = currentRelationship(entry.key) { result[entry.key] = link }
            }
        }
        if call.name == "unlink_life_item" {
            guard let id = (args["id"] as? String).flatMap(UUID.init(uuidString:)),let link = restoredLinks[id],restored[link.from] != nil else { throw LifeWorkspaceFailure.message("The approved relationship changed or is unavailable.") }
        }
        if call.name == "show_project_view" {
            guard let id = (args["widget"] as? String).flatMap(UUID.init(uuidString:)),let captured = value.widgets[id],model.workspace.selected.widgets.contains(captured),captured.kind == .projects else { throw LifeWorkspaceFailure.message("The approved Projects widget changed or is unavailable.") }
        }
        issued = restored
        issuedLinks = restoredLinks
        issuedWidgets = value.widgets.filter { model.workspace.selected.widgets.contains($0.value) }
        approvalReferenceIDs = Set(references.keys)
    }
    private func currentRelationship(_ id: UUID) -> LifeItemLink? {
        store.state.links.first { $0.id == id && $0.registration == registration && (includeTopics || $0.conversationID == nil || $0.conversationID == topic) }
    }
    private func current(_ text: String?) throws -> LifeItem {
        guard let id = text.flatMap(UUID.init(uuidString:)), let issued = issued[id],
              let value = store.items(registration, topic: topic, includeTopics: includeTopics).first(where: { $0.id == id }), value.revision == issued.revision else {
            throw LifeWorkspaceFailure.message("Read the current exact project item before changing or linking it.")
        }
        return value
    }
    func targetData(_ args: [String:Any]) throws -> String? {
        var requested = Set<UUID>()
        for key in ["id", "from", "parent", "root", "before"] {
            if let token = args[key] as? String, let id = UUID(uuidString:token) { requested.insert(id) }
        }
        for entry in args["items"] as? [[String:Any]] ?? [] {
            if let token = entry["parent"] as? String, let id = UUID(uuidString:token) { requested.insert(id) }
        }
        let all = store.items(registration, topic:topic, includeTopics:includeTopics,includeDeleted:true)
        var targets: [[String:Any]] = requested.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            guard let item = issued[id], all.contains(where: { $0.id == id && $0.revision == item.revision }) else { return nil }
            return ["id":item.id.uuidString, "titleData":item.title, "kind":item.kind.workspaceKind.rawValue, "status":item.status.rawValue, "pathData":LifeItemQuery.path(item, in:all).map(\.title), "directContentCount":all.filter{$0.parentID == item.id && $0.deletedAt == nil}.count, "directContentsData":Array(all.filter{$0.parentID == item.id && $0.deletedAt == nil}.prefix(20)).map{["id":$0.id.uuidString,"title":$0.title,"kind":$0.kind.workspaceKind.rawValue]}]
        }
        if args.count == 1, args["authorization"] != nil, let ticket = store.undoEdit(registration) {
            targets.append(["undoItemID":ticket.before.id.uuidString, "titleData":ticket.before.title, "kind":ticket.before.kind.workspaceKind.rawValue])
        }
        if let id = (args["id"] as? String).flatMap(UUID.init(uuidString:)), let link = currentRelationship(id), issuedLinks[id] == link, let owner = issued[link.from] {
            targets.append(["relationshipID":link.id.uuidString, "ownerTitleData":owner.title, "relation":link.relation.rawValue, "kind":link.target.kind.rawValue])
        }
        let batch: [[String:Any]] = (args["items"] as? [[String:Any]] ?? []).enumerated().map { index, entry in
            ["batchParentToken":"batch:" + String(index), "proposedTitleData":entry["title"] ?? "", "proposedKind":entry["kind"] ?? "", "parent":entry["parent"] ?? NSNull()]
        }
        return try json(["resolvedIssuedItems":targets, "proposedBatchStructureData":batch])
    }
    private func object(_ item:LifeItem,query:String?=nil)->[String:Any] {
        let extra=item.additionalNotes ?? []
        let primary=String(item.notes.prefix(extra.isEmpty ? 2000 : 1000))
        var budget=2000-primary.count
        let terms=LifeWorkspaceRules.key(query ?? "").split(separator:" ").map(String.init)
        let ranked=extra.enumerated().sorted {left,right in
            func matches(_ note:LifeNote)->Bool {!terms.isEmpty && terms.allSatisfy{LifeWorkspaceRules.key(note.text).contains($0)}}
            let a=matches(left.element),b=matches(right.element)
            return a == b ? left.offset < right.offset : a
        }.map(\.element)
        let additional:[[String:Any]]=ranked.prefix(6).map {note in
            let text=String(note.text.prefix(min(500,budget)));budget-=text.count
            return ["id":note.id.uuidString,"text":text,"truncated":text.count < note.text.count]
        }
        return ["id":item.id.uuidString,"title":item.title,"kind":item.kind.workspaceKind.rawValue,"parent":item.parentID?.uuidString as Any? ?? NSNull(),"status":item.status.rawValue,"notes":primary,"notesTruncated":item.notes.count > primary.count,"additionalNotes":additional,"additionalNotesTruncated":extra.count > additional.count,"noteEditing":"notes changes the original note only; additional note cards are edited locally in Projects.","due":item.due as Any? ?? NSNull(),"estimateMinutes":item.estimateMinutes as Any? ?? NSNull(),"areas":item.areas.map(\.rawValue),"ownership":item.ownership ?? "workspace","deleted":item.deletedAt != nil,"sortOrder":item.sortOrder as Any? ?? NSNull(),"path":LifeItemQuery.path(item,in:store.items(registration,topic:topic,includeTopics:includeTopics)).map(\.title)]
    }
    private func resolve(_ reference: LifeReference) -> LifeLinkOption? {
        if reference.kind == .item, let id = UUID(uuidString:reference.id), let item = store.items(registration, topic:topic, includeTopics:includeTopics).first(where: { $0.id == id }) {
            return .init(reference:reference, title:item.title, detail:item.kind.title)
        }
        return LifeWorkspaceContext.resolve(reference, model:model, registration:registration, topic:topic, includeTopics:includeTopics)
    }
    func execute(_ call: PAFunctionCall, args: [String:Any], reference: LifeReference? = nil) throws -> String {
        func text(_ key: String) -> String? { args[key] as? String }
        guard registration == model.chatGPT.activeID else { throw LifeWorkspaceFailure.message("Account changed; project operation stopped.") }
        let operationKey = try operationKey(call,args:args)
        if let receipt = try completedReceipt(call,args:args) { return receipt }
        switch call.name {
        case "undo_life_edit":
            let summary = "Local project edit undone. Linked sources are unchanged."
            let itemID = store.undoEdit(registration)?.before.id
            try store.undo(registration, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:itemID))
            if let itemID { issued.removeValue(forKey:itemID) }
            return try json(["saved":true, "result":summary])
        case "read_life_items":
            let root = try text("root").map { try current($0).id }
            guard LifeWorkspaceRules.dateValid(text("dueBefore")), (args["maxMinutes"] as? Int).map({ (1...100000).contains($0) }) != false else { throw LifeWorkspaceFailure.message("Use a date-only deadline or a positive estimate limit.") }
            let all = store.items(registration, topic: topic, includeTopics: includeTopics,includeDeleted:args["deleted"] as? Bool == true).filter{(args["deleted"] as? Bool == true) == ($0.deletedAt != nil)}
            let found = LifeItemQuery(root:root, query:text("query") ?? "", unfinished:args["unfinished"] as? Bool == true, dueBefore:text("dueBefore"), maxMinutes:args["maxMinutes"] as? Int).matching(all)
            var returned = Array(found.prefix(60))
            // Issue ancestors too: searching a module must expose its real parent, not invite title guessing.
            for item in Array(returned) { for parent in LifeItemQuery.path(item, in: all) where !returned.contains(where: { $0.id == parent.id }) && returned.count < 80 { returned.append(parent) } }
            for item in returned { issued[item.id] = item }
            let links = store.state.links.filter { issued[$0.from] != nil && $0.registration == registration && (includeTopics || $0.conversationID == nil || $0.conversationID == topic) }.prefix(120)
            var relationships: [[String:Any]] = []
            for link in links {
                issuedLinks[link.id] = link
                if let target = resolve(link.target) {
                    relationships.append(["id":link.id.uuidString, "from":link.from.uuidString, "relation":link.relation.rawValue, "targetKind":link.target.kind.rawValue, "targetID":link.target.id, "targetData":target.title, "coverage":target.detail])
                } else {
                    relationships.append(["id":link.id.uuidString, "from":link.from.uuidString, "relation":link.relation.rawValue, "targetKind":link.target.kind.rawValue, "available":false, "coverage":"Outside current permitted scope or cached coverage. Identity/content withheld; removal does not change the source."])
                }
            }
            let widgets = model.workspace.selected.widgets.filter { $0.kind == .projects }
            for widget in widgets { issuedWidgets[widget.id] = widget }
            return try json(["items":returned.map{object($0,query:text("query"))}, "relationships":relationships, "widgets":widgets.map { ["id":$0.id.uuidString, "view":$0.configuration.projectView ?? "Overview"] }, "coverage":"\(min(60,found.count)) of \(found.count) matching local records, plus issued ancestors. Relationships capped at120; unavailable source identities/content withheld. Local task state is not native completion. Missing records/links are not proof of absence."])
        case "delete_life_item":
            let item=try current(text("id")),summary="Moved “\(item.title)” to Recently deleted. Memory and external sources are retained."
            try store.trash(item.id,registration:registration,keepChildren:args["keepChildren"] as? Bool == true,expectedRevision:store.revision,receipt:.init(id:operationKey,registration:registration,result:summary,itemID:item.id));issued.removeValue(forKey:item.id)
            return try json(["saved":true,"result":summary])
        case "restore_life_item":
            guard let id=text("id").flatMap(UUID.init(uuidString:)),let prior=issued[id],store.state.items.contains(where:{$0.id == id && $0.registration == registration && $0.revision == prior.revision && $0.deletedAt != nil}) else { throw LifeWorkspaceFailure.message("Read the exact Recently deleted item before restoring.") }
            let summary="Restored “\(prior.title)” with its saved identities and links."
            try store.restore(id,registration:registration,expectedRevision:store.revision,receipt:.init(id:operationKey,registration:registration,result:summary,itemID:id))
            return try json(["saved":true,"result":summary])
        case "reorder_life_item":
            let item=try current(text("id")),parent=try text("parent").map{try current($0).id},before=try text("before").map{try current($0).id}
            let summary="Rearranged “\(item.title)” and preserved its contents."
            try store.move(item.id,registration:registration,parent:parent,before:before,expectedRevision:store.revision,receipt:.init(id:operationKey,registration:registration,result:summary,itemID:item.id))
            issued[item.id]=store.items(registration,topic:topic,includeTopics:includeTopics).first{$0.id == item.id}
            return try json(["saved":true,"result":summary])
        case "create_life_items":
            guard !issued.isEmpty || store.items(registration, topic:topic, includeTopics:includeTopics).isEmpty else { throw LifeWorkspaceFailure.message("Read the current structure before adding items.") }
            var values: [LifeItem] = []
            for entry in args["items"] as! [[String:Any]] {
                let parent: LifeItem?
                if let token = entry["parent"] as? String {
                    if token.hasPrefix("batch:"), let index = Int(token.dropFirst(6)), values.indices.contains(index) { parent = values[index] }
                    else { parent = try current(token) }
                } else { parent = nil }
                guard let kind = (entry["kind"] as? String).flatMap(LifeItemKind.init(rawValue:)), LifeItemKind.allCases.contains(kind) else {
                    throw LifeWorkspaceFailure.message("Create a space or a task.")
                }
                guard parent?.kind.isWork != true else { throw LifeWorkspaceFailure.message("Choose a space as the parent. Tasks cannot contain other items.") }
                let scope: UUID?
                if let parent { scope = parent.conversationID } else { scope = topic }
                values.append(.init(registration:registration, conversationID:scope, kind:kind, title:(entry["title"] as! String).trimmingCharacters(in:.whitespacesAndNewlines), parentID:parent?.id, notes:entry["notes"] as! String, due:entry["due"] as? String, estimateMinutes:entry["estimateMinutes"] as? Int, areas:(entry["areas"] as! [String]).compactMap(LifeArea.init(rawValue:)), sourceTurnID:turnID.uuidString, humanEvidence:String((text("authorization") ?? "").prefix(2000))))
            }
            let summary = "Created \(values.count) local workspace items."
            let saved = try store.create(values, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:values.first?.id))
            for item in saved { issued[item.id] = item }
            return try json(["saved":true, "result":summary, "items":saved.map{object($0)}])
        case "change_life_item":
            var item = try current(text("id")); let expected = item.revision
            if let title = text("title") { item.title = title.trimmingCharacters(in:.whitespacesAndNewlines) }
            if let notes = text("notes") { item.notes = notes }
            if let status = text("status").flatMap(LifeItemStatus.init(rawValue:)) { item.status = status }
            if let due = text("due") { item.due = due.isEmpty ? nil : due }
            if let minutes = args["estimateMinutes"] as? Int { item.estimateMinutes = minutes == 0 ? nil : minutes }
            if args["move"] as? Bool == true {
                item.parentID = try text("parent").map { try current($0).id }
                if item.kind == .project { item.placement = .init(status:"placed",reason:"Your chosen home is pinned.",parentPinned:true) }
            }
            let summary = "Updated “\(item.title)” locally. Linked sources are unchanged."
            let saved = try store.save(item, expected:expected, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:item.id))
            issued[item.id] = saved
            return try json(["saved":true, "result":summary, "item":object(saved)])
        case "link_life_item":
            let owner = try current(text("from")), kind = LifeReferenceKind(rawValue:text("kind")!)!
            let target: LifeReference
            if kind == .item { target = .init(kind:.item, id:try current(text("id")).id.uuidString) }
            else {
                guard let reference, reference.kind == kind, reference.id == text("id") else { throw LifeWorkspaceFailure.message("Read the exact permitted memory/source before linking it.") }
                target = reference
            }
            let summary = "Linked “\(owner.title)” without changing its source."
            let link = try store.link(.init(registration:registration, conversationID:owner.conversationID, from:owner.id, relation:LifeRelation(rawValue:text("relation")!)!, target:target), expected:owner.revision, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:owner.id))
            issuedLinks[link.id] = link
            return try json(["saved":true, "result":summary, "relationshipID":link.id.uuidString])
        case "unlink_life_item":
            guard let id = text("id").flatMap(UUID.init(uuidString:)), let link = issuedLinks[id], currentRelationship(id) == link else { throw LifeWorkspaceFailure.message("Read the exact current relationship before removing it.") }
            _ = try current(link.from.uuidString)
            let summary = "Removed the relationship. Both endpoints are retained."
            // Exact issued inputs were checked synchronously above. Retain the
            // store's loaded-byte CAS without depending on unrelated local edits.
            try store.unlink(id, registration:registration, expectedRevision:store.revision, receipt:.init(id:operationKey, registration:registration, result:summary, itemID:nil))
            return try json(["saved":true, "result":summary])
        case "show_project_view":
            guard evaluationStore == nil else { throw LifeWorkspaceFailure.message("Disposable evaluations cannot change your dashboard.") }
            guard let id = text("widget").flatMap(UUID.init(uuidString:)), let baseline = issuedWidgets[id], var widget = model.workspace.selected.widgets.first(where: { $0.id == id && $0.kind == .projects }), widget == baseline else { throw LifeWorkspaceFailure.message("Read an unchanged Projects widget on this dashboard first. Add one through Add widget if none is available.") }
            let root = try text("root").map { try current($0).id }
            if widget.configuration.projectRoots == nil { widget.configuration.projectRoots = [:] }
            widget.configuration.projectRoots?[registration] = root?.uuidString ?? ""; widget.configuration.projectView = text("view"); widget.configuration.projectOnlyUnfinished = args["unfinished"] as? Bool
            model.workspace.update(widget)
            guard model.workspace.error == nil, model.workspace.selected.widgets.contains(widget) else { throw LifeWorkspaceFailure.message(model.workspace.error ?? "The project view could not be saved.") }
            issuedWidgets[id] = widget
            return try json(["saved":true, "result":"Project view updated. Dashboard Undo is available."])
        default: throw LifeWorkspaceFailure.message("Unknown local project operation.")
        }
    }
}
