import Foundation
import SwiftData

@main struct ConversationRepositoryChecks {
    @MainActor static func main() throws {
        enum Injected: Error { case failed }
        var checks = 0
        func check(_ value: Bool, _ label: String) { checks += 1; precondition(value, label) }
        func rejects(_ label: String, _ action: () throws -> Void) {
            checks += 1
            do { try action(); preconditionFailure(label) } catch { }
        }
        func uuid(_ index: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))! }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        func conversation(_ index: Int, turns: Int, account: String = "fictional") -> AssistantConversation {
            AssistantConversation(id: uuid(index), accountID: account, title: "Fictional history \(index)", created: date, turns: (0..<turns).map { number in
                .init(id: uuid(index * 100_000 + number), role: number % 2 == 0 ? "user" : "assistant", content: "Fictional turn \(number)", completed: true, created: date, contextID: uuid(90), choices: ["Continue"], profileSessionID: uuid(91), profileControl: false, memoryNotes: ["Fictional note"], toolErrors: ["Old error"], unresolvedToolErrors: [], sourceMemoryIDs: [uuid(92)], focusAreas: [.projects], images: [.init(id: uuid(index * 100_000 + number + 40_000), registration: account, mimeType: "image/png", width: 100, height: 100, byteCount: 1_000, digest: "fictional-image"), .init(id: uuid(index * 100_000 + number + 50_000), registration: account, mimeType: "image/jpeg", width: 50, height: 50, byteCount: 500, digest: "fictional-second")], contextCapture: .init(id: uuid(index * 100_000 + number + 60_000), captured: date, model: "fictional", focusAreas: [.projects], memoryIDs: [uuid(92)], eligibleMemoryCount: 1, notebookMemoryIDs: [uuid(92)], workspaceIDs: ["life:fictional"], historyTurnIDs: [], excerptedHistoryIDs: [], sourceSnapshotIncluded: false, sourceSnapshotBytes: 0, profileSetup: false, consultedMemoryIDs: [uuid(92)], attemptedTools: ["pa.read_memory"], preparationNotes: ["Old preparation note"]))
            }, isPrimary: index == 1, focus: "Fictional topic", isTopic: index != 1, notebookAreas: [.projects])
        }
        let directory = URL(fileURLWithPath: "/tmp/3po-conversation-repository-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var stores = 0
        func open(_ url: URL) throws -> ModelContainer { try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)) }
        func fresh() throws -> (ModelContainer, URL) { stores += 1; let url = directory.appendingPathComponent("fictional-\(stores).store"); return (try open(url), url) }
        func object(_ data: Data?) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data!) as! [String: Any] }
        func rows(_ data: Data?) throws -> [[String: Any]] { try JSONSerialization.jsonObject(with: data!) as! [[String: Any]] }
        func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }

        var original = [conversation(1, turns: 130), conversation(2, turns: 2, account: "other-fictional-account")]
        original[0].turns[0].contextCapture?.directMemoryIDs = []
        original[0].turns[0].contextCapture?.pageSupportingMemoryIDs = [uuid(92)]
        original[0].turns[0].contextCapture?.lookups = [.init(id:uuid(910_001),tool:"read_memory",query:"First fictional search"),.init(id:uuid(910_002),tool:"read_context_page",query:"Second fictional search")]
        var legacyRows = try rows(JSONEncoder().encode(original))
        legacyRows[0]["futureConversation"] = ["nested": ["kept": true]]
        legacyRows[0]["futureMixed"] = [NSNull(), "retained", ["number": 123456789012345]]
        var turnRows = legacyRows[0]["turns"] as! [[String: Any]]
        turnRows[0]["futureTurn"] = ["flag": "preserved"]
        var capture = turnRows[0]["contextCapture"] as! [String: Any]; capture["futureCapture"] = ["extra": 7]
        var lookupRows=capture["lookups"] as! [[String:Any]];lookupRows[0]["futureLookup"]=["retained":true];capture["lookups"]=lookupRows
        turnRows[0]["contextCapture"] = capture
        var images = turnRows[0]["images"] as! [[String: Any]]; images[0]["futureImage"] = ["nested": ["kept": "yes"]]; turnRows[0]["images"] = images
        legacyRows[0]["turns"] = turnRows
        let legacy = try data(legacyRows)
        let (container, url) = try fresh(), records = LocalRecordRepository(container: container)
        try records.write([ConversationRepository.legacyKey: legacy, "unrelated-owner": Data([1, 2, 3])])
        var storage = ConversationRepository(container: container)
        check(try storage.load() == original, "Legacy known fields load without mutation")
        check(try records.read(ConversationRepository.indexKey) == nil, "Loading does not migrate")
        let failedMigration = ConversationRepository(container: container, repository: LocalRecordRepository(container: container) { _ in throw Injected.failed })
        rejects("Interrupted first migration must throw") { try failedMigration.save(original) }
        check(try records.read(ConversationRepository.indexKey) == nil && records.read(ConversationRepository.metadataKey(original[0].id)) == nil && records.read(ConversationRepository.chunkKey(original[0].id, 0)) == nil, "Interrupted migration leaves no partial index, metadata or chunks")
        check(try records.read(ConversationRepository.legacyKey) == legacy, "Interrupted migration preserves the legacy recovery original")
        try storage.save(original)
        check(storage.lastSave.encodedTurns == 132 && storage.lastSave.writtenRecords == 7, "First migration writes metadata, fixed chunks and index atomically")
        check(try records.read(ConversationRepository.legacyKey) == legacy, "Legacy bytes remain identical after migration")
        check(try ConversationRepository(container: try open(url)).load() == original, "Reopening recovers exact conversation/account/scope/optional fields")
        check(try object(records.read(ConversationRepository.metadataKey(original[0].id)))["futureConversation"] != nil, "Unknown conversation metadata survives migration")
        check(try rows(records.read(ConversationRepository.chunkKey(original[0].id, 0)))[0]["futureTurn"] != nil, "Unknown turn metadata survives migration")
        storage = ConversationRepository(container: try open(url))
        check(try storage.load() == original, "A reopened writer keeps raw migrated extras for subsequent edits")
        let otherMetadata = try records.read(ConversationRepository.metadataKey(original[1].id)), otherChunk = try records.read(ConversationRepository.chunkKey(original[1].id, 0))
        var edited = original
        edited[0].turns[5].content = "An explicit edit to an older fictional turn"
        try storage.save(edited)
        check(storage.lastSave.encodedTurns == 64 && storage.lastSave.writtenRecords == 2, "Older edit encodes one affected chunk plus index")
        edited[0].turns.append(.init(id: uuid(800_000), role: "user", content: "Fictional append", completed: true, created: date))
        try storage.save(edited)
        check(storage.lastSave.encodedTurns == 3 && storage.lastSave.writtenRecords == 2, "Append encodes only the short final chunk plus index")
        check(try records.read(ConversationRepository.metadataKey(original[1].id)) == otherMetadata && records.read(ConversationRepository.chunkKey(original[1].id, 0)) == otherChunk, "Another account's unchanged records remain byte-identical")
        check(try ConversationRepository(container: try open(url)).load() == edited, "Append and older edit survive reopening")
        edited[0].focus = nil; edited[0].turns[0].choices = nil
        edited[0].turns[0].contextCapture?.preparationNotes = nil
        edited[0].turns[0].contextCapture?.directMemoryIDs = nil
        edited[0].turns[0].contextCapture?.lookups?[0].query = nil
        edited[0].turns[0].contextCapture?.lookups?.reverse()
        edited[0].turns[0].images?.reverse()
        try storage.save(edited)
        let metadata = try object(records.read(ConversationRepository.metadataKey(original[0].id)))
        let row = try rows(records.read(ConversationRepository.chunkKey(original[0].id, 0)))[0]
        let changedCapture = row["contextCapture"] as! [String: Any], changedImages = row["images"] as! [[String: Any]]
        check(metadata["focus"] == nil && row["choices"] == nil && changedCapture["preparationNotes"] == nil, "Known optional fields intentionally cleared stay removed")
        check(changedCapture["directMemoryIDs"] == nil && changedCapture["pageSupportingMemoryIDs"] as? [String] == [uuid(92).uuidString], "Direct-input and backing-evidence fields remain distinct through reopen and optional clearing")
        check(metadata["futureConversation"] != nil && row["futureTurn"] != nil && changedCapture["futureCapture"] != nil, "Unknown fields survive edits at each object level")
        check((metadata["futureMixed"] as? [Any])?.count == 3, "Unknown null, array and numeric values survive edits")
        check(changedImages[0]["futureImage"] == nil && changedImages[1]["futureImage"] != nil, "Nested image extras follow exact image identity through reordering")
        let changedLookups=changedCapture["lookups"] as! [[String:Any]]
        check(changedLookups[0]["futureLookup"] == nil && changedLookups[1]["futureLookup"] != nil && changedLookups[1]["query"] == nil,"Lookup extras follow exact identity through reordering while cleared known query text stays removed")
        edited[0].turns[0].contextCapture?.id = uuid(950_000)
        try storage.save(edited)
        check(try (rows(records.read(ConversationRepository.chunkKey(original[0].id, 0)))[0]["contextCapture"] as! [String: Any])["futureCapture"] == nil, "Unknown capture extras never transfer to a different capture identity")
        edited[0].turns[0].images = nil; edited[0].turns[0].contextCapture = nil
        try storage.save(edited)
        let cleared = try rows(records.read(ConversationRepository.chunkKey(original[0].id, 0)))[0]
        check(cleared["images"] == nil && cleared["contextCapture"] == nil && cleared["futureTurn"] != nil, "Clearing known nested objects cannot resurrect their old fields")
        try storage.save(edited)
        check(storage.lastSave == ConversationSaveStatistics(), "An unchanged save encodes and writes nothing")
        let orphan = ConversationRepository.chunkKey(original[0].id, 99)
        try records.write([orphan: Data("opaque future chunk".utf8)])
        edited[0].turns = Array(edited[0].turns.prefix(10))
        try storage.save(edited)
        check(storage.lastSave.encodedTurns == 10 && storage.lastSave.removedRecords == 2, "Explicit shrink rewrites the partial chunk and removes only indexed surplus chunks")
        check(try records.read(orphan) == Data("opaque future chunk".utf8), "Unknown unindexed records are never deleted")
        check(try ConversationRepository(container: try open(url)).load() == edited, "Shrinking an existing full chunk remains readable")
        let reordered = Array(edited.reversed())
        try storage.save(reordered)
        check(storage.lastSave.encodedTurns == 0 && storage.lastSave.writtenRecords == 1, "Conversation ordering changes only the index")
        check(try ConversationRepository(container: try open(url)).load() == reordered, "Saved ordering is exact")
        try storage.save([edited[0]])
        check(storage.lastSave.removedRecords == 2, "Explicit conversation deletion removes its exact indexed metadata and chunks")
        check(try records.read("unrelated-owner") == Data([1, 2, 3]) && records.read(ConversationRepository.legacyKey) == legacy, "Unrelated records and original legacy bytes are preserved")

        // Failure/interruption cannot publish a new comparison baseline or leave dirty
        // chunk/index data available for an unrelated later save.
        var fail = false
        let injected = LocalRecordRepository(container: container) { _ in if fail { throw Injected.failed } }
        let interrupted = ConversationRepository(container: container, repository: injected)
        var baseline = try interrupted.load(), pending = baseline
        pending[0].turns[0].content = "A fictional update that must roll back"
        pending[0].turns.append(.init(id: uuid(850_000), role: "assistant", content: "Uncommitted append", completed: true))
        let before = try records.read(ConversationRepository.indexKey)
        fail = true
        rejects("Injected save failure must throw") { try interrupted.save(pending) }
        check(try records.read(ConversationRepository.indexKey) == before, "Failed save keeps the earlier index revision")
        try records.write(["later-unrelated": Data([4])])
        check(try ConversationRepository(container: try open(url)).load() == baseline, "Later save and reopening cannot resurrect failed chunks")
        fail = false
        try interrupted.save(pending)
        check(try ConversationRepository(container: try open(url)).load() == pending, "Retry after a verified failed transaction compares the retained baseline")
        baseline = pending
        let stale = ConversationRepository(container: container); _ = try stale.load()
        pending[0].title = "Changed by the current owner"
        try interrupted.save(pending)
        rejects("A stale owner must not overwrite a fresh index revision") { try stale.save(baseline) }

        // Readback corruption is an uncertain save: retain the old cached baseline
        // and reject another save until a fresh load reconciles the new index.
        var corrupt = false
        let corrupting = LocalRecordRepository(container: container) { context in
            if corrupt, let index = try context.fetch(LocalRecordRepository.request(ConversationRepository.indexKey)).first {
                var json = try object(index.data); json["futureReadbackMarker"] = true; index.data = try data(json)
            }
        }
        let uncertain = ConversationRepository(container: container, repository: corrupting)
        var unverified = try uncertain.load(); unverified[0].title = "Uncertain fictional save"
        corrupt = true
        rejects("Unexpected changed readback must fail") { try uncertain.save(unverified) }
        corrupt = false
        rejects("An uncertain save must not automatically replay") { try uncertain.save(unverified) }
        check(try uncertain.load() == unverified, "Explicit fresh load reconciles a committed but unverified save")
        unverified[0].title = "After explicit reconciliation"
        try uncertain.save(unverified)
        check(try object(records.read(ConversationRepository.indexKey))["futureReadbackMarker"] as? Bool == true, "Unknown index fields survive subsequent supported saves")

        // Existing indexes take precedence over legacy bytes, including unsupported
        // or missing data. Never quietly fallback and overwrite newer history.
        let indexBytes = try records.read(ConversationRepository.indexKey)!
        let metadataBytes = try records.read(ConversationRepository.metadataKey(original[0].id))!
        let chunkBytes = try records.read(ConversationRepository.chunkKey(original[0].id, 0))!
        func invalidFixture(_ label: String, index: Data, metadata: Data? = metadataBytes, chunk: Data? = chunkBytes) throws {
            let (broken, _) = try fresh(), records = LocalRecordRepository(container: broken)
            var values = [ConversationRepository.legacyKey: legacy, ConversationRepository.indexKey: index]
            values[ConversationRepository.metadataKey(original[0].id)] = metadata
            values[ConversationRepository.chunkKey(original[0].id, 0)] = chunk
            try records.write(values)
            let storage = ConversationRepository(container: broken)
            rejects(label) { _ = try storage.load() }
            rejects(label + " cannot be overwritten by save") { try storage.save(original) }
            check(try records.read(ConversationRepository.indexKey) == index && records.read(ConversationRepository.legacyKey) == legacy, label + " retains all original bytes")
        }
        var future = try object(indexBytes); future["version"] = 2
        try invalidFixture("Future index is unavailable", index: data(future))
        try invalidFixture("Malformed index is unavailable", index: Data("{broken".utf8))
        try invalidFixture("Missing indexed chunk is unavailable", index: indexBytes, chunk: nil)
        try invalidFixture("Missing indexed metadata is unavailable", index: indexBytes, metadata: nil)
        try invalidFixture("Malformed indexed chunk is unavailable", index: indexBytes, chunk: Data("[]".utf8))
        var wrong = try object(metadataBytes); wrong["id"] = uuid(999_999).uuidString
        try invalidFixture("Wrong metadata identity is unavailable", index: indexBytes, metadata: data(wrong))
        let (empty, _) = try fresh()
        check(try ConversationRepository(container: empty).load().isEmpty, "Genuinely absent storage starts empty")
        rejects("Unavailable container is not an empty successful load") { _ = try ConversationRepository(container: nil).load() }
        let (unsupported, _) = try fresh(), unsupportedRecords = LocalRecordRepository(container: unsupported)
        let unsupportedLegacy = Data("{\"version\":2,\"unknown\":true}".utf8)
        try unsupportedRecords.write([ConversationRepository.legacyKey: unsupportedLegacy])
        rejects("Unsupported legacy records cannot be discarded") { _ = try ConversationRepository(container: unsupported).load() }
        check(try unsupportedRecords.read(ConversationRepository.legacyKey) == unsupportedLegacy, "Unsupported legacy bytes remain intact")
        let (preciseContainer, _) = try fresh(), preciseRecords = LocalRecordRepository(container: preciseContainer)
        let known = String(data: try JSONEncoder().encode([conversation(7, turns: 1)]), encoding: .utf8)!
        let precisionLegacy = Data(("[{\"futureNumber\":123456789012345678901234567890123456789012345678901234567890," + known.dropFirst(2)).utf8)
        try preciseRecords.write([ConversationRepository.legacyKey: precisionLegacy])
        rejects("Opaque numeric precision cannot be silently rounded") { try ConversationRepository(container: preciseContainer).save([conversation(7, turns: 1)]) }
        check(try preciseRecords.read(ConversationRepository.legacyKey) == precisionLegacy && preciseRecords.read(ConversationRepository.indexKey) == nil, "Unsupported opaque numbers retain exact original bytes")
        let (collisionContainer, _) = try fresh(), collisionRecords = LocalRecordRepository(container: collisionContainer)
        let collisionKey = ConversationRepository.metadataKey(original[0].id), opaque = Data("opaque future metadata".utf8)
        try collisionRecords.write([ConversationRepository.legacyKey: legacy, collisionKey: opaque])
        rejects("Migration cannot overwrite an unindexed future record") { try ConversationRepository(container: collisionContainer).save(original) }
        check(try collisionRecords.read(collisionKey) == opaque && collisionRecords.read(ConversationRepository.indexKey) == nil, "Unowned namespace collisions preserve original bytes")

        let (boundaryContainer, _) = try fresh(), boundaryRecords = LocalRecordRepository(container: boundaryContainer), boundary = ConversationRepository(container: boundaryContainer)
        var atBoundary = [conversation(4, turns: 64)]
        try boundary.save(atBoundary)
        atBoundary[0].turns.append(.init(id: uuid(900_000), role: "user", content: "First turn in the next chunk", completed: true))
        try boundary.save(atBoundary)
        check(boundary.lastSave.encodedTurns == 1 && boundary.lastSave.writtenRecords == 2, "A 64-to-65 append writes only the new one-turn chunk and index")
        atBoundary[0].turns.removeLast()
        try boundary.save(atBoundary)
        check(boundary.lastSave.encodedTurns == 0 && boundary.lastSave.removedRecords == 1, "A 65-to-64 shrink removes the extra chunk without re-encoding unchanged turns")
        check(try boundaryRecords.read(ConversationRepository.chunkKey(atBoundary[0].id, 1)) == nil && ConversationRepository(container: boundaryContainer).load() == atBoundary, "Boundary shrink is exact and reloadable")

        let (largeContainer, _) = try fresh(), largeStorage = ConversationRepository(container: largeContainer)
        var large = [conversation(3, turns: 10_000)]
        for index in large[0].turns.indices { large[0].turns[index].content = String(repeating: "Fictional history. ", count: 100) }
        let entireBytes = try JSONEncoder().encode(large).count
        try largeStorage.save(large)
        large[0].turns[9_999].content += " A changed ending."
        try largeStorage.save(large)
        check(largeStorage.lastSave.encodedTurns == 16 && largeStorage.lastSave.writtenRecords == 2, "Large-history edit encodes only the final 16-turn chunk and index")
        check(largeStorage.lastSave.encodedBytes < entireBytes / 100, "Incremental encoding is under one percent of the full-history bytes")
        check(try ConversationRepository(container: largeContainer).load() == large, "Large-history incremental saves retain every original identity and field")
        print("Conversation repository: \(checks) checks passed. Legacy bytes, exact identities, unknown nested fields, nil removal, chunk edits/appends/shrink/deletion, failure/reopen/readback/ownership, corrupt/future refusal and 10,000-turn incremental encoding verified.")
        print("ENCODING MEASURE: complete history \(entireBytes) bytes; changed chunk + index \(largeStorage.lastSave.encodedBytes) bytes; encoded turns \(largeStorage.lastSave.encodedTurns). Fictional data only.")
    }
}
