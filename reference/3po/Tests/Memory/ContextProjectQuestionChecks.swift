import Foundation
import SwiftData

@main struct ContextProjectQuestionChecks {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
        func reject(_ message: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(message) } catch { checks += 1 }
        }
        func container() throws -> ModelContainer {
            try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        func object(_ data: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        func bytes(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
        let account = "fictional-account", other = "fictional-other"
        let clock = Date(timeIntervalSince1970: 2_000_000_000)
        let project = UUID(), secondProject = UUID()
        func identity(_ id: UUID, _ revision: String = "identity-v1") -> ContextPageReference {
            .init(kind: "projectIdentity", key: id.uuidString, revision: revision)
        }
        let wording = "What is the purpose of this fictional project?"
        let db = try container(), repository = LocalRecordRepository(container: db)
        let store = ContextProjectQuestionStore(container: db)
        check(store.isReadable && store.canSave && store.questions(registration: account).isEmpty, "Missing store is readable and empty")
        check(try repository.read(ContextProjectQuestionStore.recordKey) == nil, "Opening missing storage must not write")
        let first = try store.offer(registration: account, projectID: project, identity: identity(project), question: wording, now: clock)!
        check(first.id == ContextProjectQuestion.stableID(registration: account, projectID: project), "Question identity is stable per account/project")
        check(first.identity == identity(project) && first.created == clock && first.updated == clock && first.status == .pending, "Offer captures exact identity and original time")
        check(first.answerPageID == nil && first.answerPageRevision == nil && first.finished == nil, "Pending questions carry no answer receipt")
        check(ContextProjectQuestionRules.candidate(status: "planned", hasOpenWork: true, hasHumanNotes: false), "A modern space with current work may be considered without a legacy project kind")
        check(ContextProjectQuestionRules.candidate(status: "active", hasOpenWork: false, hasHumanNotes: true), "An explicitly active space with human notes may be considered")
        check(!ContextProjectQuestionRules.candidate(status: "planned", hasOpenWork: false, hasHumanNotes: false) && !ContextProjectQuestionRules.candidate(status: "active", hasOpenWork: false, hasHumanNotes: false), "A missing description and empty space never establish importance")
        check(!ContextProjectQuestionRules.candidate(status: "planned", hasOpenWork: false, hasHumanNotes: true), "Routine notes in an otherwise inactive folder do not trigger an interview")
        for status in ["done", "archived", "future-status"] {
            check(!ContextProjectQuestionRules.candidate(status: status, hasOpenWork: true, hasHumanNotes: true), "Closed or unknown-status spaces cannot ask clarification")
        }
        check(ContextProjectQuestionRules.actionable(first, currentIdentity: identity(project), candidate: true, hasPurpose: false), "A pending important exact-space question occupies the pending slot")
        for current in [nil, identity(project, "new-scope"), identity(secondProject)] {
            check(!ContextProjectQuestionRules.actionable(first, currentIdentity: current, candidate: true, hasPurpose: false), "Deleted, moved or different space questions cannot starve current clarification")
        }
        check(!ContextProjectQuestionRules.actionable(first, currentIdentity: identity(project), candidate: false, hasPurpose: false), "A formerly important but now inactive question cannot starve current clarification")
        let manualPurpose = ContextPage(registration: account, kind: .note, key: "project-purpose:" + project.uuidString,
            owner: .human, title: "Human purpose", markdown: "Compare the fictional calibration designs.", references: [identity(project)])
        check(ContextProjectQuestionRules.purpose(manualPurpose, registration: account, identity: identity(project)), "An exact current human purpose page satisfies the pending question")
        check(!ContextProjectQuestionRules.actionable(first, currentIdentity: identity(project), candidate: true, hasPurpose: ContextProjectQuestionRules.purpose(manualPurpose, registration: account, identity: identity(project))), "An ordinary manual purpose save frees the pending slot without rewriting question history")
        check(store.questions(registration: account) == [first], "Actionability inspection preserves the exact stored pending question")
        for invalidPurpose in [ContextPage(registration: other, kind: .note, key: manualPurpose.key, owner: .human, title: "Other account", markdown: manualPurpose.markdown, references: manualPurpose.references),
            ContextPage(registration: account, kind: .note, key: manualPurpose.key, owner: .generated, title: "Generated", markdown: manualPurpose.markdown, references: manualPurpose.references),
            ContextPage(registration: account, kind: .note, key: manualPurpose.key, owner: .human, title: "Old scope", markdown: manualPurpose.markdown, references: [identity(project, "old-scope")]),
            ContextPage(registration: account, kind: .note, key: manualPurpose.key, owner: .human, title: "Blank", markdown: " \n", references: manualPurpose.references)] {
            check(!ContextProjectQuestionRules.purpose(invalidPurpose, registration: account, identity: identity(project)), "Other-account/generated/old-scope/blank notes cannot suppress a current clarification")
        }
        let originalBytes = try repository.read(ContextProjectQuestionStore.recordKey)
        let originalGeneration = store.revision
        let repeated = try store.offer(registration: account, projectID: project, identity: identity(project), question: "Could you explain the purpose another way?", now: clock.addingTimeInterval(60))
        check(repeated == first && store.revision == originalGeneration, "Repeated wording returns the original pending question without a new revision")
        check(try repository.read(ContextProjectQuestionStore.recordKey) == originalBytes, "Repeat offer does not rewrite storage")
        check(ContextProjectQuestionStore(container: db).questions(registration: account) == [first], "Pending question survives reopening exactly")
        check(store.questions(registration: other).isEmpty, "Question projections respect account scope")
        let differentAccount = try store.offer(registration: other, projectID: project, identity: identity(project), question: wording, now: clock)!
        check(differentAccount.id != first.id && store.questions(registration: other) == [differentAccount], "Same project UUID cannot merge questions across accounts")
        let second = try store.offer(registration: account, projectID: secondProject, identity: identity(secondProject), question: "What outcome should this fictional project achieve?", now: clock.addingTimeInterval(20))!
        check(second.id != first.id && store.questions(registration: account).count == 2, "Separate projects have separate questions")
        let beforeScopeChange = try repository.read(ContextProjectQuestionStore.recordKey)
        check(try store.offer(registration: account, projectID: project, identity: identity(project, "new-scope"), question: wording) == nil, "Changed project scope cannot silently retarget the saved question")
        check(try repository.read(ContextProjectQuestionStore.recordKey) == beforeScopeChange, "Scope change cannot rewrite original identity or wording")
        reject("Wrong account dismissed a question") { _ = try store.dismiss(id: first.id, registration: other, expectedRevision: first.revision) }
        reject("Stale revision dismissed a question") { _ = try store.dismiss(id: first.id, registration: account, expectedRevision: UUID()) }
        check(try repository.read(ContextProjectQuestionStore.recordKey) == beforeScopeChange, "Rejected dismissals leave exact stored state")
        let dismissed = try store.dismiss(id: first.id, registration: account, expectedRevision: first.revision, now: clock.addingTimeInterval(40))
        check(dismissed.status == .dismissed && dismissed.revision != first.revision && dismissed.finished == clock.addingTimeInterval(40), "Dismiss records a new exact state")
        check(dismissed.question == first.question && dismissed.identity == first.identity && dismissed.created == first.created, "Dismiss preserves the original clarification")
        check(!ContextProjectQuestionRules.actionable(dismissed, currentIdentity: identity(project), candidate: true, hasPurpose: false), "Renewed importance cannot reopen a dismissed concern")
        check(store.questions(registration: account) == [second] && store.questions(registration: account, includeFinished: true).count == 2, "Finished question remains in local history, outside pending Review")
        let beforeSuppressed = try repository.read(ContextProjectQuestionStore.recordKey)
        check(try store.offer(registration: account, projectID: project, identity: identity(project), question: "Why is this project important?", now: clock.addingTimeInterval(100)) == nil, "Human dismissal is not resurrected by another model offer")
        check(try repository.read(ContextProjectQuestionStore.recordKey) == beforeSuppressed, "Dismissed question remains exact after repeated offers")
        let dismissedReload = ContextProjectQuestionStore(container: db)
        check(try dismissedReload.offer(registration: account, projectID: project, identity: identity(project), question: wording) == nil, "Dismissal dedup survives reopening")
        reject("Dismissed question accepted an answer") { _ = try store.answer(id: dismissed.id, registration: account, expectedRevision: dismissed.revision, pageID: "unused", pageRevision: UUID()) }
        reject("Already dismissed question changed again") { _ = try store.dismiss(id: dismissed.id, registration: account, expectedRevision: dismissed.revision) }

        let pageStore = ContextPageStore(container: db)
        let purposeText = "Fictional purpose answer text belongs only in its human-owned context page."
        let purpose = try pageStore.save(.init(registration: account, kind: .note, key: "purpose:" + secondProject.uuidString,
                                               owner: .human, title: "Fictional project purpose", markdown: purposeText), expectedRevision: nil, now: clock)
        let beforeBadAnswer = try repository.read(ContextProjectQuestionStore.recordKey)
        reject("Blank answer receipt accepted") { _ = try store.answer(id: second.id, registration: account, expectedRevision: second.revision, pageID: " ", pageRevision: purpose.revision) }
        reject("NUL-containing answer receipt accepted") { _ = try store.answer(id: second.id, registration: account, expectedRevision: second.revision, pageID: "bad\0page", pageRevision: purpose.revision) }
        reject("Wrong account answered a question") { _ = try store.answer(id: second.id, registration: other, expectedRevision: second.revision, pageID: purpose.id, pageRevision: purpose.revision) }
        reject("Stale answer acknowledgement accepted") { _ = try store.answer(id: second.id, registration: account, expectedRevision: UUID(), pageID: purpose.id, pageRevision: purpose.revision) }
        check(try repository.read(ContextProjectQuestionStore.recordKey) == beforeBadAnswer, "Invalid acknowledgements leave pending state exact")
        let answerTime = clock.addingTimeInterval(80)
        let answered = try store.answer(id: second.id, registration: account, expectedRevision: second.revision, pageID: purpose.id, pageRevision: purpose.revision, now: answerTime)
        check(answered.status == .answered && answered.answerPageID == purpose.id && answered.answerPageRevision == purpose.revision, "Answer records the exact saved human-page receipt")
        check(answered.revision != second.revision && answered.finished == answerTime && answered.updated == answerTime && answered.created == second.created, "Answer preserves creation and records completion")
        check(answered.question == second.question && answered.identity == second.identity, "Answer cannot rewrite the original question/project identity")
        check(!ContextProjectQuestionRules.actionable(answered, currentIdentity: identity(secondProject), candidate: true, hasPurpose: false), "Removing a purpose page cannot reopen an answered concern")
        check(store.questions(registration: account).isEmpty && store.questions(registration: account, includeFinished: true).contains(answered), "Answered clarification stays finished")
        let answeredReload = ContextProjectQuestionStore(container: db)
        check(answeredReload.questions(registration: account, includeFinished: true).contains(answered), "Answer receipt survives reopening")
        check(try answeredReload.offer(registration: account, projectID: secondProject, identity: identity(secondProject), question: wording) == nil, "Answered question is never regenerated")
        let questionBytes = try repository.read(ContextProjectQuestionStore.recordKey)!
        check(!String(decoding: questionBytes, as: UTF8.self).contains(purposeText), "Answer text is not duplicated into question state")
        check(ContextPageStore(container: db).page(id: purpose.id, registration: account) == purpose, "Question acknowledgement does not rewrite the saved answer page")
        check(try repository.read("paMemory") == nil && repository.read("lifeWorkspace") == nil, "Question storage never changes canonical memory/projects")

        let unavailable = ContextProjectQuestionStore(container: nil)
        check(!unavailable.isReadable && !unavailable.canSave && unavailable.error != nil, "Unavailable storage fails closed")
        reject("Missing storage offered a phantom question") { _ = try unavailable.offer(registration: account, projectID: project, identity: identity(project), question: wording) }
        reject("Missing storage accepted a dismissal") { _ = try unavailable.dismiss(id: first.id, registration: account, expectedRevision: first.revision) }
        reject("Missing storage accepted an answer") { _ = try unavailable.answer(id: first.id, registration: account, expectedRevision: first.revision, pageID: purpose.id, pageRevision: purpose.revision) }

        let undoDB = try container(), undoRepo = LocalRecordRepository(container: undoDB), undoStore = ContextProjectQuestionStore(container: undoDB)
        let undoOriginal = try undoStore.offer(registration: account, projectID: project, identity: identity(project), question: "  " + wording + " \n", now: clock)!
        check(undoOriginal.question == wording, "First offer trims surrounding whitespace and stores a question ending in a question mark")
        reject("Pending question accepted Undo dismissal") { _ = try undoStore.undoDismiss(id: undoOriginal.id, registration: account, expectedRevision: undoOriginal.revision) }
        let undoDismissed = try undoStore.dismiss(id: undoOriginal.id, registration: account, expectedRevision: undoOriginal.revision, now: clock.addingTimeInterval(10))
        let staleUndoOwner = ContextProjectQuestionStore(container: undoDB)
        let beforeUndo = try undoRepo.read(ContextProjectQuestionStore.recordKey)
        reject("Wrong account undid a dismissal") { _ = try undoStore.undoDismiss(id: undoOriginal.id, registration: other, expectedRevision: undoDismissed.revision) }
        reject("Stale version undid a dismissal") { _ = try undoStore.undoDismiss(id: undoOriginal.id, registration: account, expectedRevision: undoOriginal.revision) }
        check(try undoRepo.read(ContextProjectQuestionStore.recordKey) == beforeUndo, "Rejected Undo leaves exact dismissed state intact")
        let undone = try undoStore.undoDismiss(id: undoOriginal.id, registration: account, expectedRevision: undoDismissed.revision, now: clock.addingTimeInterval(20))
        check(undone.status == .pending && undone.finished == nil && undone.revision != undoDismissed.revision, "Explicit human Undo creates a new pending revision")
        check(undone.question == undoOriginal.question && undone.identity == undoOriginal.identity && undone.created == undoOriginal.created, "Undo retains the exact original wording, identity and creation time")
        check(try undoStore.offer(registration: account, projectID: project, identity: identity(project), question: "A changed model question?") == undone, "Reopened question still ignores model rewording")
        let afterUndoBytes = try undoRepo.read(ContextProjectQuestionStore.recordKey)
        reject("Stale second owner undid dismissal twice") { _ = try staleUndoOwner.undoDismiss(id: undoOriginal.id, registration: account, expectedRevision: undoDismissed.revision) }
        check(try undoRepo.read(ContextProjectQuestionStore.recordKey) == afterUndoBytes, "Undo retains whole-record CAS protection")
        let undoAnswered = try undoStore.answer(id: undone.id, registration: account, expectedRevision: undone.revision, pageID: purpose.id, pageRevision: purpose.revision)
        reject("Answer could be reverted through Undo dismissal") { _ = try undoStore.undoDismiss(id: undoAnswered.id, registration: account, expectedRevision: undoAnswered.revision) }

        let invalidDB = try container(), invalidRepo = LocalRecordRepository(container: invalidDB), invalidStore = ContextProjectQuestionStore(container: invalidDB)
        for badQuestion in ["", "  ", "This is a statement.", String(repeating: "a", count: 300) + "?", "Contains\0a nul?", "a" + String(repeating: "\u{0301}", count: 1_201) + "?"] {
            reject("Invalid question was offered") { _ = try invalidStore.offer(registration: account, projectID: project, identity: identity(project), question: badQuestion) }
        }
        for badIdentity in [ContextPageReference(kind: "workspace", key: project.uuidString, revision: "v1"), identity(secondProject), ContextPageReference(kind: "projectIdentity", key: "label instead of ID", revision: "v1"), identity(project, " ")] {
            reject("Invalid essential identity was accepted") { _ = try invalidStore.offer(registration: account, projectID: project, identity: badIdentity, question: wording) }
        }
        reject("Empty account accepted") { _ = try invalidStore.offer(registration: " ", projectID: project, identity: identity(project), question: wording) }
        reject("Invalid date accepted") { _ = try invalidStore.offer(registration: account, projectID: project, identity: identity(project), question: wording, now: Date(timeIntervalSinceReferenceDate: .infinity)) }
        check(try invalidRepo.read(ContextProjectQuestionStore.recordKey) == nil && invalidStore.questions(registration: account).isEmpty, "Invalid offers never create a record")

        let raceDB = try container(), raceRepo = LocalRecordRepository(container: raceDB)
        let raceA = ContextProjectQuestionStore(container: raceDB)
        let raceQuestion = try raceA.offer(registration: account, projectID: project, identity: identity(project), question: wording)!
        let raceB = ContextProjectQuestionStore(container: raceDB)
        let finishedRace = try raceA.dismiss(id: raceQuestion.id, registration: account, expectedRevision: raceQuestion.revision)
        let raceBytes = try raceRepo.read(ContextProjectQuestionStore.recordKey)
        reject("Stale second instance overwrote a dismissal") { _ = try raceB.answer(id: raceQuestion.id, registration: account, expectedRevision: raceQuestion.revision, pageID: purpose.id, pageRevision: purpose.revision) }
        reject("Stale no-op returned an already-dismissed question") { _ = try raceB.offer(registration: account, projectID: project, identity: identity(project), question: wording) }
        check(try raceRepo.read(ContextProjectQuestionStore.recordKey) == raceBytes, "Cross-instance conflict cannot change finished state")
        check(raceB.reload() && raceB.questions(registration: account, includeFinished: true) == [finishedRace], "Explicit reload adopts the finished state")
        check(try raceB.offer(registration: account, projectID: project, identity: identity(project), question: wording) == nil, "Reloaded dismissal remains suppressed")
        let newOwnerA = ContextProjectQuestionStore(container: raceDB), newOwnerB = ContextProjectQuestionStore(container: raceDB)
        _ = try newOwnerA.offer(registration: account, projectID: secondProject, identity: identity(secondProject), question: wording)
        let beforeLostCreate = try raceRepo.read(ContextProjectQuestionStore.recordKey)
        let thirdProject = UUID()
        reject("Stale sibling create lost a newer question") { _ = try newOwnerB.offer(registration: account, projectID: thirdProject, identity: identity(thirdProject), question: wording) }
        check(try raceRepo.read(ContextProjectQuestionStore.recordKey) == beforeLostCreate, "Whole-record CAS protects unrelated newer questions")

        for bad in [Data("not-json".utf8), Data("[]".utf8), Data("{\"schemaVersion\":2,\"future\":true}".utf8), Data("{\"schemaVersion\":null}".utf8), Data("{\"questions\":null}".utf8), try bytes(["questions": [object(JSONEncoder().encode(first)), object(JSONEncoder().encode(first))]])] {
            let corruptDB = try container(), corruptRepo = LocalRecordRepository(container: corruptDB)
            try corruptRepo.write([ContextProjectQuestionStore.recordKey: bad])
            let corrupt = ContextProjectQuestionStore(container: corruptDB)
            check(!corrupt.isReadable && !corrupt.canSave && corrupt.questions(registration: account, includeFinished: true).isEmpty, "Corrupt/unsupported questions fail closed")
            reject("Corrupt question record accepted an offer") { _ = try corrupt.offer(registration: account, projectID: project, identity: identity(project), question: wording) }
            check(try corruptRepo.read(ContextProjectQuestionStore.recordKey) == bad, "Corrupt/unsupported bytes are preserved exactly")
        }
        let legacyDB = try container(), legacyRepo = LocalRecordRepository(container: legacyDB)
        var legacyQuestion = try object(JSONEncoder().encode(first)); legacyQuestion.removeValue(forKey: "updated")
        let legacyBytes = try bytes(["questions": [legacyQuestion], "legacyOptional": ["keep": true]])
        try legacyRepo.write([ContextProjectQuestionStore.recordKey: legacyBytes])
        let legacy = ContextProjectQuestionStore(container: legacyDB)
        check(legacy.isReadable && legacy.questions(registration: account).first?.updated == first.created, "Legacy optional timestamp defaults to the original creation time")
        check(try legacyRepo.read(ContextProjectQuestionStore.recordKey) == legacyBytes, "Legacy inspection is read-only")
        _ = try legacy.dismiss(id: first.id, registration: account, expectedRevision: first.revision)
        check((try object(legacyRepo.read(ContextProjectQuestionStore.recordKey)!))["legacyOptional"] != nil, "Legacy additive metadata survives status changes")
        let emptyDB = try container(), emptyRepo = LocalRecordRepository(container: emptyDB)
        try emptyRepo.write([ContextProjectQuestionStore.recordKey: Data("{}".utf8)])
        let empty = ContextProjectQuestionStore(container: emptyDB)
        check(empty.isReadable && empty.questions(registration: account).isEmpty, "Empty legacy envelope is supported")
        _ = try empty.offer(registration: account, projectID: project, identity: identity(project), question: wording)

        let opaqueDB = try container(), opaqueRepo = LocalRecordRepository(container: opaqueDB)
        var knownRow = try object(JSONEncoder().encode(first))
        knownRow["futureQuestionField"] = "keep exact row"
        var referenceRow = knownRow["identity"] as! [String: Any]; referenceRow["futureReference"] = ["keep": true]; knownRow["identity"] = referenceRow
        let futureProject = UUID()
        let futureRow = ContextProjectQuestion(registration: account, projectID: futureProject, identity: identity(futureProject), question: wording, created: clock, status: .init(rawValue: "futureStatus"))
        let opaqueData = try bytes(["schemaVersion": 1, "questions": [knownRow, object(JSONEncoder().encode(futureRow))], "futureRoot": ["keep": 42]])
        try opaqueRepo.write([ContextProjectQuestionStore.recordKey: opaqueData])
        let opaque = ContextProjectQuestionStore(container: opaqueDB)
        check(opaque.isReadable && opaque.questions(registration: account, includeFinished: true) == [first], "Unknown status is preserved and excluded from all readable projections")
        check(try opaque.offer(registration: account, projectID: futureProject, identity: identity(futureProject), question: wording) == nil, "Unknown status cannot become a new pending question")
        reject("Unknown status was dismissed") { _ = try opaque.dismiss(id: futureRow.id, registration: account, expectedRevision: futureRow.revision) }
        _ = try opaque.dismiss(id: first.id, registration: account, expectedRevision: first.revision)
        let afterOpaque = try object(opaqueRepo.read(ContextProjectQuestionStore.recordKey)!)
        let afterRows = afterOpaque["questions"] as! [[String: Any]]
        check(afterOpaque["futureRoot"] != nil && afterRows.count == 2 && afterRows[0]["futureQuestionField"] != nil, "Unknown root/sibling/current-row fields survive ordinary updates")
        check((afterRows[0]["identity"] as! [String: Any])["futureReference"] != nil && afterRows[1]["status"] as? String == "futureStatus", "Unknown reference metadata and future status are retained")
        let opaqueReload = ContextProjectQuestionStore(container: opaqueDB)
        check(opaqueReload.questions(registration: account).isEmpty && opaqueReload.questions(registration: account, includeFinished: true).count == 1, "Unknown status stays excluded after save/reopen")
        let noPageDB = try container(), noPageRepo = LocalRecordRepository(container: noPageDB), receipts = ContextProjectQuestionStore(container: noPageDB)
        let receiptQuestion = try receipts.offer(registration: account, projectID: project, identity: identity(project), question: wording)!
        _ = try receipts.answer(id: receiptQuestion.id, registration: account, expectedRevision: receiptQuestion.revision, pageID: purpose.id, pageRevision: purpose.revision)
        check(try noPageRepo.read(ContextPageStore.recordKey) == nil, "Recording a caller-verified receipt cannot create or fake a page in storage")
        print("PASS: \(checks) project-question checks; fictional in-memory storage only, no model/source/app operations")
    }
}
