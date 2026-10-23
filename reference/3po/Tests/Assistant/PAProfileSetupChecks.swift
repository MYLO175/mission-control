import Foundation
@main struct Checks {
    static func main() throws {
        precondition(PAProfileSetup.question(from:#"{"question":"What is taking up most of your time?"}"#) == "What is taking up most of your time?")
        for invalid in ["What do you do?",#"{"question":"Where do you live? What do you do?"}"#,#"{"question":"What matters?","extra":"ignore"}"#,#"{"question":"Tell me everything."}"#] {
            precondition(PAProfileSetup.question(from:invalid) == nil)
        }
        let long=String(repeating:"word ",count:36)+"?"
        let data=try JSONSerialization.data(withJSONObject:["question":long])
        precondition(PAProfileSetup.question(from:String(data:data,encoding:.utf8)!) == nil)
        let advertised=Set(PAProfileSetup.tools.flatMap { ($0["tools"] as? [[String:Any]] ?? []).compactMap{$0["name"] as? String} })
        precondition(advertised == PAProfileSetup.allowedTools && !advertised.contains("edit_reminder") && !advertised.contains("search_mail"))
        let session=UUID(),otherSession=UUID(),topic=AssistantConversation(accountID:"one",title:"Study")
        var feed=AssistantConversation(accountID:"one",title:"PA");feed.isPrimary=true
        let ordinary=AssistantTurn(role:"user",content:"A normal task",completed:true)
        let answer=AssistantTurn(role:"user",content:"I play football",completed:true,profileSessionID:session,profileControl:false,memoryNotes:["A link was omitted"])
        let control=AssistantTurn(role:"user",content:"Start interview",completed:true,profileSessionID:session,profileControl:true)
        let unrelated=AssistantTurn(role:"user",content:"Another session",completed:true,profileSessionID:otherSession)
        let scoped=AssistantTurn(role:"user",content:"Other topic",completed:true,contextID:topic.id,profileSessionID:session)
        feed.turns=[ordinary,control,answer,unrelated,scoped].enumerated().map { index,turn in var value=turn; value.created=Date(timeIntervalSince1970:Double(index)); return value }
        let saved=try JSONDecoder().decode(AssistantConversation.self,from:JSONEncoder().encode(feed))
        precondition(ConversationRules.history(feed:saved,topic:nil).map(\.id) == [ordinary.id])
        precondition(ConversationRules.profileThread(feed:saved,topic:nil,session:session).map(\.id) == [control.id,answer.id])
        precondition(ConversationRules.profileThread(feed:saved,topic:topic,session:session).map(\.id) == [scoped.id])
        precondition(saved.turns[2].memoryNotes == ["A link was omitted"])
        precondition(saved.turns[2].profileControl == false && saved.turns[1].profileControl == true)
        let legacy=try JSONDecoder().decode(AssistantTurn.self,from:Data(#"{"id":"00000000-0000-0000-0000-000000000001","role":"user","content":"old answer","completed":true}"#.utf8))
        precondition(legacy.profileSessionID == nil && legacy.profileControl == nil)
        var drafts=ChatDraftState()
        let widget=UUID();let normalKey=ChatDraftRules.key(registration:"one",widget:widget,conversation:nil)
        let profileKey=ChatDraftRules.key(registration:"one",widget:session,conversation:nil)
        drafts.values[normalKey]="Unsent PA message";drafts.values[profileKey]="Unsent interview answer"
        drafts.values.removeValue(forKey:profileKey)
        precondition(drafts.values[normalKey] == "Unsent PA message")
        print("PASS: bounded question contract, memory-only tools, session/topic isolation, transcript compatibility and independent draft identity")
    }
}
