import Foundation

/// Read-only explanations of the existing recall gates. Does not create a parallel memory store.
enum MemoryAvailability: String, CaseIterable, Identifiable {
    case available, earlierVersion, retired, resolved, reviewNeeded, sourceUnavailable, otherScope, invalidInterpretation
    var id:String { rawValue }
    var title:String { switch self {
    case .available: "Available to PA"
    case .earlierVersion: "Earlier version"
    case .retired: "Retired from recall"
    case .resolved: "Resolved or archived"
    case .reviewNeeded: "Needs review"
    case .sourceUnavailable: "Source evidence unavailable"
    case .otherScope: "Outside this thread"
    case .invalidInterpretation: "Interpretation needs correction"
    } }
    var explanation:String { switch self {
    case .available: "Can be selected when relevant; selection is bounded."
    case .earlierVersion: "Kept as history; a newer belief replaced it."
    case .retired: "Set aside by you. Evidence stays saved; restore it to use it again. Projects are unchanged."
    case .resolved: "Kept for inspection; excluded from current recall. Apple reminders are separate."
    case .reviewNeeded: "Provisional context has gone 90 days without review; confirm or correct it when useful."
    case .sourceUnavailable: "One or more quoted versions are changed, forgotten, missing from cache or outside current source access."
    case .otherScope: "This legacy thread cannot read other topic memories. Focus conversations can use this account's earlier topic memories."
    case .invalidInterpretation: "Saved feedback context is inconsistent. The record is preserved but excluded from recall; edit or clear its interpretation."
    } }
}
struct MemoryInspectionRow:Identifiable {
    var record:PAMemory
    var availability:MemoryAvailability
    var id:UUID { record.id }
}
enum MemoryInspection {
    static func rows(_ records:[PAMemory],permitted:Set<UUID>,registration:String,topic:UUID? = nil,includeTopics:Bool = true,now:Date = .now)->[MemoryInspectionRow] {
        records.filter{$0.registration == registration}.map { record in
            let status:MemoryAvailability
            if record.supersededBy != nil { status = .earlierVersion }
            else if record.sourceInvalidation != nil || !permitted.contains(record.id) { status = .sourceUnavailable }
            else if record.retiredAt != nil { status = .retired }
            else if record.resolved != nil { status = .resolved }
            else if let interpretation=record.reviewInterpretation,(!interpretation.valid || interpretation.rule != record.text || record.reviewPreference != true || record.kind != .preference) {status = .invalidInterpretation}
            else if MemoryRules.needsReview(record,now:now) { status = .reviewNeeded }
            else if !MemoryRules.inScope(record,conversationID:topic,includeTopics:includeTopics) { status = .otherScope }
            else { status = .available }
            return .init(record:record,availability:status)
        }.sorted{$0.record.reviewed == $1.record.reviewed ? $0.id.uuidString < $1.id.uuidString : $0.record.reviewed > $1.record.reviewed}
    }
}
