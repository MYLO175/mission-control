import Foundation
import Observation
import SwiftData

@MainActor @Observable final class HeartbeatService {
    var enabled:Bool {didSet {guard !restoringSettings,enabled != oldValue else {return};settings.set(enabled,forKey:"paHeartbeatEnabled");controlsRevision=UUID();if !enabled {cancel()}}}
    var notificationsEnabled:Bool {didSet {guard !restoringSettings,notificationsEnabled != oldValue else {return};settings.set(notificationsEnabled,forKey:"paHeartbeatNotifications")}}
    var whatsappEnabled:Bool {didSet {
        guard !restoringSettings,whatsappEnabled != oldValue else {return}
        settings.set(whatsappEnabled,forKey:"paHeartbeatWhatsApp")
        let revision=UUID();whatsappLearningAccessRevision=revision
        settings.set(revision.uuidString,forKey:"paHeartbeatWhatsAppLearningAccessRevision")
        controlsRevision=UUID();cancel()
    }}
    /// A durable permission boundary, independent of ordinary heartbeat timing edits.
    private(set) var whatsappLearningAccessRevision:UUID?
    var intervalMinutes:Int {didSet {guard !restoringSettings else {return};if ![15,30,60,120].contains(intervalMinutes) {intervalMinutes=60};guard intervalMinutes != oldValue else {return};settings.set(intervalMinutes,forKey:"paHeartbeatMinutes")}}
    var dailyCallLimit:Int {didSet {guard !restoringSettings else {return};let bounded=PAHeartbeatRules.callLimit(dailyCallLimit);if bounded != dailyCallLimit {dailyCallLimit=bounded};guard dailyCallLimit != oldValue else {return};settings.set(dailyCallLimit,forKey:"paHeartbeatCallLimit");controlsRevision=UUID();cancel()}}
    @ObservationIgnored private var restoringSettings=true
    @ObservationIgnored private let settings:UserDefaults
    @ObservationIgnored private let repository:LocalRecordRepository?
    func budgetStatus(_ registration:String)->String {
        let count=PAHeartbeatRules.callCount(state.accounts[registration] ?? .init(),day:BriefingRules.day(clock()))
        return dailyCallLimit == 0 ? "\(count) heartbeat AI calls today · Daily limit off" : "\(count) of \(dailyCallLimit) heartbeat AI calls today"
    }
    func claimCall(_ registration:String) throws {
        let day=BriefingRules.day(clock())
        guard deviceAvailable,capturedPowerRevision == powerRevision,busy,registration == capturedRegistration,state.accounts[registration]?.phase == "assessing",day == capturedDay,controlsRevision == capturedControls,task?.isCancelled != true,capturedEligibility?() != false else { throw ActionFailure.message("Background-review device, account, day, controls or foreground ownership changed before inference.") }
        let prior=state.accounts[registration] ?? .init()
        state.accounts[registration]=try PAHeartbeatRules.claim(prior,day:day,limit:dailyCallLimit)
        do { try save() } catch { state.accounts[registration]=prior;throw error }
    }
    private func claimCall(_ registration:String,runID:String) throws {
        guard capturedRunID == runID else {throw ActionFailure.message("The captured heartbeat run has ended; no new call was claimed.")}
        try claimCall(registration)
    }
    private var capturedRegistration:String?
    private var capturedDay:String?
    private var capturedControls:UUID?
    private var capturedPowerRevision:Int?
    private var capturedPrior:PAHeartbeatAccount?
    private var capturedRunID:String?
    var activeRegistration:String? {busy ? capturedRegistration : nil}
    var ownedRunID:String? {busy ? capturedRunID : nil}
    func ownsLearningRun(_ runID:String)->Bool {busy && capturedRunID == runID && task?.isCancelled != true}
    @ObservationIgnored private var capturedEligibility:(()->Bool)?
    private var powerRevision=0
    private var systemSleeping=false
    @ObservationIgnored private let deviceState:()->HeartbeatDeviceState
    var deviceAvailable:Bool { !systemSleeping && deviceState().available }
    func willSleep(runtime:HeartbeatRuntime) { systemSleeping=true;deviceAvailabilityChanged(runtime:runtime) }
    func didWake(runtime:HeartbeatRuntime) { systemSleeping=false;deviceAvailabilityChanged(runtime:runtime) }
    func deviceAvailabilityChanged(runtime:HeartbeatRuntime) {
        if !deviceAvailable {
            powerRevision += 1
            if busy {
                // Persist before the OS suspends execution, not only when the
                // cancelled task eventually unwinds. Reopen retains the due anchor.
                if let registration=capturedRegistration,let prior=capturedPrior,let current=state.accounts[registration] {
                    state.accounts[registration]=PAHeartbeatRules.suspended(current,prior:prior)
                    if var run=state.accounts[registration]?.reviews?.last,run.finished == nil {
                        run.finished=clock();run.phase="suspended";run.failure="The Mac went to sleep or the laptop closed. A fresh heartbeat runs when open, awake and due."
                        run.steps=run.steps?.map{step in var value=step;if value.status == "running" {value.status="waiting"};return value}
                        if var runs=state.accounts[registration]?.reviews,!runs.isEmpty {runs[runs.count-1]=run;state.accounts[registration]?.reviews=runs}
                    }
                    do {try save()} catch {status="The sleep interruption could not be saved. Existing review receipts are retained."}
                }
                cancel();runtime.cancelChildren()
            }
        } else { check(runtime:runtime) }
    }
    private func finishAssessment(_ registration:String,account:PAHeartbeatAccount)throws {
        guard deviceAvailable,capturedPowerRevision == powerRevision,busy,capturedRegistration == registration,capturedDay == BriefingRules.day(clock()),capturedControls == controlsRevision,task?.isCancelled != true,state.accounts[registration]?.phase == "assessing" else {throw ActionFailure.message("Background-review ownership changed before completion; completed work retained.")}
        let previous=state
        var completed=account;completed.phase="idle";completed.assessed=clock();state.accounts[registration]=completed
        do {try save()} catch {state=previous;throw error}
    }
    @ObservationIgnored private let clock:()->Date
    var currentTime:Date {clock()}
    private(set) var controlsRevision = UUID()
    private(set) var busy = false
    private(set) var progress:PAHeartbeatProgress?
    #if DEBUG
    /// The caller's dedicated preview has in-memory storage and returns before startup.
    func previewProgress() async {
        guard ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"),ProcessInfo.processInfo.arguments.contains("--heartbeat-progress-preview") else {return}
        while !Task.isCancelled {
            var steps=PAHeartbeatRules.stages()
            let runID=UUID().uuidString
            busy=true
            for index in steps.indices {
                steps[index].status="running"
                progress=PAHeartbeatProgress(runID:runID,steps:steps)
                do {try await Task.sleep(for:.seconds(2))} catch {busy=false;progress=nil;return}
                steps[index].status="done"
            }
            progress=PAHeartbeatProgress(runID:runID,steps:steps,finished:true);busy=false
            do {try await Task.sleep(for:.seconds(4))} catch {return}
        }
    }
    #endif
    private(set) var status = "Sources collect without AI. Background reviews run when due while 3PO is running and the Mac is awake."
    private(set) var state = PAHeartbeatState()
    private var statusRegistration:String?
    func reviewInProgress(_ run:PAReviewRun,registration:String)->Bool {
        busy && capturedRegistration == registration && state.accounts[registration]?.reviews?.last?.id == run.id
    }
    private func recordReview(_ registration:String,run:PAReviewRun) throws {
        let previous=state
        var account=state.accounts[registration] ?? .init(),runs=account.reviews ?? []
        if let i=runs.firstIndex(where:{$0.id == run.id}) {runs[i]=run} else {runs.append(run)}
        account.reviews=Array(runs.suffix(20));state.accounts[registration]=account
        do {try save()} catch {state=previous;throw error}
    }
    func statusFor(_ registration:String)->String {
        if readable,!busy,state.accounts[registration]?.retryReason == "failure" {
            return state.accounts[registration]?.reviews?.last?.briefUpdated == true ? "Today’s brief updated; some analysis did not finish. See the stage details below. The next scheduled heartbeat checks fresh information." : "The last heartbeat did not finish. Saved work is kept; the next scheduled heartbeat checks fresh information."
        }
        if readable,!busy,statusRegistration != registration,state.accounts[registration]?.mailLanes?.values.contains(where:{$0.issue != nil}) == true {return "The last review used available sources. Unavailable Mail accounts remain pending; source checks continue independently."}
        if let statusRegistration,statusRegistration != registration {return "Sources collect without AI. This account's review runs when due and idle."}
        return status
    }
    func scheduleStatus(runtime:HeartbeatRuntime)->String {
        let environment=runtime.environment()
        let account=state.accounts[environment.registration] ?? .init(),now=clock()
        guard readable else {return "Waiting for saved review state"}
        guard enabled else {return "Automatic reviews are off"}
        guard deviceAvailable else { return "Waiting for the Mac to wake and the laptop to open" }
        if busy {return capturedRegistration == environment.registration ? "Review running" : "Waiting for the previous review to stop"}
        if !environment.contextEnabled {return "Waiting for PA context to be enabled"}
        if !environment.inferenceVerified {return "Waiting for the subscription connection"}
        if environment.usagePaused {return "Waiting for AI usage to resume"}
        let next=PAHeartbeatRules.nextReview(account,now:now,minutes:intervalMinutes,day:BriefingRules.day(now),allowance:dailyCallLimit)
        if next <= now {return composerActive ? "Due · waiting until you stop typing" : environment.workBusy ? "Due · waiting for other work to finish" : "Due · checked on the next idle minute"}
        return (account.retryReason == "allowance" ? "Daily AI call limit reached · Resumes " : account.retryAfter != nil ? "Retry " : "Next review ")+next.formatted(date:Calendar.current.isDate(next,inSameDayAs:now) ? .omitted : .abbreviated,time:.shortened)
    }
    func manualCheckBlockReason(runtime:HeartbeatRuntime)->String? {
        let environment=runtime.environment()
        if busy {return "A heartbeat is already running. See Background activity for progress."}
        if !deviceAvailable {return "Heartbeat waits while the Mac is asleep, in dark wake or the laptop is closed."}
        if !readable {return "Saved review state is unavailable. See Background activity for details."}
        if !environment.permitted {return "Heartbeat is unavailable in this preview."}
        if environment.registration.isEmpty || !environment.inferenceVerified {return "Connect your ChatGPT subscription in Settings to run a heartbeat."}
        if !environment.contextEnabled {return "Enable PA context in Settings to run a heartbeat."}
        if environment.usagePaused {return "AI usage is paused. Resume it in Settings before running a heartbeat."}
        if environment.workBusy {return "Wait for the current PA work to finish before running a heartbeat."}
        return nil
    }
    func manualCheckHelp(runtime:HeartbeatRuntime)->String {
        manualCheckBlockReason(runtime:runtime) ?? "Run heartbeat: analyse collected mail and enabled context with AI, then update your brief and Review inbox. Mail collection continues independently. Uses your ChatGPT connection."
    }
    func mailReviewStatus(registration:String,accounts:[MailAccount])->String {
        let lanes=state.accounts[registration]?.mailLanes ?? [:]
        return accounts.compactMap{account in
            guard let lane=lanes[account.id] else {return nil}
            if let issue=lane.issue {return account.title+": "+(lane.assessed.map{"reviewed "+$0.formatted(date:.abbreviated,time:.shortened)+" · "} ?? "")+"background collection issue · "+String(issue.prefix(180))}
            if let assessed=lane.assessed {return account.title+": reviewed "+assessed.formatted(date:.abbreviated,time:.shortened)+(lane.pending ? " · more work pending" : "")}
            return account.title+(lane.pending ? ": waiting for review" : ": no review work waiting")
        }.joined(separator:"\n")
    }
    private let container: ModelContainer?
    private var task: Task<Void,Never>?
    private(set) var readable = true
    init(container:ModelContainer?,settings:UserDefaults = .standard,repository:LocalRecordRepository? = nil,clock:@escaping ()->Date = {Date.now},deviceState:@escaping ()->HeartbeatDeviceState = {HeartbeatDeviceState.current()}) {
        self.container = container
        self.settings=settings;self.repository=repository ?? container.map{LocalRecordRepository(container:$0)}
        enabled=settings.object(forKey:"paHeartbeatEnabled") == nil || settings.bool(forKey:"paHeartbeatEnabled")
        notificationsEnabled=settings.object(forKey:"paHeartbeatNotifications") == nil || settings.bool(forKey:"paHeartbeatNotifications")
        whatsappEnabled=settings.object(forKey:"paHeartbeatWhatsApp") == nil || settings.bool(forKey:"paHeartbeatWhatsApp")
        whatsappLearningAccessRevision=settings.string(forKey:"paHeartbeatWhatsAppLearningAccessRevision").flatMap(UUID.init(uuidString:))
        let minutes=settings.object(forKey:"paHeartbeatMinutes") as? Int ?? PAHeartbeatRules.defaultMinutes
        intervalMinutes=[15,30,60,120].contains(minutes) ? minutes : 60
        dailyCallLimit=PAHeartbeatRules.callLimit(settings.object(forKey:"paHeartbeatCallLimit") as? Int)
        self.clock=clock
        self.deviceState=deviceState
        do {
            if let record = try self.repository?.read("paHeartbeat") {
                state = try JSONDecoder().decode(PAHeartbeatState.self,from: record)
                state.accounts = state.accounts.mapValues{PAHeartbeatRules.recovered($0,now:clock(),minutes:intervalMinutes)}
            }
        } catch { readable = false; status = "Saved background-review state unavailable; original record retained." }
        restoringSettings=false
    }
    private var lastTyping: Date?
    var composerActive: Bool { lastTyping.map { clock().timeIntervalSince($0) < 120 } ?? false }
    // Accepted Review jobs need a short typing grace, not the automatic heartbeat's two-minute quiet window.
    var reviewComposerActive: Bool { lastTyping.map { clock().timeIntervalSince($0) < 2 } ?? false }
    /// Draft editing defers the next automatic run; it does not stop captured work.
    func noteDraftEditing() {lastTyping=clock()}
    func userStartedTyping() {noteDraftEditing();cancel()}
    func cancel() { task?.cancel() }
    func cancelAndWait() async {
        let active=task
        active?.cancel()
        await active?.value
    }
    func check(runtime:HeartbeatRuntime,manual:Bool = false) {
        let environment=runtime.environment(),registration=environment.registration
        guard deviceAvailable,readable,(manual || enabled),!busy,!registration.isEmpty,environment.permitted else { return }
        let prior=state.accounts[registration] ?? PAHeartbeatAccount()
        guard manual || PAHeartbeatRules.due(prior,now:clock(),minutes:intervalMinutes,day:BriefingRules.day(clock()),allowance:dailyCallLimit) else { return }
        // Collection has its own no-AI polling. A due review must not consume its
        // interval while foreground work or disabled inference prevents assessment.
        guard manual || (!composerActive && environment.contextEnabled && environment.inferenceVerified && !environment.usagePaused) else {return}
        // Let foreground work win; this local due check never runs inference.
        guard !environment.workBusy else { return }
        let controls=controlsRevision,day=BriefingRules.day(clock())
        let power=powerRevision
        let settings=environment.sourceSettings,choices=environment.whatsappChoices,identity=environment.whatsappIdentity
        let runID=UUID().uuidString
        capturedRunID=runID
        busy=true;capturedRegistration=registration;capturedDay=day;capturedControls=controls;capturedPowerRevision=power;capturedPrior=prior;statusRegistration=registration;status="Preparing collected context for background review…"
        progress=PAHeartbeatProgress(runID:runID,steps:PAHeartbeatRules.stages())
        task=Task {
            let began=clock()
            runtime.started(registration,runID,began)
            let callsBefore=PAHeartbeatRules.callCount(prior,day:day)
            let before=runtime.activity(registration,runID)
            var steps=PAHeartbeatRules.stages(),failure:String?,sleepInterrupted=false
            var stageFailures:[String]=[]
            var reviewedMail:MailReviewScope?
            @MainActor func step(_ id:String,_ state:String,_ detail:String? = nil) throws {
                guard let index=steps.firstIndex(where:{$0.id == id}) else {return}
                steps[index].status=state;steps[index].detail=detail
                try recordReview(registration,run:.init(id:runID,started:began,manual:manual,phase:"running",detail:status,steps:steps))
                progress=PAHeartbeatProgress(runID:runID,steps:steps)
            }
            defer {
                let latest=state.accounts[registration] ?? .init()
                for index in steps.indices where steps[index].status == "running" {
                    steps[index].status=failure != nil && !sleepInterrupted ? "failed" : "waiting"
                }
                let ready=reviewedMail?.accountIDs.count ?? 0,waiting=reviewedMail?.issues.count ?? 0
                let phase=sleepInterrupted ? "suspended" : (failure != nil || !stageFailures.isEmpty) ? (Task.isCancelled ? "interrupted" : "failed") : latest.pending == true ? "waiting" : latest.phase
                let after=runtime.activity(registration,runID)
                let run=PAReviewRun(id:runID,started:began,finished:clock(),manual:manual,phase:phase,detail:String(status.prefix(600)),calls:max(0,PAHeartbeatRules.callCount(latest,day:day)-callsBefore),checkedAccounts:ready,waitingAccounts:waiting,preparedItems:max(0,after.preparedItems-before.preparedItems),drafts:max(0,after.emailDrafts-before.emailDrafts)+max(0,after.whatsappDrafts-before.whatsappDrafts),handled:max(0,after.handled-before.handled),briefUpdated:after.briefUpdated,questions:after.questions,steps:steps,failure:failure ?? (stageFailures.isEmpty ? nil : stageFailures.joined(separator:" · ")),mailCollectionIndependent:true)
                var recorded=false
                do {try recordReview(registration,run:run);recorded=true} catch {status="Review finished, but its activity record could not be saved. Existing records are retained."}
                // Only a fully traversed cycle with a saved brief reaches 100%.
                // Stops, early exits and interrupted runs disappear at their last stage.
                let finalProgress=PAHeartbeatProgress(runID:runID,steps:steps,finished:true)
                progress=recorded && after.briefUpdated && failure == nil && !sleepInterrupted && !Task.isCancelled && finalProgress.percentage == 100 ? finalProgress : nil
                busy=false;capturedRegistration=nil;capturedDay=nil;capturedControls=nil;capturedPowerRevision=nil;capturedPrior=nil;capturedRunID=nil;capturedEligibility=nil
                runtime.finished(registration,run)
            }
            var account=PAHeartbeatRules.clearWait(prior)
            do {
                try Task.checkCancellation()
                guard deviceAvailable,power == powerRevision else {throw CancellationError()}
                account.phase="refreshing"
                state.accounts[registration]=account; try save()
                try step("sources","running")
                account=state.accounts[registration] ?? account
                let sources=try await runtime.prepareSources(.init(registration:registration,whatsappEnabled:whatsappEnabled,clock:clock,validate:{
                    try Task.checkCancellation()
                    let current=runtime.environment()
                    guard self.capturedRunID == runID,self.deviceAvailable,power == self.powerRevision,(manual || self.enabled),controls == self.controlsRevision,registration == current.registration,day == BriefingRules.day(self.clock()),PAHeartbeatRules.canPrepareSources(settings:settings,currentSettings:current.sourceSettings,choices:choices,currentChoices:current.whatsappChoices,identity:identity,currentIdentity:current.whatsappIdentity) else {throw ActionFailure.message("Background-review account, device or source choices changed during source preparation.")}
                }))
                let wantsWhatsApp=sources.wantsWhatsApp,whatsappReady=sources.whatsappReady
                try Task.checkCancellation()
                guard (manual || enabled),controls == controlsRevision,registration == runtime.environment().registration,day == BriefingRules.day(clock()),
                      PAHeartbeatRules.canPrepareSources(settings:settings,currentSettings:runtime.environment().sourceSettings,choices:choices,currentChoices:runtime.environment().whatsappChoices,identity:identity,currentIdentity:runtime.environment().whatsappIdentity) else { throw ActionFailure.message("Background-review account, day or source choices changed; no assessment started.") }
                // Each child captures its own supplied source scope and validates
                // current access before saving. Broad source-choice changes must
                // not revoke unrelated stages in this scheduling run.
                capturedEligibility={
                    let current=runtime.environment()
                    return current.permitted && current.registration == registration && current.contextEnabled && current.inferenceVerified && !current.usagePaused && !current.foregroundBusy
                }
                @MainActor func requireOwned() throws {
                    try Task.checkCancellation()
                    if self.task?.isCancelled == true {throw CancellationError()}
                    guard self.capturedRunID == runID,self.deviceAvailable,power == self.powerRevision,(manual || self.enabled),controls == self.controlsRevision,day == BriefingRules.day(self.clock()),self.capturedEligibility?() == true else {
                        throw ActionFailure.message("Background-review ownership or foreground availability changed; completed work retained.")
                    }
                }
                var mailReview=sources.mailReview
                reviewedMail=mailReview
                var nativeReady=sources.nativeReady
                let enabledMail=sources.enabledMail
                account.checked = clock()
                account=PAHeartbeatRules.collectingMail(account,enabled:enabledMail,ready:mailReview.accountIDs,issues:mailReview.issues,now:clock())
                account.pending = !stageFailures.isEmpty || mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady) || account.pending == true
                state.accounts[registration]=account;try save()
                let sourceDetail="Saved Calendar & Reminders: \(nativeReady ? "available" : "waiting for background collection") · Mail: saved data from \(mailReview.accountIDs.count) accounts; \(mailReview.issues.count) collection issues · WhatsApp: \(wantsWhatsApp ? (whatsappReady ? "saved context available" : "unavailable") : "off"). All source collection runs independently."
                try step("sources",nativeReady && (!wantsWhatsApp || whatsappReady) ? "done" : "waiting",sourceDetail)
                let fingerprint=runtime.sourceFingerprint(mailReview,whatsappReady,whatsappEnabled)
                let pendingSources=runtime.pending(mailReview,whatsappReady,nativeReady).any
                var availableAccount=account;availableAccount.pending=pendingSources
                let assess=PAHeartbeatRules.needsAssessment(availableAccount,fingerprint:fingerprint,manual:manual,pendingSources:pendingSources)
                guard assess,runtime.environment().contextEnabled,runtime.environment().inferenceVerified,!runtime.environment().usagePaused else {
                    if !assess { status="Background review checked; no new source material." }
                    else { status="Context prepared; AI assessment waits for enabled context, allowance and an idle composer." }
                    account = assess ? PAHeartbeatRules.deferred(account,now:clock(),reason:.foreground) : PAHeartbeatRules.quiet(account,fingerprint:fingerprint,ready:mailReview.accountIDs,pending:mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady))
                    if mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady) {status += " " + waitingStatus(accounts:runtime.currentSources(whatsappReady).accounts,mailReview:mailReview,nativeReady:nativeReady,whatsappWaiting:wantsWhatsApp && !whatsappReady)}
                    state.accounts[registration]=account; try save();return
                }
                guard !runtime.environment().workBusy else { account=PAHeartbeatRules.deferred(account,now:clock(),reason:.foreground);state.accounts[registration]=account;try save();status="Context prepared; pending AI assessment waits for foreground work.";return }
                guard PAHeartbeatRules.canClaim(account,day:BriefingRules.day(clock()),limit:dailyCallLimit) else { throw HeartbeatBudgetExhausted() }
                account.phase="assessing"; state.accounts[registration]=account; try save()
                status="Reviewing your enabled context…"
                try step("feedback","running")
                try requireOwned()
                let feedback=try await runtime.feedback(.init(registration:registration,manual:manual,runID:runID,mailReview:mailReview,whatsappReady:whatsappReady,claim:{try self.claimCall(registration,runID:runID)},validate:{try requireOwned()}))
                try requireOwned()
                if let error=feedback.failure {
                    stageFailures.append("Feedback: "+String(error.prefix(400)))
                    try step("feedback","failed",error)
                } else {try step("feedback",feedback.skipped ? "skipped" : "done",feedback.detail)}
                if !PAHeartbeatRules.canClaim(state.accounts[registration] ?? account,day:BriefingRules.day(clock()),limit:dailyCallLimit) {throw HeartbeatBudgetExhausted()}
                try step("email",runtime.environment().emailEnabled ? "running" : "skipped")
                // Existing classifier is serial, selective and preserves its
                // original monitoring start/decisions; this is not a new backlog.
                try requireOwned()
                let email=try await runtime.email(.init(registration:registration,manual:manual,runID:runID,mailReview:mailReview,whatsappReady:whatsappReady,claim:{try self.claimCall(registration,runID:runID)},validate:{try requireOwned()}))
                try Task.checkCancellation()
                try requireOwned()
                mailReview=runtime.availableMail(mailReview)
                reviewedMail=mailReview
                account=state.accounts[registration] ?? account
                account=PAHeartbeatRules.collectingMail(account,enabled:enabledMail,ready:mailReview.accountIDs,issues:mailReview.issues,now:clock())
                state.accounts[registration]=account;try save()
                if runtime.environment().emailEnabled,let error=email.failure {
                    stageFailures.append("Email review: "+String(error.prefix(400)))
                    try step("email","failed",error)
                } else {try step("email",runtime.environment().emailEnabled ? "done" : "skipped","Existing assessments reused; new permitted mail reviewed when available.")}
                if !PAHeartbeatRules.canClaim(state.accounts[registration] ?? account,day:BriefingRules.day(clock()),limit:dailyCallLimit) { throw HeartbeatBudgetExhausted() }
                try step("learning","running")
                try requireOwned()
                let learning=try await runtime.learning(.init(registration:registration,manual:manual,runID:runID,mailReview:mailReview,whatsappReady:whatsappReady,claim:{try self.claimCall(registration,runID:runID)},validate:{try requireOwned()}))
                try requireOwned()
                if let error=learning.failure {
                    stageFailures.append("Memory: "+String(error.prefix(400)))
                    try step("learning","failed",error)
                } else {try step("learning",learning.skipped ? "skipped" : "done",learning.detail)}
                // Do not compare new inputs with an earlier stage's pre-request cache.
                // Proactive and briefing jobs capture and validate their own fresh inputs.
                nativeReady=runtime.currentSources(whatsappReady).nativeReady
                let mailFingerprints=runtime.mailFingerprints(mailReview)
                try step("suggestions",!runtime.environment().proposalsEnabled ? "skipped" : nativeReady ? "running" : "waiting")
                try requireOwned()
                let suggestions=nativeReady ? try await runtime.suggestions(.init(registration:registration,manual:manual,runID:runID,mailReview:mailReview,whatsappReady:whatsappReady,claim:{try self.claimCall(registration,runID:runID)},validate:{try requireOwned()})) : .init()
                if nativeReady,suggestions.nativeUnavailable {nativeReady=false}
                try requireOwned()
                if nativeReady,runtime.environment().proposalsEnabled,let error=suggestions.failure {
                    stageFailures.append("Suggestions: "+String(error.prefix(400)))
                    try step("suggestions","failed",error)
                } else {try step("suggestions",!runtime.environment().proposalsEnabled ? "skipped" : nativeReady ? "done" : "waiting",suggestions.detail ?? "Eligible changes assessed when due; existing results retained.")}
                if !PAHeartbeatRules.canClaim(state.accounts[registration] ?? account,day:day,limit:dailyCallLimit) {throw HeartbeatBudgetExhausted()}
                status="Updating today’s brief…"
                mailReview=runtime.availableMail(mailReview)
                reviewedMail=mailReview
                try step("brief","running")
                try requireOwned()
                let brief=try await runtime.brief(.init(registration:registration,manual:manual,runID:runID,mailReview:mailReview,whatsappReady:whatsappReady,claim:{try self.claimCall(registration,runID:runID)},validate:{try requireOwned()}))
                try requireOwned()
                guard runtime.activity(registration,runID).briefUpdated else {throw ActionFailure.message(brief.failure ?? "The brief update is waiting; completed review work is retained.")}
                mailReview=runtime.availableMail(mailReview)
                reviewedMail=mailReview
                try step("brief","done")
                let pending=runtime.pending(mailReview,whatsappReady,nativeReady),pendingAccounts=pending.mailAccounts
                account=PAHeartbeatRules.clearWait(state.accounts[registration] ?? account);account.phase="idle";account.assessed = clock()
                account=PAHeartbeatRules.collectingMail(account,enabled:enabledMail,ready:mailReview.accountIDs,issues:mailReview.issues,now:clock())
                account=PAHeartbeatRules.completedMail(account,fingerprints:mailFingerprints.filter{mailReview.accountIDs.contains($0.key)},pending:stageFailures.isEmpty ? pendingAccounts : pendingAccounts.union(mailReview.accountIDs),now:clock(),issues:mailReview.issues)
                account.pending = !stageFailures.isEmpty || mailReview.pending || !nativeReady || (wantsWhatsApp && !whatsappReady) || !pendingAccounts.isEmpty || pending.proposals
                account.fingerprint=runtime.sourceFingerprint(mailReview,whatsappReady,whatsappEnabled);try finishAssessment(registration,account:account)
                status="Heartbeat completed at " + clock().formatted(date:.omitted,time:.shortened) + ". Today’s brief updated; useful items are in Review inbox. " + waitingStatus(accounts:runtime.currentSources(whatsappReady).accounts,mailReview:mailReview,nativeReady:nativeReady,whatsappWaiting:wantsWhatsApp && !whatsappReady)
                if !stageFailures.isEmpty {
                    var retained=state.accounts[registration] ?? account
                    retained=PAHeartbeatRules.failed(retained,now:clock(),minutes:intervalMinutes)
                    state.accounts[registration]=retained;try save()
                    status="Today’s brief updated. Some analysis did not finish; completed work is saved. See the stage details in Heartbeat history. The next scheduled heartbeat checks fresh information."
                }
                if !runtime.environment().proposalsEnabled { status += " Review proposals are disabled." }
                else if runtime.environment().proposalAllowanceReached { status += " Daily comparison allowance reached; source checks continue." }
            } catch is HeartbeatBudgetExhausted {
                account=PAHeartbeatRules.deferred(state.accounts[registration] ?? account,now:clock(),reason:.allowance);account.checked = clock();state.accounts[registration]=account;try? save();status=HeartbeatBudgetExhausted().localizedDescription
            } catch {
                sleepInterrupted=power != powerRevision || !deviceAvailable
                failure=sleepInterrupted ? "The Mac went to sleep, entered dark wake or the laptop closed. Saved work is kept; a fresh heartbeat runs when open, awake and due." : error is CancellationError ? "Stopped before the remaining work finished." : String(error.localizedDescription.prefix(600))
                account = sleepInterrupted ? PAHeartbeatRules.suspended(state.accounts[registration] ?? account,prior:prior) : error is CancellationError ? PAHeartbeatRules.interrupted(state.accounts[registration] ?? account,now:clock(),foreground:composerActive,minutes:intervalMinutes) : PAHeartbeatRules.failed(state.accounts[registration] ?? account,now:clock(),minutes:intervalMinutes)
                runtime.cancelChildren()
                if !sleepInterrupted {account.checked = clock()};state.accounts[registration]=account;try? save()
                status=sleepInterrupted ? failure! : account.retryReason == "failure" ? "Heartbeat did not finish. Saved work is kept; the next scheduled heartbeat checks fresh information." : "Source check stopped before AI assessment; pending work will retry when idle."
            }
        }
    }
    private func waitingStatus(accounts:[MailAccount],mailReview:MailReviewScope,nativeReady:Bool,whatsappWaiting:Bool)->String {
        var issues=mailReview.issues.keys.sorted().map{id in (accounts.first{$0.id == id}?.title ?? "Mail account")+": "+(mailReview.issues[id] ?? "waiting")}
        if mailReview.discoveryFailed,issues.isEmpty {issues.append("Mail account list unavailable")}
        if !nativeReady {issues.append("Calendar/Reminders comparison pending; email assessment can continue")}
        if whatsappWaiting {issues.append("WhatsApp unavailable")}
        return issues.isEmpty ? "" : "Coverage notes: "+issues.joined(separator:" · ")+". Mail refresh runs independently; available collected data and pending work are retained."
    }
    private func save() throws {
        guard let repository else {throw SummaryFailure.invalid}
        try repository.write(["paHeartbeat":JSONEncoder().encode(state)],now:clock())
    }
    #if DEBUG
    func seedHistoryPreview(_ registration:String,validationDetail:String? = nil) {
        guard ProcessInfo.processInfo.arguments.contains("--preview-settings"),ProcessInfo.processInfo.arguments.contains("--heartbeat-history"),state.accounts[registration] == nil else {return}
        let now=clock()
        var finished=PAHeartbeatRules.stages()
        for index in finished.indices {finished[index].status="done"}
        finished[0].status="waiting";finished[0].detail="Calendar & Reminders: checked · Mail: 1 checked, 1 waiting · WhatsApp: checked"
        finished[4].detail=validationDetail
        let completed=PAReviewRun(id:"fictional-completed",started:now.addingTimeInterval(-7200),finished:now.addingTimeInterval(-7140),manual:false,phase:"waiting",detail:"Completed with one source waiting.",calls:3,checkedAccounts:1,waitingAccounts:1,preparedItems:2,drafts:1,briefUpdated:true,questions:1,steps:finished)
        var stopped=PAHeartbeatRules.stages();stopped[0].status="done";stopped[1].status="failed"
        let failed=PAReviewRun(id:"fictional-failed",started:now.addingTimeInterval(-3600),finished:now.addingTimeInterval(-3540),manual:false,phase:"failed",detail:"Fictional interrupted email review.",calls:1,checkedAccounts:2,briefUpdated:false,questions:0,steps:stopped,failure:"The model connection was interrupted. Completed work is retained.")
        state.accounts[registration] = PAHeartbeatRules.failed(.init(budgetDay:BriefingRules.day(now),calls:4,assessed:completed.finished,pending:true,reviews:[completed,failed]),now:failed.finished!,minutes:intervalMinutes)
    }
    /// Exercises the actual ownership guard and cache recovery without starting
    /// sources, inference, notifications or native changes. All receipts are fictional.
    static func evaluateOwnedScheduling() async throws->[String:Any] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-review-inbox"),ProcessInfo.processInfo.arguments.contains("--scheduler-only") else {throw SummaryFailure.invalid}
        let preferences=UserDefaults.standard.dictionaryRepresentation() as NSDictionary
        let suite="HeartbeatLimitValidation-"+UUID().uuidString
        let validationSettings=UserDefaults(suiteName:suite)!
        defer {validationSettings.removePersistentDomain(forName:suite)}
        var checks:[String:Bool]=[:]
        let defaultService=HeartbeatService(container:nil,settings:validationSettings)
        checks["absent daily limit defaults to off"] = defaultService.dailyCallLimit == 0
        defaultService.dailyCallLimit=32
        checks["explicit numeric daily limit survives reopening"] = HeartbeatService(container:nil,settings:validationSettings).dailyCallLimit == 32
        defaultService.dailyCallLimit=0
        checks["explicit off survives reopening"] = HeartbeatService(container:nil,settings:validationSettings).dailyCallLimit == 0
        validationSettings.set(64,forKey:"paHeartbeatCallLimit")
        checks["legacy explicit limit is retained"] = HeartbeatService(container:nil,settings:validationSettings).dailyCallLimit == 64
        let runtime=HeartbeatRuntime.inactive
        let store=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        var now=ISO8601DateFormatter().date(from:"2026-10-07T12:00:00Z")!
        var device=HeartbeatDeviceState(lidClosed:false,userWake:true)
        let service=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device}),registration="fictional-review-owner"
        let day=BriefingRules.day(now),run=PAReviewRun(id:"fictional-run",started:now,manual:false,phase:"assessing",detail:"Fictional review; no request is sent")
        service.busy=true;service.capturedRegistration=registration;service.capturedDay=day;service.capturedControls=service.controlsRevision;service.capturedPowerRevision=service.powerRevision
        service.state.accounts[registration] = .init(checked:now,phase:"assessing",budgetDay:day,calls:0,pending:true,reviews:[run])
        try service.save();try service.claimCall(registration)
        checks["owned current-day call receipt persists before a request"] = service.state.accounts[registration]?.calls == 1
        func refused(_ owner:String=registration)->Bool {
            let before=service.state.accounts[registration]?.calls
            do {try service.claimCall(owner);return false} catch {return service.state.accounts[registration]?.calls == before}
        }
        checks["wrong account cannot claim a request"] = refused("another-fictional-owner")
        device.lidClosed=true;checks["closed laptop cannot claim inference"] = refused();device.lidClosed=false
        device.userWake=false;checks["dark wake cannot claim inference"] = refused();device.userWake=true
        service.willSleep(runtime:runtime);checks["sleep notification blocks late inference"] = refused()
        service.systemSleeping=false;checks["wake does not restore an interrupted request ownership"] = refused()
        service.capturedPowerRevision=service.powerRevision
        service.capturedControls=UUID();checks["changed controls cannot claim a late request"] = refused();service.capturedControls=service.controlsRevision;service.capturedPowerRevision=service.powerRevision
        let stopped=Task<Void,Never>{};stopped.cancel();service.task=stopped
        checks["cancelled parent cannot claim a late child request"] = refused();service.task=nil
        service.noteDraftEditing();checks["draft editing defers future automatic work without revoking captured ownership"] = service.composerActive && service.capturedControls == service.controlsRevision;service.lastTyping=nil
        now=now.addingTimeInterval(86400);checks["midnight cannot charge a captured job to a new day"] = refused();now=now.addingTimeInterval(-86400)
        service.busy=false;checks["finished job cannot claim another request"] = refused()
        let restored=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["actual cache recovery schedules fresh assessing work"] = restored.state.accounts[registration]?.phase == "idle" && restored.state.accounts[registration]?.retryAfter == now.addingTimeInterval(Double(restored.intervalMinutes)*60)
        checks["actual cache recovery preserves calls and review identity"] = restored.state.accounts[registration]?.calls == 1 && restored.state.accounts[registration]?.reviews?.first?.id == run.id
        checks["unfinished restored run is not labelled running"] = !restored.reviewInProgress(run,registration:registration)
        var history=run;history.steps=PAHeartbeatRules.stages();history.steps?[0].status="done";history.steps?[1].status="failed";history.failure="Fictional email failure";history.finished=now;history.phase="paused";history.briefUpdated=false
        try service.recordReview(registration,run:history)
        let historyReopened=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["stage history and failure survive actual cache reopening without copying source bodies"] = historyReopened.state.accounts[registration]?.reviews?.last?.steps?[1].status == "failed" && historyReopened.state.accounts[registration]?.reviews?.last?.failure == history.failure
        checks["stage updates preserve one run identity"] = historyReopened.state.accounts[registration]?.reviews?.count == 1
        for index in 0..<22 {var entry=history;entry.id="history-\(index)";try service.recordReview("separate-fictional-owner",run:entry)}
        let bounded=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["history is capped at twenty runs and isolated by account"] = bounded.state.accounts["separate-fictional-owner"]?.reviews?.count == 20 && bounded.state.accounts[registration]?.reviews?.count == 1 && bounded.state.accounts["separate-fictional-owner"]?.reviews?.first?.id == "history-2"
        service.busy=true;checks["only captured running account owns its activity"] = service.reviewInProgress(run,registration:registration) && !service.reviewInProgress(run,registration:"other")
        service.state.accounts[registration]!.calls=service.dailyCallLimit
        try service.save()
        checks["actual claim rejects an exhausted daily allowance"] = refused()
        let retainedCalls=service.state.accounts[registration]!.calls
        service.dailyCallLimit=0;service.capturedControls=service.controlsRevision
        try service.claimCall(registration)
        checks["actual uncapped claim retains count beyond former limit"] = service.state.accounts[registration]?.calls == (retainedCalls ?? 0)+1
        let waiting=PAHeartbeatRules.deferred(service.state.accounts[registration]!,now:now,reason:.allowance)
        service.state.accounts[registration]=waiting;try service.save()
        let uncappedReopened=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["reopened uncapped service releases saved allowance wait without losing receipts"] = PAHeartbeatRules.due(uncappedReopened.state.accounts[registration]!,now:now,day:day,allowance:uncappedReopened.dailyCallLimit) && uncappedReopened.state.accounts[registration]?.calls == waiting.calls && uncappedReopened.state.accounts[registration]?.reviews?.first?.id == run.id
        service.dailyCallLimit=64;service.capturedControls=service.controlsRevision
        service.state.accounts[registration]!.calls=64;service.state.accounts[registration]!.phase="assessing"

        var account=PAHeartbeatRules.interrupted(service.state.accounts[registration]!,now:now,foreground:true)
        checks["typing stops committed assessment and schedules a fresh run"] = account.phase == "idle" && account.retryAfter == now.addingTimeInterval(3600)
        account.phase="refreshing";account=PAHeartbeatRules.interrupted(account,now:now,foreground:true)
        service.state.accounts[registration]=account;try service.save()
        let idle=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["idle retry survives actual cache reopening"] = idle.state.accounts[registration]?.retryAfter == now.addingTimeInterval(60) && idle.state.accounts[registration]?.phase == "idle"
        account.phase="refreshing";service.state.accounts[registration]=account;try service.save()
        let collection=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["crashed source collection recovers without a false AI pause"] = collection.state.accounts[registration]?.phase == "idle" && collection.state.accounts[registration]?.retryReason == "sources"
        checks["recovered collection retains consumed allowance"] = collection.state.accounts[registration]?.calls == service.dailyCallLimit
        account=PAHeartbeatRules.quiet(account,fingerprint:"fictional-quiet",ready:[],pending:false)
        service.state.accounts[registration]=account;try service.save()
        let quiet=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["quiet completed check clears stale pending state in cache"] = quiet.state.accounts[registration]?.pending == false && quiet.state.accounts[registration]?.retryAfter == nil
        // Virtual wall-clock timeline across actual service receipts, completion and cache reopening.
        // Source/AI stages are represented by fictional metadata, not real source reads or requests.
        let timelineStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let timelineOwner="fictional-sustained-owner"
        var timeline=HeartbeatService(container:timelineStore,settings:validationSettings,clock:{now},deviceState:{device}),cycles=0,limits=0,outages=0
        var timelineValid=true
        for hour in 0..<72 {
            now=now.addingTimeInterval(hour == 24 ? 11*3600 : 3600) // a missed block catches up once
            timeline=HeartbeatService(container:timelineStore,settings:validationSettings,clock:{now},deviceState:{device})
            var saved=timeline.state.accounts[timelineOwner] ?? .init()
            guard PAHeartbeatRules.due(saved,now:now,minutes:60,day:BriefingRules.day(now),allowance:timeline.dailyCallLimit) else {continue}
            let currentDay=BriefingRules.day(now)
            timeline.busy=true;timeline.capturedRegistration=timelineOwner;timeline.capturedDay=currentDay;timeline.capturedControls=timeline.controlsRevision;timeline.capturedPowerRevision=timeline.powerRevision
            saved.phase="refreshing";saved.checked=now;saved.pending=true;timeline.state.accounts[timelineOwner]=saved;try timeline.save()
            if hour%17 == 0 {
                let before=PAHeartbeatRules.callCount(saved,day:currentDay)
                saved=PAHeartbeatRules.interrupted(saved,now:now,foreground:false)
                timeline.state.accounts[timelineOwner]=saved;try timeline.save()
                let reopened=HeartbeatService(container:timelineStore,settings:validationSettings,clock:{now},deviceState:{device})
                timelineValid = timelineValid && reopened.state.accounts[timelineOwner]?.retryReason == "sources" && PAHeartbeatRules.callCount(reopened.state.accounts[timelineOwner]!,day:currentDay) == before
                outages+=1;continue
            }
            saved=PAHeartbeatRules.collectingMail(saved,enabled:["healthy","intermittent"],ready:["healthy"],issues:["intermittent":"Fictional outage"],now:now)
            saved.phase="assessing";timeline.state.accounts[timelineOwner]=saved;try timeline.save()
            do {
                for _ in 0..<3 {try timeline.claimCall(timelineOwner)}
                saved=PAHeartbeatRules.clearWait(timeline.state.accounts[timelineOwner]!)
                saved=PAHeartbeatRules.completedMail(saved,fingerprints:["healthy":"fixture-\(hour)"],pending:[],now:now);saved.pending=true
                try timeline.finishAssessment(timelineOwner,account:saved)
                timeline.busy=false
                let reopened=HeartbeatService(container:timelineStore,settings:validationSettings,clock:{now},deviceState:{device}),value=reopened.state.accounts[timelineOwner]!
                timelineValid = timelineValid && value.phase == "idle" && value.assessed == now && value.mailLanes?["healthy"]?.fingerprint == "fixture-\(hour)" && value.mailLanes?["intermittent"]?.pending == true && !PAHeartbeatRules.due(value,now:now.addingTimeInterval(1),minutes:60)
                cycles+=1
            } catch is HeartbeatBudgetExhausted {
                saved=PAHeartbeatRules.deferred(timeline.state.accounts[timelineOwner]!,now:now,reason:.allowance)
                timeline.state.accounts[timelineOwner]=saved;try timeline.save();limits+=1
                let reopened=HeartbeatService(container:timelineStore,settings:validationSettings,clock:{now},deviceState:{device})
                timelineValid = timelineValid && reopened.state.accounts[timelineOwner]?.pending == true && reopened.state.accounts[timelineOwner]?.retryReason == "allowance"
            }
        }
        checks["72-slot persisted timeline retains partial lanes, source retries, quota waits and one catch-up"] = timelineValid && cycles > 20 && outages > 0
        checks["completed account cannot be finished by an idle service"] = {do {timeline.busy=false;try timeline.finishAssessment(timelineOwner,account:timeline.state.accounts[timelineOwner]!);return false} catch {return true}}()
        checks["failed recovered inference catches up after missed intervals"] = PAHeartbeatRules.due(restored.state.accounts[registration]!,now:now.addingTimeInterval(86400),minutes:restored.intervalMinutes)
        let recoveryTime=restored.state.accounts[registration]!.checked!
        var legacyPause=restored.state.accounts[registration]!;legacyPause.phase="paused";legacyPause.retryAfter=nil;legacyPause.retryReason=nil
        service.state.accounts[registration]=legacyPause;try service.save()
        let legacyRecovered=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["old paused cache migrates without postponing retry or losing receipts"] = legacyRecovered.state.accounts[registration]?.retryAfter == recoveryTime.addingTimeInterval(Double(legacyRecovered.intervalMinutes)*60) && legacyRecovered.state.accounts[registration]?.calls == legacyPause.calls && legacyRecovered.state.accounts[registration]?.reviews?.first?.id == legacyPause.reviews?.first?.id
        let firstRetry=PAHeartbeatRules.failed(legacyPause,now:now,minutes:service.intervalMinutes)
        service.state.accounts[registration]=firstRetry;try service.save()
        let reopenedFailure=HeartbeatService(container:store,settings:validationSettings,clock:{now.addingTimeInterval(30)})
        checks["failed run cannot retry early after actual reopening"] = !PAHeartbeatRules.due(reopenedFailure.state.accounts[registration]!,now:now.addingTimeInterval(30),minutes:service.intervalMinutes)
        let nextDue=now.addingTimeInterval(Double(service.intervalMinutes)*60)
        let dueFailure=HeartbeatService(container:store,settings:validationSettings,clock:{nextDue})
        checks["failed run becomes due at configured interval after actual reopening"] = PAHeartbeatRules.due(dueFailure.state.accounts[registration]!,now:nextDue,minutes:service.intervalMinutes)
        var fresh=dueFailure.state.accounts[registration]!;fresh.phase="assessing";fresh.checked=nextDue
        // A later allowance day keeps prior run history but grants only today's calls.
        now=nextDue.addingTimeInterval(86400)
        service.state.accounts[registration]=fresh;service.busy=true;service.capturedRegistration=registration;service.capturedDay=BriefingRules.day(now);service.capturedControls=service.controlsRevision;service.capturedPowerRevision=service.powerRevision
        try service.save();try service.claimCall(registration)
        fresh=service.state.accounts[registration]!;fresh.pending=false;fresh=PAHeartbeatRules.clearWait(fresh)
        try service.finishAssessment(registration,account:fresh);service.busy=false
        let completedRecovery=HeartbeatService(container:store,settings:validationSettings,clock:{now},deviceState:{device})
        checks["fresh recovery completion retains earlier history and clears retry"] = completedRecovery.state.accounts[registration]?.retryAfter == nil && completedRecovery.state.accounts[registration]?.assessed == now && completedRecovery.state.accounts[registration]?.reviews?.first?.id == run.id && completedRecovery.state.accounts[registration]?.calls == 1
        let sleepStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let sleepService=HeartbeatService(container:sleepStore,settings:validationSettings,clock:{now},deviceState:{device})
        let beforeSleep=PAHeartbeatAccount(checked:now.addingTimeInterval(-7200),phase:"idle",calls:2,assessed:now.addingTimeInterval(-7200))
        var activeSleep=beforeSleep;activeSleep.phase="assessing";activeSleep.checked=now;activeSleep.calls=3
        activeSleep.reviews=[.init(id:"fictional-sleep",started:now,manual:false,phase:"running",detail:"Fictional",calls:1,steps:PAHeartbeatRules.stages())]
        sleepService.state.accounts[registration]=activeSleep;sleepService.busy=true;sleepService.capturedRegistration=registration;sleepService.capturedPrior=beforeSleep
        try sleepService.save();sleepService.willSleep(runtime:runtime)
        let sleepReopened=HeartbeatService(container:sleepStore,settings:validationSettings,clock:{now},deviceState:{device})
        let retainedSleep=sleepReopened.state.accounts[registration]!
        checks["sleep notification persists the overdue anchor before task unwind"] = retainedSleep.checked == beforeSleep.checked && PAHeartbeatRules.due(retainedSleep,now:now,minutes:sleepService.intervalMinutes)
        checks["sleep notification keeps claimed calls and a distinct history outcome"] = retainedSleep.calls == 3 && retainedSleep.reviews?.last?.outcome() == "Paused for sleep"
        service.statusRegistration=registration;service.status="Fictional previous owner's review detail"
        checks["status from another account is not displayed"] = !service.statusFor("other-fictional-owner").contains("previous owner's")
        let badStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true)),badData=Data("not a heartbeat record".utf8)
        badStore.mainContext.insert(CachedDashboard(key:"paHeartbeat",data:badData));try badStore.mainContext.save()
        let unreadable=HeartbeatService(container:badStore,settings:validationSettings,clock:{now},deviceState:{device})
        checks["unreadable review state blocks scheduling"] = !unreadable.readable && unreadable.statusFor(registration).contains("unavailable")
        checks["unreadable original cache is preserved"] = try badStore.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first?.data == badData
        // Exercise the real orchestration with injected source-free children,
        // including failures which used to prevent the brief from ever running.
        for scenario in ["email failure","feedback failure","suggestions failure","learning failure","missing sources","foreground stop","successful cycle","notification toggle","no-op controls","interval change","model change","draft editing","source scope change","source failure isolation","capped email failure"] {
            let cycleStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let cycle=HeartbeatService(container:cycleStore,settings:validationSettings,clock:{now},deviceState:{device})
            cycle.dailyCallLimit=0
            if scenario == "capped email failure" {
                cycle.dailyCallLimit=8
                cycle.state.accounts["fixture-cycle"] = .init(budgetDay:BriefingRules.day(now),calls:7)
            }
            var ports=HeartbeatRuntime.inactive,order:[String]=[],updated=false,expired:HeartbeatChildRequest?
            var env=ports.environment()
            env.registration="fixture-cycle";env.contextEnabled=true;env.inferenceVerified=true;env.permitted=true;env.emailEnabled=true;env.proposalsEnabled=true
            ports.environment={env}
            var snapshots=ports.currentSources(false)
            snapshots.nativeReady=scenario != "missing sources"
            ports.prepareSources={request in try request.validate();order.append("snapshots");return snapshots}
            ports.currentSources={_ in snapshots}
            ports.activity={_,_ in .init(briefUpdated:updated)}
            ports.feedback={request in
                try request.validate();order.append("feedback")
                if scenario == "feedback failure" {try request.claim()}
                return .init(failure:scenario == "feedback failure" ? "fixture feedback failure" : nil,skipped:scenario != "feedback failure")
            }
            ports.email={request in
                try request.validate();try request.claim();expired=request;order.append("email")
                if scenario == "foreground stop" {cycle.userStartedTyping()}
                if scenario == "notification toggle" {
                    let previous=cycle.controlsRevision
                    cycle.notificationsEnabled.toggle()
                    await Task.yield()
                    try request.validate()
                    checks["notification delivery changes retain the running analysis owner"] = cycle.controlsRevision == previous
                }
                if ["interval change","model change","draft editing","source scope change","source failure isolation"].contains(scenario) {
                    let previous=cycle.controlsRevision
                    if scenario == "interval change" {cycle.intervalMinutes=30}
                    if scenario == "model change" {env.model="new-fictional-model"}
                    if scenario == "draft editing" {cycle.noteDraftEditing()}
                    if scenario == "source scope change" || scenario == "source failure isolation" {env.scope="changed-independent-sources"}
                    await Task.yield();try request.validate()
                    checks["ordinary \(scenario) retains the running scheduler owner"]=cycle.controlsRevision == previous
                }
                if scenario == "no-op controls" {
                    let previous=cycle.controlsRevision
                    let enabled=cycle.enabled,notifications=cycle.notificationsEnabled,interval=cycle.intervalMinutes,limit=cycle.dailyCallLimit
                    cycle.enabled=enabled;cycle.notificationsEnabled=notifications;cycle.intervalMinutes=interval;cycle.dailyCallLimit=limit
                    await Task.yield()
                    try request.validate()
                    checks["no-op heartbeat controls retain the running analysis owner"] = cycle.controlsRevision == previous
                }
                return .init(failure:scenario == "email failure" || scenario == "capped email failure" || scenario == "source failure isolation" ? "fixture transport failure" : nil)
            }
            ports.learning={request in
                try request.validate();order.append("learning")
                return .init(failure:scenario == "learning failure" ? "fixture learning failure" : nil,detail:"No pending learning",skipped:scenario != "learning failure")
            }
            ports.suggestions={request in
                try request.validate();try request.claim();order.append("suggestions")
                return .init(failure:scenario == "suggestions failure" ? "result.suggestions[0].kind: unsupported" : nil)
            }
            ports.brief={request in
                try request.validate();try request.claim();order.append("brief");updated=true;return .init()
            }
            cycle.check(runtime:ports,manual:true)
            for _ in 0..<100 where cycle.busy {try await Task.sleep(for:.milliseconds(10))}
            let saved=cycle.state.accounts[env.registration],history=saved?.reviews?.last
            if scenario == "capped email failure" {
                checks["final allowed call retains its actual email failure before allowance wait"] = history?.steps?.first{$0.id == "email"}?.detail == "fixture transport failure" && history?.steps?.first{$0.id == "email"}?.status == "failed" && !updated && saved?.retryReason == "allowance" && saved?.calls == 8
            } else if scenario == "foreground stop" {
                checks["orchestration stops all later stages when foreground takes ownership"] = !cycle.busy && !updated && order == ["snapshots","feedback","email"] && history?.phase == "interrupted"
            } else {
                checks["orchestration writes brief after \(scenario)"] = !cycle.busy && updated && order.last == "brief" && history?.briefUpdated == true
                if scenario.hasSuffix("failure") {
                    let failedStage=scenario == "feedback failure" ? "feedback" : scenario == "email failure" ? "email" : scenario == "learning failure" ? "learning" : "suggestions"
                    checks["orchestration retains exact failed stage and schedules fresh recovery: \(scenario)"] = history?.steps?.first{$0.id == failedStage}?.status == "failed" && history?.outcome() == "Partly completed" && saved?.retryAfter == now.addingTimeInterval(Double(cycle.intervalMinutes)*60) && saved?.pending == true
                }
                if scenario == "source failure isolation" {checks["one child source failure survives a changed parent scope without blocking the brief"]=history?.steps?.first{$0.id == "email"}?.status == "failed" && history?.outcome() == "Partly completed" && saved?.pending == true}
                if scenario == "missing sources" {checks["missing native cache does not start suggestions or block cached brief"] = !order.contains("suggestions") && history?.steps?.first{$0.id == "sources"}?.status == "waiting"}
                if scenario == "successful cycle" {checks["full orchestration records all six stages in order"] = order == ["snapshots","feedback","email","learning","suggestions","brief"] && history?.outcome() == "Completed"}
            }
            checks["completed child cannot claim or save after parent ended: \(scenario)"] = {guard let expired else{return false};do{try expired.validate();return false}catch{do{try expired.claim();return false}catch{return true}}}()
        }
        let currentPreferences=UserDefaults.standard.dictionaryRepresentation()
        let changedKeys=Set(preferences.allKeys.compactMap{$0 as? String}).union(currentPreferences.keys).filter{!NSDictionary(dictionary:["value":preferences[$0] ?? NSNull()]).isEqual(to:["value":currentPreferences[$0] ?? NSNull()])}.sorted()
        checks["real settings remain unchanged"] = changedKeys.allSatisfy{$0 == "METAL_DEVICE_WRAPPER_TYPE" || $0 == "NSWindow Frame reviewInboxValidation"}
        return ["checks":checks,"passed":checks.values.filter{$0}.count,"total":checks.count,"storage":"Fictional in-memory SwiftData; actual HeartbeatService claims, completion and recovery. Virtual 72-slot timeline plus eight actual orchestration scenarios with injected children; not real OS sleep/wake or provider acceptance.","AIRequests":0,"nativeChanges":0,"timelineCompleted":cycles,"timelineAllowanceWaits":limits,"timelineSourceRetries":outages,"changedPreferenceKeys":changedKeys]
    }
    func withRunningReviewFixture<T>(_ operation:()->T)->T {
        let original=busy;busy=true;defer{busy=original};return operation()
    }
    #endif
}
