import Foundation
import Observation
import SwiftData

@MainActor @Observable final class SourceContextLearningService {
    private(set) var ownedHeartbeatRunID:String?
    private(set) var busy=false
    private(set) var error:String?
    private var task:Task<Void,Never>?
    func cancelAndWait(heartbeatRunID:String) async {guard ownedHeartbeatRunID == heartbeatRunID else {return};let active=task;active?.cancel();await active?.value}
    private var state=SourceContextState()
    private let container:ModelContainer?
    private var readable=true
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let saved = try LocalRecordRepository.read("paSourceContextLearning", container: container) {
                state=try JSONDecoder().decode(SourceContextState.self,from: saved)
                guard state.version == 1 else { throw MemoryLearningFailure.invalid }
                guard let migrated=state.protectingScopeKeys() else { throw MemoryLearningFailure.invalid }
                state.scopes=migrated
            }
        } catch { readable=false;self.error="Source-learning progress could not be read; its saved record is preserved." }
    }
    private func key(_ scope:WhatsAppSourceScope)->String { SourceContextRules.scopeKey(scope.registration+":"+scope.linkedIdentity) }
    /// Already received permitted changes only. No history read, claim recovery or cursor mutation.
    func contextItems(_ model: LearningRuntime, retaining: [String: Set<String>] = [:], processed: [String: String] = [:]) -> [SourceContextMessage] {
        let scope = model.whatsapp.scope(for: model.inference.activeID)
        let access = accessSnapshot(model)
        guard readable, model.assistant.memory.enabled, access.permitted, !scope.linkedIdentity.isEmpty else { return [] }
        let recent = SourceContextRules.recent(model.whatsapp.messages, chats: model.whatsapp.chats,
            allowed: model.whatsappLearningAccess.chats, now: model.now(), limit: 2000, retaining: retaining)
        let original = state.scopes[key(scope)]
        let candidates = SourceContextRules.contextItems(recent: recent, progress: model.assistant.memory.learningEnabled ? original : nil,
            access: access, processed: processed, retaining: retaining, now: model.now())
        let suppressed = model.assistant.memory.suppressed(model.inference.activeID)
        return candidates.filter { item in
            let evidence = MemorySourceEvidence(identity: .init(kind: .whatsapp, accountID: scope.linkedIdentity,
                containerID: item.chatID, itemID: item.itemID, linkedIdentity: scope.linkedIdentity), revision: item.revision,
                label: item.chatName, quote: String(item.text.prefix(500)), observed: model.now(), sourceDate: item.date)
            return PAMemory.suppressionKey(evidence).map { !suppressed.contains($0) } ?? false
        }
    }
    private func accessSnapshot(_ model:LearningRuntime)->SourceContextLearningAccess {
        let access=model.whatsappLearningAccess
        return .init(permitted:model.assistant.contextEnabled && access.enabled && access.learnContext == true && !access.chats.isEmpty,chats:Set(access.chats.map(SourceContextRules.chatKey)),revision:access.learningAccessRevision,reviewRevision:model.whatsappReviewLearningRevision)
    }
    func lastAssessment(_ model:LearningRuntime)->Date {
        let scope=model.whatsapp.scope(for:model.inference.activeID),access=model.whatsappLearningAccess
        guard access.enabled,access.learnContext == true,state.scopes[key(scope)]?.paused != true else { return .distantFuture }
        return state.scopes[key(scope)]?.coverage?.lastAssessment ?? .distantPast
    }
    func status(_ model:LearningRuntime)->String {
        if busy { return "Learning from a small recent WhatsApp batch…" }
        let scope=model.whatsapp.scope(for:model.inference.activeID),access=model.whatsappLearningAccess
        if !access.enabled || access.learnContext != true { return "WhatsApp context learning is off. Enable it separately in WhatsApp → PA chat access." }
        if state.scopes[key(scope)]?.paused == true { return "Source learning paused after an interrupted or failed attempt. Check recent context resumes once." }
        let progress=state.scopes[key(scope)],coverage=progress?.coverage
        let pending=coverage?.pending.count ?? 0
        let assessed=coverage == nil ? 0 : progress?.seen.count ?? 0
        let baseline=coverage?.baseline.count ?? progress?.seen.count ?? 0
        var text="Selected chats · last 48 hours · \(pending) waiting · \(assessed) assessed versions · at most 8 per pass"
        if baseline > 0 { text += " · \(baseline) older cursor versions retained without verified assessment" }
        if let unavailable=coverage?.unavailable,unavailable > 0 { text += " · \(unavailable) waiting versions left the available window" }
        return text + ". Partial coverage; collection does not mean the AI has read everything. Shared learning budget: 4 automatic passes/day."
    }
    func check(_ model:LearningRuntime,manual:Bool=false) {
        guard (try? model.validateOwnership()) != nil else {return}
        let assistant=model.assistant,memory=assistant.memory,registration=model.inference.activeID
        let scope=model.whatsapp.scope(for:registration),access=model.whatsappLearningAccess
        guard readable,!busy,!registration.isEmpty,!scope.linkedIdentity.isEmpty else {return}
        let scopeKey=key(scope),savedProgress=state.scopes[scopeKey] ?? .init()
        let learningAccess=accessSnapshot(model)
        if !learningAccess.permitted {
            guard savedProgress.learningAccess != learningAccess else {return}
            let prior=state;var progress=savedProgress;progress.learningAccess=learningAccess;state.scopes[scopeKey]=progress
            do {try save()} catch {state=prior;self.error=error.localizedDescription}
            return
        }
        guard !model.otherWorkBusy(excluding:.whatsapp),
              memory.enabled,memory.learningEnabled,assistant.contextEnabled,!assistant.busy,!assistant.hasDraft,!model.writing,
              !model.inference.busy,!model.inference.usagePaused,model.inference.inferenceVerified else { return }
        let recent=SourceContextRules.recent(model.whatsapp.messages,chats:model.whatsapp.chats,allowed:access.chats,now:model.now(),limit:2000)
        var progress=SourceContextRules.collecting(savedProgress,recent:recent,now:model.now())
        progress=SourceContextRules.reconcilingAccess(progress,previous:savedProgress,current:learningAccess,recent:recent)
        if savedProgress.paused && !manual {
            let prior=state;state.scopes[scopeKey]=progress
            do {try save()} catch {state=prior;self.error=error.localizedDescription}
            return
        }
        let recovered=recent.filter{memory.sourceAssessmentDate(SourceContextRules.assessmentKey(registration:registration,linkedIdentity:scope.linkedIdentity,message:$0)) != nil && progress.seen[$0.id] != $0.revision}
        if !recovered.isEmpty {
            let date=recovered.compactMap{memory.sourceAssessmentDate(SourceContextRules.assessmentKey(registration:registration,linkedIdentity:scope.linkedIdentity,message:$0))}.max() ?? model.now()
            progress=SourceContextRules.completing(progress,batch:recovered,now:date)
        }
        let collected=state;state.scopes[scopeKey]=progress
        do { try save() } catch { state=collected;self.error=error.localizedDescription;return }
        let batch=SourceContextRules.batch(recent,progress:progress,manual:manual)
        guard !batch.isEmpty,model.learningBudget.claim(registration,manual:manual,now:model.now(),lane:.whatsapp) else { return }
        let previous=state
        var claim=progress;claim.paused=true;state.scopes[scopeKey]=claim
        do { try save() } catch { state=previous;self.error=error.localizedDescription;return }
        let selectedModel=model.inference.selectedModel
        let sourcesEnabled=assistant.contextEnabled,contextRevision=assistant.contextRevision,memoryControls=memory.controlsRevision
        let selectedMemory=Array(memory.context(registration,query:batch.map(\.text).joined(separator:" "),now:model.now()).prefix(12))
        let existing=selectedMemory.map{["text":String(($0["text"] ?? "").prefix(500)),"certainty":$0["certainty"] ?? "unknown"]}
        let chats=Set(batch.map(\.chatID)),terms=MemoryRetrieval.tokens(batch.map(\.text).joined(separator:" "))
        let candidates=memory.permittedRecords.filter { record in
            MemoryRules.usable(record,registration:registration,now:model.now()) && !record.explicit && record.sourceTurnID == nil && record.organisation?.manual != true &&
            record.source?.identity.kind == .whatsapp && record.source?.identity.linkedIdentity == scope.linkedIdentity && record.source.map{chats.contains($0.identity.containerID)} == true
        }.sorted { a,b in
            let left=MemoryRetrieval.tokens(a.text).intersection(terms).count,right=MemoryRetrieval.tokens(b.text).intersection(terms).count
            return left == right ? a.reviewed > b.reviewed : left > right
        }
        guard let assessment=SourceContextRules.prepare(batch,recent:recent,existing:existing,candidates:candidates) else { self.error="This source batch exceeded its bounded context window; progress is preserved.";return }
        // The bounded input builder may trim the tail of existingMemory. Retain
        // receipts for exactly the supplied prefix before its IDs are shortened away.
        guard let input=try? JSONSerialization.jsonObject(with:Data(assessment.input.utf8)) as? [String:Any],let supplied=input["existingMemory"] as? [[String:String]],supplied.count <= selectedMemory.count else {self.error="The bounded memory context couldn't be verified; progress is preserved.";return}
        let memoryDependencies=MemoryDependencyRules.capture(Array(selectedMemory.prefix(supplied.count)))
        ownedHeartbeatRunID=model.ownedHeartbeatRunID;busy=true;error=nil
        task=Task {
            defer { ownedHeartbeatRunID=nil;busy=false }
            @MainActor func memoryCurrent()->Bool {
                let current=memory.permittedRecords.filter{MemoryRules.usable($0,registration:registration,now:model.now())}
                return MemoryDependencyRules.available(memoryDependencies,records:current.map(MemoryRetrieval.record)) && assessment.candidates.allSatisfy {old in
                    current.first(where:{$0.id == old.id}) == old && memory.sourceIsPermitted(old)
                }
            }
            do {
                try model.validateOwnership()
                guard scope == model.whatsapp.scope(for:model.inference.activeID),access == model.whatsappLearningAccess,learningAccess == accessSnapshot(model),registration == model.inference.activeID,memoryCurrent(),
                      memoryControls == memory.controlsRevision,memory.enabled,memory.learningEnabled,assistant.contextEnabled,contextRevision == assistant.contextRevision,!assistant.busy else { throw MemoryLearningFailure.changed }
                try model.claimInference()
                let output=try await model.inference.streamResponse(input:[["role":"user","content":assessment.input]],instructions:SourceContextRules.instructions+" "+LearningRuntime.inlineSourceOrganisationInstructions,model:selectedModel,purpose:.learning) { _ in }
                try model.validateOwnership()
                guard scope == model.whatsapp.scope(for:model.inference.activeID),access == model.whatsappLearningAccess,learningAccess == accessSnapshot(model),registration == model.inference.activeID,
                      memoryControls == memory.controlsRevision,memoryCurrent(),memory.enabled,memory.learningEnabled,
                      sourcesEnabled == assistant.contextEnabled,assistant.contextEnabled,contextRevision == assistant.contextRevision,!assistant.busy else { throw MemoryLearningFailure.changed }
                let fresh=SourceContextRules.recent(model.whatsapp.messages,chats:model.whatsapp.chats,allowed:access.chats,now:model.now(),limit:2000)
                guard assessment.messages.allSatisfy({item in fresh.contains(where:{$0 == item})}),assessment.candidates.allSatisfy(memory.sourceIsPermitted),
                      let facts=SourceContextRules.decode(output,messages:assessment.messages,registration:registration,linkedIdentity:scope.linkedIdentity,now:model.now(),candidates:assessment.candidates,assessing:Set(batch.map(\.id))),
                      facts.allSatisfy({SourceContextRules.permitted($0,access:access,linkedIdentity:scope.linkedIdentity,messages:model.whatsapp.messages)}) else { throw MemoryLearningFailure.invalid }
                let quotes=Dictionary(facts.flatMap(\.allSourceEvidence).compactMap{evidence in model.whatsapp.messages.first(where:{$0.id == evidence.identity.itemID && $0.chat == evidence.identity.containerID}).map{(evidence.identity,$0.text)}},uniquingKeysWith:{first,_ in first})
                let receipts=batch.map{SourceContextRules.assessmentKey(registration:registration,linkedIdentity:scope.linkedIdentity,message:$0)}
                // Exact inputs remain current; synchronously merge into the latest
                // envelope with the existing compare-and-save protection intact.
                guard memory.putSources(facts,evidenceTexts:quotes,expectedRevision:memory.revision,assessmentIDs:receipts,now:model.now()) else { throw MemoryLearningFailure.storage }
                let old=state
                state.scopes[scopeKey]=SourceContextRules.completing(progress,batch:batch,now:model.now())
                do { try save() } catch { state=old;throw error }
            } catch { self.error=error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    private func save() throws {
        guard let container else { throw MemoryLearningFailure.storage }
        try LocalRecordRepository(container: container).save(state, key: "paSourceContextLearning")
    }
}
