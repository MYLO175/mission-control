import Foundation
import SwiftData
@main struct Checks {
    @MainActor static func main() throws {
        let container = try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store = ChatDraftStore(container:container), a = UUID(), b = UUID(), topic = UUID(), other = UUID()
        store.set("Draft A",registration:"one",widget:a,conversation:topic)
        store.set("Draft B",registration:"one",widget:b,conversation:topic)
        store.set("Other topic",registration:"one",widget:a,conversation:other)
        store.set("Other account",registration:"two",widget:a,conversation:topic)
        store.show(registration:"one",widget:a,conversation:topic)
        precondition(store.hasDraft(registration:"one") && !store.hasDraft(registration:"two"))
        store.hide(widget:a); precondition(!store.hasDraft(registration:"one"),"Hidden drafts are retained without holding learning indefinitely")
        store.flush()
        let reload = ChatDraftStore(container:container)
        precondition(reload.text(registration:"one",widget:a,conversation:topic) == "Draft A")
        precondition(reload.text(registration:"one",widget:b,conversation:topic) == "Draft B")
        precondition(reload.text(registration:"one",widget:a,conversation:other) == "Other topic")
        precondition(reload.text(registration:"two",widget:a,conversation:topic) == "Other account")
        reload.set("",registration:"one",widget:a,conversation:topic); reload.flush()
        let cleared = ChatDraftStore(container:container)
        precondition(cleared.text(registration:"one",widget:a,conversation:topic).isEmpty)
        precondition(cleared.text(registration:"one",widget:b,conversation:topic) == "Draft B")
        let unavailable = ChatDraftStore(container:nil)
        unavailable.set("Keep locally",registration:"one",widget:a,conversation:topic); unavailable.flush()
        precondition(unavailable.error != nil && unavailable.text(registration:"one",widget:a,conversation:topic) == "Keep locally")
        let record = try container.mainContext.fetch(FetchDescriptor<CachedDashboard>()).first { $0.key == "assistantDrafts" }!
        let original = Data("{\"version\":99,\"values\":{}}".utf8); record.data = original; try container.mainContext.save()
        let blocked = ChatDraftStore(container:container)
        blocked.set("Must not overwrite",registration:"one",widget:a,conversation:topic); blocked.flush()
        precondition(!blocked.writable && blocked.state.values.isEmpty && record.data == original)
        print("PASS: per-widget/topic/account draft isolation, visible-only learning hold, persistence, selective clearing, storage failure and unknown-version preservation")
    }
}
