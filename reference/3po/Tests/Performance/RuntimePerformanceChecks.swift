import Foundation
import SwiftData

/// Actual service-path measurements with fictional storage. Cold means empty
/// derived/service caches; construction, decoding and initial migration are excluded.
@main struct RuntimePerformanceChecks {
    struct Observation: Equatable { var count: Int; var bytes: Int; var encodedTurns = 0; var writtenRecords = 0 }
    struct Measurement: Codable {
        var operation: String; var workload: Int
        var coldMedianMilliseconds: Double; var coldP95Milliseconds: Double
        var warmMedianMilliseconds: Double; var warmP95Milliseconds: Double
        var coldSamples: Int; var warmSamples: Int
        var outputCount: Int; var outputBytes: Int; var encodedTurns: Int; var writtenRecords: Int
        var wholeHistoryBytes: Int?
    }
    @MainActor static func main() throws {
        let priorDefaults = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(["paMemoryEnabled": true, "paMemoryLearningEnabled": true], forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(priorDefaults, forName: UserDefaults.argumentDomain) }
        let coldSamples = 5, warmSamples = 15
        var measurements: [Measurement] = [], checks = 0
        func check(_ condition: Bool, _ label: String) { checks += 1; precondition(condition, label) }
        func measure(_ operation: String, workload: Int, wholeHistoryBytes: Int? = nil, cold: () throws -> (() throws -> Observation), warm: () throws -> (() throws -> Observation)) throws {
            func sample(_ run: () throws -> Observation) throws -> (Double, Observation) {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = try run()
                return (Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000, result)
            }
            var first: Observation?, coldTimes: [Double] = [], warmTimes: [Double] = []
            for _ in 0..<coldSamples {
                let result = try autoreleasepool { try sample(cold()) }
                if let first { check(result.1 == first, "Stable cold workload output") } else { first = result.1 }
                coldTimes.append(result.0)
            }
            let runWarm = try warm()
            check(try runWarm() == first!, "Warm priming matches the cold output")
            for _ in 0..<warmSamples {
                let result = try sample(runWarm)
                check(result.1 == first!, "Stable warm workload output")
                warmTimes.append(result.0)
            }
            coldTimes.sort(); warmTimes.sort()
            func p95(_ values: [Double]) -> Double { values[Int(ceil(Double(values.count) * 0.95)) - 1] }
            let value = first!
            let report = Measurement(operation: operation, workload: workload, coldMedianMilliseconds: coldTimes[coldTimes.count / 2], coldP95Milliseconds: p95(coldTimes), warmMedianMilliseconds: warmTimes[warmTimes.count / 2], warmP95Milliseconds: p95(warmTimes), coldSamples: coldSamples, warmSamples: warmSamples, outputCount: value.count, outputBytes: value.bytes, encodedTurns: value.encodedTurns, writtenRecords: value.writtenRecords, wholeHistoryBytes: wholeHistoryBytes)
            measurements.append(report)
            print(String(format: "RUNTIME %@ n=%d cold median=%.3f ms p95=%.3f ms warm median=%.3f ms p95=%.3f ms count=%d bytes=%d encodedTurns=%d writtenRecords=%d", operation, workload, report.coldMedianMilliseconds, report.coldP95Milliseconds, report.warmMedianMilliseconds, report.warmP95Milliseconds, value.count, value.bytes, value.encodedTurns, value.writtenRecords))
        }
        func uuid(_ index: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))! }
        let now = Date.now, query = "Orion calibration", registration = "fictional-runtime"
        let directory = URL(fileURLWithPath: "/tmp/3po-runtime-performance-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for count in [100, 1_000, 10_000] {
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("memory-\(count).store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: CachedDashboard.self, configurations: configuration)
            let facts = (0..<count).map { index -> PAMemory in
                let project = index < 8 ? "Orion" : "Fictional topic \((index - 8) % 23)"
                let text = index < 8 ? "I develop Orion calibration experiment \(index)." : "I work on \(project), with unrelated observation \(index)."
                return .init(id: uuid(index + 1), registration: registration, text: text, kind: .context, provenance: "Fictional workload", created: now, reviewed: now, evidence: text, certainty: .stated, durability: .stable, connections: [.init(subject: "You", relation: "develops", object: project, evidence: text)], organisation: .init(areas: [.projects], connections: [.init(connection: "0", subjectKind: .person, objectKind: .project, subjectIsSelf: true, objectIsSelf: false)]))
            }
            let quote = "The Orion calibration meeting moved to Friday."
            let source = PAMemory(id: uuid(50_000), registration: registration, text: quote, kind: .commitment, explicit: false, provenance: "Fictional source", created: now, reviewed: now, evidence: quote, certainty: .inferred, durability: .situational, source: .init(identity: .init(kind: .mail, accountID: "fictional-mail", containerID: "Inbox", itemID: "message"), revision: "v1", label: "Fictional organiser", quote: quote, observed: now, sourceDate: now), sourceState: .changed)
            var foreign = facts[0]; foreign.id = uuid(50_001); foreign.registration = "another-account"
            var scoped = facts[0]; scoped.id = uuid(50_002); scoped.conversationID = uuid(50_003)
            try LocalRecordRepository(container: container).save(MemoryEnvelope(records: facts + [source, foreign, scoped]), key: "paMemory")
            var items = (0..<24).map { index -> LifeItem in
                let label = index == 0 ? "Orion" : "Fictional topic \(index - 1)"
                return .init(id: uuid(20_000 + index), registration: registration, kind: .space, title: label, notes: "Fictional folder", areas: [.projects], created: now, updated: now, notebookEntityID: "shared:project:" + LifeNotebook.key(label))
            }
            let links = items.enumerated().map { index, item -> LifeItemLink in
                .init(id: uuid(30_000 + index), registration: registration, from: item.id, relation: .identifies, target: .init(kind: .memory, id: facts[index == 0 ? 0 : index + 7].id.uuidString, containerID: item.notebookEntityID), created: now)
            }
            var permission = false, sourceRevision = "v1", workspaceRevision = UUID()
            func makeStore() -> PAMemoryStore {
                let store = PAMemoryStore(container: container)
                store.sourcePermissionProjection = { permission && sourceRevision == "v1" ? [source.id] : [] }
                store.notebookProjection = { notebook, _, _, _ in notebook.integrating(items, links: links) }
                store.notebookProjectionRevision = { workspaceRevision }
                return store
            }
            func selected(_ store: PAMemoryStore, query: String = query, date: Date = now) -> MemorySelection {
                store.selection(registration, query: query, focus: [.projects], now: date)
            }
            func selectionObservation(_ selection: MemorySelection) throws -> Observation {
                let bytes = try JSONSerialization.data(withJSONObject: selection.records, options: [.sortedKeys]).count
                check(bytes <= 20_000 && selection.records.count <= 40, "Memory selection bounds")
                return .init(count: selection.records.count, bytes: bytes)
            }
            func notebookObservation(_ notebook: LifeNotebook, ids: Set<UUID>, query: String = query) -> Observation {
                let context = notebook.context(query: query, selectedMemoryIDs: ids), captured = PAContextCapture.notebookIDs(context)
                check(context.utf8.count <= 8_000 && Set(captured.memories).isSubset(of: ids), "Notebook shares selected IDs and bounds")
                return .init(count: captured.memories.count, bytes: context.utf8.count)
            }
            func pipeline(_ store: PAMemoryStore) throws -> Observation {
                let selection = selected(store), a = try selectionObservation(selection)
                let ids = Set(selection.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
                let b = notebookObservation(store.notebook(registration, now: now), ids: ids)
                return .init(count: a.count, bytes: a.bytes + b.bytes)
            }
            let baseline = makeStore(), initial = selected(baseline)
            let expected = Set(facts.prefix(8).map(\.id))
            check(Set(initial.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) }) == expected, "Only relevant in-account, in-scope human facts enter the baseline")
            try measure("cached_memory_notebook", workload: count, cold: {
                let store = makeStore()
                return { notebookObservation(store.notebook(registration, now: now), ids: expected) }
            }, warm: {
                let store = makeStore()
                return { notebookObservation(store.notebook(registration, now: now), ids: expected) }
            })
            try measure("cached_memory_selection", workload: count, cold: {
                let store = makeStore(); return { try selectionObservation(selected(store)) }
            }, warm: {
                let store = makeStore(); return { try selectionObservation(selected(store)) }
            })
            try measure("cached_memory_pipeline", workload: count, cold: {
                let store = makeStore(); return { try pipeline(store) }
            }, warm: {
                let store = makeStore(); return { try pipeline(store) }
            })
            func equivalent(_ store: PAMemoryStore, query: String = query, date: Date = now) -> MemorySelection {
                let candidates = store.permittedRecords
                let notebook = LifeNotebook.build(candidates, registration: registration, now: date).integrating(items, links: links)
                let reference = MemoryRetrieval.select(candidates, registration: registration, query: query, now: date, focus: [.projects], notebook: notebook)
                let cached = selected(store, query: query, date: date)
                check(reference.records == cached.records && reference.reasons == cached.reasons && reference.eligibleCount == cached.eligibleCount, "Cached and uncached production selection agree")
                let ids = Set(cached.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
                check(notebook.context(query: query, selectedMemoryIDs: ids) == store.notebook(registration, now: date).context(query: query, selectedMemoryIDs: ids), "Cached and uncached canonical notebook contexts agree")
                return cached
            }
            _ = equivalent(baseline)
            let built = baseline.notebookBuildCount, originalRevision = baseline.revision
            _ = equivalent(baseline)
            check(baseline.notebookBuildCount == built, "Unchanged selection and notebook reuse one prepared projection")
            permission = true
            let permitted = equivalent(baseline)
            check(baseline.revision == originalRevision && baseline.notebookBuildCount > built && permitted.records.contains { $0["id"] == source.id.uuidString }, "Permission change invalidates without a memory edit")
            let permittedBuild = baseline.notebookBuildCount
            sourceRevision = "v2"
            check(!equivalent(baseline).records.contains { $0["id"] == source.id.uuidString } && baseline.notebookBuildCount > permittedBuild, "Changed source version withdraws cached support")
            sourceRevision = "v1"
            _ = equivalent(baseline)
            let beforeExpiry = baseline.notebookBuildCount
            check(!equivalent(baseline, date: now.addingTimeInterval(91 * 86400)).records.contains { $0["id"] == source.id.uuidString } && baseline.notebookBuildCount > beforeExpiry, "Temporal expiry invalidates cached usability")
            permission = false
            _ = equivalent(baseline)
            let beforeWorkspace = baseline.notebookBuildCount
            items[0].title = "Orion Gallery"; workspaceRevision = UUID()
            _ = equivalent(baseline)
            check(baseline.notebookBuildCount > beforeWorkspace, "Workspace revision invalidates canonical projection")
            var revised = facts[0]; revised.text = "Borealis has replaced my previous experiment."; revised.evidence = revised.text
            revised.connections = [.init(subject: "You", relation: "develops", object: "Borealis", evidence: revised.text)]
            let beforeMemory = baseline.notebookBuildCount, beforeRevision = baseline.revision
            check(baseline.put(revised), "Fictional memory edit saves")
            let changed = equivalent(baseline, query: "Borealis")
            check(baseline.revision != beforeRevision && baseline.notebookBuildCount > beforeMemory && changed.records.contains { $0["id"] == revised.id.uuidString }, "Memory revision rebuilds notebook and lexical relevance")
        }

        for count in [100, 1_000, 10_000] {
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("conversation-\(count).store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: CachedDashboard.self, configurations: configuration)
            let baseText = String(repeating: "A fictional conversation about the next engineering step. ", count: 36)
            let turns = (0..<count).map { index -> AssistantTurn in
                .init(id: uuid(100_000 + index), role: index % 2 == 0 ? "user" : "assistant", content: baseText + " sample 000000", completed: true, created: now, focusAreas: [.projects], contextCapture: index % 2 == 0 ? nil : .init(id: uuid(200_000 + index), captured: now, model: "fictional", focusAreas: [.projects], memoryIDs: (1...8).map(uuid), eligibleMemoryCount: 1_000, notebookMemoryIDs: (1...6).map(uuid), workspaceIDs: ["life:fictional"], historyTurnIDs: (1...20).map(uuid), excerptedHistoryIDs: [], sourceSnapshotIncluded: false, sourceSnapshotBytes: 0, profileSetup: false))
            }
            let initial = [AssistantConversation(id: uuid(90_000), accountID: registration, title: "Fictional primary conversation", created: now, turns: turns, isPrimary: true)]
            let fullBytes = try JSONEncoder().encode(initial)
            let records = LocalRecordRepository(container: container)
            try records.write([ConversationRepository.legacyKey: fullBytes])
            let migration = ConversationRepository(container: container); check(try migration.load() == initial, "Conversation baseline load")
            try migration.save(initial)
            var sequence = 0
            func operation() throws -> (() throws -> Observation) {
                let repository = ConversationRepository(container: container)
                var history = try repository.load()
                return {
                    sequence += 1
                    history[0].turns[count - 1].content = baseText + String(format: " sample %06d", sequence)
                    try repository.save(history)
                    let stats = repository.lastSave
                    check(stats.encodedTurns == (count % 64 == 0 ? 64 : count % 64) && stats.writtenRecords == 2, "Actual save changes one chunk plus index")
                    return .init(count: history[0].turns.count, bytes: stats.encodedBytes, encodedTurns: stats.encodedTurns, writtenRecords: stats.writtenRecords)
                }
            }
            try measure("conversation_changed_chunk_save", workload: count, wholeHistoryBytes: fullBytes.count, cold: operation, warm: operation)
            let reloaded = try ConversationRepository(container: container).load()
            check(reloaded[0].turns.count == count && reloaded[0].turns.dropLast() == initial[0].turns.dropLast() && reloaded[0].turns.last?.content == baseText + String(format: " sample %06d", sequence), "Incremental saves preserve every unchanged turn and exact changed content")
            check(try records.read(ConversationRepository.legacyKey) == fullBytes, "Actual incremental saves retain byte-identical recovery original")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print("RUNTIME_MEASUREMENTS_JSON_BEGIN")
        print(String(data: try encoder.encode(measurements), encoding: .utf8)!)
        print("RUNTIME_MEASUREMENTS_JSON_END")
        print("Runtime measurement checks: \(checks) passed. Cold means fresh derived caches, not cleared OS caches; setup/load/migration excluded. Timings include observation assertions/byte counts. No timing thresholds, inference, personal storage or UI latency claim.")
    }
}
