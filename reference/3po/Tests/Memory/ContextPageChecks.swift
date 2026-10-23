import Foundation
import SwiftData

@main struct ContextPageChecks {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        func expectFailure(_ message: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(message) } catch { checks += 1 }
        }
        func container() throws -> ModelContainer {
            try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        func object(_ data: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        func bytes(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
        let clock = Date(timeIntervalSince1970: 2_000_000_000)
        let account = "fictional-account", other = "fictional-other"
        let fact1 = ContextPageReference(kind: "memory", key: "fact-1", revision: "v1")
        let fact2 = ContextPageReference(kind: "workspace", key: "project-2", revision: "v1")
        func sample(_ key: String = "everyday", registration: String = "fictional-account", kind: ContextPage.Kind = .overview,
                    owner: ContextPage.Owner = .human, references: [ContextPageReference] = []) -> ContextPage {
            .init(registration: registration, kind: kind, key: key, owner: owner, title: "Fictional context", synopsis: "Optics and study context", markdown: "# About my fictional work\n\nKeep qualifications intact.\n", references: references, created: clock)
        }

        let db = try container(), repository = LocalRecordRepository(container: db)
        let absent = ContextPageStore(container: db)
        check(absent.isReadable && absent.canSave && absent.pages(registration: account).isEmpty, "Absent store must be readable and empty")
        check(try repository.read(ContextPageStore.recordKey) == nil, "Opening an absent store must not write")
        check(absent.checkpoint(registration: account) == nil && absent.history(id: "missing", registration: account).isEmpty, "Missing lookup stays absent")
        check(absent.identityStatus(id: sample().id, registration: account) == .missing, "A readable empty store reports a missing identity")
        check(try repository.read(ContextPageStore.recordKey) == nil, "Identity inspection must not create an absent record")
        let unavailable = ContextPageStore(container: nil)
        check(!unavailable.isReadable && !unavailable.canSave && unavailable.error != nil, "Missing storage cannot pretend to save")
        check(unavailable.identityStatus(id: sample().id, registration: account) == .unavailable, "Unavailable storage must not report an identity as missing")
        expectFailure("Unavailable storage accepted a write") { _ = try unavailable.save(sample(), expectedRevision: nil) }
        check(unavailable.pages(registration: account).isEmpty, "No phantom page after failed save")

        let identity = sample().id
        var renamed = sample(); renamed.title = "Renamed without changing identity"
        check(renamed.id == identity && sample(registration: other).id != identity, "Page identity must survive rename and include registration")
        check(sample("a:b", registration: "c").id != sample("b", registration: "c:a").id, "Encoded components cannot collide through separators")
        check(sample("é/🍐", kind: .project).id == sample("é/🍐", kind: .project).id, "Unicode keys remain stable")
        check(sample("same", kind: .project).id != sample("same", kind: .topic).id, "Page kind participates in identity")
        check(ContextPageReference(kind: "a:b", key: "c", revision: "x").id != ContextPageReference(kind: "a", key: "b:c", revision: "x").id, "Reference identity must be collision-free")
        check(ContextPageReference(kind: fact1.kind, key: fact1.key, revision: "v2").id == fact1.id, "Reference version is separate from identity")

        let original = try absent.save(sample(references: [fact2, fact1]), expectedRevision: nil, now: clock)
        check(original.id == identity && original.revision != sample().revision && original.created == clock, "Committed page retains stable identity with a fresh revision")
        check(original.references.map(\.id) == original.references.map(\.id).sorted(), "References are deterministic")
        check(absent.pages(registration: other).isEmpty && absent.page(id: original.id, registration: other) == nil, "Account scope precedes lookup")
        check(absent.identityStatus(id: original.id, registration: account) == .available, "A supported current row reports an available identity")
        check(absent.identityStatus(id: original.id, registration: other) == .missing && absent.identityStatus(id: sample("missing").id, registration: account) == .missing, "Identity lookup requires the exact ID and account")
        let reload = ContextPageStore(container: db)
        check(reload.page(id: original.id, registration: account) == original, "Markdown and metadata must roundtrip")
        check(reload.history(id: original.id, registration: account).map(\.page) == [original], "First save creates immutable history")
        let beforeDuplicate = try repository.read(ContextPageStore.recordKey)
        expectFailure("Create-only overwrite accepted") { _ = try absent.save(sample(), expectedRevision: nil) }
        expectFailure("Wrong editor revision accepted") { _ = try absent.save(sample(), expectedRevision: UUID()) }
        check(try repository.read(ContextPageStore.recordKey) == beforeDuplicate, "Rejected edits leave bytes exact")
        var edit = original; edit.markdown += "\nA later explicit clarification."
        let revised = try absent.save(edit, expectedRevision: original.revision, now: clock.addingTimeInterval(60))
        check(revised.id == original.id && revised.revision != original.revision && revised.created == original.created, "Edit creates a new revision within the same page")
        check(absent.history(id: original.id, registration: account).first?.page == original, "Editing must not alter the old version")
        check(absent.history(id: original.id, registration: account).last?.parentRevision == original.revision, "History keeps parent lineage")
        let beforeStaleInstance = try repository.read(ContextPageStore.recordKey)
        expectFailure("A stale second instance overwrote the latest page") { _ = try reload.save(edit, expectedRevision: original.revision) }
        check(try repository.read(ContextPageStore.recordKey) == beforeStaleInstance, "Failed second-instance CAS retains persisted state")
        check(reload.reload() && reload.page(id: original.id, registration: account) == revised, "Explicit reload adopts the committed owner")
        let otherPage = try reload.save(sample("other", registration: other, kind: .note), expectedRevision: nil, now: clock)
        check(reload.pages(registration: other) == [otherPage], "Second account remains isolated")
        check(absent.reload(), "Reload before restore")
        let restored = try absent.restore(id: original.id, registration: account, revision: original.revision, expectedRevision: revised.revision, now: clock.addingTimeInterval(120))
        let lineage = absent.history(id: original.id, registration: account)
        check(restored.markdown == original.markdown && restored.references == original.references, "Restore copies the chosen exact historical snapshot")
        check(restored.revision != original.revision && restored.revision != revised.revision && lineage.count == 3, "Restore appends instead of rewinding")
        check(lineage.last?.parentRevision == revised.revision && lineage.last?.restoredFrom == original.revision, "Restore records both parent and selected ancestor")
        check(absent.history(id: original.id, registration: other).isEmpty, "History cannot cross accounts")
        expectFailure("Wrong-account restore succeeded") { _ = try absent.restore(id: original.id, registration: other, revision: original.revision, expectedRevision: restored.revision) }
        expectFailure("Missing version restore succeeded") { _ = try absent.restore(id: original.id, registration: account, revision: UUID(), expectedRevision: restored.revision) }

        let firstChanges = try absent.changes(registration: account, currentReferences: [fact1, fact2])
        check(firstChanges.added.count == 2 && firstChanges.changed.isEmpty && firstChanges.removed.isEmpty, "Before consolidation, all current snapshots are pending")
        let cp = ContextPageCheckpoint(registration: account, references: [fact2, fact1])
        var consolidated = restored; consolidated.synopsis = "Consolidated optics context"
        let batch = try absent.saveBatch([consolidated], expectedRevisions: [restored.id: restored.revision], checkpoint: cp, now: clock.addingTimeInterval(180))
        let checkpoint = absent.checkpoint(registration: account)!
        check(batch.count == 1 && checkpoint.references.map(\.id) == checkpoint.references.map(\.id).sorted(), "Pages and checkpoint commit together")
        check(try absent.changes(registration: account, currentReferences: [fact2, fact1]).isEmpty, "Acknowledged current snapshots stop being pending")
        let changedFact = ContextPageReference(kind: fact1.kind, key: fact1.key, revision: "corrected-v2")
        let newFact = ContextPageReference(kind: "humanTurn", key: "turn-3", revision: "turn-v1")
        let changes = try absent.changes(registration: account, currentReferences: [changedFact, newFact])
        check(changes.changed == [.init(previous: fact1, current: changedFact)] && changes.added == [newFact] && changes.removed == [fact2], "Working changes retain exact additions, corrections and removals")
        check(!changes.isEmpty && changes.unchangedCount == 0, "Nonempty changes are explicit")
        check(try absent.changes(registration: other, currentReferences: [fact1]).added == [fact1], "Another account's checkpoint cannot acknowledge changes")
        expectFailure("Duplicate reference identity accepted") { _ = try absent.changes(registration: account, currentReferences: [fact1, changedFact]) }
        let beforeBadBatch = try repository.read(ContextPageStore.recordKey)
        expectFailure("Stale checkpoint allowed partial page save") {
            _ = try absent.saveBatch([sample("batch-rejected", kind: .project)], checkpoint: cp, expectedCheckpointRevision: UUID())
        }
        check(try repository.read(ContextPageStore.recordKey) == beforeBadBatch && absent.page(id: sample("batch-rejected", kind: .project).id, registration: account) == nil, "A rejected checkpoint cannot publish a partial page")
        expectFailure("Checkpoint account mismatch accepted") { _ = try absent.saveBatch([sample("mixed", registration: other)], checkpoint: cp, expectedCheckpointRevision: checkpoint.revision) }
        expectFailure("Duplicate batch page accepted") { _ = try absent.saveBatch([sample("repeat"), sample("repeat")]) }
        expectFailure("Extraneous expected revision accepted") { _ = try absent.saveBatch([sample("extra")], expectedRevisions: ["unrelated": UUID()]) }
        var invalidBatchPage = sample("invalid-batch")
        invalidBatchPage.markdown = String(repeating: "b", count: ContextPageLimits.maximumMarkdownBytes + 1)
        expectFailure("Invalid second page allowed first page to commit") {
            _ = try absent.saveBatch([sample("valid-but-uncommitted"), invalidBatchPage], checkpoint: cp, expectedCheckpointRevision: checkpoint.revision)
        }
        check(try repository.read(ContextPageStore.recordKey) == beforeBadBatch, "Batch field failure preserves pages and checkpoint atomically")
        let checkpoint2 = try absent.saveCheckpoint(.init(registration: account, references: [changedFact, newFact]), expectedRevision: checkpoint.revision, now: clock.addingTimeInterval(240))
        check(checkpoint2.revision != checkpoint.revision && checkpoint2.id == checkpoint.id, "Checkpoint identity is stable and its revision changes")
        let beforeRestoreCheckpoint = absent.checkpoint(registration: account)
        _ = try absent.restore(id: original.id, registration: account, revision: original.revision, expectedRevision: batch[0].revision, now: clock.addingTimeInterval(300))
        check(absent.checkpoint(registration: account) == beforeRestoreCheckpoint, "Restore never acknowledges pending canonical changes")
        check(ContextPageStore(container: db).checkpoint(registration: account) == checkpoint2, "Checkpoint survives reopen")

        let beforeForget = try repository.read(ContextPageStore.recordKey)
        let forgetCurrent = absent.page(id: original.id, registration: account)!
        expectFailure("Wrong account forgot a human page") { try absent.forget(id: original.id, registration: other, expectedRevision: forgetCurrent.revision) }
        expectFailure("Stale revision forgot a human page") { try absent.forget(id: original.id, registration: account, expectedRevision: UUID()) }
        check(try repository.read(ContextPageStore.recordKey) == beforeForget, "Rejected Forget leaves every record intact")
        try absent.forget(id: original.id, registration: account, expectedRevision: forgetCurrent.revision)
        check(absent.page(id: original.id, registration: account) == nil && absent.history(id: original.id, registration: account).isEmpty, "Human Forget removes exact page and lineage")
        check(absent.pages(registration: other) == [otherPage] && absent.checkpoint(registration: account) == checkpoint2, "Forget preserves other accounts and pending consolidation metadata")
        expectFailure("Forgotten lineage could be restored") { _ = try absent.restore(id: original.id, registration: account, revision: original.revision, expectedRevision: forgetCurrent.revision) }
        let afterForget = ContextPageStore(container: db)
        check(afterForget.history(id: original.id, registration: account).isEmpty && afterForget.pages(registration: other) == [otherPage], "Forget survives reopen without affecting sibling records")

        let projectionDB = try container(), projections = ContextPageStore(container: projectionDB)
        let candidates = (0..<36).map { index -> ContextPage in
            var page = sample("directory-\(index)", kind: .project, owner: .generated, references: [fact1])
            page.synopsis = String(repeating: "s", count: 500); return page
        }
        let many = try projections.saveBatch(candidates, now: clock)
        expectFailure("Generated projections can be forgotten without canonical source changes") { try projections.forget(id: many[0].id, registration: account, expectedRevision: many[0].revision) }
        let directory = try projections.directory(registration: account, maximumBytes: 1_600, isEligible: { _ in true })
        check(directory.omittedCount > 0 && directory.entries.count + directory.omittedCount == many.count, "Bounded directory reports omitted pages")
        check(try directory.encoded().count <= 1_600 && projections.pages(registration: account).count == many.count, "Projection bounds never prune stored pages")
        check(try projections.directory(registration: account, isEligible: { _ in false }).entries.isEmpty, "Eligibility has no permissive default")
        let withdrawn = try projections.directory(registration: account, isEligible: { $0.references.allSatisfy { $0 != fact1 } })
        check(withdrawn.entries.isEmpty && withdrawn.omittedCount == 0, "Revoked support is excluded before directory counts")
        let corrected = try projections.directory(registration: account, isEligible: { $0.references.allSatisfy { $0 == changedFact } })
        check(corrected.entries.isEmpty, "A correction cannot reuse a page with an old exact snapshot")
        expectFailure("Zero-byte index accepted") { _ = try projections.directory(registration: account, maximumBytes: 0, isEligible: { _ in true }) }
        check(try ContextPageLimits.providerPayload(many[0], isEligible: { _ in false }) == nil, "Ineligible page never reaches a provider payload")
        check(try ContextPageLimits.providerPayload(many[0], isEligible: { _ in true }) != nil, "Eligible bounded page produces explicit payload")
        expectFailure("Provider silently truncated a page") { _ = try ContextPageLimits.providerPayload(many[0], maximumBytes: 1, isEligible: { _ in true }) }
        var large = sample("large", kind: .note); large.markdown = String(repeating: "\\", count: ContextPageLimits.maximumMarkdownBytes)
        let largeSaved = try projections.save(large, expectedRevision: nil)
        check(largeSaved.markdown == large.markdown, "Stored Markdown is preserved even when escaped provider bytes are larger")
        expectFailure("Oversized escaped provider payload accepted") { _ = try ContextPageLimits.providerPayload(largeSaved, isEligible: { _ in true }) }
        var tooLarge = sample("too-large"); tooLarge.markdown = String(repeating: "🍐", count: 6_001)
        expectFailure("UTF-8 body bound was counted as characters") { _ = try projections.save(tooLarge, expectedRevision: nil) }
        var invalid = sample("bad-title"); invalid.title = "  "
        expectFailure("Blank title accepted") { _ = try projections.save(invalid, expectedRevision: nil) }
        invalid = sample("bad-synopsis"); invalid.synopsis = String(repeating: "s", count: ContextPageLimits.maximumSynopsisBytes + 1)
        expectFailure("Oversized synopsis accepted") { _ = try projections.save(invalid, expectedRevision: nil) }
        invalid = sample("bad-refs", references: [fact1, fact1])
        expectFailure("Duplicate page snapshots accepted") { _ = try projections.save(invalid, expectedRevision: nil) }
        invalid = sample("empty-revision", references: [.init(kind: "memory", key: "a", revision: " ")])
        expectFailure("Empty evidence revision accepted") { _ = try projections.save(invalid, expectedRevision: nil) }
        let humanCalendar = try projections.save(sample("provider-exact-calendar-id", kind: .calendarPurpose), expectedRevision: nil)
        check(humanCalendar.kind == .calendarPurpose && humanCalendar.owner == .human, "Calendar purposes bind exact IDs, independently of labels")
        var rolling = many[0]
        for index in 0..<65 {
            rolling.markdown = "Fictional version \(index)."
            rolling = try projections.save(rolling, expectedRevision: rolling.revision, now: clock.addingTimeInterval(Double(index)))
        }
        check(projections.history(id: rolling.id, registration: account).count == 66, "History must not have a silent hard cap")
        check(ContextPageStore(container: projectionDB).history(id: rolling.id, registration: account).first?.page == many[0], "Old history remains immutable after many edits")

        for bad in [Data("not json".utf8), Data("{\"schemaVersion\":99,\"futurePayload\":[1,2]}".utf8), try bytes(["schemaVersion": 1, "pages": [object(try JSONEncoder().encode(original)), object(try JSONEncoder().encode(original))]]), Data("[]".utf8), Data("{\"schemaVersion\":null}".utf8), Data("{\"pages\":null}".utf8)] {
            let corruptDB = try container(), corruptRepo = LocalRecordRepository(container: corruptDB)
            try corruptRepo.write([ContextPageStore.recordKey: bad])
            let blocked = ContextPageStore(container: corruptDB)
            check(!blocked.isReadable && !blocked.canSave && blocked.pages(registration: account).isEmpty, "Corrupt/unsupported storage must fail closed")
            check(blocked.identityStatus(id: original.id, registration: account) == .unavailable && blocked.identityStatus(id: "missing", registration: other) == .unavailable, "Unreadable storage cannot claim any identity is missing")
            expectFailure("Corrupt record accepted a write") { _ = try blocked.save(sample("replacement"), expectedRevision: nil) }
            check(try corruptRepo.read(ContextPageStore.recordKey) == bad, "Corrupt and unsupported original bytes must be preserved")
        }
        let legacyDB = try container(), legacyRepo = LocalRecordRepository(container: legacyDB)
        let legacyData = try bytes(["pages": [object(try JSONEncoder().encode(original))], "legacyOptional": ["retained": true]])
        try legacyRepo.write([ContextPageStore.recordKey: legacyData])
        let legacy = ContextPageStore(container: legacyDB)
        check(legacy.isReadable && legacy.page(id: original.id, registration: account) == original, "Legacy page-only envelope remains readable")
        check(try legacy.history(id: original.id, registration: account).count == 1 && legacyRepo.read(ContextPageStore.recordKey) == legacyData, "Inspecting legacy history must not write")
        let legacyRevised = try legacy.save(edit, expectedRevision: original.revision, now: clock.addingTimeInterval(30))
        check(legacy.history(id: original.id, registration: account).map(\.page) == [original, legacyRevised], "First legacy edit captures its original version")
        check((try object(legacyRepo.read(ContextPageStore.recordKey)!))["legacyOptional"] != nil, "Legacy unknown additive fields survive edits")
        let legacyReferenceDB = try container(), legacyReferenceRepo = LocalRecordRepository(container: legacyReferenceDB)
        var oldReferencePage = try object(JSONEncoder().encode(original))
        var oldReferenceRows = oldReferencePage["references"] as! [[String: Any]]
        for index in oldReferenceRows.indices { oldReferenceRows[index].removeValue(forKey: "id") }
        oldReferencePage["references"] = oldReferenceRows
        try legacyReferenceRepo.write([ContextPageStore.recordKey: bytes(["pages": [oldReferencePage]])])
        check(ContextPageStore(container: legacyReferenceDB).page(id: original.id, registration: account) == original, "Legacy reference IDs are derived without losing exact identity/version")
        let emptyDB = try container(), emptyRepo = LocalRecordRepository(container: emptyDB)
        try emptyRepo.write([ContextPageStore.recordKey: Data("{}".utf8)])
        let emptyLegacy = ContextPageStore(container: emptyDB)
        check(emptyLegacy.isReadable && emptyLegacy.pages(registration: account).isEmpty, "Empty legacy envelope is supported")
        _ = try emptyLegacy.save(sample(), expectedRevision: nil)

        let opaqueDB = try container(), opaqueRepo = LocalRecordRepository(container: opaqueDB), opaqueInitial = ContextPageStore(container: opaqueDB)
        let opaquePage = try opaqueInitial.save(sample(references: [fact1]), expectedRevision: nil)
        _ = try opaqueInitial.saveCheckpoint(.init(registration: account, references: [fact1]), expectedRevision: nil)
        var opaqueObject = try object(opaqueRepo.read(ContextPageStore.recordKey)!)
        opaqueObject["futureRoot"] = ["keep": true, "number": 42]
        var opaquePages = opaqueObject["pages"] as! [[String: Any]]
        opaquePages[0]["futurePage"] = "keep this exact optional field"
        var opaqueReferences = opaquePages[0]["references"] as! [[String: Any]]
        opaqueReferences[0]["futureReference"] = ["keep": true]; opaquePages[0]["references"] = opaqueReferences
        opaqueObject["pages"] = opaquePages
        var opaqueVersions = opaqueObject["versions"] as! [[String: Any]]
        opaqueVersions[0]["futureVersion"] = "keep history"
        var opaqueHistoryPage = opaqueVersions[0]["page"] as! [String: Any]
        opaqueHistoryPage["futureHistoryPage"] = "keep prior page"
        opaqueVersions[0]["page"] = opaqueHistoryPage; opaqueObject["versions"] = opaqueVersions
        var opaqueCheckpoints = opaqueObject["checkpoints"] as! [[String: Any]]
        opaqueCheckpoints[0]["futureCheckpoint"] = "keep cursor"; opaqueObject["checkpoints"] = opaqueCheckpoints
        try opaqueRepo.write([ContextPageStore.recordKey: bytes(opaqueObject)])
        let opaque = ContextPageStore(container: opaqueDB)
        check(opaque.isReadable, "Unknown additive fields are compatible")
        var opaqueEdit = opaquePage; opaqueEdit.markdown += "\nNew human information."
        _ = try opaque.save(opaqueEdit, expectedRevision: opaquePage.revision)
        let afterOpaque = try object(opaqueRepo.read(ContextPageStore.recordKey)!)
        let afterOpaquePage = (afterOpaque["pages"] as! [[String: Any]])[0]
        check(afterOpaque["futureRoot"] != nil && afterOpaquePage["futurePage"] as? String == "keep this exact optional field", "Root and current-page unknown fields survive ordinary writes")
        check(((afterOpaquePage["references"] as! [[String: Any]])[0])["futureReference"] != nil, "Reference additive fields survive ordinary writes")
        let afterOpaqueVersions = afterOpaque["versions"] as! [[String: Any]]
        check(afterOpaqueVersions[0]["futureVersion"] != nil && (afterOpaqueVersions[0]["page"] as! [String: Any])["futureHistoryPage"] != nil, "Prior immutable version retains unknown history fields")
        check((afterOpaque["checkpoints"] as! [[String: Any]])[0]["futureCheckpoint"] != nil, "Untouched checkpoint retains unknown metadata")

        let futureDB = try container(), futureRepo = LocalRecordRepository(container: futureDB)
        let futurePage = sample("future", kind: .init(rawValue: "futureKind"))
        let unknownOwner = sample("future-owner", owner: .init(rawValue: "futureOwner"))
        var futureKindRow = try object(JSONEncoder().encode(futurePage))
        futureKindRow["opaqueFutureKind"] = ["retained": true]
        var futureOwnerRow = try object(JSONEncoder().encode(unknownOwner))
        futureOwnerRow["opaqueFutureOwner"] = "Retain without exposing this content"
        let futureBytes = try bytes(["schemaVersion": 1, "pages": [futureKindRow, futureOwnerRow]])
        try futureRepo.write([ContextPageStore.recordKey: futureBytes])
        let future = ContextPageStore(container: futureDB)
        check(future.isReadable && future.pages(registration: account).isEmpty && future.page(id: futurePage.id, registration: account) == nil && future.page(id: unknownOwner.id, registration: account) == nil, "Unknown page kinds and ownership are excluded from readable projections")
        check(future.identityStatus(id: futurePage.id, registration: account) == .preserved, "An unknown kind reserves its exact stable ID")
        check(future.identityStatus(id: unknownOwner.id, registration: account) == .preserved, "An unknown owner reserves its exact supported-kind stable ID")
        check(future.identityStatus(id: futurePage.id, registration: other) == .missing && future.identityStatus(id: unknownOwner.id, registration: other) == .missing && future.identityStatus(id: sample("missing").id, registration: account) == .missing, "Preserved identities stay exact and account scoped")
        check(future.history(id: futurePage.id, registration: account).isEmpty && future.history(id: unknownOwner.id, registration: account).isEmpty, "Identity inspection does not expose unsupported history")
        check(try futureRepo.read(ContextPageStore.recordKey) == futureBytes, "Inspecting preserved identities leaves original bytes exact")
        expectFailure("Unknown kind was editable") { _ = try future.save(futurePage, expectedRevision: futurePage.revision) }
        expectFailure("Unknown owner was overwritten by a create-only supported page") { _ = try future.save(sample("future-owner"), expectedRevision: nil) }
        expectFailure("Unknown owner was replaced with a supported owner") { _ = try future.save(sample("future-owner"), expectedRevision: unknownOwner.revision) }
        check(try futureRepo.read(ContextPageStore.recordKey) == futureBytes, "Rejected replacement of a reserved identity preserves original bytes")
        var supportedSibling = try future.save(sample("supported"), expectedRevision: nil)
        let futureSaved = try object(futureRepo.read(ContextPageStore.recordKey)!)
        check((futureSaved["pages"] as! [[String: Any]]).count == 3, "Unknown future pages survive writing a supported sibling")
        check((futureSaved["versions"] as! [[String: Any]]).count == 3, "Legacy unknown pages retain their original version on first save")
        supportedSibling.markdown += "\nAn explicit fictional human edit."
        supportedSibling = try future.save(supportedSibling, expectedRevision: supportedSibling.revision)
        check(future.identityStatus(id: supportedSibling.id, registration: account) == .available, "A supported sibling remains available after an edit")
        let futureReopened = ContextPageStore(container: futureDB)
        check(futureReopened.identityStatus(id: futurePage.id, registration: account) == .preserved && futureReopened.identityStatus(id: unknownOwner.id, registration: account) == .preserved, "Preserved identities survive a supported sibling edit and reopen")
        let editedFutureRows = (try object(futureRepo.read(ContextPageStore.recordKey)!))["pages"] as! [[String: Any]]
        check(try bytes(editedFutureRows.first { $0["id"] as? String == futurePage.id }!) == bytes(futureKindRow) && bytes(editedFutureRows.first { $0["id"] as? String == unknownOwner.id }!) == bytes(futureOwnerRow), "Sibling edits preserve opaque page bodies and unknown fields exactly")
        try future.forget(id: supportedSibling.id, registration: account, expectedRevision: supportedSibling.revision)
        let futureAfterForget = try object(futureRepo.read(ContextPageStore.recordKey)!)
        check((futureAfterForget["pages"] as! [[String: Any]]).count == 2 && (futureAfterForget["versions"] as! [[String: Any]]).count == 2, "Forgetting a human sibling preserves unknown future pages and their lineages")
        check(future.identityStatus(id: supportedSibling.id, registration: account) == .missing && future.identityStatus(id: futurePage.id, registration: account) == .preserved && future.identityStatus(id: unknownOwner.id, registration: account) == .preserved, "Forgetting a supported sibling leaves reserved identities intact")
        let forgottenFutureRows = futureAfterForget["pages"] as! [[String: Any]]
        check(try bytes(forgottenFutureRows.first { $0["id"] as? String == futurePage.id }!) == bytes(futureKindRow) && bytes(forgottenFutureRows.first { $0["id"] as? String == unknownOwner.id }!) == bytes(futureOwnerRow), "Sibling Forget preserves opaque page bodies and unknown fields exactly")
        let lossyDB = try container(), lossyRepo = LocalRecordRepository(container: lossyDB)
        let lossy = Data("{\"futureNumeric\":1.234567890123456789012345678901234567890,\"pages\":[]}".utf8)
        try lossyRepo.write([ContextPageStore.recordKey: lossy])
        let lossyStore = ContextPageStore(container: lossyDB)
        check(lossyStore.isReadable, "Unknown data may be readable without being safely writable")
        expectFailure("An opaque number was rounded while preserving unknown fields") { _ = try lossyStore.save(sample(), expectedRevision: nil) }
        check(try lossyRepo.read(ContextPageStore.recordKey) == lossy, "Unsupported lossless merge preserves original bytes")

        let racingDB = try container(), racingRepo = LocalRecordRepository(container: racingDB)
        let racerA = ContextPageStore(container: racingDB), racerB = ContextPageStore(container: racingDB)
        let racerSaved = try racerA.save(sample("racer-a"), expectedRevision: nil)
        expectFailure("Second initially-empty store overwrote a newly created record") { _ = try racerB.save(sample("racer-b"), expectedRevision: nil) }
        check(ContextPageStore(container: racingDB).pages(registration: account) == [racerSaved], "Create race cannot overwrite another page")
        var externallyChanged = try object(racingRepo.read(ContextPageStore.recordKey)!)
        externallyChanged["futureOwnerToken"] = "external-update"
        try racingRepo.write([ContextPageStore.recordKey: bytes(externallyChanged)])
        expectFailure("Stale writer lost an external additive field") { _ = try racerA.save(sample("racer-next"), expectedRevision: nil) }
        check((try object(racingRepo.read(ContextPageStore.recordKey)!))["futureOwnerToken"] as? String == "external-update", "Whole-record CAS preserves unrelated newer fields")
        let beforeStaleForget = try racingRepo.read(ContextPageStore.recordKey)
        expectFailure("Stale Forget removed another owner's newer record") { try racerA.forget(id: racerSaved.id, registration: account, expectedRevision: racerSaved.revision) }
        check(try racingRepo.read(ContextPageStore.recordKey) == beforeStaleForget, "Forget uses the same whole-record CAS as saves")
        let brokenLineageDB = try container(), brokenLineageRepo = LocalRecordRepository(container: brokenLineageDB)
        var brokenVersion = try object(JSONEncoder().encode(ContextPageVersion(page: original)))
        brokenVersion["parentRevision"] = original.revision.uuidString
        let brokenBytes = try bytes(["pages": [object(JSONEncoder().encode(original))], "versions": [brokenVersion]])
        try brokenLineageRepo.write([ContextPageStore.recordKey: brokenBytes])
        let broken = ContextPageStore(container: brokenLineageDB)
        check(!broken.isReadable && broken.history(id: original.id, registration: account).isEmpty, "Cyclic/invalid version lineage fails closed")
        expectFailure("Invalid lineage accepted a write") { _ = try broken.save(sample("replacement"), expectedRevision: nil) }
        check(try brokenLineageRepo.read(ContextPageStore.recordKey) == brokenBytes, "Invalid lineage bytes are preserved")
        check(try repository.read("paMemory") == nil, "Context pages never write canonical memory")
        print("PASS: \(checks) context-page checks; fictional in-memory storage only, no model/source/app operations")
    }
}
