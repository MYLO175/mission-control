import Foundation
import Observation
import SwiftData

@MainActor @Observable final class NativeCreationStore {
    private(set) var state = NativeCreationState()
    private(set) var readable = true
    private let repository:LocalRecordRepository?
    private var loadedBytes:Data?
    init(container: ModelContainer?,repository:LocalRecordRepository? = nil) {
        self.repository=repository ?? container.map{LocalRecordRepository(container:$0)}
        do {
            if let record = try self.repository?.read("nativeCreationClaims") { state = try JSONDecoder().decode(NativeCreationState.self,from: record); guard state.version == 1 else { throw IntegrationError.verification };loadedBytes=record }
        } catch { readable = false }
    }
    func receipt(_ request: NativeCreationRequest) -> NativeCreationReceipt? { state.claims[request.key]?.receipt }
    func begin(_ request: NativeCreationRequest) throws {
        guard readable else { throw ActionFailure.message("Saved creation receipts are unavailable; no Apple item created.") }
        guard NativeCreationRules.allowed(state,key:request.key),state.claims[request.key].map({NativeCreationRules.retryAllowed($0,request:request)}) ?? true else {
            throw ActionFailure.message(receipt(request) == nil ? "This save's outcome needs checking in Apple Calendar or Reminders before another attempt. It will not be repeated automatically." : "This item was already created; no duplicate added.")
        }
        let previous=state,prior=state.claims[request.key]
        var claim=NativeCreationClaim(started:.now,requestFingerprint:NativeCreationRules.fingerprint(request))
        claim.preSaveFailureHistory=prior?.preSaveFailureHistory
        if let prior,let failure=prior.preSaveFailure {claim.preSaveFailureHistory=(prior.preSaveFailureHistory ?? [])+[prior.started.ISO8601Format()+" "+failure]}
        state.claims[request.key]=claim
        do { try save() } catch { state = previous; throw ActionFailure.message("Could not save the creation checkpoint; no Apple item created.") }
    }
    func failedBeforeSave(_ request:NativeCreationRequest,failure:NativePreSaveFailure)throws {
        guard readable,var claim=state.claims[request.key],claim.receipt == nil,claim.preSaveFailure == nil,claim.requestFingerprint == NativeCreationRules.fingerprint(request) else {throw IntegrationError.verification}
        let previous=state;claim.preSaveFailure=String(failure.message.prefix(1000));state.claims[request.key]=claim
        do {try save()} catch {state=previous;throw error}
    }
    func complete(_ request: NativeCreationRequest, receipt: NativeCreationReceipt) throws {
        guard let claim=state.claims[request.key],claim.receipt == nil,claim.preSaveFailure == nil,claim.requestFingerprint.map({$0 == NativeCreationRules.fingerprint(request)}) ?? true,receipt.requestID == request.id, receipt.registration == request.registration, receipt.kind == request.kind else { throw IntegrationError.verification }
        let previous = state; state.claims[request.key]?.receipt = receipt
        do { try save() } catch { state = previous; throw ActionFailure.message("Apple saved the item, but its local receipt could not be saved. Check Apple Calendar or Reminders; do not create it again.") }
    }
    private func save() throws {
        guard readable,let repository else { throw IntegrationError.verification }
        let bytes=try LocalRecordCoding.preservingUnknown(state,original:loadedBytes)
        try repository.write(["nativeCreationClaims":bytes],expected:["nativeCreationClaims":LocalRecordVersion(loadedBytes)])
        loadedBytes=bytes
    }
}
