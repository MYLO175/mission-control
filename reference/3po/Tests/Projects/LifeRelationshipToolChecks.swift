import Foundation
import SwiftData

// Only the dashboard/source boundary is fictional. The actual tool session,
// project models, store, receipts and loaded-byte repository CAS run below.
@MainActor final class DashboardModel {
    struct Connection { var activeID: String }
    struct Assistant { var projects: LifeWorkspaceStore }
    final class Workspace {
        var selected = DashboardPage(title:"Fixture",widgets:[])
        var error: String?
        func update(_ widget: WidgetPlacement) {
            if let index = selected.widgets.firstIndex(where: { $0.id == widget.id }) { selected.widgets[index] = widget }
        }
    }
    var chatGPT: Connection
    var assistant: Assistant
    var workspace = Workspace()
    init(account: String, store: LifeWorkspaceStore) { chatGPT = .init(activeID:account); assistant = .init(projects:store) }
}
struct LifeLinkOption {
    var reference: LifeReference
    var title: String
    var detail: String
}
enum LifeWorkspaceContext {
    @MainActor static func resolve(_ reference: LifeReference, model: DashboardModel, registration: String, topic: UUID?, includeTopics: Bool) -> LifeLinkOption? { nil }
}

@main struct LifeRelationshipToolChecks {
    @MainActor static var checks = 0
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(),message); checks += 1
    }
    @MainActor static func rejects(_ message: String, _ body: () throws -> Void) {
        do { try body(); preconditionFailure(message) } catch { checks += 1 }
    }
    static func call(_ name: String, _ args: [String:Any]) throws -> PAFunctionCall {
        .init(id:UUID().uuidString,name:name,namespace:"pa",arguments:String(decoding:try JSONSerialization.data(withJSONObject:args,options:.sortedKeys),as:UTF8.self))
    }
    @MainActor final class Fixture {
        let account = "fictional-relationship-account"
        let container: ModelContainer
        let store: LifeWorkspaceStore
        let model: DashboardModel
        let topic: UUID?
        let owner: LifeItem
        let target: LifeItem
        let other: LifeItem
        let link: LifeItemLink
        let turnID = UUID()
        init(topic: UUID? = nil) throws {
            self.topic = topic
            container = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            store = LifeWorkspaceStore(container:container)
            owner = try store.save(.init(registration:account,conversationID:topic,kind:.space,title:"Fixture owner"),expected:nil)
            target = try store.save(.init(registration:account,conversationID:topic,kind:.task,title:"Fixture target"),expected:nil)
            other = try store.save(.init(registration:account,conversationID:topic,kind:.task,title:"Unrelated fixture task",notes:"Original note"),expected:nil)
            link = try store.link(.init(registration:account,conversationID:topic,from:owner.id,relation:.related,target:.init(kind:.item,id:target.id.uuidString)),expected:owner.revision)
            model = DashboardModel(account:account,store:store)
        }
        var args: [String:Any] { ["id":link.id.uuidString,"authorization":"Remove this relationship"] }
        var unlink: PAFunctionCall { get throws { try LifeRelationshipToolChecks.call("unlink_life_item",args) } }
        func session(topic capturedTopic: UUID? = nil, overrideTopic: Bool = false) throws -> LifeWorkspaceToolSession {
            let session = LifeWorkspaceToolSession(model:model,registration:account,topic:overrideTopic ? capturedTopic : topic,includeTopics:false,turnID:turnID,evaluationStore:store)
            let args: [String:Any] = ["query":"","root":NSNull(),"unfinished":false,"dueBefore":NSNull(),"maxMinutes":NSNull(),"deleted":false]
            let call = try LifeRelationshipToolChecks.call("read_life_items",args)
            _ = try session.execute(call,args:PAToolProtocol.arguments(call))
            return session
        }
        func editUnrelatedNote() throws -> LifeItem {
            var changed = store.items(account,topic:topic).first { $0.id == other.id }!
            let expected = changed.revision
            changed.notes = "Updated independent note"
            changed.additionalNotes = [.init(text:"Independent note card")]
            changed.status = .active
            return try store.save(changed,expected:expected)
        }
        func replaceLink(_ changed: LifeItemLink) throws {
            try store.unlink(link.id,registration:account,expectedRevision:store.revision)
            let owner = store.items(account,topic:topic).first { $0.id == changed.from }!
            _ = try store.link(changed,expected:owner.revision)
        }
    }
    @MainActor static func main() throws {
        // Unrelated saves before reference preparation and after preparation
        // must preserve exact owner/relationship authority and current data.
        for editAfterPreparation in [false,true] {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            if editAfterPreparation { try session.prepareExactReferences(call,args:f.args) }
            let changed = try f.editUnrelatedNote()
            if !editAfterPreparation { try session.prepareExactReferences(call,args:f.args) }
            let output = try session.execute(call,args:f.args)
            check(output.contains("\"saved\":true"),"Unchanged issued link is removed after an independent save")
            check(!f.store.state.links.contains { $0.id == f.link.id },"Exact link removed")
            check(f.store.state.items.first { $0.id == changed.id } == changed,"Independent task and notes remain exact")
            check(f.store.state.items.first { $0.id == f.owner.id } == f.owner && f.store.state.items.first { $0.id == f.target.id } == f.target,"Both endpoints are retained unchanged")
            let state = f.store.state, receipt = try session.completedReceipt(call,args:f.args)
            check(receipt?.contains("alreadySaved") == true,"Removal has a durable receipt")
            _ = try session.execute(call,args:f.args)
            check(f.store.state == state,"Same operation is not replayed")
            let reloaded = LifeWorkspaceStore(container:f.container)
            check(reloaded.state == state,"Saved removal and unrelated edits survive reopening")
        }
        do {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            let capture = try JSONDecoder().decode(LifeWorkspaceToolSession.Capture.self,from:JSONEncoder().encode(session.approvalCapture()))
            check(capture.exactRelationships?[f.link.id] == f.link && capture.links.isEmpty,"New approval saves exact relationship payload")
            let changed = try f.editUnrelatedNote(), restored = try f.session()
            try restored.restoreApprovalCapture(capture,call:call,args:f.args)
            _ = try restored.execute(call,args:f.args)
            check(!f.store.state.links.contains { $0.id == f.link.id },"Persisted approval accepts an unchanged link after unrelated changes")
            check(f.store.state.items.first { $0.id == changed.id } == changed,"Approval preserves current independent edit")
        }
        for field in ["relation","target","owner","reason","created"] {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            let capture = session.approvalCapture()
            var changed = f.link
            switch field {
            case "relation": changed.relation = .dependsOn
            case "target": changed.target = .init(kind:.item,id:f.other.id.uuidString)
            case "owner": changed.from = f.other.id
            case "reason": changed.reason = "A newer interpretation"
            default: changed.created = changed.created.addingTimeInterval(1)
            }
            try f.replaceLink(changed)
            rejects("Changed \(field) must reject preparation") { try session.prepareExactReferences(call,args:f.args) }
            rejects("Changed \(field) must reject direct execution") { _ = try session.execute(call,args:f.args) }
            rejects("Changed \(field) must reject restored approval") { try f.session().restoreApprovalCapture(capture,call:call,args:f.args) }
            check(f.store.state.links == [changed] && f.store.state.receipts.isEmpty,"Failed stale removal preserves the newer exact relationship and makes no receipt")
        }
        do {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            let capture = session.approvalCapture()
            try f.store.unlink(f.link.id,registration:f.account,expectedRevision:f.store.revision)
            rejects("Removed link must reject execution") { _ = try session.execute(call,args:f.args) }
            rejects("Removed link must reject restored approval") { try f.session().restoreApprovalCapture(capture,call:call,args:f.args) }
            check(f.store.state.receipts.isEmpty,"Missing relationship is not recorded as success")
        }
        for deletedOwner in [false,true] {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            let capture = session.approvalCapture()
            if deletedOwner { try f.store.trash(f.owner.id,registration:f.account,keepChildren:true,expectedRevision:f.store.revision) }
            else { var changed = f.owner; changed.title += " changed"; _ = try f.store.save(changed,expected:f.owner.revision) }
            rejects("Changed/unavailable owner must reject execution") { _ = try session.execute(call,args:f.args) }
            rejects("Changed/unavailable owner must reject approval") { try f.session().restoreApprovalCapture(capture,call:call,args:f.args) }
            check(f.store.state.links == [f.link],"Owner conflict preserves relationship")
        }
        do {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            let capture = session.approvalCapture()
            f.model.chatGPT.activeID = "different-account"
            rejects("Changed account rejects execution") { _ = try session.execute(call,args:f.args) }
            rejects("Changed account rejects approval") { try session.restoreApprovalCapture(capture,call:call,args:f.args) }
            check(f.store.state.links == [f.link],"Changed account makes no removal")
        }
        do {
            let f = try Fixture(topic:UUID()), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            let capture = session.approvalCapture(), otherScope = try f.session(topic:UUID(),overrideTopic:true)
            rejects("Relationship outside captured topic rejects") { try otherScope.restoreApprovalCapture(capture,call:call,args:f.args) }
            check(f.store.state.links == [f.link],"Different scope preserves relationship")
        }
        // Older pending approvals decode and keep their conservative original
        // revision guard; modern missing/mismatched payloads cannot fall back.
        for unrelatedSave in [false,true] {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            var legacy = session.approvalCapture()
            legacy.exactRelationships = nil; legacy.links = [f.link.id:f.store.revision]
            let encoded = try JSONEncoder().encode(legacy)
            let fields = try JSONSerialization.jsonObject(with:encoded) as! [String:Any]
            check(!fields.keys.contains("exactRelationships"),"Legacy fixture has no modern field")
            let decoded = try JSONDecoder().decode(LifeWorkspaceToolSession.Capture.self,from:encoded)
            check(decoded.exactRelationships == nil,"Legacy capture decodes")
            if unrelatedSave {
                _ = try f.editUnrelatedNote()
                rejects("Legacy approval cannot invent an unavailable old payload") { try f.session().restoreApprovalCapture(decoded,call:call,args:f.args) }
            } else {
                let restored = try f.session(); try restored.restoreApprovalCapture(decoded,call:call,args:f.args)
                _ = try restored.execute(call,args:f.args)
                check(f.store.state.links.isEmpty,"Unchanged legacy approval still works")
            }
        }
        for malformed in [false,true] {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            var capture = session.approvalCapture()
            capture.links = [f.link.id:f.store.revision]
            var wrong = f.link; wrong.id = UUID()
            capture.exactRelationships = malformed ? [f.link.id:wrong] : [:]
            rejects("Modern missing or mismatched payload never uses a legacy fallback") { try f.session().restoreApprovalCapture(capture,call:call,args:f.args) }
        }
        do {
            let f = try Fixture(), session = try f.session(), call = try f.unlink
            try session.prepareExactReferences(call,args:f.args)
            let external = LifeWorkspaceStore(container:f.container)
            var edited = external.items(f.account).first { $0.id == f.other.id }!
            let prior = edited.revision; edited.notes = "Another writer's retained note"
            edited = try external.save(edited,expected:prior)
            rejects("External saved-byte change must still reject the stale store write") { _ = try session.execute(call,args:f.args) }
            let reloaded = LifeWorkspaceStore(container:f.container)
            check(reloaded.state.links == [f.link],"External CAS conflict preserves link")
            check(reloaded.state.items.first { $0.id == edited.id } == edited,"External CAS conflict preserves newer data")
            check(reloaded.state.receipts.isEmpty,"External CAS conflict creates no success receipt")
        }
        print("PASS: \(checks) actual relationship-tool checks: unrelated task/notes, durable approval roundtrip, exact link/owner/account/topic conflicts, legacy compatibility, receipt replay and external writer CAS")
    }
}
