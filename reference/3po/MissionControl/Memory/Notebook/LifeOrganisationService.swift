import Foundation
import Observation
import SwiftData

/// Classification of already-saved human facts only. No source scan, fact rewrite or Apple operation.
@MainActor @Observable final class LifeOrganisationService {
    var automatic = true {
        didSet { if !restoringSettings,automatic != oldValue { settings.set(automatic,forKey:"paNotebookOrganisationEnabled"); if !automatic,automaticJob { cancel() } } }
    }
    private let settings: UserDefaults
    @ObservationIgnored private var restoringSettings = true
    private(set) var ownedHeartbeatRunID:String?
    private(set) var busy=false
    private(set) var error:String?
    private(set) var status=""
    private var task:Task<Void,Never>?
    private var automaticJob=false
    func cancelAndWait(heartbeatRunID:String) async {guard ownedHeartbeatRunID == heartbeatRunID else {return};let active=task;active?.cancel();await active?.value}
    private var state=LifeOrganisationState()
    private let container:ModelContainer?
    private var readable=true
    init(container:ModelContainer?,settings:UserDefaults = .standard) {
        self.container=container
        self.settings=settings
        automatic = settings.object(forKey:"paNotebookOrganisationEnabled") as? Bool ?? true
        do {
            if let record = try LocalRecordRepository.read("paLifeOrganisation", container: container) {
                state=try JSONDecoder().decode(LifeOrganisationState.self,from: record)
                guard state.version == 1 else { throw MemoryLearningFailure.invalid }
            }
        } catch { readable=false; self.error="Notebook organisation progress could not be read. Its saved record is preserved." }
        restoringSettings = false
    }
    func summary(_ model:LearningRuntime)->String {
        if busy { return status }
        let registration=model.inference.activeID,records=model.assistant.memory.records.filter{MemoryRules.usable($0,registration:registration,now:model.now()) && $0.source == nil}
        let organised=records.filter{$0.organisation != nil}.count
        if state.accounts[registration]?.paused == true { return "Organisation paused after a stopped or failed attempt. Saved facts are unchanged; Organise memories resumes once." }
        return "\(organised) of \(records.count) human facts organised · unpinned classifications revisited after 30 days · at most 2 small automatic passes per day"
    }
    func check(_ model:LearningRuntime,manual:Bool=false,topic:UUID?=nil) {
        guard (try? model.validateOwnership()) != nil else {return}
        let assistant=model.assistant,memory=assistant.memory,registration=model.inference.activeID
        guard !model.otherWorkBusy(excluding:.organisation),readable,!busy,(manual || automatic),memory.enabled,memory.learningEnabled,!assistant.busy,(manual || !assistant.hasDraft),
              !model.inference.busy,!model.inference.usagePaused,model.inference.inferenceVerified,!model.writing,
              !registration.isEmpty else { return }
        let accountScopes:[UUID?]=[nil]+assistant.topics.sorted{$0.id.uuidString < $1.id.uuidString}.map{Optional($0.id)}
        let requestedScopes:[UUID?]=manual && topic != nil ? [nil,topic] : accountScopes
        let selectedModel=model.inference.selectedModel,enabledAtStart=automatic
        if manual {
            let old=state
            for scope in requestedScopes {
                let key=LifeOrganisationBatch.scope(registration,scope)
                for record in memory.records where record.registration == registration && record.conversationID == scope && record.source == nil && record.organisation?.manual != true {
                    state.scopes[key,default:.init()].inspected.removeValue(forKey:record.id)
                    if record.organisation != nil {
                        if state.scopes[key]?.reconsidered == nil { state.scopes[key]?.reconsidered=[:] }
                        state.scopes[key]?.reconsidered?[record.id] = .distantPast
                    }
                }
            }
            do { try save() } catch { state=old;self.error=error.localizedDescription;return }
        }
        guard LifeOrganisationBatch.allowed(state.accounts[registration] ?? .init(),now:model.now(),manual:manual) else { return }
        guard requestedScopes.contains(where:{ !batch(memory,registration:registration,topic:$0,now:model.now()).isEmpty }) else { return }
        guard model.learningBudget.claim(registration,manual:manual,now:model.now(),lane:.organisation) else { return }
        ownedHeartbeatRunID=model.ownedHeartbeatRunID;automaticJob = !manual;busy=true;error=nil
        task=Task {
            defer { ownedHeartbeatRunID=nil;automaticJob=false;busy=false }
            do {
                var total=0,passes=0
                for _ in 0..<(manual ? 4 : 1) {
                    try model.validateOwnership()
                    guard memory.enabled,memory.learningEnabled,registration == model.inference.activeID,
                          (manual || automatic == enabledAtStart),!assistant.busy else { throw MemoryLearningFailure.changed }
                    guard let scope=requestedScopes.first(where:{ !batch(memory,registration:registration,topic:$0,now:model.now()).isEmpty }) else { break }
                    let records=batch(memory,registration:registration,topic:scope,now:model.now()),memoryControls=memory.controlsRevision
                    let issued=Dictionary(uniqueKeysWithValues:records.map{($0.id,$0)})
                    let key=LifeOrganisationBatch.scope(registration,scope),now=model.now(),old=state
                    var progress=state.accounts[registration] ?? .init()
                    if progress.day != LifeOrganisationBatch.day(now) { progress.day=LifeOrganisationBatch.day(now);progress.attempts=0 }
                    progress.attempts += 1;progress.lastAttempt=now;progress.paused=true;state.accounts[registration]=progress
                    do { try save() } catch { state=old;throw error }
                    status="Organising \(records.count) saved facts…"
                    try model.claimInference()
                    let output=try await model.inference.streamResponse(input:[["role":"user","content":LifeOrganisationRules.input(records)]],instructions:LifeOrganisationRules.instructions,model:selectedModel,purpose:.organisation) { _ in }
                    try model.validateOwnership()
                    guard memoryControls == memory.controlsRevision,memory.enabled,memory.learningEnabled,registration == model.inference.activeID,
                          (manual || automatic == enabledAtStart),!assistant.busy,
                          issued.allSatisfy({id,record in memory.records.contains{$0.id == id && $0 == record && $0.source == nil && $0.organisation?.manual != true && MemoryRules.usable($0,registration:registration,now:model.now())}}) else { throw MemoryLearningFailure.changed }
                    guard let entries=LifeOrganisationRules.decode(output,records:records) else { throw MemoryLearningFailure.invalid }
                    // The issued records were revalidated above without yielding. The store
                    // still merges into current state under its loaded-byte CAS.
                    guard memory.organise(entries,expectedRevision:memory.revision) else { throw MemoryLearningFailure.storage }
                    let before=state
                    if state.scopes[key]?.reconsidered == nil { state.scopes[key,default:.init()].reconsidered=[:] }
                    for record in records {
                        state.scopes[key,default:.init()].inspected[record.id]=record.reviewed
                        state.scopes[key]?.reconsidered?[record.id] = model.now()
                    }
                    state.accounts[registration]?.paused=false
                    do { try save() } catch { state=before;throw error }
                    total += entries.count;passes += 1
                }
                status="Organised \(total) saved facts in \(passes) small \(passes == 1 ? "pass" : "passes"). Original facts and evidence are preserved."
            } catch is CancellationError { error="Organisation stopped. Completed metadata is kept; the interrupted pass remains paused." }
            catch { self.error=error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    private func batch(_ memory:PAMemoryStore,registration:String,topic:UUID?,now:Date)->[PAMemory] {
        LifeOrganisationBatch.records(memory.records,registration:registration,topic:topic,progress:state.scopes[LifeOrganisationBatch.scope(registration,topic)] ?? .init(),now:now)
    }
    private func save() throws {
        guard let container else { throw MemoryLearningFailure.storage }
        try LocalRecordRepository(container: container).save(state, key: "paLifeOrganisation")
    }
}
