import Foundation

extension EmailSummaryService {
    @discardableResult func submitReviewFeedback(_ source:ReviewFeedbackEmail,words:String,about:String,model:DashboardModel)->Bool {
        guard feedbackSourceCurrent(source.message,summary:source.summary,model:model),model.assistant.memory.canSaveReviewPreference,let body=source.summary.bodyFingerprint else {feedback.error="The email or account changed. Your words are still here; reopen Feedback before saving.";return false}
        let job=ReviewFeedbackJob(registration:model.chatGPT.activeID,messageID:source.message.id,accountID:source.message.accountID,headerFingerprint:source.summary.fingerprint,bodyFingerprint:body,assessmentVersion:ReviewAcknowledgementRules.emailVersion(source.message,source.summary),model:model.chatGPT.selectedModel,sourceRevision:model.sourceRevision,words:words,about:about,heartbeatEligible:true,sourceSettings:model.proactive.sourceSettingsScope(model),adviceRevision:source.summary.adviceRevision(replied:source.message.replied))
        if let previous=feedback.latest(job.registration,messageID:job.messageID),previous.pending,feedbackMemory(previous,model:model) != nil {guard feedback.markSaved(previous.id) else {return false}}
        guard feedback.submit(job) else {return false}
        return true
    }
    private func feedbackSource(_ job:ReviewFeedbackJob,model:DashboardModel)->ReviewFeedbackEmail? {
        guard enabled,let message=model.mailData.messages.first(where:{$0.id == job.messageID && $0.accountID == job.accountID}),let summary=current(message,model:model),job.matches(message:message,summary:summary,registration:model.chatGPT.activeID,model:model.chatGPT.selectedModel,sourceRevision:model.sourceRevision,sourceSettings:model.proactive.sourceSettingsScope(model)),feedbackSourceCurrent(message,summary:summary,model:model) else {return nil}
        return .init(message:message,summary:summary)
    }
    func feedbackMemory(_ job:ReviewFeedbackJob,model:DashboardModel)->PAMemory? {
        guard job.registration == model.chatGPT.activeID else {return nil}
        return model.assistant.memory.records.first{$0.id == job.memoryID && $0.registration == job.registration && $0.reviewPreference == true && $0.reviewFeedback == job.words.trimmingCharacters(in:.whitespacesAndNewlines)}
    }
    @discardableResult func retryFeedback(_ job:ReviewFeedbackJob,model:DashboardModel)->Bool {
        guard feedback.activeID != job.id,feedback.records.first(where:{$0.id == job.id}) == job,job.registration == model.chatGPT.activeID,!job.pending else {return false}
        if feedbackMemory(job,model:model) != nil {return feedback.markSaved(job.id)}
        var retry=job;retry.activityAttemptID=UUID();retry.model=model.chatGPT.selectedModel;retry.sourceRevision=model.sourceRevision;retry.state = .queued;retry.error=nil;retry.heartbeatEligible=true;retry.sourceSettings=model.proactive.sourceSettingsScope(model)
        guard feedbackSource(retry,model:model) != nil else {feedback.error="This email changed or is unavailable. Your feedback is retained; submit new feedback from its current review.";return false}
        guard feedback.replaceForRetry(retry) else {return false}
        return processFeedbackNow(retry,model:model)
    }
    @discardableResult func saveFeedbackWords(_ job:ReviewFeedbackJob,model:DashboardModel)->Bool {
        guard feedback.activeID != job.id,feedback.records.first(where:{$0.id == job.id}) == job,job.registration == model.chatGPT.activeID,!job.pending,job.state != .saved else {return false}
        if feedbackMemory(job,model:model) != nil {return feedback.markSaved(job.id)}
        guard model.assistant.memory.saveReviewPreference(job.words,registration:job.registration,about:job.about,id:job.memoryID) else {feedback.error=model.assistant.memory.error;return false}
        return feedback.markSaved(job.id)
    }
    @discardableResult func processFeedbackNow(_ job:ReviewFeedbackJob,model:DashboardModel)->Bool {
        guard feedback.records.first(where:{$0.id == job.id}) == job,job.state == .queued,job.registration == model.chatGPT.activeID,!model.assistant.busy,!model.writing,(feedback.activeID == nil || feedback.ownedHeartbeatRunID != nil),model.heartbeat.busy || feedbackReady(model,request:nil) else {feedback.error="Finish the current PA operation, then process this feedback. Your words remain queued.";return false}
        let generation=reviewFeedbackGeneration
        let preemptHeartbeat=model.heartbeat.busy
        Task { @MainActor in
            if preemptHeartbeat {await model.heartbeat.cancelAndWait()}
            guard generation == self.reviewFeedbackGeneration,self.feedback.records.first(where:{$0.id == job.id}) == job,self.feedbackSource(job,model:model) != nil,self.feedbackReady(model,request:nil) else {return}
            _=await self.runFeedback(model,id:job.id,request:nil)
        }
        return true
    }
    func runHeartbeatFeedback(_ request:HeartbeatChildRequest,model:DashboardModel)async throws->HeartbeatChildResult {
        try request.validate()
        let job=await runFeedback(model,id:nil,request:request)
        try request.validate()
        guard let job else {return .init(detail:"No queued feedback ready to process.",skipped:true)}
        return job.state == .saved ? .init(detail:"One submitted preference learned; remaining feedback stays queued.") : .init(failure:job.error ?? "Feedback progress could not be saved.")
    }
    func cancelHeartbeatFeedback(runID:String) {feedback.cancelHeartbeat(runID)}
    private func feedbackReady(_ model:DashboardModel,request:HeartbeatChildRequest?)->Bool {
        model.heartbeat.deviceAvailable && !busy && !model.chatGPT.busy && !model.assistant.busy && !model.writing && (!model.heartbeat.busy || request?.runID == model.heartbeat.ownedRunID) && !model.proactive.busy && !model.briefings.busy && !model.memoryLearning.busy && !model.sourceLearning.busy && !model.nativeSourceLearning.busy && !model.memoryMaintenance.busy && !model.projectPlacement.busy && !model.lifeOrganisation.busy
    }
    private func runFeedback(_ model:DashboardModel,id:UUID?,request:HeartbeatChildRequest?)async ->ReviewFeedbackJob? {
        var completionGuard:(id:UUID,generation:Int)?
        return await feedback.runOne(id:id,registration:request?.registration ?? model.chatGPT.activeID,heartbeatRunID:request?.runID,validate:{job in
            if let request {do {try request.validate()} catch {return false}}
            return self.feedbackSource(job,model:model) != nil
        },ready:{self.feedbackReady(model,request:request)},prepare:{job in
            guard let source=self.feedbackSource(job,model:model) else {throw ReviewFeedbackFailure.message("The email changed. Your feedback is retained.")}
            completionGuard=(job.id,self.reviewFeedbackGeneration)
            return try await self.interpretReviewFeedback(source,words:job.words,about:job.about,model:model,inferenceModel:job.model,heartbeatRequest:request,isCurrent:{self.feedbackSource(job,model:model) != nil})
        },commit:{job,interpretation in
            if let request {try request.validate()}
            #if DEBUG
            let fictional=ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") && ProcessInfo.processInfo.arguments.contains("--feedback-preview")
            #else
            let fictional=false
            #endif
            guard completionGuard?.id == job.id,completionGuard?.generation == self.reviewFeedbackGeneration,!model.assistant.busy,model.heartbeat.deviceAvailable,(fictional || model.chatGPT.inferenceVerified),!model.chatGPT.usagePaused,model.assistant.memory.canSaveReviewPreference else {throw ReviewFeedbackFailure.message("Feedback was interrupted or memory storage is unavailable. No preference was saved; your feedback is retained.")}
            guard model.assistant.memory.saveReviewPreference(job.words,registration:job.registration,about:job.about,interpretation:interpretation,id:job.memoryID) else {throw ReviewFeedbackFailure.message(model.assistant.memory.error ?? "The preference could not be saved. Your feedback is retained.")}
            guard self.feedbackMemory(job,model:model)?.reviewInterpretation == interpretation else {throw ReviewFeedbackFailure.message("The saved preference could not be verified. Inspect memory before retrying.")}
        },alreadySaved:{job in self.feedbackMemory(job,model:model) != nil})
    }
}
