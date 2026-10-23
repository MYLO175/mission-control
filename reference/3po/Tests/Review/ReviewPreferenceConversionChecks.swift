import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        func check(_ value: Bool, line: UInt = #line) { precondition(value, "Conversion check failed at line \(line)") }
        let settings = UserDefaults(suiteName: "fictional-conversion-\(UUID())")!
        let now = Date(timeIntervalSince1970: 1_900_000_000.123456)
        func fixture() throws -> (ModelContainer, LocalRecordRepository) {
            let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            return (container, LocalRecordRepository(container: container))
        }
        func legacy(_ account: String, _ topic: String, _ direction: String, inactive: Bool = false) -> ReviewPreferenceConversion.Legacy {
            .init(id: UUID(), registration: account, topic: topic, direction: direction, revision: UUID(), inactive: inactive)
        }
        func object(_ data: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        let a = legacy("account-a", "Orion project updates", "more")
        let b = legacy("account-b", "Routine newsletters", "less", inactive: true)
        let values = [a,b], original = try JSONEncoder().encode(values)
        let (container, repository) = try fixture()
        let existing = PAMemory(registration: "account-a", text: "Existing human fact", kind: .context, provenance: "Human", created: now, reviewed: now)
        var envelope = try object(JSONEncoder().encode(MemoryEnvelope(records: [existing])))
        envelope["futureEnvelope"] = ["opaque": "retained"]
        var rows = envelope["records"] as! [[String: Any]]
        rows[0]["futureFact"] = ["key": "untouched"]
        envelope["records"] = rows
        try repository.write(["paMemory": JSONSerialization.data(withJSONObject: envelope), ReviewPreferenceConversion.legacyKey: original])
        let proof = try ReviewPreferenceConversion.run(repository: repository, now: now)!
        check(proof.original == original && proof.items.count == 2)
        try check(repository.read(ReviewPreferenceConversion.legacyKey) == nil)
        let stored = try repository.read("paMemory")!
        let decoded = try MemoryEnvelope.decode(stored)
        check(decoded.records.count == 3 && decoded.records.first == existing)
        let convertedA = decoded.records.first { $0.id == a.id }!
        let convertedB = decoded.records.first { $0.id == b.id }!
        check(convertedA.registration == a.registration && convertedA.created == now && convertedA.reviewed == now && convertedA.retiredAt == nil && convertedA.source == nil && convertedA.reviewPreference == true)
        check(convertedA.text.contains("Prioritise") && convertedA.reviewContext == a.topic && convertedA.evidence == a.topic)
        check(convertedB.registration == b.registration && convertedB.retiredAt == now && convertedB.text.contains("less attention"))
        check(proof.items.first { $0.memory.id == a.id }?.legacyRevision == a.revision)
        var savedObject = try object(stored)
        check((savedObject["futureEnvelope"] as! [String: String])["opaque"] == "retained")
        check(((savedObject["records"] as! [[String: Any]])[0]["futureFact"] as! [String: String])["key"] == "untouched")
        let reopened = PAMemoryStore(container: container, settings: settings)
        check(reopened.reviewPreferenceMigrationReadable && reopened.reviewPreferences("account-a").map(\.id) == [a.id])
        check(reopened.reviewPreferences("account-b").isEmpty && reopened.reviewPreferences("account-b",includeRetired:true).map(\.id) == [b.id])
        check(reopened.matchesConvertedReviewPreference(id: a.id.uuidString, revision: a.revision.uuidString, registration: "account-a", direction: "more"))
        check(!reopened.matchesConvertedReviewPreference(id: a.id.uuidString, revision: a.revision.uuidString, registration: "account-b", direction: "more"))
        reopened.enabled=false
        check(!reopened.matchesConvertedReviewPreference(id:a.id.uuidString,revision:a.revision.uuidString,registration:"account-a",direction:"more"))
        reopened.enabled=true
        check(reopened.matchesConvertedReviewPreference(id:a.id.uuidString,revision:a.revision.uuidString,registration:"account-a",direction:"more"))
        let classified=LifeMemoryOrganisation(areas:[.projects],connections:[])
        check(reopened.setOrganisation(a.id,value:classified))
        check(reopened.matchesConvertedReviewPreference(id:a.id.uuidString,revision:a.revision.uuidString,registration:"account-a",direction:"more"))
        let secondProof = try ReviewPreferenceConversion.run(repository: repository, now: now.addingTimeInterval(100))!
        check(secondProof.migratedAt == now)
        check(reopened.records.first{$0.id == a.id}?.organisation?.areas == [.projects])
        check(reopened.forget(a.id))
        check(!reopened.matchesConvertedReviewPreference(id: a.id.uuidString, revision: a.revision.uuidString, registration: "account-a", direction: "more"))
        let forgottenBytes = try repository.read("paMemory")!
        try repository.write([ReviewPreferenceConversion.legacyKey: original])
        _ = try ReviewPreferenceConversion.run(repository: repository)
        try check((repository.read("paMemory")) == forgottenBytes && (repository.read(ReviewPreferenceConversion.legacyKey)) == nil)
        check(PAMemoryStore(container: container,settings: settings).records.allSatisfy { $0.id != a.id })
        // Edited canonical facts keep opaque metadata; another loaded owner must not overwrite.
        let owner = PAMemoryStore(container: container,settings: settings), stale = PAMemoryStore(container: container,settings: settings)
        check(owner.accept(existing.id))
        check(!stale.resolve(existing.id))
        try check(MemoryEnvelope.decode(repository.read("paMemory")!).records.first { $0.id == existing.id }?.resolved == nil)
        savedObject = try object(repository.read("paMemory")!)
        check(savedObject["futureEnvelope"] != nil && (savedObject["records"] as! [[String: Any]]).first { ($0["id"] as? String) == existing.id.uuidString }?["futureFact"] != nil)
        // Any failed save rolls all three related changes back.
        let (rollbackContainer, rollbackRepo) = try fixture()
        try rollbackRepo.write([ReviewPreferenceConversion.legacyKey: original])
        let failing = LocalRecordRepository(container: rollbackContainer,beforeCommit: { _ in throw CocoaError(.fileWriteUnknown) })
        do { _ = try ReviewPreferenceConversion.run(repository: failing); preconditionFailure("Expected rollback") } catch {}
        try check((rollbackRepo.read(ReviewPreferenceConversion.legacyKey)) == original && (rollbackRepo.read("paMemory")) == nil && (rollbackRepo.read(ReviewPreferenceConversion.receiptKey)) == nil)
        _ = try ReviewPreferenceConversion.run(repository: rollbackRepo)
        try check(MemoryEnvelope.decode(rollbackRepo.read("paMemory")!).records.count == 2)
        // Existing ID collision is never treated as a duplicate or merged by title.
        let (collisionContainer, collisionRepo) = try fixture()
        var collision = existing; collision.id = a.id
        let collisionBytes = try JSONEncoder().encode(MemoryEnvelope(records: [collision]))
        try collisionRepo.write(["paMemory": collisionBytes, ReviewPreferenceConversion.legacyKey: original])
        let blocked = PAMemoryStore(container: collisionContainer, settings: settings)
        check(!blocked.reviewPreferenceMigrationReadable && !blocked.canSaveReviewPreference)
        try check((collisionRepo.read("paMemory")) == collisionBytes && (collisionRepo.read(ReviewPreferenceConversion.legacyKey)) == original && (collisionRepo.read(ReviewPreferenceConversion.receiptKey)) == nil)
        // Unknown legacy semantics refuse conversion without deleting anything.
        let (_, unknownRepo) = try fixture()
        var unknownRows = try JSONSerialization.jsonObject(with: original) as! [[String: Any]]
        unknownRows[0]["futureScope"] = ["possiblyChangesMeaning": true]
        let unknown = try JSONSerialization.data(withJSONObject: unknownRows)
        try unknownRepo.write([ReviewPreferenceConversion.legacyKey: unknown])
        do { _ = try ReviewPreferenceConversion.run(repository: unknownRepo); preconditionFailure("Expected unknown refusal") } catch {}
        try check((unknownRepo.read(ReviewPreferenceConversion.legacyKey)) == unknown && (unknownRepo.read("paMemory")) == nil)
        // A genuinely different restored legacy batch cannot overwrite its first conversion proof.
        try repository.write([ReviewPreferenceConversion.legacyKey: JSONEncoder().encode([a])])
        let beforeMismatch = try repository.read("paMemory")!
        do { _ = try ReviewPreferenceConversion.run(repository: repository); preconditionFailure("Expected replay mismatch") } catch {}
        try check((repository.read("paMemory")) == beforeMismatch && (repository.read(ReviewPreferenceConversion.legacyKey)) != nil)
        // A loaded pre-conversion owner cannot overwrite newly converted knowledge.
        let (staleContainer, staleRepo) = try fixture()
        let beforeConversion = PAMemoryStore(container: staleContainer, settings: settings)
        try staleRepo.write([ReviewPreferenceConversion.legacyKey: original])
        _ = try ReviewPreferenceConversion.run(repository: staleRepo, now: now)
        let beforeStaleSave = try staleRepo.read("paMemory")!
        check(!beforeConversion.put(existing))
        try check(staleRepo.read("paMemory") == beforeStaleSave)
        // Bare legacy memory arrays retain future per-record fields when wrapped.
        let (_, arrayRepo) = try fixture()
        try arrayRepo.write(["paMemory": JSONSerialization.data(withJSONObject: rows), ReviewPreferenceConversion.legacyKey: original])
        _ = try ReviewPreferenceConversion.run(repository: arrayRepo, now: now)
        try check((object(arrayRepo.read("paMemory")!)["records"] as! [[String: Any]])[0]["futureFact"] != nil)
        let (_, numericRepo) = try fixture()
        let arrayBytes = try JSONEncoder().encode([existing])
        let numericText = String(decoding: arrayBytes, as: UTF8.self).replacingOccurrences(of: "[{", with: "[{\"futureNumber\":1e127,")
        let numericBytes = Data(numericText.utf8)
        try numericRepo.write(["paMemory": numericBytes, ReviewPreferenceConversion.legacyKey: original])
        do { _ = try ReviewPreferenceConversion.run(repository: numericRepo); preconditionFailure("Expected opaque numeric refusal") } catch {}
        try check(numericRepo.read("paMemory") == numericBytes && numericRepo.read(ReviewPreferenceConversion.legacyKey) == original)
        print("Review preference conversion checks passed: exact batch/account/IDs/dates, inactive retirement, proof/reopen, no resurrection, rollback, collisions, unknown refusal, stale-owner CAS and opaque canonical metadata.")
    }
}
