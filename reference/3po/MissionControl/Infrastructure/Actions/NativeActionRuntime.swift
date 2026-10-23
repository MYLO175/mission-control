import Foundation

struct ActionResult { var message: String; var undoToken: String? = nil; var itemID: String? = nil; var nativeUndo: NativeEditUndo? = nil }

/// The action executor needs current permission/ownership and presentation
/// callbacks, rather than the dashboard's navigation, memory and source machinery.
@MainActor protocol NativeActionRuntime: AnyObject {
    var actionRegistration: String { get }
    var actionContextEnabled: Bool { get }
    var actionAssistantBusy: Bool { get }
    var actionExcludedCalendars: Set<String> { get }
    var actionExcludedLists: Set<String> { get }
    var nativeActionWriter: any NativeActionWriting { get }
    var writing: Bool { get set }
    var undoToken: String? { get set }
    var undoTitle: String { get set }
    func clearNativeEditUndo()
    func recordAssistantEditUndo(_ receipt: NativeEditUndo)
    func showFeedback(_ text: String)
    func refresh(retryMail: Bool)
}

protocol NativeActionWriting {
    func applyTool(_ draft: ActionDraft, reminder: TaskItem?, event: AgendaEvent?, marker: String, allowedCalendars: Set<String>, allowedLists: Set<String>, expectedDetails: NativeEditDetails?, valid: NativeWriteValidity?) async throws -> ActionResult
    func deleteItem(baseline: NativeEditDetails, scope: NativeChangeScope, valid: NativeWriteValidity?, claim: NativeWriteClaim?) async throws -> String
    #if DEBUG
    func clearRequestMarker(id: String, receiptKey: String, eventScope: NativeChangeScope?, valid: @escaping NativeWriteValidity) async throws -> NativeItemKind?
    func removeActionFixture(id: String, title: String, marker: String, expectedNotes: String?) async throws
    #endif
}

extension NativeActionWriting {
    func deleteItem(baseline: NativeEditDetails, scope: NativeChangeScope) async throws -> String {
        try await deleteItem(baseline: baseline, scope: scope, valid: nil, claim: nil)
    }
}
