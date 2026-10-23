import Foundation
import Observation

/// Saved output for the human to inspect. These records never authorise or replay work.
enum AIActivityKind: String, Codable, CaseIterable {
    case chat, action, review, heartbeat, feedback
    var title: String {
        switch self {
        case .chat: "3PO chat"
        case .action: "3PO actions"
        case .review: "Review"
        case .heartbeat: "Heartbeat"
        case .feedback: "Feedback"
        }
    }
}

/// Activity follows typed work, never a guess from conversational prose.
enum AIActivityWork {
    static let descriptions:[String:String] = [
        "read_calendar":"Checking Calendar…", "read_reminders":"Checking Reminders…",
        "read_item_details":"Checking item details…", "change_calendar":"Updating Calendar…",
        "change_reminder":"Updating Reminders…", "search_mail":"Searching email…",
        "continue_mail":"Searching email…", "read_email":"Reading an email…",
        "search_whatsapp":"Searching WhatsApp…", "read_weather":"Checking the weather…",
        "dismiss_suggestion":"Acknowledging a suggestion…", "undo_apple_change":"Undoing a change…",
        "organise_memory":"Organising memory…", "save_memory":"Saving a memory…",
        "remember_context":"Saving a memory…", "change_memory":"Updating memory…",
        "read_life_items":"Checking project items…", "create_life_items":"Adding project items…",
        "execute_review_actions":"Completing Review actions…",
        "change_life_item":"Updating a project item…", "link_life_item":"Linking project items…",
        "unlink_life_item":"Unlinking project items…", "show_project_view":"Opening a project…",
        "undo_life_edit":"Undoing a project change…", "delete_life_item":"Removing a project item…",
        "restore_life_item":"Restoring a project item…", "reorder_life_item":"Reordering project items…"
    ]
    static func includes(_ tools:[String],confirmed:Int=0,unconfirmed:Int=0)->Bool {
        let reads:Set<String>=["read_calendar","read_reminders","read_item_details","search_mail","continue_mail","read_email","search_whatsapp","read_weather","read_life_items"]
        return confirmed > 0 || unconfirmed > 0 || tools.contains{descriptions[$0] != nil && !reads.contains($0)}
    }
    static func running(_ tools:[String])->String {
        tools.reversed().compactMap{descriptions[$0]}.first ?? "Working on your actions…"
    }
    static func completed(_ tools:[String],receipts:[String],confirmed:Int)->String {
        if !receipts.isEmpty {return receipts.joined(separator:" · ")}
        if confirmed > 0 {return "\(confirmed) action\(confirmed == 1 ? "" : "s") completed"}
        let checked:[String:String] = ["read_calendar":"Checked Calendar", "read_reminders":"Checked Reminders", "read_item_details":"Checked item details", "search_mail":"Searched email", "continue_mail":"Searched email", "read_email":"Read the email", "search_whatsapp":"Searched WhatsApp", "read_weather":"Checked the weather", "read_life_items":"Checked project items"]
        return tools.reversed().compactMap{checked[$0]}.first ?? "No new changes were confirmed."
    }
}

enum AIActivityStatus: String, Codable, CaseIterable {
    case queued, running, succeeded, partial, failed, stopped, interrupted, needsAnswer, uncertain, replied, resolved
    var title: String {
        switch self {
        case .queued: "Queued"
        case .running: "Working"
        case .succeeded: "Completed"
        case .partial: "Partly completed"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .interrupted: "Interrupted"
        case .needsAnswer: "Needs your answer"
        case .replied: "Replied"
        case .resolved: "Resolved"
        case .uncertain: "Outcome unconfirmed"
        }
    }
    var isTerminal: Bool { self != .queued && self != .running }
    var isFailure:Bool {[.partial,.failed,.interrupted,.uncertain].contains(self)}
    var needsAttention: Bool {
        [.partial, .failed, .interrupted, .needsAnswer, .uncertain].contains(self)
    }
    var symbol: String {
        switch self {
        case .queued: "clock"
        case .running: "sparkles"
        case .succeeded: "checkmark.circle.fill"
        case .partial, .failed, .interrupted, .uncertain: "exclamationmark.circle.fill"
        case .stopped: "stop.circle"
        case .needsAnswer: "questionmark.circle.fill"
        case .replied: "bubble.left.and.bubble.right"
        case .resolved: "checkmark.circle"
        }
    }
}

/// Navigation hints are exact local targets, never instructions to infer or mutate.
enum AIActivityDestination: Codable, Equatable {
    case assistant(targetID: String? = nil)
    case review(targetID: String? = nil)
    case heartbeat(targetID: String? = nil)
    case project(targetID: String? = nil)
    case calendar(targetID: String? = nil)
    case reminders(targetID: String? = nil)
    case feedback(targetID: String? = nil)

    var targetID: String? {
        switch self {
        case .assistant(let id), .review(let id), .heartbeat(let id), .project(let id),
             .calendar(let id), .reminders(let id), .feedback(let id): id
        }
    }
    var title: String {
        switch self {
        case .assistant: "Open chat"
        case .review: "Open Review conversation"
        case .heartbeat: "Open heartbeat"
        case .project: "View project"
        case .calendar: "View Calendar"
        case .reminders: "View Reminders"
        case .feedback: "View feedback"
        }
    }
    var symbol: String {
        switch self {
        case .assistant: "bubble.left.and.bubble.right"
        case .review: "tray"
        case .heartbeat: "waveform.path.ecg"
        case .project: "folder"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .feedback: "text.bubble"
        }
    }
}

struct AIActivityRecord: Codable, Equatable, Identifiable {
    var id: String
    var registration: String
    var kind: AIActivityKind
    var state: AIActivityStatus
    var title: String
    var message: String
    var progress: Double?
    var created: Date
    var finished: Date?
    var destination: AIActivityDestination?
    var acknowledged: Bool

    init(id: String, registration: String, kind: AIActivityKind, state: AIActivityStatus,
         title: String, message: String, progress: Double? = nil, created: Date = .now,
         finished: Date? = nil, destination: AIActivityDestination? = nil, acknowledged: Bool = false) {
        self.id = id; self.registration = registration; self.kind = kind; self.state = state
        self.title = title; self.message = message; self.progress = progress; self.created = created
        self.finished = finished; self.destination = destination; self.acknowledged = acknowledged
    }
    var needsAttention: Bool { state.needsAttention && !acknowledged }
    var failureAlert:Bool {state.isFailure && !acknowledged}
    var date: Date { finished ?? created }
}

/// Ephemeral feedback from a direct UI action, never an AI Activity record.
struct AIActivityFeedback: Equatable {
    var registration: String
    var message: String
    var date: Date = .now
    var expiry: Date { date.addingTimeInterval(AIActivityPillRules.successDuration) }
}

/// A local display choice; this never changes a saved outcome or resumes work.
enum AIActivityPillRules {
    static let successDuration:TimeInterval = 6
    static func feedback(_ feedback:AIActivityFeedback?,displayed:AIActivityRecord?,registration:String,now:Date = .now)->AIActivityFeedback? {
        guard let feedback,feedback.registration == registration,now >= feedback.date,now < feedback.expiry else {return nil}
        // Running work and unresolved attention retain priority. A newer AI
        // completion can supersede an earlier manual-action confirmation.
        if let displayed {
            guard displayed.state == .succeeded,feedback.date >= displayed.date else {return nil}
        }
        return feedback
    }
    static func displayed(_ records:[AIActivityRecord],current:AIActivityRecord?,registration:String,now:Date = .now)->AIActivityRecord? {
        if let current,current.registration == registration,current.state == .running {return current}
        let outcomes=records.filter{$0.registration == registration && $0.kind != .heartbeat && $0.state.isTerminal && !AIActivitySummary.contextOnly($0)}.sorted {
            $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id
        }
        if let attention=outcomes.first(where:{$0.needsAttention}) {return attention}
        // Acknowledging the latest outcome must not revive an older success.
        guard let latest=outcomes.first,latest.state == .succeeded,!latest.acknowledged,now >= latest.date,now.timeIntervalSince(latest.date) < successDuration else {return nil}
        return latest
    }
}


/// Presentation only: retain all stored history and original result prose.
enum AIActivitySummary {
    static func contextOnly(_ record:AIActivityRecord)->Bool {
        guard record.state == .succeeded else {return false}
        let reads:Set<String>=["Checked Calendar","Checked Reminders","Checked item details","Searched email","Read the email","Searched WhatsApp","Checked the weather","Checked project items"]
        return reads.contains(text(record.message))
    }
    static func recent(_ records:[AIActivityRecord],current:AIActivityRecord?,registration:String)->[AIActivityRecord] {
        // Sleep/closed-laptop suspensions and foreground cancellation are
        // interrupted/stopped outcomes, distinct from an actual analysis failure.
        var values=records.filter{$0.registration == registration && ($0.kind != .heartbeat || [.failed,.partial].contains($0.state)) && $0.state.isTerminal && ![.replied,.resolved].contains($0.state) && !contextOnly($0)}
        if let current,current.registration == registration,current.kind != .heartbeat,current.state == .running {
            values.removeAll{$0.id == current.id};values.append(current)
        }
        return Array(values.sorted {
            if ($0.state == .running) != ($1.state == .running) {return $0.state == .running}
            return $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id
        }.prefix(5))
    }
    static func text(_ message:String,hint:String? = nil,compact:Bool = false)->String {
        var text=message.trimmingCharacters(in:.whitespacesAndNewlines)
        for marker in ["**","__","`"] {text=text.replacingOccurrences(of:marker,with:"")}
        if text.lowercased().hasPrefix("completed: ") {text=String(text.dropFirst(11))}
        let labels=[("Created reminder: ","Reminder created"),("Updated reminder: ","Reminder updated"),
                    ("Created event: ","Calendar event created"),("Updated event: ","Calendar event updated"),
                    ("Removed event: ","Calendar event removed"),("Deleted event: ","Calendar event removed"),
                    ("Your feedback was saved","Feedback saved")]
        for (prefix,label) in labels where text.lowercased().hasPrefix(prefix.lowercased()) {
            let remainder=String(text.dropFirst(prefix.count)).trimmingCharacters(in:.whitespacesAndNewlines)
            return compact || remainder.isEmpty ? label : label+": "+remainder
        }
        let natural=["Reminder created","Reminder updated","Reminder removed","Calendar event created","Calendar event updated","Calendar event removed","Space created","Task created","Reply draft copied","Feedback saved"]
        if compact,let label=natural.first(where:{text.hasPrefix($0+": ") || text == $0}) {return label}
        // Older verified Review outcomes used quoted titles in the final reply.
        // A captured typed operation supplies the kind; prose never establishes a save.
        if text.lowercased().hasPrefix("created "),let hint {
            let quoted=text.range(of:"[“\"]([^”\"]+)[”\"]",options:.regularExpression).map{String(text[$0]).dropFirst().dropLast()}
            if let quoted {return compact ? hint+" created" : hint+" created: "+quoted}
        }
        if text.lowercased().hasPrefix("recreated "),let hint,let range=text.range(of:" as ",options:.caseInsensitive) {
            let title=String(text[text.index(text.startIndex,offsetBy:10)..<range.lowerBound])
            return compact ? hint+" created" : hint+" created: "+title
        }
        return text
    }
}

struct AIActivityState: Codable, Equatable {
    var version = 1
    var records: [AIActivityRecord] = []
}

@MainActor @Observable final class AIActivityStore {
    private(set) var state = AIActivityState()
    private(set) var readable = true
    private(set) var error: String?
    var readOnly: Bool { !readable }
    @ObservationIgnored private let persist: (Data) throws -> Void
    private var acknowledgements: [String: AcknowledgementUndo] = [:]
    private struct AcknowledgementUndo {
        var id: String
        var created: Date
    }

    init(load: () throws -> Data? = { nil }, persist: @escaping (Data) throws -> Void = { _ in }) {
        self.persist = persist
        do {
            guard let data = try load() else { return }
            try Self.validateShape(data)
            let saved = try JSONDecoder().decode(AIActivityState.self, from: data)
            try Self.validate(saved)
            state = saved
        } catch {
            readable = false
            self.error = "Saved AI activity could not be read. Its original record is preserved; changes are disabled."
            return
        }
        // Reopening is a display recovery only. It never resumes or repeats a job.
        var recovered = state
        for index in recovered.records.indices where recovered.records[index].state == .running {
            recovered.records[index].state = .interrupted
            recovered.records[index].finished = max(.now, recovered.records[index].created)
            recovered.records[index].progress = nil
        }
        guard recovered != state else { return }
        do { try save(recovered) }
        catch {
            // Show the interruption even if storage cannot record it, retaining original bytes.
            state = recovered; readable = false
            self.error = "AI activity was interrupted, but recovery could not be saved. The original record is preserved; no work was replayed."
        }
    }

    func records(_ registration: String) -> [AIActivityRecord] {
        state.records.filter { $0.registration == registration }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.created != $1.created { return $0.created > $1.created }
            return $0.id < $1.id
        }
    }
    func latest(_ registration: String) -> AIActivityRecord? { records(registration).first }
    func undoDate(_ registration: String) -> Date? { acknowledgements[registration]?.created }
    func undoLabel(_ registration: String) -> String? {
        acknowledgements[registration] == nil ? nil : "Undo AI activity acknowledgement"
    }

    @discardableResult func upsert(_ record: AIActivityRecord) -> Bool {
        guard readable else { return false }
        var candidate = state
        if let index = candidate.records.firstIndex(where: { $0.id == record.id && $0.registration == record.registration }) {
            let old = candidate.records[index]
            guard old.created == record.created, old.kind == record.kind else {
                error = "This AI activity has a different captured identity; its saved record was preserved."
                return false
            }
            var updated = record
            updated.acknowledged = old.acknowledged
            candidate.records[index] = updated
        } else { candidate.records.append(record) }
        return commit(candidate)
    }

    @discardableResult func acknowledge(_ id: String, registration: String) -> Bool {
        guard readable, let index = state.records.firstIndex(where: { $0.id == id && $0.registration == registration }),
              state.records[index].state.isTerminal, !state.records[index].acknowledged else { return false }
        var candidate = state; candidate.records[index].acknowledged = true
        guard commit(candidate) else { return false }
        acknowledgements[registration] = .init(id: id, created: .now)
        return true
    }

    @discardableResult func undoAcknowledgement(_ registration: String) -> Bool {
        guard readable, let undo = acknowledgements[registration],
              let index = state.records.firstIndex(where: { $0.id == undo.id && $0.registration == registration }),
              state.records[index].acknowledged else { return false }
        var candidate = state; candidate.records[index].acknowledged = false
        guard commit(candidate) else { return false }
        acknowledgements.removeValue(forKey: registration)
        return true
    }

    private func commit(_ candidate: AIActivityState) -> Bool {
        guard candidate != state else { return true }
        do { try Self.validate(candidate); try save(candidate); error = nil; return true }
        catch { self.error = "AI activity could not be saved. Its previous history is preserved."; return false }
    }
    private func save(_ candidate: AIActivityState) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try persist(encoder.encode(candidate))
        state = candidate
    }
    private enum StorageFailure: Error { case invalid, unknown }
    private static func validate(_ state: AIActivityState) throws {
        guard state.version == 1 else { throw StorageFailure.unknown }
        var keys = Set<String>()
        for record in state.records {
            let key = record.registration + "\u{0}" + record.id
            guard !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.id.contains("\u{0}"), !record.registration.contains("\u{0}"), keys.insert(key).inserted,
                  !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.created.timeIntervalSince1970.isFinite,
                  record.finished.map({ $0.timeIntervalSince1970.isFinite && $0 >= record.created }) ?? true,
                  record.progress.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  record.destination?.targetID.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true
            else { throw StorageFailure.invalid }
        }
    }
    /// Unknown fields remain untouched instead of being lost through a Codable round-trip.
    private static func validateShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: ["version", "records"]), let records = root["records"] as? [[String: Any]]
        else { throw StorageFailure.unknown }
        let recordKeys: Set<String> = ["id", "registration", "kind", "state", "title", "message", "progress", "created", "finished", "destination", "acknowledged"]
        let destinationKeys: Set<String> = ["assistant", "review", "heartbeat", "project", "calendar", "reminders", "feedback"]
        for record in records {
            guard Set(record.keys).isSubset(of: recordKeys) else { throw StorageFailure.unknown }
            if let destination = record["destination"], !(destination is NSNull) {
                guard let value = destination as? [String: Any], value.count == 1,
                      let name = value.keys.first, destinationKeys.contains(name),
                      let fields = value[name] as? [String: Any], Set(fields.keys).isSubset(of: ["targetID"])
                else { throw StorageFailure.unknown }
            }
        }
    }
}
