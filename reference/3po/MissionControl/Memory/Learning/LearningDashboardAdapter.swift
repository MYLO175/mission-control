import Foundation

extension AssistantService: LearningAssistantReading {}
extension WhatsAppService: WhatsAppLearningReading {}

@MainActor extension DashboardModel {
    func learningRuntime(heartbeatRequest request:HeartbeatChildRequest? = nil) -> LearningRuntime {
        let runtime = LearningRuntime(assistant: assistant, inference: chatGPT, learningBudget: learningBudget, whatsapp: whatsapp,
            activity: { [weak self] in
                guard let self else { return .unavailable }
                var lanes = Set<LearningLane>()
                if memoryLearning.busy { lanes.insert(.conversation) }
                if nativeSourceLearning.busy { lanes.insert(.nativeSources) }
                if sourceLearning.busy { lanes.insert(.whatsapp) }
                if lifeOrganisation.busy { lanes.insert(.organisation) }
                if memoryMaintenance.busy { lanes.insert(.maintenance) }
                return LearningActivity(otherWorkBusy: (heartbeat.busy && !(request.map{self.heartbeat.ownsLearningRun($0.runID)} ?? false)) || projectPlacement.busy || proactive.busy || briefings.busy || emailSummaries.busy, lanes: lanes)
            }, writing: { [weak self] in self?.writing ?? true },
            sourceRevision: { [weak self] in self?.sourceRevision ?? .min },
            nativeItems: { [weak self] kind, now in
                guard let self else {return nil}
                if kind == .mail,let request {
                    return NativeSourceAdapters.collectedMail(self.mailData,index:self.mailIndex,summaries:self.emailSummaries.records,registration:self.chatGPT.activeID,excluded:self.assistant.excludedAccounts,now:now,scope:request.mailReview)
                }
                return self.nativeLearningItems(kind,now:now)
            },ownership:request.map{value in .init(runID:value.runID,validate:value.validate,claim:value.claim)},
            reviewNativePermission:{[weak self] kind in
                guard let self,self.assistant.contextEnabled else {return false}
                switch kind {
                case .calendar,.reminder:return true
                case .mail:return self.emailSummaries.enabled
                case .whatsapp:return false
                }
            },reviewWhatsAppPermission:{[weak self] in
                guard let self else {return false}
                let access=self.whatsapp.access(for:self.chatGPT.activeID)
                return access.briefEnabled || access.includeInSuggestions == true || self.heartbeat.whatsappEnabled
            },reviewWhatsAppRevision:{[weak self] in self?.heartbeat.whatsappLearningAccessRevision})
        runtime.canOfferQuestion = { [weak self] registration, now in
            guard let self else { return false }
            return !self.contextQuestions.questions(registration: registration, includeFinished: true).contains { BriefingRules.day($0.created) == BriefingRules.day(now) }
        }
        return runtime
    }
}

@MainActor extension MemoryLearningService {
    func check(_ model: DashboardModel, manual: Bool = false) { check(model.learningRuntime(), manual: manual) }
    func recoverDelivery(_ model: DashboardModel) { recoverDelivery(model.learningRuntime()) }
    #if DEBUG
    func validate(_ model: DashboardModel) async throws -> String { try await validate(model.learningRuntime()) }
    #endif
}
@MainActor extension SourceContextLearningService {
    func lastAssessment(_ model: DashboardModel) -> Date { lastAssessment(model.learningRuntime()) }
    func status(_ model: DashboardModel) -> String { status(model.learningRuntime()) }
    func check(_ model: DashboardModel, manual: Bool = false) { check(model.learningRuntime(), manual: manual) }
}
@MainActor extension NativeSourceLearningService {
    func setEnabled(_ value: Bool, kind: MemorySourceKind, model: DashboardModel) { setEnabled(value, kind: kind, model: model.learningRuntime()) }
    func permits(_ record: PAMemory, model: DashboardModel) -> Bool { permits(record, model: model.learningRuntime()) }
    func status(_ kind: MemorySourceKind, model: DashboardModel) -> String { status(kind, model: model.learningRuntime()) }
    func check(_ model: DashboardModel, kind: MemorySourceKind? = nil, manual: Bool = false) { check(model.learningRuntime(), kind: kind, manual: manual) }
}
@MainActor extension LifeOrganisationService {
    func summary(_ model: DashboardModel) -> String { summary(model.learningRuntime()) }
    func check(_ model: DashboardModel, manual: Bool = false, topic: UUID? = nil) { check(model.learningRuntime(), manual: manual, topic: topic) }
}
@MainActor extension MemoryMaintenanceService {
    func check(_ model: DashboardModel, manual: Bool = false) { check(model.learningRuntime(), manual: manual) }
}

@MainActor extension DashboardModel {
    /// One fair automatic lane over already collected sources. Explicit heartbeat is not Review once.
    func runHeartbeatLearning(request:HeartbeatChildRequest) async throws->HeartbeatLearningResult {
        try request.validate()
        let runtime=learningRuntime(heartbeatRequest:request)
        for lane in BackgroundLearningPolicy.orderedLanes(receipts:learningBudget.receipts(request.registration),now:runtime.now()) {
            try request.validate()
            if lane == .whatsapp && !request.whatsappReady {continue}
            let before=learningBudget.revision
            switch lane {
            case .conversation:memoryLearning.check(runtime)
            case .nativeSources:nativeSourceLearning.check(runtime)
            case .whatsapp:sourceLearning.check(runtime)
            case .organisation:lifeOrganisation.check(runtime)
            case .maintenance:memoryMaintenance.check(runtime)
            }
            guard before != learningBudget.revision else {continue}
            func busy()->Bool {switch lane {
            case .conversation:return memoryLearning.busy
            case .nativeSources:return nativeSourceLearning.busy
            case .whatsapp:return sourceLearning.busy
            case .organisation:return lifeOrganisation.busy
            case .maintenance:return memoryMaintenance.busy
            }}
            do {
                while busy() {try Task.checkCancellation();try await Task.sleep(for:.milliseconds(100))}
                try request.validate()
            } catch {
                switch lane {
                case .conversation:await memoryLearning.cancelAndWait(heartbeatRunID:request.runID)
                case .nativeSources:await nativeSourceLearning.cancelAndWait(heartbeatRunID:request.runID)
                case .whatsapp:await sourceLearning.cancelAndWait(heartbeatRunID:request.runID)
                case .organisation:await lifeOrganisation.cancelAndWait(heartbeatRunID:request.runID)
                case .maintenance:await memoryMaintenance.cancelAndWait(heartbeatRunID:request.runID)
                }
                throw error
            }
            let error:String?
            switch lane {
            case .conversation:error=memoryLearning.error
            case .nativeSources:error=nativeSourceLearning.error
            case .whatsapp:error=sourceLearning.error
            case .organisation:error=lifeOrganisation.error
            case .maintenance:error=memoryMaintenance.error
            }
            return .init(lane:lane,failure:error,detail:error == nil ? "One bounded \(lane.rawValue) learning pass completed; saved evidence and organisation retained." : "Learning paused after a failed or interrupted pass; completed facts retained.",skipped:false)
        }
        return .init(detail:"No eligible learning pass: existing permissions, paused claims, pending deltas and shared learning allowance are preserved.")
    }
    func cancelHeartbeatLearning(runID:String) {
        if memoryLearning.ownedHeartbeatRunID == runID {memoryLearning.cancel()}
        if nativeSourceLearning.ownedHeartbeatRunID == runID {nativeSourceLearning.cancel()}
        if sourceLearning.ownedHeartbeatRunID == runID {sourceLearning.cancel()}
        if lifeOrganisation.ownedHeartbeatRunID == runID {lifeOrganisation.cancel()}
        if memoryMaintenance.ownedHeartbeatRunID == runID {memoryMaintenance.cancel()}
    }
}
