import Foundation

struct AssistantTurn: Codable, Identifiable, Equatable {
    var id = UUID()
    var role: String
    var content: String
    var completed: Bool
    var deliveryID: String?
    var created: Date? = .now
    /// Context captured when sent; changing a widget's topic never retargets a reply.
    var contextID: UUID?
    var choices: [String]? = nil
    var profileSessionID: UUID? = nil
    var profileControl: Bool? = nil
    var memoryNotes: [String]? = nil
    /// Local failure reasons, without raw tool arguments, source bodies or credentials.
    var toolErrors: [String]? = nil
    /// New turns separate unresolved failures from the retained diagnostic history.
    var unresolvedToolErrors: [String]? = nil
    var sourceMemoryIDs:[UUID]? = nil
    /// Exact page/working reference versions, without source prose or model reasoning.
    var contextKnowledgeVersions: [String: String]? = nil
    var focusAreas:[LifeArea]? = nil
    var images:[ChatImageAttachment]? = nil
    /// IDs/counts only. A prepared input trace, not an assertion of model attention or write success.
    var contextCapture: PAContextCapture? = nil
    /// Concrete local proposals. Approval is a human UI action, never model prose.
    var actionApprovals:[AssistantActionProposal]? = nil
    var approvalQueuedRequestID:UUID? = nil
    /// Final verified work metadata. Never inferred from assistant prose.
    var actionResult:AssistantActionResult? = nil
}

struct AssistantActionResult:Codable,Equatable {
    var phase:String
    var receipts:[String]
    var confirmedActions:Int
    var unconfirmedActions:Int
    /// Explicitly verified/user-confirmed recovery only, preserving saved history.
    var resolvedActivityIDs:[String]? = nil
    var succeeded:Bool {phase == "completed" && confirmedActions > 0 && unconfirmedActions == 0 && !receipts.isEmpty}
}

struct AssistantActionProposal:Codable,Equatable,Identifiable {
    enum Phase:String,Codable {case pending,attempted,completed,failed,dismissed}
    var id=UUID()
    var toolName:String
    var arguments:String
    /// Private exact targets/destinations and ownership, not an inference trace.
    var snapshot:Data
    var outline:[String]
    var details:[String]
    var phase:Phase = .pending
    var result:String? = nil
    var approvedAt:Date? = nil
}
struct PAChatApprovalRequired:Error {var proposal:AssistantActionProposal;var stopInference=false}

/// Bounded lookup metadata, separate from reasoning, source bodies and action receipts.
struct AssistantLookupTrace: Codable, Equatable, Identifiable {
    var id = UUID()
    var tool: String
    var query: String?
    var filters: [String] = []
    var targetID: String?
    var accessFingerprint: String?
    var status = "running"
    var resultCount: Int?
    var pageIDs: [String]?
    static func queryExcerpt(_ text: String) -> String { ConversationRules.utf8Prefix(text, bytes: 400) + (text.utf8.count > 400 ? "…" : "") }

    static let names: Set<String> = ["read_assistant_context", "read_context_page", "read_memory", "read_life_notebook", "read_life_items", "read_calendar", "read_reminders", "read_item_details", "search_mail", "continue_mail", "read_email", "list_whatsapp_chats", "search_whatsapp", "read_weather", "read_attention"]
    var title: String {
        switch tool {
        case "read_assistant_context": return "Assistant tools"
        case "read_context_page": return "Context pages"
        case "read_memory": return "Supporting facts"
        case "read_life_notebook": return "Life context"
        case "read_life_items": return "Projects"
        case "read_calendar": return "Calendar"
        case "read_reminders": return "Reminders"
        case "read_item_details": return "Item details"
        case "search_mail": return "Email search"
        case "continue_mail": return "Email search continued"
        case "read_email": return "Email opened"
        case "list_whatsapp_chats": return "Selected WhatsApp chats"
        case "search_whatsapp": return "WhatsApp search"
        case "read_weather": return "Weather"
        case "read_attention": return "Brief and Review inbox"
        default: return "Lookup"
        }
    }
    static func request(tool: String, namespace: String?, arguments: String, access: String?) -> Self? {
        guard namespace == "pa", names.contains(tool), arguments.utf8.count <= 32_000,
              let args = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] else { return nil }
        let query = (args["terms"] as? [String]).map { $0.prefix(5).joined(separator: ", ") } ?? args["query"] as? String
        var value = Self(tool: tool, query: query.map(queryExcerpt), accessFingerprint: access)
        if let start = args["start"] as? String, let end = args["end"] as? String { value.filters.append(String(start.prefix(24)) + " → " + String(end.prefix(24)) + " (end excluded)") }
        if let folders = args["folders"] as? [String] { value.filters.append(folders.filter { ["inbox", "sent", "archive"].contains($0) }.joined(separator: ", ")) }
        if tool == "read_reminders" { value.filters.append("Incomplete reminders") }
        if tool == "read_life_items", args["unfinished"] as? Bool == true { value.filters.append("Unfinished work") }
        if tool == "read_context_page", let offset = args["offset"] as? String, offset != "0" { value.filters.append("Page continuation") }
        if ["read_context_page", "read_life_items"].contains(tool), let target = (args["id"] ?? args["root"]) as? String { value.targetID = String(target.prefix(180)) }
        if tool == "search_whatsapp" {
            if let chat = args["chat"] as? String { value.targetID = String(chat.prefix(180)) }
            else { value.filters.append("All selected chats") }
        }
        return value
    }
    mutating func finish(output: String, succeeded: Bool) {
        status = succeeded ? "completed" : "failed"
        guard succeeded, let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any] else { return }
        if object["available"] as? Bool == false || object["unavailable"] != nil { status = "unavailable"; return }
        let key: String? = switch tool {
        case "read_context_page": "pages"
        case "read_memory", "read_life_notebook": "records"
        case "read_life_items": "items"
        case "read_calendar": "events"
        case "read_reminders": "reminders"
        case "search_mail", "continue_mail": "sources"
        case "list_whatsapp_chats": "chats"
        case "search_whatsapp": "messages"
        default: nil
        }
        if let key, let rows = object[key] as? [Any] { resultCount = rows.count }
        if tool == "read_context_page" {
            pageIDs = Array((object["pages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.filter { $0.utf8.count <= 180 }.prefix(12))
            if object["instructions"] != nil || object["currentProject"] != nil { resultCount = (resultCount ?? 0) + 1 }
        }
    }
}
struct PAContextCapture: Codable, Equatable, Identifiable {
    var id = UUID()
    var captured = Date.now
    var model: String
    var focusAreas: [LifeArea]?
    var memoryIDs: [UUID]
    var eligibleMemoryCount: Int
    var notebookMemoryIDs: [UUID]
    var workspaceIDs: [String]
    var historyTurnIDs: [UUID]
    var excerptedHistoryIDs: [UUID]
    var sourceSnapshotIncluded: Bool
    var sourceSnapshotBytes: Int
    var profileSetup: Bool
    var consultedMemoryIDs: [UUID] = []
    var attemptedTools: [String] = []
    var preparationNotes:[String]? = nil
    /// Version 1 records initial, successful-read and transitive history dependencies.
    var sourceMemoryDependencyVersion:Int? = nil
    var selectionPurpose:String? = nil
    var sourceHints:[String]? = nil
    var usedFollowupContext:Bool? = nil
    var contextPageIDs: [String]? = nil
    var contextGuideFingerprint: String? = nil
    var contextGuideBytes: Int? = nil
    var requestMode: String? = nil
    /// Inspection split only; memoryIDs retains the complete initial evidence union.
    var directMemoryIDs: [UUID]? = nil
    var pageSupportingMemoryIDs: [UUID]? = nil
    var registration: String? = nil
    var retrievalQuery: String? = nil
    var retrievalAccess: String? = nil
    var lookups: [AssistantLookupTrace]? = nil
    var omittedLookups: Int? = nil
    mutating func appendLookup(_ lookup: AssistantLookupTrace) {
        var rows = lookups ?? []; rows.append(lookup)
        lookups = rows; boundLookups()
    }
    mutating func boundLookups() {
        var rows = lookups ?? []
        while !rows.isEmpty && (rows.count > 32 || ((try? JSONEncoder().encode(rows).count) ?? Int.max) > 16_000) {
            rows.removeFirst(); omittedLookups = (omittedLookups ?? 0) + 1
        }
        lookups = rows
    }
    static func notebookIDs(_ context:String)->(memories:[UUID],workspace:[String]) {
        let object=(try? JSONSerialization.jsonObject(with:Data(context.utf8))) as? [String:Any] ?? [:]
        let areas=object["areas"] as? [[String:Any]] ?? []
        let ids=areas.flatMap{($0["facts"] as? [[String:String]] ?? []).compactMap{$0["id"].flatMap(UUID.init(uuidString:))}}
        return (Array(Set(ids)).sorted{$0.uuidString < $1.uuidString},(object["lifeStructure"] as? [[String:Any]] ?? []).compactMap{$0["id"] as? String})
    }
}
/// Stable Activity metadata, excluding prose that changes for every streamed delta.
struct AssistantActivityContext:Equatable {
    var accountID:String
    var title:String
    var reviewKey:String?
    var reviewSourceKind:String?
    var reviewAccountID:String?
    var reviewMessageID:String?
    var reviewSourceIdentity:String?
    var reviewSourceChatID:String?
    var turnDates:[UUID:Date]=[:]
    var attemptedTools:[UUID:[String]]=[:]
    var repliesAfter:[UUID:UUID]=[:]
    var actionResults:[UUID:AssistantActionResult]=[:]
    var unresolvedActionErrors:[UUID:[String]]=[:]
    var resolvedActivityIDs:Set<String>=[]
    init(_ conversation:AssistantConversation) {
        accountID=conversation.accountID;title=conversation.title;reviewKey=conversation.reviewKey
        reviewSourceKind=conversation.reviewSourceKind;reviewAccountID=conversation.reviewAccountID
        reviewMessageID=conversation.reviewMessageID;reviewSourceIdentity=conversation.reviewSourceIdentity;reviewSourceChatID=conversation.reviewSourceChatID
        // Exact transcript order handles queued replies whose timestamps precede
        // the prior response finishing. Prose and streamed completion flags are excluded.
        var laterHuman:[String:UUID]=[:]
        for turn in conversation.turns.reversed() {
            let scope=(turn.contextID?.uuidString ?? "general")+"|"+(turn.profileSessionID?.uuidString ?? "")
            if turn.role == "user",turn.deliveryID == nil {laterHuman[scope]=turn.id}
            else if turn.role == "assistant",let reply=laterHuman[scope] {repliesAfter[turn.id]=reply}
        }
        for turn in conversation.turns {
            if turnDates[turn.id] == nil,let created=turn.created {turnDates[turn.id]=created}
            if attemptedTools[turn.id] == nil,let names=turn.contextCapture?.attemptedTools,!names.isEmpty {attemptedTools[turn.id]=names}
            if turn.completed,let result=turn.actionResult {
                actionResults[turn.id]=result
                if let errors=turn.unresolvedToolErrors,!errors.isEmpty {unresolvedActionErrors[turn.id]=errors}
                if result.succeeded,(turn.unresolvedToolErrors ?? []).isEmpty {resolvedActivityIDs.formUnion(result.resolvedActivityIDs ?? [])}
            }
        }
    }
}

struct AssistantConversation: Codable, Identifiable, Equatable {
    var id = UUID()
    var accountID: String
    var title: String
    var created = Date.now
    var turns: [AssistantTurn] = []
    var isPrimary: Bool?
    /// Dedicated Review history stays outside the primary feed and legacy topics.
    var reviewKey:String? = nil
    var reviewSourceKind:String? = nil
    var reviewAccountID:String? = nil
    var reviewMessageID:String? = nil
    var reviewSourceIdentity:String? = nil
    var reviewSourceChatID:String? = nil
    var focus: String?
    var isTopic: Bool?
    var notebookAreas:[LifeArea]? = nil
}

struct AssistantTranscriptRow:Identifiable {
    var turn:AssistantTurn
    var separator:String?
    var id:UUID {turn.id}
}

enum ConversationRules {
    /// One visibility check per turn; separators retain preceding hidden-by-pagination history.
    static func transcript(_ turns:[AssistantTurn],visible:(AssistantTurn)->Bool,calendar:Calendar = .current)->[AssistantTranscriptRow] {
        var rows:[AssistantTranscriptRow]=[],previous:AssistantTurn?,previousHuman:AssistantTurn?
        for turn in turns where visible(turn) {
            rows.append(.init(turn:turn,separator:separator(before:turn,previous:previous,previousHuman:previousHuman,calendar:calendar)))
            previous=turn
            if turn.role == "user" {previousHuman=turn}
        }
        return rows
    }
    static func topics(in conversations: [AssistantConversation], registration: String) -> [AssistantConversation] {
        conversations.filter { $0.accountID == registration && $0.reviewKey == nil && $0.isPrimary != true && ($0.isTopic == true || $0.focus != nil) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    /// Empty stored value means explicitly no topic. Legacy chats become modes only if configured.
    static func topicSelection(_ stored: String?, legacy: UUID?, in conversations: [AssistantConversation], registration: String) -> UUID? {
        let candidate: UUID?
        if let stored { candidate = UUID(uuidString:stored) } else { candidate = legacy }
        return topics(in:conversations,registration:registration).first { $0.id == candidate }?.id
    }
    /// Each optional context is a distinct ongoing thread. Tagged messages preserve the previous feed without copying or deleting records.
    static func thread(feed: AssistantConversation, topic: AssistantConversation?) -> [AssistantTurn] {
        let turns = feed.turns.filter { $0.contextID == topic?.id } + (topic?.turns ?? [])
        return turns.enumerated().sorted {
            let lhs = $0.element.created ?? .distantPast, rhs = $1.element.created ?? .distantPast
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
    }
    static func profileThread(feed:AssistantConversation,topic:AssistantConversation?,session:UUID)->[AssistantTurn] {
        thread(feed:feed,topic:topic).filter { $0.profileSessionID == session }
    }
    static func history(feed: AssistantConversation, topic: AssistantConversation?, excludedDeliveries: Set<String> = []) -> [AssistantTurn] {
        let eligible=thread(feed:feed,topic:topic).filter { $0.completed && $0.profileSessionID == nil && ($0.deliveryID.map { !excludedDeliveries.contains($0) } ?? true) }
        // Background deliveries must not evict the actual human conversation.
        let updates=eligible.filter{$0.deliveryID != nil && $0.role != "user"}.suffix(4)
        let dialogue=eligible.filter{$0.deliveryID == nil || $0.role == "user"}.suffix(20-updates.count)
        let ids=Set((Array(dialogue)+Array(updates)).map(\.id))
        return eligible.filter{ids.contains($0.id)}

    }
    static func separator(before turn:AssistantTurn,previous:AssistantTurn?,previousHuman:AssistantTurn?,calendar:Calendar = .current)->String? {
        guard let date=turn.created else { return nil }
        if previous?.created.map({!calendar.isDate($0,inSameDayAs:date)}) ?? true { return date.formatted(date:.abbreviated,time:.omitted) }
        if turn.role == "user",let old=previousHuman?.created,date.timeIntervalSince(old) >= 4*3600 { return "Conversation resumed" }
        return nil
    }
    static func sourceMemoryHistory(_ turns:[AssistantTurn],permitted:Set<UUID>,history:[AssistantTurn]=[])->[AssistantTurn] {
        let byID=Dictionary((history+turns).map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
        var memo:[UUID:Set<UUID>]=[:],visiting=Set<UUID>()
        func dependencies(_ turn:AssistantTurn)->Set<UUID> {
            if let cached=memo[turn.id] {return cached}
            let stored=Set(turn.sourceMemoryIDs ?? [])
            guard !stored.isEmpty,let capture=turn.contextCapture,capture.sourceMemoryDependencyVersion == nil else {return stored}
            // Reconstruct older overcaptured receipts only from exact saved traces,
            // including facts supplied indirectly by earlier assistant replies.
            // Incomplete/cyclic/deep legacy graphs keep their conservative gates.
            guard visiting.count < 64,visiting.insert(turn.id).inserted else {return stored}
            defer {visiting.remove(turn.id)}
            var supplied=Set(capture.memoryIDs+capture.notebookMemoryIDs+capture.consultedMemoryIDs)
            for id in capture.historyTurnIDs {
                guard let prior=byID[id] else {return stored}
                supplied.formUnion(dependencies(prior))
            }
            let result=stored.intersection(supplied);memo[turn.id]=result;return result
        }
        return turns.compactMap { turn in
            let required=dependencies(turn)
            guard required.isSubset(of:permitted) else {return nil}
            var value=turn
            if value.sourceMemoryIDs != nil {value.sourceMemoryIDs=required.sorted()}
            return value
        }
    }
    static let promptByteLimit = 16_000
    static func acceptsPrompt(_ prompt: String) -> Bool {
        guard prompt.utf8.count <= promptByteLimit, let data = try? JSONSerialization.data(withJSONObject:["role":"user","content":prompt]) else { return false }
        return data.count + 2 <= 24_000
    }
    static func utf8Prefix(_ text: String, bytes: Int) -> String {
        var data = Array(text.utf8.prefix(max(0,bytes)))
        while !data.isEmpty {
            if let result = String(bytes:data,encoding:.utf8) { return result }
            data.removeLast()
        }
        return ""
    }
    /// The current human request is intact; only older saved turns may become labelled excerpts.
    static func replay(_ turns: [AssistantTurn], currentUserID: UUID, bytes: Int = 24_000) -> [[String:String]] {
        replayTurns(turns,currentUserID:currentUserID,bytes:bytes).map { ["role":$0.role,"content":$0.content] }
    }
    static func replayTurns(_ turns:[AssistantTurn],currentUserID:UUID,bytes:Int = 24_000)->[AssistantTurn] {
        guard let current = turns.last(where:{ $0.id == currentUserID && $0.role == "user" && $0.completed }) else { return [] }
        let last = ["role":current.role,"content":current.content]
        guard let encoded = try? JSONSerialization.data(withJSONObject:last), encoded.count + 2 <= bytes else { return [] }
        var used=encoded.count+2,selected:[UUID:AssistantTurn]=[:]
        let before=Array(turns.prefix(while:{$0.id != currentUserID}).filter{$0.completed && ["user","assistant"].contains($0.role)}.suffix(19))
        func add(_ turn:AssistantTurn,limit:Int)->Bool {
            guard selected[turn.id] == nil else { return true }
            let content=turn.content.utf8.count > limit ? utf8Prefix(turn.content,bytes:limit)+"\n[Earlier message excerpt; remaining text omitted.]" : turn.content
            let value=["role":turn.role,"content":content]
            guard let data=try? JSONSerialization.data(withJSONObject:value),used+data.count+1 <= bytes else { return false }
            var excerpt=turn;excerpt.content=content;selected[turn.id]=excerpt;used+=data.count+1;return true
        }
        // Preserve a just-delivered proposal for a short human acceptance, then give dialogue priority.
        if let prior=before.last,prior.deliveryID != nil { _ = add(prior,limit:1000) }
        for turn in before.reversed() where turn.deliveryID == nil || turn.role == "user" { if !add(turn,limit:3000) { break } }
        for turn in before.reversed() where turn.deliveryID != nil && turn.role != "user" { _ = add(turn,limit:500) }
        let result=before.compactMap{selected[$0.id]}+[current]
        return result
    }
    static func context(for turn: AssistantTurn, in conversation: AssistantConversation) -> UUID? {
        conversation.isPrimary == true ? turn.contextID : conversation.id
    }
    static func selection(_ preferred: UUID?, in conversations: [AssistantConversation], registration: String) -> UUID? {
        let available = conversations.filter { $0.accountID == registration }
        if let preferred, available.contains(where:{ $0.id == preferred }) { return preferred }
        return available.first(where:{ $0.isPrimary == true })?.id ?? available.sorted { $0.created > $1.created }.first?.id
    }
    static func morningKey(registration: String, day: String) -> String { registration + ":morning:" + day }
    static func hasDelivery(_ conversations: [AssistantConversation], registration: String, key: String) -> Bool {
        conversations.contains { $0.accountID == registration && $0.turns.contains { $0.deliveryID == key } }
    }
}

struct ChatDraftState: Codable {
    var version = 1
    var values: [String:String] = [:]
    var images: [String:[ChatImageAttachment]]? = nil
}
enum ChatDraftRules {
    static func key(registration: String, widget: UUID, conversation: UUID?) -> String { registration + ":" + widget.uuidString + ":" + (conversation?.uuidString ?? "unselected") }
    static func hasDraft(_ state: ChatDraftState, registration: String) -> Bool { state.values.contains { $0.key.hasPrefix(registration+":") && !$0.value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty } }
}

/// Small references only; screenshot bytes are stored separately in private local storage.
struct ChatImageAttachment: Codable, Identifiable, Equatable {
    var id = UUID()
    var registration: String
    var mimeType: String
    var width: Int
    var height: Int
    var byteCount: Int
    var digest: String
}
