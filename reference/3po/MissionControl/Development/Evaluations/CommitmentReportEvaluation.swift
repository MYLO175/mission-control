#if DEBUG
import Foundation
import SwiftData
import SwiftUI

@MainActor enum CommitmentReportEvaluation {
    /// One production native-learning request with fictional Mail excerpts; never starts sources.
    static func run(_ model:DashboardModel)async throws->[String:Any] {
        let selected=model.chatGPT.selectedModel,account=model.chatGPT.activeID
        guard !account.isEmpty,model.chatGPT.inferenceVerified,!model.chatGPT.usagePaused else { throw MemoryLearningFailure.changed }
        let now=Date.now
        let texts=["Alex asks the recipient: Would you be able to prepare the Orion prototype presentation for Friday?", "A different Alex reports: The Orion prototype presentation is cancelled; no presentation is needed.", "Supervisor Jordan reports: The Vega engineering project report you submitted this morning has been received."]
        let messages=try texts.enumerated().map{index,_ -> MailMessage in
            let value:[String:Any]=["id":"fictional-mail-\(index)","accountID":"fictional-mail","account":"Fictional Mail","messageID":index+1,"internetMessageID":"fictional-mail-\(index)","sender":["Alex <first-alex@example.invalid>","Alex <different-alex@example.invalid>","Supervisor Jordan <jordan@example.invalid>"][index],"subject":["Orion prototype presentation request","Orion presentation cancellation report","Vega report receipt"][index],"received":now.addingTimeInterval(Double(index)*60-180).ISO8601Format(),"unread":true,"replied":false,"flagged":false]
            return try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:value))
        }
        let summaries=messages.enumerated().map{index,message in
            EmailSummary(id:message.id,registration:"fictional",fingerprint:EmailSummary.fingerprint(message),summary:texts[index],attention:true,reason:"Fictional engineering responsibility",evidence:texts[index],bodyFingerprint:EmailSummary.fingerprintBody(texts[index]),bodyCheckedAt:now,message:message)
        }
        let items=NativeSourceAdapters.mail(messages,summaries:summaries,registration:"fictional",excluded:[],now:now)
        guard items.count == texts.count else {throw MemoryLearningFailure.invalid}
        let profile=[["text":"My current engineering projects are Orion and Vega. Preparing prototype presentations and writing supervisor reports are significant ongoing responsibilities for me.","certainty":"Directly stated by user"]]
        let input=try NativeLearningRules.input(items:items,candidates:[],existing:profile,coverage:"Three separate fictional Mail excerpts relevant to the stated engineering projects. Matching Orion titles and Alex names do not establish a shared person/plan. No live sources or writes.")
        let output=try await model.chatGPT.streamResponse(input:[["role":"user","content":input]],instructions:NativeLearningRules.instructions,model:selected,purpose:.diagnostic) { _ in }
        guard account == model.chatGPT.activeID,selected == model.chatGPT.selectedModel,let facts=NativeLearningRules.decode(output,items:items,candidates:[],registration:"fictional",now:now) else { throw MemoryLearningFailure.invalid }
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true)),store=PAMemoryStore(container:container)
        store.sourceIsPermitted={NativeLearningRules.permitted($0,items:items)}
        var checks:[String:Bool]=[:]
        checks["production exact-evidence save"]=store.putSources(facts,evidenceTexts:Dictionary(uniqueKeysWithValues:items.map{($0.identity,$0.text)}),expectedRevision:store.revision)
        checks["invitation stays proposed"]=facts.contains{$0.source?.identity.itemID == "fictional-mail-0" && $0.kind == .commitment && $0.sourceState == .proposed}
        checks["cancellation is attributed"]=facts.contains{$0.source?.identity.itemID == "fictional-mail-1" && $0.sourceState == .cancelled && !$0.explicit}
        checks["completion is attributed"]=facts.contains{$0.source?.identity.itemID == "fictional-mail-2" && $0.sourceState == .completed && $0.resolved == nil}
        checks["model cannot join source identities"]=facts.allSatisfy{$0.supersedes == nil && $0.commitmentGroup == nil && $0.commitmentGroupRevision == nil}
        let projection=CommitmentRules.context(store.context("fictional"))
        checks["independent reports remain singleton plans"]=(projection["plans"] as? [[String:Any]])?.allSatisfy{($0["reportIDs"] as? [String])?.count == 1} == true
        checks["no native or personal memory mutations"]=model.assistant.memory.records.isEmpty && model.assistant.projects.state.items.isEmpty && !model.writing
        checks["account and model preserved"]=account == model.chatGPT.activeID && selected == model.chatGPT.selectedModel
        return ["completed":Date.now.ISO8601Format(),"model":selected,"requests":1,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"facts":facts.map{["text":$0.text,"quote":$0.source?.quote ?? "","reportedState":$0.sourceState?.rawValue ?? "unknown"]},"storage":"Fictional Mail excerpts, disposable stores before source startup. One narrow quality scenario, not a multi-turn benchmark or live Mail/WhatsApp scheduler/UI acceptance."]
    }
}

struct LifeAndPlanPreview:View {
    var model:DashboardModel
    @State private var ready=false
    @State private var plans=false
    @State private var firstID:UUID?
    @State private var registration=""
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("Fictional workspace and plan reports · disposable storage").font(.caption);Spacer();Toggle("Plan reports",isOn:$plans).toggleStyle(.button) }
            if plans,let firstID { CommitmentReportsView(memory:model.assistant.memory,recordID:firstID,registration:registration) }
            else if ready { LifeMapAreaDetails(model:model,registration:registration,area:.studies) { _ in } }
        }.padding(12).task {
            guard !ready,let (account,_,_,_) = LifeProjectPreview.seed(model) else { return }
            registration=account
            let now=Date.now
            func fact(_ kind:MemorySourceKind,_ id:String,_ text:String,_ state:MemorySourceState,date:Date)->PAMemory {
                let source=MemorySourceEvidence(identity:.init(kind:kind,accountID:"fictional",containerID:"fictional",itemID:id,linkedIdentity:kind == .whatsapp ? "fictional-linked" : nil),revision:"v1",label:"Fictional " + kind.rawValue,quote:text,observed:now,sourceDate:date)
                return .init(registration:account,text:text,kind:.commitment,explicit:false,provenance:"Fictional report",created:now,reviewed:now,evidence:text,sourceDate:date,certainty:.inferred,durability:.situational,source:source,sourceState:state)
            }
            let first=fact(.mail,"orion-email","Alex asks whether the Orion demonstration can take place Friday.",.proposed,date:now.addingTimeInterval(-3600))
            let second=fact(.whatsapp,"orion-wa","Alex reports that the Orion demonstration is now agreed for Monday.",.changed,date:now)
            model.assistant.memory.sourcePermissionProjection=nil
            model.assistant.memory.sourceIsPermitted={record in record.registration == account && record.allSourceEvidence.allSatisfy{$0.identity.accountID == "fictional"}}
            _=model.assistant.memory.putSources([first,second],evidenceTexts:Dictionary(uniqueKeysWithValues:[first,second].map{($0.source!.identity,$0.text)}),expectedRevision:model.assistant.memory.revision)
            firstID=first.id;ready=true
        }
    }
}
#endif
