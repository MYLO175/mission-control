import Foundation
import Observation
import SwiftData

struct ActionTarget: Identifiable { var id: String; var label: String }

@MainActor @Observable final class AssistantActions {
    var targets: [ActionTarget] = []
    var selectedTarget = ""
    private let receipts: ActionReceiptStore
    private var ledger: [String:ActionLedgerEntry] { get { receipts.entries } set { receipts.entries = newValue } }
    private var storageAvailable: Bool { receipts.readable }
    init(container: ModelContainer?, repository: LocalRecordRepository? = nil) {
        receipts = ActionReceiptStore(container: container, repository: repository)
    }
    func receiptSummary(registration: String, turnID: UUID) -> ActionTurnReceiptSummary {
        receipts.summary(registration: registration, turnID: turnID)
    }
    private func save() throws {
        try receipts.save()
    }
    /// Executes a completed model tool call using only identities issued in this turn.
    /// The latest human message authorises the operation; imported records never do.
    func performTool(_ draft: ActionDraft, human: String, authorization: String?, turnID: UUID, model: any NativeActionRuntime, calendar: CalendarSnapshot, reminders: ReminderSnapshot, expectedDetails: NativeEditDetails? = nil, valid: NativeWriteValidity? = nil) async throws -> String {
        try PAToolProtocol.evidence(authorization,human:human)
        try ActionRules.validate(draft)
        guard model.actionContextEnabled, !model.writing, !ProcessInfo.processInfo.arguments.contains("--sample") else { throw ActionFailure.message("Apple writes are unavailable; no change attempted.") }
        let reminder = reminders.reminders.first { $0.id == draft.target }, event = calendar.events.first { $0.id == draft.target }
        switch draft.kind {
        case .editReminder,.completeReminder,.deleteReminder: guard reminder != nil else { throw ActionFailure.message("Read the reminder's exact identity before changing it.") }
        case .editEvent,.deleteEvent: guard event != nil else { throw ActionFailure.message("Read the event's exact occurrence before changing it.") }
        default: break
        }
        if !selectedTarget.isEmpty, let target = draft.target, target != selectedTarget { throw ActionFailure.message("The tool target differs from your selected item.") }
        // Canonical operation key deduplicates repeated calls even if their call IDs differ.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let canonical = String(data:try encoder.encode(draft),encoding:.utf8)!
        let key = ActionRules.key(registration:model.actionRegistration,request:turnID.uuidString,selectedTarget:canonical)
        if let prior = ledger[key], prior.undone != true && prior.preSaveFailure == nil {
            if let result = prior.result { return "Already applied: " + result }
            throw PANativeActionUncertainty(operationKey: key, message: "This operation already has a pending receipt. Check the original before continuing; no save was repeated.")
        }
        let allowedCalendars = Set(calendar.sources.filter { !model.actionExcludedCalendars.contains($0.id) && $0.writable }.map(\.id))
        let allowedLists = Set(reminders.sources.filter { !model.actionExcludedLists.contains($0.id) && $0.writable }.map(\.id))
        if let destination = draft.destination {
            let allowed = draft.kind == .createEvent || draft.kind == .editEvent ? allowedCalendars : allowedLists
            guard allowed.contains(destination) else { throw ActionFailure.message("Destination is not an enabled writable source issued by a read tool.") }
        }
        try Task.checkCancellation()
        model.writing = true; defer { model.writing = false }
        try receipts.begin(key, turnID: turnID, registration: model.actionRegistration)
        let result: ActionResult
        do {
            result = try await model.nativeActionWriter.applyTool(draft,reminder:reminder,event:event,marker:key,allowedCalendars:allowedCalendars,allowedLists:allowedLists,expectedDetails:expectedDetails,valid:valid)
        } catch let failure as NativePreSaveFailure {
            do { try receipts.failedBeforeSave(key, failure: failure) }
            catch { throw PANativeActionUncertainty(operationKey: key, message: "No Apple save was attempted, but its failure receipt could not be saved. The pending receipt is retained; check it before continuing.") }
            try Task.checkCancellation()
            throw failure
        } catch {
            throw PANativeActionUncertainty(operationKey: key, message: "The Apple operation's outcome is unconfirmed. Its pending receipt is retained; check the original before continuing. " + String(error.localizedDescription.prefix(500)))
        }
        var fixtureTitle: String?, fixtureNotes: String?
        #if DEBUG
        if let title = draft.title, (draft.kind == .createReminder || draft.kind == .createEvent), title.hasPrefix("Mission Control tool validation "), UUID(uuidString:String(title.dropFirst("Mission Control tool validation ".count))) != nil, draft.notes == nil { fixtureTitle = title;fixtureNotes = NativeRequestNotes.creation(draft.notes) }
        if let itemID = result.itemID, let title = draft.title {
            for (originalKey, original) in ledger where original.itemID == itemID && original.fixtureTitle != nil { ledger[originalKey]?.fixtureTitle = title }
        }
        #endif
        if let token = result.undoToken { model.undoToken = token; model.undoTitle = reminder?.title ?? "Reminder" }
        if draft.scope == "futureEvents" || draft.scope == "reminderSeries" || draft.kind == .deleteEvent || draft.kind == .deleteReminder || (draft.kind == .editEvent || draft.kind == .editReminder) && result.nativeUndo == nil { model.clearNativeEditUndo() }
        if let undo = result.nativeUndo { model.recordAssistantEditUndo(undo) }
        do {
            try receipts.complete(key, result: result.message, itemID: result.itemID, undoToken: result.undoToken,
                                  fixtureTitle: fixtureTitle, fixtureNotes: fixtureNotes)
        } catch {
            model.refresh(retryMail:false)
            throw PANativeActionUncertainty(operationKey: key, nativeReadbackVerified: true,
                message: "Apple readback confirmed the change, but its completion receipt could not be saved. The pending receipt is retained; check the original before continuing. " + String(error.localizedDescription.prefix(400)))
        }
        model.showFeedback(result.message); selectedTarget = ""; model.refresh(retryMail:false)
        return result.message
    }
    func performNativeDeletion(baseline: NativeEditDetails, scope: NativeChangeScope, requestID: UUID, model: any NativeActionRuntime) async throws -> String {
        let key=ActionRules.key(registration:model.actionRegistration,request:requestID.uuidString,selectedTarget:baseline.occurrenceID + ":delete:" + scope.rawValue)
        if let prior=ledger[key],prior.preSaveFailure == nil { if let result=prior.result {return result};throw PANativeActionUncertainty(operationKey:key,message:"A deletion is already recorded as pending. Check Apple Calendar or Reminders before continuing; it was not repeated.") }
        try NativeEditRules.validateDeletion(scope,baseline:baseline)
        try receipts.begin(key, turnID: requestID, registration: model.actionRegistration)
        let result: String
        do { result=try await model.nativeActionWriter.deleteItem(baseline:baseline,scope:scope) }
        catch let failure as NativePreSaveFailure {
            do { try receipts.failedBeforeSave(key, failure: failure) }
            catch { throw PANativeActionUncertainty(operationKey: key, message: "No Apple removal was attempted, but its failure receipt could not be saved. The pending receipt is retained; check it before continuing.") }
            try Task.checkCancellation()
            throw failure
        }
        catch { throw PANativeActionUncertainty(operationKey:key,message:"The native deletion's outcome is unconfirmed. Its pending receipt is retained; check the original before continuing. " + String(error.localizedDescription.prefix(500))) }
        do { try receipts.complete(key, result: result, itemID: baseline.itemID) }
        catch { throw PANativeActionUncertainty(operationKey:key,nativeReadbackVerified:true,message:"Native deletion readback was confirmed, but its completion receipt could not be saved. The pending receipt is retained; check the original before continuing.") }
        return result
    }
    func recordUndo(token: String) throws {
        let before = ledger
        let keys = ledger.filter { $0.value.undoToken == token }.map(\.key).sorted()
        for key in keys { ledger[key]?.undone = true }
        do { try save() }
        catch {
            ledger = before
            throw PANativeActionUncertainty(operationKey: keys.first ?? token, nativeReadbackVerified: true,
                message: "Native Undo readback was confirmed, but its action receipt could not be updated. The previous receipt is retained; check the original before continuing.")
        }
    }
    #if DEBUG
    /// Explicit one-off human-requested cleanup; never called by refresh/inference.
    func cleanupRequestMarkers(_ model:any NativeActionRuntime) async -> [String:Int] {
        let registration=model.actionRegistration
        guard storageAvailable,!model.actionAssistantBusy,!model.writing else {return ["blocked":1]}
        model.writing=true;defer {model.writing=false}
        var report=["reminders":0,"events":0,"unchanged":0,"errors":0]
        let eventScope:NativeChangeScope? = ProcessInfo.processInfo.arguments.contains("--cleanup-marker-future") ? .futureEvents : ProcessInfo.processInfo.arguments.contains("--cleanup-marker-next") ? .occurrence : nil
        let valid:NativeWriteValidity = {model.actionRegistration == registration}
        for (key,entry) in ledger.sorted(by:{$0.key < $1.key}) where entry.result != nil && entry.itemID != nil && entry.fixtureTitle == nil {
            guard valid() else {report["errors",default:0] += 1;break}
            do {
                if let kind=try await model.nativeActionWriter.clearRequestMarker(id:entry.itemID!,receiptKey:key,eventScope:eventScope,valid:valid) {
                    report[kind == .reminder ? "reminders" : "events",default:0] += 1
                    ledger[key]?.clearedMarker=true;try save()
                } else {report["unchanged",default:0] += 1}
            } catch {
                report["errors",default:0] += 1
                if error.localizedDescription == "Recurring Calendar notes need an explicit scope." {report["recurringCalendarSkipped",default:0] += 1}
                else {report["otherError",default:0] += 1}
            }
        }
        return report
    }
    func cleanupFixtures(_ model: any NativeActionRuntime) async throws -> String {
        for (key, entry) in ledger where entry.fixtureTitle != nil {
            guard let id = entry.itemID, let title = entry.fixtureTitle else { continue }
            try await model.nativeActionWriter.removeActionFixture(id:id,title:title,marker:key,expectedNotes:entry.fixtureNotes)
            ledger[key]?.fixtureTitle = nil
            try save()
        }
        model.refresh(retryMail:false)
        return "Tracked assistant action fixtures cleaned and absence verified."
    }
    #endif
}
