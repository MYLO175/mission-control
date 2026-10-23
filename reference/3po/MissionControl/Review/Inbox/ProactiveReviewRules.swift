import Foundation

enum ProactiveReviewRules {
    /// Local presentation only. A category label or informational explanation is
    /// insufficient to offer an action; retain the saved concern and history.
    static func hasSuggestedAction(_ record:PADiscovery)->Bool {
        guard UUID(uuidString:record.id) != nil else {return false}
        if let removal=record.proposedRemoval {return removal.target.kind == "event" && removal.target.writable && removal.target.start != nil && removal.target.end != nil && removal.scope == "occurrence"}
        if let change=record.proposedChange {return change.target.writable && DiscoveryProposedDate(start:change.newDate,hasTime:change.hasTime,timeZoneID:change.timeZoneID).valid}
        switch record.kind {
        case "calendar":return !record.needsDateClarification && record.proposedDate?.valid == true
        case "reminder":return !record.needsDateClarification && (record.proposedDate == nil || record.proposedDate?.valid == true)
        case "project":return true
        case "projectTask":return record.proposedProjectTask != nil
        case "reply":return record.replyDraft.map{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty} == true
        default:return false
        }
    }

    static func reference(_ request: String, turns: [AssistantTurn], records: [PADiscovery]) -> PADiscovery? {
        let value = request.trimmingCharacters(in:.whitespacesAndNewlines)
        guard value.count <= 200, let last = turns.last(where:{ $0.role == "assistant" }), last.completed, let delivery = last.deliveryID,
              delivery.hasPrefix("discovery:"), let record = records.first(where:{ $0.deliveryID == delivery && !$0.dismissed && $0.supersededBy == nil && $0.retiredAt == nil && $0.message == last.content && ["calendar","reminder"].contains($0.kind) }) else { return nil }
        let affirmations = #"^(?:yes(?:[, ]+(?:please|do that|go ahead))?|please do|go ahead)[.!]?$"#
        let additions = #"^(?:yes[, ]+)?(?:please |pls )?(?:add|put|schedule|create) (?:(?:that|this|it)(?: (?:as|to|in|on) (?:a |an |my |the )?(?:calendar|event|reminder|reminders))?|(?:a |an )?(?:event|reminder) (?:for|from) (?:that|this))(?: please| pls)?[.!]?$"#
        guard value.range(of:affirmations,options:[.regularExpression,.caseInsensitive]) != nil || value.range(of:additions,options:[.regularExpression,.caseInsensitive]) != nil else { return nil }
        if value.range(of:#"\b(?:reminder|reminders)\b"#,options:[.regularExpression,.caseInsensitive]) != nil, record.kind != "reminder" { return nil }
        if value.range(of:#"\b(?:calendar|event)\b"#,options:[.regularExpression,.caseInsensitive]) != nil, record.kind != "calendar" { return nil }
        return record
    }
}
