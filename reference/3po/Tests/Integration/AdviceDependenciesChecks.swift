import Foundation
import SwiftData

@main struct AdviceDependenciesChecks {
    @MainActor static func main() throws {
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=PAMemoryStore(container:container),registration="fictional-owner",now=Date.now
        var access=true,version="v1"
        store.sourceIsPermitted={access && $0.source?.revision == version}
        let identity=MemorySourceIdentity(kind:.calendar,accountID:"fictional-provider",containerID:"fictional-studies",itemID:"fictional-orion")
        let quote="Orion supervision needs a four-sensor prototype."
        let source=MemorySourceEvidence(identity:identity,revision:version,label:"Fictional Studies",quote:quote,observed:now,sourceDate:now)
        let fact=PAMemory(registration:registration,text:"A Calendar entry requests a four-sensor Orion prototype.",kind:.commitment,explicit:false,provenance:"Calendar evidence",evidence:quote,sourceDate:now,certainty:.inferred,durability:.situational,source:source,sourceState:.proposed)
        precondition(store.putSources([fact],evidenceTexts:[identity:quote],expectedRevision:store.revision))
        let human=PAMemory(registration:registration,text:"I prefer preparing prototypes the day before.",kind:.preference,provenance:"Fictional human",evidence:"I prefer preparing prototypes the day before.")
        precondition(store.put(human))
        let captured=store.selection(registration),dependencies=MemoryDependencyRules.capture(captured.records)
        func usable()->[[String:String]] { store.enabled ? store.permittedRecords.filter{MemoryRules.usable($0,registration:registration)}.map(MemoryRetrieval.record) : [] }
        func available()->Bool { MemoryDependencyRules.available(dependencies,records:usable()) }
        precondition(dependencies.count == 2 && available())
        precondition(store.selection(registration,sourceFilter:{_ in false}).records.count == 1,"Feature permissions narrow the existing projection without hiding human facts")
        access=false;precondition(!available(),"Source opt-out invalidates supporting advice without deleting the dated output")
        access=true;precondition(available())
        version="v2";precondition(!available(),"Changed evidence cannot be used even when its old memory ID is still saved")
        version="v1"
        let unrelated=PAMemory(registration:registration,text:"I play tennis on Sundays.",kind:.context,provenance:"Fictional human")
        precondition(store.put(unrelated) && available(),"An unrelated fact must not invalidate a saved result")
        precondition(store.setOrganisation(human.id,value:.init(areas:[.about],connections:[],selfName:nil)) && available(),"Reclassification alone does not rewrite supporting truth")
        var changed=fact;changed.id=UUID();changed.text="A Calendar entry cancels the Orion prototype request.";changed.supersedes=fact.id;changed.sourceState = .cancelled
        changed.source?.revision="v2";changed.source?.observed=now.addingTimeInterval(1);changed.source?.quote="Orion prototype request has been cancelled.";changed.evidence=changed.source?.quote
        version="v2"
        precondition(store.putSources([changed],evidenceTexts:[identity:changed.evidence!],expectedRevision:store.revision,replacementSources:[fact.id:source]))
        precondition(!available() && store.records.contains{$0.id == fact.id && $0.supersededBy == changed.id},"Cancellation retains history while excluding earlier support")
        let currentDependencies=MemoryDependencyRules.capture(store.context(registration))
        precondition(MemoryDependencyRules.available(currentDependencies,records:usable()))
        precondition(store.forget(changed.id) && !MemoryDependencyRules.available(currentDependencies,records:usable()),"Forget invalidates receipts, without asserting Apple completion")
        let humanDependencies=MemoryDependencyRules.capture(store.context(registration))
        let initialHuman=store.records.first{$0.id == human.id}!
        var correction=initialHuman;correction.id=UUID();correction.text="I now prefer preparing two days before.";correction.evidence=correction.text
        precondition(store.correct(human.id,with:correction))
        precondition(!MemoryDependencyRules.available(humanDependencies,records:usable()),"Human corrections invalidate old advice too")
        precondition(!MemoryDependencyRules.available(humanDependencies,records:store.context("another-account")))
        precondition(MemoryDependencyRules.available(nil,records:[]) && MemoryDependencyRules.available([],records:[]))
        precondition(!MemoryDependencyRules.available([dependencies[0],dependencies[0]],records:captured.records))
        var altered=dependencies[0];altered.fingerprint=String(repeating:"f",count:64)
        precondition(!MemoryDependencyRules.available([altered],records:captured.records))
        var reordered=captured.records[0];reordered["organisation"]="new metadata";reordered["reviewed"]="later"
        precondition(MemoryDependencyRules.fingerprint(reordered) == MemoryDependencyRules.fingerprint(captured.records[0]))
        reordered["sourceReportedState"]="cancelled";precondition(MemoryDependencyRules.fingerprint(reordered) != MemoryDependencyRules.fingerprint(captured.records[0]))
        precondition(!AutomaticMemoryUse.brief.allowsWhatsApp(enabled:true,brief:false,suggestions:true,heartbeat:true))
        precondition(!AutomaticMemoryUse.suggestions.allowsWhatsApp(enabled:true,brief:true,suggestions:false,heartbeat:false))
        precondition(AutomaticMemoryUse.manualSuggestions.allowsWhatsApp(enabled:true,brief:false,suggestions:false,heartbeat:false))
        precondition(AutomaticMemoryUse.heartbeatSuggestions.allowsWhatsApp(enabled:true,brief:false,suggestions:false,heartbeat:true))
        precondition(!AutomaticMemoryUse.heartbeatSuggestions.allowsWhatsApp(enabled:false,brief:true,suggestions:true,heartbeat:true))
        let morning=DailyBriefing(id:"immutable-morning",registration:registration,day:BriefingRules.day(now),created:now,items:[.init(text:"Prepare the prototype.",sourceIDs:["memory_0"])],sources:[.init(id:"memory_0",label:"Memory",kind:"memory",date:nil,originalID:fact.id.uuidString)],coverage:"Fictional",sourceScope:"same",message:"Good morning. Prepare the prototype.",memoryDependencies:dependencies)
        let saved=try JSONDecoder().decode(DailyBriefing.self,from:JSONEncoder().encode(morning))
        precondition(saved.memoryDependencies == dependencies && saved.message == morning.message)
        let state=BriefingState(records:[saved],notificationClaims:[saved.day])
        precondition(BriefingRules.completedDays(records:state.records,registration:registration) == [saved.day],"Stale support must never prepare or deliver a second morning")
        var legacyObject=try JSONSerialization.jsonObject(with:JSONEncoder().encode(saved)) as! [String:Any]
        legacyObject.removeValue(forKey:"memoryDependencies")
        let legacy=try JSONDecoder().decode(DailyBriefing.self,from:JSONSerialization.data(withJSONObject:legacyObject))
        precondition(legacy.memoryDependencies == nil && legacy.sources.first?.originalID == fact.id.uuidString)
        let candidate=DiscoveryCandidate(alias:"mail_0",mailID:"fictional-mail",evidence:quote,followUpEvidence:"",sourceRevision:"header",sourceAssessmentRevision:"body-one")
        let output=#"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"Could a prototype reminder help?","evidence":"Orion supervision needs a four-sensor prototype."}]}"#
        var advice=try ProactiveRules.decode(output,candidates:[candidate],registration:registration,scope:"same",now:now)[0]
        advice.memoryDependencies=dependencies;advice.memoryUse = .manualSuggestions
        let reloaded=try JSONDecoder().decode(PADiscovery.self,from:JSONEncoder().encode(advice))
        precondition(reloaded.memoryDependencies == dependencies && reloaded.memoryUse == .manualSuggestions && reloaded.sourceAssessmentRevision == "body-one")
        var newer=advice;newer.sourceAssessmentRevision="body-two"
        precondition(ProactiveRules.unreported([newer],prior:[advice],budget:1).isEmpty,"An assessment revision alone cannot issue the same pending action again")
        var changedSource=candidate;changedSource.sourceAssessmentRevision="body-two";changedSource.sourceContentVersion="different-exact-body-content"
        let changedOutput=#"{"suggestions":[{"mailID":"mail_0","kind":"reminder","message":"Could a diagram reminder help instead?","evidence":"Orion supervision now needs a diagram instead of a prototype."}]}"#
        changedSource.evidence="Orion supervision now needs a diagram instead of a prototype."
        let changedAdvice=try ProactiveRules.decode(changedOutput,candidates:[changedSource],registration:registration,scope:"same",now:now)[0]
        precondition(ProactiveRules.unreported([changedAdvice],prior:[advice],budget:1).count == 1,"Changed exact content with a materially different supported action remains eligible despite identical Mail headers")
        var dismissed=advice;dismissed.dismissed=true
        precondition(ProactiveRules.unreported([advice],prior:[dismissed],budget:1).isEmpty,"No duplicate unchanged advice after dismissal")
        var legacyAdvice=try JSONSerialization.jsonObject(with:JSONEncoder().encode(advice)) as! [String:Any]
        for key in ["memoryDependencies","memoryUse","sourceAssessmentRevision"] { legacyAdvice.removeValue(forKey:key) }
        let restoredLegacy=try JSONDecoder().decode(PADiscovery.self,from:JSONSerialization.data(withJSONObject:legacyAdvice))
        precondition(restoredLegacy.memoryDependencies == nil && restoredLegacy.sourceAssessmentRevision == nil)
        var assessment=EmailSummary(id:"fixture",registration:registration,fingerprint:"header",summary:"Orion request",attention:true,reason:"Prepare",evidence:quote,bodyFingerprint:"body-one")
        let assessed=assessment.adviceRevision(replied:false)
        assessment.replyDraft="An edited local draft";assessment.bodyCheckedAt=now
        precondition(assessment.adviceRevision(replied:false) == assessed,"Draft edits and identical body rechecks are not new source evidence")
        assessment.bodyFingerprint="body-two";precondition(assessment.adviceRevision(replied:false) != assessed)
        precondition(assessment.adviceRevision(replied:false) != assessment.adviceRevision(replied:true),"Already-replied source state invalidates old follow-up advice")
        func message(_ subject:String)->MailMessage {
            let json:[String:Any]=["id":"fixture","accountID":"fictional-mail","account":"Fictional Mail","messageID":1,"internetMessageID":"fictional@example.invalid","sender":"Fictional person","subject":subject,"received":now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
            return try! JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:json))
        }
        let originalMessage=message("Orion preparation")
        assessment.fingerprint=EmailSummary.fingerprint(originalMessage)
        let currentRevision=assessment.adviceRevision(replied:false)
        precondition(assessment.adviceMatches(originalMessage,revision:currentRevision))
        precondition(!assessment.adviceMatches(message("Orion preparation cancelled"),revision:currentRevision),"A changed header with an old assessment must stop before inference/save")
        let request=WhatsAppReadMessage(id:"request",chat:"fictional-study",sender:"Tutor",text:"Please bring the four-sensor prototype.",sentByMe:false,time:now.timeIntervalSince1970*1000)
        let cancellation=WhatsAppReadMessage(id:"cancel",chat:request.chat,sender:"Tutor",text:"The supervision is cancelled; no prototype needed.",sentByMe:false,time:request.time+1000)
        let window=ProactiveRules.whatsappWindow([request],chats:[request.chat],identity:"fictional-linked")
        precondition(window != ProactiveRules.whatsappWindow([request,cancellation],chats:[request.chat],identity:"fictional-linked"),"An unchanged request plus a later cancellation invalidates the captured context")
        let unrelatedReply=WhatsAppReadMessage(id:cancellation.id,chat:"unselected",sender:cancellation.sender,text:cancellation.text,sentByMe:false,time:cancellation.time)
        precondition(window == ProactiveRules.whatsappWindow([unrelatedReply,request],chats:[request.chat],identity:"fictional-linked"),"An unselected chat never participates in the window")
        let windows=ProactiveRules.whatsappDependencies([request],chats:[request.chat],identity:"fictional-linked")
        precondition(windows.first?.fingerprint == window)
        var windowBrief=morning;windowBrief.whatsappDependencies=windows
        let manyChats=Set((0..<120).map{"fictional-chat-\($0)"})
        precondition(ProactiveRules.whatsappDependencies([],chats:manyChats,identity:"fictional-link").count <= MemoryDependencyRules.sourceChatLimit,"Receipt bounds cover the maximum selected source evidence plus raw brief chats")
        let restoredWindow=try JSONDecoder().decode(DailyBriefing.self,from:JSONEncoder().encode(windowBrief))
        precondition(restoredWindow.whatsappDependencies == windows && restoredWindow.id == morning.id)
        print("PASS advice dependencies: exact selected belief receipts; scope/access/version/Forget/correction/cancellation; stable organisation and unrelated facts; purpose-specific WhatsApp permissions; immutable morning and legacy persistence; exact Mail assessment changes and no duplicate dismissal replay. Fictional disposable storage; no AI/native writes.")
    }
}
