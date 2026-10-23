import Foundation
import SwiftData
@main struct Checks {
    @MainActor static func main() throws {
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let queue=PARequestQueue(container:container),topic=UUID()
        precondition(queue.add(registration:"one",topicID:topic,prompt:"Move my reminder to Monday"))
        precondition(queue.add(registration:"two",topicID:nil,prompt:"Other account"))
        precondition(queue.add(registration:"one",topicID:nil,prompt:"Second task"))
        let first=queue.items[0]
        precondition(PAQueueRules.next(queue.items,registration:"one")?.id == first.id)
        precondition(queue.mark(first.id,.running))
        let reload=PARequestQueue(container:container)
        precondition(reload.items[0].state == .interrupted && reload.items[0].topicID == topic)
        precondition(PAQueueRules.next(reload.items,registration:"one")?.prompt == "Second task")
        precondition(PAQueueRules.next(reload.items,registration:"two")?.prompt == "Other account")
        precondition(reload.remove(first.id))
        precondition(PARequestQueue(container:container).items.count == 2)
        precondition(!PARequestQueue(container:nil).add(registration:"one",topicID:nil,prompt:"Keep my draft"))
        precondition(!reload.add(registration:"",topicID:nil,prompt:"invalid"))
        precondition(!reload.add(registration:"one",topicID:nil,prompt:"  "))
        for i in 0..<125 { precondition(reload.add(registration:"one",topicID:nil,prompt:"Task \(i)",focusAreas:[.studies])) }
        let many=PARequestQueue(container:container)
        precondition(many.items == reload.items && many.items.count == 127,"More than twenty per account and one hundred total survive reopening with exact IDs/order")
        precondition(PAQueueRules.next(many.items,registration:"one")?.prompt == "Second task")
        let retained=Array(many.items.prefix(5))
        for item in retained {precondition(many.finish(item.id,result:"Fictional completed receipt",needsAnswer:false))}
        precondition(many.add(registration:"one",topicID:nil,prompt:"Retain completed history"))
        precondition(retained.allSatisfy{item in many.items.contains{$0.id == item.id && $0.state == .completed && $0.result == "Fictional completed receipt"}},"Admission does not evict completed receipts to make room")
        precondition(!many.add(registration:"one",topicID:nil,prompt:String(repeating:"x",count:ConversationRules.promptByteLimit+1)),"Per-request bounds remain enforced")
        var greeting=PAQueuedRequest(registration:"one",prompt:"hi just checking stuff");greeting.state = .completed;greeting.result="Hi"
        var answer=PAQueuedRequest(registration:"one",prompt:"Book a trip",focusAreas:[.studies,.career]);answer.state = .needsAnswer
        precondition(PAQueueRules.handoffs([greeting,answer],registration:"one").map(\.id) == [answer.id])
        let captured=try JSONDecoder().decode(PAQueuedRequest.self,from:JSONEncoder().encode(answer));precondition(captured.focusAreas == [.studies,.career])
        print("PASS: uncapped request-count admission/reopen, retained completed receipts, captured topic/account/Focus, FIFO, interrupted no-replay state, removal, unavailable storage and per-request bounds")
    }
}
