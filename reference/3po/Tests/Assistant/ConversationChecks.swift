import Foundation
@main struct Checks {
    @MainActor static func main() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"accountID\":\"one\",\"title\":\"Old topic\",\"created\":0,\"turns\":[{\"id\":\"00000000-0000-0000-0000-000000000002\",\"role\":\"user\",\"content\":\"Hello\",\"completed\":true}]}".utf8)
        var chat = try JSONDecoder().decode(AssistantConversation.self,from:legacy)
        precondition(chat.isPrimary == nil && chat.turns[0].deliveryID == nil && chat.turns[0].created == nil)
        let key = ConversationRules.morningKey(registration:"one",day:"2026-10-02")
        precondition(!ConversationRules.hasDelivery([chat],registration:"one",key:key))
        chat.turns.append(AssistantTurn(role:"assistant",content:"Briefing",completed:true,deliveryID:key)); chat.isPrimary = true
        let saved = try JSONDecoder().decode(AssistantConversation.self,from:JSONEncoder().encode(chat))
        precondition(ConversationRules.hasDelivery([saved],registration:"one",key:key))
        precondition(!ConversationRules.hasDelivery([saved],registration:"two",key:key))
        precondition(!ConversationRules.hasDelivery([saved],registration:"one",key:ConversationRules.morningKey(registration:"one",day:"2026-10-03")))
        precondition(saved.isPrimary == true && saved.turns.count == 2)
        precondition(saved.turns[0].created == nil && saved.turns[1].created != nil)
        var topic = AssistantConversation(accountID:"one",title:"Topic")
        topic.created = saved.created.addingTimeInterval(20)
        var other = AssistantConversation(accountID:"two",title:"Other account"); other.isPrimary = true
        precondition(ConversationRules.selection(topic.id,in:[saved,topic,other],registration:"one") == topic.id)
        precondition(ConversationRules.selection(other.id,in:[saved,topic,other],registration:"one") == saved.id)
        precondition(ConversationRules.selection(nil,in:[saved,topic,other],registration:"one") == saved.id)
        precondition(ConversationRules.selection(nil,in:[saved,topic,other],registration:"unknown") == nil)
        let widget = UUID(), otherWidget = UUID()
        let keys = [ChatDraftRules.key(registration:"one",widget:widget,conversation:saved.id),ChatDraftRules.key(registration:"one",widget:otherWidget,conversation:saved.id),ChatDraftRules.key(registration:"one",widget:widget,conversation:topic.id),ChatDraftRules.key(registration:"two",widget:widget,conversation:saved.id)]
        precondition(Set(keys).count == 4)
        var drafts = ChatDraftState(); drafts.values[keys[0]] = "Draft"; drafts.values[keys[3]] = "   "
        precondition(ChatDraftRules.hasDraft(drafts,registration:"one") && !ChatDraftRules.hasDraft(drafts,registration:"two"))
        let restored = try JSONDecoder().decode(ChatDraftState.self,from:JSONEncoder().encode(drafts))
        precondition(restored.values == drafts.values)
        precondition(chat.turns[0].contextID == nil && chat.isTopic == nil)
        topic.focus = "Engineering study"
        var archived = AssistantConversation(accountID:"one",title:"An old conversation")
        archived.turns = [.init(role:"user",content:"Archived private question",completed:true)]
        var secondTopic = AssistantConversation(accountID:"one",title:"Applications"); secondTopic.isTopic = true
        let all = [saved,topic,other,archived,secondTopic]
        precondition(Set(ConversationRules.topics(in:all,registration:"one").map(\.id)) == Set([topic.id,secondTopic.id]))
        precondition(ConversationRules.topicSelection(nil,legacy:topic.id,in:all,registration:"one") == topic.id)
        precondition(ConversationRules.topicSelection("",legacy:topic.id,in:all,registration:"one") == nil, "Explicit no-topic must not fall back to Study")
        precondition(ConversationRules.topicSelection(nil,legacy:archived.id,in:all,registration:"one") == nil)
        precondition(ConversationRules.topicSelection(topic.id.uuidString,legacy:nil,in:all,registration:"two") == nil)
        precondition(ConversationRules.topicSelection(UUID().uuidString,legacy:topic.id,in:all,registration:"one") == nil)
        var feed = saved
        feed.turns = (0..<25).map { .init(role:"user",content:"General \($0)",completed:true,created:Date(timeIntervalSince1970:Double($0))) }
        topic.turns = [.init(role:"user",content:"Existing Study context",completed:true,created:Date(timeIntervalSince1970:25))]
        let study = AssistantTurn(role:"user",content:"Study request",completed:true,created:Date(timeIntervalSince1970:26),contextID:topic.id)
        let studyReply = AssistantTurn(role:"assistant",content:"Study response",completed:true,created:Date(timeIntervalSince1970:27),contextID:topic.id)
        let otherMode = AssistantTurn(role:"user",content:"Another topic secret",completed:true,created:Date(timeIntervalSince1970:28),contextID:secondTopic.id)
        feed.turns += [study,studyReply,otherMode,.init(role:"assistant",content:"Partial",completed:false,created:Date(timeIntervalSince1970:29),contextID:topic.id)]
        let generalHistory = ConversationRules.history(feed:feed,topic:nil)
        let topicHistory = ConversationRules.history(feed:feed,topic:topic)
        precondition(generalHistory.count == 20 && generalHistory.allSatisfy { $0.contextID == nil })
        precondition(topicHistory.count == 3 && topicHistory.last?.id == studyReply.id)
        precondition(topicHistory.contains { $0.content == "Existing Study context" } && !topicHistory.contains { $0.id == otherMode.id || !$0.completed })
        precondition(ConversationRules.context(for:study,in:feed) == topic.id)
        precondition(ConversationRules.context(for:feed.turns[0],in:feed) == nil)
        precondition(ConversationRules.context(for:topic.turns[0],in:topic) == topic.id)
        let roundTrip = try JSONDecoder().decode(AssistantConversation.self,from:JSONEncoder().encode(feed))
        precondition(roundTrip.turns.first { $0.id == studyReply.id }?.contextID == topic.id)
        precondition(feed.turns.count == 29, "Changing topics preserves stored messages")
        let studyThread = ConversationRules.thread(feed:feed,topic:topic)
        precondition(studyThread.count == 4 && studyThread.last?.completed == false)
        precondition(!studyThread.contains { $0.content.hasPrefix("General") || $0.id == otherMode.id })
        precondition(ConversationRules.thread(feed:feed,topic:nil).count == 25)
        precondition(ConversationRules.thread(feed:feed,topic:secondTopic).map(\.id) == [otherMode.id])
        precondition(ConversationRules.history(feed:feed,topic:secondTopic).contains { $0.id == otherMode.id })
        let hidden = AssistantTurn(role:"assistant",content:"Dismissed source",completed:true,deliveryID:"discovery:hidden",created:Date(timeIntervalSince1970:30))
        let morning = AssistantTurn(role:"assistant",content:"Old source scope",completed:true,deliveryID:"one:morning:old",created:Date(timeIntervalSince1970:31))
        var withSources = feed; withSources.turns += [hidden,morning]
        let filtered = ConversationRules.history(feed:withSources,topic:nil,excludedDeliveries:["discovery:hidden","one:morning:old"])
        precondition(filtered.count == 20 && !filtered.contains { $0.id == hidden.id || $0.id == morning.id })
        precondition(withSources.turns.contains { $0.id == hidden.id }, "Filtering inference never deletes the transcript")
        let current = AssistantTurn(role:"user",content:String(repeating:"🧠",count:3000),completed:true)
        let longHistory = (0..<19).map { _ in AssistantTurn(role:"assistant",content:String(repeating:"Older detailed response ",count:1000),completed:true) } + [current]
        let replay = ConversationRules.replay(longHistory,currentUserID:current.id)
        precondition(replay.last?["content"] == current.content && replay.count < longHistory.count && replay.count > 1)
        precondition(replay.first?["content"]?.contains("Earlier message excerpt") == true)
        let replayData = try JSONSerialization.data(withJSONObject:replay); precondition(replayData.count <= 24_000)
        precondition(ConversationRules.acceptsPrompt(current.content) && !ConversationRules.acceptsPrompt(String(repeating:"🧠",count:5000)))
        precondition(!ConversationRules.acceptsPrompt(String(repeating:"\n",count:16000)), "JSON escaping must fit before the draft is consumed")
        precondition(ConversationRules.utf8Prefix("🧠hello",bytes:3).isEmpty && ConversationRules.utf8Prefix("🧠hello",bytes:5) == "🧠h")
        precondition(longHistory[0].content.count > 3000 && longHistory.last?.content == current.content)
        let sourceID=UUID()
        let sourceReply=AssistantTurn(role:"assistant",content:"Source-backed answer",completed:true,sourceMemoryIDs:[sourceID])
        let normalReply=AssistantTurn(role:"assistant",content:"Human-backed answer",completed:true)
        precondition(ConversationRules.sourceMemoryHistory([sourceReply,normalReply],permitted:[sourceID]).count == 2)
        precondition(ConversationRules.sourceMemoryHistory([sourceReply,normalReply],permitted:[]).map(\.id) == [normalReply.id],"Removed/edited sources cannot return through later AI history")
        let sourceRoundTrip=try JSONDecoder().decode(AssistantTurn.self,from:JSONEncoder().encode(sourceReply))
        precondition(sourceRoundTrip.sourceMemoryIDs == [sourceID])
        var flooded=AssistantConversation(accountID:"one",title:"Protected dialogue")
        let origin=Date(timeIntervalSince1970:1700000000)
        let question=AssistantTurn(role:"user",content:"Help me plan Engineering",completed:true,created:origin)
        let proposal=AssistantTurn(role:"assistant",content:"Create a study project?",completed:true,created:origin.addingTimeInterval(1))
        flooded.turns=[question,proposal]
        for n in 0..<60 { flooded.turns.append(.init(role:"assistant",content:"Background update",completed:true,deliveryID:"discovery:"+String(n),created:origin.addingTimeInterval(Double(n+2)))) }
        let reply=AssistantTurn(role:"user",content:"Yes, do that",completed:true,created:origin.addingTimeInterval(3600))
        flooded.turns.append(reply)
        let protected=ConversationRules.history(feed:flooded,topic:nil)
        precondition(protected.contains{$0.id == question.id} && protected.contains{$0.id == proposal.id} && protected.last?.id == reply.id)
        precondition(protected.filter{$0.deliveryID != nil}.count == 4 && protected.count <= 20)
        let protectedReplay=ConversationRules.replay(protected,currentUserID:reply.id)
        precondition(protectedReplay.last?["content"] == reply.content)
        var later=reply;later.created=origin.addingTimeInterval(5*3600)
        precondition(ConversationRules.separator(before:later,previous:reply,previousHuman:question) != nil)
        var projectionFeed=(0..<2000).map { n in AssistantTurn(role:n.isMultiple(of:3) ? "user" : "assistant",content:"Fictional turn \(n)",completed:true,created:origin.addingTimeInterval(Double(n)*600)) }
        projectionFeed[1980].created=nil
        var visibilityCalls=0
        let rows=ConversationRules.transcript(projectionFeed,visible:{turn in visibilityCalls+=1;return turn.id != projectionFeed[1998].id})
        precondition(visibilityCalls == projectionFeed.count,"Visibility must run once per turn rather than once per displayed divider")
        let visible=projectionFeed.filter{$0.id != projectionFeed[1998].id}
        precondition(rows.map(\.id) == visible.map(\.id),"Pagination projections retain exact turn identities and order")
        for index in rows.indices {
            let previous=index > 0 ? visible[index-1] : nil
            let previousHuman=visible.prefix(index).last{$0.role == "user"}
            precondition(rows[index].separator == ConversationRules.separator(before:visible[index],previous:previous,previousHuman:previousHuman),"Linear separators preserve day and resumed-conversation boundaries, including outside the displayed suffix")
        }
        precondition(Array(rows.suffix(40)).first?.id == visible[visible.count-40].id)
        let legacyTurn=try JSONDecoder().decode(AssistantTurn.self,from:Data(#"{"role":"assistant","content":"Saved old reply","completed":true,"id":"84E20284-7BCE-41BD-B801-D600733F2068"}"#.utf8))
        precondition(legacyTurn.toolErrors == nil)
        var failureTurn=legacyTurn;failureTurn.toolErrors=["3PO stopped this request before executing the operation: Resolve the opening date."]
        let restoredFailure=try JSONDecoder().decode(AssistantTurn.self,from:JSONEncoder().encode(failureTurn))
        precondition(restoredFailure.toolErrors == failureTurn.toolErrors && restoredFailure.id == legacyTurn.id && restoredFailure.content == legacyTurn.content)
        AssistantTranscriptProjectionChecks.run()
        print("PASS: legacy data preservation, configured-topic-only selection, explicit no-topic/account isolation, distinct persisted topic threads, bounded isolated history and memory-learning scope")
    }
}
