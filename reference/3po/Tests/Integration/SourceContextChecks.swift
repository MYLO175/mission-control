import Foundation
@main struct Checks {
    static func main() throws {
        let now=Date(timeIntervalSince1970:2_000_000_000)
        let message=WhatsAppReadMessage(id:"one",chat:"family",sender:"participant",text:"Alex is starting a robotics project next week.",sentByMe:false,time:now.timeIntervalSince1970*1000)
        let other=WhatsAppReadMessage(id:"one",chat:"excluded",sender:"participant",text:"Secret unrelated text",sentByMe:false,time:message.time)
        let chats=[WhatsAppChat(id:"family",name:"The Nest",group:true)]
        let recent=SourceContextRules.recent([message,other],chats:chats,allowed:["family"],now:now)
        precondition(recent.count == 1 && recent[0].itemID == "one")
        let both=SourceContextRules.recent([message,other],chats:chats,allowed:["family","excluded"],now:now)
        precondition(Set(both.map(\.id)).count == 2,"Identical message IDs in different chats stay separate")
        let output:[String:Any]=["facts":[["messageID":recent[0].id,"text":"A message mentions Alex starting a robotics project.","quote":message.text,"kind":"context","areas":["projects"]]]]
        func json(_ value:[String:Any])->String { String(data:try! JSONSerialization.data(withJSONObject:value),encoding:.utf8)! }
        let facts=SourceContextRules.decode(json(output),messages:recent,registration:"owner",linkedIdentity:"linked",now:now)!
        precondition(facts.count == 1 && !facts[0].explicit && facts[0].certainty == .inferred && facts[0].durability == .situational && facts[0].sourceTurnID == nil)
        precondition(facts[0].source?.identity.itemID == "one" && facts[0].source?.identity.linkedIdentity == "linked")
        precondition(facts[0].organisation?.areas == [.projects])
        var wrong=output
        wrong["facts"]=[["messageID":"invented","text":"Unknown","quote":message.text,"kind":"context","areas":["projects"]]]
        precondition(SourceContextRules.decode(json(wrong),messages:recent,registration:"owner",linkedIdentity:"linked",now:now) == nil)
        wrong["facts"]=[["messageID":recent[0].id,"text":"Unsupported","quote":"Fabricated quotation","kind":"context","areas":["projects"]]]
        precondition(SourceContextRules.decode(json(wrong),messages:recent,registration:"owner",linkedIdentity:"linked",now:now) == nil)
        wrong["facts"]=[["messageID":recent[0].id,"text":"Unsupported preference","quote":message.text,"kind":"preference","areas":["about"]]]
        precondition(SourceContextRules.decode(json(wrong),messages:recent,registration:"owner",linkedIdentity:"linked",now:now) == nil)
        precondition(SourceContextRules.decode(json(output),messages:recent,registration:"owner",linkedIdentity:"",now:now) == nil)
        let access=WhatsAppAccess(enabled:true,chats:["family"],learnContext:true)
        precondition(SourceContextRules.permitted(facts[0],access:access,linkedIdentity:"linked",messages:[message]))
        precondition(!SourceContextRules.permitted(facts[0],access:.init(enabled:true,chats:["family"]),linkedIdentity:"linked",messages:[message]))
        precondition(!SourceContextRules.permitted(facts[0],access:access,linkedIdentity:"other-linked",messages:[message]))
        precondition(!SourceContextRules.permitted(facts[0],access:access,linkedIdentity:"linked",messages:[]))
        let progress=SourceContextProgress(seen:[recent[0].id:recent[0].revision])
        precondition(SourceContextRules.batch(recent,progress:progress).isEmpty)
        let edited=WhatsAppReadMessage(id:message.id,chat:message.chat,sender:message.sender,text:message.text+" Changed",sentByMe:false,time:message.time)
        precondition(SourceContextRules.revision(edited) != SourceContextRules.revision(message))
        precondition(SourceContextRules.recent([edited],chats:chats,allowed:["family"],now:now)[0].id == recent[0].id)
        precondition(SourceContextRules.batch(SourceContextRules.recent([edited],chats:chats,allowed:["family"],now:now),progress:progress).count == 1)
        let expired=WhatsAppReadMessage(id:"old",chat:"family",sender:"participant",text:message.text,sentByMe:false,time:now.addingTimeInterval(-49*3600).timeIntervalSince1970*1000)
        precondition(SourceContextRules.recent([expired],chats:chats,allowed:["family"],now:now).isEmpty)
        let input=try SourceContextRules.input(recent,existing:Array(repeating:["text":String(repeating:"界",count:5000)],count:12))
        precondition(input.utf8.count <= 24000)
        var long=recent[0];long.text=String(repeating:"界",count:1200)
        precondition(SourceContextRules.batch(Array(repeating:long,count:8),progress:.init()).count <= 3)
        let backlog=(0..<24).map{index in WhatsAppReadMessage(id:"backlog-\(index)",chat:index == 23 ? "quiet" : "busy",sender:"participant",text:"A concrete project update \(index)",sentByMe:false,time:now.addingTimeInterval(Double(-index)).timeIntervalSince1970*1000)}
        let backlogRecent=SourceContextRules.recent(backlog,chats:[],allowed:["busy","quiet"],now:now)
        var queued=SourceContextRules.collecting(.init(),recent:backlogRecent,now:now)
        precondition(queued.coverage?.pending.count == 24 && queued.seen.isEmpty)
        let firstBatch=SourceContextRules.batch(backlogRecent,progress:queued)
        precondition(firstBatch.count == 8 && firstBatch.contains{$0.chatID == "quiet"},"Busy chats cannot starve a quiet selected chat")
        queued=SourceContextRules.completing(queued,batch:firstBatch,now:now)
        precondition(queued.seen.count == 8 && queued.coverage?.pending.count == 16,"Only assessed versions advance")
        let persisted=try JSONDecoder().decode(SourceContextProgress.self,from:JSONEncoder().encode(queued))
        precondition(persisted.coverage?.pending.count == 16)
        for _ in 0..<2 {
            queued=SourceContextRules.collecting(queued,recent:backlogRecent,now:now)
            queued=SourceContextRules.completing(queued,batch:SourceContextRules.batch(backlogRecent,progress:queued),now:now)
        }
        precondition(queued.seen.count == 24 && queued.coverage?.pending.isEmpty == true)
        let legacy=SourceContextRules.collecting(.init(seen:[recent[0].id:recent[0].revision],oriented:true),recent:recent,now:now)
        precondition(legacy.seen.isEmpty && legacy.coverage?.baseline.count == 1 && SourceContextRules.batch(recent,progress:legacy).isEmpty,"Old orientation stays excluded but is not labelled assessed")
        let unavailable=SourceContextRules.collecting(persisted,recent:[],now:now)
        precondition(unavailable.coverage?.pending.isEmpty == true && unavailable.coverage?.unavailable == 16)
        var paused=persisted;paused.paused=true
        let roundtrip=try JSONDecoder().decode(SourceContextProgress.self,from:JSONEncoder().encode(paused))
        precondition(roundtrip.paused && roundtrip.coverage?.pending.count == 16,"Interrupted work keeps its pending references")
        var tracked=roundtrip
        tracked.learningAccess = .init(permitted:true,chats:Set(["busy","quiet"].map(SourceContextRules.chatKey)),revision:UUID())
        let newlyAdmitted=SourceContextMessage(id:"opaque-new-chat-message",itemID:"older-message",chatID:"new-chat",chatName:"New fictional chat",sender:"fictional",sentByMe:false,text:"An old responsibility from a newly selected chat",date:now.addingTimeInterval(-3600),revision:"one")
        let expandedAccess=SourceContextLearningAccess(permitted:true,chats:Set(["busy","quiet","new-chat"].map(SourceContextRules.chatKey)),revision:UUID())
        let collectedExpanded=SourceContextRules.collecting(tracked,recent:backlogRecent+[newlyAdmitted],now:now)
        let expanded=SourceContextRules.reconcilingAccess(collectedExpanded,previous:tracked,current:expandedAccess,recent:backlogRecent+[newlyAdmitted])
        precondition(expanded.paused && expanded.coverage?.pending.count == tracked.coverage?.pending.count,"Scope expansion preserves exact old pending versions and the interrupted-claim pause")
        precondition(SourceContextRules.batch([newlyAdmitted],progress:expanded).isEmpty,"Newly admitted cached history is baseline, not automatic work")
        precondition(SourceContextRules.batch([newlyAdmitted],progress:expanded,manual:true).count == 1,"Explicit Review once may inspect a bounded baseline batch")
        let expandedReload=try JSONDecoder().decode(SourceContextProgress.self,from:JSONEncoder().encode(expanded))
        precondition(expandedReload.learningAccess == expandedAccess && expandedReload.coverage?.pending.count == 16 && expandedReload.paused,"Opaque access boundaries, pending work and paused claims survive reopening")
        let many=(0..<250).map{index in WhatsAppReadMessage(id:"many-\(index)",chat:"busy",sender:"participant",text:"Update \(index)",sentByMe:false,time:now.addingTimeInterval(Double(-index)).timeIntervalSince1970*1000)}+backlog.filter{$0.chat == "quiet"}
        let fairWindow=SourceContextRules.recent(many,chats:[],allowed:["busy","quiet"],now:now)
        precondition(fairWindow.count == 200 && fairWindow.contains{$0.chatID == "quiet"})
        let fullWindow=SourceContextRules.recent(many,chats:[],allowed:["busy","quiet"],now:now,limit:2000)
        precondition(fullWindow.count == 251)
        let fullQueue=SourceContextRules.collecting(.init(),recent:fullWindow,now:now)
        let newer=many+[WhatsAppReadMessage(id:"newer",chat:"busy",sender:"participant",text:"Newest update",sentByMe:false,time:now.timeIntervalSince1970*1000)]
        let changedWindow=SourceContextRules.recent(newer,chats:[],allowed:["busy","quiet"],now:now,limit:2000)
        let retainedQueue=SourceContextRules.collecting(fullQueue,recent:changedWindow,now:now)
        precondition(retainedQueue.coverage?.pending.count == 252 && retainedQueue.coverage?.unavailable == 0,"Available references are not evicted by the smaller inference sample")
        let encodedPending=String(decoding:try JSONEncoder().encode(retainedQueue.coverage!.pending),as:UTF8.self)
        precondition(!encodedPending.contains("busy") && !encodedPending.contains("quiet") && !encodedPending.contains("text") && !encodedPending.contains("date"),"Pending storage uses opaque references only")
        let legacyKey="account:linked-phone-identity",safeKey=SourceContextRules.scopeKey(legacyKey)
        let protected=SourceContextState(scopes:[legacyKey:persisted]).protectingScopeKeys()!
        precondition(protected[safeKey]?.coverage?.pending.count == 16 && protected[legacyKey] == nil)
        precondition(SourceContextState(scopes:protected).protectingScopeKeys()!.keys.first == safeKey,"Opaque scope keys do not rehash on reload")
        precondition(SourceContextState(scopes:[legacyKey:persisted,safeKey:persisted]).protectingScopeKeys() == nil,"Conflicting legacy and protected scopes preserve the original store rather than overwrite")
        var old=facts[0];old.reviewed=now.addingTimeInterval(-91*86400)
        precondition(!MemoryRules.usable(old,registration:"owner",now:now),"Source-derived beliefs age out even if incorrectly marked stable")
        old.durability = .stable;old.certainty = .stated
        precondition(!MemoryRules.usable(old,registration:"owner",now:now))
        let day=BriefingRules.day(now)
        precondition(!LearningBudgetRules.allowed(.init(day:day,attempts:4,lastAttempt:now.addingTimeInterval(-3600)),now:now))
        precondition(!LearningBudgetRules.allowed(.init(day:day,attempts:1,lastAttempt:now),now:now))
        precondition(LearningBudgetRules.allowed(.init(day:"old",attempts:4,lastAttempt:now.addingTimeInterval(-3600)),now:now))
        print("PASS: selected chats, linked identity, scoped revisions, bounded deltas/input, provisional attribution, invalid evidence, expiry and shared quota")
    }
}
