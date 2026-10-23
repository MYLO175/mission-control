import Foundation
import SwiftData
@main struct Checks {
    @MainActor static func main() throws {
        let request = NativeCreationRequest(kind:.reminder,registration:"fixture-account",title:"Duplicate title")
        let base = NativeEditDetails(kind:.reminder,itemID:request.id.uuidString,occurrenceID:request.id.uuidString,sourceID:"list-ID",title:request.title,notes:"",writable:true)
        try NativeCreationRules.validate(request:request,baseline:base,edited:base)
        func rejects(_ body: () throws -> Void) { do { try body(); preconditionFailure("Unexpected success") } catch {} }
        var wrong = request; wrong.id = UUID(); rejects { try NativeCreationRules.validate(request:wrong,baseline:base,edited:base) }
        var noTitle = base; noTitle.title = " "; rejects { try NativeCreationRules.validate(request:request,baseline:base,edited:noTitle) }
        var readOnly = base; readOnly.writable = false; rejects { try NativeCreationRules.validate(request:request,baseline:readOnly,edited:base) }
        let instant=ISO8601DateFormatter().date(from:"2027-01-21T16:00:00Z")!
        var dated=request;dated.kind = .event;dated.suggestedStart=instant;dated.suggestedHasTime=true;dated.suggestedTimeZone="Europe/London"
        var event=base;event.kind = .event
        let deadline=NativeCreationRules.applyingSuggestion(dated,to:event)
        precondition(deadline.start == instant && deadline.end == instant.addingTimeInterval(900) && !deadline.allDay,"Supported deadline instant prefilled with visible short marker")
        dated.suggestedStart=ISO8601DateFormatter().date(from:"2027-06-03T23:00:00Z")!;dated.suggestedHasTime=false
        let day=NativeCreationRules.applyingSuggestion(dated,to:event)
        precondition(day.allDay && day.end.timeIntervalSince(day.start) == 86400,"Date-only suggestion is one local all-day reference")
        dated.suggestedEnd=day.start.addingTimeInterval(86400)
        let range=NativeCreationRules.applyingSuggestion(dated,to:event)
        precondition(range.end.timeIntervalSince(range.start) == 172800,"Inclusive source end becomes exclusive editor end")
        let container = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store = NativeCreationStore(container:container)
        precondition(NativeCreationRules.allowed(store.state,key:request.key))
        try store.begin(request); precondition(!NativeCreationRules.allowed(store.state,key:request.key))
        rejects { try store.begin(request) }
        var alternative = request; alternative.kind = .event
        precondition(alternative.key == request.key)
        rejects { try store.begin(alternative) }
        let pending = NativeCreationStore(container:container)
        rejects { try pending.begin(request) }; precondition(pending.receipt(request) == nil)
        let receipt = NativeCreationReceipt(requestID:request.id,registration:request.registration,kind:request.kind,itemID:"exact-new-ID",title:request.title,destination:"To do · Test",created:.now,sourceScope:"fixture")
        var invalid = receipt; invalid.registration = "other-account"; rejects { try store.complete(request,receipt:invalid) }
        try store.complete(request,receipt:receipt)
        rejects { try store.complete(request,receipt:receipt) }
        let completed = NativeCreationStore(container:container)
        precondition(completed.receipt(request) == receipt)
        rejects { try completed.begin(request) }
        var otherAccount = request; otherAccount.registration = "other-account"; try completed.begin(otherAccount)
        let unavailable = NativeCreationStore(container:nil)
        rejects { try unavailable.begin(request) }; precondition(unavailable.state.claims.isEmpty)
        let ownership=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let firstOwner=NativeCreationStore(container:ownership),staleOwner=NativeCreationStore(container:ownership)
        try firstOwner.begin(request)
        let different=NativeCreationRequest(kind:.reminder,registration:"fixture-account",title:"Other request")
        rejects {try staleOwner.begin(different)}
        let retained=NativeCreationStore(container:ownership)
        precondition(retained.state.claims.count == 1 && retained.state.claims[request.key] != nil,"A stale form owner never overwrites a newer pending native claim")
        do {
            let retryStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let original=NativeCreationRequest(kind:.reminder,registration:"fixture-account",title:"Private original form title",notes:"Private form seed notes",evidence:"Private source quotation")
            let claims=NativeCreationStore(container:retryStore)
            try claims.begin(original)
            let started=claims.state.claims[original.key]!.started
            try claims.failedBeforeSave(original,failure:.init(message:"The selected destination changed before save"))
            let known=claims.state.claims[original.key]!
            precondition(known.started == started && known.receipt == nil && known.preSaveFailure != nil && NativeCreationRules.allowed(claims.state,key:original.key),"Known no-save proof retains the original claim and makes the form manually retryable")
            rejects {try claims.complete(original,receipt:.init(requestID:original.id,registration:original.registration,kind:original.kind,itemID:"not-saved",title:original.title,destination:"Fictional",created:.now,sourceScope:"fixture"))}
            let reopened=NativeCreationStore(container:retryStore)
            precondition(NativeCreationRules.retryAllowed(reopened.state.claims[original.key]!,request:original),"The exact durable no-save proof survives reopening")
            var differentKind=original;differentKind.kind = .event
            rejects {try reopened.begin(differentKind)}
            var editedRequest=original;editedRequest.title="Corrected seed title";editedRequest.notes="Corrected seed notes"
            var edited=NativeEditDetails(kind:.reminder,itemID:original.id.uuidString,occurrenceID:original.id.uuidString,sourceID:"new-list",title:"Edited human form title",notes:"Edited human notes",writable:true)
            let baseline=edited;edited.due=instant;edited.hasTime=true
            try NativeCreationRules.validate(request:editedRequest,baseline:baseline,edited:edited)
            try reopened.begin(editedRequest)
            let retried=reopened.state.claims[original.key]!
            precondition(retried.requestFingerprint == known.requestFingerprint && retried.preSaveFailure == nil && retried.preSaveFailureHistory?.count == 1 && retried.preSaveFailureHistory?.first?.contains("destination changed") == true,"Manual retry keeps the canonical form identity, appends failure history and claims a new pending attempt")
            rejects {try reopened.begin(original)}
            try reopened.failedBeforeSave(editedRequest,failure:.init(message:"The corrected destination is temporarily unavailable"))
            try reopened.begin(editedRequest)
            precondition(reopened.state.claims[original.key]?.preSaveFailureHistory?.count == 2,"Multiple positively verified no-save attempts preserve each historical failure")
            let saved=NativeCreationReceipt(requestID:original.id,registration:original.registration,kind:original.kind,itemID:"verified-retry-item",title:edited.title,destination:"Chosen list",created:.now,sourceScope:"fixture")
            try reopened.complete(editedRequest,receipt:saved)
            let completedRetry=NativeCreationStore(container:retryStore)
            precondition(completedRetry.receipt(original) == saved && completedRetry.state.claims[original.key]?.preSaveFailureHistory?.count == 2,"Verified retry readback persists without losing previous failed attempts")
            rejects {try completedRetry.begin(original)}
            rejects {try completedRetry.failedBeforeSave(original,failure:.init(message:"Cannot reclassify a completed save"))}
            let bytes=try LocalRecordRepository.read("nativeCreationClaims",container:retryStore)!
            let encoded=String(decoding:bytes,as:UTF8.self)
            precondition(!encoded.contains(original.notes) && !encoded.contains(original.evidence!),"The form identity is opaque rather than another persisted source/seed-content copy")
        }
        do {
            let failedProofStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            var fail=false
            let repository=LocalRecordRepository(container:failedProofStore,beforeCommit:{_ in if fail {throw CocoaError(.fileWriteUnknown)}})
            let claims=NativeCreationStore(container:failedProofStore,repository:repository)
            try claims.begin(request)
            let pending=claims.state
            fail=true
            rejects {try claims.failedBeforeSave(request,failure:.init(message:"Positively no native save"))}
            precondition(claims.state.claims == pending.claims && !NativeCreationRules.allowed(claims.state,key:request.key),"Failure to persist no-save proof rolls back in-memory eligibility and retains uncertainty")
            let reopened=NativeCreationStore(container:failedProofStore)
            precondition(reopened.state.claims[request.key]?.preSaveFailure == nil,"An unsuccessful proof save cannot appear as durable recovery after reopening")
            rejects {try reopened.begin(request)}
        }
        do {
            let staleProofStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let first=NativeCreationStore(container:staleProofStore)
            try first.begin(request)
            let stale=NativeCreationStore(container:staleProofStore)
            try first.failedBeforeSave(request,failure:.init(message:"Known no-save"))
            rejects {try stale.failedBeforeSave(request,failure:.init(message:"Stale owner proof"))}
            precondition(stale.state.claims[request.key]?.preSaveFailure == nil,"A failed proof CAS does not publish stale recovery state")
            let retryOwner=NativeCreationStore(container:staleProofStore),staleRetry=NativeCreationStore(container:staleProofStore)
            try retryOwner.begin(request)
            rejects {try staleRetry.begin(request)}
            let durable=NativeCreationStore(container:staleProofStore)
            precondition(durable.state.claims[request.key]?.preSaveFailure == nil && durable.state.claims[request.key]?.preSaveFailureHistory?.count == 1,"A stale retry never overwrites a newly pending attempt or its failure history")
        }
        do {
            let opaqueStore=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let first=NativeCreationStore(container:opaqueStore)
            try first.begin(request)
            var envelope=try JSONSerialization.jsonObject(with:JSONEncoder().encode(first.state)) as! [String:Any]
            envelope["futureEnvelope"]=["keep":"exact"]
            var rows=envelope["claims"] as! [String:[String:Any]]
            rows[request.key]?["futureClaim"]=["identity":"retained"]
            envelope["claims"]=rows
            try LocalRecordRepository(container:opaqueStore).write(["nativeCreationClaims":JSONSerialization.data(withJSONObject:envelope,options:[.sortedKeys])])
            let preserved=NativeCreationStore(container:opaqueStore)
            try preserved.failedBeforeSave(request,failure:.init(message:"Known no-save with future metadata"))
            try preserved.begin(request)
            let after=try JSONSerialization.jsonObject(with:LocalRecordRepository.read("nativeCreationClaims",container:opaqueStore)!) as! [String:Any]
            let afterClaims=after["claims"] as! [String:[String:Any]]
            precondition((after["futureEnvelope"] as? [String:String])?["keep"] == "exact" && (afterClaims[request.key]?["futureClaim"] as? [String:String])?["identity"] == "retained","No-save proof and manual retry preserve additive opaque envelope/claim metadata")
        }
        let record = try container.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first!
        let preserved = Data("{\"version\":99,\"claims\":{}}".utf8); record.data = preserved; try container.mainContext.save()
        let unsupported = NativeCreationStore(container:container)
        precondition(!unsupported.readable); rejects { try unsupported.begin(request) }; precondition(record.data == preserved)
        print("PASS creation identity/form edits, durable known-no-save/manual retry/history, proof-save rollback, stale-proof/retry CAS, opaque metadata, pending/completed refusal across reload, registration isolation and unavailable/unknown storage preservation")
    }
}
