import Foundation
import EventKit

/// Pure formatting of unchanged canonical values, never permission or availability.
/// Callers must filter current eligibility before consulting this bounded cache.
@MainActor final class ContextRecordProjectionCache {
    private var owner: String?
    private var memoryRevision: UUID?
    private var projectRevision: UUID?
    private var memories: [UUID: (PAMemory, ContextKnowledgeRecord)] = [:]
    private var projects: [UUID: (LifeItem, [ContextKnowledgeRecord])] = [:]
    #if DEBUG
    private(set) var builds = 0
    #endif
    func prepare(registration: String, memory: UUID, project: UUID) {
        if owner != registration || memoryRevision != memory { memories.removeAll(); memoryRevision=memory }
        if owner != registration || projectRevision != project { projects.removeAll(); projectRevision=project }
        owner=registration
    }
    func memory(_ value: PAMemory, build: () -> ContextKnowledgeRecord) -> ContextKnowledgeRecord {
        if let cached=memories[value.id], cached.0 == value { return cached.1 }
        let record=build()
        if memories.count < 1024 { memories[value.id]=(value,record) }
        #if DEBUG
        builds += 1
        #endif
        return record
    }
    func project(_ value: LifeItem, build: () -> [ContextKnowledgeRecord]) -> [ContextKnowledgeRecord] {
        if let cached=projects[value.id], cached.0 == value { return cached.1 }
        let records=build()
        if projects.count < 1024 { projects[value.id]=(value,records) }
        #if DEBUG
        builds += 1
        #endif
        return records
    }
}

@MainActor extension DashboardModel {
    private var contextCalendarAllowed: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--validate-advice-context"), let contextCalendarAccess { return contextCalendarAccess() }
        #endif
        return EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
    private func contextSourceAllowed(_ kind: MemorySourceKind, accountID: String? = nil, chatID: String? = nil,
                                      purpose: ContextKnowledgePurpose, mailAccounts: Set<String>?, whatsappReady: Bool) -> Bool {
        guard !purpose.humanOnly, assistant.contextEnabled else { return false }
        switch kind {
        case .calendar, .reminder: return true // Exact permitted native projection has already filtered identity/version/source choices.
        case .mail: return emailSummaries.enabled && (accountID.map { mailAccounts?.contains($0) ?? true } ?? true)
        case .whatsapp:
            guard whatsappReady else { return false }
            let access = whatsapp.access(for: chatGPT.activeID)
            guard chatID.map({ access.chats.contains($0) }) ?? true else { return false }
            switch purpose {
            case .brief: return access.briefEnabled
            case .suggestions: return access.enabled && access.includeInSuggestions == true
            case .heartbeatSuggestions: return access.enabled && (access.includeInSuggestions == true || heartbeat.whatsappEnabled)
            case .maintenance, .inspection: return true // Current permitted learning/inspection projection is still required below.
            default: return access.enabled
            }
        }
    }
    private func contextMemoryAllowed(_ memory: PAMemory, purpose: ContextKnowledgePurpose, mailAccounts: Set<String>?, whatsappReady: Bool) -> Bool {
        if purpose.humanOnly { return memory.source == nil }
        return memory.allSourceEvidence.allSatisfy {
            contextSourceAllowed($0.identity.kind, accountID: $0.identity.accountID, chatID: $0.identity.kind == .whatsapp ? $0.identity.containerID : nil,
                                 purpose: purpose, mailAccounts: mailAccounts, whatsappReady: whatsappReady)
        }
    }
    func featureInstruction(_ feature: ContextFeature, registration: String) -> (text: String, reference: ContextPageReference, available: Bool) {
        let id = ContextPage.stableID(registration: registration, kind: .instruction, key: feature.rawValue)
        let identity = contextPages.identityStatus(id: id, registration: registration)
        guard identity == .missing || identity == .available else {
            return ("", .init(kind: "instruction", key: feature.rawValue, revision: identity == .preserved ? "preserved" : "unavailable"), false)
        }
        let saved = contextPages.page(id: id, registration: registration)
        let text = saved?.owner == .human ? saved!.markdown : feature == .assistant ? assistant.preferences : feature.defaultText
        return (text, .init(kind: "instruction", key: feature.rawValue, revision: saved?.revision.uuidString ?? ContextKnowledgeRules.fingerprint(text)), true)
    }
    /// Current eligibility is evaluated before every projection, including after source withdrawal.
    func contextKnowledge(registration: String, topic: UUID? = nil, includeTopics: Bool = true,
                          allowedMemoryIDs: Set<UUID>? = nil, includeRecent: Bool = true, retainingReferences: [String: String] = [:],
                          retainingReferenceVersions: [String: Set<String>] = [:], purpose: ContextKnowledgePurpose = .conversation, mailAccounts: Set<String>? = nil, whatsappReady: Bool = true) -> [ContextKnowledgeRecord] {
        #if DEBUG
        contextKnowledgeBuildCount += 1
        #endif
        guard assistant.memory.enabled, registration == chatGPT.activeID else { return [] }
        contextRecordProjections.prepare(registration:registration,memory:assistant.memory.revision,project:assistant.projects.revision)
        var records: [ContextKnowledgeRecord] = assistant.memory.permittedRecords.filter {
            MemoryRules.usable($0, registration: registration) && MemoryRules.inScope($0, conversationID: topic, includeTopics: includeTopics) &&
            (allowedMemoryIDs?.contains($0.id) ?? true) && contextMemoryAllowed($0, purpose: purpose, mailAccounts: mailAccounts, whatsappReady: whatsappReady)
        }.map { memory in
            contextRecordProjections.memory(memory) { .init(reference: .init(kind: "memory", key: memory.id.uuidString, revision: MemoryDependencyRules.fingerprint(MemoryRetrieval.record(memory))),
                  title: memory.kind.rawValue, text: memory.text, date: memory.sourceDate ?? memory.created,
                  areas: memory.organisation?.areas ?? [], memoryID: memory.id) }
        }
        let items = assistant.projects.items(registration, topic: topic, includeTopics: includeTopics)
        for item in items {
            records += contextRecordProjections.project(item) {
                // Navigation/reorder revisions alone do not require another synthesis.
                let canonical = ContextKnowledgeRules.json(["id": item.id.uuidString, "kind": item.kind.workspaceKind.rawValue,
                    "title": item.title, "notes": item.searchableNotes, "status": item.status.rawValue,
                    "due": item.due ?? "", "parent": item.parentID?.uuidString ?? "", "scope": item.conversationID?.uuidString ?? "shared"])
                let text = ContextKnowledgeRules.projectText(title:item.title,kind:item.kind.workspaceKind.rawValue,notes:item.searchableNotes,status:item.status.rawValue,due:item.due,parent:item.parentID?.uuidString,scope:item.conversationID?.uuidString ?? "shared")
                return [.init(reference: .init(kind: "project", key: item.id.uuidString, revision: ContextKnowledgeRules.fingerprint(canonical)),
                              title: item.title, text: text, date: item.updated, areas: item.areas, projectID: item.id),
                        .init(reference: .init(kind: "projectIdentity", key: item.id.uuidString,
                              revision: ContextKnowledgeRules.fingerprint(registration + ":" + item.id.uuidString + ":" + (item.conversationID?.uuidString ?? "shared"))),
                              title: item.title, text: "Existing human-owned " + item.kind.title, date: item.created, projectID: item.id)]
            }
        }
        if allowedMemoryIDs == nil && includeRecent && purpose.includesWorkingChanges {
            var retained = retainingReferenceVersions
            for ref in contextPages.pages(registration: registration).flatMap({ $0.references + ($0.processedReferences ?? []) }) { retained[ref.contextKey, default: []].insert(ref.revision) }
            for (key, revision) in retainingReferences { retained[key, default: []].insert(revision) }
            let processed = Dictionary((contextPages.checkpoint(registration: registration)?.references ?? []).map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first })
            func retainedVersions(_ prefix: String) -> [String: Set<String>] {
                Dictionary(retained.filter { $0.key.hasPrefix(prefix) }.map { (String($0.key.dropFirst(prefix.count)), $0.value) }, uniquingKeysWith: { $0.union($1) })
            }
            func processedVersions(_ prefix: String) -> [String: String] {
                Dictionary(processed.filter { $0.key.hasPrefix(prefix) }.map { (String($0.key.dropFirst(prefix.count)), $0.value) }, uniquingKeysWith: { first, _ in first })
            }
            let runtime = learningRuntime()
            for kind in NativeLearningRules.kinds {
                let prefix = "native-" + kind.rawValue + ":"
                for item in nativeSourceLearning.contextItems(kind, model: runtime, retaining: retainedVersions(prefix), processed: processedVersions(prefix)) where contextSourceAllowed(kind, accountID: item.identity.accountID, purpose: purpose, mailAccounts: mailAccounts, whatsappReady: whatsappReady) {
                    records.append(.init(reference: .init(kind: "native-" + kind.rawValue, key: item.id, revision: item.revision),
                        title: "Attributed " + kind.rawValue + " update · " + item.label, text: item.text,
                        date: item.changed ?? item.date ?? .distantPast))
                }
            }
            let identity = whatsapp.linkedIdentity
            let identityPrefix = ContextKnowledgeRules.fingerprint(identity) + "."
            let prefix = "whatsapp:" + identityPrefix
            for item in sourceLearning.contextItems(runtime, retaining: retainedVersions(prefix), processed: processedVersions(prefix)) where contextSourceAllowed(.whatsapp, chatID: item.chatID, purpose: purpose, mailAccounts: mailAccounts, whatsappReady: whatsappReady) {
                records.append(.init(reference: .init(kind: "whatsapp", key: identityPrefix + item.id, revision: item.revision),
                    title: "Attributed message · " + item.chatName, text: item.sender + ": " + item.text, date: item.date, whatsappChatID: item.chatID))
            }
        }
        if includeRecent && allowedMemoryIDs == nil && purpose.includesWorkingChanges {
            // Completed human messages only. Imported/quoted contents stay DATA; summaries must not promote commands into facts.
            var suppressedTurns = assistant.memory.suppressed(registration)
            suppressedTurns.formUnion(assistant.memory.records.filter {
                $0.registration == registration && $0.sourceTurnID != nil &&
                ($0.supersededBy != nil || $0.retiredAt != nil || $0.resolved != nil || MemoryRules.needsReview($0))
            }.compactMap(\.sourceTurnID))
            let turns = assistant.conversations.flatMap(\.turns).filter {
                $0.role == "user" && $0.completed && $0.profileControl != true && $0.deliveryID == nil && !suppressedTurns.contains($0.id.uuidString) &&
                (includeTopics || $0.contextID == nil || $0.contextID == topic)
            }.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
            var referencedHuman = Set<String>(), referencedActions = Set<String>()
            for page in contextPages.pages(registration: registration) {
                for reference in page.references + (page.processedReferences ?? []) {
                    if reference.kind == "human" { referencedHuman.insert(reference.key) }
                    if reference.kind == "action" { referencedActions.insert(reference.key) }
                }
            }
            for key in Set(retainingReferences.keys).union(retainingReferenceVersions.keys) {
                if key.hasPrefix("human:") { referencedHuman.insert(String(key.dropFirst(6))) }
                if key.hasPrefix("action:") { referencedActions.insert(String(key.dropFirst(7))) }
            }
            let retainedTurns = Array(turns.prefix(32)) + turns.dropFirst(32).filter { referencedHuman.contains($0.id.uuidString) }
            var seen = Set<UUID>()
            for turn in retainedTurns where seen.insert(turn.id).inserted {
                let text = String(turn.content.prefix(1800))
                records.append(.init(reference: .init(kind: "human", key: turn.id.uuidString, revision: ContextKnowledgeRules.fingerprint(turn.content)),
                                     title: "Recent human conversation", text: text, date: turn.created ?? .distantPast))
            }
            let actions = assistant.conversations.flatMap(\.turns).filter {
                $0.completed && $0.actionResult?.succeeded == true && (includeTopics || $0.contextID == nil || $0.contextID == topic)
            }.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
            let retainedActions = Array(actions.prefix(24)) + actions.dropFirst(24).filter { referencedActions.contains($0.id.uuidString) }
            seen.removeAll()
            for turn in retainedActions where seen.insert(turn.id).inserted {
                let canonical = ContextKnowledgeRules.json(["confirmedActions": turn.actionResult!.confirmedActions, "receipts": turn.actionResult!.receipts] as [String: Any])
                let text = ContextKnowledgeRules.actionText(confirmed:turn.actionResult!.confirmedActions,receipts:turn.actionResult!.receipts)
                records.append(.init(reference: .init(kind: "action", key: turn.id.uuidString, revision: ContextKnowledgeRules.fingerprint(canonical)),
                                     title: "Verified app action (historical outcome)", text: String(text.prefix(2000)), date: turn.created ?? .distantPast))
            }
        }
        // Resolve readable human pages after canonical facts and retained conversation evidence.
        // A fixed point handles explicit page references without depending on saved-ID order.
        var waiting = contextPages.pages(registration: registration).filter { $0.owner == .human && $0.kind != .calendarPurpose && $0.kind != .instruction }
        for _ in 0..<min(32, waiting.count) {
            let ready = waiting.filter { ContextKnowledgeRules.current($0.references, records: records) }
            guard !ready.isEmpty else { break }
            for page in ready {
                records.append(.init(reference: .init(kind: "page", key: page.id, revision: page.revision.uuidString),
                    title: page.title, text: page.markdown, date: page.updated,
                    projectID: page.references.first(where: { $0.kind == "projectIdentity" }).flatMap { UUID(uuidString: $0.key) }))
            }
            let emitted = Set(ready.map(\.id)); waiting.removeAll { emitted.contains($0.id) }
        }
        return records.sorted { $0.reference.contextKey < $1.reference.contextKey }
    }

    func contextPageEligible(_ page: ContextPage, records: [ContextKnowledgeRecord]) -> Bool {
        guard page.registration == chatGPT.activeID, assistant.memory.enabled else { return false }
        if page.kind == .calendarPurpose { return false } // Only supplied alongside current permitted calendar identities.
        if page.kind == .project, !records.contains(where: { $0.reference.kind == "project" && $0.reference.key == page.key }) { return false }
        if page.owner == .generated, page.references.isEmpty { return false }
        return ContextKnowledgeRules.current(page.references, records: records)
    }

    /// Small directory and current changes are computed locally; browsing never creates saved projects/pages.
    func captureContextPages(registration: String, query: String?, topic: UUID? = nil, includeTopics: Bool = true,
                             everyday: Bool = false, pageID requestedPageID: String? = nil, allowedMemoryIDs: Set<UUID>? = nil, pageOffset: Int = 0,
                             purpose: ContextKnowledgePurpose = .conversation, mailAccounts: Set<String>? = nil, whatsappReady: Bool = true, includeSourceChanges: Bool = true) -> AssistantPageContext {
        guard assistant.memory.enabled, registration == chatGPT.activeID else { return .init() }
        let areaKey = requestedPageID.flatMap { value -> String? in
            guard value.hasPrefix("area:") else { return nil }
            let key = String(value.dropFirst(5))
            return ContextTopicRoute.named(key)?.key
        }
        if requestedPageID?.hasPrefix("area:") == true, areaKey == nil {
            return .init(text: ContextKnowledgeRules.json(["unavailable": "This topic route is unknown. Search with a descriptive query and no page ID."]))
        }
        let pageID = areaKey.map { ContextPage.stableID(registration: registration, kind: .topic, key: $0) } ?? requestedPageID
        let pages = contextPages.pages(registration: registration)
        let spaceItems = assistant.projects.items(registration, topic: topic, includeTopics: includeTopics).filter { !$0.kind.isWork }
        if let pageID, areaKey == nil,
           !pages.contains(where: { $0.id == pageID }),
           !spaceItems.contains(where: { ContextPage.stableID(registration: registration, kind: .project, key: $0.id.uuidString) == pageID }),
           !ContextInstructionRoute.all.contains(where: { $0.id == pageID }) {
            return .init(text: ContextKnowledgeRules.json(["unavailable": "This page is missing or outside the current scope. Search with a descriptive query and no page ID."]))
        }
        let records = contextKnowledge(registration: registration, topic: topic, includeTopics: includeTopics, allowedMemoryIDs: allowedMemoryIDs, purpose: purpose, mailAccounts: mailAccounts, whatsappReady: whatsappReady)
        let navigation = everyday ? contextNavigationGuide(registration: registration, items: spaceItems, records: records) : (text: "", references: [ContextPageReference]())
        let visible = pages.filter { $0.kind != .instruction && contextPageEligible($0, records: records) }
        let checkpoint = contextPages.checkpoint(registration: registration)
        let prior = Dictionary((checkpoint?.references ?? []).map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first })
        let selfLabel = assistant.memory.notebook(registration, topic: topic, includeTopics: includeTopics).selfLabel
        let effectiveQuery = query ?? areaKey.flatMap { ContextTopicRoute.named($0)?.title } ?? pageID.flatMap { id in pages.first { $0.id == id }?.title ?? spaceItems.first { ContextPage.stableID(registration: registration, kind: .project, key: $0.id.uuidString) == id }?.title }
        let terms = MemoryRetrieval.queryTerms(effectiveQuery, selfLabel: selfLabel)
        func relevant(_ record: ContextKnowledgeRecord) -> Bool {
            effectiveQuery == nil || !terms.isDisjoint(with: MemoryRetrieval.tokens(record.title + " " + record.text))
        }
        let working = records.filter { purpose.includesWorkingChanges && (includeSourceChanges || ($0.reference.kind != "whatsapp" && !$0.reference.kind.hasPrefix("native-"))) && pageID?.hasPrefix("instructions:") != true && prior[$0.reference.contextKey] != $0.reference.revision && $0.reference.kind != "projectIdentity" && relevant($0) }
            .sorted { $0.date == $1.date ? $0.reference.contextKey < $1.reference.contextKey : $0.date > $1.date }
        var selected = visible.filter { page in
            if let pageID { return page.id == pageID }
            return (everyday && page.kind == .overview) || ContextKnowledgeRules.matches(query, title: page.title, synopsis: page.synopsis + (page.owner == .human ? " " + page.markdown : ""), key: page.key, selfLabel: selfLabel)
        }.sorted { lhs, rhs in
            if everyday && (lhs.kind == .overview) != (rhs.kind == .overview) { return lhs.kind == .overview }
            if lhs.owner != rhs.owner { return lhs.owner == .human }
            return lhs.updated > rhs.updated
        }
        if pageID == nil {
            // Orientation has its own allowance; it cannot crowd every targeted page out.
            let orientation = everyday ? Array(selected.filter { $0.kind == .overview }.prefix(2)) : []
            let orientationIDs = Set(orientation.map(\.id))
            selected = orientation + Array(selected.filter { !orientationIDs.contains($0.id) }.prefix(4))
        }
        var payload: [String: Any] = ["pages": [], "workingChanges": [], "lastConsolidation": checkpoint?.updated.ISO8601Format() ?? "Not yet consolidated",
            "coverage": "Bounded current permitted knowledge. Pages retain exact support. Pending changes are available before heartbeat consolidation. Missing context is unknown. App action receipts describe only verified historical operations, never current external completion."]
        var supplied: [ContextPageReference] = [], suppliedPages: [ContextPage] = []
        var directoryBindings: [String: [ContextPageReference]] = [:]
        let maximumBytes = pageID == nil ? 20_000 - navigation.text.utf8.count : 32_000
        var rows: [[String: String]] = []
        for page in selected {
            let excerpt = ContextKnowledgeRules.excerpt(page.markdown, offset: pageID == nil ? 0 : pageOffset, limit: pageID == nil ? (everyday && page.kind == .overview ? 600 : 1800) : 4000)
            let row = ["id": page.id, "title": page.title, "markdown": excerpt.text, "updated": page.updated.ISO8601Format(), "owner": page.owner.rawValue,
                       "offset": String(pageID == nil ? 0 : pageOffset), "nextOffset": excerpt.next.map(String.init) ?? "end", "totalCharacters": String(excerpt.total)]
            var candidate = payload; candidate["pages"] = rows + [row]
            guard ContextKnowledgeRules.json(candidate).utf8.count <= (pageID == nil ? 12_000 : 24_000) else { continue }
            rows.append(row); supplied += page.references; suppliedPages.append(page)
            if page.owner == .human { supplied.append(.init(kind: "page", key: page.id, revision: page.revision.uuidString)) }
        }
        payload["pages"] = rows
        payload["pageReading"] = "If nextOffset is a number, call read_context_page with that exact page ID and offset to continue. Stored pages are never truncated."
        var changes: [[String: String]] = []
        for record in working.prefix(16) {
            var row = record.input; row["text"] = String(record.text.prefix(900))
            var candidate = payload; candidate["workingChanges"] = changes + [row]
            guard ContextKnowledgeRules.json(candidate).utf8.count <= 15_000 else { continue }
            changes.append(row); supplied.append(record.reference)
        }
        payload["workingChanges"] = changes
        payload["pendingRelevantChangeCount"] = working.count
        let descriptions = contextSpaceDescriptions(registration: registration, items: spaceItems, records: records)
        var scopes = suppliedPages.compactMap { page -> ContextInstructionScope? in
            if page.kind == .project, let id = UUID(uuidString: page.key) { return .space(id) }
            if page.kind == .topic { return .topic(page.key) }
            return nil
        }
        if let areaKey { scopes.append(.topic(areaKey)) }
        if let item = spaceItems.first(where: { ContextPage.stableID(registration: registration, kind: .project, key: $0.id.uuidString) == pageID }) {
            scopes.append(.space(item.id))
            let parentIDs = Set(ContextHierarchyRules.ancestors(of: item.id, items: spaceItems).map(\.id))
            let related = descriptions.filter { parentIDs.contains($0.id) || $0.parentID == item.id }
            var parentRows: [[String: String]] = [], childRows: [[String: String]] = []
            for row in related.sorted(by: { ($0.title, $0.id.uuidString) < ($1.title, $1.id.uuidString) }) {
                let value = ["id": row.pageID, "title": row.title, "description": row.text, "parent": row.parentID?.uuidString ?? "root", "owner": row.human ? "human" : "maintained"]
                guard ContextKnowledgeRules.json(parentRows + childRows + [value]).utf8.count <= 5000 else { continue }
                if parentIDs.contains(row.id) { parentRows.append(value) } else { childRows.append(value) }
                supplied += row.references
            }
            payload["parentSpaces"] = parentRows; payload["subspaces"] = childRows
        }
        // Exact canonical title matches also provide guidance before a first generated page exists.
        if pageID == nil, let effectiveQuery {
            for item in spaceItems {
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, let match = effectiveQuery.range(of: title, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let before = match.lowerBound == effectiveQuery.startIndex ? nil : effectiveQuery[effectiveQuery.index(before: match.lowerBound)]
                let after = match.upperBound == effectiveQuery.endIndex ? nil : effectiveQuery[match.upperBound]
                guard before.map({ !$0.isLetter && !$0.isNumber }) ?? true,
                      after.map({ !$0.isLetter && !$0.isNumber }) ?? true else { continue }
                scopes.append(.space(item.id))
            }
        }
        let scoped = contextGuidance(scopes: scopes, registration: registration, items: spaceItems, records: records)
        if !scoped.rows.isEmpty { payload["scopeInstructions"] = scoped.rows }
        // A compact everyday orientation is a deliberate ordinary-chat contract; source assessments don't receive the whole directory.
        if everyday || (pageID == nil && query == nil) {
            var directory: [(row: [String: String], references: [ContextPageReference])] = visible.map { page in
                let about = page.kind == .project ? "Project context" : page.owner == .human ? "Context written by you" : page.kind == .overview ? "Everyday orientation" : "Topic context"
                let refs = page.owner == .human ? page.references + [.init(kind: "page", key: page.id, revision: page.revision.uuidString)] : records.filter { page.kind == .project && $0.reference.kind == "project" && $0.reference.key == page.key }.map(\.reference)
                // Navigation uses generic labels, never unsupported source summaries.
                return (["id": page.id, "title": page.title, "about": about], refs)
            }
            let existing = Set(visible.map(\.id))
            for item in assistant.projects.items(registration, topic: topic, includeTopics: includeTopics) where !item.kind.isWork {
                let id = ContextPage.stableID(registration: registration, kind: .project, key: item.id.uuidString)
                if !existing.contains(id) {
                    let refs = records.filter { $0.reference.kind == "project" && $0.reference.key == item.id.uuidString }.map(\.reference)
                    directory.append((["id": id, "title": item.title, "about": "Current project/space context"], refs))
                }
            }
            directory += ContextInstructionRoute.all.map { (["id": $0.id, "title": $0.title, "about": $0.about], []) }
            var included: [[String: String]] = []
            for entry in directory.sorted(by: { $0.row["title", default: ""] < $1.row["title", default: ""] }) {
                guard ContextKnowledgeRules.json(included + [entry.row]).utf8.count <= 4000 else { continue }
                included.append(entry.row); supplied += entry.references
                if let id = entry.row["id"] { directoryBindings[id] = entry.references }
            }
            payload["directory"] = included; payload["directoryCount"] = directory.count
        }
        if let pageID {
            if let instruction = pages.first(where: { $0.id == pageID && $0.kind == .instruction }),
               let scope = ContextInstructionScope(key: instruction.key),
               let current = contextScopedInstruction(scope, registration: registration, records: records) {
                let excerpt = ContextKnowledgeRules.excerpt(current.markdown, offset: pageOffset, limit: 4000)
                payload["instructions"] = ["scope": scope.key, "markdown": excerpt.text, "nextOffset": excerpt.next.map(String.init) ?? "end"]
                supplied += current.references + [.init(kind: "page", key: current.id, revision: current.revision.uuidString)]
            }
            else if pageID == "instructions:brief" {
                guard briefings.writingPromptReadable else { return .init(text: ContextKnowledgeRules.json(["unavailable": "Saved brief instructions could not be read. Original data is preserved."])) }
                let prompt = briefings.writingPrompt(registration)
                let excerpt = ContextKnowledgeRules.excerpt(prompt.text, offset: pageOffset, limit: 4000)
                payload["instructions"] = ["purpose": "Brief writing preferences", "markdown": excerpt.text, "nextOffset": excerpt.next.map(String.init) ?? "end", "totalCharacters": String(excerpt.total)]
                supplied.append(.init(kind: "instruction", key: "brief", revision: briefInstructionRevision(registration)))
            }
            else if pageID == "instructions:review" {
                guard emailSummaries.reviewPolicies.readable else { return .init(text: ContextKnowledgeRules.json(["unavailable": "Saved Review guidance could not be read. Original data is preserved."])) }
                var policy = emailSummaries.policy(registration).input
                let excerpt = ContextKnowledgeRules.excerpt(policy["text"] ?? "", offset: pageOffset, limit: 4000)
                policy["text"] = excerpt.text; policy["nextOffset"] = excerpt.next.map(String.init) ?? "end"; policy["totalCharacters"] = String(excerpt.total)
                payload["instructions"] = policy
                supplied.append(.init(kind: "instruction", key: "review", revision: reviewInstructionRevision(registration)))
                let feedback = assistant.memory.reviewPreferences(registration).filter { MemoryRules.inScope($0, conversationID: topic, includeTopics: includeTopics) }
                var feedbackRows: [[String: String]] = []
                for fact in feedback.prefix(12) {
                    let row = ["text": String(fact.text.prefix(900)), "about": fact.reviewContext ?? ""]
                    var candidate = payload; candidate["feedback"] = feedbackRows + [row]
                    guard ContextKnowledgeRules.json(candidate).utf8.count <= maximumBytes - 1000 else { continue }
                    feedbackRows.append(row)
                    supplied.append(.init(kind: "memory", key: fact.id.uuidString, revision: MemoryDependencyRules.fingerprint(MemoryRetrieval.record(fact))))
                }
                payload["feedback"] = feedbackRows; payload["feedbackCount"] = feedback.count
            } else if pageID == "instructions:calendars" { return calendarPurposeCapture(sources: calendarData.sources, registration: registration) }
            else if let feature = ContextFeature(rawValue: String(pageID.dropFirst("instructions:".count))), pageID.hasPrefix("instructions:") {
                guard contextPages.isReadable else { return .init(text: ContextKnowledgeRules.json(["unavailable": "Saved feature instructions could not be read. Original data is preserved."])) }
                let guidance = featureInstruction(feature, registration: registration)
                guard guidance.available else { return .init(text: ContextKnowledgeRules.json(["unavailable": "This saved instruction page needs a compatible version of 3PO. Its original data is preserved."])) }
                let excerpt = ContextKnowledgeRules.excerpt(guidance.text, offset: pageOffset, limit: 4000)
                payload["instructions"] = ["purpose": feature.title, "markdown": excerpt.text, "nextOffset": excerpt.next.map(String.init) ?? "end", "totalCharacters": String(excerpt.total)]
                supplied.append(guidance.reference)
            }
            else if suppliedPages.isEmpty {
                // A not-yet-maintained project can still be opened by its stable directory ID.
                if let item = assistant.projects.items(registration, topic: topic, includeTopics: includeTopics).first(where: { ContextPage.stableID(registration: registration, kind: .project, key: $0.id.uuidString) == pageID }),
                   let record = records.first(where: { $0.reference.kind == "project" && $0.reference.key == item.id.uuidString }) {
                    var row = record.input; row["text"] = String(record.text.prefix(1600))
                    payload["currentProject"] = row; supplied.append(record.reference)
                } else { payload["unavailable"] = "This page is missing, changed or outside current permitted context. Search relevant saved facts or sources." }
            }
        }
        if (everyday || purpose == .conversation) && pageID == nil && contextPages.isReadable {
            var policies: [[String: String]] = []
            for feature in ContextFeature.allCases {
                let guidance = featureInstruction(feature, registration: registration)
                var text = ContextKnowledgeRules.bytePrefix(guidance.text, maximumBytes: 900)
                func row() -> [String: String] {
                    ["feature": feature.rawValue, "markdown": text, "readMore": "instructions:" + feature.rawValue,
                     "partial": String(text.count < guidance.text.count), "available": String(guidance.available)]
                }
                while ContextKnowledgeRules.json(policies + [row()]).utf8.count > 4000 && !text.isEmpty { text = String(text.dropLast(min(64, text.count))) }
                policies.append(row()); supplied.append(guidance.reference)
            }
            payload["featureInstructions"] = policies
        }
        if pageID == nil {
            // Keep orientation and policy available even with large Unicode/escaped notes.
            // Omitted optional rows cannot leave hidden evidence dependencies behind.
            let initialChangeKeys = Set(changes.compactMap { $0["id"] })
            let initialDirectoryReferences: [ContextPageReference] = directoryBindings.values.flatMap { $0 }
            let initialDirectoryKeys = Set(initialDirectoryReferences.map(\.contextKey))
            let initialPageReferences = suppliedPages.flatMap { page in page.references + (page.owner == .human ? [.init(kind: "page", key: page.id, revision: page.revision.uuidString)] : []) }
            let initialPageKeys = Set(initialPageReferences.map(\.contextKey))
            let fixedReferences = supplied.filter { !initialChangeKeys.contains($0.contextKey) && !initialDirectoryKeys.contains($0.contextKey) && !initialPageKeys.contains($0.contextKey) }
            var directory = payload["directory"] as? [[String: String]] ?? []
            func updateRows() {
                payload["pages"] = rows; payload["workingChanges"] = changes
                payload["workingChangesOmittedCount"] = max(0, working.count - changes.count)
                if payload["directory"] != nil { payload["directory"] = directory }
            }
            updateRows()
            while ContextKnowledgeRules.json(payload).utf8.count > maximumBytes && !changes.isEmpty { changes.removeLast(); updateRows() }
            while ContextKnowledgeRules.json(payload).utf8.count > maximumBytes,
                  let index = rows.indices.filter({ rows[$0]["markdown", default: ""].count > 160 }).max(by: { rows[$0]["markdown", default: ""].utf8.count < rows[$1]["markdown", default: ""].utf8.count }) {
                let text = rows[index]["markdown", default: ""]
                let shorter = String(text.prefix(max(160, text.count / 2)))
                rows[index]["markdown"] = shorter
                rows[index]["nextOffset"] = String((Int(rows[index]["offset"] ?? "0") ?? 0) + shorter.count)
                updateRows()
            }
            while ContextKnowledgeRules.json(payload).utf8.count > maximumBytes && !directory.isEmpty { directory.removeLast(); updateRows() }
            while ContextKnowledgeRules.json(payload).utf8.count > maximumBytes && rows.count > 1 { rows.removeLast(); updateRows() }
            let keptPageIDs = Set(rows.compactMap { $0["id"] })
            suppliedPages.removeAll { !keptPageIDs.contains($0.id) }
            let pageReferences = suppliedPages.flatMap { page in page.references + (page.owner == .human ? [.init(kind: "page", key: page.id, revision: page.revision.uuidString)] : []) }
            let keptChangeKeys = Set(changes.compactMap { $0["id"] })
            let changeReferences = working.filter { keptChangeKeys.contains($0.reference.contextKey) }.map(\.reference)
            let directoryReferences = directory.flatMap { directoryBindings[$0["id"] ?? ""] ?? [] }
            supplied = fixedReferences + pageReferences + changeReferences + directoryReferences
        }
        // The final encoded object, including instructions and the directory, has one whole-payload bound.
        if ContextKnowledgeRules.json(payload).utf8.count > maximumBytes {
            payload = ["unavailable": "This context selection exceeded its bounded payload. Request a specific page ID and offset.", "maximumBytes": maximumBytes]
            supplied.removeAll(); suppliedPages.removeAll()
        }
        supplied += navigation.references
        if payload["scopeInstructions"] != nil { supplied += scoped.references }
        if !supplied.isEmpty { supplied.append(.init(kind: "context-purpose", key: purpose.rawValue, revision: "1")) }
        let ids = Set(supplied.map(\.contextKey))
        let selectedRecords = records.filter { ids.contains($0.reference.contextKey) }
        let expected = supplied
        let whatsappPurpose: WhatsAppReadPurpose = purpose == .brief ? .brief : [.suggestions, .manualSuggestions, .heartbeatSuggestions].contains(purpose) ? .suggestions : .conversation
        let whatsappScope = expected.contains { $0.kind == "whatsapp" } ? whatsapp.scope(for: registration, purpose: whatsappPurpose) : nil
        return .init(text: ContextKnowledgeRules.json(payload), pageIDs: suppliedPages.map(\.id),
                     memoryIDs: Set(selectedRecords.compactMap(\.memoryID)), workspaceIDs: Set(selectedRecords.compactMap(\.projectID)), referenceVersions: Dictionary(expected.map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first }), guideText: navigation.text, guideFingerprint: navigation.text.isEmpty ? nil : ContextKnowledgeRules.fingerprint(navigation.text), validate: { [weak self] ignored in
            guard let self, registration == self.chatGPT.activeID, self.assistant.memory.enabled else { return false }
            if let whatsappScope, whatsappScope != self.whatsapp.scope(for: registration, purpose: whatsappPurpose) { return false }
            let ignoredProjects = Set(ignored.filter { $0.hasPrefix("project:") }.map { String($0.dropFirst(8)) })
            let retained = Dictionary(expected.map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first })
            let filtered = expected.filter { ref in
                if ignored.contains(ref.contextKey) { return false }
                if ref.kind != "page", let record = selectedRecords.first(where: { $0.reference.contextKey == ref.contextKey }),
                   let project = record.projectID, ignoredProjects.contains(project.uuidString) { return false }
                return true
            }
            let current = self.contextDependencyVersions(registration: registration, records: self.contextKnowledge(registration: registration, topic: topic, includeTopics: includeTopics, allowedMemoryIDs: allowedMemoryIDs, retainingReferences: retained, purpose: purpose, mailAccounts: mailAccounts, whatsappReady: whatsappReady), ignoring: ignored)
            return filtered.allSatisfy { current[$0.contextKey] == $0.revision }
        })
    }

    func contextKnowledgeAvailable(registration: String, versions: [String: String], ignoring: Set<String> = []) -> Bool {
        guard !versions.isEmpty else { return true }
        guard assistant.memory.enabled, registration == chatGPT.activeID else { return false }
        let capturedPurposes = versions.keys.filter { $0.hasPrefix("context-purpose:") }.compactMap { ContextKnowledgePurpose(rawValue: String($0.dropFirst("context-purpose:".count))) }
        let purposes = capturedPurposes.isEmpty ? [ContextKnowledgePurpose.conversation] : capturedPurposes
        return purposes.allSatisfy { purpose in
            let records = contextKnowledge(registration: registration, retainingReferences: versions, purpose: purpose)
            let current = contextDependencyVersions(registration: registration, records: records, ignoring: ignoring)
            return versions.allSatisfy { ignoring.contains($0.key) || current[$0.key] == $0.value }
        }
    }

    /// Share current evidence only within one synchronous, read-only evaluation. The union
    /// retains every exact supplied version without letting one receipt overwrite another.
    /// Do not await or mutate model state inside body; escaped nonempty checks fail closed.
    func withContextPageAvailability<T>(registration: String, captures: [[String: String]],
                                       _ body: (@escaping ([String: String]?) -> Bool) -> T) -> T {
        var active = true
        defer { active = false }
        var retained: [String: Set<String>] = [:]
        var purposes = Set<ContextKnowledgePurpose>()
        for versions in captures where !versions.isEmpty {
            for (key, revision) in versions { retained[key, default: []].insert(revision) }
            let captured = versions.keys.filter { $0.hasPrefix("context-purpose:") }
                .compactMap { ContextKnowledgePurpose(rawValue: String($0.dropFirst("context-purpose:".count))) }
            purposes.formUnion(captured.isEmpty ? [.conversation] : captured)
        }
        var current: [ContextKnowledgePurpose: [String: String]] = [:]
        if assistant.memory.enabled, registration == chatGPT.activeID {
            for purpose in purposes.sorted(by: { $0.rawValue < $1.rawValue }) {
                let records = contextKnowledge(registration: registration, retainingReferenceVersions: retained, purpose: purpose)
                current[purpose] = contextDependencyVersions(registration: registration, records: records)
            }
        }
        return body { versions in
            ContextPageDependencyRules.available(versions) { versions in
                guard active, self.assistant.memory.enabled, registration == self.chatGPT.activeID else { return false }
                let captured = versions.keys.filter { $0.hasPrefix("context-purpose:") }
                    .compactMap { ContextKnowledgePurpose(rawValue: String($0.dropFirst("context-purpose:".count))) }
                let required = captured.isEmpty ? [.conversation] : captured
                return required.allSatisfy { purpose in
                    guard let projection = current[purpose] else { return false }
                    return versions.allSatisfy { projection[$0.key] == $0.value }
                }
            }
        }
    }

    /// Human edits can make new information relevant to the next assessment. Generated page
    /// maintenance is deliberately absent so summarisation cannot cause an inference loop.
    func humanContextDiscoveryRevision(_ registration: String) -> String {
        guard assistant.memory.enabled else { return "memory-paused" }
        return ContextKnowledgeRules.fingerprint(ContextKnowledgeRules.json(contextPages.pages(registration: registration).filter { $0.owner == .human && $0.kind != .calendarPurpose && $0.kind != .instruction }.map { ["id": $0.id, "revision": $0.revision.uuidString] }))
    }

    func contextReferencesForOwnedChanges(registration: String, keys: Set<String>) -> Set<String> {
        // Supporting project/fact changes can be owned; an independent edit of the human's
        // page body still invalidates the capture and must never be adopted with that support.
        keys
    }

    private func briefInstructionRevision(_ registration: String) -> String {
        let prompt = briefings.writingPrompt(registration)
        return (prompt.revision?.uuidString ?? "default") + ":" + ContextKnowledgeRules.fingerprint(prompt.text)
    }
    private func reviewInstructionRevision(_ registration: String) -> String {
        ContextKnowledgeRules.fingerprint(ContextKnowledgeRules.json(emailSummaries.policy(registration).input))
    }
    private func contextDependencyVersions(registration: String, records: [ContextKnowledgeRecord], ignoring: Set<String> = []) -> [String: String] {
        var current = Dictionary(records.filter { $0.reference.kind != "page" }.map { ($0.reference.contextKey, $0.reference.revision) }, uniquingKeysWith: { first, _ in first })
        // Text versions are independently checked even when this job itself retires support.
        // Build transitive page availability from canonical records, never a self-supporting cycle.
        var waiting = contextPages.pages(registration: registration).filter { $0.owner == .human && $0.kind != .calendarPurpose && $0.kind != .instruction }
        for _ in 0..<min(32, waiting.count) {
            let ready = waiting.filter { page in page.references.allSatisfy { ignoring.contains($0.contextKey) || current[$0.contextKey] == $0.revision } }
            guard !ready.isEmpty else { break }
            for page in ready { current["page:" + page.id] = page.revision.uuidString }
            let emitted = Set(ready.map(\.id)); waiting.removeAll { emitted.contains($0.id) }
        }
        for purpose in ContextKnowledgePurpose.allCases { current["context-purpose:" + purpose.rawValue] = "1" }
        if contextPages.isReadable {
            for feature in ContextFeature.allCases { let guidance = featureInstruction(feature, registration: registration); current[guidance.reference.contextKey] = guidance.reference.revision }
            for page in contextPages.pages(registration: registration) where page.kind == .instruction {
                guard let scope = ContextInstructionScope(key: page.key),
                      contextScopedInstruction(scope, registration: registration, records: records) != nil else { continue }
                current["page:" + page.id] = page.revision.uuidString
            }
        }
        if briefings.writingPromptReadable { current["instruction:brief"] = briefInstructionRevision(registration) }
        if emailSummaries.reviewPolicies.readable { current["instruction:review"] = reviewInstructionRevision(registration) }
        if contextPages.isReadable && assistant.contextEnabled && contextCalendarAllowed {
            for source in calendarData.sources where !assistant.excludedCalendars.contains(source.id) {
                current["calendar-guide:" + source.id] = calendarGuideRevision(source, registration: registration)
            }
        }
        return current
    }

    func contextReferencesForMemoryMutation(registration: String, call: PAFunctionCall) -> Set<String> {
        guard registration == chatGPT.activeID, call.name == "change_memory",
              let arguments = try? PAToolProtocol.arguments(call), let rawID = arguments["id"] as? String,
              let id = UUID(uuidString: rawID), let record = assistant.memory.records.first(where: { $0.id == id && $0.registration == registration }) else { return [] }
        let forgetting = arguments["operation"] as? String == "forget"
        let affected = forgetting ? assistant.memory.versionFamily(id) : [record]
        var keys = Set(affected.map { "memory:" + $0.id.uuidString })
        keys.formUnion(affected.compactMap(\.sourceTurnID).map { "human:" + $0 })
        if forgetting {
            for source in affected.flatMap(\.allSourceEvidence) {
                if source.identity.kind == .whatsapp {
                    let identity = ContextKnowledgeRules.fingerprint(source.identity.linkedIdentity ?? source.identity.accountID)
                    let messageID = SourceContextRules.messageKey(chat: source.identity.containerID, item: source.identity.itemID)
                    keys.insert("whatsapp:" + identity + "." + messageID)
                } else { keys.insert("native-" + source.identity.kind.rawValue + ":" + NativeLearningRules.hash(source.identity)) }
            }
        }
        return keys
    }

    func calendarPageKey(_ source: SourceOption) -> String {
        // Provider IDs carry identity; a cosmetic account-label rename must retain its guide.
        let account = source.providerID.map { "provider:" + $0 } ?? "legacy-label:" + source.account
        return ContextKnowledgeRules.fingerprint(ContextKnowledgeRules.json(["id": source.id, "account": account]))
    }
    private func calendarGuideRevision(_ source: SourceOption, registration: String) -> String {
        let id = ContextPage.stableID(registration: registration, kind: .calendarPurpose, key: calendarPageKey(source))
        let page = contextPages.page(id: id, registration: registration)
        return ContextKnowledgeRules.fingerprint(ContextKnowledgeRules.json(["identity": calendarPageKey(source), "label": source.label, "writable": String(source.writable), "page": page?.revision.uuidString ?? "undescribed"]))
    }
    /// Previously recorded human guidance remains usable without creating a second editable authority.
    /// Generated summaries and source interpretations cannot supply calendar-purpose instructions.
    func calendarHumanGuidance(registration: String) -> [ContextKnowledgeRecord] {
        guard assistant.memory.enabled, assistant.contextEnabled, registration == chatGPT.activeID,
              contextPages.isReadable, contextCalendarAllowed else { return [] }
        let candidates = contextKnowledge(registration: registration, includeTopics: false, includeRecent: false, purpose: .email)
            .filter { ($0.reference.kind == "memory" || $0.reference.kind == "page") &&
                !MemoryRetrieval.tokens($0.text).isDisjoint(with: ["calendar", "calendars"]) }
            .filter { record in
                guard let id = record.memoryID else { return true }
                guard let memory = assistant.memory.records.first(where: { $0.id == id }) else { return false }
                return memory.source == nil && memory.reviewPreference != true && (memory.explicit || memory.certainty == .stated)
            }
            .sorted { ($0.date, $0.reference.contextKey) > ($1.date, $1.reference.contextKey) }
        var selected: [ContextKnowledgeRecord] = []
        for record in candidates where selected.count < 6 {
            guard ContextKnowledgeRules.json((selected + [record]).map(\.input)).utf8.count <= 3500 else { continue }
            selected.append(record)
        }
        return selected
    }
    func calendarPurposeCapture(sources: [SourceOption], registration: String) -> AssistantPageContext {
        guard assistant.memory.enabled, assistant.contextEnabled, registration == chatGPT.activeID,
              contextCalendarAllowed else { return .init() }
        guard contextPages.isReadable else { return .init(text: ContextKnowledgeRules.json(["unavailable": "Saved calendar guidance could not be read. Original data is preserved."])) }
        let enabled = sources.filter { !assistant.excludedCalendars.contains($0.id) }
        let guidance = calendarHumanGuidance(registration: registration)
        let guidanceVersions = Dictionary(guidance.map { ($0.reference.contextKey, $0.reference.revision) }, uniquingKeysWith: { first, _ in first })
        var rows: [[String: Any]] = []
        var captured: [SourceOption] = []
        var versions = guidanceVersions
        func payload(_ calendars: [[String: Any]]) -> [String: Any] {
            ["calendars": calendars, "humanGuidance": guidance.map(\.input), "omittedCount": enabled.count - calendars.count,
             "coverage": "Bounded human calendar-purpose guidance with exact current account/provider identities. Existing humanGuidance and individual purpose notes guide destination choice; never infer purpose from a name alone. Truncated guidance may be incomplete: clarify rather than invent exceptions. Guidance never authorises a new action. Missing or ambiguous purpose uses a useful clarification or the ordinary default."]
        }
        for source in enabled.prefix(60) {
            let id = ContextPage.stableID(registration: registration, kind: .calendarPurpose, key: calendarPageKey(source))
            let page = contextPages.page(id: id, registration: registration)
            let purpose = page?.owner == .human ? page!.markdown : "Not described"
            let row: [String: Any] = ["id": source.id, "label": source.label, "account": source.account, "providerID": source.providerID ?? "", "writable": source.writable, "purpose": String(purpose.prefix(1200)), "purposeTruncated": purpose.count > 1200]
            guard ContextKnowledgeRules.json(payload(rows + [row])).utf8.count <= 20_000 else { continue }
            rows.append(row)
            captured.append(source); versions["calendar-guide:" + source.id] = calendarGuideRevision(source, registration: registration)
        }
        let expected = versions
        let supplied = captured
        return .init(text: ContextKnowledgeRules.json(payload(rows)), referenceVersions: versions, validate: { [weak self] _ in
            guard let self, self.assistant.memory.enabled, self.assistant.contextEnabled, self.chatGPT.activeID == registration,
                  self.contextPages.isReadable, self.contextCalendarAllowed,
                  self.contextKnowledgeAvailable(registration: registration, versions: guidanceVersions) else { return false }
            return supplied.allSatisfy { source in
                guard !self.assistant.excludedCalendars.contains(source.id) else { return false }
                // A native tool may have freshly issued a calendar before the widget cache mounts.
                // When the cache knows that ID its account/provider/label must still agree.
                let current = self.calendarData.sources.first { $0.id == source.id } ?? source
                return expected["calendar-guide:" + source.id] == self.calendarGuideRevision(current, registration: registration)
            }
        })
    }
}
