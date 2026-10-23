import Foundation
import SwiftData

/// Measured fictional workloads, not timing pass/fail targets or live UI acceptance.
@main struct PerformanceChecks {
    struct Observation: Equatable { var count: Int; var bytes: Int }
    struct Measurement: Codable {
        var operation: String
        var workload: Int
        var firstMilliseconds: Double
        var warmMedianMilliseconds: Double
        var warmP95Milliseconds: Double
        var warmSamples: Int
        var outputCount: Int
        var outputBytes: Int
    }
    @MainActor static func main() throws {
        let samples = 15
        var measurements: [Measurement] = []
        func measure<T>(_ operation: String, workload: Int, run: () throws -> T, observe: (T) throws -> Observation) throws {
            func sample() throws -> (Double, Observation) {
                let start = DispatchTime.now().uptimeNanoseconds
                let value = try run()
                let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                return (duration, try observe(value))
            }
            let first = try sample()
            var warm: [Double] = []
            for _ in 0..<samples {
                let result = try sample()
                precondition(result.1 == first.1, "The workload must keep output count/bytes stable")
                warm.append(result.0)
            }
            warm.sort()
            let report = Measurement(operation: operation, workload: workload, firstMilliseconds: first.0, warmMedianMilliseconds: warm[warm.count / 2], warmP95Milliseconds: warm[Int(ceil(Double(warm.count) * 0.95)) - 1], warmSamples: samples, outputCount: first.1.count, outputBytes: first.1.bytes)
            measurements.append(report)
            print(String(format: "MEASURE %@ n=%d first=%.3f ms warm median=%.3f ms p95=%.3f ms output=%d bytes=%d", operation, workload, report.firstMilliseconds, report.warmMedianMilliseconds, report.warmP95Milliseconds, report.outputCount, report.outputBytes))
        }
        func uuid(_ index: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))! }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let query = "Orion calibration"
        for count in [100, 1_000, 10_000] {
            let facts = (0..<count).map { index -> PAMemory in
                let project = index < 8 ? "Orion" : "Fictional topic \((index - 8) % 23)"
                let text = index < 8 ? "I am developing Orion calibration experiment \(index)." : "I am working on \(project), with unrelated observation \(index)."
                return PAMemory(id: uuid(index + 1), registration: "fictional", text: text, kind: .context, provenance: "Fictional human workload", created: date, reviewed: date, evidence: text, certainty: .stated, durability: .stable, connections: [.init(subject: "You", relation: "develops", object: project, evidence: text)], organisation: .init(areas: [.projects], connections: [.init(connection: "0", subjectKind: .person, objectKind: .project, subjectIsSelf: true, objectIsSelf: false)]))
            }
            let items = (0..<24).map { index -> LifeItem in
                let label = index == 0 ? "Orion" : "Fictional topic \(index - 1)"
                return LifeItem(id: uuid(20_000 + index), registration: "fictional", kind: .space, title: label, notes: "Fictional local folder", areas: [.projects], created: date, updated: date, notebookEntityID: "shared:project:" + LifeNotebook.key(label))
            }
            let itemLinks = items.enumerated().map { index, item -> LifeItemLink in
                let fact = facts[index == 0 ? 0 : index + 7]
                return .init(id: uuid(30_000 + index), registration: "fictional", from: item.id, relation: .identifies, target: .init(kind: .memory, id: fact.id.uuidString, containerID: item.notebookEntityID), created: date)
            }
            let base = LifeNotebook.build(facts, registration: "fictional", now: date)
            let canonical = base.integrating(items, links: itemLinks)
            let expected = Set(facts.prefix(8).map(\.id))
            func select(_ notebook: LifeNotebook) -> MemorySelection {
                MemoryRetrieval.select(facts, registration: "fictional", query: query, now: date, limit: 40, bytes: 20_000, notebook: notebook)
            }
            func selectionObservation(_ selection: MemorySelection) throws -> Observation {
                precondition(Set(selection.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) }) == expected)
                let bytes = try JSONSerialization.data(withJSONObject: selection.records, options: [.sortedKeys]).count
                precondition(selection.records.count <= 40 && bytes <= 20_000)
                return .init(count: selection.records.count, bytes: bytes)
            }
            try measure("memory_notebook_build", workload: count, run: { LifeNotebook.build(facts, registration: "fictional", now: date) }, observe: { .init(count: $0.eligibleCount, bytes: 0) })
            try measure("memory_canonical_projection", workload: count, run: { base.integrating(items, links: itemLinks) }, observe: { .init(count: $0.anchors.count, bytes: 0) })
            try measure("memory_bounded_selection", workload: count, run: { select(canonical) }, observe: selectionObservation)
            let selected = select(canonical)
            let selectedIDs = Set(selected.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
            func notebookObservation(_ context: String) -> Observation {
                let ids = PAContextCapture.notebookIDs(context)
                precondition(Set(ids.memories).isSubset(of: selectedIDs) && context.utf8.count <= 8_000)
                return .init(count: ids.memories.count, bytes: context.utf8.count)
            }
            try measure("memory_selected_notebook_context", workload: count, run: { canonical.context(query: query, maxBytes: 8_000, selectedMemoryIDs: selectedIDs) }, observe: notebookObservation)
            try measure("memory_complete_pipeline", workload: count, run: { () -> (MemorySelection, String) in
                let notebook = LifeNotebook.build(facts, registration: "fictional", now: date).integrating(items, links: itemLinks)
                let selection = select(notebook)
                let ids = Set(selection.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
                return (selection, notebook.context(query: query, maxBytes: 8_000, selectedMemoryIDs: ids))
            }, observe: { result in
                let selection = try selectionObservation(result.0), context = notebookObservation(result.1)
                return .init(count: selection.count, bytes: selection.bytes + context.bytes)
            })
        }

        // All-conversation encoding is the legacy baseline save format. Text and
        // metadata are fictional; image bytes are not embedded in these records.
        for turns in [100, 1_000, 10_000] {
            let text = String(repeating: "A fictional conversation about the next engineering step. ", count: 36)
            let conversations = (0..<10).map { conversation -> AssistantConversation in
                let rows = (0..<(turns / 10)).map { index -> AssistantTurn in
                    let key = conversation * (turns / 10) + index
                    let assistant = index % 2 == 1
                    let capture = assistant ? PAContextCapture(id: uuid(100_000 + key), captured: date, model: "fictional", focusAreas: [.projects], memoryIDs: (1...8).map(uuid), eligibleMemoryCount: 1_000, notebookMemoryIDs: (1...6).map(uuid), workspaceIDs: ["life:" + uuid(20_000).uuidString], historyTurnIDs: (1...20).map(uuid), excerptedHistoryIDs: [], sourceSnapshotIncluded: false, sourceSnapshotBytes: 0, profileSetup: false, attemptedTools: ["pa.read_memory"]) : nil
                    return AssistantTurn(id: uuid(200_000 + key), role: assistant ? "assistant" : "user", content: text, completed: true, created: date, contextID: conversation == 0 ? nil : uuid(300_000 + conversation), focusAreas: [.projects], images: index % 20 == 0 ? [.init(id: uuid(400_000 + key), registration: "fictional", mimeType: "image/png", width: 100, height: 100, byteCount: 2_000, digest: "fictional-reference-only")] : nil, contextCapture: capture)
                }
                return AssistantConversation(id: uuid(300_000 + conversation), accountID: "fictional", title: "Fictional conversation \(conversation)", created: date, turns: rows, isPrimary: conversation == 0, isTopic: conversation != 0)
            }
            try measure("conversation_encode_entire_collection", workload: turns, run: { try JSONEncoder().encode(conversations) }, observe: { .init(count: turns, bytes: $0.count) })
            try measure("conversation_encode_one_changed_conversation", workload: turns, run: { try JSONEncoder().encode(conversations[0]) }, observe: { .init(count: conversations[0].turns.count, bytes: $0.count) })
            try measure("conversation_encode_one_changed_turn", workload: turns, run: { try JSONEncoder().encode(conversations[0].turns.last!) }, observe: { .init(count: 1, bytes: $0.count) })
            var feed = conversations[0]
            feed.turns = conversations.flatMap(\.turns)
            var target = conversations.last!
            let targetCount = target.turns.count
            target.turns = []
            try measure("navigation_topic_transcript_projection", workload: turns, run: {
                let thread = ConversationRules.thread(feed:feed, topic:target)
                return ConversationRules.transcript(thread, visible: { $0.completed && !$0.content.isEmpty })
            }, observe: { rows in
                precondition(rows.count == targetCount)
                return .init(count:rows.count, bytes:rows.reduce(0) { $0 + $1.turn.content.utf8.count })
            })
        }

        let directory = URL(fileURLWithPath: "/tmp/3po-memory-worker-performance-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for unrelated in [100, 1_000, 10_000] {
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("fictional-\(unrelated).store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: CachedDashboard.self, configurations: configuration)
            let initial = Data(repeating: 42, count: 4_096), noise = Data(repeating: 7, count: 1_024)
            let setup = ModelContext(container); setup.autosaveEnabled = false
            setup.insert(CachedDashboard(key: "target", data: initial, updated: date))
            for index in 0..<unrelated { setup.insert(CachedDashboard(key: "unrelated-\(index)", data: noise, updated: date)) }
            try setup.save()
            let repository = LocalRecordRepository(container: container)
            func legacyRead() throws -> Data? {
                try container.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first { $0.key == "target" }?.data
            }
            func readObservation(_ value: Data?) -> Observation {
                precondition(value?.count == initial.count)
                return .init(count: value == nil ? 0 : 1, bytes: value?.count ?? 0)
            }
            try measure("storage_keyed_read_fresh_context", workload: unrelated, run: { try repository.read("target") }, observe: readObservation)
            try measure("storage_legacy_fetch_all_read_reused_context", workload: unrelated, run: legacyRead, observe: readObservation)
            var sequence = 0
            func nextPayload() -> Data { sequence += 1; var data = initial; data[0] = UInt8(sequence % 255); return data }
            try measure("storage_keyed_write_fresh_context", workload: unrelated, run: {
                let payload = nextPayload(); try repository.write(["target": payload]); return payload
            }, observe: { payload in
                let saved = try repository.read("target")
                precondition(saved == payload)
                return .init(count: 1, bytes: payload.count)
            })
            try measure("storage_legacy_fetch_all_write_reused_context", workload: unrelated, run: {
                let payload = nextPayload()
                if let row = try container.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first(where: { $0.key == "target" }) { row.data = payload; row.updated = date }
                else { container.mainContext.insert(CachedDashboard(key: "target", data: payload, updated: date)) }
                try container.mainContext.save(); return payload
            }, observe: { payload in
                let saved = try repository.read("target")
                precondition(saved == payload)
                return .init(count: 1, bytes: payload.count)
            })
            let retained = try repository.read("unrelated-\(unrelated - 1)")
            precondition(retained == noise)
        }
        let output = JSONEncoder(); output.outputFormatting = [.prettyPrinted, .sortedKeys]
        print("MEASUREMENTS_JSON_BEGIN")
        print(String(data: try output.encode(measurements), encoding: .utf8)!)
        print("MEASUREMENTS_JSON_END")
        print("Performance measurements completed; count/byte/readback invariants passed. First-call timings do not clear OS caches; warm p95 uses nearest rank across 15 samples. No timing thresholds, inference, personal data or native source reads.")
    }
}
