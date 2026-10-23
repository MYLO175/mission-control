import Foundation
import SwiftData

/// One application owns its services. Construction never starts collection,
/// source helpers, inference or scheduling; the lifecycle owner starts those.
/// Dashboard state (selection, sheets, layout and feedback) stays in its adapter.
@MainActor final class ApplicationServices {
    private let container: ModelContainer?
    private let injectedNativeSources: (any NativeSourceReading)?
    let chatGPT = ChatGPTConnection()
    let eventKit = EventKitService()
    let mail = MailService()
    let mailLookup = MailLookup()
    let whatsapp = WhatsAppService()
    let conversationEngine = PAConversationEngine()
    let backgroundLearning = BackgroundLearningCoordinator()
    let projectPlacement = LifePlacementService()
    var nativeSources: any NativeSourceReading { injectedNativeSources ?? eventKit }
    lazy var weather = WeatherService(container: container)
    lazy var aiUsage = AIUsageStore(container: container)
    lazy var assistant = AssistantService(connection: chatGPT, container: container, engine: conversationEngine)
    lazy var assistantActions = AssistantActions(container: container)
    lazy var emailSummaries = EmailSummaryService(container: container)
    lazy var heartbeat = HeartbeatService(container: container)
    lazy var memoryLearning = MemoryLearningService(container: container)
    lazy var sourceLearning = SourceContextLearningService(container: container)
    lazy var nativeSourceLearning = NativeSourceLearningService(container: container)
    lazy var memoryMaintenance = MemoryMaintenanceService(container: container)
    lazy var learningBudget = LearningBudget(container: container)
    lazy var lifeOrganisation = LifeOrganisationService(container: container)
    lazy var nativeCreations = NativeCreationStore(container: container)
    lazy var proactive = ProactiveService(container: container)
    lazy var briefings = BriefingService(container: container)
    init(container: ModelContainer?, nativeSources: (any NativeSourceReading)? = nil) {
        self.container = container
        self.injectedNativeSources = nativeSources
    }
}
