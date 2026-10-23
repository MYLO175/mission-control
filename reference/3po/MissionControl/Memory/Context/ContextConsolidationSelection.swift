import Foundation

/// Pure request construction shared by the production service and fictional checks.
/// A prior summary is only a drafting aid beside its original, currently eligible records.
enum ContextConsolidationSelection {
    static let maximumPendingRecords = 20
    static let maximumRecords = 52
    static let maximumTargetBytes = 20_000
    static let maximumBatchBytes = 30_000
    static let maximumTargets = 4

    static func target(registration: String, kind: ContextPage.Kind, key: String, title: String,
                       candidates: [ContextKnowledgeRecord], previous: ContextPage?, anchorKeys: [String] = [],
                       projectID: UUID? = nil, mayAskPurpose: Bool = false,
                       eligibleReferences: [String: String]? = nil, structuralReferences: [ContextPageReference] = []) -> ContextPageTarget? {
        let groups = Dictionary(grouping: candidates, by: { $0.reference.contextKey })
        // An ambiguous current identity is not resolved by array order.
        let current = groups.compactMapValues { rows -> ContextKnowledgeRecord? in
            guard let first = rows.first, !ContextPageTarget.suppliedText(first).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rows.allSatisfy({ $0.reference == first.reference && $0.text == first.text }) else { return nil }
            return first
        }
        guard !current.isEmpty else { return nil }
        let id = ContextPage.stableID(registration: registration, kind: kind, key: key)
        if let previous, previous.id == id, previous.registration == registration, previous.owner != .generated { return nil }
        let old = previous.flatMap { $0.id == id && $0.registration == registration && $0.owner == .generated ? $0 : nil }
        let processed = (old?.processedReferences ?? old?.references ?? []).filter { current[$0.contextKey]?.reference.revision == $0.revision }
        let priorVersions = Dictionary(processed.map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first })
        func pending(_ record: ContextKnowledgeRecord) -> Bool { priorVersions[record.reference.contextKey] != record.reference.revision }
        func chronology(_ lhs: ContextKnowledgeRecord, _ rhs: ContextKnowledgeRecord) -> Bool {
            lhs.date == rhs.date ? lhs.reference.contextKey < rhs.reference.contextKey : lhs.date < rhs.date
        }
        func eligiblePending(_ record: ContextKnowledgeRecord) -> Bool {
            pending(record) && (eligibleReferences.map { $0[record.reference.contextKey] == record.reference.revision } ?? true)
        }
        let allWaiting = current.values.filter(pending).sorted(by: chronology)
        let waiting = allWaiting.filter(eligiblePending)
        var seen = Set<String>()
        let anchors = anchorKeys.compactMap { current[$0] }.filter { seen.insert($0.reference.contextKey).inserted }
        let supportedPrior = old.flatMap { page in
            !page.references.isEmpty && page.references.allSatisfy { current[$0.contextKey]?.reference == $0 || structuralReferences.contains($0) } ? page : nil
        }
        let retained = (supportedPrior?.references ?? old?.references ?? []).compactMap { ref -> ContextKnowledgeRecord? in
            guard let record = current[ref.contextKey], record.reference == ref else { return nil }
            return record
        }.sorted(by: chronology).filter { seen.insert($0.reference.contextKey).inserted }
        let boundedTitle = ContextKnowledgeRules.bytePrefix(String(title.prefix(60)), maximumBytes: ContextPageLimits.maximumTitleBytes)
        var result = ContextPageTarget(registration: registration, kind: kind, key: key,
            title: boundedTitle.isEmpty ? "Project context" : boundedTitle, records: [], projectID: projectID,
            mayAskPurpose: mayAskPurpose, hasPendingChanges: !waiting.isEmpty, processedReferences: processed,
            previousPage: supportedPrior, pendingReferences: [], allPendingReferences: allWaiting.map(\.reference), remainingPendingCount: waiting.count)
        result.structuralReferences = structuralReferences
        let anchorIDs = Set(anchors.map { $0.reference.contextKey })
        let priorIDs = Set(supportedPrior?.references.map(\.contextKey) ?? [])
        var originals = anchors + retained
        var newIDs = Set(originals.filter(eligiblePending).map { $0.reference.contextKey })
        for record in waiting where !originals.contains(where: { $0.reference.contextKey == record.reference.contextKey }) {
            guard newIDs.count < maximumPendingRecords, originals.count < maximumRecords else { break }
            originals.append(record); newIDs.insert(record.reference.contextKey)
        }
        result.records = originals
        func fits(_ candidate: ContextPageTarget) -> Bool {
            var measured = candidate
            measured.pendingReferences = measured.records.filter(eligiblePending).map(\.reference)
            measured.remainingPendingCount = max(0, waiting.count - measured.pendingReferences.count)
            return ContextKnowledgeRules.json(ContextConsolidationRules.targetInputs([measured])[0]).utf8.count <= maximumTargetBytes
        }
        // Remove only excess new input while retaining at least one actual pending version.
        while (result.records.count > maximumRecords || !fits(result)),
              let index = result.records.lastIndex(where: { !anchorIDs.contains($0.reference.contextKey) && !priorIDs.contains($0.reference.contextKey) && eligiblePending($0) }),
              result.records.filter(eligiblePending).count > 1 {
            result.records.remove(at: index)
        }
        if !fits(result) || result.records.count > maximumRecords {
            // A prior page is never supplied without every original supporting record.
            result.previousPage = nil
            while (result.records.count > maximumRecords || !fits(result)),
                  let index = result.records.lastIndex(where: { !anchorIDs.contains($0.reference.contextKey) && !pending($0) }) {
                result.records.remove(at: index)
            }
            while (result.records.count > maximumRecords || !fits(result)),
                  result.records.filter(eligiblePending).count > 1,
                  let index = result.records.lastIndex(where: { !anchorIDs.contains($0.reference.contextKey) && eligiblePending($0) }) {
                result.records.remove(at: index)
            }
        }
        // Reuse space freed by an oversized prior; every successful call advances pending work.
        for record in waiting where !result.records.contains(where: { $0.reference.contextKey == record.reference.contextKey }) {
            guard result.records.count < maximumRecords, result.records.filter(eligiblePending).count < maximumPendingRecords else { break }
            var candidate = result; candidate.records.append(record)
            if fits(candidate) { result = candidate }
        }
        guard !result.records.isEmpty else { return nil }
        result.previousPage = result.supportedPreviousPage
        result.pendingReferences = result.records.filter(eligiblePending).map(\.reference)
        result.remainingPendingCount = max(0, waiting.count - result.pendingReferences.count)
        // If mandatory anchors themselves exceed the bound, batch selection refuses the target;
        // no model claim or false acknowledgement occurs and all changes remain pending.
        return result
    }

    static func ordered(_ targets: [ContextPageTarget], pages: [ContextPage]) -> [ContextPageTarget] {
        let existing = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return targets.sorted { lhs, rhs in
            let initialOverviewA = lhs.kind == .overview && existing[lhs.id] == nil
            let initialOverviewB = rhs.kind == .overview && existing[rhs.id] == nil
            if initialOverviewA != initialOverviewB { return initialOverviewA }
            let a = existing[lhs.id]?.updated ?? .distantPast, b = existing[rhs.id]?.updated ?? .distantPast
            if a != b { return a < b }
            if (lhs.kind == .overview) != (rhs.kind == .overview) { return lhs.kind == .overview }
            return lhs.id < rhs.id
        }
    }

    static func input(_ targets: [ContextPageTarget], now: Date, timezone: String) -> String {
        ContextKnowledgeRules.json(["targets": ContextConsolidationRules.targetInputs(targets), "now": now.ISO8601Format(), "timezone": timezone])
    }

    static func batch(_ targets: [ContextPageTarget], now: Date, timezone: String) -> [ContextPageTarget] {
        var result: [ContextPageTarget] = []
        for target in targets {
            guard result.count < maximumTargets else { break }
            let proposed = result + [target]
            let tools = ContextConsolidationRules.tools(proposed)
            guard !tools.isEmpty, ContextKnowledgeRules.json(ContextConsolidationRules.targetInputs([target])[0]).utf8.count <= maximumTargetBytes,
                  input(proposed, now: now, timezone: timezone).utf8.count + ContextKnowledgeRules.json(tools).utf8.count <= maximumBatchBytes else { continue }
            result.append(target)
        }
        return result
    }
}

/// Finite initial-population work, independent of later arrivals or refreshed anchors.
/// The caller supplies the current eligible targets and their permitted canonical records.
struct ContextPopulationSnapshot {
    private struct Target {
        let registration: String
        let initialRevision: UUID?
        let pending: Set<ContextPageReference>
    }
    private let targets: [String: Target]
    let references: [String: String]

    init(initial: [ContextPageTarget], pages: [ContextPage]) {
        var targets: [String: Target] = [:]
        var references: [String: String] = [:]
        for target in initial {
            let page = pages.first { $0.id == target.id && $0.registration == target.registration && $0.owner == .generated }
            targets[target.id] = Target(registration: target.registration, initialRevision: page?.revision,
                                        pending: Set(target.allPendingReferences))
            for reference in target.allPendingReferences { references[reference.contextKey] = reference.revision }
        }
        self.targets = targets
        self.references = references
    }

    func remaining(current: [ContextPageTarget], records: [ContextKnowledgeRecord],
                   pages: [ContextPage]) -> (targetIDs: Set<String>, workCount: Int) {
        // A changed/withdrawn version retires frozen work; its replacement belongs to a later run.
        let currentReferences = Set(records.map(\.reference))
        var targetIDs = Set<String>(), workCount = 0
        for target in current {
            guard let frozen = targets[target.id], frozen.registration == target.registration,
                  !targetIDs.contains(target.id) else { continue }
            let page = pages.first { $0.id == target.id && $0.registration == frozen.registration && $0.owner == .generated }
            // Legacy pages treated their supporting references as successful input coverage.
            let processed = Set(page?.processedReferences ?? page?.references ?? [])
            let pending = frozen.pending.filter { currentReferences.contains($0) && !processed.contains($0) }.count
            let wroteInitial = page.map { $0.revision != frozen.initialRevision } ?? false
            let count = pending + (wroteInitial ? 0 : 1)
            guard count > 0 else { continue }
            targetIDs.insert(target.id); workCount += count
        }
        return (targetIDs, workCount)
    }
}
