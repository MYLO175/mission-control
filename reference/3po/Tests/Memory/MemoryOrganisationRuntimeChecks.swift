import Foundation
import SwiftData

@MainActor private final class OrganisationInference:PAInferenceConnection {
    var activeID="fictional-owner",selectedModel="fictional-model"
    var busy=false,usagePaused=false,inferenceVerified=true,hasSession=true
    var answer="",calls=0
    var requestedModels:[String]=[]
    var onCall:(()->Void)?
    func streamResponse(input:[[String:String]],instructions:String,model:String?,effort:String,purpose:AIRequestPurpose,onDelta:@escaping(String)->Void) async throws->String {
        calls += 1;requestedModels.append(model ?? "");onCall?();await Task.yield();return answer
    }
    func toolResponse(input:[[String:Any]],instructions:String,tools:[[String:Any]],model:String,purpose:AIRequestPurpose,onDelta:@escaping(String)->Void) async throws->PAResponse {fatalError("These workers have no action tools")}
}
@MainActor private final class OrganisationAssistant:LearningAssistantReading {
    let connection:any PAInferenceConnection,memory:PAMemoryStore
    var busy=false,hasDraft=false,contextEnabled=true
    var contextRevision=UUID(),topics:[AssistantConversation]=[]
    var excludedCalendars=Set<String>(),excludedLists=Set<String>(),excludedAccounts=Set<String>()
    init(_ connection:any PAInferenceConnection,memory:PAMemoryStore) {self.connection=connection;self.memory=memory}
    func learningTurns()->[MemoryLearningTurn] {[]}
    func acknowledgeLearned(_ learned:[LearnedMemory]) {}
}
@MainActor private final class OrganisationWhatsApp:WhatsAppLearningReading {
    var messages:[WhatsAppReadMessage]=[],chats:[WhatsAppChat]=[]
    func scope(for registration:String)->WhatsAppSourceScope {.init(registration:registration,linkedIdentity:"fictional-device",revision:UUID())}
    func access(for registration:String)->WhatsAppAccess {.init()}
}

@main struct MemoryOrganisationRuntimeChecks {
    @MainActor static func main() async throws {
        var count=0
        func check(_ condition:Bool,_ message:String) {precondition(condition,message);count += 1}
        let cases=["unrelated addition","unrelated edit","other account addition","no-op controls","no-op service controls","service disabled","supplied edit","supplied forget","supplied retirement","supplied pin","memory disabled","learning disabled","memory off and on","learning off and on","model changed","draft opened","unrelated topic added","unrelated native edit","account changed","owner ended","foreground started","Stop"]
        for lane in ["organisation","maintenance"] {
            for scenario in cases+(lane == "maintenance" ? ["proposal dismissed","proposal Undo","other account toggle"] : []) {
                let label=lane+": "+scenario,suite="3PO.memory-organisation-check."+UUID().uuidString
                let settings=UserDefaults(suiteName:suite)!
                defer {settings.removePersistentDomain(forName:suite)}
                let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
                let inference=OrganisationInference(),memory=PAMemoryStore(container:container,settings:settings)
                let assistant=OrganisationAssistant(inference,memory:memory),budget=LearningBudget(container:container)
                var now=Date.now,owned=true,nativeWriting=false
                let owner=inference.activeID
                let runtime=LearningRuntime(assistant:assistant,inference:inference,learningBudget:budget,whatsapp:OrganisationWhatsApp(),now:{now},activity:{.init()},writing:{nativeWriting},sourceRevision:{0},nativeItems:{_,_ in nil},ownership:.init(runID:"fictional-owned-heartbeat",validate:{if !owned {throw MemoryLearningFailure.changed}},claim:{}))
                let issued=(0..<8).map{index in PAMemory(registration:owner,text:"Optics sample \(index) requires a lens",kind:.context,explicit:true,provenance:"Fictional validation",created:now.addingTimeInterval(-100),reviewed:now.addingTimeInterval(-100))}
                for record in issued {check(memory.put(record),label+" seed saved")}
                let unissued=PAMemory(registration:owner,text:"Garden irrigation valve",kind:.context,explicit:true,provenance:"Fictional validation",created:now.addingTimeInterval(-50),reviewed:now.addingTimeInterval(-50))
                check(memory.put(unissued),label+" unissued fact saved")
                var preparedProposal:MemoryReviewProposal?
                if scenario == "proposal dismissed" || scenario == "proposal Undo" {
                    let json=String(decoding:try JSONSerialization.data(withJSONObject:["proposals":[["kind":"duplicate","recordIDs":[issued[0].id.uuidString,issued[1].id.uuidString],"reason":"An existing exact duplicate suggestion."]]]),as:UTF8.self)
                    preparedProposal=MemoryReviewRules.decode(json,records:memory.records,registration:owner,now:now)?.first
                    check(preparedProposal != nil,label+" existing exact proposal prepared")
                    try LocalRecordRepository(container:container).save(MemoryReviewState(proposals:[preparedProposal!]),key:"paMemoryReview")
                }
                let organisation=LifeOrganisationService(container:container,settings:settings),maintenance=MemoryMaintenanceService(container:container)
                maintenance.setAutomatic(true,registration:owner)
                if scenario == "proposal Undo" {maintenance.dismiss(preparedProposal!.id,registration:owner)}
                if scenario == "other account toggle" {maintenance.setAutomatic(true,registration:"fictional-other")}
                let target=issued[0]
                if lane == "organisation" {
                    inference.answer=String(data:try JSONSerialization.data(withJSONObject:["entries":[["id":target.id.uuidString,"organisation":["areas":["studies"],"connections":[]]]]]),encoding:.utf8)!
                } else {
                    inference.answer=String(data:try JSONSerialization.data(withJSONObject:["proposals":[["kind":"duplicate","recordIDs":[issued[0].id.uuidString,issued[1].id.uuidString],"reason":"Inspect these two fictional optics statements."]]]),encoding:.utf8)!
                }
                var addition:PAMemory?
                inference.onCall={
                    switch scenario {
                    case "unrelated addition","other account addition":
                        let fact=PAMemory(registration:scenario == "other account addition" ? "fictional-other" : owner,text:"Maritime navigation route",kind:.context,explicit:true,provenance:"Fictional validation")
                        check(memory.put(fact),label+" concurrent addition saved");addition=memory.records.first{$0.id == fact.id}
                    case "unrelated edit":var fact=unissued;fact.text="Garden irrigation valve replaced";check(memory.put(fact),label+" concurrent unissued edit saved")
                    case "no-op controls":let use=memory.enabled,learn=memory.learningEnabled;memory.enabled=use;memory.learningEnabled=learn
                    case "no-op service controls":let automatic=organisation.automatic;organisation.automatic=automatic;maintenance.setAutomatic(true,registration:owner)
                    case "service disabled":if lane == "organisation" {organisation.automatic=false} else {maintenance.setAutomatic(false,registration:owner)}
                    case "supplied edit":var fact=target;fact.text="The optics sample now needs a mirror";check(memory.put(fact),label+" concurrent issued edit saved")
                    case "supplied forget":check(memory.forget(target.id),label+" forget saved")
                    case "supplied retirement":check(memory.retire(target.id,retired:true,expectedRevision:memory.revision),label+" retirement saved")
                    case "supplied pin":check(memory.setOrganisation(target.id,value:.init(areas:[.interests],connections:[])),label+" manual pin saved")
                    case "memory disabled":memory.enabled=false
                    case "learning disabled":memory.learningEnabled=false
                    case "memory off and on":memory.enabled=false;memory.enabled=true
                    case "learning off and on":memory.learningEnabled=false;memory.learningEnabled=true
                    case "model changed":inference.selectedModel="changed-model"
                    case "draft opened":assistant.hasDraft=true
                    case "unrelated native edit":nativeWriting=true
                    case "unrelated topic added":assistant.topics.append(.init(accountID:owner,title:"Another saved topic"))
                    case "proposal dismissed":maintenance.dismiss(preparedProposal!.id,registration:owner)
                    case "proposal Undo":maintenance.undo(owner)
                    case "other account toggle":maintenance.setAutomatic(false,registration:"fictional-other")
                    case "account changed":inference.activeID="changed-owner"
                    case "owner ended":owned=false
                    case "foreground started":assistant.busy=true
                    case "Stop":if lane == "organisation" {organisation.cancel()} else {maintenance.cancel()}
                    default:preconditionFailure("Unrecognised fixture")
                    }
                }
                if lane == "organisation" {organisation.check(runtime)} else {maintenance.check(runtime)}
                func busy()->Bool {lane == "organisation" ? organisation.busy : maintenance.busy}
                for _ in 0..<10000 {if !busy(){break};await Task.yield()}
                check(!busy() && inference.calls == 1 && inference.requestedModels == ["fictional-model"],label+" bounded inference retains captured model")
                let success=["unrelated addition","unrelated edit","other account addition","no-op controls","no-op service controls","model changed","draft opened","unrelated topic added","proposal dismissed","proposal Undo","other account toggle","unrelated native edit"].contains(scenario)
                let error=lane == "organisation" ? organisation.error : maintenance.error
                check((error == nil) == success,label+" exact outcome")
                if success {
                    if lane == "organisation" {check(memory.records.first{$0.id == target.id}?.organisation?.areas == [.studies],label+" issued classification saved")}
                    else {
                        check(maintenance.proposals(memory,registration:owner).count == (scenario == "proposal dismissed" ? 0 : 1),label+" current proposal presentation preserved")
                        if let preparedProposal {
                            let saved=try LocalRecordRepository(container:container).decode("paMemoryReview",as:MemoryReviewState.self)!
                            check(saved.proposals.count == 1 && saved.proposals.first?.id == preparedProposal.id && saved.proposals.first?.dismissed == (scenario == "proposal dismissed"),label+" exact Dismiss Undo and canonical proposal identity retained")
                        }
                    }
                    if let addition {check(memory.records.contains{$0 == addition},label+" concurrent unrelated addition preserved")}
                    if scenario == "unrelated edit" {check(memory.records.contains{$0.id == unissued.id && $0.text == "Garden irrigation valve replaced"},label+" concurrent unrelated edit preserved")}
                    let reopened=PAMemoryStore(container:container,settings:settings)
                    check(reopened.records == memory.records,label+" canonical memory round-trip")
                } else {
                    let current=memory.records.first{$0.id == target.id}
                    check(current?.organisation?.areas != [.studies],label+" no late inferred classification")
                    if scenario == "supplied pin" {check(current?.organisation?.manual == true && current?.organisation?.areas == [.interests],label+" human pin retained")}
                    if scenario == "supplied forget" {check(current == nil,label+" forgotten identity stays absent")}
                    inference.onCall=nil;inference.activeID=owner;inference.selectedModel="fictional-model";owned=true;assistant.busy=false;memory.enabled=true;memory.learningEnabled=true;now.addTimeInterval(8*86400)
                    let reopenedOrganisation=LifeOrganisationService(container:container,settings:settings),reopenedMaintenance=MemoryMaintenanceService(container:container)
                    if lane == "organisation" {reopenedOrganisation.check(runtime);check(!reopenedOrganisation.busy && inference.calls == 1 && reopenedOrganisation.summary(runtime).contains("paused"),label+" attempted claim stays paused across reopen")}
                    else {reopenedMaintenance.check(runtime);check(!reopenedMaintenance.busy && inference.calls == 1 && reopenedMaintenance.paused(owner),label+" attempted claim stays paused across reopen")}
                }
                check(budget.receipts(owner).count == 1,label+" original automatic learning allowance retained")
            }
        }
        do {
            let suite="3PO.memory-organisation-cas."+UUID().uuidString,settings=UserDefaults(suiteName:suite)!
            defer {settings.removePersistentDomain(forName:suite)}
            let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let inference=OrganisationInference(),memory=PAMemoryStore(container:container,settings:settings),budget=LearningBudget(container:container)
            let target=PAMemory(registration:inference.activeID,text:"Fictional optical sensor",kind:.context,explicit:true,provenance:"Fictional validation")
            check(memory.put(target),"CAS fixture fact saved")
            let assistant=OrganisationAssistant(inference,memory:memory)
            let runtime=LearningRuntime(assistant:assistant,inference:inference,learningBudget:budget,whatsapp:OrganisationWhatsApp(),activity:{.init()},writing:{false},sourceRevision:{0},nativeItems:{_,_ in nil})
            let organisation=LifeOrganisationService(container:container,settings:settings)
            inference.answer=String(data:try JSONSerialization.data(withJSONObject:["entries":[["id":target.id.uuidString,"organisation":["areas":["studies"],"connections":[]]]]]),encoding:.utf8)!
            let concurrent=PAMemory(registration:inference.activeID,text:"Fictional separate writer's garden",kind:.context,explicit:true,provenance:"Fictional validation")
            inference.onCall={
                let writer=PAMemoryStore(container:container,settings:settings)
                check(writer.put(concurrent),"CAS concurrent store write saved")
            }
            organisation.check(runtime)
            for _ in 0..<10000 {if !organisation.busy {break};await Task.yield()}
            let reopened=PAMemoryStore(container:container,settings:settings)
            check(inference.calls == 1 && organisation.error != nil,"Loaded-byte CAS rejects an external writer even when the in-memory revision is unchanged")
            check(reopened.records.contains{$0.id == concurrent.id && $0.text == concurrent.text},"External saved data survives rejected organisation save")
            check(reopened.records.first{$0.id == target.id}?.organisation == nil,"CAS rejection cannot save stale classification")
        }
        print("PASS \(count) actual maintenance/organisation checks across \(cases.count*2+3) fictional runs: exact issued records, concurrent unrelated data preservation, control generations, account/model/owner/Stop and durable failed-claim pauses; zero live inference/native/personal reads.")
    }
}
