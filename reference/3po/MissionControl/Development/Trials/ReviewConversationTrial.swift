#if DEBUG
import Foundation
import Observation

/// Fictional, in-memory interaction trial. No inference, EventKit or app stores.
struct ReviewTrialAction: Identifiable, Equatable, Codable {
    enum Destination: String, Codable { case project, calendar }
    var id: String
    var title: String
    var date: String
    var detail: String
    var destination: Destination
    var provisional = false
    static let examples: [Self] = [
        .init(id:"nov-task",title:"Prepare Michaelmas presentation",date:"No deadline assigned",detail:"IIB MEng Project · the source gives a presentation window, not a preparation deadline.",destination:.project),
        .init(id:"milestone-task",title:"Submit technical milestone report",date:"21 January 2027 · deadline 16:00",detail:"IIB MEng Project · due date 21 January; exact 16:00 deadline retained in notes.",destination:.project),
        .init(id:"report-task",title:"Submit final report",date:"31 May 2027 · deadline 16:00",detail:"IIB MEng Project · due date 31 May; exact 16:00 deadline retained in notes.",destination:.project),
        .init(id:"presentation-task",title:"Prepare final project presentation",date:"4 June 2027",detail:"IIB MEng Project · date-only milestone; presentation time has not been allocated.",destination:.project),
        .init(id:"nov-26",title:"Michaelmas presentation window",date:"26 November 2026 · 08:30–17:00",detail:"Example Calendar · provisional window, not your allocated presentation slot.",destination:.calendar,provisional:true),
        .init(id:"nov-27",title:"Michaelmas presentation window",date:"27 November 2026 · 08:30–17:00",detail:"Example Calendar · provisional window, not your allocated presentation slot.",destination:.calendar,provisional:true),
        .init(id:"milestone-calendar",title:"Technical milestone report deadline",date:"21 January 2027 · 16:00–16:15",detail:"Example Calendar · 15-minute deadline marker at 16:00; not a meeting.",destination:.calendar),
        .init(id:"report-calendar",title:"Final report deadline",date:"31 May 2027 · 16:00–16:15",detail:"Example Calendar · 15-minute deadline marker at 16:00; not a meeting.",destination:.calendar),
        .init(id:"presentation-calendar",title:"Final project presentation date",date:"4 June 2027 · all day",detail:"Example Calendar · date marker only; individual presentation time is unconfirmed.",destination:.calendar)
    ]
}
struct ReviewTrialMessage: Identifiable, Equatable {
    var id = UUID()
    var human: Bool
    var text: String
}
struct ReviewTrialJob: Identifiable, Equatable {
    enum State: String { case queued, running, succeeded, partial, failed, stopped }
    enum Outcome: String { case waiting, saved, uncertain }
    var id = UUID()
    var title = "Add IIB project dates"
    var reply: String
    var actions: [ReviewTrialAction]
    var owner: Int
    var state: State = .queued
    var outcomes: [String: Outcome] = [:]
    var ticks = 0
    var uncertainCalendar = false
    var error: String?
    var acknowledged = false
    var savedCount: Int { outcomes.values.filter { $0 == .saved }.count }
    var finishedCount: Int { outcomes.values.filter { $0 != .waiting }.count }
    var progress: Double { actions.isEmpty ? 0 : Double(finishedCount) / Double(actions.count) }
    var status: String {
        switch state {
        case .queued: "Queued"
        case .running: "Adding your project dates"
        case .succeeded: "\(savedCount) actions completed"
        case .partial: "\(savedCount) of \(actions.count) confirmed · needs attention"
        case .failed: "Couldn’t complete your request"
        case .stopped: "Stopped · \(savedCount) actions confirmed"
        }
    }
}
@MainActor @Observable final class ReviewTrialEngine {
    var selection = Set(ReviewTrialAction.examples.map(\.id))
    var messages: [ReviewTrialMessage] = []
    private(set) var jobs: [ReviewTrialJob] = []
    private var projectEntries: [Int:[ReviewTrialAction]] = [:]
    private var calendarRecords: [Int:[ReviewTrialAction]] = [:]
    var projectTasks: [ReviewTrialAction] {projectEntries[owner] ?? []}
    var calendarEntries: [ReviewTrialAction] {calendarRecords[owner] ?? []}
    var visibleJobs: [ReviewTrialJob] {jobs.filter { $0.owner == owner }}
    private(set) var heartbeatTicks: Int?
    private(set) var activeJobID: UUID?
    private(set) var owner = 1
    private(set) var paused = false
    var injectUncertainSave = false
    var automatic = true
    var heartbeatNote: String?
    var queuedCount: Int { visibleJobs.filter { $0.state == .queued }.count }
    var activeJob: ReviewTrialJob? { jobs.first { $0.id == activeJobID } }
    var attention: ReviewTrialJob? { visibleJobs.last { !$0.acknowledged && [.partial,.failed,.stopped].contains($0.state) } }
    var lastOutcome: ReviewTrialJob? { visibleJobs.last { $0.state != .queued && $0.state != .running } }
    var heartbeatProgress: Double { Double(heartbeatTicks ?? 0) / 20 }
    var heartbeatStage: String {
        switch heartbeatTicks ?? 0 {
        case 0..<5: "Reviewing your email"
        case 5..<10: "Organising memory"
        case 10..<15: "Preparing suggestions"
        default: "Updating today’s brief"
        }
    }
    var selectedActions: [ReviewTrialAction] { ReviewTrialAction.examples.filter { selection.contains($0.id) } }
    var title: String {
        if heartbeatTicks != nil { return heartbeatStage }
        if activeJob != nil { return "Adding your project dates" }
        if let attention { return attention.state == .partial ? "One action needs checking" : attention.status }
        if queuedCount > 0 { return paused ? "Queue paused" : "Your request is queued" }
        if let lastOutcome, !lastOutcome.acknowledged { return lastOutcome.status }
        return heartbeatNote ?? "3PO is ready"
    }
    var subtitle: String {
        if heartbeatTicks != nil { return "Heartbeat · \(Int(heartbeatProgress * 100))%" + (queuedCount > 0 ? " · \(queuedCount) queued" : "") }
        if let job = activeJob { return "\(job.finishedCount) of \(job.actions.count) actions" + (queuedCount > 0 ? " · \(queuedCount) queued" : "") }
        if let attention { return attention.error ?? "Open activity for the details" }
        if queuedCount > 0 { return paused ? "Continue when you’re ready" : "Waiting for the current job" }
        return "Open chat or inspect activity"
    }
    var progress: Double? { heartbeatTicks != nil ? heartbeatProgress : activeJob?.progress }
    func startHeartbeat() {
        guard heartbeatTicks == nil, activeJobID == nil, queuedCount == 0 else { return }
        heartbeatNote = nil; heartbeatTicks = 0
    }
    func finishHeartbeat() {
        guard heartbeatTicks != nil else { return }
        heartbeatTicks = nil; heartbeatNote = "Heartbeat complete"; beginNext()
    }
    @discardableResult func submit(_ raw: String) -> Bool {
        let words = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return false }
        messages.append(.init(human:true,text:words))
        let normal = words.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:".!👍 "))
        if normal.contains("only") || normal.contains("leave november") || normal.contains("without november") {
            if normal.contains("calendar only") || normal.contains("only calendar") {
                selection = Set(ReviewTrialAction.examples.filter { $0.destination == .calendar }.map(\.id))
            } else if normal.contains("task") || normal.contains("project only") {
                selection = Set(ReviewTrialAction.examples.filter { $0.destination == .project }.map(\.id))
            } else if normal.contains("november") {
                selection.subtract(["nov-task","nov-26","nov-27"])
            } else {
                messages.append(.init(human:false,text:"In this scripted demo, use the action checkboxes, ‘project tasks only’, ‘calendar only’, or ‘leave November out’. Then say yes to the revised plan.")); return false
            }
            messages.append(.init(human:false,text:"I’ve adjusted the plan below. Would you like me to add these \(selectedActions.count) actions?")); return false
        }
        guard words == "👍" || ["yes","yep","yes please","go ahead","do that","add these","ok","okay"].contains(normal) else {
            messages.append(.init(human:false,text:"This demo understands approval and a few plan changes. Select the actions below, then say ‘yes’, or try ‘project tasks only’. No actions have been added.")); return false
        }
        let actions = selectedActions
        guard !actions.isEmpty else { messages.append(.init(human:false,text:"Choose at least one action first.")); return false }
        if jobs.contains(where:{ [.queued,.running].contains($0.state) && $0.actions == actions && $0.owner == owner }) {
            messages.append(.init(human:false,text:"That exact plan is already queued. I’ll keep its existing request rather than add it twice.")); return false
        }
        if visibleJobs.contains(where: { job in job.actions.contains { actions.contains($0) && job.outcomes[$0.id] == .uncertain } }) {
            messages.append(.init(human:false,text:"One selected action has an unconfirmed save. Check that existing operation in activity before submitting it again.")); return false
        }
        let job = ReviewTrialJob(reply:words,actions:actions,owner:owner,uncertainCalendar:injectUncertainSave)
        injectUncertainSave = false; jobs.append(job)
        messages.append(.init(human:false,text:heartbeatTicks != nil ? "Queued behind the heartbeat. You can close this conversation; I’ll work through these \(actions.count) actions next and show the outcome in the status pill." : "Accepted. You can close this conversation while I work through these \(actions.count) actions. The status pill will show the outcome."))
        beginNext(); return true
    }
    private func beginNext() {
        guard heartbeatTicks == nil, activeJobID == nil, !paused,
              let index = jobs.firstIndex(where: { $0.state == .queued }) else { return }
        guard jobs[index].owner == owner else {
            jobs[index].state = .failed; jobs[index].error = "The account changed. Reopen the plan before continuing."; paused = true; return
        }
        let blocked = jobs.contains { earlier in earlier.id != jobs[index].id && earlier.owner == jobs[index].owner && earlier.actions.contains { action in jobs[index].actions.contains(action) && earlier.outcomes[action.id] == .uncertain } }
        guard !blocked else {
            jobs[index].error = "Check the earlier unconfirmed Calendar save before continuing this request."; paused = true; return
        }
        jobs[index].error = nil
        jobs[index].state = .running; activeJobID = jobs[index].id
    }
    func tick() {
        if let ticks = heartbeatTicks {
            if ticks >= 19 { finishHeartbeat() } else { heartbeatTicks = ticks + 1 }
            return
        }
        beginNext()
        guard let id = activeJobID, let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].ticks += 1
        guard jobs[index].ticks % 2 == 0 else { return }
        guard let action = jobs[index].actions.first(where: { jobs[index].outcomes[$0.id] == nil }) else { complete(index); return }
        let alreadyExists = (projectTasks + calendarEntries).contains { $0.id == action.id }
        if !alreadyExists {
            if action.destination == .project { projectEntries[owner,default:[]].append(action) } else { calendarRecords[owner,default:[]].append(action) }
        }
        if action.destination == .calendar && jobs[index].uncertainCalendar {
            jobs[index].uncertainCalendar = false; jobs[index].outcomes[action.id] = .uncertain
        } else { jobs[index].outcomes[action.id] = .saved }
        if jobs[index].finishedCount == jobs[index].actions.count { complete(index) }
    }
    private func complete(_ index: Int) {
        if jobs[index].outcomes.values.contains(.uncertain) {
            jobs[index].state = .partial; jobs[index].error = "Calendar save was not confirmed. Check it before trying again."; paused = true
        } else { jobs[index].state = .succeeded }
        messages.append(.init(human:false,text:jobs[index].state == .partial ? "\(jobs[index].savedCount) actions are confirmed. One Calendar save needs checking; I won’t repeat it automatically. Open activity for the affected entry." : "Done. \(jobs[index].savedCount) actions are confirmed in your example project and Calendar."))
        activeJobID = nil
    }
    func stop() {
        if heartbeatTicks != nil { heartbeatTicks = nil; heartbeatNote = "Heartbeat stopped" }
        if let id = activeJobID, let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].state = .stopped; jobs[index].error = "Completed actions are retained. The remaining actions have stopped."
        }
        activeJobID = nil; paused = true
    }
    func continueQueue() { paused = false; beginNext() }
    func acknowledge(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].acknowledged = true
    }
    /// Simulated native readback; checking a save never issues a second creation.
    func checkUncertain(_ jobID: UUID, actionID: String) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID && $0.owner == owner }), jobs[index].outcomes[actionID] == .uncertain,
              calendarEntries.contains(where: { $0.id == actionID }) else { return }
        jobs[index].outcomes[actionID] = .saved
        if jobs[index].actions.allSatisfy({ jobs[index].outcomes[$0.id] == .saved }) { jobs[index].state = .succeeded; jobs[index].error = nil }
        messages.append(.init(human:false,text:jobs[index].state == .succeeded ? "Checked the original Calendar save. All \(jobs[index].savedCount) actions are now confirmed; no duplicate entry was created." : "Checked the original Calendar save. \(jobs[index].savedCount) actions are confirmed; the remaining work is still stopped."))
    }
    func changeOwner() {
        stop()
        for index in jobs.indices where jobs[index].state == .queued {
            jobs[index].state = .failed; jobs[index].error = "The account changed. This request was not retargeted."
        }
        owner += 1; messages = []; selection = Set(ReviewTrialAction.examples.map(\.id))
        paused = false; heartbeatNote = "Example account changed"
    }
    func reset() {
        selection = Set(ReviewTrialAction.examples.map(\.id)); messages = []; jobs = []
        projectEntries = [:]; calendarRecords = [:]; heartbeatTicks = nil; activeJobID = nil
        owner = 1; paused = false; injectUncertainSave = false; heartbeatNote = nil
    }
    func runClock() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for:.milliseconds(650)) } catch { return }
            if automatic { tick() }
        }
    }
}
#endif
