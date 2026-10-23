import SwiftUI
import SwiftData
import AppKit
import EventKit

struct CalendarRemovalReviewSession:Identifiable {
    var record:PADiscovery
    var baseline:NativeEditDetails
    var selectedModel:String
    var sourceScope:String
    var id:String {record.id}
}

@MainActor @Observable final class DashboardModel {
    let preparedReview = PreparedReviewStore()
    @ObservationIgnored lazy var contextPages = ContextPageStore(container: container)
    @ObservationIgnored let contextRecordProjections = ContextRecordProjectionCache()
    #if DEBUG
    /// Fictional consumer acceptance only; normal startup never consults this port.
    @ObservationIgnored var contextCalendarAccess: (() -> Bool)?
    @ObservationIgnored var contextKnowledgeBuildCount = 0
    #endif
    @ObservationIgnored lazy var contextConsolidation = ContextConsolidationService()
    @ObservationIgnored lazy var contextQuestions = ContextProjectQuestionStore(container: container)
    var whatsapp: WhatsAppService { services.whatsapp }
    var calendarData = CalendarSnapshot(sources: [], events: [])
    var paOrientation: PAOrientation? {didSet{nativeLearningProjectionRevision &+= 1}}
    var paOrientationHealth = SourceHealth()
    private(set) var orientationCollectionRevision = -1
    private(set) var reminderCollectionRevision = -1
    private(set) var completedReminderCollectionRevision = -1
    private var lastOrientationCheck = Date.distantPast
    private var heartbeatPowerMonitor:HeartbeatPowerMonitor?
    var reminderData = ReminderSnapshot(sources: [], reminders: []) {didSet{nativeLearningProjectionRevision &+= 1}}
    @ObservationIgnored var nativeLearningProjectionRevision=0
    @ObservationIgnored let nativeLearningProjectionCache=NativeLearningProjectionCache()
    @ObservationIgnored let nativeLearningValidation=NativeLearningValidationBatch()
    var completedReminders:[CompletedReminder] = []
    var completedReminderHealth=SourceHealth()
    var mailData = MailSnapshot(messages: [], accounts: [], errors: []) {didSet{mailLearningProjectionRevision &+= 1}}
    var mailLearningProjectionRevision=0
    @ObservationIgnored let mailLearningProjectionCache=MailLearningProjectionCache()
    var calendarHealth = SourceHealth()
    var reminderHealth = SourceHealth()
    var mailHealth = SourceHealth()
    var mailIndex = MailIndexState() {didSet{mailLearningProjectionRevision &+= 1}}
    var mailCoverage: String { sample ? "Sample data" : mailIndex.coverage(accounts: mailData.accounts) }
    var selectedDate = Calendar.current.startOfDay(for: .now)
    var excludedCalendars: Set<String> = [] { didSet { saveFilters() } }
    var excludedLists: Set<String> = [] { didSet { saveFilters() } }
    var excludedAccounts: Set<String> = [] { didSet { saveFilters() } }
    var assistantFocusRequest: AssistantFocusRequest?
    func openAssistantComposer() {
        assistant.openPA()
        workspace.showAssistant()
        guard let widget = workspace.selected.widgets.first(where:{ $0.kind == .conversation }) else { return }
        assistantFocusRequest = AssistantFocusRequest(widgetID:widget.id)
    }
    var activityNavigation:AIActivityNavigation?
    var reviewSheetHeight:CGFloat=660
    var reviewPresentation:ReviewConversationPresentation?
    var showingAIHeartbeat=false
    @ObservationIgnored var reviewQueuePump:Task<Void,Never>?
    @ObservationIgnored lazy var reviewWork:ReviewWorkService = {
        return ReviewWorkService(load:{try LocalRecordRepository.read("reviewWork",container:self.container)},persist:{data in guard let container=self.container else {throw ActionFailure.message("Storage is unavailable.")};try LocalRecordRepository(container:container).write(["reviewWork":data])})
    }()
    @ObservationIgnored lazy var aiActivity:AIActivityStore = {
        return AIActivityStore(load:{try LocalRecordRepository.read("aiActivity",container:self.container)},persist:{data in guard let container=self.container else {throw ActionFailure.message("Storage is unavailable.")};try LocalRecordRepository(container:container).write(["aiActivity":data])})
    }()
    var selectedMessage: MailMessage?
    var editTarget: NativeEditTarget?
    var calendarRemovalReview:CalendarRemovalReviewSession?
    private(set) var nativeWriteFeedback: AIActivityFeedback?
    var preview = ""
    var previewLoading = false
    var previewError: String?
    var writeError: String?
    private(set) var approvingDiscoveryID:String?
    private(set) var reviewApprovalError:String?
    private(set) var reviewApprovalErrorID:String?
    private(set) var reviewApprovalErrorAccount:String?
    var writing = false
    var undoToken: String? { didSet { completionUndoDate = undoToken == nil ? nil : .now } }
    private var completionUndoDate: Date?
    private var editUndo: NativeEditUndo?
    var undoTitle = ""
    var validationReport: String?
    #if DEBUG
    func validateProactivePrompt() {
        validationReport = "Checking the proactive prompt with fictional sources…"
        Task { [self] in
            let result: String
            do { result = try await proactive.validate(self) } catch { result = error.localizedDescription }
            validationReport = result
            UserDefaults.standard.set(["completed":Date.now.ISO8601Format(),"result":result],forKey:"debugProactiveValidation")
        }
    }
    func validateMailFolders() {
        validationReport = "Checking bounded Mail folder reads…"
        Task { [self] in
            let result: String
            do { result = try await mail.validateSearchFolders() } catch { result = error.localizedDescription }
            validationReport = result
            UserDefaults.standard.set(["completed":Date.now.ISO8601Format(),"result":result],forKey:"debugMailFolderValidation")
        }
    }
    func validateMemoryLearning() {
        validationReport = "Checking the memory prompt with fictional source-free messages…"
        Task { [self] in
            do { validationReport = try await memoryLearning.validate(self) }
            catch { validationReport = error.localizedDescription }
        }
    }
    func validateLifeNotebook() {
        validationReport="Checking life organisation and recall with fictional facts…"
        Task { [self] in
            let result:[String:Any]
            do { result=try await LifeNotebookEvaluation.run(self);validationReport="Life notebook evaluation: \(result["passed"] ?? 0)/\(result["total"] ?? 0) checks passed." }
            catch { result=["completed":Date.now.ISO8601Format(),"error":String(error.localizedDescription.prefix(500))];validationReport=error.localizedDescription }
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-life-notebook-evaluation.json"),options:.atomic) }
            if ProcessInfo.processInfo.arguments.contains("--validate-life-notebook") { NSApp.terminate(nil) }
        }
    }
    #endif
    var storageError: String?
    private(set) var storageOwnershipBlocked = false
    @ObservationIgnored private var personalStorageLease: LocalRecordFileLease?
    @ObservationIgnored private lazy var services = ApplicationServices(container: container, nativeSources: injectedNativeSources)
    var weather: WeatherService { get { services.weather } set { services.weather = newValue } }
    var chatGPT: ChatGPTConnection { services.chatGPT }
    var aiUsage: AIUsageStore { get { services.aiUsage } set { services.aiUsage = newValue } }
    @ObservationIgnored lazy var workspace = WorkspaceStore(container:container,calendars:excludedCalendars,lists:excludedLists,accounts:excludedAccounts,date:selectedDate)
    @ObservationIgnored lazy var widgetCalendars = WidgetCalendarStore(service:eventKit)
    @ObservationIgnored lazy var assistant:AssistantService = {
        let service=services.assistant
        service.memory.sourceIsPermitted = { [weak self,weak service] record in
            guard let self,service?.contextEnabled == true else { return false }
            if record.source?.identity.kind == .whatsapp {
                return SourceContextRules.permitted(record,access:self.learningRuntime().whatsappLearningAccess,linkedIdentity:self.whatsapp.linkedIdentity,messages:self.whatsapp.messages)
            }
            return self.nativeSourceLearning.permits(record,model:self)
        }
        service.memory.sourcePermissionProjection = { [weak self,weak service] in
            guard let self,let service,service.contextEnabled else { return [] }
            return self.nativeLearningValidation.permittedMemory {
                let registration=self.chatGPT.activeID
                var result=Set<UUID>()
                // Hash each native snapshot once per projection, rather than once per saved fact.
                let sourceRecords=service.memory.records.filter{$0.registration == registration && $0.source != nil}
                for kind in NativeLearningRules.kinds where sourceRecords.contains(where:{$0.source?.identity.kind == kind}) && self.nativeSourceLearning.permittedKind(kind,model:self.learningRuntime()) {
                    if let items=self.nativeLearningItems(kind) {
                        for record in sourceRecords where record.source?.identity.kind == kind {
                            if NativeLearningRules.permitted(record,items:items) { result.insert(record.id) }
                        }
                    }
                }
                for record in service.memory.records where record.source?.identity.kind == .whatsapp {
                    if service.memory.sourceIsPermitted(record) { result.insert(record.id) }
                }
                return result
            }
        }
        return service
    }()
    var assistantActions: AssistantActions { get { services.assistantActions } set { services.assistantActions = newValue } }
    var emailSummaries: EmailSummaryService { get { services.emailSummaries } set { services.emailSummaries = newValue } }
    var heartbeat: HeartbeatService { get { services.heartbeat } set { services.heartbeat = newValue } }
    private var briefingPoll: Task<Void, Never>?
    private var nativePoll: Task<Void, Never>?
    var memoryLearning: MemoryLearningService { get { services.memoryLearning } set { services.memoryLearning = newValue } }
    var sourceLearning: SourceContextLearningService { get { services.sourceLearning } set { services.sourceLearning = newValue } }
    var nativeSourceLearning: NativeSourceLearningService { get { services.nativeSourceLearning } set { services.nativeSourceLearning = newValue } }
    var memoryMaintenance: MemoryMaintenanceService { get { services.memoryMaintenance } set { services.memoryMaintenance = newValue } }
    var learningBudget: LearningBudget { get { services.learningBudget } set { services.learningBudget = newValue } }
    private var backgroundLearning: BackgroundLearningCoordinator { services.backgroundLearning }
    var projectPlacement: LifePlacementService { services.projectPlacement }
    var lifeOrganisation: LifeOrganisationService { get { services.lifeOrganisation } set { services.lifeOrganisation = newValue } }
    var nativeCreations: NativeCreationStore { get { services.nativeCreations } set { services.nativeCreations = newValue } }
    var proactive: ProactiveService { get { services.proactive } set { services.proactive = newValue } }
    var sourceRevision = 0
    var briefings: BriefingService { get { services.briefings } set { services.briefings = newValue } }
    var eventKit: EventKitService { services.eventKit }
    private let injectedNativeSources: (any NativeSourceReading)?
    var nativeSources: any NativeSourceReading { services.nativeSources }
    var mail: MailService { services.mail }
    var mailLookup: MailLookup { services.mailLookup }
    var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var changes: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    @ObservationIgnored private let nativeReconciliation = NativeReconciliation()
    private var nativeWriteGeneration = 0
    private var pendingCalendarRefresh = false
    private var pendingReminderRefresh = false
    private var pendingOrientationRefresh = false
    private var started = false
    private var sample: Bool { ProcessInfo.processInfo.arguments.contains("--sample") }

    @ObservationIgnored private var loadingFilters = true
    init(nativeSources: (any NativeSourceReading)? = nil) {
        defer {loadingFilters=false}
        injectedNativeSources = nativeSources
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-conversation") || ProcessInfo.processInfo.arguments.contains("--preview-chat-approval") {
            do {container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))}
            catch {storageError="Trial storage unavailable"}
            return
        }
        #endif
        defer { if !storageOwnershipBlocked { chatGPT.usageStore = aiUsage } }
        // Read all saved filters before observable property setters persist any
        // values; otherwise the first setter erases later filters during init.
        let savedCalendars = Set(UserDefaults.standard.stringArray(forKey: "excludedCalendars") ?? [])
        let savedLists = Set(UserDefaults.standard.stringArray(forKey: "excludedLists") ?? [])
        let savedAccounts = Set(UserDefaults.standard.stringArray(forKey: "excludedAccounts") ?? [])
        excludedCalendars = savedCalendars
        excludedLists = savedLists
        excludedAccounts = savedAccounts
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-calendar-drag") {
                container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true));return
            }
            if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") || ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") || ProcessInfo.processInfo.arguments.contains("--preview-life-and-plans") || ProcessInfo.processInfo.arguments.contains("--validate-commitment-reports") || ProcessInfo.processInfo.arguments.contains("--validate-advice-context") || ProcessInfo.processInfo.arguments.contains("--validate-native-memory") || ProcessInfo.processInfo.arguments.contains("--preview-memory-review") || ProcessInfo.processInfo.arguments.contains("--inspect-luna-access") || ProcessInfo.processInfo.arguments.contains("--preview-memory-inspection") || ProcessInfo.processInfo.arguments.contains("--validate-memory-inspection") {
                container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true));return
            }
            if ProcessInfo.processInfo.arguments.contains("--validate-source-timeline") || ProcessInfo.processInfo.arguments.contains("--preview-source-timeline") || ProcessInfo.processInfo.arguments.contains("--preview-settings") || ProcessInfo.processInfo.arguments.contains("--validate-images") || ProcessInfo.processInfo.arguments.contains("--preview-images") || ProcessInfo.processInfo.arguments.contains("--render-projects") || ProcessInfo.processInfo.arguments.contains("--validate-projects") || ProcessInfo.processInfo.arguments.contains("--preview-projects") || ProcessInfo.processInfo.arguments.contains("--validate-placement") || ProcessInfo.processInfo.arguments.contains("--validate-ownership") || ProcessInfo.processInfo.arguments.contains("--validate-mail-monitoring") || ProcessInfo.processInfo.arguments.contains("--validate-mail-dates") {
                container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                return
            }
            #endif
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mission Control", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            do {
                // Older copies do not know the lease protocol. Refuse an
                // already running registered copy before opening personal data.
                guard !NSWorkspace.shared.runningApplications.contains(where: {
                    $0.bundleIdentifier == "com.mylomichael.missioncontrol" && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                }) else { throw LocalRecordFailure.busy }
                personalStorageLease = try LocalRecordFileLease(url: directory.appendingPathComponent("application-writer.lock"))
            }
            catch { storageOwnershipBlocked = true; throw error }
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("Dashboard.store"), cloudKitDatabase: .none)
            container = try ModelContainer(for: CachedDashboard.self, configurations: configuration)
            restore()
        } catch { storageError = "Local cache unavailable: " + error.localizedDescription }
    }
    func start() {
        guard !storageOwnershipBlocked else { return }
        guard !started else { return }; started = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-conversation") || ProcessInfo.processInfo.arguments.contains("--preview-chat-approval") { return }
        if ProcessInfo.processInfo.arguments.contains("--preview-calendar-drag") { return }
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") || ProcessInfo.processInfo.arguments.contains("--preview-life-and-plans") || ProcessInfo.processInfo.arguments.contains("--preview-memory-review") || ProcessInfo.processInfo.arguments.contains("--preview-memory-inspection") {return}
        if ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") {
            Task {
                if ProcessInfo.processInfo.arguments.contains("--working-context-model") {
                    let report:[String:Any]
                    do {report=try await WorkingContextModelEvaluation.run(self)}
                    catch {report=["error":error.localizedDescription,"requests":NSNull(),"requestCountKnown":false,"storage":"Fictional read-only ports; normal source startup did not run. This outer failure does not establish how many requests were attempted."]}
                    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-working-context-model-evaluation.json"),options:.atomic)}
                    NSApp.terminate(nil);return
                }
                if ProcessInfo.processInfo.arguments.contains("--reminder-completion-native") {
                    let report:[String:Any]
                    do {report=try await ReviewInboxEvaluation.runReminderCompletion(self)}
                    catch {report=["error":error.localizedDescription,"cleanupError":"Native completion check did not finish."]}
                    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-reminder-completion-evaluation.json"),options:.atomic)}
                    NSApp.terminate(nil);return
                }
                let result:[String:Any]
                let resolutionOnly=ProcessInfo.processInfo.arguments.contains("--email-resolution-only")
                let removalOnly=ProcessInfo.processInfo.arguments.contains("--calendar-removal-only")
                let approvalOnly=ProcessInfo.processInfo.arguments.contains("--approval-only")
                let mailOnly=ProcessInfo.processInfo.arguments.contains("--mail-review-only")
                let evidenceOnly=ProcessInfo.processInfo.arguments.contains("--mail-evidence-only")
                let emailWork=ProcessInfo.processInfo.arguments.contains("--email-work-only")
                let relevanceOnly=ProcessInfo.processInfo.arguments.contains("--relevance-only")
                let schedulerOnly=ProcessInfo.processInfo.arguments.contains("--scheduler-only")
                let intentPreparation=ProcessInfo.processInfo.arguments.contains("--intent-preparation-only")
                let chatApproval=ProcessInfo.processInfo.arguments.contains("--chat-approval-only")
                let heartbeatContract=ProcessInfo.processInfo.arguments.contains("--heartbeat-contract-only")
                let briefDayparts=ProcessInfo.processInfo.arguments.contains("--brief-dayparts-only")
                let proposalTimeline=ProcessInfo.processInfo.arguments.contains("--proposal-timeline-only")
                do {result=try await (chatApproval ? ReviewInboxEvaluation.runChatApproval(self) : resolutionOnly ? ReviewInboxEvaluation.runEmailResolution(self) : removalOnly ? ReviewInboxEvaluation.runCalendarRemoval(self) : relevanceOnly ? ReviewInboxEvaluation.runRelevance(self) : briefDayparts ? ReviewInboxEvaluation.runBriefDayparts(self) : intentPreparation ? ReviewInboxEvaluation.runIntentPreparation(self) : heartbeatContract ? ReviewInboxEvaluation.runHeartbeatContract(self) : proposalTimeline ? ReviewInboxEvaluation.runProposalTimeline(self) : schedulerOnly ? HeartbeatService.evaluateScheduling(self) : emailWork ? ReviewInboxEvaluation.runEmailWork(self) : evidenceOnly ? ReviewInboxEvaluation.runMailEvidence(self) : mailOnly ? ReviewInboxEvaluation.runMailReview(self) : approvalOnly ? ReviewInboxEvaluation.runApproval(self) : ReviewInboxEvaluation.run(self))} catch {result=["error":error.localizedDescription,"storage":"Fictional disposable source-free startup"]}
                let path=chatApproval ? "/tmp/missioncontrol-chat-approval-evaluation.json" : resolutionOnly ? "/tmp/missioncontrol-email-resolution-evaluation.json" : removalOnly ? "/tmp/missioncontrol-calendar-removal-evaluation.json" : relevanceOnly ? "/tmp/missioncontrol-relevance-evaluation.json" : briefDayparts ? "/tmp/missioncontrol-brief-dayparts-evaluation.json" : intentPreparation ? "/tmp/missioncontrol-intent-preparation-evaluation.json" : heartbeatContract ? "/tmp/missioncontrol-heartbeat-contract-evaluation.json" : proposalTimeline ? "/tmp/missioncontrol-proposal-timeline-evaluation.json" : schedulerOnly ? "/tmp/missioncontrol-review-scheduler-evaluation.json" : emailWork ? "/tmp/missioncontrol-email-work-evaluation.json" : evidenceOnly ? "/tmp/missioncontrol-mail-evidence-evaluation.json" : mailOnly ? "/tmp/missioncontrol-mail-review-evaluation.json" : approvalOnly ? "/tmp/missioncontrol-review-approval-evaluation.json" : "/tmp/missioncontrol-review-inbox-evaluation.json"
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:EvaluationOutput.url(path),options:.atomic)}
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-commitment-reports") {
            Task {
                let result:[String:Any]
                do { result=try await CommitmentReportEvaluation.run(self) } catch { result=["error":error.localizedDescription,"storage":"Fictional data; disposable storage; sources never started"] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-commitment-reports-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-advice-context") {
            Task {
            let result:[String:Any]
            do { result=try await AdviceContextEvaluation.run(self) } catch { result=["error":error.localizedDescription,"requests":0,"storage":"Disposable storage; sources never started"] }
            if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-advice-context-evaluation.json"),options:.atomic) }
            NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-native-memory") {
            Task {
                let result:[String:Any]
                do { result=try await NativeMemoryEvaluation.run(self) } catch { result=["error":error.localizedDescription,"storage":"Fictional data; disposable storage; sources never started"] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-native-memory-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--inspect-luna-access") {
            Task {
                let result:[String:Any]
                do {result=try await chatGPT.inspectLunaAccess()} catch {result=["error":error.localizedDescription,"personalSourcesSent":false,"selectedModel":chatGPT.selectedModel]}
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-luna-access.json"),options:.atomic)}
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-memory-inspection") {
            Task { await MemoryInspectionPreview.validate(self);NSApp.terminate(nil) };return
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-source-timeline") { return }
        if ProcessInfo.processInfo.arguments.contains("--validate-source-timeline") {
            Task {
                let result:[String:Any]
                do { result=try await SourceContextEvaluation.runTimeline(self) }
                catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format(),"storage":"Fictional data; disposable in-memory storage; sources never started"] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-source-timeline-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-images") || ProcessInfo.processInfo.arguments.contains("--preview-settings") { return }
        if ProcessInfo.processInfo.arguments.contains("--validate-images") {
            Task {
                let result:[String:Any]
                do { result=try await ChatImageEvaluation.run(self) } catch { result=["error":error.localizedDescription] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-image-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-mail-dates") {
            Task {
                let result=(try? await mail.validateDates()) ?? "Unavailable"
                try? Data(result.utf8).write(to:URL(fileURLWithPath:"/tmp/missioncontrol-mail-dates.json"),options:.atomic)
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-mail-monitoring") {
            Task {
                let result:[String:Any]
                do { result = try await mail.validateMonitoring() } catch { result = ["unavailable":true] }
                if let data = try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-mail-monitor-live.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-clean-notes") {
            Task {
                let report=await eventKit.validateCleanNotes()
                if let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]) {try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-clean-notes-native.json"),options:.atomic)}
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--cleanup-request-markers") {
            Task {
                let report=await assistantActions.cleanupRequestMarkers(self)
                if let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]) {try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-request-marker-cleanup.json"),options:.atomic)}
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--preview-projects") { return }
        if ProcessInfo.processInfo.arguments.contains("--validate-ownership") {
            Task {
                let result:[String:Any]
                do { result=try await LifeOwnershipEvaluation.run(self) } catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format()] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-ownership-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-placement") {
            Task {
                let result:[String:Any]
                do { result=try await LifePlacementEvaluation.run(self) } catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format()] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-placement-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }

        if ProcessInfo.processInfo.arguments.contains("--render-projects") {
            Task { try? await Task.sleep(for:.milliseconds(250)); await LifeProjectPreview.render(self); NSApp.terminate(nil) }; return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-projects") {
            Task {
                let result: [String:Any]
                do { result = try await LifeWorkspaceEvaluation.run(self) }
                catch { result = ["error":error.localizedDescription, "completed":Date.now.ISO8601Format()] }
                if let data = try? JSONSerialization.data(withJSONObject:result, options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-project-evaluation.json"), options:.atomic) }
                NSApp.terminate(nil)
            }; return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-native-editors") {
            Task { [self] in
                let result:String
                do {result=try await eventKit.validateNativeEditors()} catch {result=error.localizedDescription}
                try? Data(result.utf8).write(to:URL(fileURLWithPath:"/tmp/missioncontrol-native-editors-result.txt"),options:.atomic)
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-native-capabilities") {
            Task { [self] in
                let result:[String:Any]
                do {result=try await NativeCapabilitiesEvaluation.run(self)} catch {result=["error":error.localizedDescription]}
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-native-capabilities-evaluation.json"),options:.atomic)}
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-focus-workflow") {
            Task {
                let result:[String:Any]
                do { result=try await WorkflowEvaluation.run(self) }
                catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format()] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-workflow-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-source-context") {
            Task {
                let result:[String:Any]
                do { result=try await SourceContextEvaluation.run(self) }
                catch { result=["error":error.localizedDescription,"completed":Date.now.ISO8601Format()] }
                if let data=try? JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:EvaluationOutput.url("/tmp/missioncontrol-source-context-evaluation.json"),options:.atomic) }
                NSApp.terminate(nil)
            };return
        }
        if ProcessInfo.processInfo.arguments.contains("--render-weather") {
            Task { try? await Task.sleep(for:.milliseconds(250));WeatherWidgetPreview.render();NSApp.terminate(nil) };return
        }
        if ProcessInfo.processInfo.arguments.contains("--render-life-map") {
            Task { try? await Task.sleep(for:.milliseconds(250));LifeNotebookPreview.render();DateClockPreview.render();NSApp.terminate(nil) };return
        }
        if ProcessInfo.processInfo.arguments.contains("--validate-life-notebook") { validateLifeNotebook();return }
        #endif
        if !sample { whatsapp.resumeAtLaunch() }
        if sample { loadSample(); return }
        weather.startRefresh(allowPrompt:true)
        observers.append(NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sourceRevision += 1
                self.changes?.cancel()
                self.changes = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    self.widgetCalendars.invalidate(); await self.refreshCalendar(); await self.refreshReminders(); await self.refreshPAOrientation()
                }
            }
        })
        heartbeatPowerMonitor=HeartbeatPowerMonitor { [weak self] in if let self {self.heartbeat.deviceAvailabilityChanged(self)} }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { if let self {self.heartbeat.willSleep(self)} } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in if let self {self.refresh(retryMail:false);self.heartbeat.didWake(self)} } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in if let self {self.heartbeat.deviceAvailabilityChanged(self)} } })
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                self?.weather.startRefresh()
                if let self {await self.refreshMail()}
            }
        }
        nativePoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(900))
                guard !Task.isCancelled else {return}
                if let self {
                    async let orientation:Void=self.refreshPAOrientation()
                    async let reminders:Void=self.refreshReminders()
                    _ = await (orientation,reminders)
                }
            }
        }
        briefingPoll = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    self.heartbeat.check(self)
                    if !self.heartbeat.busy && !self.briefings.busy {
                        self.projectPlacement.check(self);self.memoryLearning.recoverDelivery(self);self.proactive.recoverDelivery(self)
                    }
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
        refresh(retryMail: false)
        scheduleReviewWork()
        heartbeat.check(self)
        if ProcessInfo.processInfo.arguments.contains("--validate-live") {
            Task {
                do { validationReport = try await eventKit.validateDisposableReminders() }
                catch { validationReport = "Live reminder validation failed: " + error.localizedDescription }
                persist("validationReport", validationReport)
                await refreshReminders()
            }
        }
    }
    func refresh(retryMail: Bool = true) {
        widgetCalendars.invalidate()
        if retryMail { mailIndex.resume() }
        guard !sample else { loadSample(); return }
        weather.startRefresh()
        Task { await refreshCalendar() }
        Task { await refreshReminders() }
        Task { await refreshPAOrientation() }
        Task { await refreshMail() }
    }
    func navigate(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        Task { await refreshCalendar() }
    }
    private var nativeCollectionScope: NativeCollectionScope {
        .init(registration:chatGPT.activeID,sourceRevision:sourceRevision,writeGeneration:nativeWriteGeneration,storage:container.map(ObjectIdentifier.init))
    }
    /// Only verified writes call this. Receipts are durable before collection begins.
    private func reconcileVerifiedNativeWrite(_ kind: NativeItemKind, owner: NativeCollectionScope) {
        nativeWriteGeneration += 1
        if kind == .event { widgetCalendars.invalidate();orientationCollectionRevision = -1 }
        else { reminderCollectionRevision = -1;completedReminderCollectionRevision = -1 }
        nativeReconciliation.schedule(kind == .event ? .calendar : .reminders) { [weak self] kind in
            guard let self,owner.registration == self.chatGPT.activeID,owner.storage == self.container.map(ObjectIdentifier.init) else { return }
            switch kind {
            case .calendar:
                await self.refreshCalendar()
                await self.refreshPAOrientation()
            case .reminders: await self.refreshReminders()
            }
        }
    }
    #if DEBUG
    /// Fictional source-reader regression only; this never performs a native write.
    func reconcileVerifiedNativeWriteFixture(_ kind: NativeItemKind) throws {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") else { throw IntegrationError.verification }
        reconcileVerifiedNativeWrite(kind,owner:nativeCollectionScope)
    }
    func finishNativeReconciliationFixture() async throws {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") else { throw IntegrationError.verification }
        await nativeReconciliation.waitForPending()
    }
    #endif
    func refreshCalendar() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-calendar-drag") { return }
        #endif
        guard !sample else { return }
        if calendarHealth.loading { pendingCalendarRefresh = true; return }
        calendarHealth.loading = true
        let start = selectedDate, ownership = nativeCollectionScope
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        let result = await NativeSourceCollection(snapshot: calendarData, health: calendarHealth).collecting {
            let snapshot = try await nativeSources.calendar(from: start, to: end)
            guard start == selectedDate else { throw NativeSourceReadError.unavailable("Selected calendar range changed") }
            return snapshot
        }
        guard ownership == nativeCollectionScope else {
            calendarHealth.loading=false
            if pendingCalendarRefresh { pendingCalendarRefresh=false;await refreshCalendar() }
            return
        }
        calendarData = result.snapshot; calendarHealth = result.health
        persistCollection("calendar", healthKey: "calendarHealth", snapshot: calendarData, health: calendarHealth)
        if pendingCalendarRefresh { pendingCalendarRefresh = false; await refreshCalendar() }
    }
    func refreshPAOrientation() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-calendar-drag") { return }
        #endif
        guard !sample, assistant.contextEnabled else { return }
        if paOrientationHealth.loading { pendingOrientationRefresh=true;return }
        lastOrientationCheck = .now; paOrientationHealth.loading = true
        let ownership=nativeCollectionScope
        let start = Calendar.current.startOfDay(for:.now), end = Calendar.current.date(byAdding:.day,value:90,to:start)!, revision = sourceRevision
        do {
            let snapshot = try await nativeSources.calendar(from:start,to:end)
            guard ownership == nativeCollectionScope else {
                paOrientationHealth.loading=false
                if pendingOrientationRefresh { pendingOrientationRefresh=false;await refreshPAOrientation() }
                return
            }
            paOrientation = PAOrientation(start:start,end:end,refreshed:.now,calendar:snapshot)
            paOrientationHealth = .init(lastSuccess:.now)
            orientationCollectionRevision = revision
            persist("paOrientation",paOrientation); persist("paOrientationHealth",paOrientationHealth)
        } catch { if ownership == nativeCollectionScope { paOrientationHealth.error = error.localizedDescription }; paOrientationHealth.loading = false }
        if pendingOrientationRefresh { pendingOrientationRefresh=false;await refreshPAOrientation() }
    }
    func refreshReminders() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-calendar-drag") { return }
        #endif
        guard !sample else { return }
        if reminderHealth.loading { pendingReminderRefresh = true; return }
        reminderHealth.loading = true
        let collectionRevision=sourceRevision,ownership=nativeCollectionScope
        let result = await NativeSourceCollection(snapshot: reminderData, health: reminderHealth).collecting {
            let snapshot = try await nativeSources.reminders()
            guard collectionRevision == sourceRevision else { throw NativeSourceReadError.unavailable("Reminders source choices changed") }
            return snapshot
        }
        guard ownership == nativeCollectionScope else {
            reminderHealth.loading=false
            if pendingReminderRefresh { pendingReminderRefresh=false;await refreshReminders() }
            return
        }
        reminderData = result.snapshot; reminderHealth = result.health
        if reminderHealth.error == nil {reminderCollectionRevision = collectionRevision}
        persistCollection("reminders", healthKey: "reminderHealth", snapshot: reminderData, health: reminderHealth)
        if reminderHealth.error == nil, assistant.contextEnabled {
            let completed = await NativeSourceCollection(snapshot: completedReminders, health: completedReminderHealth).collecting {
                let items = try await nativeSources.completedReminders(excluded: assistant.excludedLists)
                guard collectionRevision == sourceRevision else { throw NativeSourceReadError.unavailable("Completion source choices changed") }
                return items
            }
            guard ownership == nativeCollectionScope else {
                if pendingReminderRefresh { pendingReminderRefresh=false;await refreshReminders() }
                return
            }
            completedReminders = completed.snapshot; completedReminderHealth = completed.health
            if completed.health.error == nil {completedReminderCollectionRevision = collectionRevision}
        } else if !assistant.contextEnabled { completedReminders=[]; completedReminderHealth = .init() }
        if pendingReminderRefresh { pendingReminderRefresh = false; await refreshReminders() }
    }
    func validateCalendarIntegration() {
        Task {
            do { validationReport = try await eventKit.validateDisposableCalendarEvents() }
            catch { validationReport = "Calendar validation: " + error.localizedDescription }
            persist("validationReport", validationReport)
            await refreshCalendar()
        }
    }
    private func persistMailCheckpoint() {
        persist("mailCheckpoint", MailCheckpoint(snapshot: mailData, index: mailIndex))
    }
    func refreshMail() async {
        if ProcessInfo.processInfo.arguments.contains("--skip-mail") { mailHealth.error = "Mail paused for validation"; return }
        guard !sample, !mailHealth.loading else { return }
        mailHealth.loading = true
        defer { mailHealth.loading = false }
        do {
            let discovery = try await mail.discoverAccounts()
            let collection = try discovery.collection(retaining:mailData.accounts)
            let accounts = collection.accounts
            mailIndex.discovered()
            let enabled = Set(accounts.map(\.id))
            mailData = MailSnapshot(messages: mailData.messages.filter { enabled.contains($0.accountID) && $0.received >= Date.now.addingTimeInterval(-30 * 86400) }, accounts: accounts, errors: [])
            mailIndex.prepare(accounts: accounts,lastCheck:mailHealth.lastSuccess)
            for (id,error) in collection.failures {mailIndex.failed(id,detail:error)}
            persistMailCheckpoint()
            // All accounts get an arrival page before background work. Two arrival
            // pages/account/check; only one history/reconciliation page per five
            // minutes. Never recursively drain or rebuild the month's cache.
            for account in collection.healthy where mailIndex.available(account.id) {
                if let window = mailIndex.monitor(account.id) { try await readMailPage(window,account:account) }
            }
            for account in collection.healthy where mailIndex.available(account.id) {
                if let window = mailIndex.monitor(account.id) { try await readMailPage(window,account:account) }
                if mailIndex.available(account.id), let window = mailIndex.background(account.id) { try await readMailPage(window,account:account) }
            }
            mailHealth.error = accounts.compactMap { account in
                mailIndex.accountErrors?[account.id].map { account.title + " Inbox: " + $0 + " Cached mail retained; automatic retry backs off up to 30 minutes. Refresh retries now." }
            }.joined(separator:"; ")
            if mailHealth.error?.isEmpty == true { mailHealth.error = nil }
            if accounts.isEmpty { mailHealth.lastSuccess = .now }
            persistMailCheckpoint()
            persist("mailHealth", SourceHealth(lastSuccess:mailHealth.lastSuccess,error:mailHealth.error))
        } catch is CancellationError {
            // Keep completed pages and the interrupted cursor. Foreground
            // ownership is not an account outage and must not add backoff.
            persistMailCheckpoint()
        } catch {
            mailIndex.discovered(error:error.localizedDescription)
            mailHealth.error = error.localizedDescription + " Cached mail retained; monitoring retries on its next check."
            persistMailCheckpoint()
        }
    }
    func recordMailReadFailure(_ accountID:String,detail:String) {
        mailIndex.failed(accountID,detail:detail)
        mailHealth.error=mailData.accounts.compactMap{account in mailIndex.accountErrors?[account.id].map{account.title+": "+$0}}.joined(separator:"; ")
        persistMailCheckpoint()
    }
    private func readMailPage(_ window: MailWindowProgress, account: MailAccount) async throws {
        do {
            let batch = try await mail.batch(accountID:account.id,window:window,knownMessages:window.id.hasPrefix("monitor:") ? mailData.messages : nil)
            mailData = mailIndex.apply(batch,to:window.id,snapshot:mailData)
            mailHealth.lastSuccess = .now
        } catch is CancellationError {throw CancellationError()}
        catch {
            // Reset only a stale exact page, retaining cached rows and all other
            // account cursors. Transport failures keep their immutable ID list.
            if case MailServiceError.mail(let detail) = error,
               detail.contains("changed or moved") || detail.contains("-1728") {
                mailIndex.resetCursor(window.id)
            }
            mailIndex.failed(account.id,detail:error.localizedDescription)
        }
        persistMailCheckpoint()
    }
    func complete(_ reminder: TaskItem) {
        guard !sample, !writing else { return }
        let owner = nativeCollectionScope
        writing = true; writeError = nil
        Task {
            do {
                let baseline = try await eventKit.editSession(.reminder(reminder)).item
                undoToken = try await eventKit.complete(id: reminder.id, valid: {
                    owner.registration == self.nativeCollectionScope.registration && owner.storage == self.nativeCollectionScope.storage
                }, expected: baseline)
                undoTitle = reminder.title
                showFeedback("Completed: " + reminder.title)
                await refreshReminders()
            } catch { writeError = error.localizedDescription; await refreshReminders() }
            writing = false
        }
    }
    func newNativeItem(_ kind: NativeItemKind, date: Date? = nil) {
        editTarget = .create(NativeCreationRequest(kind:kind,registration:chatGPT.activeID,preferredDate:date))
    }
    func reviewDiscovery(_ record:PADiscovery,as kind:NativeItemKind? = nil) {
        guard proactive.preparedReviewAvailable(record,model:self),currentPreparedApproval(record),!record.needsDateClarification,record.registration == chatGPT.activeID,let id=UUID(uuidString:record.id) else { return }
        if let removal=record.proposedRemoval,let event=(paOrientation?.calendar ?? calendarData).events.first(where:{$0.id == removal.target.itemID}) {
            editTarget = .event(event);return
        }
        if record.proposedChange != nil {
            guard !writing,proactive.canReview(record.id,model:self),let current=proactive.state.records.first(where:{$0.id == record.id && $0.registration == record.registration}) else {return}
            editTarget=dateReviewTarget(current)
            return
        }
        let label:String,title:String
        if record.sourceKind == "whatsapp" { label="WhatsApp · " + (record.sourceLabel ?? "Selected chat");title=record.sourceTitle ?? "Follow up: " + (record.sourceLabel ?? "WhatsApp") }
        else {
            let message=mailData.messages.first(where:{$0.id == record.mailID}) ?? emailSummaries.records.first(where:{$0.id == record.mailID && $0.registration == record.registration})?.message
            label=record.sourceLabel ?? message.map{$0.account + " · " + $0.subject} ?? "Email";title=record.sourceTitle ?? message?.subject ?? "Follow up"
        }
        let selectedKind=kind ?? (record.kind == "calendar" ? .event : .reminder)
        editTarget = .create(NativeCreationRequest(id:id,kind:selectedKind,registration:record.registration,title:String(title.prefix(500)),notes:"Source: " + label + "\n" + record.evidence,discoveryID:record.id,discoveryApproval:preparedApprovalSnapshot(record),evidence:record.message + "\n\n" + label + ": " + record.evidence,requiresDateSelection:selectedKind == .event,suggestedStart:record.proposedDate?.date(),suggestedEnd:record.proposedDate?.end.flatMap{record.proposedDate?.date($0)},suggestedHasTime:record.proposedDate?.hasTime,suggestedTimeZone:record.proposedDate?.timeZoneID))
    }
    func dateReviewTarget(_ record:PADiscovery)->NativeEditTarget? {
        guard let change=record.proposedChange,let date=change.date() else {return nil}
        let review=NativeDateReview(discoveryID:record.id,registration:record.registration,date:date,hasTime:change.hasTime,expectedModified:change.target.modified,evidence:record.message+"\n\nWhy this item: "+change.connection+"\n\nSource: "+record.evidence,discoveryApproval:preparedApprovalSnapshot(record),expectedOccurrenceID:change.target.itemID,expectedSourceID:change.target.sourceID,expectedTitle:change.target.title,expectedStart:change.target.start,expectedEnd:removalEditorEnd(change.target),expectedDue:change.target.due,expectedHasTime:change.target.hasTime)
        if change.target.kind == "event",let item=(paOrientation?.calendar ?? calendarData).events.first(where:{$0.id == change.target.itemID}) {return .reviewEvent(item,review)}
        if change.target.kind == "reminder",let item=reminderData.reminders.first(where:{$0.id == change.target.itemID}) {return .reviewReminder(item,review)}
        return nil
    }
    func approveDiscovery(_ record:PADiscovery) async {
        if record.proposedRemoval != nil {await approveCalendarRemoval(record);return}
        guard !sample,!writing,!assistant.busy,approvingDiscoveryID == nil,
              record.registration == chatGPT.activeID,proactive.canReview(record.id,model:self),
              let current=proactive.state.records.first(where:{$0.id == record.id && $0.registration == record.registration}),
              currentPreparedApproval(record),
              let target=dateReviewTarget(current) else {return}
        let review:NativeDateReview
        switch target {case .reviewEvent(_,let value),.reviewReminder(_,let value):review=value;default:return}
        // Exact native/project evidence is rechecked by running AI consumers.
        approvingDiscoveryID=record.id;reviewApprovalError=nil;reviewApprovalErrorID=nil;reviewApprovalErrorAccount=nil;writing=true
        defer {writing=false;approvingDiscoveryID=nil}
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {throw ActionFailure.message("Fictional preview is read-only; no Apple write.")}
            #endif
            let session=try await eventKit.editSession(target)
            try Task.checkCancellation()
            guard review.registration == chatGPT.activeID,proactive.canReview(review.discoveryID,model:self),currentPreparedApproval(record) else {throw ActionFailure.message("The proposal changed. Reopen it before approving it.")}
            let edited=try review.applying(to:session.item)
            // A repeating item needs an explicit occurrence/series choice in the native form.
            if session.item.recurring {editTarget=target;return}
            writing=false
            try await saveNativeEdit(baseline:session.item,edited:edited,review:review)
        } catch {
            if review.registration == chatGPT.activeID {
                reviewApprovalError=error.localizedDescription;reviewApprovalErrorID=record.id;reviewApprovalErrorAccount=record.registration
            }
        }
    }
    private func approveCalendarRemoval(_ record:PADiscovery) async {
        guard !sample,!writing,!assistant.busy,approvingDiscoveryID == nil,record.registration == chatGPT.activeID,
              proactive.canReview(record.id,model:self),let current=proactive.state.records.first(where:{$0.id == record.id}),currentPreparedApproval(record),
              let removal=current.proposedRemoval,removal.valid,
              let event=(paOrientation?.calendar ?? calendarData).events.first(where:{$0.id == removal.target.itemID}) else {return}
        let selectedModel=chatGPT.selectedModel,sourceScope=proactive.sourceSettingsScope(self)
        // Exact native/project evidence is rechecked by running AI consumers.
        approvingDiscoveryID=record.id;reviewApprovalError=nil;reviewApprovalErrorID=nil;reviewApprovalErrorAccount=nil;writing=true
        defer {writing=false;approvingDiscoveryID=nil}
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {throw ActionFailure.message("Fictional preview is read-only; no Apple write.")}
            #endif
            let session=try await eventKit.editSession(.event(event))
            try Task.checkCancellation()
            try validateCalendarRemoval(record,baseline:session.item)
            if session.item.recurring {calendarRemovalReview = .init(record:record,baseline:session.item,selectedModel:selectedModel,sourceScope:sourceScope);return}
            writing=false
            try await saveCalendarRemoval(record,baseline:session.item,selectedModel:selectedModel,sourceScope:sourceScope)
        } catch {
            if record.registration == chatGPT.activeID {reviewApprovalError=error.localizedDescription;reviewApprovalErrorID=record.id;reviewApprovalErrorAccount=record.registration}
        }
    }
    func validateCalendarRemoval(_ record:PADiscovery,baseline:NativeEditDetails)throws {
        guard record.registration == chatGPT.activeID,proactive.canReview(record.id,model:self),
              currentPreparedApproval(record),let removal=record.proposedRemoval,removal.valid,
              baseline.kind == .event,baseline.writable,baseline.occurrenceID == removal.target.itemID,baseline.sourceID == removal.target.sourceID,
              baseline.title == removal.target.title,baseline.start == removal.target.start,baseline.end == removalEditorEnd(removal.target),
              !baseline.allDay == removal.target.hasTime,baseline.modified == removal.target.modified else {
            throw ActionFailure.message("The proposal or Calendar event changed. Reopen it before approving removal.")
        }
    }
    private func removalEditorEnd(_ target:DiscoveryNativeTarget)->Date? {
        guard let end=target.end,!target.hasTime else {return target.end}
        let day=Calendar.current.startOfDay(for:end)
        return end == day ? end : Calendar.current.date(byAdding:.day,value:1,to:day)
    }
    func saveCalendarRemoval(_ record:PADiscovery,baseline:NativeEditDetails,selectedModel:String,sourceScope:String,occurrenceConfirmed:Bool = false,additionalValidity:NativeWriteValidity? = nil) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {throw ActionFailure.message("Fictional preview is read-only; no Apple write.")}
        #endif
        guard !sample,!writing,(!assistant.busy || (reviewConversationOwnsAssistant && additionalValidity?() == true)),additionalValidity?() ?? true,!baseline.recurring || occurrenceConfirmed else {throw ActionFailure.message("Review the exact occurrence before removing a repeating event.")}
        try validateCalendarRemoval(record,baseline:baseline)
        let registration=record.registration,nativeOwner=nativeCollectionScope
        // Exact native/project evidence is rechecked by running AI consumers.
        writing=true;writeError=nil;defer {writing=false}
        var claimed=false
        do {
            let valid:NativeWriteValidity = { [self] in
                registration == chatGPT.activeID && nativeOwner.storage == nativeCollectionScope.storage && record.proposedRemoval?.valid == true &&
                currentPreparedApproval(record) && (additionalValidity?() ?? true)
            }
            let claim:NativeWriteClaim = { [self] in
                guard valid() else {throw ActionFailure.message("Removal ownership changed before the save claim.")}
                try validateCalendarRemoval(record,baseline:baseline)
                try proactive.beginReview(record.id,model:self);claimed=true
            }
            let result=try await eventKit.deleteItem(baseline:baseline,scope:.occurrence,valid:valid,claim:claim)
            editUndo=nil;widgetCalendars.invalidate()
            try proactive.finishReview(record.id,registration:registration)
            showFeedback(result)
            reconcileVerifiedNativeWrite(.event,owner:nativeOwner)
        } catch {
            if error is NativePreSaveFailure,claimed {try? proactive.abortReview(record.id,registration:registration)}
            // Removal may have succeeded even if verification or receipt storage failed.
            if claimed {widgetCalendars.invalidate();reconcileVerifiedNativeWrite(.event,owner:nativeOwner)}
            writeError=error.localizedDescription;throw error
        }
    }
    /// Capture only what the person is approving. Supporting context is reviewed by
    /// heartbeats; it is not new authority and need not be reread during an approval.
    func preparedApprovalSnapshot(_ record:PADiscovery)->Data? {
        struct Approval:Encodable {
            var id:String;var registration:String;var kind:String;var title:String?
            var message:String;var evidence:String
            var date:DiscoveryProposedDate?;var change:DiscoveryDateChange?
            var removal:DiscoveryCalendarRemoval?;var project:DiscoveryProjectTask?;var replyDraft:String?
            var calendar:[String:String]?
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let calendar=record.proposedCalendarDestination.map { destination in
            var value=["sourceID":destination.sourceID,"account":destination.account]
            if let provider=destination.providerID {value["providerID"]=provider}
            return value
        }
        return try? encoder.encode(Approval(id:record.id,registration:record.registration,kind:record.kind,title:record.sourceTitle,message:record.message,evidence:record.evidence,date:record.proposedDate,change:record.proposedChange,removal:record.proposedRemoval,project:record.proposedProjectTask,replyDraft:record.replyDraft,calendar:calendar))
    }
    func currentPreparedApproval(_ record:PADiscovery)->Bool {
        guard let snapshot=preparedApprovalSnapshot(record) else {return false}
        return currentPreparedApproval(record.id,registration:record.registration,snapshot:snapshot)
    }
    private func currentPreparedApproval(_ id:String,registration:String,snapshot:Data?)->Bool {
        guard registration == chatGPT.activeID,let snapshot,
              let current=proactive.state.records.first(where:{$0.id == id && $0.registration == registration}),
              proactive.preparedReviewAvailable(current,model:self) else {return false}
        return preparedApprovalSnapshot(current) == snapshot
    }
    func validatePreparedApproval(_ record:PADiscovery)throws {
        guard currentPreparedApproval(record) else {throw ActionFailure.message("This suggestion changed. Reopen it from Review inbox.")}
    }
    func savePreparedProjectItem(_ value:LifeItem,proposal:PADiscovery,additionalValidity:(@MainActor ()->Bool)? = nil,acceptedSnapshot:ReviewPreparedPayload? = nil)throws {
        guard !writing,(!assistant.busy || (acceptedSnapshot != nil && reviewConversationOwnsAssistant && additionalValidity?() == true)),!assistant.projects.readOnly,value.registration == chatGPT.activeID,
              value.registration == proposal.registration else {throw LifeWorkspaceFailure.message("Another operation or account change is in progress. Your draft is kept.")}
        guard additionalValidity?() ?? true else {throw LifeWorkspaceFailure.message("This request stopped before saving.")}
        if let acceptedSnapshot {guard acceptedPreparedApproval(acceptedSnapshot) else {throw LifeWorkspaceFailure.message("The approved concrete action changed.")}} else {try validatePreparedApproval(proposal)}
        guard proposal.reviewState == nil else {throw LifeWorkspaceFailure.message("This suggestion already has a save recorded.")}
        if let parent=value.parentID {
            guard assistant.projects.items(value.registration,includeTopics:true).contains(where:{$0.id == parent && $0.conversationID == value.conversationID && !$0.kind.isWork && $0.ownership != "life" && $0.status != .archived}) else {throw LifeWorkspaceFailure.message("The chosen destination is no longer an available space. Choose another destination.")}
        }
        // Exact native/project evidence is rechecked by running AI consumers.
        var item=value;item.humanEvidence="Accepted a reviewed PA " + item.kind.title.lowercased() + " suggestion."
        let reference:LifeReference?
        if proposal.sourceKind == "whatsapp",let chat=proposal.sourceChatID,let message=proposal.sourceMessageID,let identity=proposal.sourceIdentity,let version=proposal.sourceRevision {
            reference = .init(kind:.whatsapp,id:message,containerID:chat,linkedIdentity:identity,contentRevision:version)
        } else if let message=mailData.messages.first(where:{$0.id == proposal.mailID}) ?? emailSummaries.records.first(where:{$0.id == proposal.mailID && $0.registration == proposal.registration})?.message {
            reference = .init(kind:.mail,id:message.id,containerID:message.accountID,contentRevision:message.internetMessageID)
        } else {reference=nil}
        // Source links explain origin; unavailable source metadata cannot veto a human action.
        let links=reference.map{[LifeItemLink(registration:item.registration,conversationID:item.conversationID,from:item.id,relation:.evidence,target:$0)]} ?? []
        _ = try assistant.projects.create([item],receipt:.init(id:"project-suggestion:"+proposal.id,registration:item.registration,result:"Created a human-reviewed " + item.kind.title.lowercased() + ".",itemID:item.id),links:links)
    }
    func createNativeItem(_ request: NativeCreationRequest, baseline: NativeEditDetails, edited: NativeEditDetails, dateSelected: Bool,additionalValidity:(@MainActor ()->Bool)? = nil,acceptedSnapshot:ReviewPreparedPayload? = nil) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {throw ActionFailure.message("Fictional preview is read-only; no Apple write.")}
        #endif
        guard !sample, !writing, (!assistant.busy || (acceptedSnapshot != nil && reviewConversationOwnsAssistant && additionalValidity?() == true)), request.registration == chatGPT.activeID,additionalValidity?() ?? true else { throw ActionFailure.message("Another change or account switch is in progress; reopen the form when ready.") }
        if request.requiresDateSelection && !dateSelected { throw ActionFailure.message("Choose the event's date and time before creating it.") }
        // The explicit action owns the foreground; saved context is not re-analysed.
        // Exact native/project evidence is rechecked by running AI consumers.
        writing=true;defer {writing=false}
        if let discovery=request.discoveryID {
            guard acceptedSnapshot.map(acceptedPreparedApproval) ?? (currentPreparedApproval(discovery,registration:request.registration,snapshot:request.discoveryApproval) && proactive.canReview(discovery,model:self)) else {throw ActionFailure.message("This suggestion changed or already has a save recorded. Reopen it before creating anything.")}
        }
        let nativeOwner=nativeCollectionScope
        let ownedStorage=nativeOwner.storage,sourceScope=proactive.sourceSettingsScope(self)
        try NativeCreationRules.validate(request:request,baseline:baseline,edited:edited)
        try nativeCreations.begin(request)
        writeError = nil; nativeWriteFeedback = nil
        do {
            let receipt = try await eventKit.createItem(request:request,baseline:baseline,edited:edited,scope:sourceScope,valid:{request.registration == self.chatGPT.activeID && ownedStorage == self.nativeCollectionScope.storage && (!self.assistant.busy || (acceptedSnapshot != nil && self.reviewConversationOwnsAssistant)) && (additionalValidity?() ?? true) && (acceptedSnapshot.map(self.acceptedPreparedApproval) ?? (request.discoveryID.map{self.currentPreparedApproval($0,registration:request.registration,snapshot:request.discoveryApproval)} ?? true))})
            try nativeCreations.complete(request,receipt:receipt)
            showFeedback("Created " + receipt.title + " · " + receipt.destination)
            reconcileVerifiedNativeWrite(request.kind,owner:nativeOwner)
        } catch let failure as NativePreSaveFailure {
            do {try nativeCreations.failedBeforeSave(request,failure:failure)}
            catch {
                let text="No Apple save was attempted, but its failure checkpoint could not be saved. The pending creation is retained; check it before trying again."
                writeError=text;throw PANativeActionUncertainty(operationKey:request.key,message:text)
            }
            let text=failure.localizedDescription+" No item was created. Correct the form or reload its source, then choose Create again when ready."
            writeError=text;throw NativePreSaveFailure(message:text)
        } catch {
            let text = error.localizedDescription + " Check Apple Calendar or Reminders before creating another item; this save will not be repeated automatically."
            writeError = text; throw ActionFailure.message(text)
        }
    }
    func moveCalendarEvent(_ event: AgendaEvent, to start: Date, valid: NativeWriteValidity? = nil) async throws {
        guard !writing, !assistant.busy, valid?() ?? true else { throw ActionFailure.message("Calendar controls changed or another operation is running; the event was not moved.") }
        let session = try await eventKit.editSession(.event(event))
        guard valid?() ?? true, session.item.modified == event.modified else { throw IntegrationError.missing }
        let proposal = NativeEventMoveProposal(occurrenceID:event.id,sourceID:event.calendarID,originalStart:event.start,originalEnd:event.end,start:start)
        let edited = try NativeEditRules.moved(session.item,proposal:proposal)
        // A pointer drag selects one visible occurrence, never the whole series.
        try await saveNativeEdit(baseline:session.item,edited:edited,scope:.occurrence,validity:valid)
    }
    func saveNativeEdit(baseline: NativeEditDetails, edited: NativeEditDetails, scope: NativeChangeScope = .occurrence,review:NativeDateReview? = nil,validity:NativeWriteValidity? = nil) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {throw ActionFailure.message("Fictional preview is read-only; no Apple write.")}
        #endif
        guard !sample, !writing, (!assistant.busy || (review != nil && reviewConversationOwnsAssistant && validity?() == true)) else { throw ActionFailure.message("Another change is in progress; wait before saving.") }
        // Exact native/project evidence is rechecked by running AI consumers.
        writing = true; writeError = nil
        defer { writing = false }
        let nativeOwner=nativeCollectionScope
        var claimedReview=false
        do {
            let valid:NativeWriteValidity = { [self] in
                nativeOwner.registration == chatGPT.activeID && nativeOwner.storage == nativeCollectionScope.storage && (validity?() ?? true) && (review.map{$0.registration == chatGPT.activeID && $0.expectedModified == baseline.modified && currentPreparedApproval($0.discoveryID,registration:$0.registration,snapshot:$0.discoveryApproval)} ?? true)
            }
            let claim:NativeWriteClaim = { [self] in if let review {
                guard review.registration == chatGPT.activeID else {throw ActionFailure.message("Review account changed; reopen the inbox.")}
                try proactive.beginReview(review.discoveryID,model:self);claimedReview=true
            } }
            let saved = try await eventKit.saveEdit(baseline:baseline,edited:edited,scope:scope,valid:valid,claim:review == nil ? nil : claim)
            editUndo = NativeEditRules.supportsUndo(baseline:baseline,edited:edited,scope:scope) ? NativeEditUndo(original:baseline,saved:saved) : nil
            if saved.kind == .event { widgetCalendars.invalidate() }
            do {if let review {try proactive.finishReview(review.discoveryID,registration:review.registration)}}
            catch {reconcileVerifiedNativeWrite(saved.kind,owner:nativeOwner);throw error}
            showFeedback("Updated: " + saved.title)
            reconcileVerifiedNativeWrite(saved.kind,owner:nativeOwner)
        } catch {
            if error is NativePreSaveFailure,claimedReview,let review {try? proactive.abortReview(review.discoveryID,registration:review.registration)}
            writeError = error.localizedDescription;throw error
        }
    }
    func deleteNativeItem(baseline: NativeEditDetails, scope: NativeChangeScope, requestID: UUID) async throws {
        guard !sample, !writing, !assistant.busy else { throw ActionFailure.message("Another change is in progress.") }
        writing=true;defer {writing=false}
        let result=try await assistantActions.performNativeDeletion(baseline:baseline,scope:scope,requestID:requestID,model:self)
        editUndo=nil;showFeedback(result);widgetCalendars.invalidate()
        await refreshCalendar();await refreshReminders();await refreshPAOrientation()
    }
    func clearNativeEditUndo() { editUndo=nil }
    func recordAssistantEditUndo(_ receipt: NativeEditUndo) { editUndo = receipt; widgetCalendars.invalidate() }
    func showFeedback(_ text: String) { nativeWriteFeedback = .init(registration:chatGPT.activeID,message:text) }
    var latestUndo: String? {
        UndoOrder.latest(layout:workspace.canUndo ? workspace.undoDate : nil,completion:undoToken == nil ? nil : completionUndoDate,edit:editUndo?.created,email:emailSummaries.undoDate(chatGPT.activeID),discovery:proactive.undoDate(chatGPT.activeID),question:memoryLearning.undoDate(chatGPT.activeID),project:assistant.projects.undoDate(chatGPT.activeID),memoryReview:memoryMaintenance.undoDate(chatGPT.activeID),reviewQuestion:briefings.undoQuestionDate(chatGPT.activeID),activity:aiActivity.undoDate(chatGPT.activeID))
    }
    var latestUndoDate: Date? {
        switch latestUndo {
        case "activity":return aiActivity.undoDate(chatGPT.activeID)
        case "layout": return workspace.undoDate
        case "completion": return completionUndoDate
        case "edit": return editUndo?.created
        case "email": return emailSummaries.undoDate(chatGPT.activeID)
        case "discovery": return proactive.undoDate(chatGPT.activeID)
        case "question": return memoryLearning.undoDate(chatGPT.activeID)
        case "reviewQuestion": return briefings.undoQuestionDate(chatGPT.activeID)
        case "memoryReview": return memoryMaintenance.undoDate(chatGPT.activeID)
        case "project": return assistant.projects.undoDate(chatGPT.activeID)
        default: return nil
        }
    }
    var undoLabel: String {
        switch latestUndo {
        case "activity":return aiActivity.undoLabel(chatGPT.activeID) ?? "Undo acknowledgement"
        case "edit": return "Undo edit"
        case "completion": return "Undo reminder completion"
        case "layout": return "Undo dashboard change"
        case "email": return "Undo email dismissal"
        case "discovery": return "Undo suggestion dismissal"
        case "question","reviewQuestion": return "Undo question dismissal"
        case "memoryReview": return "Undo memory review dismissal"
        case "project": return "Undo project edit"
        default: return "Undo"
        }
    }
    func undoAssistantAppleChange() async throws -> String {
        guard !sample, !writing else { throw ActionFailure.message("Another write is in progress.") }
        let latest = UndoOrder.latest(layout:nil,completion:undoToken == nil ? nil : completionUndoDate,edit:editUndo?.created)
        guard latest != nil else { throw ActionFailure.message("No supported Apple edit/completion remains to undo. Creation/deletion are outside this Undo.") }
        writing = true; defer { writing = false }
        let result: String
        if latest == "edit", let ticket = editUndo {
            try await eventKit.undoEdit(ticket); editUndo = nil; widgetCalendars.invalidate(); result = "Edit undone: " + ticket.original.title
        } else if let token = undoToken {
            try await eventKit.undo(token:token); undoToken = nil; result = "Reminder restored: " + undoTitle
            do { try assistantActions.recordUndo(token:token) } catch { writeError = "Reminder restored; action receipt update failed.";throw error }
        } else { throw ActionFailure.message("Undo receipt is unavailable.") }
        showFeedback(result); await refreshCalendar(); await refreshReminders(); await refreshPAOrientation(); return result
    }
    func undoLatest() {
        guard !writing, !assistant.busy else { return }
        if latestUndo == "activity" {_ = aiActivity.undoAcknowledgement(chatGPT.activeID);return}
        if latestUndo == "project" {
            do { try assistant.projects.undo(chatGPT.activeID); showFeedback("Project edit undone") } catch { writeError = error.localizedDescription }
            return
        }
        if latestUndo == "memoryReview" { memoryMaintenance.undo(chatGPT.activeID); return }
        if latestUndo == "email" { emailSummaries.undoDismiss(self); return }
        if latestUndo == "discovery" { proactive.undo(self); return }
        if latestUndo == "question" { memoryLearning.undoQuestion(chatGPT.activeID); return }
        if latestUndo == "reviewQuestion" { briefings.undoQuestion(chatGPT.activeID);return }
        if latestUndo == "layout" { workspace.undo(); if workspace.error == nil { showFeedback("Dashboard change undone") }; return }
        if latestUndo == "completion" { undo(); return }
        guard latestUndo == "edit", let ticket = editUndo else { return }
        writing = true; writeError = nil
        Task {
            defer { writing = false }
            do {
                try await eventKit.undoEdit(ticket); editUndo = nil; showFeedback("Edit undone: " + ticket.original.title)
                widgetCalendars.invalidate(); await refreshCalendar(); await refreshReminders(); await refreshPAOrientation()
            } catch { writeError = "Could not undo the edit. The item may have changed outside 3PO. " + error.localizedDescription }
        }
    }
    func undo() {
        guard let token = undoToken, !writing else { return }
        writing = true; writeError = nil
        Task {
            do {
                try await eventKit.undo(token: token); undoToken = nil
                showFeedback("Reminder restored: " + undoTitle)
                do { try assistantActions.recordUndo(token:token) } catch { writeError = "Reminder restored; its action receipt could not be updated." }
                await refreshReminders()
            }
            catch { writeError = error.localizedDescription; await refreshReminders() }
            writing = false
        }
    }
    func select(_ message: MailMessage) {
        previewTask?.cancel()
        selectedMessage = message; preview = ""; previewError = nil; previewLoading = true
        previewTask = Task {
            do {
                let body = try await mail.body(accountID: message.accountID, messageID: message.messageID, expectedInternetMessageID: message.internetMessageID, mailboxName:message.mailboxName)
                guard !Task.isCancelled, selectedMessage?.id == message.id else { return }
                preview = body.isEmpty ? "This message has no plain-text body." : body
            } catch {
                guard !Task.isCancelled, selectedMessage?.id == message.id else { return }
                previewError = error.localizedDescription
            }
            previewLoading = false
        }
    }
    func openMessage(_ message: MailMessage) {
        guard !message.internetMessageID.isEmpty else { writeError = "This message has no Internet Message-ID. Open it in Mail using its subject."; return }
        let identifier = message.internetMessageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@._-"))
        if let encoded = identifier.addingPercentEncoding(withAllowedCharacters: allowed), let url = URL(string: "message://%3C\(encoded)%3E") { NSWorkspace.shared.open(url) }
    }
    var visibleEvents: [AgendaEvent] { calendarData.events.filter { !excludedCalendars.contains($0.calendarID) } }
    var visibleReminders: [TaskItem] { reminderData.reminders.filter { !excludedLists.contains($0.listID) } }
    var visibleMessages: [MailMessage] { mailData.messages.filter { !excludedAccounts.contains($0.accountID) }.sorted { $0.received > $1.received } }
    private func saveFilters() {
        guard !loadingFilters else {return}
        UserDefaults.standard.set(Array(excludedCalendars), forKey: "excludedCalendars")
        UserDefaults.standard.set(Array(excludedLists), forKey: "excludedLists")
        UserDefaults.standard.set(Array(excludedAccounts), forKey: "excludedAccounts")
    }
    private func persistCollection<Value: Encodable>(_ key: String, healthKey: String, snapshot: Value, health: SourceHealth) {
        guard !sample, let container else { return }
        do { try LocalRecordRepository(container: container).write([key: JSONEncoder().encode(snapshot), healthKey: JSONEncoder().encode(health)]) }
        catch { storageError = "Source checkpoint could not be saved: " + error.localizedDescription }
    }
    private func persist<T: Encodable>(_ key: String, _ value: T) {
        guard !sample, let container else { return }
        do { try LocalRecordRepository(container: container).save(value, key: key) }
        catch { storageError = "Cache could not be saved: " + error.localizedDescription }
    }
    private func restore() {
        guard !sample, let container else { return }
        let repository = LocalRecordRepository(container: container)
        func read<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
            do { return try repository.decode(key, as: type) }
            catch { storageError = "Saved source cache could not be read; original record retained: " + error.localizedDescription; return nil }
        }
        paOrientation = read("paOrientation",PAOrientation.self)
        paOrientationHealth = read("paOrientationHealth",SourceHealth.self) ?? paOrientationHealth
        if paOrientation != nil { paOrientationHealth.error = "Cached data · refresh pending" }
        calendarData = read("calendar", CalendarSnapshot.self) ?? calendarData
        reminderData = read("reminders", ReminderSnapshot.self) ?? reminderData
        mailData = read("mail", MailSnapshot.self) ?? mailData
        mailIndex = read("mailIndex", MailIndexState.self) ?? mailIndex
        if let checkpoint = read("mailCheckpoint", MailCheckpoint.self) {
            mailData = checkpoint.snapshot; mailIndex = checkpoint.index
        }
        calendarHealth = read("calendarHealth", SourceHealth.self) ?? calendarHealth
        reminderHealth = read("reminderHealth", SourceHealth.self) ?? reminderHealth
        mailHealth = read("mailHealth", SourceHealth.self) ?? mailHealth
        for key in ["calendar", "reminders", "mail"] {
            switch key {
            case "calendar": if calendarHealth.lastSuccess != nil { calendarHealth.error = "Cached data · refresh pending" }
            case "reminders": if reminderHealth.lastSuccess != nil { reminderHealth.error = "Cached data · refresh pending" }
            default: if mailHealth.lastSuccess != nil { mailHealth.error = "Cached data · refresh pending" }
            }
            }
    }
    private func loadSample() {
        calendarData = SampleCalendarService().snapshot()
        reminderData = SampleReminderService().snapshot()
        mailData = SampleMailService().snapshot()
    }
}

struct AssistantFocusRequest: Equatable {
    let id = UUID()
    let widgetID: UUID
}


extension DashboardModel: NativeActionRuntime {
    var actionRegistration: String { chatGPT.activeID }
    var actionContextEnabled: Bool { assistant.contextEnabled }
    var actionAssistantBusy: Bool { assistant.busy }
    var actionExcludedCalendars: Set<String> { assistant.excludedCalendars }
    var actionExcludedLists: Set<String> { assistant.excludedLists }
    var nativeActionWriter: any NativeActionWriting { eventKit }
}
