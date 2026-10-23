import Foundation
import SwiftData

@MainActor private final class FictionalWriter: NativeActionWriting {
    var attempts = 0
    var fail = false
    var failBeforeSave = false
    var afterPreSaveFailure: (() -> Void)?
    var afterApply: (() -> Void)?
    var resultUndoToken: String?
    func applyTool(_ draft: ActionDraft, reminder: TaskItem?, event: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>, expectedDetails: NativeEditDetails?, valid: NativeWriteValidity?) async throws -> ActionResult {
        attempts += 1
        if failBeforeSave { afterPreSaveFailure?(); throw NativePreSaveFailure(message:"Fictional target changed before saving") }
        if fail { throw ActionFailure.message("Fictional uncertain native outcome") }
        afterApply?()
        return .init(message:"Fictional verified action",undoToken:resultUndoToken,itemID:"fictional-native-item")
    }
    func deleteItem(baseline: NativeEditDetails, scope: NativeChangeScope, valid: NativeWriteValidity?, claim: NativeWriteClaim?) async throws -> String { attempts += 1;return "Fictional deletion" }
}
@MainActor private final class FictionalRuntime: NativeActionRuntime {
    let writer = FictionalWriter()
    var actionRegistration = "fixture"
    var actionContextEnabled = true
    var actionAssistantBusy = false
    var actionExcludedCalendars: Set<String> = []
    var actionExcludedLists: Set<String> = []
    var nativeActionWriter: any NativeActionWriting { writer }
    var writing = false
    var undoToken: String?
    var undoTitle = ""
    var refreshes = 0
    var feedbacks = 0
    func clearNativeEditUndo() {}
    func recordAssistantEditUndo(_ receipt: NativeEditUndo) {}
    func showFeedback(_ text: String) { feedbacks += 1 }
    func refresh(retryMail: Bool) { refreshes += 1 }
}
@main struct ActionReceiptChecks {
    @MainActor static func main() async throws {
        enum Injected: Error { case failure }
        func check(_ value: Bool) { precondition(value) }
        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ownershipContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let ownerA=ActionReceiptStore(container:ownershipContainer),ownerB=ActionReceiptStore(container:ownershipContainer)
        let ownerTurn=UUID()
        try ownerA.begin("owner-A",turnID:ownerTurn,registration:"owner")
        do {try ownerB.begin("owner-B",turnID:UUID(),registration:"owner");check(false)}
        catch LocalRecordFailure.changed {}
        let ownershipReload=ActionReceiptStore(container:ownershipContainer)
        check(Set(ownershipReload.entries.keys) == ["owner-A"] && ownershipReload.summary(registration:"owner",turnID:ownerTurn).pending == 1)
        let repository = LocalRecordRepository(container: container)
        var fail = true
        let injected = LocalRecordRepository(container: container) { _ in if fail { throw Injected.failure } }
        let ledger = ActionReceiptStore(container: container, repository: injected)
        var nativeAttempts = 0
        do { try ledger.begin("fictional-request"); nativeAttempts += 1; check(false) }
        catch Injected.failure { }
        check(nativeAttempts == 0 && ledger.entries.isEmpty)
        try repository.save("Other owner", key: "unrelated")
        let reopened = ActionReceiptStore(container: container)
        check(reopened.entries.isEmpty)
        fail = false
        try ledger.begin("fictional-request")
        check(ledger.entries.count == 1 && ledger.entries["fictional-request"]?.result == nil)
        let uncertain = ActionReceiptStore(container: container)
        do { try uncertain.begin("fictional-request"); check(false) }
        catch { check(uncertain.entries.count == 1) }
        ledger.entries["fictional-request"]?.result = "Native save verified"
        fail = true
        do { try ledger.save(); check(false) } catch Injected.failure { }
        let afterFailedCompletion = ActionReceiptStore(container: container)
        check(afterFailedCompletion.entries["fictional-request"]?.result == nil)
        do { try afterFailedCompletion.begin("fictional-request"); check(false) } catch { }
        fail = false; try ledger.save()
        let completed = ActionReceiptStore(container: container)
        check(completed.entries["fictional-request"]?.result == "Native save verified")
        let ownedTurn = UUID()
        try completed.begin("owned-request", turnID: ownedTurn, registration: "owner-a")
        check(completed.entries["owned-request"]?.turnID == ownedTurn && completed.entries["owned-request"]?.registration == "owner-a")
        check(completed.summary(registration:"owner-a",turnID:ownedTurn).pending == 1)
        check(completed.summary(registration:"owner-b",turnID:ownedTurn).pending == 0)
        check(completed.summary(registration:"owner-a",turnID:UUID()).pending == 0)
        completed.entries["owned-request"]?.result = "Dirty unsaved result"
        check(completed.summary(registration:"owner-a",turnID:ownedTurn).confirmed == 0 && completed.summary(registration:"owner-a",turnID:ownedTurn).pending == 1)
        completed.entries["owned-request"]?.result = nil
        try completed.complete("owned-request", result:"Confirmed owned save",itemID:"owned-exact-item")
        check(completed.summary(registration:"owner-a",turnID:ownedTurn).confirmed == 1 && completed.summary(registration:"owner-a",turnID:ownedTurn).pending == 0)
        check(completed.entries["fictional-request"]?.turnID == nil && completed.entries["fictional-request"]?.registration == nil)
        completed.entries["owned-request"]?.undone = true; try completed.save()
        check(completed.summary(registration:"owner-a",turnID:ownedTurn).confirmed == 0)
        completed.entries["fictional-request"]?.undone = true; try completed.save()
        try completed.begin("fictional-request")
        check(completed.entries["fictional-request"]?.undone == nil)
        try repository.write(["assistantActionLedger": Data("unreadable original".utf8)])
        let bad = ActionReceiptStore(container: container)
        check(!bad.readable)
        check(!bad.summary(registration:"owner-a",turnID:ownedTurn).readable)
        do { try bad.begin("new"); check(false) } catch { }
        try check(repository.read("assistantActionLedger") == Data("unreadable original".utf8))
        let actionContainer = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let actionRepository = LocalRecordRepository(container:actionContainer)
        var failActionSave = true
        let actionFailure = LocalRecordRepository(container:actionContainer) { _ in if failActionSave {throw Injected.failure} }
        let actions = AssistantActions(container:actionContainer,repository:actionFailure)
        let runtime = FictionalRuntime(), request = UUID(), human = "Create a fictional reminder"
        let draft = ActionDraft(kind:.createReminder,title:"Fictional reminder")
        let calendars = CalendarSnapshot(sources:[],events:[])
        let reminders = ReminderSnapshot(sources:[.init(id:"list",title:"To do",account:"Fixture",writable:true)],reminders:[])
        do { _ = try await actions.performTool(draft,human:human,authorization:human,turnID:request,model:runtime,calendar:calendars,reminders:reminders);check(false) }
        catch Injected.failure { }
        check(runtime.writer.attempts == 0 && !runtime.writing)
        try actionRepository.save("Later save",key:"unrelated")
        check(ActionReceiptStore(container:actionContainer).entries.isEmpty)
        failActionSave = false;runtime.writer.fail = true
        do { _ = try await actions.performTool(draft,human:human,authorization:human,turnID:request,model:runtime,calendar:calendars,reminders:reminders);check(false) }
        catch let failure as PANativeActionUncertainty { check(!failure.nativeReadbackVerified) }
        check(runtime.writer.attempts == 1 && ActionReceiptStore(container:actionContainer).entries.count == 1)
        check(actions.receiptSummary(registration:"fixture",turnID:request).pending == 1 && actions.receiptSummary(registration:"fixture",turnID:request).confirmed == 0)
        let reopenedActions = AssistantActions(container:actionContainer)
        do { _ = try await reopenedActions.performTool(draft,human:human,authorization:human,turnID:request,model:runtime,calendar:calendars,reminders:reminders);check(false) } catch { }
        check(runtime.writer.attempts == 1)
        runtime.writer.fail = false
        let successRequest = UUID()
        let output = try await reopenedActions.performTool(draft,human:human,authorization:human,turnID:successRequest,model:runtime,calendar:calendars,reminders:reminders)
        check(output == "Fictional verified action" && runtime.writer.attempts == 2 && runtime.refreshes == 1)
        let duplicate = try await reopenedActions.performTool(draft,human:human,authorization:human,turnID:successRequest,model:runtime,calendar:calendars,reminders:reminders)
        check(duplicate.hasPrefix("Already applied:") && runtime.writer.attempts == 2)
        check(reopenedActions.receiptSummary(registration:"fixture",turnID:successRequest).confirmed == 1)
        check(reopenedActions.receiptSummary(registration:"other-owner",turnID:successRequest).confirmed == 0)
        var failedCompletion = AssistantActions(container:actionContainer,repository:actionFailure)
        let completionRequest = UUID()
        runtime.writer.afterApply = { failActionSave = true }
        let feedbacksBefore = runtime.feedbacks
        do {
            _ = try await failedCompletion.performTool(draft,human:human,authorization:human,turnID:completionRequest,model:runtime,calendar:calendars,reminders:reminders)
            check(false)
        } catch let failure as PANativeActionUncertainty {
            check(failure.nativeReadbackVerified && !failure.operationKey.isEmpty)
            check(failure.stoppedReply(receipts:["Earlier confirmed action"]).contains("Earlier confirmed action"))
        }
        check(runtime.writer.attempts == 3 && runtime.feedbacks == feedbacksBefore && !runtime.writing)
        check(failedCompletion.receiptSummary(registration:"fixture",turnID:completionRequest).pending == 1 && failedCompletion.receiptSummary(registration:"fixture",turnID:completionRequest).confirmed == 0)
        failActionSave = false; runtime.writer.afterApply = nil
        do {
            _ = try await failedCompletion.performTool(draft,human:human,authorization:human,turnID:completionRequest,model:runtime,calendar:calendars,reminders:reminders)
            check(false)
        } catch is PANativeActionUncertainty { }
        check(runtime.writer.attempts == 3)
        let durablePending = AssistantActions(container:actionContainer)
        do {
            _ = try await durablePending.performTool(draft,human:human,authorization:human,turnID:completionRequest,model:runtime,calendar:calendars,reminders:reminders)
            check(false)
        } catch is PANativeActionUncertainty { }
        check(runtime.writer.attempts == 3 && durablePending.receiptSummary(registration:"fixture",turnID:completionRequest).pending == 1)
        let batchTurn = UUID()
        for index in 0..<3 {
            var next = draft; next.title = "Different fictional action \(index)"
            _ = try await durablePending.performTool(next,human:human,authorization:human,turnID:batchTurn,model:runtime,calendar:calendars,reminders:reminders)
        }
        check(durablePending.receiptSummary(registration:"fixture",turnID:batchTurn).confirmed == 3)
        let undoTurn = UUID()
        runtime.writer.resultUndoToken = "fictional-undo-token"
        let attemptsBeforeStale=runtime.writer.attempts
        do {_=try await failedCompletion.performTool(draft,human:human,authorization:human,turnID:undoTurn,model:runtime,calendar:calendars,reminders:reminders);check(false)}
        catch LocalRecordFailure.changed {}
        precondition(runtime.writer.attempts == attemptsBeforeStale,"A stale loaded action owner cannot overwrite a newer ledger or start a native write")
        failedCompletion=AssistantActions(container:actionContainer,repository:actionFailure)
        _ = try await failedCompletion.performTool(draft,human:human,authorization:human,turnID:undoTurn,model:runtime,calendar:calendars,reminders:reminders)
        let attemptsBeforeUndoReceipt = runtime.writer.attempts
        failActionSave = true
        do { try failedCompletion.recordUndo(token:"fictional-undo-token");check(false) }
        catch let failure as PANativeActionUncertainty { check(failure.nativeReadbackVerified) }
        failActionSave = false
        let originalAfterFailedUndo = try await failedCompletion.performTool(draft,human:human,authorization:human,turnID:undoTurn,model:runtime,calendar:calendars,reminders:reminders)
        check(originalAfterFailedUndo.hasPrefix("Already applied:") && runtime.writer.attempts == attemptsBeforeUndoReceipt)
        check(failedCompletion.receiptSummary(registration:"fixture",turnID:undoTurn).confirmed == 1)
        let preparedContainer = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var rejectFailureSave = false
        let preparedRepository = LocalRecordRepository(container:preparedContainer) { _ in if rejectFailureSave {throw Injected.failure} }
        let preparedActions = AssistantActions(container:preparedContainer,repository:preparedRepository), preparedRuntime = FictionalRuntime(), preparedTurn = UUID()
        preparedRuntime.writer.failBeforeSave = true
        do { _ = try await preparedActions.performTool(draft,human:human,authorization:human,turnID:preparedTurn,model:preparedRuntime,calendar:calendars,reminders:reminders);check(false) }
        catch is NativePreSaveFailure {}
        check(preparedActions.receiptSummary(registration:"fixture",turnID:preparedTurn).pending == 0)
        let preservedFailure = ActionReceiptStore(container:preparedContainer)
        check(preservedFailure.entries.count == 1 && preservedFailure.entries.values.first?.preSaveFailure == "Fictional target changed before saving")
        let reopenedPrepared = AssistantActions(container:preparedContainer)
        preparedRuntime.writer.failBeforeSave = false
        _ = try await reopenedPrepared.performTool(draft,human:human,authorization:human,turnID:preparedTurn,model:preparedRuntime,calendar:calendars,reminders:reminders)
        let retried = ActionReceiptStore(container:preparedContainer)
        check(preparedRuntime.writer.attempts == 2 && retried.entries.count == 1)
        check(retried.entries.values.first?.preSaveFailure == nil && retried.entries.values.first?.preSaveFailureHistory?.count == 1)
        check(reopenedPrepared.receiptSummary(registration:"fixture",turnID:preparedTurn).confirmed == 1)
        let failedProofTurn = UUID()
        let proofActions = AssistantActions(container:preparedContainer,repository:preparedRepository)
        preparedRuntime.writer.failBeforeSave = true
        preparedRuntime.writer.afterPreSaveFailure = { rejectFailureSave = true }
        do { _ = try await proofActions.performTool(draft,human:human,authorization:human,turnID:failedProofTurn,model:preparedRuntime,calendar:calendars,reminders:reminders);check(false) }
        catch is PANativeActionUncertainty {}
        rejectFailureSave = false; preparedRuntime.writer.afterPreSaveFailure = nil
        check(proofActions.receiptSummary(registration:"fixture",turnID:failedProofTurn).pending == 1)
        let proofReopened = AssistantActions(container:preparedContainer), beforeBlocked = preparedRuntime.writer.attempts
        do { _ = try await proofReopened.performTool(draft,human:human,authorization:human,turnID:failedProofTurn,model:preparedRuntime,calendar:calendars,reminders:reminders);check(false) }
        catch is PANativeActionUncertainty {}
        check(preparedRuntime.writer.attempts == beforeBlocked)
        print("Action receipt checks passed: actual begin failure, no native attempt, later save/reopen, persistent uncertain outcome, completion failure, Undo and corrupt-original preservation.")
    }
}
