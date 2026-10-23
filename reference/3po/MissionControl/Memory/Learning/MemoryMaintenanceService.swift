import Foundation
import SwiftData
import Observation

/// Semantic maintenance only proposes human review; it never executes memory edits.
@MainActor @Observable final class MemoryMaintenanceService {
    private var state=MemoryReviewState()
    private var readable=true
    private let container:ModelContainer?
    private var task:Task<Void,Never>?
    func cancelAndWait(heartbeatRunID:String) async {guard ownedHeartbeatRunID == heartbeatRunID else {return};let active=task;active?.cancel();await active?.value}
    private(set) var ownedHeartbeatRunID:String?
    private(set) var busy=false
    private(set) var error:String?
    private(set) var status="Review useful human facts for possible duplicates, conflicts or obsolete provisional context."
    private var automaticRegistration:String?
    private var undoID:String?
    private var dismissalDate:Date?
    func undoDate(_ registration:String)->Date? { state.proposals.contains{$0.id == undoID && $0.registration == registration && $0.dismissed} ? dismissalDate : nil }
    init(container:ModelContainer?) {
        self.container=container
        do {
            if let saved = try LocalRecordRepository.read("paMemoryReview", container: container) {
                state=try JSONDecoder().decode(MemoryReviewState.self,from: saved)
                guard state.version == 1 else { throw MemoryLearningFailure.invalid }
            }
        } catch { readable=false;self.error="Saved review data is unreadable and has been preserved." }
    }
    func automatic(_ registration:String)->Bool { readable && state.accounts[registration]?.automatic == true }
    func setAutomatic(_ value:Bool,registration:String) {
        guard readable,!registration.isEmpty,(state.accounts[registration]?.automatic ?? false) != value else { return }
        let prior=state;state.accounts[registration,default:.init()].automatic=value
        do { try save();if !value,automaticRegistration == registration { cancel() } } catch { state=prior;self.error=error.localizedDescription }
    }
    func proposals(_ memory:PAMemoryStore,registration:String)->[MemoryReviewProposal] {
        state.proposals.filter{!$0.dismissed && MemoryReviewRules.current($0,records:memory.records,registration:registration)}.sorted{$0.created > $1.created}
    }
    func dismiss(_ id:String,registration:String) {
        guard let index=state.proposals.firstIndex(where:{$0.id == id && $0.registration == registration}) else { return }
        let prior=state;state.proposals[index].dismissed=true
        do { try save();undoID=id;dismissalDate = .now } catch { state=prior;self.error=error.localizedDescription }
    }
    func undo(_ registration:String) {
        guard let index=state.proposals.firstIndex(where:{$0.id == undoID && $0.registration == registration && $0.dismissed}) else { return }
        let prior=state;state.proposals[index].dismissed=false
        do { try save();undoID=nil;dismissalDate=nil } catch { state=prior;self.error=error.localizedDescription }
    }
    func paused(_ registration:String)->Bool { state.accounts[registration]?.paused == true }
    func check(_ model:LearningRuntime,manual:Bool=false) {
        guard (try? model.validateOwnership()) != nil else {return}
        let memory=model.assistant.memory,registration=model.inference.activeID,progress=state.accounts[registration] ?? .init()
        guard !model.otherWorkBusy(excluding:.maintenance),readable,!busy,!registration.isEmpty,manual || (progress.automatic && !progress.paused && model.now().timeIntervalSince(progress.lastAttempt ?? .distantPast) >= 7*86400),
              memory.enabled,memory.learningEnabled,!model.assistant.busy,!model.assistant.hasDraft,!model.inference.busy,!model.inference.usagePaused,model.inference.inferenceVerified,!model.writing else { return }
        let now=model.now(),records=MemoryReviewRules.batch(memory.records,registration:registration,progress:progress,manual:manual,now:now)
        guard !records.isEmpty,let input=try? MemoryReviewRules.input(records,now:now),model.learningBudget.claim(registration,manual:manual,now:model.now(),lane:.maintenance) else { return }
        let prior=state;state.accounts[registration,default:.init()].paused=true;state.accounts[registration]?.lastAttempt=now
        do { try save() } catch { state=prior;self.error=error.localizedDescription;return }
        let memoryControls=memory.controlsRevision,selectedModel=model.inference.selectedModel
        let issued=Dictionary(uniqueKeysWithValues:records.map{($0.id,$0)})
        ownedHeartbeatRunID=model.ownedHeartbeatRunID;automaticRegistration=manual ? nil : registration;busy=true;error=nil;status="Reviewing \(records.count) human facts; no edits will be made…"
        task=Task {
            defer { ownedHeartbeatRunID=nil;automaticRegistration=nil;busy=false }
            do {
                try model.validateOwnership()
                guard registration == model.inference.activeID,(manual || automatic(registration)),memoryControls == memory.controlsRevision,memory.enabled,memory.learningEnabled,!model.assistant.busy,issued.allSatisfy({id,record in memory.records.contains{$0.id == id && $0 == record && MemoryReviewRules.eligible($0,registration:registration)}}) else { throw MemoryLearningFailure.changed }
                try model.claimInference()
                let output=try await model.inference.streamResponse(input:[["role":"user","content":input]],instructions:MemoryReviewRules.instructions,model:selectedModel,purpose:.organisation) { _ in }
                try model.validateOwnership()
                guard registration == model.inference.activeID,(manual || automatic(registration)),memoryControls == memory.controlsRevision,memory.enabled,memory.learningEnabled,!model.assistant.busy,issued.allSatisfy({id,record in memory.records.contains{$0.id == id && $0 == record && MemoryReviewRules.eligible($0,registration:registration)}}) else { throw MemoryLearningFailure.changed }
                guard let proposals=MemoryReviewRules.decode(output,records:records,registration:registration,now:now) else { throw MemoryLearningFailure.invalid }
                let beforeSave=state
                for proposal in proposals where !state.proposals.contains(where:{$0.id == proposal.id}) { state.proposals.append(proposal) }
                for record in records { state.accounts[registration,default:.init()].inspected[record.id]=MemoryReviewRules.fingerprint(record) }
                let currentIDs=Set(memory.records.filter{$0.registration == registration}.map(\.id))
                let retainedInspection=state.accounts[registration]?.inspected.filter{currentIDs.contains($0.key)} ?? [:]
                state.accounts[registration]?.inspected=retainedInspection
                let retained=Array(state.proposals.filter{$0.registration == registration}.sorted{$0.created > $1.created}.prefix(200))
                state.proposals=state.proposals.filter{$0.registration != registration}+retained
                state.accounts[registration]?.paused=false
                do { try save() } catch { state=beforeSave;throw error }
                status="Reviewed \(records.count) facts; \(proposals.count) possible improvements. Check the evidence before changing a fact."
            } catch { self.error=error.localizedDescription;status="Review paused. Review now explicitly resumes; completed suggestions remain saved." }
        }
    }
    func cancel() { task?.cancel() }
    #if DEBUG
    func seedPreview(_ proposals:[MemoryReviewProposal]) {
        state.proposals=proposals
        do { try save() } catch { self.error=error.localizedDescription }
    }
    #endif
    private func save() throws {
        guard let container else { throw MemoryLearningFailure.storage }
        try LocalRecordRepository(container: container).save(state, key: "paMemoryReview")
    }
}
