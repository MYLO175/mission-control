import Foundation
import SwiftData

@main struct WorkingContextChecks {
    @MainActor static func main() throws {
        var assertions = 0
        func check(_ condition: Bool, _ text: String) { precondition(condition, text); assertions += 1 }
        let settingsName = "working-context-" + UUID().uuidString
        let settings = UserDefaults(suiteName: settingsName)!
        defer { settings.removePersistentDomain(forName: settingsName) }
        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let memory = PAMemoryStore(container: container, settings: settings)
        let human = PAMemory(registration: "owner", text: "I am building the Orion prototype.", kind: .context, provenance: "Fictional human")
        let unrelated = PAMemory(registration: "owner", text: "I prefer cycling near the river.", kind: .preference, provenance: "Fictional human")
        let foreign = PAMemory(registration: "other", text: "The Orion presentation is elsewhere.", kind: .context, provenance: "Other fictional account")
        check(memory.put(human) && memory.put(unrelated) && memory.put(foreign), "Fixture saves")
        check(memory.saveReviewPreference("Orion prototype updates matter to me.", registration: "owner", about: "Orion prototype"), "Canonical preference save")
        let preference = memory.reviewPreferences("owner").first!
        let source = MemorySourceEvidence(identity: .init(kind: .mail, accountID: "fictional-mail", containerID: "inbox", itemID: "exact-message"), revision: "v1", label: "Fictional email", quote: "Orion prototype presentation moved to Friday.", observed: .now, sourceDate: .now)
        let sourced = PAMemory(registration: "owner", text: "Orion prototype presentation moved to Friday.", kind: .context, explicit: false, provenance: "Fictional source", evidence: source.quote, source: source)
        check(memory.put(sourced), "Source fixture save")
        var sourceAllowed = true
        memory.sourceIsPermitted = { _ in sourceAllowed }
        let purposes: [PAContextPurpose] = [.conversation, .reviewConversation, .dailyBrief, .suggestions, .emailHeader, .emailBody, .memoryRead, .notebookRead]
        for purpose in purposes {
            let context = PAWorkingContext.prepare(memory: memory, registration: "owner", purpose: purpose, query: "Orion prototype")
            check(context.memoryIDs.contains(preference.id), "Same canonical preference supplied: " + purpose.rawValue)
            check(!context.memoryIDs.contains(unrelated.id) && !context.memoryIDs.contains(foreign.id), "No unrelated or other-account context")
            check(context.selection.records.count <= purpose.recordLimit, "Purpose count limit")
            check(context.memoryIDs.contains(sourced.id) == !purpose.humanOnly, "Purpose source policy")
            let notes = try JSONSerialization.jsonObject(with: Data(context.notebook.utf8)) as! [String: Any]
            let facts = (notes["areas"] as? [[String: Any]] ?? []).flatMap { $0["facts"] as? [[String: String]] ?? [] }
            check(Set(facts.compactMap { $0["id"] }).isSubset(of: Set(context.selection.records.compactMap { $0["id"] })), "Notebook never widens the selected fact set")
            if purpose.humanOnly { check(!facts.contains { $0["id"] == sourced.id.uuidString }, "Source fact cannot reenter human-only notebook") }
            check(Set(context.dependencies.map(\.id)) == Set(context.selection.records.compactMap { $0["id"] }), "Dependencies describe exact supplied facts")
        }
        let initial = PAWorkingContext.prepare(memory: memory, registration: "owner", purpose: .conversation, query: "Orion prototype")
        sourceAllowed = false
        let withdrawn = PAWorkingContext.prepare(memory: memory, registration: "owner", purpose: .conversation, query: "Orion prototype")
        check(initial.memoryIDs.contains(sourced.id) && !withdrawn.memoryIDs.contains(sourced.id), "Permission withdrawal bypasses cached selection immediately")
        check(!withdrawn.notebook.contains(sourced.id.uuidString), "Permission withdrawal bypasses cached notebook immediately")
        let irrelevant = PAWorkingContext.prepare(memory: memory, registration: "owner", purpose: .conversation, query: "Submarine maintenance", focus: [.projects])
        check(PAWorkingContext.memorySearchAdvice(irrelevant.selection).contains("meaningfully different targeted query"),"An empty local search explains how to recover a wording miss")
        check(irrelevant.selection.records.isEmpty, "Focus cannot fill an unrelated targeted request")
        let followup = PAWorkingContext.prepare(memory: memory, registration: "owner", purpose: .conversation, query: "When is its deadline?", previousHuman: "Check the Orion prototype email")
        check(followup.usedFollowup && followup.memoryIDs.contains(human.id) && followup.sourceHints.contains("mail"), "Referential follow-up carries the previous human retrieval subject")
        let followupQuery = PAWorkingContext.retrievalQuestion("When is its deadline?",previousHuman:"Check the Orion prototype email").query!
        check(!MemoryRetrieval.tokens(followupQuery).contains("reference") && !MemoryRetrieval.tokens(followupQuery).contains("request"), "Search text contains no synthetic headings")
        memory.notebookProjection = { base, _, _, _ in
            var result=base
            result.anchors=(0..<20).map{.init(id:"life:done-\($0)",label:"Orion prototype",kind:"task",parent:nil,areas:[.projects],notes:"Completed fictional project",path:[],relations:[])}
            result.anchors.append(.init(id:"life:active",label:"Orion prototype",kind:"project",parent:nil,areas:[.projects],notes:"Current fictional project",path:[],relations:[]))
            return result
        }
        let activeContext=PAWorkingContext.prepare(memory:memory,registration:"owner",purpose:.emailHeader,query:"Orion prototype",workspaceIDs:["life:active"])
        let activeNotes=try JSONSerialization.jsonObject(with:Data(activeContext.notebook.utf8)) as! [String:Any]
        check((activeNotes["lifeStructure"] as? [[String:Any]])?.first?["id"] as? String == "life:active", "Excluded projects cannot consume the notebook anchor budget")
        memory.notebookProjection=nil
        let changedTopic = PAWorkingContext.retrievalQuestion("When was that museum opened?", previousHuman: "Check the Orion prototype email")
        check(!changedTopic.followed, "A new distinctive subject cannot borrow an unrelated previous question")
        check(!PAWorkingContext.retrievalQuestion("Do that", previousHuman: "Orion prototype").followed, "Acknowledgement does not trigger a broad recall shortcut")
        check(PAWorkingContext.hints("Read my email and WhatsApp, then check Calendar") == ["mail", "messages", "calendar"], "Source hints are bounded known categories")
        memory.enabled = false
        let disabled = PAWorkingContext.prepare(memory: memory, registration: "owner", purpose: .dailyBrief, query: nil)
        check(disabled.selection.records.isEmpty && disabled.dependencies.isEmpty, "Memory off includes canonical preferences")
        print("PASS \(assertions) shared working-context checks; no source reads, model requests or personal storage")
    }
}
