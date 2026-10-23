import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let account="fictional",now=Date.now
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let memory=PAMemoryStore(container:container),workspace=LifeWorkspaceStore(container:container)
        var fact=PAMemory(registration:account,text:"I am building Sensor Garden.",kind:.context,explicit:false,provenance:"Fictional human",sourceTurnID:"fictional-human",evidence:"I am building Sensor Garden.",certainty:.stated,durability:.situational,connections:[.init(subject:"Me",relation:"builds",object:"Sensor Garden",evidence:"I am building Sensor Garden.")])
        fact.organisation = .init(areas:[.projects],connections:[.init(connection:"0",subjectKind:.person,objectKind:.project,subjectIsSelf:true,objectIsSelf:false)])
        precondition(memory.put(fact))
        var project=try workspace.save(.init(registration:account,kind:.project,title:"Sensor Garden"),expected:nil)
        let binding=LifeItemLink(registration:account,from:project.id,relation:.identifies,target:.init(kind:.memory,id:fact.id.uuidString,containerID:"shared:project:sensor garden"))
        _=try workspace.link(binding,expected:project.revision)
        project=workspace.items(account).first{$0.id == project.id}!
        var renamed=project;renamed.title="Lumen"
        project=try workspace.save(renamed,expected:project.revision)
        memory.notebookProjection={base,registration,topic,includeTopics in
            base.integrating(workspace.items(registration,topic:topic,includeTopics:includeTopics),links:workspace.state.links)
        }
        // More facts than the recall cap: a renamed exact binding must compete successfully.
        for index in 0..<45 { precondition(memory.put(.init(registration:account,text:"Unrelated fictional context \(index)",kind:.context,provenance:"Fictional"))) }
        let selection=memory.selection(account,query:"Lumen")
        precondition(selection.records.contains{$0["id"] == fact.id.uuidString})
        precondition(selection.reasons[fact.id]?.contains("Linked to a matching saved project or life item") == true)
        precondition(memory.notebook(account).anchors.first{$0.id == "life:"+project.id.uuidString}?.memoryIDs == [fact.id])
        let context=memory.notebook(account).context(query:"Lumen",maxBytes:8000)
        precondition(context.utf8.count <= 8000 && context.contains(fact.id.uuidString))
        var corrected=fact;corrected.id=UUID();corrected.text="Sensor Garden is now my experimental prototype.";corrected.evidence=corrected.text;corrected.connections?[0].evidence=corrected.text
        precondition(memory.correct(fact.id,with:corrected))
        let current=memory.notebook(account)
        precondition(current.entities.first{$0.id == "life:"+project.id.uuidString}?.memoryIDs == [corrected.id],"Exact binding follows a correction with the same typed endpoint")
        precondition(current.anchors.first{$0.id == "life:"+project.id.uuidString}?.memoryIDs == [corrected.id])
        precondition(!memory.selection(account,query:"Lumen").records.contains{$0["id"] == fact.id.uuidString})
        let beforeWorkspace=workspace.state,beforeMemory=memory.revision
        precondition(memory.retire(corrected.id,retired:true,expectedRevision:beforeMemory))
        precondition(!memory.retire(corrected.id,retired:false,expectedRevision:beforeMemory),"Stale restoration is rejected")
        let stored=memory.records.first{$0.id == corrected.id}!
        precondition(stored.retiredAt != nil && stored.text == corrected.text && stored.evidence == corrected.evidence)
        precondition(!memory.selection(account,query:"Lumen").records.contains{$0["id"] == corrected.id.uuidString})
        precondition(memory.notebook(account).anchors.first{$0.id == "life:"+project.id.uuidString}?.memoryIDs.isEmpty == true)
        precondition(MemoryInspection.rows(memory.records,permitted:Set(memory.permittedRecords.map(\.id)),registration:account).first{$0.id == corrected.id}?.availability == .retired)
        precondition(workspace.state == beforeWorkspace && memory.suppressed(account).isEmpty,"Retirement neither edits projects nor creates Forget suppression")
        let reopened=PAMemoryStore(container:container)
        precondition(reopened.records.first{$0.id == corrected.id}?.retiredAt != nil && reopened.selection(account).records.allSatisfy{$0["id"] != corrected.id.uuidString})
        let repeatFact=LearnedMemory(turnID:"fictional-human",text:"A paraphrase of the retired context",kind:.context,evidence:corrected.evidence!,certainty:.stated,durability:.situational)
        precondition(memory.merge([repeatFact],registration:account) && !memory.records.contains{$0.text == repeatFact.text},"The same retired human evidence cannot resurrect a paraphrase")
        precondition(memory.retire(corrected.id,retired:false,expectedRevision:memory.revision))
        precondition(memory.records.first{$0.id == corrected.id}?.retiredAt == nil && memory.selection(account,query:"Lumen").records.contains{$0["id"] == corrected.id.uuidString})
        precondition(workspace.state == beforeWorkspace)
        let beforeClassification=memory.records.first{$0.id == corrected.id}!
        var classification=beforeClassification.organisation!;classification.areas=[.studies]
        precondition(memory.organise(corrected.id,value:classification,expectedRevision:memory.revision))
        let afterClassification=memory.records.first{$0.id == corrected.id}!
        precondition(afterClassification.text == beforeClassification.text && afterClassification.evidence == beforeClassification.evidence && afterClassification.reviewed == beforeClassification.reviewed && afterClassification.explicit == beforeClassification.explicit,"Classification does not renew evidence or truth")
        precondition(memory.setOrganisation(corrected.id,value:classification) && !memory.organise(corrected.id,value:classification,expectedRevision:memory.revision),"Pinned organisation cannot be overwritten")
        precondition(LifeOrganisationRules.input([afterClassification]).contains("existingOrganisation"))
        let commitment=PAMemory(registration:account,text:"Prepare a prototype report",kind:.commitment,provenance:"Fictional")
        precondition(memory.put(commitment) && !memory.retire(commitment.id,retired:true,expectedRevision:memory.revision))
        precondition(memory.resolve(commitment.id) && memory.records.first{$0.id == commitment.id}?.resolved != nil)
        var source=fact;source.id=UUID();source.source = .init(identity:.init(kind:.mail,accountID:"fictional-mail",containerID:"inbox",itemID:"fictional-message"),revision:"fictional-version",label:"Fictional source",quote:fact.text,observed:now)
        precondition(memory.put(source) && !memory.retire(source.id,retired:true,expectedRevision:memory.revision))
        precondition(!memory.selection(account).records.contains{$0["id"] == source.id.uuidString},"Unavailable source never enters project recall")
        var duplicate=project;duplicate.id=UUID();duplicate.title="Sensor Garden"
        let ambiguous=LifeNotebook.build([fact],registration:account).integrating([duplicate,LifeItem(registration:account,kind:.project,title:"Sensor Garden")],links:[])
        precondition(ambiguous.entities.first{$0.id == "shared:project:sensor garden"} != nil,"Identical labels are not an identity merge")
        var deleted=project;deleted.deletedAt=now
        let withoutProject=LifeNotebook.build([corrected],registration:account).integrating([deleted],links:[binding])
        precondition(withoutProject.anchors.isEmpty && withoutProject.entities.allSatisfy{!$0.id.hasPrefix("life:")})
        // Organisation reconsideration is metadata-only, bounded and deliberately slow.
        var aged=fact;aged.created=now.addingTimeInterval(-35*86400);aged.reviewed=aged.created;aged.durability = .stable
        var pinned=aged;pinned.id=UUID();pinned.organisation?.manual=true
        var retired=aged;retired.id=UUID();retired.retiredAt=now
        var foreign=aged;foreign.id=UUID();foreign.registration="other"
        var unclassified=aged;unclassified.id=UUID();unclassified.organisation=nil
        let candidates=[aged,pinned,retired,foreign,source,unclassified]
        let batch=LifeOrganisationBatch.records(candidates,registration:account,topic:nil,progress:.init(),now:now)
        precondition(Set(batch.map(\.id)) == [aged.id,unclassified.id] && batch.first?.id == unclassified.id)
        var progress=LifeOrganisationProgress();progress.reconsidered=[aged.id:now];progress.inspected[unclassified.id]=unclassified.reviewed
        precondition(LifeOrganisationBatch.records(candidates,registration:account,topic:nil,progress:progress,now:now).isEmpty)
        precondition(LifeOrganisationBatch.records([aged],registration:account,topic:nil,progress:progress,now:now.addingTimeInterval(31*86400)).count == 1)
        var legacyProgress=(try JSONSerialization.jsonObject(with:JSONEncoder().encode(progress))) as! [String:Any];legacyProgress.removeValue(forKey:"reconsidered")
        let legacy=try JSONDecoder().decode(LifeOrganisationProgress.self,from:JSONSerialization.data(withJSONObject:legacyProgress))
        precondition(legacy.reconsidered == nil)
        var legacyMemory=(try JSONSerialization.jsonObject(with:JSONEncoder().encode(fact))) as! [String:Any];legacyMemory.removeValue(forKey:"retiredAt")
        let decodedMemory=try JSONDecoder().decode(PAMemory.self,from:JSONSerialization.data(withJSONObject:legacyMemory))
        precondition(decodedMemory.retiredAt == nil)
        print("PASS: renamed project recall, exact correction bindings, current-fact context, reversible persisted retirement, stale guards, same-evidence relearning protection, commitment/source boundaries, deleted/ambiguous identities and bounded unpinned organisation reconsideration")
    }
}
