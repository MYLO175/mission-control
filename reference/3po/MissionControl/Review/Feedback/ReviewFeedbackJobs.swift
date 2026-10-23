import Foundation
import Observation

struct ReviewFeedbackJob:Codable,Identifiable,Equatable {
    enum State:String,Codable {case queued,learning,saving,saved,failed,stopped,interrupted}
    var id=UUID()
    var memoryID=UUID()
    var activityAttemptID:UUID?
    var registration:String
    var messageID:String
    var accountID:String
    var headerFingerprint:String
    var bodyFingerprint:String
    var assessmentVersion:String
    var model:String
    var sourceRevision:Int
    var words:String
    var about:String
    var created=Date.now
    var heartbeatEligible:Bool?
    var sourceSettings:String?
    var adviceRevision:String?
    var state=State.queued
    var error:String?
    var pending:Bool {state == .queued || state == .learning || state == .saving}
    /// Presentation changes (including Dismiss) and unrelated collection revisions
    /// do not revoke an accepted submission; its actual source and choices do.
    func matches(message:MailMessage,summary:EmailSummary,registration:String,model:String,sourceRevision:Int,sourceSettings:String)->Bool {
        self.registration == registration && summary.registration == registration && !self.model.isEmpty &&
        messageID == message.id && accountID == message.accountID && headerFingerprint == EmailSummary.fingerprint(message) &&
        summary.fingerprint == headerFingerprint && bodyFingerprint == summary.bodyFingerprint &&
        (summary.observedBodyFingerprint == nil || summary.observedBodyFingerprint == summary.bodyFingerprint) &&
        assessmentVersion == ReviewAcknowledgementRules.emailVersion(message,summary) &&
        (adviceRevision == nil || adviceRevision == summary.adviceRevision(replied:message.replied))
    }
    var status:String {
        switch state {
        case .queued:"Feedback queued for next heartbeat"
        case .learning,.saving:"Learning your preference…"
        case .saved:"Preference saved"
        case .failed:"Feedback needs attention"
        case .stopped:"Feedback stopped"
        case .interrupted:"Feedback interrupted"
        }
    }
}

/// Explicit submissions only. Navigation never owns or cancels these tasks.
/// Never-started authorised jobs may wait for a heartbeat across reopen.
/// Attempted jobs never replay automatically and pending jobs are not recall facts.
@MainActor @Observable final class ReviewFeedbackJobs {
    private(set) var records:[ReviewFeedbackJob]=[]
    private(set) var readable=true
    var error:String?
    @ObservationIgnored private let persist:([ReviewFeedbackJob])throws->Void
    @ObservationIgnored private var task:Task<Void,Never>?
    @ObservationIgnored private var operation:Task<ReviewFeedbackInterpretation,Error>?
    private(set) var ownedHeartbeatRunID:String?
    private(set) var activeID:UUID?

    init(load:()throws->[ReviewFeedbackJob],persist:@escaping ([ReviewFeedbackJob])throws->Void) {
        self.persist=persist
        do {
            let saved=try load()
            guard Set(saved.map(\.id)).count == saved.count,Set(saved.map(\.memoryID)).count == saved.count else {throw ReviewFeedbackFailure.message("Invalid feedback identities")}
            records=saved.map {value in
                var job=value
                if job.state == .learning || job.state == .saving || (job.state == .queued && job.heartbeatEligible != true) {job.state = .interrupted;job.error="The app closed before feedback finished. Your words are retained; retry when ready."}
                return job
            }
            if records != saved {try persist(records)}
        } catch {readable=false;self.error="Saved feedback is unavailable. Its storage is preserved; new submissions are disabled."}
    }
    func items(_ registration:String)->[ReviewFeedbackJob] {records.filter{$0.registration == registration}.sorted{$0.created > $1.created}}
    func latest(_ registration:String,messageID:String)->ReviewFeedbackJob? {items(registration).first{$0.messageID == messageID}}
    @discardableResult func submit(_ job:ReviewFeedbackJob)->Bool {
        guard readable,!job.words.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,job.words.count <= 2000,job.about.count <= 300,!job.registration.isEmpty,!job.messageID.isEmpty,!records.contains(where:{$0.id == job.id || $0.memoryID == job.memoryID || ($0.registration == job.registration && $0.messageID == job.messageID && $0.pending)}) else {error="Check your feedback or wait for its existing submission.";return false}
        return change { $0.append(job) }
    }
    @discardableResult func replaceForRetry(_ job:ReviewFeedbackJob)->Bool {
        guard readable,activeID != job.id,let previous=records.first(where:{$0.id == job.id}),!previous.pending,previous.state != .saved,previous.memoryID == job.memoryID,previous.registration == job.registration,previous.words == job.words,previous.about == job.about else {return false}
        return update(job.id) {$0=job}
    }
    func stop(_ id:UUID) {
        guard records.first(where:{$0.id == id})?.pending == true else {return}
        if activeID == id {operation?.cancel()}
        _=update(id) {$0.state = .stopped;$0.error="Stopped. Your feedback is retained; no new preference will be saved."}
    }
    func interruptActive() {
        task?.cancel();operation?.cancel()
        guard let activeID,records.first(where:{$0.id == activeID})?.state == .learning else {return}
        if !update(activeID,{$0.state = .stopped;$0.error="Foreground work interrupted feedback. Your words are retained; retry when ready."}) {readable=false}
    }
    func cancelHeartbeat(_ runID:String) {
        guard ownedHeartbeatRunID == runID else {return}
        interruptActive()
    }
    @discardableResult func markSaved(_ id:UUID)->Bool {update(id) {$0.state = .saved;$0.error=nil}}
    /// One durable submission per invocation. No waiting loop or queue drain can
    /// compete with foreground work or consume an entire heartbeat.
    func runOne(id:UUID?=nil,registration:String?=nil,heartbeatRunID:String?=nil,validate:@escaping (ReviewFeedbackJob)->Bool,ready:()->Bool,prepare:@escaping (ReviewFeedbackJob)async throws->ReviewFeedbackInterpretation,commit:(ReviewFeedbackJob,ReviewFeedbackInterpretation)throws->Void,alreadySaved:(ReviewFeedbackJob)->Bool)async -> ReviewFeedbackJob? {
        guard readable,activeID == nil,ready(),!Task.isCancelled,
              let job=records.first(where:{$0.state == .queued && (id == nil || $0.id == id) && (registration == nil || $0.registration == registration) && (heartbeatRunID == nil || $0.heartbeatEligible == true)}) else {return nil}
        activeID=job.id;ownedHeartbeatRunID=heartbeatRunID
        defer {operation=nil;activeID=nil;ownedHeartbeatRunID=nil}
        do {
            guard validate(job) else {throw ReviewFeedbackFailure.message("The email, account or settings changed. Your feedback is retained; reopen it before retrying.")}
            if alreadySaved(job) {_=markSaved(job.id);return records.first{$0.id == job.id}}
            guard update(job.id,{$0.state = .learning;$0.error=nil}) else {return records.first{$0.id == job.id}}
            let operation=Task(priority:heartbeatRunID == nil ? .userInitiated : .background) {let result=try await prepare(job);try Task.checkCancellation();return result}
            self.operation=operation
            let interpretation=try await withTaskCancellationHandler(operation:{try await operation.value},onCancel:{operation.cancel()})
            self.operation=nil
            try Task.checkCancellation()
            guard validate(job),records.first(where:{$0.id == job.id})?.state == .learning else {throw ReviewFeedbackFailure.message("The email, account or settings changed. No preference was saved; your feedback is retained.")}
            guard update(job.id,{$0.state = .saving}) else {return records.first{$0.id == job.id}}
            try commit(job,interpretation)
            _=markSaved(job.id)
        } catch {
            if records.first(where:{$0.id == job.id})?.state != .stopped {
                _=update(job.id,{$0.state = error is CancellationError ? .stopped : .failed;$0.error=error is CancellationError ? "Interrupted by foreground work. Your feedback is retained; retry when ready." : error.localizedDescription})
            }
        }
        return records.first{$0.id == job.id}
    }
    /// Explicit Process now / Retry owns only the selected submission.
    func start(id:UUID?=nil,validate:@escaping (ReviewFeedbackJob)->Bool,ready:@escaping ()->Bool,prepare:@escaping (ReviewFeedbackJob)async throws->ReviewFeedbackInterpretation,commit:@escaping (ReviewFeedbackJob,ReviewFeedbackInterpretation)throws->Void,alreadySaved:@escaping (ReviewFeedbackJob)->Bool) {
        guard task == nil,activeID == nil else {return}
        task=Task { @MainActor in
            defer {self.task=nil}
            _=await self.runOne(id:id,validate:validate,ready:ready,prepare:prepare,commit:commit,alreadySaved:alreadySaved)
        }
    }
    @discardableResult private func update(_ id:UUID,_ mutation:(inout ReviewFeedbackJob)->Void)->Bool {
        change {values in if let i=values.firstIndex(where:{$0.id == id}) {mutation(&values[i])}}
    }
    private func change(_ mutation:(inout [ReviewFeedbackJob])->Void)->Bool {
        guard readable else {return false}
        var next=records;mutation(&next)
        do {try persist(next);records=next;error=nil;return true}
        catch {self.error="Feedback progress could not be saved. Your retained feedback has not been discarded.";return false}
    }
}
