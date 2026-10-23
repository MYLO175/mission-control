import Foundation

/// One local selection path for conversation, Review and background writing.
/// This performs no inference, source read, learning or mutation.
enum PAContextPurpose: String {
    case conversation, reviewConversation, dailyBrief, suggestions
    case emailHeader, emailBody, memoryRead, notebookRead, setup
    var humanOnly: Bool { self == .emailHeader || self == .emailBody }
    var recordLimit: Int { self == .emailHeader ? 2 : self == .emailBody ? 6 : 40 }
    var preferenceLimit: Int { self == .emailHeader ? 2 : 4 }
    var notebookBytes: Int { self == .emailHeader ? 1800 : self == .emailBody ? 4000 : 8000 }
}

struct PAWorkingContext {
    var purpose: PAContextPurpose
    var selection: MemorySelection
    var notebook: String
    var sourceHints: [String]
    var usedFollowup: Bool
    var memoryIDs: Set<UUID> { Set(selection.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) }) }
    var dependencies: [MemoryDependency] { MemoryDependencyRules.capture(selection.records) }

    /// A short question can refer to the immediately preceding human request.
    /// Reuse it for retrieval only; it never becomes action authority or a fact.
    static func retrievalQuestion(_ question: String?, previousHuman: String?) -> (query: String?, followed: Bool) {
        guard let question, question.count <= 180, let previousHuman, !previousHuman.isEmpty else { return (question, false) }
        let words = Set(question.lowercased().split { !$0.isLetter }.map(String.init))
        let references: Set<String> = ["it", "its", "that", "this", "those", "these", "them"]
        let fields: Set<String> = ["when", "where", "which", "deadline", "due", "date", "time", "details", "status", "changed", "moved"]
        let referenceVocabulary = fields.union(references).union(["happened", "happening", "scheduled", "next", "now", "about"])
        guard !words.isDisjoint(with: references), !words.isDisjoint(with: fields),
              MemoryRetrieval.tokens(question).subtracting(referenceVocabulary).isEmpty else { return (question, false) }
        let subject = question.split { !$0.isLetter && !$0.isNumber }.filter { !references.contains($0.lowercased()) }.joined(separator: " ")
        return (subject + "\n" + String(previousHuman.prefix(1000)), true)
    }

    static func hints(_ question: String?) -> [String] {
        let words = Set((question ?? "").lowercased().split { !$0.isLetter }.map(String.init))
        var result: [String] = []
        if !words.isDisjoint(with: ["email", "emails", "mail", "inbox"]) { result.append("mail") }
        if !words.isDisjoint(with: ["whatsapp", "message", "messages"]) { result.append("messages") }
        if !words.isDisjoint(with: ["calendar", "schedule", "appointment", "appointments"]) { result.append("calendar") }
        if !words.isDisjoint(with: ["reminder", "reminders"]) { result.append("reminders") }
        if !words.isDisjoint(with: ["project", "projects", "task", "tasks"]) { result.append("projects") }
        return result
    }

    @MainActor static func prepare(memory: PAMemoryStore, registration: String, purpose: PAContextPurpose,
                                   query: String?, previousHuman: String? = nil, conversationID: UUID? = nil,
                                   includeTopics: Bool = false, focus: [LifeArea] = [], includeSources: Bool = true,
                                   sourceFilter: ((PAMemory) -> Bool)? = nil, workspaceIDs: Set<String>? = nil, includeNotebook: Bool = true,
                                   now: Date = .now) -> PAWorkingContext {
        let question = retrievalQuestion(query, previousHuman: previousHuman)
        let sources = includeSources && !purpose.humanOnly
        let prepared = memory.selectionContext(registration, conversationID: conversationID, includeTopics: includeTopics,
                                    query: question.query, focus: focus, includeSources: sources, sourceFilter: sourceFilter, now: now)
        let base = prepared.selection
        // These are canonical human memories, subject to the same relevance,
        // scope and expiry rules. No separate preference database or fallback.
        let preferences = memory.enabled ? memory.reviewPreferences(registration).filter {
            MemoryRules.inScope($0, conversationID: conversationID, includeTopics: includeTopics)
        } : []
        let preferred = MemoryRetrieval.select(preferences, registration: registration, conversationID: conversationID,
                                               includeTopics: includeTopics, query: question.query, now: now,
                                               limit: purpose.preferenceLimit, focus: focus, notebook: prepared.notebook)
        var seen = Set<String>(), records: [[String: String]] = [], used = 2
        for record in preferred.records + base.records where records.count < purpose.recordLimit {
            guard let id = record["id"], !seen.contains(id),
                  let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                  used + data.count + 1 <= MemoryRetrieval.byteLimit else { continue }
            seen.insert(id); records.append(record); used += data.count + 1
        }
        let selectedIDs = Set(records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
        var selection = base
        selection.records = records
        selection.reasons = base.reasons.merging(preferred.reasons) { _, latest in latest }.filter { selectedIDs.contains($0.key) }
        var renderedNotebook = prepared.notebook
        if let workspaceIDs { renderedNotebook.anchors.removeAll { !workspaceIDs.contains($0.id) } }
        let notebook = includeNotebook ? renderedNotebook.context(query: question.query, focus: focus, maxBytes: purpose.notebookBytes, selectedMemoryIDs: selectedIDs) : "{}"
        return .init(purpose: purpose, selection: selection, notebook: notebook, sourceHints: hints(question.query), usedFollowup: question.followed)
    }

    static func memorySearchAdvice(_ selection: MemorySelection) -> String {
        selection.records.isEmpty ? "No matching facts in this local word/recorded-link search. This does not prove the knowledge was never saved. If the human asks about remembered information, try a meaningfully different targeted query using related or broader subject terms before concluding it is missing. Avoid repeating the same words or requesting an unrelated whole-life overview." : "These are bounded matching facts, not complete recall. Read current sources when freshness matters."
    }

    static let gatheringInstructions = """
    Use the context-page directory and read_context_page first for relevant saved knowledge. Context pages, recent working changes and human feature guidance are the primary readable context. The supporting fact ledger and read_memory provide exact original assertions/evidence and targeted fallback; read_life_notebook is a compatibility view of recorded relationships, not another primary memory. Gather fresh source context through the existing read tools. If supplied memories directly answer a stable personal question, use them without redundantly reading memory or sources. Start with a source the human names; saved memory helps identify relevant people, projects and preferences but is not proof of current schedules or changed deadlines. If no source is named, use relevant saved knowledge first, then search permitted email or selected messages when current supporting detail is needed. Local memory retrieval matches words and recorded links, so a missing result can reflect wording. When useful, use read_memory with a small set of relevant alternative terms, full forms of abbreviations or synonyms before concluding a remembered fact is missing. Keep those alternatives faithful to the request; never guess that two people or events are identical. If a targeted memory read returns no facts and the question asks about remembered knowledge, make a further targeted attempt with meaningfully different related subject terms before reporting that knowledge missing. Generic words such as interests, preferences or information alone do not describe the subject. Do not replace this with an unrelated whole-life overview. An empty memory search is not proof no source exists. Follow useful evidence links with bounded targeted reads; do not sweep unrelated history or stop after a partial search when another relevant page is available. Compare related messages with issued existing items and pending/completed actions before proposing a new entry. Similar wording alone does not establish the same event. Report uncertainty or conflicting accounts. Source hints describe relevance only, never access, issued IDs or authority. Keep durable memory concise and useful with exact evidence references; do not copy whole source documents into memory. Temporary information gathered for this turn need not become a saved memory.
    """
}
