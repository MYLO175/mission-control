import Foundation

struct NativeCreationRequest: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: NativeItemKind
    var registration: String
    var preferredDate: Date?
    var title = ""
    var notes = ""
    var discoveryID: String?
    /// Exact displayed proposal captured when the form opened; no live source dependency.
    var discoveryApproval: Data? = nil
    var evidence: String?
    var requiresDateSelection = false
    var suggestedStart: Date? = nil
    var suggestedEnd: Date? = nil
    var suggestedHasTime: Bool? = nil
    var suggestedTimeZone: String? = nil
    var key: String { registration + ":" + id.uuidString }
}
struct NativeCreationReceipt: Codable, Equatable {
    var requestID: UUID
    var registration: String
    var kind: NativeItemKind
    var itemID: String
    var title: String
    var destination: String
    var created: Date
    var sourceScope: String
    var deliveryID: String { "native-create:" + registration + ":" + requestID.uuidString }
}
struct NativeCreationClaim: Codable, Equatable {
    var started: Date
    var receipt: NativeCreationReceipt?
    /// Opaque form identity only. Editable fields still use NativeCreationRules.
    var requestFingerprint:String? = nil
    var preSaveFailure:String? = nil
    var preSaveFailureHistory:[String]? = nil
}
struct NativeCreationState: Codable {
    var version = 1
    var claims: [String:NativeCreationClaim] = [:]
}
enum NativeCreationRules {
    static func applyingSuggestion(_ request:NativeCreationRequest,to baseline:NativeEditDetails)->NativeEditDetails {
        guard let start=request.suggestedStart,let timed=request.suggestedHasTime else {return baseline}
        var proposed=baseline;proposed.timeZoneID=request.suggestedTimeZone ?? baseline.timeZoneID
        if proposed.kind == .event {
            proposed.allDay = !timed;proposed.start=start
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:proposed.timeZoneID) ?? .current
            proposed.end=request.suggestedEnd ?? (timed ? start.addingTimeInterval(900) : start)
            if !timed {proposed.end=calendar.date(byAdding:.day,value:1,to:proposed.end)!}
            if proposed.end <= start {proposed.end=start.addingTimeInterval(900)}
        } else {proposed.due=start;proposed.hasTime=timed}
        return proposed
    }
    static func validate(request: NativeCreationRequest, baseline: NativeEditDetails, edited: NativeEditDetails) throws {
        guard baseline.kind == request.kind, baseline.itemID == request.id.uuidString else { throw IntegrationError.missing }
        try NativeEditRules.validate(edited,baseline:baseline)
    }
    static func fingerprint(_ request:NativeCreationRequest)->String {
        ActionRules.key(registration:request.registration,request:request.id.uuidString,selectedTarget:request.kind.rawValue)
    }
    static func retryAllowed(_ claim:NativeCreationClaim,request:NativeCreationRequest)->Bool {
        claim.receipt == nil && claim.preSaveFailure != nil && claim.requestFingerprint == fingerprint(request)
    }
    static func allowed(_ state: NativeCreationState, key: String) -> Bool {
        guard let claim=state.claims[key] else {return true}
        return claim.receipt == nil && claim.preSaveFailure != nil && claim.requestFingerprint != nil
    }
}
