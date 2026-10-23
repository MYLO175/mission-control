import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let now=Date.now,account="fictional"
        var stable=PAMemory(registration:account,text:"I study Orion engineering.",kind:.context,provenance:"Human",evidence:"I study Orion engineering.",certainty:.stated,durability:.stable)
        stable.reviewed=now.addingTimeInterval(-100*86400)
        var old=stable;old.id=UUID();old.supersededBy=stable.id
        var resolved=stable;resolved.id=UUID();resolved.resolved=now
        var expired=stable;expired.id=UUID();expired.explicit=false;expired.certainty = .inferred;expired.durability = .situational
        var denied=stable;denied.id=UUID();denied.sourceInvalidation = .accessRemoved
        var scoped=stable;scoped.id=UUID();scoped.conversationID=UUID()
        var foreign=stable;foreign.id=UUID();foreign.registration="other"
        let records=[stable,old,resolved,expired,denied,scoped,foreign],permitted=Set(records.filter{$0.id != denied.id}.map(\.id))
        let rows=MemoryInspection.rows(records,permitted:permitted,registration:account,includeTopics:false,now:now)
        precondition(rows.count == 6)
        func status(_ record:PAMemory)->MemoryAvailability { rows.first{$0.id == record.id}!.availability }
        precondition(status(stable) == .available && status(old) == .earlierVersion && status(resolved) == .resolved && status(expired) == .reviewNeeded && status(denied) == .sourceUnavailable && status(scoped) == .otherScope)
        let focusRows=MemoryInspection.rows(records,permitted:permitted,registration:account,includeTopics:true,now:now)
        let eligible=Set(focusRows.filter{$0.availability == .available}.map(\.id))
        let selection=MemoryRetrieval.select(records.filter{permitted.contains($0.id)},registration:account,includeTopics:true,query:"Orion",now:now)
        precondition(eligible == Set(selection.records.compactMap{$0["id"].flatMap(UUID.init(uuidString:))}))
        precondition(selection.reasons[stable.id]?.contains("Words match your question") == true)
        let limited=MemoryRetrieval.select(records.filter{permitted.contains($0.id)},registration:account,includeTopics:true,query:"Orion",now:now,limit:1)
        precondition(limited.records.count == 1 && limited.eligibleCount == 2 && limited.reasons.count == 1)
        var preference=stable;preference.id=UUID();preference.kind = .preference
        precondition(MemoryRetrieval.select([preference],registration:account,query:"unrelated",now:now).records.isEmpty)
        let pinned=MemoryRetrieval.select([preference],registration:account,now:now)
        precondition(pinned.reasons[preference.id]?.contains("Core confirmed preference") == true)
        let notebook=LifeNotebook.build(records.filter{permitted.contains($0.id)},registration:account,now:now,includeTopics:true)
        let context=notebook.context(query:"Orion")
        let ids=PAContextCapture.notebookIDs(context)
        precondition(Set(ids.memories).isSubset(of:eligible) && !ids.memories.isEmpty)
        let capture=PAContextCapture(model:"fictional-model",focusAreas:[.studies],memoryIDs:Array(eligible),eligibleMemoryCount:eligible.count,notebookMemoryIDs:ids.memories,workspaceIDs:[],historyTurnIDs:[],excerptedHistoryIDs:[],sourceSnapshotIncluded:false,sourceSnapshotBytes:0,profileSetup:false)
        let turn=AssistantTurn(role:"assistant",content:"Fictional",completed:true,contextCapture:capture)
        let encoded=try JSONEncoder().encode(turn)
        let decoded=try JSONDecoder().decode(AssistantTurn.self,from:encoded)
        precondition(decoded.contextCapture == capture)
        var legacy=(try JSONSerialization.jsonObject(with:encoded)) as! [String:Any];legacy.removeValue(forKey:"contextCapture")
        let decodedLegacy=try JSONDecoder().decode(AssistantTurn.self,from:JSONSerialization.data(withJSONObject:legacy))
        precondition(decodedLegacy.contextCapture == nil)
        let serialized=String(data:encoded,encoding:.utf8)!
        precondition(!serialized.contains(stable.text) && !serialized.contains("accessToken"))
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=PAMemoryStore(container:container)
        _=store.put(stable)
        var correction=stable;correction.id=UUID();correction.text="I now study Lyra engineering."
        precondition(store.correct(stable.id,with:correction))
        precondition(Set(store.lineage(stable.id).map(\.id)) == [stable.id,correction.id])
        precondition(Set(store.lineage(correction.id).map(\.id)) == [stable.id,correction.id])
        precondition(store.versionFamily(stable.id).count == 1 && store.versionFamily(correction.id).count == 2)
        print("Memory inspection checks passed: account/scope/source/history/review gates; exact bounded selection reasons; notebook IDs; optional transcript trace; lineage inspection preserves Forget semantics.")
    }
}
