#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Small real-subscription quality check; fictional inputs and disposable storage only.
@MainActor enum NativeMemoryEvaluation {
    static func run(_ model:DashboardModel)async throws->[String:Any] {
        let selected=model.chatGPT.selectedModel,account=model.chatGPT.activeID
        guard !account.isEmpty,model.chatGPT.inferenceVerified,!model.chatGPT.usagePaused else { throw MemoryLearningFailure.changed }
        let store=PAMemoryStore(container:try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true)))
        let now=Date.now,identity=MemorySourceIdentity(kind:.calendar,accountID:"fictional-provider",containerID:"fictional-calendar",itemID:"fictional-orion")
        let initial=NativeLearningItem(identity:identity,revision:"fictional-v1",label:"Fictional Studies",text:"Calendar entry: Weekly Orion engineering supervision. Alex is preparing the Orion sensor prototype with two sensors for this continuing project.\nStart: 2026-10-09T10:00:00+01:00",date:now.addingTimeInterval(86400),changed:now)
        var revised=initial;revised.revision="fictional-v2";revised.text="Calendar entry: Weekly Orion engineering supervision. Alex is preparing the Orion sensor prototype with four sensors, replacing the earlier two-sensor plan.\nStart: 2026-10-09T10:00:00+01:00"
        var current=[initial],checks:[String:Bool]=[:],outputs:[[String:Any]]=[]
        store.sourceIsPermitted={NativeLearningRules.permitted($0,items:current)}
        for (index,item) in [initial,revised].enumerated() {
            guard account == model.chatGPT.activeID,selected == model.chatGPT.selectedModel else { throw MemoryLearningFailure.changed }
            current=[item]
            let candidates=store.records.filter{NativeLearningRules.replaceable($0,by:item,registration:"fictional",now:.now)}
            let input=try NativeLearningRules.input(items:[item],candidates:candidates,existing:[],coverage:"One fictional exact Calendar entry; no live sources or writes.")
            let output=try await model.chatGPT.streamResponse(input:[["role":"user","content":input]],instructions:NativeLearningRules.instructions,model:selected,purpose:.diagnostic) { _ in }
            guard let facts=NativeLearningRules.decode(output,items:[item],candidates:candidates,registration:"fictional",now:.now) else { throw MemoryLearningFailure.invalid }
            let replacements=Dictionary(uniqueKeysWithValues:candidates.compactMap{record in record.source.map{(record.id,$0)}})
            checks["pass\(index+1) atomic exact-evidence save"]=store.putSources(facts,evidenceTexts:[item.identity:item.text],expectedRevision:store.revision,replacementSources:replacements)
            checks["pass\(index+1) useful provisional extraction"] = !facts.isEmpty && facts.allSatisfy{!$0.explicit && $0.source?.identity == identity}
            outputs.append(["pass":index+1,"facts":facts.map{["text":$0.text,"quote":$0.source?.quote ?? "","updates":$0.supersedes?.uuidString ?? "none"]}])
            if index == 1 {
                checks["changed same-date item replaces earlier belief"]=facts.contains{$0.supersedes != nil}
                checks["current recall excludes earlier revision"]=store.permittedRecords.allSatisfy{$0.source?.revision == revised.revision}
                checks["source date unchanged"]=facts.allSatisfy{$0.sourceDate == initial.date}
            }
        }
        let records=MemoryReviewPreview.records("fictional")
        let output=try await model.chatGPT.streamResponse(input:[["role":"user","content":MemoryReviewRules.input(records,now:.now)]],instructions:MemoryReviewRules.instructions,model:selected,purpose:.diagnostic) { _ in }
        guard let proposals=MemoryReviewRules.decode(output,records:records,registration:"fictional",now:.now) else { throw MemoryLearningFailure.invalid }
        checks["review uses only issued fact IDs"]=proposals.allSatisfy{MemoryReviewRules.current($0,records:records,registration:"fictional")}
        checks["duplicate or conflict identified"]=proposals.contains{$0.kind == .duplicate || $0.kind == .conflict}
        checks["old provisional assumption offered for review"]=proposals.contains{$0.kind == .retirement}
        checks["account and model preserved"]=account == model.chatGPT.activeID && selected == model.chatGPT.selectedModel
        checks["personal memory store untouched"]=model.assistant.memory.records.isEmpty
        return ["completed":Date.now.ISO8601Format(),"model":selected,"requests":3,"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"extractions":outputs,"proposals":proposals.map{["kind":$0.kind.rawValue,"reason":$0.reason]},"storage":"Fictional Calendar and human facts, disposable stores. No source startup, permissions changed or personal/native writes. Three focused requests are not a quality benchmark or scheduler acceptance."]
    }
}
struct MemoryReviewPreview:View {
    var model:DashboardModel
    @State private var ready=false
    @State private var selected=0
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                Text("Fictional memory review").font(.title2)
                MemoryMaintenanceView(model:model) { ids in selected=ids.count }
                if selected > 0 { Text("Selected \(selected) saved facts for inspection.") }
            }.padding(24)
        }.frame(width:720,height:720)
            .task {
                guard !ready else { return };ready=true
                let registration=model.chatGPT.activeID,records=Self.records(registration)
                model.assistant.memory.loadReviewFixture(records)
                let kinds:[MemoryReviewKind]=[.duplicate,.conflict,.retirement]
                let ids=[[records[0].id,records[1].id],[records[0].id,records[2].id],[records[3].id]]
                let entries=kinds.enumerated().map { index,kind in ["kind":kind.rawValue,"recordIDs":ids[index].map(\.uuidString),"reason":kind == .retirement ? "A temporary interpretation has not been reviewed for over 90 days. Check whether it still applies." : "These fictional Orion facts may repeat or disagree; inspect their evidence before editing."] as [String:Any] }
                let output=String(decoding:try! JSONSerialization.data(withJSONObject:["proposals":entries]),as:UTF8.self)
                if let proposals=MemoryReviewRules.decode(output,records:records,registration:registration,now:.now) { model.memoryMaintenance.seedPreview(proposals) }
            }
    }
    static func records(_ registration:String)->[PAMemory] {
        let now=Date.now
        return [
            .init(registration:registration,text:"My Orion prototype uses twelve sensors.",kind:.context,provenance:"Fictional human statement",evidence:"My Orion prototype uses twelve sensors.",certainty:.stated,durability:.stable),
            .init(registration:registration,text:"The Orion prototype I am building has twelve sensors.",kind:.context,provenance:"Fictional human statement",evidence:"The Orion prototype I am building has twelve sensors.",certainty:.stated,durability:.stable),
            .init(registration:registration,text:"My Orion prototype uses sixteen sensors.",kind:.context,provenance:"Fictional human statement",evidence:"My Orion prototype uses sixteen sensors.",certainty:.stated,durability:.stable),
            .init(registration:registration,text:"I might want to leave the temporary Orion reading group.",kind:.context,explicit:false,provenance:"Fictional provisional interpretation",created:now.addingTimeInterval(-110*86400),reviewed:now.addingTimeInterval(-100*86400),evidence:"I'm considering leaving the temporary Orion reading group.",certainty:.inferred,durability:.situational)
        ]
    }
}
#endif
