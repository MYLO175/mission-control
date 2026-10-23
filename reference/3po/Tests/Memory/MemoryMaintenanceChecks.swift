import Foundation

@main struct Checks {
    static func main()throws {
        let now=Date.now,registration="fictional"
        let old=PAMemory(registration:registration,text:"I might stop the temporary Orion reading group.",kind:.context,explicit:false,provenance:"Fictional interpretation",created:now.addingTimeInterval(-110*86400),reviewed:now.addingTimeInterval(-100*86400),evidence:"I'm considering leaving the Orion reading group.",certainty:.inferred,durability:.situational)
        let stated=PAMemory(registration:registration,text:"My Orion project has twelve sensors.",kind:.context,provenance:"Fictional human",evidence:"My Orion project has twelve sensors.",certainty:.stated,durability:.stable)
        var duplicate=stated;duplicate.id=UUID()
        var conflict=stated;conflict.id=UUID();conflict.text="My Orion project has sixteen sensors."
        let records=[old,stated,duplicate,conflict]
        func json(_ kind:String,_ ids:[UUID])->String { String(decoding:try! JSONSerialization.data(withJSONObject:["proposals":[["kind":kind,"recordIDs":ids.map(\.uuidString),"reason":"Check these particular facts against their original evidence."]]]),as:UTF8.self) }
        let retire=MemoryReviewRules.decode(json("retirement",[old.id]),records:records,registration:registration,now:now)!.first!
        precondition(MemoryReviewRules.current(retire,records:records,registration:registration))
        let duplicateProposal=MemoryReviewRules.decode(json("duplicate",[stated.id,duplicate.id]),records:records,registration:registration,now:now)!.first!
        precondition(MemoryReviewRules.decode(json("conflict",[stated.id,conflict.id]),records:records,registration:registration,now:now)?.count == 1)
        precondition(MemoryReviewRules.decode(json("retirement",[stated.id]),records:records,registration:registration,now:now) == nil)
        var pinned=old;pinned.organisation = .init(areas:[.interests],connections:[],manual:true)
        precondition(MemoryReviewRules.decode(json("retirement",[old.id]),records:[pinned],registration:registration,now:now) == nil)
        var commitment=old;commitment.kind = .commitment
        precondition(MemoryReviewRules.decode(json("retirement",[old.id]),records:[commitment],registration:registration,now:now) == nil)
        var stable=old;stable.durability = .stable
        precondition(MemoryReviewRules.decode(json("retirement",[old.id]),records:[stable],registration:registration,now:now) == nil)
        var recent=old;recent.reviewed=now
        precondition(MemoryReviewRules.decode(json("retirement",[old.id]),records:[recent],registration:registration,now:now) == nil)
        var otherScope=duplicate;otherScope.conversationID=UUID()
        precondition(MemoryReviewRules.decode(json("duplicate",[stated.id,duplicate.id]),records:[stated,otherScope],registration:registration,now:now) == nil)
        var changed=stated;changed.text="Corrected current statement."
        precondition(!MemoryReviewRules.current(duplicateProposal,records:[changed,duplicate],registration:registration))
        var retired=old;retired.retiredAt=now
        precondition(!MemoryReviewRules.current(retire,records:[retired],registration:registration))
        precondition(!MemoryReviewRules.current(retire,records:records,registration:"other"))
        precondition(MemoryReviewRules.decode(json("duplicate",[stated.id,UUID()]),records:records,registration:registration,now:now) == nil)
        let snapshot=records
        let first=MemoryReviewRules.batch(records,registration:registration,progress:.init(),manual:false,now:now)
        precondition(first.first?.id == old.id && first.count <= 24 && records == snapshot,"Review flags old provisional context without mutating facts")
        var progress=MemoryReviewProgress();progress.inspected=Dictionary(uniqueKeysWithValues:records.map{($0.id,MemoryReviewRules.fingerprint($0))})
        precondition(MemoryReviewRules.batch(records,registration:registration,progress:progress,manual:false,now:now).isEmpty)
        precondition(MemoryReviewRules.batch(records,registration:registration,progress:progress,manual:true,now:now).count == records.count)
        let replay=try JSONDecoder().decode(MemoryReviewProposal.self,from:JSONEncoder().encode(retire))
        precondition(replay.fingerprints == retire.fingerprints)
        let reverse=MemoryReviewRules.decode(json("duplicate",[duplicate.id,stated.id]),records:records,registration:registration,now:now)!.first!
        precondition(reverse.id == duplicateProposal.id,"Dismissal identity is independent of model order/reason phrasing")
        print("PASS bounded memory review, exact revision/account/scope gates, retirement protections, stable dismissal identities and no fact mutation")
    }
}
