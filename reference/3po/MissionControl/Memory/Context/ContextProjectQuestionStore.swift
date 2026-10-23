import Foundation
import Observation
import SwiftData

/// Local clarification state, separate from pages/facts/projects and protected by whole-record CAS.
@MainActor @Observable final class ContextProjectQuestionStore {
    static let recordKey = "contextProjectQuestions"
    private(set) var isReadable = false
    private(set) var error: String?
    private(set) var revision = UUID()
    var canSave: Bool { isReadable && repository != nil }
    @ObservationIgnored private let repository: LocalRecordRepository?
    @ObservationIgnored private var loadedBytes: Data?
    private var state = ContextProjectQuestionEnvelope()

    init(container: ModelContainer?) {
        repository = container.map { LocalRecordRepository(container: $0) }
        reload()
    }
    @discardableResult func reload() -> Bool {
        do {
            guard let repository else { throw ContextProjectQuestionFailure.unavailable }
            let bytes = try repository.read(Self.recordKey)
            let next = try bytes.map { try JSONDecoder().decode(ContextProjectQuestionEnvelope.self, from: $0) } ?? ContextProjectQuestionEnvelope()
            try Self.validate(next)
            state = next; loadedBytes = bytes; isReadable = true; error = nil; revision = UUID()
            return true
        } catch {
            state = ContextProjectQuestionEnvelope(); isReadable = false; self.error = Self.message(error)
            return false
        }
    }
    func questions(registration: String, includeFinished: Bool = false) -> [ContextProjectQuestion] {
        guard isReadable else { return [] }
        return state.questions.filter { $0.registration == registration && $0.status.isSupported && (includeFinished || $0.status == .pending) }
            .sorted { $0.created == $1.created ? $0.id < $1.id : $0.created < $1.created }
    }

    /// A repeat offer returns the original pending wording. Finished/changed-scope questions stay
    /// retired; neither changed model wording nor a project revision silently creates another.
    @discardableResult func offer(registration: String, projectID: UUID, identity: ContextPageReference,
                                 question: String, now: Date = .now) throws -> ContextProjectQuestion? {
        do {
            guard canSave else { throw ContextProjectQuestionFailure.unavailable }
            let value = ContextProjectQuestion(registration: registration, projectID: projectID, identity: identity, question: question.trimmingCharacters(in: .whitespacesAndNewlines), created: now)
            try Self.validate(value)
            if let current = state.questions.first(where: { $0.id == value.id }) {
                // A stale no-op must not offer an already-dismissed question from another owner.
                try requireUnchangedStorage()
                error = nil
                guard current.identity == identity, current.status == .pending else { return nil }
                return current
            }
            var next = state; next.questions.append(value)
            try commit(next, now: now)
            return value
        } catch { self.error = Self.message(error); throw error }
    }

    @discardableResult func dismiss(id: String, registration: String, expectedRevision: UUID, now: Date = .now) throws -> ContextProjectQuestion {
        try finish(id: id, registration: registration, expectedRevision: expectedRevision, status: .dismissed, pageID: nil, pageRevision: nil, now: now)
    }

    /// Explicit human Undo only. Ordinary offers never undo a dismissal or reset a finished state.
    @discardableResult func undoDismiss(id: String, registration: String, expectedRevision: UUID, now: Date = .now) throws -> ContextProjectQuestion {
        do {
            guard canSave else { throw ContextProjectQuestionFailure.unavailable }
            guard let index = state.questions.firstIndex(where: { $0.id == id && $0.registration == registration }),
                  state.questions[index].revision == expectedRevision else { throw ContextProjectQuestionFailure.stale }
            let current = state.questions[index]
            guard current.status.isSupported else { throw ContextProjectQuestionFailure.unsupportedStatus }
            guard current.status == .dismissed else { throw ContextProjectQuestionFailure.notDismissed }
            var value = current
            value.status = .pending; value.revision = UUID(); value.updated = now; value.finished = nil
            try Self.validate(value)
            var next = state; next.questions[index] = value
            try commit(next, now: now)
            return value
        } catch { self.error = Self.message(error); throw error }
    }

    /// The caller must have saved and verified the human-owned purpose page first. This records its
    /// exact receipt only; it neither creates a page nor claims to have verified that page's existence.
    @discardableResult func answer(id: String, registration: String, expectedRevision: UUID,
                                  pageID: String, pageRevision: UUID, now: Date = .now) throws -> ContextProjectQuestion {
        try finish(id: id, registration: registration, expectedRevision: expectedRevision, status: .answered, pageID: pageID, pageRevision: pageRevision, now: now)
    }

    private func finish(id: String, registration: String, expectedRevision: UUID, status: ContextProjectQuestion.Status,
                        pageID: String?, pageRevision: UUID?, now: Date) throws -> ContextProjectQuestion {
        do {
            guard canSave else { throw ContextProjectQuestionFailure.unavailable }
            guard let index = state.questions.firstIndex(where: { $0.id == id && $0.registration == registration }),
                  state.questions[index].revision == expectedRevision else { throw ContextProjectQuestionFailure.stale }
            let current = state.questions[index]
            guard current.status.isSupported else { throw ContextProjectQuestionFailure.unsupportedStatus }
            guard current.status == .pending else { throw ContextProjectQuestionFailure.finished }
            var value = current
            value.status = status; value.revision = UUID(); value.updated = now; value.finished = now
            value.answerPageID = pageID; value.answerPageRevision = pageRevision
            try Self.validate(value)
            var next = state; next.questions[index] = value
            try commit(next, now: now)
            return value
        } catch { self.error = Self.message(error); throw error }
    }
    private func requireUnchangedStorage() throws {
        guard let repository else { throw ContextProjectQuestionFailure.unavailable }
        guard try LocalRecordVersion(repository.read(Self.recordKey)) == LocalRecordVersion(loadedBytes) else { throw LocalRecordFailure.changed }
    }
    private func commit(_ next: ContextProjectQuestionEnvelope, now: Date) throws {
        guard let repository else { throw ContextProjectQuestionFailure.unavailable }
        try Self.validate(next)
        let bytes = try LocalRecordCoding.preservingUnknown(next, original: loadedBytes)
        try repository.write([Self.recordKey: bytes], now: now, expected: [Self.recordKey: LocalRecordVersion(loadedBytes)])
        state = next; loadedBytes = bytes; error = nil; revision = UUID()
    }
    private static func validate(_ envelope: ContextProjectQuestionEnvelope) throws {
        guard envelope.schemaVersion == 1 else { throw ContextProjectQuestionFailure.unsupportedSchema(envelope.schemaVersion) }
        guard Set(envelope.questions.map(\.id)).count == envelope.questions.count else { throw ContextProjectQuestionFailure.corrupt }
        for question in envelope.questions { try validate(question) }
    }
    private static func validate(_ value: ContextProjectQuestion) throws {
        let text = value.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validText(value.registration, maximumBytes: 2_000),
              value.id == ContextProjectQuestion.stableID(registration: value.registration, projectID: value.projectID),
              value.identity.kind == "projectIdentity", UUID(uuidString: value.identity.key) == value.projectID,
              value.identity.id == ContextPageReference.stableID(kind: value.identity.kind, key: value.identity.key),
              validText(value.identity.revision, maximumBytes: 4_000),
              !text.isEmpty, value.question.last == "?", value.question.count <= ContextProjectQuestion.maximumQuestionCharacters,
              value.question.utf8.count <= ContextProjectQuestion.maximumQuestionBytes, !value.question.contains("\0"),
              validText(value.status.rawValue, maximumBytes: 128), value.created.timeIntervalSinceReferenceDate.isFinite,
              value.updated.timeIntervalSinceReferenceDate.isFinite, value.finished?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw ContextProjectQuestionFailure.invalid
        }
        if value.status == .pending {
            guard value.answerPageID == nil, value.answerPageRevision == nil, value.finished == nil else { throw ContextProjectQuestionFailure.invalid }
        } else if value.status == .dismissed {
            guard value.answerPageID == nil, value.answerPageRevision == nil else { throw ContextProjectQuestionFailure.invalid }
        } else if value.status == .answered {
            guard let pageID = value.answerPageID, validText(pageID, maximumBytes: 6_000), value.answerPageRevision != nil else { throw ContextProjectQuestionFailure.invalid }
        }
        // Unknown statuses are retained, excluded from UI/updates and never interpreted as pending.
    }
    private static func validText(_ value: String, maximumBytes: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximumBytes && !value.contains("\0")
    }
    private static func message(_ error: Error) -> String {
        (error as? ContextProjectQuestionFailure)?.errorDescription ?? (error as? LocalRecordFailure)?.errorDescription ?? ContextProjectQuestionFailure.corrupt.errorDescription!
    }
}

private struct ContextProjectQuestionEnvelope: Codable {
    var schemaVersion = 1
    var questions: [ContextProjectQuestion] = []
    private enum CodingKeys: String, CodingKey { case schemaVersion, questions }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = values.contains(.schemaVersion) ? try values.decode(Int.self, forKey: .schemaVersion) : 1
        questions = values.contains(.questions) ? try values.decode([ContextProjectQuestion].self, forKey: .questions) : []
    }
}
