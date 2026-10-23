import Foundation
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let now=Date.now,registration="fictional",linked="fictional-linked",chat="orion"
        let initial=WhatsAppReadMessage(id:"initial",chat:chat,sender:"Alex",text:"Orion draft: please send it by Friday. You agreed to prepare the draft.",sentByMe:false,time:now.addingTimeInterval(-72*3600).timeIntervalSince1970*1000)
        let moved=WhatsAppReadMessage(id:"moved",chat:chat,sender:"Alex",text:"The Orion draft deadline has moved from Friday to Monday.",sentByMe:false,time:now.addingTimeInterval(-24*3600).timeIntervalSince1970*1000)
        let cancelled=WhatsAppReadMessage(id:"cancelled",chat:chat,sender:"Alex",text:"Cancel that draft; it is no longer needed for Orion.",sentByMe:false,time:now.addingTimeInterval(-3600).timeIntervalSince1970*1000)
        let other=WhatsAppReadMessage(id:"other",chat:"another-orion",sender:"Alex",text:"The Orion draft is still due on Friday for our separate project.",sentByMe:false,time:cancelled.time+3000)
        let chats=[WhatsAppChat(id:chat,name:"Orion",group:true),WhatsAppChat(id:other.chat,name:"Orion",group:true)]
        var cache=[initial,moved,cancelled,other],access=WhatsAppAccess(enabled:true,chats:[chat,other.chat],learnContext:true)
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=PAMemoryStore(container:container)
        store.sourceIsPermitted={SourceContextRules.permitted($0,access:access,linkedIdentity:linked,messages:cache)}
        func message(_ item:WhatsAppReadMessage)->SourceContextMessage {
            SourceContextRules.recent([item],chats:chats,allowed:access.chats,now:Date(timeIntervalSince1970:item.time/1000+1))[0]
        }
        func json(_ facts:[[String:Any]])->String { String(data:try! JSONSerialization.data(withJSONObject:["facts":facts]),encoding:.utf8)! }
        func fact(_ item:WhatsAppReadMessage,_ text:String,_ state:String,previous:PAMemory? = nil,support:[WhatsAppReadMessage]=[])->[String:Any] {
            var value:[String:Any]=["messageID":message(item).id,"text":text,"quote":item.text,"kind":"commitment","state":state,"areas":["projects"],"support":support.map{["messageID":message($0).id,"quote":$0.text]}]
            if let previous { value["updatesMemoryID"]=previous.id.uuidString };return value
        }
        func save(_ values:[PAMemory])->Bool {
            let texts=Dictionary(values.flatMap(\.allSourceEvidence).compactMap{evidence in cache.first(where:{$0.chat == evidence.identity.containerID && $0.id == evidence.identity.itemID}).map{(evidence.identity,$0.text)}},uniquingKeysWith:{first,_ in first})
            return store.putSources(values,evidenceTexts:texts,expectedRevision:store.revision)
        }
        let first=SourceContextRules.decode(json([fact(initial,"Alex reports the agreed Orion draft is due Friday.","accepted")]),messages:[message(initial)],registration:registration,linkedIdentity:linked,now:now)!.first!
        precondition(save([first]))
        let changeOutput=json([fact(moved,"Alex reports the Orion draft deadline is now Monday.","changed",previous:first,support:[initial])])
        // An older saved quotation may support a current report without replaying old history.
        let change=SourceContextRules.decode(changeOutput,messages:[message(moved)],registration:registration,linkedIdentity:linked,now:now,candidates:[first])!.first!
        let omittedSupport=SourceContextRules.decode(json([fact(moved,"Alex reports the Orion deadline is now Monday.","changed",previous:first)]),messages:[message(moved)],registration:registration,linkedIdentity:linked,now:now,candidates:[first])!.first!
        precondition(omittedSupport.supportingSources?.first == first.source,"The app retains the earlier exact quote even when the model omits that linkage")
        precondition(change.supportingSources?.first?.identity.itemID == initial.id && save([change]))
        precondition(store.context(registration).map{$0["text"]} == [change.text])
        precondition(store.records.first(where:{$0.id == first.id})?.text == first.text && store.records.first(where:{$0.id == first.id})?.source == first.source)
        precondition(store.records.first(where:{$0.id == first.id})?.supersededBy == change.id && store.records.first(where:{$0.id == change.id})?.supersedes == first.id)
        let cancelOutput=json([fact(cancelled,"Alex reports the Orion draft is cancelled and no longer needed.","cancelled",previous:change,support:[moved,initial])])
        let cancellation=SourceContextRules.decode(cancelOutput,messages:[message(cancelled)],registration:registration,linkedIdentity:linked,now:now,candidates:[change])!.first!
        precondition(save([cancellation]))
        let reloaded=PAMemoryStore(container:container);reloaded.sourceIsPermitted=store.sourceIsPermitted
        precondition(reloaded.versionFamily(cancellation.id).count == 3 && reloaded.context(registration).map{$0["text"]} == [cancellation.text])
        precondition(reloaded.context(registration).first?["sourceReportedState"]?.contains("not confirmed task status") == true)
        precondition(cancellation.allSourceEvidence.count == 3 && !cancellation.explicit && cancellation.resolved == nil,"A reported cancellation never completes an Apple item or resolves human memory")
        precondition(reloaded.context(registration,includeSources:false).isEmpty,"Legacy automatic inputs still exclude source memories")
        let recordsBefore=reloaded.records,revisionBefore=reloaded.revision
        precondition(!reloaded.putSources([cancellation],evidenceTexts:[:],expectedRevision:revisionBefore) && reloaded.records == recordsBefore,"Replay cannot duplicate a current version")
        precondition(SourceContextRules.decode(changeOutput,messages:[message(moved)],registration:registration,linkedIdentity:linked,now:now,candidates:reloaded.records.filter{$0.id == first.id}) == nil,"An earlier superseded version is not an update target")
        var wrong=fact(other,"Alex reports a separate Orion draft is cancelled.","cancelled",previous:cancellation)
        precondition(SourceContextRules.decode(json([wrong]),messages:[message(other)],registration:registration,linkedIdentity:linked,now:now,candidates:[cancellation]) == nil,"Equal chat names do not authorise cross-conversation updates")
        wrong=fact(moved,"Invented earlier update","changed",previous:cancellation)
        precondition(SourceContextRules.decode(json([wrong]),messages:[message(moved)],registration:registration,linkedIdentity:linked,now:now,candidates:[cancellation]) == nil,"Out-of-order arrivals cannot overwrite a newer report")
        wrong=fact(cancelled,"Cancelled report","cancelled",support:[other])
        precondition(SourceContextRules.decode(json([wrong]),messages:[message(cancelled),message(other)],registration:registration,linkedIdentity:linked,now:now) == nil,"Supporting evidence cannot cross conversations")
        wrong=fact(moved,"Deadline now Monday","changed",support:[cancelled])
        precondition(SourceContextRules.decode(json([wrong]),messages:[message(moved),message(cancelled)],registration:registration,linkedIdentity:linked,now:now) == nil,"Primary evidence is the latest cited report")
        wrong=fact(cancelled,"Cancelled report","cancelled",support:[moved]);wrong["support"]=[["messageID":message(moved).id,"quote":"Invented quote that never appeared"]]
        precondition(SourceContextRules.decode(json([wrong]),messages:[message(cancelled),message(moved)],registration:registration,linkedIdentity:linked,now:now) == nil)
        cache[0]=WhatsAppReadMessage(id:initial.id,chat:initial.chat,sender:initial.sender,text:initial.text+" Edited",sentByMe:initial.sentByMe,time:initial.time)
        precondition(reloaded.context(registration).isEmpty,"Changing any supporting version excludes the entire derived belief")
        precondition(reloaded.records == recordsBefore,"Revocation preserves every historical record and quote")
        cache[0]=initial;access.chats=[other.chat]
        precondition(reloaded.context(registration).isEmpty,"Revoking selected source access excludes the current projection")
        access.chats=[chat,other.chat];access.learnContext=false
        precondition(reloaded.context(registration).isEmpty)
        access.learnContext=true;cache.removeAll{$0.id == moved.id}
        precondition(reloaded.context(registration).isEmpty,"Missing supporting cache is unknown; it never resurrects Friday")
        cache.append(moved)
        precondition(reloaded.context(registration).count == 1)
        let historical=reloaded.versionFamily(first.id)
        precondition(historical.count == 1 && reloaded.forget(first.id))
        precondition(reloaded.context(registration).isEmpty && reloaded.notebook(registration).eligibleCount == 0,"Forgetting an earlier quoted version also excludes its dependent current belief")
        precondition(reloaded.records.first(where:{$0.id == cancellation.id})?.sourceInvalidation == .forgotten)
        precondition(reloaded.restoreForgotten(historical) && reloaded.context(registration).count == 1,"Undo restores explicitly forgotten source evidence and dependent recall")
        precondition(reloaded.forget(cancellation.id) && reloaded.records.isEmpty)
        var paraphrase=cancellation;paraphrase.id=UUID();paraphrase.supersedes=nil;paraphrase.text="Different wording for the same cancelled Orion draft"
        precondition(reloaded.putSources([paraphrase],evidenceTexts:Dictionary(uniqueKeysWithValues:cache.filter{$0.chat == chat}.map{(.init(kind:.whatsapp,accountID:linked,containerID:chat,itemID:$0.id,linkedIdentity:linked),$0.text)}),expectedRevision:reloaded.revision) && reloaded.records.isEmpty,"Forget suppresses every quoted source version in the lineage")
        var confirmed=first;confirmed.id=UUID();confirmed.registration="confirmed";confirmed.explicit=true
        precondition(reloaded.put(confirmed))
        precondition(SourceContextRules.decode(json([fact(moved,"New deadline Monday","changed",previous:confirmed)]),messages:[message(moved)],registration:"confirmed",linkedIdentity:linked,now:now,candidates:[confirmed]) == nil,"Source reports cannot supersede human-confirmed memory")
        var unsafe=change;unsafe.id=UUID();unsafe.registration="confirmed";unsafe.supersedes=confirmed.id
        precondition(!reloaded.putSources([unsafe],evidenceTexts:Dictionary(uniqueKeysWithValues:cache.filter{$0.chat == chat}.map{(.init(kind:.whatsapp,accountID:linked,containerID:chat,itemID:$0.id,linkedIdentity:linked),$0.text)}),expectedRevision:reloaded.revision))
        var legacy=try JSONSerialization.jsonObject(with:JSONEncoder().encode(first)) as! [String:Any]
        legacy.removeValue(forKey:"supportingSources");legacy.removeValue(forKey:"sourceState")
        let legacyRecord=try JSONDecoder().decode(PAMemory.self,from:JSONSerialization.data(withJSONObject:legacy))
        precondition(legacyRecord.allSourceEvidence.count == 1,"Legacy primary-only memory still decodes")
        let recent=SourceContextRules.recent(cache,chats:chats,allowed:access.chats,now:now)
        let prepared=SourceContextRules.prepare([message(moved)],recent:recent,existing:[],candidates:[first])!
        precondition(prepared.input.utf8.count <= 24000 && prepared.messages.contains{$0.itemID == cancelled.id})
        let input=try JSONSerialization.jsonObject(with:Data(prepared.input.utf8)) as! [String:Any]
        let inputMessages=input["messages"] as! [[String:Any]]
        precondition(inputMessages.filter{$0["assess"] as? Bool == true}.count == 1 && inputMessages.contains{$0["id"] as? String == message(cancelled).id && $0["assess"] as? Bool == false})
        precondition(SourceContextRules.decode(json([fact(cancelled,"Cancelled report","cancelled")]),messages:prepared.messages,registration:registration,linkedIdentity:linked,now:now,candidates:prepared.candidates,assessing:[message(moved).id]) == nil,"Context-only messages do not advance or create assessed facts")
        let receipt=SourceContextRules.assessmentKey(registration:registration,linkedIdentity:linked,message:message(cancelled))
        let receiptContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let receipts=PAMemoryStore(container:receiptContainer)
        receipts.sourceIsPermitted=store.sourceIsPermitted
        let texts=Dictionary(uniqueKeysWithValues:cache.filter{$0.chat == chat}.map{(MemorySourceIdentity(kind:.whatsapp,accountID:linked,containerID:chat,itemID:$0.id,linkedIdentity:linked),$0.text)})
        var receiptFact=cancellation;receiptFact.supersedes=nil
        precondition(receipts.putSources([receiptFact],evidenceTexts:texts,expectedRevision:receipts.revision,assessmentIDs:[receipt]))
        var retry=receiptFact;retry.id=UUID();retry.text="A paraphrased replay of the cancelled draft"
        precondition(receipts.putSources([retry],evidenceTexts:texts,expectedRevision:receipts.revision,assessmentIDs:[receipt]) && receipts.records.count == 1,"The source-version receipt is atomic with its facts and prevents a paraphrased retry")
        let emptyReceipt=SourceContextRules.assessmentKey(registration:registration,linkedIdentity:linked,message:message(moved))
        precondition(receipts.putSources([],evidenceTexts:[:],expectedRevision:receipts.revision,assessmentIDs:[emptyReceipt]) && receipts.sourceAssessmentDate(emptyReceipt) != nil,"A valid no-facts assessment also persists its receipt")
        precondition(SourceContextRules.assessmentKey(registration:"another",linkedIdentity:linked,message:message(cancelled)) != receipt)
        precondition(SourceContextRules.assessmentKey(registration:registration,linkedIdentity:"another",message:message(cancelled)) != receipt)
        precondition(!receipt.contains(chat) && !receipt.contains(registration) && receipt.count == 82,"Assessment receipts retain only opaque scoped version identity")
        precondition(PAMemoryStore(container:receiptContainer).sourceAssessmentDate(receipt) != nil,"Receipts survive store reopen after an unsaved coverage cursor")
        let overlapContainer=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let overlap=PAMemoryStore(container:overlapContainer)
        overlap.sourceIsPermitted=store.sourceIsPermitted
        var a=first;a.id=UUID();a.registration="overlap"
        var b=a;b.id=UUID();b.text="A separate interpretation of the same initial report"
        var dependent=cancellation;dependent.id=UUID();dependent.registration="overlap";dependent.supersedes=nil
        precondition(overlap.putSources([a,b,dependent],evidenceTexts:texts,expectedRevision:overlap.revision))
        precondition(overlap.forget(a.id))
        let undoB=overlap.versionFamily(b.id)
        precondition(overlap.forget(b.id) && overlap.restoreForgotten(undoB))
        precondition(overlap.suppressed("overlap").contains(a.sourceSuppressionKey!) && overlap.context("overlap").isEmpty,"Undo B cannot remove A's overlapping Forget suppression")
        let overlapReload=PAMemoryStore(container:overlapContainer);overlapReload.sourceIsPermitted=store.sourceIsPermitted
        precondition(overlapReload.suppressed("overlap").contains(a.sourceSuppressionKey!) && overlapReload.context("overlap").isEmpty,"Overlapping Forget ownership survives store reopen")
        print("PASS: three-day attributed version history, multiple exact quotes, current-only recall, chronology, chat identity, human protection, revocation, cache loss, Forget/replay and bounded context")
    }
}
