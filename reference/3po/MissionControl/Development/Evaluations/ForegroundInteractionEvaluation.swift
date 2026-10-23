#if DEBUG
import Foundation
import SwiftData

@MainActor private final class ForegroundInteractionInference:PAInferenceConnection {
    var activeID="fictional-foreground-owner",selectedModel="fictional-model"
    var busy=false,usagePaused=false,inferenceVerified=true,hasSession=true
    var held:CheckedContinuation<Void,Never>?,calls=0
    func streamResponse(input:[[String:String]],instructions:String,model:String?,effort:String,purpose:AIRequestPurpose,onDelta:@escaping(String)->Void) async throws->String {fatalError("Fictional completed-tool transport only")}
    func toolResponse(input:[[String:Any]],instructions:String,tools:[[String:Any]],model:String,purpose:AIRequestPurpose,onDelta:@escaping(String)->Void) async throws->PAResponse {
        calls += 1
        if calls == 1 {
            onDelta("Preparing the requested reminder…")
            await withCheckedContinuation{held=$0}
            let call=PAFunctionCall(id:"fictional-create-reminder",name:"change_reminder",namespace:"pa",arguments:"{}")
            return .init(text:"",output:[["type":"function_call","call_id":call.id,"name":call.name,"arguments":call.arguments]],calls:[call])
        }
        return .init(text:"Fictional reminder created and verified",output:[],calls:[])
    }
    func release() {let continuation=held;held=nil;continuation?.resume()}
}
@MainActor private final class ForegroundInteractionCursor:AssistantMailCursor {
    var status="No Mail search",results:[MailMessage]=[],hasMore=false,hasUnavailable=false
}
@MainActor private final class ForegroundInteractionTools:AssistantToolSession {
    var calendar=CalendarSnapshot(sources:[],events:[]),reminders=ReminderSnapshot(sources:[],reminders:[])
    var itemDetails:[String:NativeEditDetails]=[:],consultedMemory=Set<UUID>(),receipts:[String]=[],memoryNotes:[String]=[]
    var clarification:(String,[String])?,mailCursor:any AssistantMailCursor=ForegroundInteractionCursor()
    let repository:LocalRecordRepository
    var writes=0
    init(_ container:ModelContainer) {repository=LocalRecordRepository(container:container)}
    func execute(_ call:PAFunctionCall,valid:@escaping NativeWriteValidity) async throws->String {
        guard valid(),call.name == "change_reminder" else {throw IntegrationError.verification}
        await Task.yield()
        guard valid() else {throw IntegrationError.verification}
        writes += 1
        try repository.save(["id":"fictional-owned-reminder","title":"Follow up with fictional insurer","operation":"exact-owned-creation"],key:"fictionalInteractionReminder")
        receipts.append("Fictional reminder created and verified")
        return "{\"verified\":true,\"id\":\"fictional-owned-reminder\"}"
    }
}

/// Actual desktop attention projection/dismissal plus the real foreground engine;
/// only inference and the final reminder save use fictional local ports.
@MainActor enum ForegroundInteractionEvaluation {
    static func run()async throws->[String:Bool] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-advice-context") else {throw IntegrationError.verification}
        var checks:[String:Bool]=[:]
        for mode in ["chat-dismiss","chat-undo","review-dismiss"] {
            let model=DashboardModel(),provider=ForegroundInteractionInference()
            guard let container=model.container else {throw IntegrationError.verification}
            let suite="3PO.foreground-interaction."+UUID().uuidString,settings=UserDefaults(suiteName:suite)!
            let images=FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            defer {settings.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:images)}
            settings.set(true,forKey:"assistantContextEnabled");settings.set(true,forKey:"paMemoryEnabled")
            let assistant=AssistantService(connection:provider,container:container,settings:settings,imageDirectory:images)
            model.assistant=assistant;model.chatGPT.activeID=provider.activeID;model.chatGPT.selectedModel=provider.selectedModel
            let fields:[String:Any]=["id":"fictional-unrelated-mail","accountID":"fictional-mail","account":"Fictional Mail","messageID":1,"internetMessageID":"fixture@example.invalid","sender":"Fictional newsletter","subject":"Unrelated announcement","received":Date.now.ISO8601Format(),"unread":true,"replied":false,"flagged":false]
            let message=try JSONDecoder().decode(MailMessage.self,from:JSONSerialization.data(withJSONObject:fields))
            let summary=EmailSummary(id:message.id,registration:provider.activeID,fingerprint:EmailSummary.fingerprint(message),summary:"Unrelated announcement",attention:false,reason:"Optional reading",evidence:"Optional reading",bodyFingerprint:"fictional-body",message:message,worthReading:true)
            model.mailData = .init(messages:[message],accounts:[.init(id:message.accountID,title:"Fictional Mail")],errors:[])
            try model.emailSummaries.seedAdviceFixture([summary])
            func dismiss() {model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:provider.activeID,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary))}
            if mode == "chat-undo" {dismiss()}
            let before=model.reviewAcknowledgementRevision
            let tools=ForegroundInteractionTools(container)
            var runtime=model.assistantRuntime();runtime.tools={_ in tools};runtime.afterTurn={}
            // This fixture supplies no weather and has no location tool. Keep
            // its weather port fictional too: macOS may finish initialising
            // native permission asynchronously during the first desktop model.
            let desktopState=runtime.state
            runtime.state={
                guard var state=desktopState() else {return nil}
                state.weatherScope="fictional-no-weather"
                return state
            }
            let id:UUID
            if mode == "review-dismiss" {
                id=assistant.openReview(key:"fictional-requested-source",title:"Requested source",sourceKind:"mail",accountID:"fictional-mail",messageID:"fictional-other-source",identity:nil,chatID:nil,seeds:[])!
                assistant.draft="Retained general draft"
                guard assistant.sendReview(runtime:runtime,conversationID:id,prompt:"Add a reminder for next week",humanTurnID:UUID(),responseTurnID:UUID(),query:"Requested reminder",submitted:.now,focusAreas:[],valid:{true}) else {throw ActionFailure.message("Fictional \(mode) could not start: \(assistant.error ?? "no request")")}
            } else {
                id=assistant.openPA()!
                guard assistant.send(runtime:runtime,topicID:nil,prompt:"Add a reminder for next week") else {throw ActionFailure.message("Fictional \(mode) could not start: \(assistant.error ?? "no request")")}
            }
            for _ in 0..<40000 {if provider.held != nil || !assistant.busy {break};await Task.yield()}
            guard provider.held != nil else {throw ActionFailure.message("Fictional \(mode) did not reach inference: \(assistant.error ?? "no active request")")}
            if mode == "chat-undo" {model.emailSummaries.undoDismiss(model)} else {dismiss()}
            let changed=model.reviewAcknowledgementRevision,saved=ReviewInferenceGuard.fingerprint(model.emailSummaries.records)
            provider.release()
            for _ in 0..<40000 {if !assistant.busy {break};await Task.yield()}
            let turn=assistant.conversation(id)?.turns.last
            let persisted:[String:String]?=try tools.repository.decode("fictionalInteractionReminder")
            if assistant.error != nil || tools.writes != 1 || provider.calls != 2 {
                let detail="Fictional foreground \(mode): calls=\(provider.calls), writes=\(tools.writes), phase=\(turn?.actionResult?.phase ?? "missing"), error=\(assistant.error ?? "none")\n"
                FileHandle.standardError.write(Data(detail.utf8))
            }
            checks["Foreground \(mode) exercises the actual changed desktop acknowledgement"]=before != changed
            checks["Foreground \(mode) completes the owned reminder request"] = !assistant.busy && assistant.error == nil && turn?.actionResult?.phase == "completed"
            checks["Foreground \(mode) saves exactly once with verified receipt"]=tools.writes == 1 && tools.receipts.count == 1 && persisted?["operation"] == "exact-owned-creation"
            checks["Foreground \(mode) preserves exact unrelated dismissal timestamp and source version"]=ReviewInferenceGuard.fingerprint(model.emailSummaries.records) == saved && model.reviewAcknowledgementRevision == changed
            checks["Foreground \(mode) preserves completion across reopening"]=turn?.actionResult?.phase == "completed" && AssistantService(connection:provider,container:container,settings:settings,imageDirectory:images).conversation(id)?.turns.last?.actionResult == turn?.actionResult
            checks["Foreground \(mode) makes no subscription request"]=provider.calls == 2 && model.aiUsage.state.records.isEmpty
            if mode == "review-dismiss" {checks["Foreground Review interaction retains the unsent general draft"]=assistant.draft == "Retained general draft"}
        }
        return checks
    }
}
#endif
