import Foundation
import Observation
import SwiftData

/// One additive record, separate from paMemory. The byte CAS also protects two store instances.
/// Reading these local pages does not validate source permission; consumers must do that before use.
@MainActor @Observable final class ContextPageStore {
    static let recordKey = "contextPages"
    private(set) var error: String?
    private(set) var isReadable = false
    private(set) var revision = UUID()
    var canSave: Bool { isReadable && repository != nil }
    @ObservationIgnored private let repository: LocalRecordRepository?
    @ObservationIgnored private var loadedBytes: Data?
    private var state = ContextPageEnvelope()

    init(container: ModelContainer?) {
        repository = container.map { LocalRecordRepository(container: $0) }
        reload()
    }

    /// Explicitly adopt another owner's latest data; a failed CAS never silently reloads an editor.
    @discardableResult func reload() -> Bool {
        do {
            guard let repository else { throw ContextPageFailure.unavailable }
            let bytes = try repository.read(Self.recordKey)
            let next = try bytes.map { try JSONDecoder().decode(ContextPageEnvelope.self, from: $0) } ?? ContextPageEnvelope()
            try Self.validate(next)
            state = next; loadedBytes = bytes; isReadable = true; error = nil; revision = UUID()
            return true
        } catch {
            state = ContextPageEnvelope(); isReadable = false
            self.error = Self.message(error)
            return false
        }
    }

    /// Complete saved list. Bounds apply only to explicit provider/directory projections.
    func pages(registration: String) -> [ContextPage] {
        guard isReadable else { return [] }
        return state.pages.filter { $0.registration == registration && $0.isSupported }.sorted { $0.id < $1.id }
    }
    func page(id: String, registration: String) -> ContextPage? {
        pages(registration: registration).first { $0.id == id }
    }
    /// Inspect identity availability without returning unsupported page content.
    func identityStatus(id: String, registration: String) -> ContextPageIdentityStatus {
        guard isReadable else { return .unavailable }
        guard let page = state.pages.first(where: { $0.id == id && $0.registration == registration }) else { return .missing }
        return page.isSupported ? .available : .preserved
    }
    func history(id: String, registration: String) -> [ContextPageVersion] {
        guard let current = page(id: id, registration: registration) else { return [] }
        return state.versions?.filter { $0.page.id == id && $0.page.registration == registration } ?? [.init(page: current)]
    }
    func checkpoint(registration: String) -> ContextPageCheckpoint? {
        guard isReadable else { return nil }
        return state.checkpoints.first { $0.registration == registration }
    }

    func changes(registration: String, currentReferences: [ContextPageReference]) throws -> ContextPageChanges {
        guard isReadable else { throw ContextPageFailure.unavailable }
        try Self.validateRegistration(registration)
        let current = try Self.canonicalReferences(currentReferences)
        let prior = try Self.canonicalReferences(checkpoint(registration: registration)?.references ?? [])
        let old = Dictionary(uniqueKeysWithValues: prior.map { ($0.id, $0) })
        let new = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        return ContextPageChanges(
            added: current.filter { old[$0.id] == nil },
            changed: current.compactMap { value in
                guard let previous = old[value.id], previous.revision != value.revision else { return nil }
                return .init(previous: previous, current: value)
            },
            removed: prior.filter { new[$0.id] == nil },
            unchangedCount: current.filter { old[$0.id] == $0 }.count)
    }

    @discardableResult func save(_ candidate: ContextPage, expectedRevision: UUID?, now: Date = .now) throws -> ContextPage {
        try saveBatch([candidate], expectedRevisions: expectedRevision.map { [candidate.id: $0] } ?? [:], now: now)[0]
    }

    /// Missing expected page/checkpoint revisions mean create-only. The checkpoint is acknowledged
    /// only if all page versions commit. Empty page batches may explicitly acknowledge a quiet cycle.
    @discardableResult func saveBatch(_ candidates: [ContextPage], expectedRevisions: [String: UUID] = [:],
                                     checkpoint candidateCheckpoint: ContextPageCheckpoint? = nil,
                                     expectedCheckpointRevision: UUID? = nil, now: Date = .now) throws -> [ContextPage] {
        do {
            guard canSave else { throw ContextPageFailure.unavailable }
            guard now.timeIntervalSinceReferenceDate.isFinite else { throw ContextPageFailure.invalid("date") }
            let ids = Set(candidates.map(\.id))
            guard ids.count == candidates.count, Set(expectedRevisions.keys).isSubset(of: ids),
                  candidateCheckpoint != nil || expectedCheckpointRevision == nil else { throw ContextPageFailure.invalid("batch") }
            if let candidateCheckpoint {
                guard candidates.allSatisfy({ $0.registration == candidateCheckpoint.registration }) else { throw ContextPageFailure.invalid("checkpoint account") }
            }
            guard !candidates.isEmpty || candidateCheckpoint != nil else { return [] }
            var next = state
            var versions = next.versions ?? next.pages.map { ContextPageVersion(page: $0) }
            var saved: [ContextPage] = []
            for candidate in candidates {
                try Self.validatePage(candidate)
                guard candidate.isSupported else { throw ContextPageFailure.unsupportedPage }
                let current = next.pages.first { $0.id == candidate.id }
                guard current?.revision == expectedRevisions[candidate.id] else { throw ContextPageFailure.stalePage }
                if let current, !current.isSupported { throw ContextPageFailure.unsupportedPage }
                var value = candidate
                value.revision = UUID(); value.created = current?.created ?? now; value.updated = now
                value.references = try Self.canonicalReferences(candidate.references)
                if let processed = candidate.processedReferences { value.processedReferences = try Self.canonicalReferences(processed) }
                versions.append(.init(page: value, parentRevision: current?.revision))
                if let index = next.pages.firstIndex(where: { $0.id == value.id }) { next.pages[index] = value }
                else { next.pages.append(value) }
                saved.append(value)
            }
            next.versions = versions
            if var value = candidateCheckpoint {
                try Self.validateCheckpoint(value)
                let current = next.checkpoints.first { $0.registration == value.registration }
                guard current?.revision == expectedCheckpointRevision else { throw ContextPageFailure.staleCheckpoint }
                value.revision = UUID(); value.updated = now
                value.references = try Self.canonicalReferences(value.references)
                if let index = next.checkpoints.firstIndex(where: { $0.id == value.id }) { next.checkpoints[index] = value }
                else { next.checkpoints.append(value) }
            }
            try commit(next, now: now)
            return saved
        } catch { self.error = Self.message(error); throw error }
    }

    @discardableResult func saveCheckpoint(_ candidate: ContextPageCheckpoint, expectedRevision: UUID?, now: Date = .now) throws -> ContextPageCheckpoint {
        _ = try saveBatch([], checkpoint: candidate, expectedCheckpointRevision: expectedRevision, now: now)
        return checkpoint(registration: candidate.registration)!
    }

    /// Restoring text does not restore permission or a canonical fact, acknowledge changes, or replay actions.
    @discardableResult func restore(id: String, registration: String, revision targetRevision: UUID,
                                    expectedRevision: UUID, now: Date = .now) throws -> ContextPage {
        do {
            guard canSave else { throw ContextPageFailure.unavailable }
            guard let current = page(id: id, registration: registration), current.revision == expectedRevision else { throw ContextPageFailure.stalePage }
            guard let target = history(id: id, registration: registration).first(where: { $0.id == targetRevision }) else { throw ContextPageFailure.missingVersion }
            guard target.page.isSupported else { throw ContextPageFailure.unsupportedPage }
            var next = state
            var value = target.page
            value.revision = UUID(); value.created = current.created; value.updated = now
            try Self.validatePage(value)
            var versions = next.versions ?? next.pages.map { ContextPageVersion(page: $0) }
            versions.append(.init(page: value, parentRevision: current.revision, restoredFrom: targetRevision))
            next.versions = versions
            next.pages[next.pages.firstIndex(where: { $0.id == id })!] = value
            try commit(next, now: now)
            return value
        } catch { self.error = Self.message(error); throw error }
    }

    /// Explicit human Forget removes this page and its entire lineage. Generated projections must
    /// instead follow current canonical facts/permissions; deleting a projection cannot forget its sources.
    func forget(id: String, registration: String, expectedRevision: UUID, now: Date = .now) throws {
        do {
            guard canSave else { throw ContextPageFailure.unavailable }
            guard let current = page(id: id, registration: registration), current.revision == expectedRevision else { throw ContextPageFailure.stalePage }
            guard current.owner == .human else { throw ContextPageFailure.unsupportedPage }
            guard now.timeIntervalSinceReferenceDate.isFinite else { throw ContextPageFailure.invalid("date") }
            var next = state
            next.pages.removeAll { $0.id == current.id && $0.registration == registration }
            next.versions = next.versions?.filter { $0.page.id != current.id || $0.page.registration != registration }
            try commit(next, now: now)
        } catch { self.error = Self.message(error); throw error }
    }

    /// An omitted count is explicit; no saved page is pruned to fit this provider index.
    /// Eligibility must check each page's exact current references for this consumer's purpose.
    func directory(registration: String, maximumBytes: Int = ContextPageLimits.maximumDirectoryBytes,
                   isEligible: (ContextPage) -> Bool) throws -> ContextPageDirectory {
        guard isReadable else { throw ContextPageFailure.unavailable }
        let eligible = pages(registration: registration).filter(isEligible)
        var entries: [ContextPageDirectoryEntry] = []
        guard maximumBytes >= 0, try ContextPageDirectory(entries: [], omittedCount: eligible.count).encoded().count <= maximumBytes else {
            throw ContextPageFailure.payloadTooLarge
        }
        for page in eligible {
            let candidate = entries + [.init(page)]
            let output = ContextPageDirectory(entries: candidate, omittedCount: eligible.count - candidate.count)
            if try output.encoded().count <= maximumBytes { entries = candidate }
        }
        return ContextPageDirectory(entries: entries, omittedCount: eligible.count - entries.count)
    }

    private func commit(_ next: ContextPageEnvelope, now: Date) throws {
        guard let repository else { throw ContextPageFailure.unavailable }
        try Self.validate(next)
        let bytes = try LocalRecordCoding.preservingUnknown(next, original: loadedBytes)
        try repository.write([Self.recordKey: bytes], now: now, expected: [Self.recordKey: LocalRecordVersion(loadedBytes)])
        state = next; loadedBytes = bytes; revision = UUID(); error = nil
    }

    private static func validate(_ envelope: ContextPageEnvelope) throws {
        guard envelope.schemaVersion == 1 else { throw ContextPageFailure.unsupportedSchema(envelope.schemaVersion) }
        guard Set(envelope.pages.map(\.id)).count == envelope.pages.count,
              Set(envelope.checkpoints.map(\.id)).count == envelope.checkpoints.count else { throw ContextPageFailure.corrupt }
        for page in envelope.pages { try validatePage(page) }
        for checkpoint in envelope.checkpoints { try validateCheckpoint(checkpoint) }
        guard let versions = envelope.versions else { return } // Legacy page-only records gain their initial history on first save.
        guard Set(versions.map(\.id)).count == versions.count else { throw ContextPageFailure.corrupt }
        var prior: [UUID: ContextPageVersion] = [:]
        var latest: [String: ContextPageVersion] = [:]
        let pages = Dictionary(uniqueKeysWithValues: envelope.pages.map { ($0.id, $0) })
        for version in versions {
            try validatePage(version.page)
            guard version.id == version.page.revision, pages[version.page.id] != nil else { throw ContextPageFailure.corrupt }
            if let parent = version.parentRevision {
                guard prior[parent]?.page.id == version.page.id, latest[version.page.id]?.id == parent else { throw ContextPageFailure.corrupt }
            } else if latest[version.page.id] != nil { throw ContextPageFailure.corrupt }
            if let restored = version.restoredFrom, prior[restored]?.page.id != version.page.id { throw ContextPageFailure.corrupt }
            prior[version.id] = version; latest[version.page.id] = version
        }
        for page in envelope.pages { guard latest[page.id]?.page == page else { throw ContextPageFailure.corrupt } }
    }
    private static func validatePage(_ page: ContextPage) throws {
        try validateRegistration(page.registration)
        guard validText(page.kind.rawValue, maximumBytes: 128), validText(page.owner.rawValue, maximumBytes: 128),
              validText(page.key, maximumBytes: 2_000), page.id == ContextPage.stableID(registration: page.registration, kind: page.kind, key: page.key),
              validText(page.title, maximumBytes: ContextPageLimits.maximumTitleBytes),
              page.synopsis.utf8.count <= ContextPageLimits.maximumSynopsisBytes,
              page.markdown.utf8.count <= ContextPageLimits.maximumMarkdownBytes,
              page.references.count <= ContextPageLimits.maximumPageReferences,
              page.created.timeIntervalSinceReferenceDate.isFinite, page.updated.timeIntervalSinceReferenceDate.isFinite else {
            throw ContextPageFailure.invalid("page")
        }
        _ = try canonicalReferences(page.references)
        if let processed = page.processedReferences {
            guard processed.count <= 4096 else { throw ContextPageFailure.invalid("page progress") }
            _ = try canonicalReferences(processed)
        }
        if let quotes = page.evidenceQuotes {
            let ids = Set(page.references.map(\.id))
            guard quotes.count <= 32, quotes.allSatisfy({ ids.contains($0.referenceID) && (1...500).contains($0.quote.count) }) else { throw ContextPageFailure.invalid("page evidence") }
        }
    }
    private static func validateCheckpoint(_ value: ContextPageCheckpoint) throws {
        try validateRegistration(value.registration)
        guard value.id == ContextPageCheckpoint.stableID(registration: value.registration), value.updated.timeIntervalSinceReferenceDate.isFinite else {
            throw ContextPageFailure.invalid("checkpoint")
        }
        _ = try canonicalReferences(value.references)
    }
    private static func validateRegistration(_ registration: String) throws {
        guard validText(registration, maximumBytes: 2_000) else { throw ContextPageFailure.invalid("registration") }
    }
    private static func validText(_ value: String, maximumBytes: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= maximumBytes && !value.contains("\0")
    }
    private static func canonicalReferences(_ references: [ContextPageReference]) throws -> [ContextPageReference] {
        guard Set(references.map(\.id)).count == references.count else { throw ContextPageFailure.invalid("duplicate reference") }
        for value in references {
            guard validText(value.kind, maximumBytes: 128), validText(value.key, maximumBytes: 4_000),
                  validText(value.revision, maximumBytes: 4_000), value.id == ContextPageReference.stableID(kind: value.kind, key: value.key) else {
                throw ContextPageFailure.invalid("reference")
            }
        }
        return references.sorted { $0.id < $1.id }
    }
    private static func message(_ error: Error) -> String {
        (error as? ContextPageFailure)?.errorDescription ?? (error as? LocalRecordFailure)?.errorDescription ?? ContextPageFailure.corrupt.errorDescription!
    }
}

private struct ContextPageEnvelope: Codable {
    var schemaVersion = 1
    var pages: [ContextPage] = []
    var versions: [ContextPageVersion]? = nil
    var checkpoints: [ContextPageCheckpoint] = []
    private enum CodingKeys: String, CodingKey { case schemaVersion, pages, versions, checkpoints }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = values.contains(.schemaVersion) ? try values.decode(Int.self, forKey: .schemaVersion) : 1
        pages = values.contains(.pages) ? try values.decode([ContextPage].self, forKey: .pages) : []
        versions = try values.decodeIfPresent([ContextPageVersion].self, forKey: .versions)
        checkpoints = values.contains(.checkpoints) ? try values.decode([ContextPageCheckpoint].self, forKey: .checkpoints) : []
    }
}
