import Foundation

/// The learning services consume saved human context, permitted cached source
/// evidence and an inference port. They cannot navigate or start source helpers.
@MainActor protocol LearningAssistantReading: AnyObject {
    var connection: any PAInferenceConnection { get }
    var memory: PAMemoryStore { get }
    var busy: Bool { get }
    var hasDraft: Bool { get }
    var contextEnabled: Bool { get }
    var contextRevision: UUID { get }
    var topics: [AssistantConversation] { get }
    var excludedCalendars: Set<String> { get }
    var excludedLists: Set<String> { get }
    var excludedAccounts: Set<String> { get }
    func learningTurns() -> [MemoryLearningTurn]
    func acknowledgeLearned(_ learned: [LearnedMemory])
}

@MainActor protocol WhatsAppLearningReading: AnyObject {
    var messages: [WhatsAppReadMessage] { get }
    var chats: [WhatsAppChat] { get }
    func scope(for registration: String) -> WhatsAppSourceScope
    func access(for registration: String) -> WhatsAppAccess
}

struct LearningActivity {
    var otherWorkBusy = false
    var lanes: Set<LearningLane> = []
    func blocks(_ lane: LearningLane) -> Bool {
        otherWorkBusy || !lanes.subtracting([lane]).isEmpty
    }
    static var unavailable: Self { .init(otherWorkBusy: true) }
}

@MainActor struct LearningOwnership {
    var runID:String
    var validate:() throws->Void
    var claim:() throws->Void
}
struct HeartbeatLearningResult {
    var lane:LearningLane? = nil
    var failure:String? = nil
    var detail:String
    var skipped:Bool = true
}
@MainActor final class LearningRuntime {
    static let inlineSourceOrganisationInstructions="Classify each useful new source fact into up to three existing supplied broad areas in the same bounded response when its exact evidence supports them. Use no invented areas and leave areas empty when uncertain. This is navigation metadata only: never create, rename, merge or restructure a human project or task."
    let assistant: any LearningAssistantReading
    let inference: any PAInferenceConnection
    let learningBudget: LearningBudget
    let whatsapp: any WhatsAppLearningReading
    let now: () -> Date
    let ownership:LearningOwnership?
    var canOfferQuestion: (String, Date) -> Bool = { _, _ in true }
    private let reviewNativePermission:(MemorySourceKind)->Bool
    private let reviewWhatsAppPermission:()->Bool
    private let reviewWhatsAppRevision:()->UUID?
    var ownedHeartbeatRunID:String? {ownership?.runID}
    func validateOwnership() throws {try Task.checkCancellation();try ownership?.validate()}
    func claimInference() throws {try validateOwnership();try ownership?.claim();try validateOwnership()}
    func permitsReviewLearning(_ kind:MemorySourceKind)->Bool {assistant.contextEnabled && reviewNativePermission(kind)}
    var whatsappLearningAccess:WhatsAppAccess {
        var access=whatsapp.access(for:inference.activeID)
        if assistant.contextEnabled && access.enabled && !access.chats.isEmpty && reviewWhatsAppPermission() {access.learnContext=true}
        return access
    }
    var whatsappReviewLearningRevision:UUID? {
        let access=whatsapp.access(for:inference.activeID)
        // These independent source choices already admit learning. A heartbeat
        // toggle cannot revoke their grant or manufacture a new baseline.
        guard assistant.contextEnabled,access.enabled,!access.chats.isEmpty,access.learnContext != true,!access.briefEnabled,access.includeInSuggestions != true else {return nil}
        return reviewWhatsAppRevision()
    }
    private let activity: () -> LearningActivity
    private let isWriting: () -> Bool
    private let revision: () -> Int
    private let cachedNativeItems: (MemorySourceKind, Date) -> [NativeLearningItem]?
    var writing: Bool { isWriting() }
    var sourceRevision: Int { revision() }
    func otherWorkBusy(excluding lane: LearningLane) -> Bool { activity().blocks(lane) }
    func nativeLearningItems(_ kind: MemorySourceKind) -> [NativeLearningItem]? { cachedNativeItems(kind, now()) }
    init(assistant: any LearningAssistantReading, inference: any PAInferenceConnection, learningBudget: LearningBudget, whatsapp: any WhatsAppLearningReading,
         now: @escaping () -> Date = { .now }, activity: @escaping () -> LearningActivity, writing: @escaping () -> Bool,
         sourceRevision: @escaping () -> Int, nativeItems: @escaping (MemorySourceKind, Date) -> [NativeLearningItem]?,
         ownership:LearningOwnership? = nil,reviewNativePermission:@escaping (MemorySourceKind)->Bool = {_ in false},reviewWhatsAppPermission:@escaping ()->Bool = {false},reviewWhatsAppRevision:@escaping ()->UUID? = {nil}) {
        self.assistant = assistant; self.inference = inference; self.learningBudget = learningBudget; self.whatsapp = whatsapp
        self.ownership=ownership;self.reviewNativePermission=reviewNativePermission;self.reviewWhatsAppPermission=reviewWhatsAppPermission;self.reviewWhatsAppRevision=reviewWhatsAppRevision
        self.now = now; self.activity = activity; self.isWriting = writing; self.revision = sourceRevision; self.cachedNativeItems = nativeItems
    }
}
