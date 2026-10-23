import Foundation
import SwiftData

@main struct CommitmentReportsChecks {
    @MainActor static func main() throws {
        let account="fictional-owner",now=Date.now
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=PAMemoryStore(container:container),workspace=LifeWorkspaceStore(container:container)
        var allowed:Set<String>=["email","accepted","moved","cancelled","other-chat","completed"]
        store.sourceIsPermitted={memory in memory.allSourceEvidence.allSatisfy{allowed.contains($0.identity.itemID)}}
        func fact(_ id:String,_ kind:MemorySourceKind,_ text:String,_ state:MemorySourceState,date:Date,chat:String="orion")->PAMemory {
            let source=MemorySourceEvidence(identity:.init(kind:kind,accountID:kind == .whatsapp ? "linked" : "mail-account",containerID:chat,itemID:id,linkedIdentity:kind == .whatsapp ? "linked" : nil),revision:"v1",label:"Alex · Orion",quote:text,observed:now,sourceDate:date)
            return .init(registration:account,text:text,kind:.commitment,explicit:false,provenance:"Fictional source",created:now,reviewed:now,evidence:text,sourceDate:date,certainty:.inferred,durability:.situational,source:source,sourceState:state)
        }
        var email=fact("email",.mail,"Alex asks whether the Orion draft can be presented Friday.",.proposed,date:now.addingTimeInterval(-7200))
        let accepted=fact("accepted",.whatsapp,"Alex reports the agreed Orion draft is due Friday.",.accepted,date:now.addingTimeInterval(-3600))
        let other=fact("other-chat",.whatsapp,"Alex reports the agreed Orion draft is due Friday.",.accepted,date:now.addingTimeInterval(-3500),chat:"separate-orion")
        let completed=fact("completed",.whatsapp,"Alex reports that the Orion draft was sent.",.completed,date:now.addingTimeInterval(-1000))
        func save(_ values:[PAMemory],replacements:[UUID:MemorySourceEvidence]=[:])->Bool {
            store.putSources(values,evidenceTexts:Dictionary(values.flatMap(\.allSourceEvidence).map{($0.identity,$0.quote)},uniquingKeysWith:{a,_ in a}),expectedRevision:store.revision,replacementSources:replacements)
        }
        precondition(save([email,accepted,other,completed]))
        let baseline=store.records
        let raw=CommitmentRules.context(store.context(account))
        precondition((raw["plans"] as! [[String:Any]]).count == 4,"Equal labels/date/person names do not establish cross-source or cross-chat identity")
        precondition(CommitmentRules.reports(accepted,from:store.permittedRecords).count == 1)
        let receipts=MemoryDependencyRules.capture(store.context(account))
        let stale=store.revision
        precondition(store.connectCommitments(email.id,accepted.id,registration:account,expectedRevision:stale))
        email=store.records.first{$0.id == email.id}!
        let group=email.commitmentGroup!
        precondition(!store.connectCommitments(email.id,other.id,registration:account,expectedRevision:stale),"A stale selection cannot join another report")
        precondition(!MemoryDependencyRules.available(receipts,records:store.context(account)),"A changed identity connection invalidates earlier advice")
        precondition(CommitmentRules.reports(email,from:store.permittedRecords).count == 2)
        let connected=CommitmentRules.context(store.context(account))["plans"] as! [[String:Any]]
        let linked=connected.first{$0["humanConnected"] as? Bool == true}!
        precondition(linked["uncertain"] as? Bool == true && Set(linked["reportedStates"] as! [String]) == ["proposed","accepted"],"Connecting reports never adjudicates acceptance or chooses a latest winner")
        precondition(store.records.map(\.text) == baseline.map(\.text) && store.records.map(\.reviewed) == baseline.map(\.reviewed) && store.records.allSatisfy{$0.resolved == nil},"Identity review preserves evidence, truth/review date and task status")
        precondition(PAMemoryStore(container:container).records.first{$0.id == email.id}?.commitmentGroup == group)
        var forgedHuman=email;forgedHuman.id=UUID()
        precondition(store.put(forgedHuman) && store.records.first{$0.id == forgedHuman.id}?.commitmentGroup == nil,"Generic put cannot forge a human identity connection")
        var forgedExisting=email;forgedExisting.commitmentGroup=UUID()
        precondition(store.put(forgedExisting) && store.records.first{$0.id == email.id}?.commitmentGroup == group,"Generic edits preserve only the existing reviewed identity")
        var forged=other;forged.id=UUID();forged.commitmentGroup=group
        precondition(!save([forged]),"Source tools cannot issue a human identity connection")
        var moved=fact("moved",.whatsapp,"Alex reports the Orion deadline is now Monday.",.changed,date:now.addingTimeInterval(-2000))
        moved.supersedes=accepted.id;moved.supportingSources=[accepted.source!]
        let emailOnly=MemoryDependencyRules.capture([MemoryRetrieval.record(store.records.first{$0.id == email.id}!)])
        precondition(save([moved]))
        moved=store.records.first{$0.id == moved.id}!
        precondition(!MemoryDependencyRules.available(emailOnly,records:store.context(account)),"A changed connected report invalidates even advice that supplied only its other group member")
        email=store.records.first{$0.id == email.id}!
        precondition(moved.commitmentGroup == group && store.records.first{$0.id == accepted.id}?.supersededBy == moved.id,"Only validated exact source versioning inherits the reviewed identity")
        precondition(Set(CommitmentRules.reports(email,from:store.permittedRecords).map(\.id)) == [email.id,moved.id],"Superseded versions never re-enter current plan reports")
        let remaining=MemoryDependencyRules.capture(store.context(account))
        allowed.remove("moved")
        precondition(CommitmentRules.reports(email,from:store.permittedRecords).map(\.id) == [email.id] && !MemoryDependencyRules.available(remaining,records:store.context(account)))
        precondition(store.records.first{$0.id == moved.id}?.resolved == nil,"Missing or disabled support never means completion")
        allowed.insert("moved")
        let cancellation=fact("cancelled",.mail,"Alex reports that the Orion draft is cancelled.",.cancelled,date:now.addingTimeInterval(-500))
        precondition(save([cancellation]))
        precondition(CommitmentRules.reports(cancellation,from:store.permittedRecords).count == 1,"A cross-email cancellation cannot automatically override a WhatsApp plan")
        var correction=moved;correction.id=UUID();correction.text="I am responsible for Monday's review, not the Friday draft.";correction.source=nil;correction.supportingSources=nil;correction.sourceState=nil;correction.explicit=true;correction.evidence=correction.text
        precondition(store.correct(moved.id,with:correction))
        correction=store.records.first{$0.id == correction.id}!
        precondition(correction.commitmentGroup == group && CommitmentRules.reports(email,from:store.permittedRecords).map(\.id).contains(correction.id))
        precondition(store.disconnectCommitment(correction.id,registration:account,expectedRevision:store.revision))
        precondition(store.records.first{$0.id == correction.id}?.commitmentGroup == nil && CommitmentRules.reports(email,from:store.permittedRecords).count == 1)
        precondition(store.restoreVersion(moved.id))
        let restored=store.records.first{$0.supersedes == correction.id}!
        precondition(restored.commitmentGroup == nil,"Restoring history cannot silently restore a disconnected group")
        var reclassified=restored;reclassified.id=UUID();reclassified.kind = .context
        precondition(store.correct(restored.id,with:reclassified) && store.records.first{$0.id == reclassified.id}?.commitmentGroup == nil)
        var otherAccount=cancellation;otherAccount.id=UUID();otherAccount.registration="different"
        var otherScope=cancellation;otherScope.id=UUID();otherScope.conversationID=UUID()
        precondition(store.put(otherAccount) && store.put(otherScope))
        precondition(!store.connectCommitments(email.id,otherAccount.id,registration:account,expectedRevision:store.revision) && !store.connectCommitments(email.id,otherScope.id,registration:account,expectedRevision:store.revision))
        // Connected recall must find differently-worded reports beyond the ordinary 40-fact cap.
        var human=PAMemory(registration:account,text:"I will prepare the optical demonstrator.",kind:.commitment,provenance:"Fictional human")
        precondition(store.put(human) && store.connectCommitments(email.id,human.id,registration:account,expectedRevision:store.revision))
        human=store.records.first{$0.id == human.id}!
        let revisionBefore=store.records.first{$0.id == email.id}!.commitmentGroupRevision
        precondition(store.setOrganisation(email.id,value:.init(areas:[.administration],connections:[])) && store.records.first{$0.id == email.id}?.commitmentGroupRevision == revisionBefore,"Classification cannot revise a plan's evidence")
        for index in 0..<45 { precondition(store.put(.init(registration:account,text:"Unrelated fictional context \(index)",kind:.context,provenance:"Fictional"))) }
        let selected=store.selection(account,query:"optical demonstrator")
        precondition(selected.records.contains{$0["id"] == email.id.uuidString} && selected.reasons[email.id]?.contains("Same plan as another relevant report, connected by you") == true)
        precondition(store.forget(human.id) && CommitmentRules.reports(email,from:store.permittedRecords).count == 1,"Forget removes its own lineage without deleting the other report")
        var expired=cancellation;expired.id=UUID();expired.reviewed=now.addingTimeInterval(-91*86400)
        precondition(!CommitmentRules.linkable(email,expired))
        let a=PAMemory(registration:account,text:"Plan A",kind:.commitment,provenance:"Fictional",commitmentGroup:UUID())
        let b=PAMemory(registration:account,text:"Plan B",kind:.commitment,provenance:"Fictional",commitmentGroup:UUID())
        precondition(!CommitmentRules.linkable(a,b),"Two established plan groups require separate review, not an implicit group merge")
        let projection=CommitmentRules.context((0..<40).map{_ in ["id":UUID().uuidString,"kind":"commitment","scope":"shared","sourceReportedState":"cancelled; attributed report"]},maxBytes:1800)
        let projectionBytes=try JSONSerialization.data(withJSONObject:projection).count
        precondition(projectionBytes <= 1800)
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(email)) as! [String:Any];legacy.removeValue(forKey:"commitmentGroup")
        let decoded=try JSONDecoder().decode(PAMemory.self,from:JSONSerialization.data(withJSONObject:legacy))
        precondition(decoded.commitmentGroup == nil)
        let mailItem=NativeLearningItem(identity:cancellation.source!.identity,revision:"v1",label:"Fictional Mail",text:cancellation.text,date:now,changed:now)
        let output=try JSONSerialization.data(withJSONObject:["facts":[["itemID":mailItem.id,"text":cancellation.text,"quote":cancellation.text,"kind":"commitment","areas":[],"state":"cancelled"]]])
        precondition(NativeLearningRules.decode(String(decoding:output,as:UTF8.self),items:[mailItem],candidates:[],registration:account,now:now)?.first?.sourceState == .cancelled)
        let invalid=String(decoding:output,as:UTF8.self).replacingOccurrences(of:"commitment",with:"context")
        precondition(NativeLearningRules.decode(invalid,items:[mailItem],candidates:[],registration:account,now:now) == nil)
        // Same counted canonical workspace items appear on opening an area, including item-only areas.
        let folder=try workspace.save(.init(registration:account,kind:.section,title:"Ideas",areas:[.projects]),expected:nil)
        var note=try workspace.save(.init(registration:account,kind:.resource,title:"Experiment notes",parentID:folder.id,notes:"Fictional project notes."),expected:nil)
        let notebook=LifeNotebook.build([],registration:account).integrating(workspace.items(account),links:[])
        precondition(Set(LifeAreaWorkspace.items(.projects,notebook:notebook,items:workspace.items(account)).map(\.id)) == [folder.id,note.id])
        precondition(notebook.notes.contains{$0.area == .projects && $0.records.isEmpty})
        note=try workspace.save({var changed=note;changed.title="Revised notes";return changed}(),expected:note.revision)
        precondition(LifeAreaWorkspace.items(.projects,notebook:notebook,items:workspace.items(account)).contains{$0.id == note.id && $0.title == "Revised notes"})
        precondition(workspace.items(account).count == 2 && store.records.first{$0.id == completed.id}?.resolved == nil,"Plan linking does not create workspace content or complete native tasks")
        print("PASS: cross-source abstention, explicit same-plan connection, mixed reports, scoped persistence, source version inheritance, correction/disconnection/Forget, bounded recall, native report states and exact Life map items")
    }
}
