import Foundation
import SwiftData

@main struct MemoryPreparationChecks {
    @MainActor static func main() throws {
        let now = Date.now, container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly:true))
        let repository = LocalRecordRepository(container:container)
        var human = PAMemory(registration:"fixture",text:"AI careers",kind:.context,provenance:"Fictional human")
        human.reviewed = now
        var temporary = PAMemory(registration:"fixture",text:"AI temporary plan",kind:.context,explicit:false,provenance:"Fictional provisional")
        temporary.reviewed = now
        var source = PAMemory(registration:"fixture",text:"AI source report",kind:.context,explicit:false,provenance:"Fictional source")
        source.source = .init(identity:.init(kind:.whatsapp,accountID:"fixture",containerID:"chat",itemID:"one",linkedIdentity:"device"),revision:"v1",label:"Fictional",quote:"AI source report",observed:now,sourceDate:now)
        source.reviewed = now
        var envelope = MemoryEnvelope(); envelope.records = [human,temporary,source]
        try repository.save(envelope,key:"paMemory")
        let store = PAMemoryStore(container:container)
        var permitted = false
        store.sourceIsPermitted = { _ in permitted }
        let first = store.selection("fixture",query:"AI",now:now)
        let notebook = store.notebook("fixture",now:now)
        precondition(first.records.count == 2 && notebook.eligibleCount == 2 && store.notebookBuildCount == 1)
        let again = store.selection("fixture",query:"AI",now:now)
        precondition(again.records == first.records && again.reasons == first.reasons && store.notebookBuildCount == 1)
        permitted = true
        precondition(store.selection("fixture",query:"AI",now:now).records.count == 3 && store.notebookBuildCount == 2)
        permitted = false
        precondition(store.selection("fixture",query:"AI",now:now).records.count == 2 && store.notebookBuildCount == 3)
        precondition(store.selection("fixture",query:"AI",now:now.addingTimeInterval(90*86400)).records.count == 1 && store.notebookBuildCount == 4)
        precondition(store.selection("other",query:"AI",now:now).records.isEmpty)
        var projection = UUID(), label = "First"
        store.notebookProjectionRevision = { projection }
        store.notebookProjection = { base,_,_,_ in var value=base;value.selfLabel=label;return value }
        precondition(store.notebook("fixture",now:now).selfLabel == "First")
        label = "Second"; projection = UUID()
        precondition(store.notebook("fixture",now:now).selfLabel == "Second")
        store.notebookProjectionRevision = nil
        label = "Unversioned first";precondition(store.notebook("fixture",now:now).selfLabel == label)
        label = "Unversioned next";precondition(store.notebook("fixture",now:now).selfLabel == label)
        precondition(store.saveReviewPreference("Assessment invitations matter",registration:"fixture",about:"Coding assessment"))
        precondition(store.selection("fixture",query:"coding assessment",now:.now).records.contains{$0["purpose"] == "review preference"})
        precondition(store.selection("fixture",query:"AI",includeSources:false,now:now).records.allSatisfy{$0["sourceEvidence"] == nil})
        print("Memory preparation checks passed: shared preparation, deterministic results, consent loss, time expiry, account changes, workspace revisions, unversioned projections and feedback invalidation.")
    }
}
