#if DEBUG
import Foundation
import SwiftData
@MainActor enum LifeOwnershipEvaluation {
    static func run(_ model:DashboardModel) async throws -> [String:Any] {
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let account=model.chatGPT.activeID,selected=model.chatGPT.selectedModel,store=LifeWorkspaceStore(container:container)
        var checks:[String:Bool]=[:]
        func call(_ name:String,_ args:[String:Any]) throws -> PAFunctionCall { .init(id:UUID().uuidString,name:name,namespace:"pa",arguments:String(decoding:try JSONSerialization.data(withJSONObject:args,options:.sortedKeys),as:UTF8.self)) }
        func session(_ human:String,_ history:[[String:String]]=[])->PAToolSession { .init(model:model,human:human,humanContext:human,topicID:nil,turnID:UUID(),history:history,evaluationProjects:store) }
        let valid:NativeWriteValidity = { model.chatGPT.activeID == account && model.chatGPT.selectedModel == selected }
        let read:[String:Any]=["query":"","root":NSNull(),"unfinished":false,"dueBefore":NSNull(),"maxMinutes":NSNull(),"deleted":false]
        func entry(_ title:String,_ kind:String,_ parent:Any=NSNull())->[String:Any] { ["title":title,"kind":kind,"parent":parent,"notes":"","due":NSNull(),"estimateMinutes":NSNull(),"areas":[]] }
        let mention="I am studying Optics this year."
        do { _ = try await session(mention).execute(call("create_life_items",["items":[entry("Optics","course")],"authorization":mention]),valid:valid);checks["mere mention does not create workspace"]=false } catch { checks["mere mention does not create workspace"]=store.items(account).isEmpty }
        let create="Create an Optics Study project with a Reading folder."
        _ = try await session(create).execute(call("create_life_items",["items":[entry("Optics Study","project"),entry("Reading","section","batch:0")],"authorization":create]),valid:valid)
        checks["explicit creation executes"]=store.items(account).count == 2
        let yes="Yes, create it.",accept=session(yes,[["role":"assistant","content":"Should I create a Portfolio project?"]])
        _ = try await accept.execute(call("read_life_items",read),valid:valid)
        _ = try await accept.execute(call("create_life_items",["items":[entry("Portfolio","project")],"authorization":yes]),valid:valid)
        checks["accepted proposal executes"]=store.items(account).contains{$0.title == "Portfolio"}
        let project=store.items(account).first{$0.title == "Optics Study"}!,child=store.items(account).first{$0.title == "Reading"}!
        let delete="Delete Optics Study but keep all its contents.",remove=session(delete)
        _ = try await remove.execute(call("read_life_items",read),valid:valid)
        _ = try await remove.execute(call("delete_life_item",["id":project.id.uuidString,"keepChildren":true,"authorization":delete]),valid:valid)
        checks["actual recoverable deletion keeps contents"]=store.items(account).contains(where:{$0.id == child.id && $0.parentID == nil}) && !store.items(account).contains(where:{$0.id == project.id})
        let restore="Restore Optics Study.",recovery=session(restore)
        var trashRead=read;trashRead["deleted"]=true
        _ = try await recovery.execute(call("read_life_items",trashRead),valid:valid)
        _ = try await recovery.execute(call("restore_life_item",["id":project.id.uuidString,"authorization":restore]),valid:valid)
        checks["actual restore retains identity"]=store.items(account).contains{$0.id == project.id}
        checks["selected model unchanged"]=valid()
        return ["completed":Date.now.ISO8601Format(),"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"model":selected,"boundary":"Production semantic human-intent validation and actual local tools on fictional disposable SwiftData; no source startup, personal transcripts or native writes."]
    }
}
#endif
