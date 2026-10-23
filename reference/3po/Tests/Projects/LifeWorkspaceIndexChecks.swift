import Foundation
import SwiftData

/// Compare the indexed widget path with its previous semantics, including
/// inherited Focus, legacy kinds, ordering, historical notes and local stages.
enum LifeWorkspaceIndexChecks {
    @MainActor static func run() throws {
        let registration = "fictional-index"
        let root = LifeItem(registration: registration, kind: .space, title: "Studies", notes: "Retained note", areas: [.studies])
        var task = LifeItem(registration: registration, kind: .task, title: "Waiting", parentID: root.id, status: .waiting, areas: [.home])
        task.additionalNotes = [.init(text: "Independent note")]
        let nested = LifeItem(registration: registration, kind: .space, title: "Nested", parentID: root.id)
        var values = [root, task, nested,
            LifeItem(registration: registration, kind: .task, title: "Done", parentID: nested.id, status: .done),
            LifeItem(registration: registration, kind: .task, title: "Archived", parentID: nested.id, status: .archived),
            LifeItem(registration: registration, kind: .task, title: "Active", parentID: nested.id, status: .active),
            LifeItem(registration: registration, kind: .course, title: "Legacy course"),
            LifeItem(registration: registration, kind: .project, title: "Legacy project"),
            LifeItem(registration: registration, kind: .task, title: "Unfiled"),
            LifeItem(registration: registration, kind: .space, title: "Home", areas: [.home])]
        var parent = nested.id
        for number in 0..<20 {
            let child = LifeItem(registration: registration, kind: .space, title: "Depth \(number)", parentID: parent)
            values.append(child); parent = child.id
        }
        values.append(.init(registration: registration, kind: .milestone, title: "Deep legacy task", parentID: parent, status: .active))
        values[1].sortOrder = 8; values[2].sortOrder = 2
        var deleted = LifeItem(registration: registration, kind: .task, title: "Deleted", parentID: root.id)
        deleted.deletedAt = .now; values.append(deleted)
        let original = values
        let ordered = LifeWorkspaceRules.ordered(values)
        for focus: [LifeArea] in [[], [.studies], [.projects], [.home], [.career], [.unsorted], [.home, .studies]] {
            let matching = ordered.filter { !Set(LifeWorkspaceRules.navigationAreas($0, in: ordered)).isDisjoint(with: focus) }
            let included = Set(matching.flatMap { LifeItemQuery.path($0, in: ordered).map(\.id) })
            let expected = focus.isEmpty ? ordered : ordered.filter { included.contains($0.id) }
            let index = LifeProjectIndex(ordered, focusAreas: focus)
            precondition(index.items == expected, "Focus retains the exact prior ordered records and note content")
            for item in expected {
                precondition(index.byID[item.id] == item)
                precondition(index.path(item) == LifeItemQuery.path(item, in: expected), "Indexed breadcrumbs match canonical ancestors")
                precondition(index.progress(under: item.id) == LifeFolderContents.progress(under: item.id, in: expected), "Progress includes descendants, waiting and legacy tasks, excluding archived/deleted work")
            }
            for id in [nil, Optional(root.id), Optional(nested.id), Optional(UUID())] {
                for unfinished in [false, true] {
                    precondition(index.children(of: id, unfinished: unfinished) == LifeFolderContents.children(of: id, in: expected, unfinished: unfinished), "Direct child ordering and unfinished filtering stay exact")
                }
            }
        }
        precondition(values == original, "Read-only projections cannot edit canonical records")
        // Orphaned legacy parents appear at Home, in their saved order.
        let orphan = LifeItem(registration: registration, kind: .task, title: "Orphan", parentID: UUID())
        precondition(LifeProjectIndex([orphan]).children(of: nil) == [orphan])

        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = LifeWorkspaceStore(container: container), otherStore = LifeWorkspaceStore(container: nil)
        _ = try store.save(root, expected: nil)
        _ = try store.save(task, expected: nil)
        let scoped = LifeItem(registration: registration, conversationID: UUID(), kind: .space, title: "Topic", areas: [.studies])
        _ = try store.save(scoped, expected: nil)
        let cache = LifeProjectProjectionCache()
        func project(_ account: String = registration, topic: UUID? = nil, focus: [LifeArea] = [.studies], revision: UUID? = nil, owner: AnyObject? = nil) -> LifeProjectIndex {
            cache.value(owner: owner ?? store, revision: revision ?? store.revision, registration: account, topic: topic, focusAreas: focus) { store.items(account, topic: topic) }
        }
        let first = project(), before = store.state, initialRevision = store.revision
        for _ in 0..<200 { precondition(project() === first, "Repeated view access reuses one immutable projection") }
        precondition(cache.builds == 1 && store.state == before && store.revision == initialRevision)
        let shared = project()
        precondition(!shared.items.contains { $0.id == scoped.id })
        precondition(project(topic: scoped.conversationID).items.contains { $0.id == scoped.id }, "Topic changes invalidate before returning content")
        precondition(project("other-account").items.isEmpty, "Account changes cannot return cached personal content")
        precondition(project(focus: [.career]).items.isEmpty, "Focus changes invalidate before returning content")
        let multiple = project(focus: [.studies, .home])
        precondition(project(focus: [.home, .studies, .home]) === multiple, "Equivalent multi-select Focus order reuses its exact projection")
        let current = project()
        precondition(project(owner: otherStore) !== current, "A different store owner invalidates even with the same supplied revision")
        let old = project()
        var edited = store.state.items.first { $0.id == task.id }!; edited.status = .done
        _ = try store.save(edited, expected: edited.revision)
        let updated = project()
        precondition(updated !== old && updated.byID[task.id]?.status == .done, "Actual saved store revisions invalidate status, counts and records")
        precondition(updated.progress(under: root.id).counts == [0, 0, 1])

        // Same exact flat 100/1,000/5,000-item workload used in the audit.
        // Report timing without brittle wall-clock pass/fail thresholds.
        for count in [100, 1_000, 5_000] {
            let folder = LifeItem(registration: registration, kind: .space, title: "Benchmark folder", areas: [.studies])
            let all = [folder] + (1..<count).map { LifeItem(registration: registration, kind: .task, title: "Task \($0)", parentID: folder.id, notes: String(repeating: "x", count: 2000)) }
            let fixture = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            try LocalRecordRepository(container: fixture).save(LifeWorkspaceState(items: all), key: "lifeWorkspace")
            let fixtureStore = LifeWorkspaceStore(container: fixture)
            var cold: [Double] = [], warm: [Double] = []
            for _ in 0..<5 {
                let local = LifeProjectProjectionCache(), start = DispatchTime.now().uptimeNanoseconds
                let value = local.value(owner: fixtureStore, revision: fixtureStore.revision, registration: registration, topic: nil, focusAreas: [.studies]) { fixtureStore.items(registration) }
                cold.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                precondition(value.items == LifeWorkspaceRules.ordered(all) && value.progress(under: folder.id).counts == [count - 1, 0, 0], "Large projection preserves every matching item, its exact order and counts")
            }
            let local = LifeProjectProjectionCache()
            let initial = local.value(owner: fixtureStore, revision: fixtureStore.revision, registration: registration, topic: nil, focusAreas: [.studies]) { fixtureStore.items(registration) }
            for _ in 0..<15 {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<100 {
                    let value = local.value(owner: fixtureStore, revision: fixtureStore.revision, registration: registration, topic: nil, focusAreas: [.studies]) { preconditionFailure("Warm render must not reload or sort the workspace") }
                    precondition(value === initial && value.progress(under: folder.id).total == count - 1)
                }
                warm.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 100_000_000)
            }
            precondition(local.builds == 1)
            cold.sort(); warm.sort()
            print(String(format: "PROJECT INDEX n=%d cold median=%.3fms p95=%.3fms warm median=%.6fms p95=%.6fms (5 cold; 15x100 warm; one build)", count, cold[2], cold[4], warm[7], warm[14]))
        }
        print("PASS: indexed Focus/ordering/ancestor/stage/note/child/progress equivalence; account/topic/owner/revision invalidation; actual saved-edit refresh; 100/1000/5000 cold and reused widget projection workloads")
    }
}
