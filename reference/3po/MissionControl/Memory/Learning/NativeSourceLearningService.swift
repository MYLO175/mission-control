import Foundation
import Observation
import SwiftData

@MainActor @Observable final class NativeSourceLearningService {
    private(set) var ownedHeartbeatRunID:String?
    private(set) var busy=false
    private(set) var error:String?
    private(set) var revision=UUID()
    private(set) var activeKind:MemorySourceKind?
    private var activeRegistration:String?
    private var permissionRevisions:[String:UUID]=[:]
    private var state=NativeLearningState()
    private var readable=true
    private var task:Task<Void,Never>?
    func cancelAndWait(heartbeatRunID:String) async {guard ownedHeartbeatRunID == heartbeatRunID else {return};let active=task;active?.cancel();await active?.value}
    private let container:ModelContainer?
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let saved = try LocalRecordRepository.read("paNativeSourceLearning", container: container) {
                state=try JSONDecoder().decode(NativeLearningState.self,from: saved)
                guard state.version == 1 else { throw MemoryLearningFailure.invalid }
            }
        } catch { readable=false;self.error="Source-learning settings could not be read. Their saved data is preserved." }
    }
    func enabled(_ kind:MemorySourceKind,registration:String)->Bool { readable && state.scopes[NativeLearningRules.key(registration,kind)]?.enabled == true }
    /// Local pending deltas for working context; never advances learning cursors or revives a failed claim.
    /// Retained IDs are exact supporting versions of an already saved page, rechecked against today's cache.
    func contextItems(_ kind: MemorySourceKind, model: LearningRuntime, retaining: [String: Set<String>] = [:], processed: [String: String] = [:]) -> [NativeLearningItem] {
        guard readable, model.assistant.memory.enabled, model.assistant.contextEnabled,
              permittedKind(kind, model: model), let items = model.nativeLearningItems(kind) else { return [] }
        let original = state.scopes[NativeLearningRules.key(model.inference.activeID, kind)]
        let candidates = NativeLearningRules.contextItems(items: items, progress: model.assistant.memory.learningEnabled ? original : nil,
            processed: processed, retaining: retaining, now: model.now())
        let suppressed = model.assistant.memory.suppressed(model.inference.activeID)
        return candidates.filter { item in
            let evidence = MemorySourceEvidence(identity: item.identity, revision: item.revision, label: item.label,
                quote: String(item.text.prefix(500)), observed: model.now(), sourceDate: item.date)
            return PAMemory.suppressionKey(evidence).map { !suppressed.contains($0) } ?? false
        }
    }
    func permittedKind(_ kind:MemorySourceKind,model:LearningRuntime)->Bool {
        readable && (enabled(kind,registration:model.inference.activeID) || model.permitsReviewLearning(kind))
    }
    func setEnabled(_ value:Bool,kind:MemorySourceKind,model:LearningRuntime) {
        guard readable,NativeLearningRules.kinds.contains(kind),!model.inference.activeID.isEmpty else { return }
        let key=NativeLearningRules.key(model.inference.activeID,kind),prior=state
        var progress=state.scopes[key] ?? .init()
        guard progress.enabled != value else { return }
        progress.enabled=value
        // Every new opt-in starts from what's present, not an automatic historical sweep.
        if value,let items=model.nativeLearningItems(kind) {
            progress=NativeLearningRules.collecting(progress,items:items,now:model.now())
            for item in items { progress.baseline[item.id]=item.revision;progress.pending?.removeValue(forKey:item.id) }
        }
        state.scopes[key]=progress
        do {
            try save();revision=UUID();permissionRevisions[key]=UUID()
            if activeKind == kind,activeRegistration == model.inference.activeID {cancel()}
            error=nil
        } catch { state=prior;self.error=error.localizedDescription }
    }
    func lastAssessment(_ registration:String)->Date {
        NativeLearningRules.kinds.compactMap { kind -> Date? in
            let progress=state.scopes[NativeLearningRules.key(registration,kind)]
            return progress?.enabled == true && progress?.paused != true ? progress?.lastAssessment ?? .distantPast : nil
        }.min() ?? .distantFuture
    }
    func permits(_ record:PAMemory,model:LearningRuntime)->Bool {
        guard record.registration == model.inference.activeID,let kind=record.source?.identity.kind,permittedKind(kind,model:model),let items=model.nativeLearningItems(kind) else { return false }
        return NativeLearningRules.permitted(record,items:items)
    }
    func status(_ kind:MemorySourceKind,model:LearningRuntime)->String {
        guard permittedKind(kind,model:model) else { return "Off · collected data is request context only; it isn't learned into memory." }
        if !model.assistant.memory.enabled || !model.assistant.memory.learningEnabled { return "Opt-in saved; memory use/learning is paused. Existing facts and progress remain saved." }
        if busy && activeKind == kind { return "Assessing a small cached batch…" }
        guard let items=model.nativeLearningItems(kind) else { return "Waiting for fresh, permitted source coverage. Cached or failed reads aren't evidence of completion." }
        let progress=state.scopes[NativeLearningRules.key(model.inference.activeID,kind)] ?? .init()
        if progress.paused { return "Paused after an interrupted attempt or cursor limit. Review once explicitly resumes a bounded pass." }
        let pending=NativeLearningRules.batch(items,progress:progress,manual:false).count
        let assessed=items.filter{progress.assessed[$0.id] == $0.revision}.count
        let baseline=items.filter{progress.baseline[$0.id] == $0.revision && progress.assessed[$0.id] != $0.revision}.count
        return "\(items.count) currently eligible · \(assessed) assessed versions · \(baseline) baseline · \(pending == 8 ? "8 or more" : String(pending)) waiting · \(progress.unavailable ?? 0) waiting versions became unavailable. Missing items are unknown."
    }
    func check(_ model:LearningRuntime,kind requested:MemorySourceKind? = nil,manual:Bool=false) {
        guard (try? model.validateOwnership()) != nil else {return}
        let assistant=model.assistant,memory=assistant.memory,registration=model.inference.activeID
        guard !model.otherWorkBusy(excluding:.nativeSources),readable,!busy,memory.enabled,memory.learningEnabled,assistant.contextEnabled,!assistant.busy,!assistant.hasDraft,!model.writing,
              !model.inference.busy,!model.inference.usagePaused,model.inference.inferenceVerified else { return }
        let kinds=requested.map{[$0]} ?? NativeLearningRules.kinds.sorted { left,right in
            let l=state.scopes[NativeLearningRules.key(registration,left)]?.lastAssessment ?? .distantPast
            let r=state.scopes[NativeLearningRules.key(registration,right)]?.lastAssessment ?? .distantPast
            return l == r ? left.rawValue < right.rawValue : l < r
        }
        for kind in kinds {
            guard permittedKind(kind,model:model),let items=model.nativeLearningItems(kind) else { continue }
            let key=NativeLearningRules.key(registration,kind),original=state.scopes[key] ?? .init()
            guard manual || !original.paused else { continue }
            var progress=NativeLearningRules.collecting(original,items:items,now:model.now())
            let recovered=items.filter{memory.sourceAssessmentDate(NativeLearningRules.receipt(registration,$0)) != nil && progress.assessed[$0.id] != $0.revision}
            if !recovered.isEmpty { progress=NativeLearningRules.completing(progress,items:recovered,now:recovered.compactMap{memory.sourceAssessmentDate(NativeLearningRules.receipt(registration,$0))}.max() ?? model.now()) }
            let prior=state;state.scopes[key]=progress
            do { try save() } catch { state=prior;self.error=error.localizedDescription;return }
            let batch=NativeLearningRules.batch(items,progress:progress,manual:manual)
            guard !batch.isEmpty,manual || !progress.paused else { continue }
            guard model.learningBudget.claim(registration,manual:manual,now:model.now(),lane:.nativeSources) else { return }
            let beforeClaim=state
            var claim=progress;claim.paused=true;state.scopes[key]=claim
            do { try save() } catch { state=beforeClaim;self.error=error.localizedDescription;return }
            let now=model.now()
            let candidates=Array(memory.records.filter { old in batch.contains{NativeLearningRules.replaceable(old,by:$0,registration:registration,now:now)} }.prefix(8))
            let selectedMemory=Array(memory.context(registration,query:batch.map(\.text).joined(separator:" "),now:model.now()).prefix(12))
            let memoryDependencies=MemoryDependencyRules.capture(selectedMemory)
            let existing=selectedMemory.map{["text":String(($0["text"] ?? "").prefix(500)),"certainty":$0["certainty"] ?? "unknown"]}
            let coverage=Self.coverage(kind)
            guard let input=try? NativeLearningRules.input(items:batch,candidates:candidates,existing:existing,coverage:coverage) else { error="The bounded input couldn't be prepared. Review once resumes this paused pass.";return }
            let permissionRevision=permissionRevisions[key],selectedModel=model.inference.selectedModel,contextRevision=assistant.contextRevision,memoryControls=memory.controlsRevision
            let calendars=assistant.excludedCalendars,lists=assistant.excludedLists,accounts=assistant.excludedAccounts
            ownedHeartbeatRunID=model.ownedHeartbeatRunID;busy=true;activeKind=kind;activeRegistration=registration;error=nil
            task=Task {
                defer { ownedHeartbeatRunID=nil;busy=false;activeKind=nil;activeRegistration=nil }
                @MainActor func valid()->Bool {
                    let choicesMatch:Bool
                    switch kind {
                    case .calendar:choicesMatch=calendars == assistant.excludedCalendars
                    case .reminder:choicesMatch=lists == assistant.excludedLists
                    case .mail:choicesMatch=accounts == assistant.excludedAccounts
                    case .whatsapp:choicesMatch=false
                    }
                    guard let current=model.nativeLearningItems(kind) else {return false}
                    let currentMemory=memory.permittedRecords.filter{MemoryRules.usable($0,registration:registration,now:model.now())}.map(MemoryRetrieval.record)
                    return registration == model.inference.activeID && permissionRevision == permissionRevisions[key] && permittedKind(kind,model:model) &&
                    memoryControls == memory.controlsRevision && memory.enabled && memory.learningEnabled && assistant.contextEnabled && contextRevision == assistant.contextRevision &&
                    choicesMatch && MemoryDependencyRules.available(memoryDependencies,records:currentMemory) &&
                    candidates.allSatisfy({old in memory.records.first(where:{$0.id == old.id}) == old && batch.contains{NativeLearningRules.replaceable(old,by:$0,registration:registration,now:model.now())}}) &&
                    !assistant.busy && batch.allSatisfy(current.contains)
                }
                do {
                    try model.validateOwnership();guard valid() else { throw MemoryLearningFailure.changed }
                    try model.claimInference()
                    let output=try await model.inference.streamResponse(input:[["role":"user","content":input]],instructions:NativeLearningRules.instructions+" "+LearningRuntime.inlineSourceOrganisationInstructions,model:selectedModel,purpose:.learning) { _ in }
                    try model.validateOwnership()
                    guard valid(),let facts=NativeLearningRules.decode(output,items:batch,candidates:candidates,registration:registration,now:model.now()),facts.allSatisfy({permits($0,model:model)}) else { throw MemoryLearningFailure.changed }
                    let texts=Dictionary(batch.map{($0.identity,$0.text)},uniquingKeysWith:{first,_ in first})
                    let replacements=Dictionary(candidates.compactMap{old in old.source.map{(old.id,$0)}},uniquingKeysWith:{first,_ in first})
                    // No await follows exact dependency validation. Merge against the
                    // current envelope so unrelated saves survive, retaining store CAS.
                    guard memory.putSources(facts,evidenceTexts:texts,expectedRevision:memory.revision,assessmentIDs:batch.map{NativeLearningRules.receipt(registration,$0)},replacementSources:replacements,now:model.now()) else { throw MemoryLearningFailure.storage }
                    let beforeSave=state;state.scopes[key]=NativeLearningRules.completing(progress,items:batch,now:model.now())
                    do { try save() } catch { state=beforeSave;throw error }
                } catch { self.error=error.localizedDescription }
            }
            return
        }
    }
    static func title(_ kind:MemorySourceKind)->String { switch kind { case .calendar:"Calendar";case .reminder:"Reminders";case .mail:"Mail";case .whatsapp:"WhatsApp" } }
    static func coverage(_ kind:MemorySourceKind)->String { switch kind {
    case .calendar:"Fresh cached 90-day calendar orientation, at most 200 enabled occurrences. Provider IDs and original recurring-occurrence dates distinguish items; ambiguous/missing identities are skipped. No location/notes/history are supplied."
    case .reminder:"Fresh incomplete-reminder cache, at most 200 enabled items. Missing items do not prove completion/deletion. No notes or completed history are supplied."
    case .mail:"At most 200 current cached headers; only matching assessments with exact retained excerpts and a body check within 24 hours. No full bodies, unassessed emails or inferred thread identities."
    case .whatsapp:"Selected chats only."
    } }
    func cancel() { task?.cancel() }
    private func save() throws {
        guard let container else { throw MemoryLearningFailure.storage }
        try LocalRecordRepository(container: container).save(state, key: "paNativeSourceLearning")
    }
}
