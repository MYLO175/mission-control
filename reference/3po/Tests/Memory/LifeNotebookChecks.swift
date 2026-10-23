import Foundation
@main struct Checks {
    static func main() throws {
        let now=Date(timeIntervalSince1970:2_000_000_000),topic=UUID(),otherTopic=UUID()
        func fact(_ text:String,_ subject:String,_ relation:String,_ object:String,_ areas:[LifeArea],_ a:LifeEntityKind,_ b:LifeEntityKind,selfSubject:Bool=false,selfName:String?=nil)->PAMemory {
            PAMemory(registration:"owner",text:text,kind:.context,provenance:"Synthetic human fixture",created:now,reviewed:now,evidence:text,certainty:.stated,durability:.stable,connections:[.init(subject:subject,relation:relation,object:object,evidence:text)],organisation:.init(areas:areas,connections:[.init(connection:"0",subjectKind:a,objectKind:b,subjectIsSelf:selfSubject,objectIsSelf:false)],selfName:selfName))
        }
        let identity=fact("My name is Alex.","You","is named","Alex",[.about],.person,.concept,selfSubject:true,selfName:"Alex")
        let study=fact("I study Materials Engineering.","Alex","studies","Materials Engineering",[.studies],.person,.course,selfSubject:true)
        let project=fact("I am building Signal Garden.","You","builds","Signal Garden",[.projects,.studies],.person,.project,selfSubject:true)
        let aim=fact("Signal Garden supports my goal of shipping useful hardware.","Signal Garden","supports","Shipping useful hardware",[.projects,.career],.project,.goal)
        let value=fact("Shipping useful hardware means full lifecycle ownership for me.","Shipping useful hardware","requires","Full lifecycle ownership",[.about,.career],.goal,.value)
        let habit=fact("I want a consistent meditation habit.","Me","practises","Meditation",[.wellbeing],.person,.habit,selfSubject:true)
        let family=fact("My family chat is The Nest.","You","family chat","The Nest",[.people],.person,.group,selfSubject:true)
        let contact=fact("My football teammate is also called Alex.","You","football teammate","Alex",[.people,.interests],.person,.person,selfSubject:true)
        let otherContact=fact("My lab partner is called Alex.","You","lab partner","Alex",[.people,.studies],.person,.person,selfSubject:true)
        let namedYou=fact("A friend has the nickname You.","You","nickname of","Old friend",[.people],.person,.concept)
        var foreign=study;foreign.id=UUID();foreign.registration="other account"
        var privateTopic=project;privateTopic.id=UUID();privateTopic.conversationID=otherTopic
        var scoped=habit;scoped.id=UUID();scoped.conversationID=topic
        var resolved=aim;resolved.id=UUID();resolved.resolved=now
        var expired=study;expired.id=UUID();expired.explicit=false;expired.certainty = .inferred;expired.reviewed=now.addingTimeInterval(-91*86400)
        var legacy=project;legacy.id=UUID();legacy.organisation=nil
        let facts=[identity,study,project,aim,value,habit,family,contact,otherContact,namedYou,foreign,privateTopic,scoped,resolved,expired,legacy]
        let notebook=LifeNotebook.build(facts,registration:"owner",now:now)
        precondition(notebook.selfLabel == "Alex")
        precondition(notebook.entities.filter{$0.id == LifeNotebook.selfID}.count == 1)
        precondition(notebook.links.first(where:{$0.memoryID == study.id})?.from == LifeNotebook.selfID,"Supported named self merges with first person")
        precondition(notebook.entities.filter{$0.label == "Alex" && $0.id != LifeNotebook.selfID && $0.kind == .person}.count == 2,"Same name contacts stay distinct")
        precondition(notebook.links.first(where:{$0.memoryID == namedYou.id})?.from != LifeNotebook.selfID,"Typed not-self overrides a pronoun-like contact label")
        precondition(notebook.entities.contains{$0.kind == .habit && $0.label == "Meditation"})
        precondition(notebook.entities.contains{$0.kind == .goal && $0.label == "Shipping useful hardware"})
        precondition(notebook.entities.contains{$0.kind == .value && $0.label == "Full lifecycle ownership"})
        precondition(notebook.entities.first(where:{$0.label == "Signal Garden" && $0.kind == .project})?.memoryIDs == [project.id,aim.id])
        precondition(notebook.notes.first(where:{$0.area == .projects})?.records.contains(where:{$0.id == project.id}) == true)
        precondition(notebook.notes.first(where:{$0.area == .studies})?.records.contains(where:{$0.id == project.id}) == true)
        precondition(notebook.notes.first(where:{$0.area == .unsorted})?.records.contains(where:{$0.id == legacy.id}) == true)
        precondition(notebook.links.allSatisfy{![foreign.id,privateTopic.id,scoped.id,resolved.id,expired.id].contains($0.memoryID)})
        precondition(notebook.links.first(where:{$0.memoryID == family.id})?.evidence == family.evidence)
        precondition(notebook.links.map(\.id) == LifeNotebook.build(facts.reversed(),registration:"owner",now:now).links.map(\.id))
        let focused=LifeNotebook.build(facts,registration:"owner",topic:topic,now:now)
        precondition(focused.links.contains{$0.memoryID == scoped.id} && !focused.links.contains{$0.memoryID == privateTopic.id})
        precondition(!LifeNotebook.build(facts.filter{$0.id != identity.id},registration:"owner",now:now).selfLabel.contains("Alex"),"A named contact never supplies owner identity")
        let noise=(0..<50).map { i in fact("I enjoy unrelated activity \(i).","You","enjoys","Unrelated activity \(i)",[.interests],.person,.interest,selfSubject:true) }
        let retrieval=MemoryRetrieval.select([project,aim,value]+noise,registration:"owner",query:"Signal Garden",now:now,limit:3)
        precondition(Set(retrieval.records.compactMap{$0["id"]}) == [project.id.uuidString,aim.id.uuidString,value.id.uuidString],"Useful two-hop connection outranks unrelated self links")
        let studyFocus=MemoryRetrieval.select(noise+[study],registration:"owner",query:nil,now:now,limit:1,focus:[.studies])
        precondition(studyFocus.records.first?["id"] == study.id.uuidString)
        precondition(MemoryRetrieval.select(noise+[study],registration:"owner",query:"",now:now,focus:[.studies]).records.isEmpty,"Only null asks for broad orientation; Focus cannot widen a targeted query")
        let outside=MemoryRetrieval.select(noise+[family,study],registration:"owner",query:"The Nest family",now:now,limit:1,focus:[.studies])
        precondition(outside.records.first?["id"] == family.id.uuidString,"Area focus does not exclude a relevant shared fact")
        for bound in [2,300,1000,8000] {
            let context=notebook.context(query:"Signal Garden",focus:[.projects],maxBytes:bound)
            precondition(context.utf8.count <= bound)
            _=try JSONSerialization.jsonObject(with:Data(context.utf8))
        }
        let parsed=try JSONSerialization.jsonObject(with:Data(notebook.context(query:"Signal Garden").utf8)) as! [String:Any]
        let noteIDs=(parsed["areas"] as? [[String:Any]] ?? []).flatMap{$0["facts"] as? [[String:String]] ?? []}.compactMap{$0["id"]}
        precondition(noteIDs.contains(project.id.uuidString) && !noteIDs.contains(privateTopic.id.uuidString))
        precondition(!noteIDs.contains(study.id.uuidString) && !noteIDs.contains(habit.id.uuidString) && !noteIDs.contains(family.id.uuidString),"Notebook context must not reintroduce irrelevant facts")
        let security=try JSONSerialization.jsonObject(with:Data(notebook.context(query:"Alex Google sign-in security alert",focus:[.studies]).utf8)) as! [String:Any]
        precondition((security["areas"] as? [[String:Any]] ?? []).isEmpty,"User identity and area focus must not refill a targeted check")
        let capped=try JSONSerialization.jsonObject(with:Data(notebook.context(query:"Signal Garden",selectedMemoryIDs:[project.id]).utf8)) as! [String:Any]
        let cappedIDs=Set((capped["areas"] as? [[String:Any]] ?? []).flatMap{$0["facts"] as? [[String:String]] ?? []}.compactMap{$0["id"]})
        precondition(cappedIDs == [project.id.uuidString],"Notebook shares the actual selection budget instead of supplying additional two-hop facts")
        var bad=study.organisation!;bad.connections[0].subjectKind = .goal
        precondition(!LifeMemoryOrganisation.valid(bad,record:study))
        bad=study.organisation!;bad.areas=[.about,.studies,.career,.projects]
        precondition(!LifeMemoryOrganisation.valid(bad,record:study))
        bad=study.organisation!;bad.connections[0].connection="3"
        precondition(!LifeMemoryOrganisation.valid(bad,record:study))
        bad=identity.organisation!;bad.selfName="Unstated"
        precondition(!LifeMemoryOrganisation.valid(bad,record:identity))
        var privateName=identity;privateName.conversationID=topic
        precondition(!LifeMemoryOrganisation.valid(identity.organisation!,record:privateName))
        let entry=LifeOrganisationEntry(id:study.id,organisation:study.organisation!)
        func response(_ entries:[LifeOrganisationEntry]) throws -> String { struct Response:Encodable { let entries:[LifeOrganisationEntry] };return String(data:try JSONEncoder().encode(Response(entries:entries)),encoding:.utf8)! }
        let validResponse=try response([entry]),duplicateResponse=try response([entry,entry])
        precondition(LifeOrganisationRules.decode(validResponse,records:[study])?.count == 1)
        precondition(LifeOrganisationRules.decode(duplicateResponse,records:[study]) == nil)
        precondition(LifeOrganisationRules.decode(validResponse,records:[identity]) == nil)
        var pinned=entry;pinned.organisation.manual=true
        let pinnedResponse=try response([pinned]);precondition(LifeOrganisationRules.decode(pinnedResponse,records:[study]) == nil)
        var oldJSON=try JSONSerialization.jsonObject(with:JSONEncoder().encode(study)) as! [String:Any];oldJSON.removeValue(forKey:"organisation")
        let oldDecoded=try JSONDecoder().decode(PAMemory.self,from:JSONSerialization.data(withJSONObject:oldJSON)),roundtrip=try JSONDecoder().decode(PAMemory.self,from:JSONEncoder().encode(project))
        precondition(oldDecoded.organisation == nil);precondition(roundtrip == project)
        var progress=LifeOrganisationProgress()
        precondition(LifeOrganisationBatch.records(facts,registration:"owner",topic:nil,progress:progress,now:now).map(\.id) == [legacy.id])
        progress.inspected[legacy.id]=legacy.reviewed
        precondition(LifeOrganisationBatch.records([legacy],registration:"owner",topic:nil,progress:progress,now:now).isEmpty)
        legacy.reviewed=now.addingTimeInterval(5)
        precondition(LifeOrganisationBatch.records([legacy],registration:"owner",topic:nil,progress:progress,now:now).count == 1)
        progress.day=LifeOrganisationBatch.day(now);progress.attempts=2
        precondition(!LifeOrganisationBatch.allowed(progress,now:now,manual:false))
        precondition(LifeOrganisationBatch.allowed(progress,now:now,manual:true))
        progress.attempts=0;progress.paused=true
        precondition(!LifeOrganisationBatch.allowed(progress,now:now.addingTimeInterval(86400),manual:false),"Interrupted jobs do not replay the next day")
        let general=UUID(),other=UUID()
        var oldTopic=PAMemory(registration:"owner",text:"Scoped old study fact",kind:.context,provenance:"fixture",organisation:.init(areas:[.studies],connections:[]));oldTopic.conversationID=general
        var foreignFocus=oldTopic;foreignFocus.id=UUID();foreignFocus.registration="other";foreignFocus.conversationID=other
        precondition(LifeNotebook.build([oldTopic,foreignFocus],registration:"owner").notes.isEmpty)
        precondition(LifeNotebook.build([oldTopic,foreignFocus],registration:"owner",includeTopics:true).notes.flatMap(\.records).map(\.id) == [oldTopic.id])
        precondition(MemoryRetrieval.select([oldTopic,foreignFocus],registration:"owner",includeTopics:true,query:"study",focus:[.studies,.career]).records.count == 1)
        precondition(LifeFocusRules.normalised(["career","studies","career","bad"]) == [.studies,.career])
        print("PASS: canonical self, distinct contacts, typed goals/habits/projects, cross-area notes, scoped evidence, two-hop recall without self spillover, topic bias, exact byte bounds, metadata validation, legacy decode and bounded paused organisation")
    }
}
