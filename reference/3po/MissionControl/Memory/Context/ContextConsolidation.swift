import Foundation
import Observation

@MainActor @Observable final class ContextConsolidationService {
    private(set) var busy = false
    private(set) var ownedHeartbeatRunID: String?
    private(set) var error: String?
    private(set) var status = "Context pages update during a heartbeat when relevant information changes."

    private func mayOfferQuestion(_ model: DashboardModel, registration: String, now: Date = .now) -> Bool {
        guard model.memoryLearning.questionsEnabled, model.contextQuestions.canSave,
              model.visibleContextProjectQuestions().isEmpty,
              !model.memoryLearning.offeredQuestion(registration: registration, on: now) else { return false }
        return !model.contextQuestions.questions(registration: registration, includeFinished: true).contains { BriefingRules.day($0.created) == BriefingRules.day(now) }
    }

    func targets(_ model: DashboardModel, registration: String, eligibleReferences: [String: String]? = nil) -> [ContextPageTarget] {
        let records = model.contextKnowledge(registration: registration, includeTopics: false, retainingReferences: eligibleReferences ?? [:], purpose: .maintenance)
        let memory = model.assistant.memory.permittedRecords.filter { MemoryRules.usable($0, registration: registration) && $0.conversationID == nil }
        let everyday = Set(memory.filter { $0.source == nil && $0.reviewPreference != true && $0.conversationID == nil &&
            ($0.kind == .preference || $0.organisation?.areas.contains(.about) == true) }.map(\.id))
        var result: [ContextPageTarget] = []
        func append(kind: ContextPage.Kind, key: String, title: String, candidates: [ContextKnowledgeRecord],
                    anchorKeys: [String] = [], projectID: UUID? = nil, mayAskPurpose: Bool = false,
                    structuralReferences: [ContextPageReference] = []) {
            let id = ContextPage.stableID(registration: registration, kind: kind, key: key)
            let identity = model.contextPages.identityStatus(id: id, registration: registration)
            guard identity == .missing || identity == .available else { return }
            let old = model.contextPages.page(id: id, registration: registration)
            guard old?.owner != .human,
                  let target = ContextConsolidationSelection.target(registration: registration, kind: kind, key: key,
                    title: title, candidates: candidates, previous: old, anchorKeys: anchorKeys,
                    projectID: projectID, mayAskPurpose: mayAskPurpose, eligibleReferences: eligibleReferences,
                    structuralReferences: structuralReferences) else { return }
            result.append(target)
        }
        let humanOverviewIDs = Set(model.contextPages.pages(registration: registration).filter { $0.owner == .human && $0.kind == .overview }.map(\.id))
        var overview = records.filter { $0.memoryID.map(everyday.contains) == true || ($0.reference.kind == "page" && humanOverviewIDs.contains($0.reference.key)) }
        if overview.isEmpty {
            let human = Set(memory.filter { $0.source == nil && $0.reviewPreference != true }.map(\.id))
            overview = records.filter { $0.memoryID.map(human.contains) == true }
        }
        if overview.isEmpty { overview = records.filter { $0.reference.kind == "project" } }
        append(kind: .overview, key: "maintained", title: "Everyday overview", candidates: overview,
            anchorKeys: overview.filter { $0.reference.kind == "page" }.map { $0.reference.contextKey })
        for area in LifeArea.allCases {
            let selected = records.filter { $0.reference.kind == "memory" && $0.areas.contains(area) }
            append(kind: .topic, key: area.rawValue, title: area.title, candidates: selected)
        }
        let notebook = model.assistant.memory.notebook(registration, includeTopics: false)
        let items = model.assistant.projects.items(registration, includeTopics: false)
        for item in items where !item.kind.isWork {
            let linked = notebook.anchors.first { $0.id == "life:" + item.id.uuidString }?.memoryIDs ?? []
            let children = Set(items.filter { $0.parentID == item.id }.map(\.id)).union([item.id])
            var selected = records.filter { $0.reference.kind == "project" && $0.projectID.map(children.contains) == true }
            selected += records.filter { $0.reference.kind == "projectIdentity" && $0.reference.key == item.id.uuidString }
            selected += records.filter { $0.reference.kind == "page" && $0.projectID == item.id }
            let ancestorIDs = Set(ContextHierarchyRules.ancestors(of: item.id, items: items, maximum: 8).map(\.id))
            let path = records.filter { $0.reference.kind == "project" && ($0.projectID == item.id || $0.projectID.map(ancestorIDs.contains) == true) }
            let inheritedCandidates = records.filter { record in
                (record.reference.kind == "project" && record.projectID.map(ancestorIDs.contains) == true) ||
                (record.reference.kind == "page" && record.projectID.map(ancestorIDs.contains) == true)
            }.map { record in
                var value = record
                value.relevance = "Inherited context of an exact parent space, not a direct assertion about this child. Use it to understand the hierarchy; child-specific human context takes priority. Do not copy the parent's whole purpose as this child's purpose."
                return value
            }
            var inherited: [ContextKnowledgeRecord] = [], inheritedBytes = 0
            for record in inheritedCandidates {
                let bytes = ContextKnowledgeRules.bytePrefix(record.text, maximumBytes: 4000).utf8.count + 200
                guard inheritedBytes + bytes <= 6000 else { continue }
                inherited.append(record); inheritedBytes += bytes
            }
            selected += inherited
            selected += records.filter { $0.memoryID.map(linked.contains) == true }
            selected += records.filter { ContextKnowledgeRules.projectCandidate($0, title: item.title, notes: item.searchableNotes, selfLabel: notebook.selfLabel) }.map {
                var candidate = $0
                candidate.relevance = "Lexically retrieved candidate for this existing project. Verify relevance from its text; a similar name is not a confirmed relationship. Omit unrelated material."
                return candidate
            }
            guard !selected.isEmpty else { continue }
            let meaningfulProject = model.contextProjectQuestionCandidate(item, items: items)
            let purposes = Set(model.contextPages.pages(registration: registration).filter { page in
                page.owner == .human && page.kind == .note && page.key == "project-purpose:" + item.id.uuidString &&
                selected.contains { record in record.reference.kind == "page" && record.reference.key == page.id }
            }.map(\.id))
            let structuralReferences = inherited.isEmpty ? [] : path.map(\.reference)
            let anchors = ["project:" + item.id.uuidString, "projectIdentity:" + item.id.uuidString] + inherited.map { $0.reference.contextKey } +
                selected.filter { $0.reference.kind == "page" && purposes.contains($0.reference.key) }.map { $0.reference.contextKey }
            append(kind: .project, key: item.id.uuidString, title: item.title, candidates: selected, anchorKeys: anchors,
                projectID: item.id, mayAskPurpose: mayOfferQuestion(model, registration: registration) && purposes.isEmpty && meaningfulProject,
                structuralReferences: structuralReferences)
        }
        let updates = records.filter { $0.reference.kind != "projectIdentity" }
        append(kind: .topic, key: "recent", title: "Recent context and recorded changes", candidates: updates)
        let dirty = result.filter { target in
            let current = model.contextPages.page(id: target.id, registration: registration)
            return current == nil || target.hasPendingChanges || !ContextKnowledgeRules.current(current!.references, records: records)
        }
        return ContextConsolidationSelection.ordered(dirty, pages: model.contextPages.pages(registration: registration))
    }

    /// One synthesis per owned heartbeat; all provider calls use that run's persisted allowance.
    /// Existing source-learning quotas/failed claims are unchanged.
    func run(_ model: DashboardModel, request: HeartbeatChildRequest, targetIDs: Set<String>? = nil,
             eligibleReferences: [String: String]? = nil) async throws -> HeartbeatLearningResult {
        try request.validate()
        guard model.contextPages.canSave else {
            return .init(failure: model.contextPages.error ?? "Context-page storage is unavailable.", detail: "Saved context is preserved; maintenance could not start.", skipped: false)
        }
        guard !busy, model.assistant.memory.enabled, model.assistant.memory.learningEnabled,
              !model.assistant.hasDraft, !model.assistant.busy else {
            return .init(detail: "Context-page maintenance is waiting for idle permitted memory.", skipped: true)
        }
        let registration = request.registration
        let all = targets(model, registration: registration, eligibleReferences: eligibleReferences).filter { targetIDs?.contains($0.id) ?? true }
        let capturedRecords = model.contextKnowledge(registration: registration, includeTopics: false, purpose: .maintenance)
        let checkpoint = model.contextPages.checkpoint(registration: registration)
        guard !all.isEmpty else {
            let current = Dictionary(capturedRecords.map { ($0.reference.contextKey, $0.reference) }, uniquingKeysWith: { first, _ in first })
            let retained = (checkpoint?.references ?? []).filter { current[$0.contextKey]?.revision == $0.revision }
            if retained != checkpoint?.references {
                try model.contextPages.saveBatch([], checkpoint: .init(registration: registration, references: retained), expectedCheckpointRevision: checkpoint?.revision)
            }
            status = "Context pages are current; no AI update was needed."
            return .init(detail: status, skipped: true)
        }
        let now = Date.now, timezone = TimeZone.current.identifier
        let selected = ContextConsolidationSelection.batch(all, now: now, timezone: timezone)
        guard !selected.isEmpty else { return .init(failure: "A context page exceeded its bounded input; its changes remain pending.", detail: "Context input remains pending.", skipped: false) }
        let tools = ContextConsolidationRules.tools(selected)
        guard !tools.isEmpty else { return .init(failure: "The bounded context result could not be prepared. Saved pages and changes are retained.", detail: "Context input remains pending.", skipped: false) }
        let selectedModel = model.chatGPT.selectedModel
        let memoryPermission = model.assistant.memory.useRevision
        let learningPermission = model.assistant.memory.controlsRevision
        let expected = Dictionary(selected.compactMap { target in model.contextPages.page(id: target.id, registration: registration).map { (target.id, $0.revision) } }, uniquingKeysWith: { first, _ in first })
        let input = ContextConsolidationSelection.input(selected, now: now, timezone: timezone)
        busy = true; ownedHeartbeatRunID = request.runID; error = nil; status = "Updating relevant context pages…"
        defer { busy = false; ownedHeartbeatRunID = nil }
        do {
            try request.validate(); try request.claim()
            let response = try await model.chatGPT.toolResponse(input: [["role": "user", "content": input]], instructions: ContextConsolidationRules.instructions,
                tools: tools, model: selectedModel, purpose: .learning) { _ in }
            guard response.calls.count == 1, let call = response.calls.first,
                  (call.namespace == "pa" && call.name == ContextConsolidationRules.resultTool) || (call.namespace == nil && call.name == "pa." + ContextConsolidationRules.resultTool) else {
                throw ContextPageFailure.invalid("consolidation result")
            }
            let text = call.arguments
            try Task.checkCancellation(); try request.validate()
            guard registration == model.chatGPT.activeID, model.assistant.memory.enabled, model.assistant.memory.learningEnabled,
                  memoryPermission == model.assistant.memory.useRevision, learningPermission == model.assistant.memory.controlsRevision else { throw MemoryLearningFailure.changed }
            let dependencies = selected.flatMap { $0.references + $0.structuralReferences }
            let current = model.contextKnowledge(registration: registration, includeTopics: false, retainingReferences: Dictionary(dependencies.map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first }), purpose: .maintenance)
            guard selected.allSatisfy({ ContextKnowledgeRules.current($0.references + $0.structuralReferences, records: current) }) else { throw ContextPageFailure.invalid("changed supporting records") }
            let decoded = try ContextConsolidationRules.decode(text, targets: selected)
            // Never acknowledge unprocessed targets or changes that arrived while this call yielded.
            let currentByKey = Dictionary(current.map { ($0.reference.contextKey, $0.reference) }, uniquingKeysWith: { first, _ in first })
            var acknowledged = Dictionary((checkpoint?.references ?? []).filter { currentByKey[$0.contextKey]?.revision == $0.revision }.map { ($0.contextKey, $0) }, uniquingKeysWith: { first, _ in first })
            for reference in selected.flatMap(\.references) { acknowledged[reference.contextKey] = reference }
            let newCheckpoint = ContextPageCheckpoint(registration: registration, references: Array(acknowledged.values))
            let saved = try model.contextPages.saveBatch(decoded.map { $0.0 }, expectedRevisions: expected, checkpoint: newCheckpoint,
                expectedCheckpointRevision: checkpoint?.revision)
            var offered = false
            for (page, question) in decoded where !offered {
                guard mayOfferQuestion(model, registration: registration), let question, let target = selected.first(where: { $0.id == page.id }), let projectID = target.projectID,
                      let identity = current.first(where: { $0.reference.kind == "projectIdentity" && $0.reference.key == projectID.uuidString })?.reference,
                      !model.contextPages.pages(registration: registration).contains(where: { page in
                          page.owner == .human && page.kind == .note && page.key == "project-purpose:" + projectID.uuidString &&
                          current.contains { $0.reference.kind == "page" && $0.reference.key == page.id }
                      }) else { continue }
                offered = try model.contextQuestions.offer(registration: registration, projectID: projectID, identity: identity, question: question) != nil
            }
            let remaining = targets(model, registration: registration, eligibleReferences: eligibleReferences).filter { targetIDs?.contains($0.id) ?? true }
            let pending = remaining.reduce(0) { $0 + $1.pendingReferences.count + $1.remainingPendingCount }
            status = "Updated \(saved.count) context page\(saved.count == 1 ? "" : "s")" +
                (remaining.isEmpty ? "." : "; \(remaining.count) page updates and \(pending) current inputs remain pending.")
            return .init(detail: status, skipped: false)
        } catch {
            self.error = error.localizedDescription
            status = "Context-page update did not finish. Saved pages and pending changes are retained."
            if error is CancellationError { throw error }
            return .init(failure: self.error, detail: status, skipped: false)
        }
    }
}
