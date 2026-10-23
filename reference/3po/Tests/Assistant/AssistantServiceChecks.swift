import Foundation
import SwiftData
import Observation

private final class ObservationCounter:@unchecked Sendable {
    private let lock=NSLock()
    private var count=0
    var value:Int {lock.withLock{count}}
    func increment() {lock.withLock{count += 1}}
}

@MainActor private final class FictionalInference: PAInferenceConnection {
    var activeID = "fictional-owner"
    var selectedModel = "fictional-model"
    var busy = false
    var usagePaused = false
    var inferenceVerified = true
    var hasSession = true
    var replies: [PAResponse] = []
    var holdNext = false
    var deltas=["Fictional partial"]
    var afterDelta:(@MainActor ()->Void)?
    private var held: CheckedContinuation<Void, Never>?
    private(set) var inputs: [[[String: Any]]] = []
    private(set) var instructions: [String] = []
    private(set) var topLevelInstructions: [String] = []
    private(set) var purposes: [AIRequestPurpose] = []
    private(set) var models:[String] = []
    private(set) var efforts:[String] = []
    private(set) var toolNames:[[String]] = []
    var waiting: Bool { held != nil }
    func release() { let value = held; held = nil; value?.resume() }
    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        preconditionFailure("These assistant fixtures must use completed tool transport.")
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        toolNames.append((tools.first?["tools"] as? [[String:Any]] ?? []).compactMap { $0["name"] as? String })
        inputs.append(input); topLevelInstructions.append(instructions)
        let developerText = input.filter { $0["role"] as? String == "developer" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }
        self.instructions.append(([instructions] + developerText).filter { !$0.isEmpty }.joined(separator: "\n")); purposes.append(purpose);models.append(model)
        for text in deltas {onDelta(text);afterDelta?()}
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0 }
        }
        try Task.checkCancellation()
        precondition(!replies.isEmpty, "Missing fictional response")
        return replies.removeFirst()
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        efforts.append(effort)
        return try await toolResponse(input:input,instructions:instructions,tools:tools,model:model,purpose:purpose,onDelta:onDelta)
    }
}

@MainActor private final class FictionalMailCursor: AssistantMailCursor {
    var status = "Fictional bounded mail search"
    var results: [MailMessage] = []
    var hasMore = false
    var hasUnavailable = false
}

@MainActor private final class FictionalTools: AssistantToolSession {
    var calendar = CalendarSnapshot(sources: [], events: [])
    var reminders = ReminderSnapshot(sources: [], reminders: [])
    var itemDetails: [String: NativeEditDetails] = [:]
    var consultedMemory: Set<UUID> = []
    var consultedWorkspace: Set<UUID> = []
    var suppliedWeatherScope:String?
    var suppliedWhatsAppScope:WhatsAppSourceScope?
    var receipts: [String] = []
    private(set) var actionCountReads=0
    var confirmedActionCount:Int {actionCountReads += 1;return receipts.count}
    var pendingNativeActionCount=0
    var actionReceiptsReadable=true
    var memoryNotes: [String] = []
    var clarification: (String, [String])?
    let mailCursor: any AssistantMailCursor = FictionalMailCursor()
    var executeBody: ((PAFunctionCall, FictionalTools) throws -> String)?
    private(set) var calls: [String] = []
    func execute(_ call: PAFunctionCall, valid: @escaping NativeWriteValidity) async throws -> String {
        try Task.checkCancellation()
        guard valid() else { throw ActionFailure.message("Fictional owned context changed") }
        calls.append(call.name)
        if call.name == "ask_clarification" { clarification = ("Which fictional option?", ["First", "Second"]) }
        return try executeBody?(call, self) ?? "{\"verified\":true}"
    }
}

@MainActor private final class FictionalContext {
    let now = Date.now.addingTimeInterval(3600)
    var state = AssistantRuntimeState(attentionPreferencesReadable: true, resolvedRequests: [], whatsappScope: .init(registration: "fictional-owner", linkedIdentity: "fictional-device", revision: UUID()), weatherScope: "fictional-weather")
    var attentionRevision="ack-1"
    var acknowledgements:[ReviewAcknowledgement] = []
    var sourceCalls = 0
    var streamingStorageCurrent = true
    var afterCalls = 0
    var requests: [AssistantToolRequest] = []
    var sessions: [FictionalTools] = []
    var configure: ((FictionalTools, AssistantToolRequest) -> Void)?
    var pageCapture: (String, String?, UUID?, Bool, Bool) -> AssistantPageContext = { _,_,_,_,_ in .init() }
    func runtime() -> AssistantRuntime {
        .init(clock: { self.now }, state: { self.state }, sourceSnapshot: { self.sourceCalls += 1; return "Fictional cached context\n" + String(decoding:try! JSONEncoder().encode(self.acknowledgements),as:UTF8.self) }, deliveryAvailable: { $0.deliveryID != "fictional-withdrawn" }, tools: { request in
            let session = FictionalTools()
            self.configure?(session, request)
            self.requests.append(request); self.sessions.append(session)
            return session
        }, afterTurn: { self.afterCalls += 1 }, streamingState: { .init(storageCurrent:self.streamingStorageCurrent,whatsappScope:self.state.whatsappScope,weatherScope:self.state.weatherScope) }, lookupAccess: { "fictional-access:" + $0 }, contextPages: { self.pageCapture($0,$1,$2,$3,$4) })
    }
}

@main struct AssistantServiceChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { count += 1; precondition(value, message) }
        func until(_ condition: () -> Bool) async {
            for _ in 0..<20_000 { if condition() { return }; await Task.yield() }
            preconditionFailure("Fictional assistant did not settle")
        }
        func final(_ text: String) -> PAResponse { .init(text: text, output: [], calls: []) }
        func tools(_ names: [String]) -> PAResponse {
            let calls = names.enumerated().map { PAFunctionCall(id: "fictional-\($0.offset)-\(UUID().uuidString)", name: $0.element, namespace: "pa", arguments: "{}") }
            return .init(text: "", output: [["type": "reasoning", "encrypted_content": "fictional-reasoning"]] + calls.map { ["type": "function_call", "call_id": $0.id, "name": $0.name, "arguments": $0.arguments] }, calls: calls)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("3po-assistant-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "3po-assistant-fixture-" + UUID().uuidString
        let settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        settings.set(true, forKey: "assistantContextEnabled")
        settings.set(true, forKey: "paMemoryEnabled")
        settings.set(true, forKey: "paMemoryLearningEnabled")
        func open(_ name: String) throws -> ModelContainer {
            try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(url: directory.appendingPathComponent(name + ".store"), cloudKitDatabase: .none))
        }
        func service(_ provider: FictionalInference, _ container: ModelContainer) -> AssistantService {
            AssistantService(connection: provider, container: container, settings: settings, imageDirectory: directory.appendingPathComponent("images"))
        }
        func greetingPages() -> AssistantPageContext {
            .init(text:"{\"featureInstructions\":[{\"feature\":\"assistant\",\"markdown\":\"Fictional complete guidance\",\"available\":\"true\",\"partial\":\"false\"}]}",referenceVersions:["instruction:assistant":"policy-v1"])
        }

        do {
            let p=FictionalInference(),c=FictionalContext(),store=try open("lookup-history"),value=service(p,store)
            let page=PAFunctionCall(id:"lookup-page",name:"read_context_page",namespace:"pa",arguments:"{\"id\":null,\"query\":\"Orion design\",\"offset\":null}")
            let mail=PAFunctionCall(id:"lookup-mail",name:"search_mail",namespace:"pa",arguments:"{\"terms\":[\"Orion\",\"review\"],\"start\":\"2026-10-01\",\"end\":\"2026-10-22\",\"folders\":[\"inbox\",\"sent\"]}")
            let reminders=PAFunctionCall(id:"lookup-reminders",name:"read_reminders",namespace:"pa",arguments:"{}")
            c.configure={session,_ in session.executeBody={call,_ in
                if call.name == "read_context_page" { return "{\"pages\":[{\"id\":\"fictional-page\",\"markdown\":\"PRIVATE_BODY_NOT_IN_TRACE\"}]}" }
                if call.name == "search_mail" { return "{\"sources\":[{\"body\":\"PRIVATE_BODY_NOT_IN_TRACE\"},{\"bodyAvailable\":false}]}" }
                throw ActionFailure.message("Fictional read failure")
            }}
            let calls=[page,mail,reminders]
            p.replies=[.init(text:"",output:calls.map{["type":"function_call","call_id":$0.id,"name":$0.name,"arguments":$0.arguments]},calls:calls),final("Fictional lookup answer")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Find Orion design and review context"),"Search history fixture starts")
            await until{!value.busy}
            let capture=value.feed!.turns.last!.contextCapture!,rows=capture.lookups!
            check(rows.map(\.tool) == ["read_context_page","search_mail","read_reminders"] && rows.map(\.status) == ["completed","completed","failed"],"Lookup history distinguishes completed and failed reads in execution order")
            check(rows[0].query == "Orion design" && rows[0].pageIDs == ["fictional-page"] && rows[0].resultCount == 1,"Page queries and exact returned page IDs are inspectable")
            check(rows[1].query == "Orion, review" && rows[1].resultCount == 2 && rows[1].filters.count == 2,"Mail trace uses actual terms, date/folder scope and returned source count")
            let encoded=String(decoding:try JSONEncoder().encode(capture),as:UTF8.self)
            check(!encoded.contains("PRIVATE_BODY_NOT_IN_TRACE") && !encoded.contains("Fictional read failure"),"Search traces duplicate no source bodies or tool error prose")
            check(capture.registration == p.activeID && capture.retrievalQuery == "Find Orion design and review context" && capture.retrievalAccess == "fictional-access:read_context_page","Initial retrieval is separate from model tool searches and keeps exact ownership")
            let reopened=service(FictionalInference(),store)
            check(reopened.feed?.turns.last?.contextCapture?.lookups == rows,"Search queries, outcomes and IDs survive reopening")
            check(AssistantLookupTrace.request(tool:"change_reminder",namespace:"pa",arguments:"{\"authorization\":\"PRIVATE_AUTHORITY_NOT_TRACE\"}",access:"fixture") == nil,"Action payloads never become lookup traces")
            var bounded=capture
            for _ in 0..<80 {
                var row=AssistantLookupTrace(tool:"read_context_page",query:String(repeating:"q",count:400),accessFingerprint:"fixture")
                row.finish(output:String(decoding:try JSONSerialization.data(withJSONObject:["pages":(0..<12).map{["id":String(repeating:"p",count:170)+String($0)]}]),as:UTF8.self),succeeded:true)
                bounded.appendLookup(row)
            }
            let lookupBytes=try JSONEncoder().encode(bounded.lookups).count
            check((bounded.lookups?.count ?? 0) <= 32 && lookupBytes <= 16_000 && (bounded.omittedLookups ?? 0) > 0,"Completed lookup histories remain bounded without limiting tool execution")
        }

        for revoked in ["account","memory","sources","storage"] {
            settings.set(true,forKey:"paMemoryEnabled");settings.set(true,forKey:"assistantContextEnabled")
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("stream-light-gate-"+revoked))
            var emitted=0,firstPartial=""
            p.deltas=["First provisional word","Must stay hidden","Still hidden"];p.replies=[final("Must not complete")]
            p.afterDelta={
                emitted += 1
                guard emitted == 1 else {return};firstPartial=value.feed?.turns.last?.content ?? ""
                switch revoked {
                case "account":p.activeID="fictional-other-owner"
                case "memory":value.memory.enabled=false
                case "sources":value.contextEnabled=false
                default:c.streamingStorageCurrent=false
                }
            }
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Explain fictional Orion context"),"Light streaming guard fixture starts")
            await until{!value.busy}
            if revoked != "account" { check(value.feed?.turns.last?.content == firstPartial && value.feed?.turns.last?.completed == false,"Light access/storage gates stop later fragments and reject completion") }
            check(c.sessions.first?.calls.isEmpty == true && value.error != nil,"Light streaming withdrawal cannot execute a late tool")
            settings.set(true,forKey:"paMemoryEnabled");settings.set(true,forKey:"assistantContextEnabled")
        }

        do {
            for prompt in ["hey", " HI \n", "Hello"] {
                check(AssistantGreetingRequest.eligible(prompt,history:[]), "Only literal social openings are eligible")
            }
            for prompt in ["hey, add a task", "hi there", "\"hey\"", "don't say hello", "hello?", "hello\nremember this"] {
                check(!AssistantGreetingRequest.eligible(prompt,history:[]), "Other human requests keep full assistant routing")
            }
            let question=AssistantTurn(role:"assistant",content:"How should the fictional message begin?",completed:true)
            check(!AssistantGreetingRequest.eligible("hi",history:[question]), "A greeting can answer an essential question")
            var pending=AssistantTurn(role:"assistant",content:"Prepared fictional action",completed:true)
            pending.actionApprovals=[.init(toolName:"change_reminder",arguments:"{}",snapshot:Data(),outline:[],details:[])]
            check(!AssistantGreetingRequest.eligible("hey",history:[pending]), "Pending authority is checked before prepare can dismiss it")
            pending.actionApprovals=nil;pending.choices=["hi","bye"]
            check(!AssistantGreetingRequest.eligible("hi",history:[pending]), "Answer buttons keep normal context")
            pending.choices=nil;pending.actionResult = .init(phase:"uncertain",receipts:[],confirmedActions:0,unconfirmedActions:1)
            check(!AssistantGreetingRequest.eligible("hey",history:[pending]), "An uncertain action cannot take the social route")
            check(!AssistantGreetingRequest.accepts(.init(id:"bad",name:"change_reminder",namespace:"pa",arguments:"{}")) && !AssistantGreetingRequest.accepts(.init(id:"bad",name:"read_assistant_context",namespace:"other",arguments:"{}")) && !AssistantGreetingRequest.accepts(.init(id:"bad",name:"read_assistant_context",namespace:"pa",arguments:"{\"extra\":true}")), "Compact routing refuses mutations, other namespaces and unknown arguments")
            check(!AssistantGreetingRequest.hasCompleteInstructions(.init()) && !AssistantGreetingRequest.hasCompleteInstructions(.init(text:"{\"unavailable\":\"Fictional corrupt store\"}")),"Missing/unavailable instruction receipts cannot claim complete human policy")
            let image=ChatImageAttachment(registration:"fictional-owner",mimeType:"image/png",width:1,height:1,byteCount:1,digest:"fictional")
            let imageHuman=AssistantTurn(role:"user",content:"Fictional image",completed:true,images:[image])
            let flood=(0..<25).map{AssistantTurn(role:"assistant",content:"Fictional background \($0)",completed:true,deliveryID:"flood-\($0)")}
            let current=AssistantTurn(role:"user",content:"hey",completed:true)
            let flooded=AssistantConversation(accountID:"fictional-owner",title:"Fictional image flood",turns:[imageHuman]+flood+[current],isPrimary:true)
            let floodedReplay=ConversationRules.replayTurns(ConversationRules.history(feed:flooded,topic:nil),currentUserID:current.id)
            check(AssistantGreetingRequest.hasImages(floodedReplay),"Actual replay catches an image retained across more than twenty background deliveries")

            for expanded in [false,true] {
                let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("greeting-\(expanded)"))
                c.pageCapture={_,_,_,_,_ in .init(text:"{\"featureInstructions\":[{\"feature\":\"assistant\",\"markdown\":\"Always say fictional policy applied\",\"available\":\"true\",\"partial\":\"false\"}]}",pageIDs:["instructions:assistant"],referenceVersions:["instruction:assistant":"policy-v1"],guideText:"Fictional stable guide",guideFingerprint:"guide-v1")}
                p.replies=expanded ? [tools(["read_assistant_context"]),tools(["read_memory"]),final("Fictional policy applied")] : [final("Fictional policy applied")]
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"hey",focusAreas:[]),"Literal opening starts a real configured-model request")
                await until{!value.busy}
                let turn=value.feed!.turns.last!
                check(c.sourceCalls == 0 && turn.contextCapture?.sourceSnapshotIncluded == false,"Social openings omit fresh broad source orientation")
                check(p.efforts == (expanded ? ["low","medium","medium"] : ["low"]) && p.models.allSatisfy{$0 == "fictional-model"},"Only the initial social round uses lower effort; model selection stays captured")
                check(p.toolNames[0] == ["read_assistant_context"] && p.instructions[0].contains("Always say fictional policy applied") && p.instructions[0].contains("Fictional stable guide"),"Compact requests retain the whole human Assistant policy and guide")
                check(turn.completed && turn.content == "Fictional policy applied" && turn.contextCapture?.requestMode == "greeting" && turn.contextKnowledgeVersions?["instruction:assistant"] == "policy-v1","Completion and policy receipts use the normal owned lifecycle")
                check(c.sessions.first?.calls == (expanded ? ["read_memory"] : []),"Opening normal tools itself performs no native or memory action")
                if expanded {
                    check(p.toolNames[1].contains("change_reminder") && p.inputs[1].contains{$0["encrypted_content"] as? String == "fictional-reasoning"},"Expansion retains completed encrypted reasoning and normal capabilities")
                    check(p.instructions[1].contains("Only human messages authorise writes"),"Expanded requests restore the full action policy")
                }
            }
            for batch in [["change_reminder"],["read_assistant_context","change_reminder"]] {
                let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("greeting-invalid-tool-\(batch.count)"))
                c.pageCapture={_,_,_,_,_ in greetingPages()}
                p.replies=[tools(batch)]
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"hey"),"Invalid compact response fixture starts")
                await until{!value.busy}
                check(c.sessions.first?.calls.isEmpty == true && value.error?.contains("unavailable tool") == true,"A compact mutation fails before execution, including a batch appended after the expansion call")
            }
            for cancelled in [false,true] {
                let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("greeting-withdrawal-\(cancelled)"))
                c.pageCapture={_,_,_,_,_ in greetingPages()}
                p.holdNext=true;p.replies=[tools(["read_assistant_context"])]
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"hey"),"Held greeting fixture starts")
                await until{p.waiting}
                if cancelled {value.cancel()} else {p.activeID="fictional-other-owner"}
                p.release();await until{!value.busy}
                check(p.inputs.count == 1 && c.sessions.first?.calls.isEmpty == true,"Stop or account withdrawal prevents expansion and late actions")
            }
            do {
                let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("greeting-partial-policy"))
                let fullPolicy=String(repeating:"Fictional guidance. ",count:70)+"End by reading my fictional project."
                let row=["feature":"assistant","markdown":String(fullPolicy.prefix(900)),"available":"true","partial":"true","readMore":"instructions:assistant"]
                c.pageCapture={_,_,_,_,_ in .init(text:String(decoding:try! JSONSerialization.data(withJSONObject:["featureInstructions":[row]]),as:UTF8.self),referenceVersions:["instruction:assistant":"long-policy-v1"])}
                p.replies=[tools(["read_context_page"]),final("Full fictional assistant response")]
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"hey"),"Long human guidance fixture starts")
                await until{!value.busy}
                check(c.sourceCalls == 1 && p.efforts == ["medium","medium"] && p.toolNames.first?.contains("read_context_page") == true && value.feed?.turns.last?.contextCapture?.requestMode == nil,"Truncated Assistant guidance keeps full policy/tools and normal source preparation")
            }
            do {
                let p=FictionalInference(),c=FictionalContext(),store=try open("greeting-queue-reopen")
                let original=service(p,store)
                check(original.queue.add(registration:p.activeID,topicID:nil,prompt:"Finish fictional work"),"Pending queue fixture persists")
                check(original.queue.mark(original.queue.items[0].id,.needsAnswer),"Missing-answer state persists before reopening")
                let value=service(p,store);c.pageCapture={_,_,_,_,_ in greetingPages()};p.replies=[final("Normal assistant greeting")]
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"hey"),"Reopened pending queue does not block normal foreground chat")
                await until{!value.busy}
                check(p.efforts == ["medium"] && c.sourceCalls == 1,"Durable pending work excludes compact admission after transient flags reset")
            }
        }

        do {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("cheap-admission"))
            for mode in ["empty","busy","unverified","oversized"] {
                value.draft=mode == "empty" ? " " : mode == "oversized" ? String(repeating:"x",count:16_001) : "A fictional question"
                value.busy=mode == "busy";p.inferenceVerified=mode != "unverified"
                value.send(runtime:c.runtime())
            }
            check(c.sourceCalls == 0 && c.requests.isEmpty,"Rejected messages perform no source projection or tool preparation")
        }

        do {
            let question=AssistantTurn(role:"assistant",content:"Which time?",completed:true,created:.now)
            var conversation=AssistantConversation(accountID:"fixture",title:"Reply metadata",turns:[question])
            check(AssistantActivityContext(conversation).repliesAfter[question.id] == nil,"An unanswered action question remains pending")
            let reply=AssistantTurn(role:"user",content:"Use noon",completed:true,created:.distantPast)
            conversation.turns.append(reply)
            let answered=AssistantActivityContext(conversation)
            check(answered.repliesAfter[question.id] == reply.id,"Accepted later transcript replies resolve questions even with earlier queued timestamps")
            conversation.turns[0].content="A streamed partial variant"
            check(AssistantActivityContext(conversation) == answered,"Question resolution metadata never observes streamed prose")
            conversation.turns[1].contextID=UUID()
            check(AssistantActivityContext(conversation).repliesAfter[question.id] == nil,"Replies in another captured conversation scope do not resolve a question")
            conversation.turns[1].contextID=nil;conversation.turns[1].deliveryID="background-delivery"
            check(AssistantActivityContext(conversation).repliesAfter[question.id] == nil,"Imported deliveries are not human answers")
        }
        let streamProvider=FictionalInference(),streamContext=FictionalContext()
        let streamService=service(streamProvider,try open("stream-observation"))
        let streamID=streamService.openPA()!
        streamProvider.deltas=(1...200).map{"Fictional streamed response \($0)"}
        streamProvider.replies=[final("Completed fictional streaming response")]
        check(streamService.send(runtime:streamContext.runtime(),topicID:nil,prompt:"Fictional streaming request"),"Streaming fixture starts the actual assistant service")
        let transcriptChanges=ObservationCounter(),activityChanges=ObservationCounter()
        @MainActor func observeStreaming() {
            withObservationTracking({_ = streamService.conversation(streamID)},onChange:{transcriptChanges.increment()})
            withObservationTracking({_ = streamService.activityContext(streamID)},onChange:{activityChanges.increment()})
        }
        let streamingRevision=streamService.transcriptRevision
        observeStreaming();streamProvider.afterDelta={
            check(streamService.transcriptRevision == streamingRevision,"Ordinary streamed prose must not invalidate the structural transcript projection")
            observeStreaming()
        }
        await until{!streamService.busy}
        check(transcriptChanges.value >= 200,"Each real streamed delta updates the displayed transcript")
        check(activityChanges.value == 0,"Streamed prose never invalidates Activity metadata")
        check(streamService.transcriptRevision != streamingRevision,"The completed saved response advances the structural transcript revision")
        check(streamService.feed?.turns.last?.content == "Completed fictional streaming response","Removing Activity observation retains the full final response")
        streamProvider.activeID="different-fictional-account"
        check(streamService.activityContext(streamID) == nil && streamService.conversation(streamID) == nil,"Exact context lookup still excludes other accounts")
        print("Streaming observation:200 deltas; transcript invalidations \(transcriptChanges.value); Activity invalidations \(activityChanges.value)")

        let provider = FictionalInference(), context = FictionalContext(), container = try open("normal")
        let preferencesBeforeConstruction = NSDictionary(dictionary:settings.persistentDomain(forName:suite) ?? [:])
        let assistant = service(provider, container)
        check(preferencesBeforeConstruction.isEqual(to:settings.persistentDomain(forName:suite) ?? [:]), "Constructing the assistant must not persist fallback preferences or source selections")
        let fact = PAMemory(registration: provider.activeID, text: "My AI coursework is a current study priority.", kind: .context, explicit: true, provenance: "Fictional human")
        check(assistant.memory.put(fact), "Fixture memory must save in disposable storage.")
        let widget = UUID()
        assistant.drafts.set("Retained fictional unsent draft", registration: provider.activeID, widget: widget, conversation: nil)
        assistant.drafts.flush()
        context.configure = { session, request in
            session.executeBody = { call, session in
                if call.name == "read_memory" {
                    session.consultedMemory.insert(fact.id)
                    return String(decoding: try JSONSerialization.data(withJSONObject: ["records": [["id": fact.id.uuidString, "text": fact.text]]]), as: UTF8.self)
                }
                if call.name == "remember_context" {
                    let entry = PAMemory(registration: request.registration, text: "I prefer a short coursework plan.", kind: .preference, explicit: true, provenance: "Fictional current request", sourceTurnID: request.turnID.uuidString)
                    guard assistant.memory.put(entry) else { throw ActionFailure.message("Fixture memory save failed") }
                    session.receipts.append("Fictional memory saved and verified")
                }
                return "{\"verified\":true}"
            }
        }
        provider.replies = [tools(["read_memory", "remember_context"]), final("Completed fictional coursework plan")]
        assistant.draft = "Keep the visible fixture draft"
        check(assistant.send(runtime: context.runtime(), topicID: nil, prompt: "Help with my AI coursework; remember that I prefer a short plan.", focusAreas: [.studies]), "Actual service must accept a normal request.")
        check(assistant.busy && assistant.draft == "Keep the visible fixture draft", "Preparation must preserve the caller's draft and mark only its reply busy.")
        await until { !assistant.busy }
        let reply = assistant.feed!.turns.last!
        check(reply.completed && reply.content == "Completed fictional coursework plan", "Completed transport must supersede partial text and receipts.")
        check(reply.contextCapture?.memoryIDs.isEmpty == true && reply.contextCapture?.directMemoryIDs == [] && reply.contextCapture?.consultedMemoryIDs == [fact.id], "Ordinary chat reads original facts on demand, separately from its initial page context.")
        let initialInput = String(describing: provider.inputs.first!)
        check(!initialInput.contains(fact.text) && !initialInput.contains("\"savedMemory\""), "Ordinary preparation does not inject the matching raw fact or the old saved-memory list")
        check(String(describing: provider.inputs.last!).contains(fact.text), "An explicit successful fact lookup still supplies its original text to the model")
        check(reply.contextCapture?.attemptedTools == ["read_memory", "remember_context"] && reply.focusAreas == [.studies], "Actual execution traces and captured Focus must stay on the response.")
        check(reply.contextCapture?.selectionPurpose == "conversation" && reply.contextCapture?.usedFollowupContext == false,"Actual preparation uses the shared context policy and retains its small trace")
        check(reply.created == context.now && reply.contextCapture?.captured == context.now, "Preparation and trace dates must use the injected clock.")
        check(context.sessions.first?.receipts == ["Fictional memory saved and verified"] && context.afterCalls == 1, "Verified receipts must persist across rounds and finish once.")
        check(provider.inputs.last?.contains(where: { $0["encrypted_content"] as? String == "fictional-reasoning" }) == true, "Actual service must replay completed reasoning output.")
        check(provider.instructions.first?.contains(DateRules.localTimestamp(context.now)) == true, "Inference instructions must use the captured fictional clock.")
        check(provider.topLevelInstructions.allSatisfy(\.isEmpty) && provider.inputs.allSatisfy { $0.filter { $0["role"] as? String == "developer" }.count == 2 }, "Each tool round has exactly one stable and one current developer block, without changing top-level instructions.")
        let prefix = provider.inputs[0][0]["content"] as! [[String: Any]]
        let current = provider.inputs[0].filter { $0["role"] as? String == "developer" }[1]["content"] as! [[String: Any]]
        check(!(prefix[0]["text"] as! String).contains(DateRules.localTimestamp(context.now)) && (current[0]["text"] as! String).contains(DateRules.localTimestamp(context.now)), "Changing clocks stay behind the reusable policy boundary.")
        let historical: [[String: Any]] = [["role": "user", "content": "Fictional current human evidence"], ["type": "function_call_output", "call_id": "original-operation", "output": "original receipt"]]
        let firstPrompt = AssistantRequestPrompt(stable: "Stable fictional guide", current: "Clock A; source hint A")
        let nextPrompt = AssistantRequestPrompt(stable: "Stable fictional guide", current: "Clock B; source hint B")
        let firstInput = firstPrompt.input(around: historical)
        let nextInput = nextPrompt.input(around: historical)
        check(try JSONSerialization.data(withJSONObject: firstInput[0], options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: nextInput[0], options: [.sortedKeys]), "New clocks and selected source hints leave the complete cacheable prefix unchanged.")
        check(firstInput[1]["role"] as? String == "user" && firstInput[2]["role"] as? String == "developer", "The original human message ends the reusable initial developer block before changing context.")
        check(try JSONSerialization.data(withJSONObject: firstInput.filter { $0["role"] as? String != "developer" }, options: [.sortedKeys]) == JSONSerialization.data(withJSONObject: historical, options: [.sortedKeys]), "Human evidence and completed operation transport retain their exact order and payloads.")
        check(!String(describing: firstInput).contains("prompt_cache_breakpoint"), "Implicit caching adds no unsupported cache parameter.")
        let originalIDs = assistant.feed!.turns.map(\.id)
        let reopened = service(FictionalInference(), try open("normal"))
        check(reopened.feed?.turns.map(\.id) == originalIDs && reopened.feed?.turns.last?.contextCapture == reply.contextCapture, "Reopening must preserve turn identities, completed replies and exact traces.")
        check(reopened.memory.records.contains(where: { $0.text == "I prefer a short coursework plan." }), "Verified memory changes must survive reopening.")
        check(reopened.drafts.text(registration: provider.activeID, widget: widget, conversation: nil) == "Retained fictional unsent draft", "Unrelated unsent drafts must survive the conversation run.")

        let history = AssistantConversation(accountID: provider.activeID, title: "Fictional history", turns: [
            .init(role: "user", content: "Retained fictional human turn", completed: true, created: context.now),
            .init(role: "assistant", content: "Withdrawn fictional source advice", completed: true, deliveryID: "fictional-withdrawn", created: context.now)
        ], isPrimary: true)
        check(assistant.sourceSafeHistory(runtime: context.runtime(), feed: history, topic: nil).map(\.content) == ["Retained fictional human turn"], "Injected delivery support must withdraw stale source advice without discarding human history.")

        do {
            var turns: [AssistantTurn] = []
            for index in 0..<300 {
                turns.append(.init(role:"user",content:"Fictional dialogue \(index)",completed:true,created:context.now.addingTimeInterval(Double(index*2))))
                turns.append(.init(role:"assistant",content:"Fictional update \(index)",completed:true,deliveryID:"delivery-\(index)",created:context.now.addingTimeInterval(Double(index*2+1))))
            }
            // The recent rejected deliveries must expose older permitted updates.
            // A shared legacy identity also keeps its conservative all-turn gate.
            turns[1].deliveryID="delivery-292";turns[1].content="Unavailable shared identity"
            let feed=AssistantConversation(accountID:provider.activeID,title:"Wide fictional history",turns:turns,isPrimary:true)
            func available(_ turn: AssistantTurn) -> Bool {
                turn.content != "Unavailable shared identity" && !Set((294..<300).map{"delivery-\($0)"}).contains(turn.deliveryID ?? "")
            }
            let excluded=Set(turns.compactMap { turn -> String? in turn.deliveryID != nil && !available(turn) ? turn.deliveryID : nil })
            let expected=ConversationRules.history(feed:feed,topic:nil,excludedDeliveries:excluded)
            var runtime=context.runtime(),checks=0
            runtime.deliveryAvailable={checks += 1;return available($0)}
            let actual=assistant.sourceSafeHistory(runtime:runtime,feed:feed,topic:nil)
            check(actual == expected,"Lazy delivery support retains the exact previous history result, including refill and shared identities")
            check(checks < 20,"Old background deliveries outside bounded replay require no expensive evidence checks")
            let current=turns.last(where:{$0.role == "user"})!.id
            check(ConversationRules.replayTurns(actual,currentUserID:current) == ConversationRules.replayTurns(expected,currentUserID:current),"Bounded delivery validation preserves exact provider replay")
        }

        do {
            let kept=AssistantTurn(role:"assistant",content:"Current fictional page reply",completed:true,created:context.now,contextKnowledgeVersions:["page:kept":"v1"])
            let stale=AssistantTurn(role:"assistant",content:"Stale fictional page reply",completed:true,created:context.now,contextKnowledgeVersions:["page:stale":"v1"])
            let feed=AssistantConversation(accountID:provider.activeID,title:"Fictional page history",turns:[history.turns[0],kept,stale],isPrimary:true)
            var runtime=context.runtime(),batches=0,current=true
            runtime.pageKnowledgeAvailable={_,_ in preconditionFailure("History must use its one fresh batch")}
            runtime.pageKnowledgeAvailability={registration,captures in
                batches += 1
                precondition(registration == provider.activeID && captures.count == 3)
                return captures.map { $0.isEmpty || (current && $0["page:kept"] == "v1") }
            }
            check(assistant.sourceSafeHistory(runtime:runtime,feed:feed,topic:nil).map(\.id) == [history.turns[0].id,kept.id] && batches == 1,"History checks page receipts in one batch while withholding stale replies")
            current=false
            check(assistant.sourceSafeHistory(runtime:runtime,feed:feed,topic:nil).map(\.id) == [history.turns[0].id] && batches == 2,"A later history read rebuilds current availability and preserves human messages")
            runtime.pageKnowledgeAvailability={_,_ in []}
            check(assistant.sourceSafeHistory(runtime:runtime,feed:feed,topic:nil).isEmpty,"Malformed batch cardinality fails closed")
        }

        for corrected in [true,false] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("native-preparation-\(corrected)"))
            var attempts=0
            c.configure={session,_ in session.executeBody={call,session in
                if call.name == "change_reminder" {
                    attempts += 1
                    if attempts == 1 {throw NativePreSaveFailure(message:"The exact fictional item needs a fresh read")}
                    session.receipts.append("Fictional reminder edit verified")
                    return "{\"verified\":true,\"result\":\"Fictional reminder edit verified\"}"
                }
                return "{}"
            }}
            let original=tools(["change_reminder"])
            var retry=tools(["change_reminder"])
            if !corrected {retry.calls[0].arguments="{\"target\":\"different-sibling\"}"}
            p.replies=[original,tools(["read_reminders","read_item_details"]),retry,final("Fictional native action answer")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Update this fictional reminder"),"Known pre-save failure fixture starts")
            await until{!value.busy}
            let turn=value.feed!.turns.last!
            let toolOutputs=p.inputs.flatMap{$0}.compactMap{$0["output"] as? String}
            check(toolOutputs.contains{output in
                guard let result=(try? JSONSerialization.jsonObject(with:Data(output.utf8))) as? [String:Any] else {return false}
                return result["stage"] as? String == "native_preparation" && result["nativeSaveAttempted"] as? Bool == false
            },"Positive no-save proof is projected separately from uncertain native operations")
            check(turn.toolErrors?.count == 1 && (turn.unresolvedToolErrors?.isEmpty == true) == corrected,"Only verified recovery of the exact native payload clears its unresolved error; sibling changes retain it")
        }

        do {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("exact-source-dependencies"))
            func sourceFact(_ text:String,_ item:String)->PAMemory {
                let source=MemorySourceEvidence(identity:.init(kind:.mail,accountID:"fictional-mail",containerID:"inbox",itemID:item),revision:"v1",label:"Fictional source",quote:text,observed:c.now,sourceDate:c.now)
                return PAMemory(registration:p.activeID,text:text,kind:.context,explicit:false,provenance:"Fictional source",evidence:text,sourceDate:c.now,certainty:.inferred,durability:.situational,source:source)
            }
            let selected=sourceFact("Orion coursework needs a prototype","selected"),unrelated=sourceFact("Garden irrigation needs a valve","unrelated")
            var permitted:Set<UUID>=[selected.id,unrelated.id]
            value.memory.sourceIsPermitted={permitted.contains($0.id)}
            check(value.memory.putSources([selected,unrelated],evidenceTexts:[selected.source!.identity:selected.text,unrelated.source!.identity:unrelated.text],expectedRevision:value.memory.revision),"Fictional exact-source facts save with original evidence")
            p.holdNext=true;p.replies=[final("No original fact was supplied")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Help with garden irrigation"),"An ordinary request with an unsupplied matching original starts")
            await until{p.waiting}
            permitted.remove(unrelated.id);p.release();await until{!value.busy}
            let unprovided=value.feed!.turns.last!
            check(unprovided.completed && value.error == nil && unprovided.sourceMemoryIDs?.isEmpty != false && unprovided.contextCapture?.directMemoryIDs == [],"Withdrawal of an original that never entered page or tool context does not block ordinary chat")
            permitted=[selected.id,unrelated.id]
            c.pageCapture={_,query,_,_,_ in
                guard query?.contains("Orion") == true else {return .init()}
                return .init(text:"{\"pages\":[{\"id\":\"fictional-orion\",\"markdown\":\"Orion page summary\"}]}",pageIDs:["fictional-orion"],memoryIDs:[selected.id])
            }
            p.holdNext=true;p.replies=[final("Selected Orion answer")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Help with Orion coursework"),"Selected-source request starts")
            await until{p.waiting}
            permitted.remove(unrelated.id);p.release();await until{!value.busy}
            let first=value.feed!.turns.last!
            check(value.error == nil && first.completed && first.sourceMemoryIDs == [selected.id],"Unrelated source withdrawal neither stops a request nor becomes its dependency")
            check(first.contextCapture?.directMemoryIDs == [] && first.contextCapture?.pageSupportingMemoryIDs == [selected.id],"The trace distinguishes backing page evidence from directly supplied original facts")
            check(!String(describing:p.inputs.last!).contains(selected.text),"Backing page IDs never reintroduce the original source fact as a parallel prompt list")
            check(value.sourceSafeHistory(runtime:c.runtime(),feed:value.feed!,topic:nil).contains{$0.id == first.id},"A reply remains recallable after unrelated source loss")
            permitted.remove(selected.id)
            check(!value.sourceSafeHistory(runtime:c.runtime(),feed:value.feed!,topic:nil).contains{$0.id == first.id},"Selected-source withdrawal still removes dependent reply history")
            permitted=[selected.id,unrelated.id]
            c.configure={session,_ in session.executeBody={call,session in
                if call.name == "read_memory" {session.consultedMemory.insert(unrelated.id)}
                return "{\"records\":[{\"id\":\"\(unrelated.id.uuidString)\"}]}"
            }}
            p.replies=[tools(["read_memory"]),final("Answer using selected and successfully read facts")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Help with Orion coursework again"),"Additional successful memory-read request starts")
            await until{!value.busy}
            let readReply=value.feed!.turns.last!
            check(Set(readReply.sourceMemoryIDs ?? []) == [selected.id,unrelated.id] && readReply.contextCapture?.consultedMemoryIDs == [unrelated.id],"Actual successful tool reads extend exact reply dependencies beyond initial selection")
            p.replies=[final("Follow-up using facts supplied by earlier replies")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Could you continue?"),"A follow-up without a direct memory match starts")
            await until{!value.busy}
            let followup=value.feed!.turns.last!
            check(followup.contextCapture?.memoryIDs.isEmpty == true && Set(followup.sourceMemoryIDs ?? []) == [selected.id,unrelated.id],"Earlier assistant history carries its transitive source dependencies into a new reply even with zero lexical matches")
            permitted.remove(unrelated.id)
            check(!value.sourceSafeHistory(runtime:c.runtime(),feed:value.feed!,topic:nil).contains{$0.id == readReply.id},"An additional successfully read source remains a required dependency")
            check(!value.sourceSafeHistory(runtime:c.runtime(),feed:value.feed!,topic:nil).contains{$0.id == followup.id},"Source withdrawal also removes follow-ups derived indirectly from an earlier source-backed reply")
            var legacy=first;legacy.sourceMemoryIDs=[selected.id,unrelated.id];legacy.contextCapture?.sourceMemoryDependencyVersion=nil
            check(ConversationRules.sourceMemoryHistory([legacy],permitted:[selected.id],history:value.feed!.turns).count == 1 && legacy.sourceMemoryIDs == [selected.id,unrelated.id],"Exact saved traces narrow old overcaptured dependencies without rewriting stored history")
            var legacyFollowup=followup;legacyFollowup.contextCapture?.sourceMemoryDependencyVersion=nil
            check(ConversationRules.sourceMemoryHistory([legacyFollowup],permitted:[selected.id],history:value.feed!.turns).isEmpty,"Legacy dependency reconstruction retains exact facts consumed through saved earlier history")
            check(ConversationRules.sourceMemoryHistory([legacy],permitted:[selected.id]).isEmpty,"An incomplete legacy trace retains its conservative gates")
            legacy.contextCapture=nil
            check(ConversationRules.sourceMemoryHistory([legacy],permitted:[selected.id]).isEmpty,"Legacy replies without an exact trace retain their conservative source gates")
            value.memory.enabled=false
            check(!value.sourceSafeHistory(runtime:c.runtime(),feed:value.feed!,topic:nil).contains{$0.id == first.id},"Disabling saved memory also withdraws its dependent AI history")
            value.memory.enabled=true
            p.holdNext=true;p.replies=[final("Must not accept selected-source loss")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Help with Orion coursework once more"),"Selected-source ownership fixture starts")
            await until{p.waiting};permitted.remove(selected.id);p.release();await until{!value.busy}
            check(value.error != nil && value.feed!.turns.last?.completed != true,"Selected-source loss during inference still rejects late output")
        }

        let imageProvider = FictionalInference(), imageContext = FictionalContext()
        let imageAssistant = service(imageProvider, try open("images"))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1sAAAAASUVORK5CYII=")!
        let attachment = try imageAssistant.images.add(png, registration: imageProvider.activeID)
        imageProvider.replies = [final("Fictional image described")]
        check(imageAssistant.send(runtime: imageContext.runtime(), topicID: nil, prompt: "Describe this fictional image", images: [attachment]), "Actual service must accept an owned stored image.")
        await until { !imageAssistant.busy }
        let imageTurn = imageAssistant.feed!.turns.first!
        let inputContent = imageProvider.inputs.first?.first(where: { $0["role"] as? String == "user" })?["content"] as? [[String: Any]] ?? []
        check(imageTurn.images == [attachment] && inputContent.contains(where: { $0["type"] as? String == "input_image" }), "Actual image preparation must preserve attachment identity and include the bounded payload.")
        let imageReopened = service(FictionalInference(), try open("images"))
        check(imageReopened.feed?.turns.first?.images == [attachment] && (try? imageReopened.images.data(attachment, registration: imageProvider.activeID)) != nil, "Owned image metadata and bytes must remain usable after reopening.")

        let setupProvider = FictionalInference(), setupContext = FictionalContext()
        let setup = service(setupProvider, try open("setup"))
        setupProvider.replies = [final("{\"question\":\"What is taking up most of your time?\"}")]
        check(setup.beginSetup(runtime: setupContext.runtime(), topic: nil), "Explicit setup Start must use the real service.")
        await until { !setup.busy }
        check(setupContext.sourceCalls == 0 && setup.feed?.turns.last?.content == "What is taking up most of your time?", "Setup must avoid cached source snapshots and show one completed question.")
        check(setup.feed?.turns.first?.profileControl == true && setup.learningTurns().isEmpty, "Setup controls must not become learning evidence.")
        check(setup.feed?.turns.last?.contextCapture?.profileSetup == true && setup.feed?.turns.last?.contextCapture?.sourceSnapshotIncluded == false, "Setup must retain its memory-only capture.")
        setupProvider.replies = [tools(["change_calendar"])]
        check(setup.sendProfile(runtime: setupContext.runtime(), topic: nil, answer: "For this fictional example, I study engineering."), "Setup must save the current human answer before inference.")
        await until { !setup.busy }
        check(setup.error?.contains("memory setup") == true && setupContext.sessions.last?.calls.isEmpty == true, "Setup restrictions must stop unsupported execution in the actual service.")
        check(setup.learningTurns().count == 1, "Human setup answers remain available while controls remain excluded.")

        for change in ["Stop", "account", "source", "memory", "memory-reset"] {
            let p = FictionalInference(), c = FictionalContext(), store = try open("ownership-" + change)
            let value = service(p, store)
            p.holdNext = true; p.replies = [tools(["read_memory"])]
            check(value.send(runtime: c.runtime(), topicID: nil, prompt: "Fictional owned request"), "Fixture owned request must prepare.")
            await until { p.waiting }
            switch change {
            case "Stop": value.cancel()
            case "account": p.activeID = "another-fictional-owner"
            case "source": c.state.weatherScope = "changed-fictional-weather"
            case "memory-reset":value.memory.enabled.toggle();value.memory.enabled.toggle()
            default: value.memory.enabled = false
            }
            p.release()
            await until { !value.busy }
            if change == "memory" {value.memory.enabled=true}
            check(c.sessions.first?.calls.isEmpty == true && value.error != nil, "\(change) must reject late tools and retain a visible stop/failure.")
            let saved = try ConversationRepository(container: try open("ownership-" + change)).load()
            check(saved.first?.turns.contains(where: { $0.role == "user" && $0.content == "Fictional owned request" }) == true, "\(change) must retain the prepared human request after reopen.")
        }

        // Changing future defaults is not Stop. Hold real service inference,
        // finish one verified operation, then prove the next request uses them.
        for change in ["model","preferences","name","focus","learning","learning-cycle","weather-unused","source-grant"] {
            settings.set(true,forKey:"paMemoryLearningEnabled")
            let p=FictionalInference(),c=FictionalContext(),store=try open("captured-default-"+change),value=service(p,store)
            let originalModel=p.selectedModel,originalPreferences=value.preferences,originalName=value.displayName
            if change == "weather-unused" {c.state.weatherSupplied=false}
            if change == "source-grant" {value.excludedCalendars=["fictional-excluded"];value.excludedLists=["fictional-excluded"];value.excludedAccounts=["fictional-excluded"]}
            var writes=0
            c.configure={session,_ in session.executeBody={call,session in
                check(call.name == "change_reminder","Captured-default fixture executes only the requested operation")
                writes += 1;session.receipts.append("Created fictional requested reminder")
                return "{\"verified\":true}"
            }}
            p.holdNext=true;p.replies=[tools(["change_reminder"]),final("Requested reminder created")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Add the requested reminder",focusAreas:[.studies]),"\(change) captured-default fixture starts")
            await until{p.waiting}
            switch change {
            case "model":p.selectedModel="next-request-model"
            case "preferences":value.preferences="Next request should use different writing instructions."
            case "name":value.displayName="Next request name"
            case "focus":value.standaloneFocusSelections[p.activeID]=[LifeArea.career.rawValue]
            case "learning":value.memory.learningEnabled=false
            case "weather-unused":c.state.weatherScope="new-unsupplied-weather"
            case "source-grant":value.excludedCalendars=[];value.excludedLists=[];value.excludedAccounts=[]
            default:value.memory.learningEnabled=false;value.memory.learningEnabled=true
            }
            p.release();await until{!value.busy}
            let turn=value.feed!.turns.last!
            check(value.error == nil && turn.actionResult?.phase == "completed" && writes == 1,"\(change) must finish the captured instruction exactly once")
            check(p.models == [originalModel,originalModel] && c.requests.first?.inferenceModel == originalModel,"\(change) cannot retarget later transport rounds or tool intent checks")
            check(p.instructions.count == 2 && p.instructions[0] == p.instructions[1] && p.instructions[0].contains(originalPreferences) && p.instructions[0].contains(originalName),"\(change) keeps the original instructions throughout its tool loop")
            check(turn.focusAreas == [.studies] && turn.contextCapture?.model == originalModel,"\(change) retains exact captured Focus and model provenance")
            let reopened=service(p,store)
            check(reopened.feed?.turns.last?.actionResult == turn.actionResult,"\(change) completed outcome survives reopening")
            p.replies=[final("Next request finished")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"A new independent request",focusAreas:[.career]),"\(change) next request starts normally")
            await until{!value.busy}
            check(p.models.last == p.selectedModel && p.instructions.last?.contains(value.preferences) == true && p.instructions.last?.contains(value.displayName) == true && value.feed?.turns.last?.focusAreas == [.career],"\(change) future choices apply to the next request")
        }

        for revoked in [false,true] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("weather-tool-"+String(revoked)))
            c.state.weatherSupplied=false
            c.configure={session,_ in session.executeBody={call,session in
                check(call.name == "read_weather","Weather dependency is issued only by the weather read")
                session.suppliedWeatherScope=c.state.weatherScope
                if revoked {c.state.weatherScope="withdrawn-after-read"}
                return "{\"days\":[{\"conditions\":\"Fictional\"}]}"
            }}
            p.holdNext=true;p.replies=[tools(["read_weather"]),final("The fictional forecast is available")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Read the current forecast"),"Weather tool fixture starts")
            await until{p.waiting};c.state.weatherScope="permission-granted-before-first-read";p.release();await until{!value.busy}
            check(revoked ? value.error != nil && p.inputs.count == 1 : value.error == nil && value.feed?.turns.last?.actionResult?.phase == "completed","Fresh weather access may be granted, but supplied weather permission cannot be withdrawn")
        }

        for revoked in [false,true] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("whatsapp-tool-"+String(revoked)))
            c.configure={session,_ in session.executeBody={_,session in
                session.suppliedWhatsAppScope=c.state.whatsappScope
                if revoked {c.state.whatsappScope = .init(registration:p.activeID,linkedIdentity:"withdrawn-after-read",revision:UUID())}
                return "{\"messages\":[{\"text\":\"Fictional\"}]}"
            }}
            p.holdNext=true;p.replies=[tools(["search_whatsapp"]),final("Requested fictional message found")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Read the requested WhatsApp message"),"WhatsApp tool fixture starts")
            await until{p.waiting};c.state.whatsappScope = .init(registration:p.activeID,linkedIdentity:"current-device-before-first-read",revision:UUID());p.release();await until{!value.busy}
            check(revoked ? value.error != nil && p.inputs.count == 1 : value.error == nil && value.feed?.turns.last?.actionResult?.phase == "completed","Fresh WhatsApp read captures its own permission, which cannot be withdrawn after supply")
        }

        // Dismiss/Undo is attention metadata, not revocation of an unrelated
        // human instruction. Exercise the actual engine through save and reopen.
        for mode in ["dismiss-before-tool","undo-before-tool","dismiss-during-stream","dismiss-during-read","dismiss-after-save","review-dismiss"] {
            let p=FictionalInference(),c=FictionalContext(),container=try open("dismiss-reminder-"+mode),value=service(p,container)
            let repository=LocalRecordRepository(container:container),receipt="Fictional reminder created and verified"
            let dismissal=ReviewAcknowledgement(id:"email:fictional-unrelated",kind:"email",sourceID:"fictional-unrelated",title:"Unrelated newsletter",concern:"Already seen",acknowledgedAt:c.now)
            var writes=0,streamed=0,changed=false
            let originalRevision=c.attentionRevision
            if mode == "undo-before-tool" {c.acknowledgements=[dismissal]}
            func changeAttention() {
                guard !changed else {return};changed=true
                c.attentionRevision=mode == "undo-before-tool" ? "ack-empty" : "ack-new-dismissal"
                c.acknowledgements=mode == "undo-before-tool" ? [] : [dismissal]
                check(c.attentionRevision != originalRevision,"Fixture changes the independent attention revision")
            }
            c.configure={session,_ in session.executeBody={call,session in
                if call.name == "read_reminders" {
                    if mode == "dismiss-during-read" {changeAttention()}
                    return "{\"reminders\":[],\"coverage\":\"Fictional enabled list\"}"
                }
                precondition(call.name == "change_reminder")
                writes += 1
                try repository.save(["title":"Follow up with fictional insurer","due":DateRules.localDate(c.now.addingTimeInterval(7*86400)),"operation":"fictional-owned-creation"],key:"fictionalReminder")
                session.receipts.append(receipt)
                if mode == "dismiss-after-save" {changeAttention()}
                return "{\"verified\":true,\"id\":\"fictional-owned-reminder\"}"
            }}
            p.holdNext=mode.contains("before-tool") || mode == "review-dismiss"
            p.replies=mode == "dismiss-during-read" ? [tools(["read_reminders"]),tools(["change_reminder"]),final(receipt)] : [tools(["change_reminder"]),final(receipt)]
            if mode == "dismiss-during-stream" {
                p.deltas=Array(repeating:"Working ",count:200)
                p.afterDelta={streamed += 1;if streamed == 1 {changeAttention()}}
            }
            let review=mode == "review-dismiss",id:UUID
            if review {
                id=value.openReview(key:"fictional-owned-request",title:"Fictional source",sourceKind:"mail",accountID:"fictional-mail",messageID:"fictional-owned-source",identity:nil,chatID:nil,seeds:[])!
                value.draft="Retained general draft"
                check(value.sendReview(runtime:c.runtime(),conversationID:id,prompt:"Add a reminder for next week",humanTurnID:UUID(),responseTurnID:UUID(),query:"Add a reminder",submitted:c.now,focusAreas:[],valid:{true}),"Review conversation starts the exact owned request")
            } else {
                id=value.openPA()!
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Add a reminder for next week"),"Reminder request starts before independent Review interaction")
            }
            if p.holdNext || p.waiting {await until{p.waiting};changeAttention();p.release()}
            await until{!value.busy}
            check(changed && value.error == nil,"\(mode) must not abort the current human instruction")
            check(writes == 1 && c.sessions[0].receipts == [receipt],"\(mode) completes exactly one verified reminder operation")
            check(value.conversation(id)?.turns.last?.content == receipt && value.conversation(id)?.turns.last?.actionResult?.phase == "completed","\(mode) saves the verified completed reply")
            check(c.acknowledgements == (mode == "undo-before-tool" ? [] : [dismissal]),"\(mode) preserves the independent attention choice")
            let reopened=service(p,try open("dismiss-reminder-"+mode))
            let persisted:[String:String]?=try repository.decode("fictionalReminder")
            check(persisted?["operation"] == "fictional-owned-creation" && reopened.conversation(id)?.turns.last?.actionResult?.phase == "completed","\(mode) retains exact save and outcome across reopen")
            if review {check(value.draft == "Retained general draft","Review completion preserves the general unsent draft")}
            if mode == "dismiss-during-stream" {check(streamed == 400,"Dismiss during partial streaming retains both completed transport rounds")}
        }

        // Real service pauses in transport while independent collection/local edits occur.
        for mode in ["ack-title","ack-support","resolution-added","resolution-crowded","resolution-changed","resolution-lost","human-dismiss","whatsapp-account","unrelated-memory","selected-memory","unrelated-project","selected-project"] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("context-churn-"+mode))
            let fact=PAMemory(registration:p.activeID,text:"Orion prototype needs a small motor",kind:.context,explicit:true,provenance:"Fictional human")
            check(value.memory.put(fact),"Context churn fixture saves its selected fact")
            let item=LifeItem(registration:p.activeID,kind:.space,title:"Orion prototype")
            _=try value.projects.create([item],receipt:.init(id:"fixture-"+mode,registration:p.activeID,result:"Fictional space",itemID:item.id))
            c.pageCapture = { _,_,_,_,_ in
                let text=String(decoding:try! JSONEncoder().encode(item),as:UTF8.self)
                return .init(text:text,pageIDs:["fictional-context-page-"+item.id.uuidString],memoryIDs:[fact.id],workspaceIDs:[item.id],referenceVersions:["project:"+item.id.uuidString:item.revision.uuidString],validate:{ignored in
                    ignored.contains("project:"+item.id.uuidString) || value.projects.state.items.first(where:{$0.id == item.id})?.revision == item.revision
                })
            }
            c.acknowledgements=[.init(id:"dismissed-fictional",kind:"email",sourceID:"fictional-email",title:"Cached name",concern:"Historical dismissed concern")]
            let resolved=["requestID":"fictional-request","accountID":"fictional-mail","confirmationID":"fictional-confirmation","confirmationQuote":"Received"]
            if mode.hasPrefix("resolution-") && mode != "resolution-added" {c.state.resolvedRequests=[resolved]}
            p.holdNext=true;p.replies=[tools(["read_memory"]),final("Orion answer retained")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Tell me about the Orion prototype"),"Context churn request starts")
            await until{p.waiting}
            switch mode {
            case "ack-title":c.acknowledgements[0].title="Recovered display name"
            case "ack-support":c.acknowledgements=[]
            case "resolution-added":c.state.resolvedRequests=[resolved]
            case "resolution-crowded":c.state.resolvedRequests=(0..<30).map{["requestID":"unrelated-\($0)","accountID":"fictional-mail"]}+[resolved]
            case "resolution-changed":c.state.resolvedRequests[0]["confirmationQuote"]="Changed confirmation"
            case "resolution-lost":c.state.resolvedRequests=[]
            case "human-dismiss":c.attentionRevision="ack-human-changed"
            case "whatsapp-account":c.state.whatsappScope = .init(registration:p.activeID,linkedIdentity:"different-fictional-device",revision:UUID())
            case "unrelated-memory":_=value.memory.put(PAMemory(registration:p.activeID,text:"Garden irrigation uses a valve",kind:.context,explicit:true,provenance:"Fictional human"))
            case "selected-memory":var changed=fact;changed.text="Orion prototype now needs a large motor";_=value.memory.put(changed)
            case "unrelated-project":_=try value.projects.save(LifeItem(registration:p.activeID,kind:.space,title:"Garden irrigation"),expected:nil)
            default:var changed=item;changed.notes="The prototype scope changed";_=try value.projects.save(changed,expected:item.revision)
            }
            p.release();await until{!value.busy}
            let rejected=["resolution-changed","resolution-lost","selected-memory","selected-project"].contains(mode)
            check((value.error != nil) == rejected,"\(mode) distinguishes supplied-context changes from unrelated collection")
            check(rejected ? c.sessions[0].calls.isEmpty : c.sessions[0].calls == ["read_memory"],"\(mode) validates before executing any late tool")
            if rejected {check(value.error?.contains("because") == true,"Real invalidation names the changed context rather than a generic configuration failure")}
            else {check(value.feed!.turns.last?.completed == true,"Unrelated churn keeps the completed reply")}
        }
        for kind in ["memory","project"] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("read-dependency-"+kind))
            let fact=PAMemory(registration:p.activeID,text:"Garden irrigation needs a valve",kind:.context,explicit:true,provenance:"Fictional human")
            check(value.memory.put(fact),"Read dependency fixture saves its initially unrelated fact")
            let item=LifeItem(registration:p.activeID,kind:.space,title:"Garden irrigation")
            _=try value.projects.create([item],receipt:.init(id:"read-dependency-"+kind,registration:p.activeID,result:"Fictional space",itemID:item.id))
            c.configure={session,_ in session.executeBody={_,session in
                if kind == "memory" {session.consultedMemory.insert(fact.id)} else {session.consultedWorkspace.insert(item.id)}
                p.holdNext=true
                return "{}"
            }}
            p.replies=[tools([kind == "memory" ? "read_memory" : "read_life_items"]),tools(["change_reminder"])]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Tell me about the Orion prototype"),"Additional read request starts without a lexical match")
            await until{p.waiting}
            if kind == "memory" {var changed=fact;changed.text="The irrigation valve has changed";_=value.memory.put(changed)}
            else {var changed=item;changed.notes="Changed after read";_=try value.projects.save(changed,expected:item.revision)}
            p.release();await until{!value.busy}
            check(value.error != nil && c.sessions[0].calls.count == 1,"A changed \(kind) actually supplied by a tool blocks the next late action")
        }

        for name in ["remember_context","change_memory"] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("mutation-dependency-"+name))
            let saved=PAMemory(registration:p.activeID,text:"Orion prototype uses a motor",kind:.context,explicit:true,provenance:"Fictional human")
            c.configure={session,_ in session.executeBody={_,_ in
                precondition(value.memory.put(saved))
                p.holdNext=true
                return "{\"saved\":true,\"id\":\"\(saved.id.uuidString)\"}"
            }}
            p.replies=[tools([name]),tools(["change_reminder"])]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Remember the Orion prototype details"),"Mutation-return dependency fixture starts")
            await until{p.waiting}
            var changed=saved;changed.text="Orion prototype needs a revised motor";_=value.memory.put(changed)
            p.release();await until{!value.busy}
            check(value.error != nil && c.sessions[0].calls == [name],"A changed canonical memory returned by \(name) blocks the next action")
            check(value.feed!.turns.last?.contextCapture?.consultedMemoryIDs.isEmpty == true,"Mutation-issued memory IDs remain separate from successful-read traces")
        }
        for supplied in [false,true] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("resolution-tool-\(supplied)"))
            let row=["requestID":"fictional-request","accountID":"fictional-mail","confirmationQuote":"Received"]
            c.configure={session,_ in session.executeBody={_,_ in
                c.state.resolvedRequests=[row];p.holdNext=true
                return supplied ? String(data:try JSONSerialization.data(withJSONObject:["resolvedEmailRequests":[row]]),encoding:.utf8)! : "{\"saved\":true}"
            }}
            let name=supplied ? "read_attention" : "remember_context"
            p.replies=[tools([name]),final("Fictional answer")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Help with the Orion prototype"),"Resolution-tool fixture starts")
            await until{p.waiting}
            c.state.resolvedRequests[0]["confirmationQuote"]="Changed"
            p.release();await until{!value.busy}
            check((value.error != nil) == supplied,"Only an actually supplied tool confirmation becomes a later dependency")
        }

        for selected in [false,true] {
            let p=FictionalInference(),c=FictionalContext(),value=service(p,try open("project-link-churn-\(selected)"))
            let orion=LifeItem(registration:p.activeID,kind:.space,title:"Orion prototype"),garden=LifeItem(registration:p.activeID,kind:.space,title:"Garden irrigation")
            _=try value.projects.create([orion,garden],receipt:.init(id:"project-link-churn",registration:p.activeID,result:"Fictional spaces"))
            let owner=selected ? orion : garden
            let edge=try value.projects.link(.init(registration:p.activeID,from:owner.id,relation:.related,target:.init(kind:.item,id:(selected ? garden : orion).id.uuidString)),expected:owner.revision)
            p.holdNext=true;p.replies=[tools(["change_reminder"]),final("Fictional answer")]
            check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Tell me about the Orion prototype"),"Project link-churn request starts")
            await until{p.waiting}
            try value.projects.unlink(edge.id,registration:p.activeID,expectedRevision:value.projects.revision)
            p.release();await until{!value.busy}
            check((value.error != nil) == selected,"Only changed relationships of supplied project owners stop inference")
            check(selected ? c.sessions[0].calls.isEmpty : c.sessions[0].calls == ["change_reminder"],"Changed supplied links reject late writes while unrelated links do not")
        }

        let queuedProvider = FictionalInference(), queuedContext = FictionalContext()
        let queued = service(queuedProvider, try open("queue"))
        queuedProvider.holdNext = true
        queuedProvider.replies = [final("First fictional response"), final("Second fictional response")]
        check(queued.send(runtime: queuedContext.runtime(), topicID: nil, prompt: "First fictional request"), "First queue fixture request must prepare.")
        await until { queuedProvider.waiting }
        check(queued.send(runtime: queuedContext.runtime(), topicID: nil, prompt: "Second fictional request", focusAreas: [.career]), "Explicit request during a busy turn must enqueue.")
        check(queued.queue.items.first?.state == .waiting && queued.queue.items.first?.focusAreas == [.career], "Enqueued work must capture Focus and wait serially.")
        queuedProvider.release()
        await until { queued.queue.items.first?.state == .completed && !queued.busy }
        check(queued.feed?.turns.last?.content == "Second fictional response" && queued.feed?.turns.last?.focusAreas == [.career], "Queue delivery must use the captured request and Focus.")
        let queueReopened = service(FictionalInference(), try open("queue"))
        check(queueReopened.queue.items.first?.state == .completed && queueReopened.feed?.turns.map(\.id) == queued.feed?.turns.map(\.id), "Completed queued receipts and identities must survive reopening.")

        let questionProvider = FictionalInference(), questionContext = FictionalContext()
        let question = service(questionProvider, try open("question-queue"))
        questionProvider.holdNext = true; questionProvider.replies = [final("First complete"), tools(["ask_clarification"])]
        _ = question.send(runtime: questionContext.runtime(), topicID: nil, prompt: "First question fixture request")
        await until { questionProvider.waiting }
        _ = question.send(runtime: questionContext.runtime(), topicID: nil, prompt: "Request needing an answer")
        _ = question.send(runtime: questionContext.runtime(), topicID: nil, prompt: "Later request must wait")
        questionProvider.release()
        await until { question.queue.items.first?.state == .needsAnswer && !question.busy }
        check(question.queue.items.last?.state == .waiting && questionProvider.inputs.count == 2, "Needs-answer must stop automatic queue advancement.")
        check(question.feed?.turns.last?.completed == true && question.feed?.turns.last?.choices == ["First", "Second"], "The captured clarification bubble must retain exact answer choices.")
        let questionReopenedProvider = FictionalInference()
        let questionReopened = service(questionReopenedProvider, try open("question-queue"))
        await Task.yield()
        check(questionReopened.queue.items.first?.state == .needsAnswer && questionReopened.queue.items.last?.state == .waiting && questionReopenedProvider.inputs.isEmpty, "Reopening must not replay a paused needs-answer queue.")

        let interruptedProvider = FictionalInference(), interruptedContext = FictionalContext()
        let interrupted = service(interruptedProvider, try open("interrupted-queue"))
        interruptedProvider.holdNext = true; interruptedProvider.replies = [final("Initial completed response"), final("Cancelled response must not appear")]
        _ = interrupted.send(runtime: interruptedContext.runtime(), topicID: nil, prompt: "Initial interruption fixture request")
        await until { interruptedProvider.waiting }
        _ = interrupted.send(runtime: interruptedContext.runtime(), topicID: nil, prompt: "Queued request to stop")
        _ = interrupted.send(runtime: interruptedContext.runtime(), topicID: nil, prompt: "Later request must remain waiting")
        interruptedProvider.holdNext = true; interruptedProvider.release()
        await until { interruptedProvider.inputs.count == 2 && interruptedProvider.waiting }
        interrupted.cancel(); interruptedProvider.release()
        await until { interrupted.queue.items.first?.state == .interrupted && !interrupted.busy }
        check(interrupted.queue.items.last?.state == .waiting && interruptedProvider.inputs.count == 2, "Stopping queued inference must preserve interruption and pause later work.")
        let interruptedReopenedProvider = FictionalInference()
        let interruptedReopened = service(interruptedReopenedProvider, try open("interrupted-queue"))
        await Task.yield()
        check(interruptedReopened.queue.items.first?.state == .interrupted && interruptedReopened.queue.items.last?.state == .waiting && interruptedReopenedProvider.inputs.isEmpty, "Reopening must not replay interrupted foreground requests.")

        func nativeCall(_ name:String,operation:String = "create",target:String? = nil,destination:String? = nil,scope:String? = nil)->PAFunctionCall {
            var fields:[String:Any]=["operation":operation,"target":target as Any? ?? NSNull(),"destination":destination as Any? ?? NSNull(),"title":"Fictional weekend","notes":NSNull(),"scope":scope as Any? ?? NSNull(),"options":NSNull(),"authorization":"Yes, all weekend"]
            if name == "change_calendar" {fields.merge(["location":NSNull(),"start":"2026-10-24","end":"2026-10-26","allDay":true]){_,new in new}}
            else {fields.merge(["due":"2026-10-24","hasTime":false]){_,new in new}}
            return .init(id:UUID().uuidString,name:name,namespace:"pa",arguments:String(decoding:try! JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys]),as:UTF8.self))
        }
        func response(_ calls:[PAFunctionCall])->PAResponse {
            .init(text:"",output:calls.map{["type":"function_call","call_id":$0.id,"name":$0.name,"arguments":$0.arguments]},calls:calls)
        }
        let projectReason="Use the exact project item identity returned by a current read."
        let projectParent=UUID().uuidString
        func projectCall(_ parent:String,title:String="Fictional module",read:Bool=false)->PAFunctionCall {
            let fields:[String:Any]=read ? ["query":"Modules","root":parent,"unfinished":false,"dueBefore":NSNull(),"maxMinutes":NSNull(),"deleted":false] : ["items":[["title":title,"kind":"space","parent":parent,"notes":"Fictional notes","due":NSNull(),"estimateMinutes":NSNull(),"areas":[]]],"authorization":"Add the fictional module"]
            return .init(id:UUID().uuidString,name:read ? "read_life_items" : "create_life_items",namespace:"pa",arguments:String(decoding:try! JSONSerialization.data(withJSONObject:fields,options:.sortedKeys),as:UTF8.self))
        }
        for mode in ["creation","read","sibling","unverified","changed-parent","ambiguous"] {
            let p=FictionalInference(),c=FictionalContext(),container=try open("project-recovery-"+mode)
            let value=service(p,container),bad=projectCall(mode == "changed-parent" ? projectParent : "invalid-project-reference",read:mode == "read")
            let good=projectCall(mode == "changed-parent" ? UUID().uuidString : projectParent,title:mode == "sibling" ? "Different module" : "Fictional module",read:mode == "read")
            var attempt=0,outcomes:[AssistantTurnOutcome]=[]
            c.configure={session,_ in session.executeBody={call,session in
                attempt += 1
                if attempt == 1 || (mode == "ambiguous" && attempt == 2) {throw PAReadPreparationFailure(readTool:"read_life_items",reason:projectReason)}
                if mode == "read" {return "{\"items\":[],\"coverage\":\"Fictional exact branch\"}"}
                if mode == "unverified" {return "{\"saved\":false,\"items\":[]}"}
                session.receipts.append("Space created: Fictional module")
                return "{\"saved\":true,\"items\":[{\"id\":\""+UUID().uuidString+"\"}]}"
            }}
            p.replies=(mode == "ambiguous" ? [response([bad]),response([projectCall("another-invalid-parent")])] : [response([bad])])+[response([good]),final("Fictional request finished")]
            var runtime=c.runtime();runtime.finished={outcomes.append($0)}
            check(value.send(runtime:runtime,topicID:nil,prompt:"Add the fictional module"),"Project preparation recovery starts within the existing request")
            await until{!value.busy}
            let recovered=["creation","read"].contains(mode),turn=value.feed!.turns.last!
            check(turn.unresolvedToolErrors?.isEmpty == recovered,"Only matching verified project preparation resolves: "+mode)
            check(turn.toolErrors == Array(repeating:projectReason,count:mode == "ambiguous" ? 2 : 1) && turn.contextCapture?.preparationNotes?.contains(projectReason) == true,"Original diagnostics remain inspectable after project recovery: "+mode)
            check(outcomes.last?.phase == (recovered ? "completed" : mode == "unverified" ? "failed" : "partial"),"Final action outcome reflects unresolved work: "+mode)
            check(turn.actionResult?.phase == outcomes.last?.phase && value.activityContext(value.feed!.id)?.actionResults[turn.id] == turn.actionResult,"Pill uses stable saved final outcome metadata: "+mode)
            let reopened=try ConversationRepository(container:container).load().first!.turns.last!
            check(reopened.actionResult == turn.actionResult && reopened.unresolvedToolErrors == turn.unresolvedToolErrors,"Recovered project status survives reopening: "+mode)
        }
        do {
            let failed=projectCall("life:"+projectParent,read:true)
            let requirement=PAProjectPreparation(call:failed,reason:projectReason)!
            check(requirement.resolved(by:projectCall(projectParent,read:true),output:"{\"items\":[],\"coverage\":\"Exact read\"}"),"Known prefixed UUID recovery preserves the exact project identity")
            var broadArgs=try PAToolProtocol.arguments(projectCall(projectParent,read:true));broadArgs["root"]=NSNull()
            let broad=PAFunctionCall(id:UUID().uuidString,name:"read_life_items",namespace:"pa",arguments:String(decoding:try JSONSerialization.data(withJSONObject:broadArgs,options:.sortedKeys),as:UTF8.self))
            check(!PAProjectPreparation(call:projectCall("ambiguous-branch",read:true),reason:projectReason)!.resolved(by:broad,output:"{\"items\":[],\"coverage\":\"Broad overview\"}"),"A broad overview cannot resolve a failed exact-branch read")
        }
        let destination=SourceOption(id:"fictional-destination",title:"Fictional destination",account:"Fictional",writable:true)
        for name in ["change_calendar","change_reminder"] {
            for explicit in [false,true] {
                let p=FictionalInference(),c=FictionalContext()
                settings.set(true,forKey:"assistantContextEnabled")
                let value=service(p,try open("recovery-"+name+String(explicit))),original=nativeCall(name,destination:explicit ? destination.id : nil)
                var writes=0,mutations:[PAFunctionCall]=[]
                c.configure={session,_ in session.executeBody={call,session in
                    if call.name == "read_calendar" {session.calendar.sources=[destination];return "{\"sources\":[\"fictional-destination\"]}"}
                    if call.name == "read_reminders" {session.reminders.sources=[destination];return "{\"sources\":[\"fictional-destination\"]}"}
                    mutations.append(call)
                    try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!(name == "change_calendar" ? session.calendar.sources : session.reminders.sources).isEmpty,hasDetails:false)
                    writes += 1;session.receipts.append("Fictional creation saved and verified")
                    return "{\"verified\":true}"
                }}
                p.replies=[response([original]),final("Fictional creation completed")]
                check(value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend"),"A confirmed creation must start without another human message")
                await until{!value.busy}
                check(c.sessions[0].calls == [name,name == "change_calendar" ? "read_calendar" : "read_reminders",name] && writes == 1,"Missing destinations must cause one internal read and one actual creation")
                check(mutations.count == 2 && mutations.allSatisfy{$0.id == original.id && $0.arguments == original.arguments},"Preparation must preserve exact mutation identity, dates, explicit/default destination and authority")
                check(value.error == nil && value.feed?.turns.last?.content == "Fictional creation completed" && value.feed?.turns.filter{$0.role == "user"}.count == 1,"The same foreground request must finish without asking the human to repeat")
                check(value.feed?.turns.last?.unresolvedToolErrors?.isEmpty == true && value.feed?.turns.last?.contextCapture?.attemptedTools.contains(name == "change_calendar" ? "read_calendar" : "read_reminders") == true,"Internal preparation must be traced without a false visible save failure")
                let saved=try ConversationRepository(container:try open("recovery-"+name+String(explicit))).load()
                check(saved.first?.turns.last?.content == "Fictional creation completed","Recovered creation reply must survive reopening")
            }
        }
        for interruption in ["Stop","account","permission","filters","context"] {
            let p=FictionalInference(),c=FictionalContext()
            settings.set(true,forKey:"assistantContextEnabled")
            let value=service(p,try open("preparation-interruption-"+interruption))
            var writes=0
            c.configure={session,_ in session.executeBody={call,session in
                if call.name == "read_calendar" {
                    session.calendar.sources=[destination]
                    switch interruption {
                    case "Stop":value.cancel()
                    case "account":p.activeID="changed-owner"
                    case "permission":value.contextEnabled=false
                    case "filters":value.excludedCalendars.insert(destination.id)
                    default:c.state.weatherScope="changed-context"
                    }
                    return "{}"
                }
                try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!session.calendar.sources.isEmpty,hasDetails:false)
                writes += 1;return "{}"
            }}
            p.replies=[response([nativeCall("change_calendar")])]
            _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend")
            await until{!value.busy}
            check(writes == 0 && c.sessions[0].calls == ["change_calendar","read_calendar"],"\(interruption) during preparation must block the original mutation")
            check(value.error != nil && p.inputs.count == 1,"\(interruption) must stop the captured turn without fresh inference or retargeting")
        }
        for name in ["change_calendar","change_reminder"] {
            for operation in ["edit","delete"] {
                let p=FictionalInference(),c=FictionalContext()
                settings.set(true,forKey:"assistantContextEnabled")
                let value=service(p,try open("details-"+name+operation)),target="issued-occurrence",original=nativeCall(name,operation:operation,target:target,scope:name == "change_calendar" ? "occurrence" : "reminderSeries")
                var writes=0,mutations:[PAFunctionCall]=[]
                c.configure={session,_ in
                    if name == "change_calendar" {session.calendar = .init(sources:[destination],events:[.init(id:target,calendarID:destination.id,title:"Fictional event",start:c.now,end:c.now.addingTimeInterval(3600),allDay:false,location:"",sourceLabel:"Fictional")])}
                    else {session.reminders = .init(sources:[destination],reminders:[.init(id:target,listID:destination.id,title:"Fictional reminder",due:nil,hasTime:false,sourceLabel:"Fictional",writable:true,recurring:true)])}
                    session.executeBody={call,session in
                        if call.name == "read_item_details" {
                            let args=try PAToolProtocol.arguments(call)
                            check(args["id"] as? String == target && args["kind"] as? String == (name == "change_calendar" ? "event" : "reminder"),"Internal detail read preserves exact occurrence and native kind")
                            session.itemDetails[target] = .init(kind:name == "change_calendar" ? .event : .reminder,itemID:"fictional-item",occurrenceID:target,sourceID:destination.id,title:"Fictional",notes:"",recurring:true,writable:true)
                            return "{}"
                        }
                        mutations.append(call)
                        try PAToolProtocol.nativeReadPreflight(call.name,operation:operation,hasSources:true,hasDetails:session.itemDetails[target] != nil,target:target)
                        writes += 1;session.receipts.append("Fictional exact operation verified");return "{\"verified\":true}"
                    }
                }
                p.replies=[response([original]),final("Fictional exact operation completed")]
                _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend")
                await until{!value.busy}
                check(writes == 1 && mutations.count == 2 && mutations.allSatisfy{$0.id == original.id && $0.arguments == original.arguments},"Detail preparation cannot change occurrence, recurring scope or authorisation")
                check(c.sessions[0].calls == [name,"read_item_details",name] && value.error == nil,"An already issued edit/delete target is prepared once in the same turn")
            }
        }
        for name in ["change_calendar","change_reminder"] {
            for sibling in [false,true] {
                let p=FictionalInference(),c=FictionalContext()
                let value=service(p,try open("late-issued-"+name+String(sibling))),target="later-issued",other="sibling-issued"
                let original=nativeCall(name,operation:"edit",target:target),unresolved=nativeCall(name,operation:"edit",target:other)
                let readName=name == "change_calendar" ? "read_calendar" : "read_reminders"
                let read=PAFunctionCall(id:UUID().uuidString,name:readName,namespace:"pa",arguments:readName == "read_calendar" ? "{\"start\":\"2026-10-24\",\"end\":\"2026-10-25\"}" : "{}")
                var writes=0
                c.configure={session,_ in session.executeBody={call,session in
                    if call.name == readName {
                        if name == "change_calendar" {session.calendar = .init(sources:[destination],events:[target,other].map{.init(id:$0,calendarID:destination.id,title:"Fictional event",start:c.now,end:c.now.addingTimeInterval(3600),allDay:false,location:"",sourceLabel:"Fictional")})}
                        else {session.reminders = .init(sources:[destination],reminders:[target,other].map{.init(id:$0,listID:destination.id,title:"Fictional reminder",due:nil,hasTime:false,sourceLabel:"Fictional",writable:true,recurring:false)})}
                        return "{}"
                    }
                    if call.name == "read_item_details" {
                        let args=try PAToolProtocol.arguments(call)
                        check(args["id"] as? String == target,"Internal recovery must resolve only its exact target")
                        session.itemDetails[target] = .init(kind:name == "change_calendar" ? .event : .reminder,itemID:"fictional-item",occurrenceID:target,sourceID:destination.id,title:"Fictional",notes:"",recurring:false,writable:true)
                        return "{}"
                    }
                    let args=try PAToolProtocol.arguments(call),id=args["target"] as? String
                    try PAToolProtocol.nativeReadPreflight(call.name,operation:"edit",hasSources:false,hasDetails:id.flatMap{session.itemDetails[$0]} != nil,target:id)
                    writes += 1;session.receipts.append("Fictional later-issued edit verified");return "{\"verified\":true}"
                }}
                // A newly issued transport call may retry the unchanged operation;
                // the engine must still reject reuse of a completed call ID.
                var retry=original;retry.id=UUID().uuidString
                p.replies=[response(sibling ? [original,unresolved] : [original]),response([read]),response([retry]),final("Fictional later-issued edit completed")]
                _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Edit the exact previously discussed item")
                await until{!value.busy}
                check(writes == 1 && value.error == nil,"A freshly issued target can complete after exact internal details preparation")
                check(value.feed?.turns.last?.toolErrors?.contains(PAReadPrerequisite.details) == true,"Resolved prerequisite history must remain saved")
                check(value.feed?.turns.last?.unresolvedToolErrors?.isEmpty == !sibling,"Resolve the recovered target while retaining any sibling prerequisite")
                check(c.sessions[0].itemDetails[other] == nil,"Recovery must not read or edit the sibling target")
            }
        }
        for failure in ["empty","read-error","uncertain-save","repeated-prerequisite","disabled-destination","read-only"] {
            let p=FictionalInference(),c=FictionalContext()
            settings.set(true,forKey:"assistantContextEnabled")
            let value=service(p,try open("preparation-failure-"+failure))
            var writes=0
            c.configure={session,_ in session.executeBody={call,session in
                if call.name == "read_calendar" {
                    if failure == "read-error" {throw ActionFailure.message("Fictional source unavailable")}
                    var source=destination;if failure == "read-only" {source.writable=false}
                    session.calendar.sources=failure == "empty" ? [] : [source]
                    return "{}"
                }
                if failure == "uncertain-save" {writes += 1;throw ActionFailure.message("Fictional attempted save has an uncertain outcome")}
                try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!session.calendar.sources.isEmpty,hasDetails:false)
                if failure == "repeated-prerequisite" {throw PAReadPrerequisite(readTool:"read_calendar",reason:PAReadPrerequisite.destinations)}
                if failure == "disabled-destination" {throw NativePreSaveFailure(message:"The explicitly selected fictional destination is unavailable")}
                if failure == "read-only" {throw NativePreSaveFailure(message:"The fictional destination is read-only")}
                writes += 1;return "{}"
            }}
            p.replies=[response([nativeCall("change_calendar",destination:failure == "disabled-destination" ? "excluded-destination" : nil)]),final("Fictional limitation reported")]
            _=value.send(runtime:c.runtime(),topicID:nil,prompt:"Yes, all weekend")
            await until{!value.busy}
            let calls=c.sessions[0].calls
            check(writes == (failure == "uncertain-save" ? 1 : 0),"\(failure) must not replay or substitute a native write")
            check(calls.filter{$0 == "read_calendar"}.count == (failure == "uncertain-save" ? 0 : 1) && calls.filter{$0 == "change_calendar"}.count <= 2,"\(failure) must have bounded known-prerequisite recovery only")
            check(value.feed?.turns.last?.unresolvedToolErrors?.isEmpty == false,"\(failure) must retain its genuine unresolved limitation")
            if ["empty","read-error"].contains(failure) {
                let output=p.inputs[1].first{$0["type"] as? String == "function_call_output"}?["output"] as? String
                let detail=try output.flatMap{try JSONSerialization.jsonObject(with:Data($0.utf8)) as? [String:Any]}
                check(detail?["nativeSaveAttempted"] as? Bool == false && detail?["stage"] as? String == "read_preparation","A failed preparatory read must not be described as an uncertain native save")
            }
        }
        let batchProvider=FictionalInference(),batchContext=FictionalContext()
        settings.set(true,forKey:"assistantContextEnabled")
        let batchService=service(batchProvider,try open("preparation-partial-batch")),creation=nativeCall("change_calendar")
        let memoryCall=PAFunctionCall(id:UUID().uuidString,name:"save_memory",namespace:"pa",arguments:"{}")
        var batchWrites=0
        batchContext.configure={session,request in session.executeBody={call,session in
            if call.name == "save_memory" {
                guard batchService.memory.put(.init(registration:request.registration,text:"Fictional preference",kind:.preference,explicit:true,provenance:"Fictional human",sourceTurnID:request.turnID.uuidString)) else {throw ActionFailure.message("Fixture memory save failed")}
                session.receipts.append("Fictional earlier memory verified");return "{\"verified\":true}"
            }
            if call.name == "read_calendar" {session.calendar.sources=[destination];return "{}"}
            try PAToolProtocol.nativeReadPreflight(call.name,operation:"create",hasSources:!session.calendar.sources.isEmpty,hasDetails:false)
            batchWrites += 1;session.receipts.append("Fictional later event verified");return "{\"verified\":true}"
        }}
        batchProvider.replies=[response([memoryCall,creation]),final("Fictional batch completed")]
        _=batchService.send(runtime:batchContext.runtime(),topicID:nil,prompt:"Remember my fictional preference and add the fictional event")
        await until{!batchService.busy}
        check(batchWrites == 1 && batchContext.sessions[0].receipts.count == 2 && batchService.error == nil,"A recovered later operation preserves earlier verified receipts and self-authored memory revision")
        let replayed=batchProvider.inputs[1].filter{$0["type"] as? String == "function_call_output"}.compactMap{$0["call_id"] as? String}
        check(replayed == [memoryCall.id,creation.id],"Internal reads do not fabricate completed transport calls or duplicate the original operation")
        let readOnlyProvider=FictionalInference(),readOnlyContext=FictionalContext()
        let readOnlyService=service(readOnlyProvider,try open("readonly-receipts-unavailable"))
        var readOnlyOutcomes:[AssistantTurnOutcome]=[]
        var readOnlyRuntime=readOnlyContext.runtime();readOnlyRuntime.finished={readOnlyOutcomes.append($0)}
        var readOnlyProgress:[AssistantTurnOutcome]=[]
        readOnlyRuntime.working={readOnlyProgress.append($0)}
        readOnlyContext.configure={session,_ in session.actionReceiptsReadable=false}
        readOnlyProvider.replies=[final("Supported fictional read-only answer")]
        _=readOnlyService.send(runtime:readOnlyRuntime,topicID:nil,prompt:"Explain this fictional project")
        await until{!readOnlyService.busy}
        check(readOnlyOutcomes.last?.phase == "completed" && readOnlyOutcomes.last?.unconfirmedActions == 0,"Unavailable historical action receipts cannot invent uncertainty for a read-only answer")
        check(readOnlyProgress.isEmpty && readOnlyOutcomes.last?.attemptedTools.isEmpty == true,"A conversation-only answer emits no work progress or invented tool attempts")

        let uncertainProvider=FictionalInference(),uncertainContext=FictionalContext()
        let uncertainService=service(uncertainProvider,try open("uncertain-turn"))
        var uncertainOutcomes:[AssistantTurnOutcome]=[]
        var uncertainRuntime=uncertainContext.runtime();uncertainRuntime.finished={uncertainOutcomes.append($0)}
        var workingOutcomes:[AssistantTurnOutcome]=[]
        uncertainRuntime.working={outcome in
            check(uncertainContext.sessions[0].calls.isEmpty,"Work progress is emitted before the tool can attempt a save")
            check(uncertainContext.sessions[0].actionCountReads == 0,"Progress metadata never reads the durable action ledger")
            workingOutcomes.append(outcome)
        }
        uncertainContext.configure={session,_ in session.executeBody={_,session in
            session.pendingNativeActionCount=1
            throw PANativeActionUncertainty(operationKey:"fictional-durable-claim",nativeReadbackVerified:true,message:"Fictional save receipt is unconfirmed")
        }}
        uncertainProvider.replies=[response([nativeCall("change_calendar")]),final("This unsupported success must never be requested")]
        _=uncertainService.send(runtime:uncertainRuntime,topicID:nil,prompt:"Add the fictional event")
        await until{!uncertainService.busy}
        check(uncertainProvider.inputs.count == 1 && uncertainProvider.replies.count == 1,"Native uncertainty stops the real engine before another inference or save")
        check(uncertainOutcomes.count == 1 && uncertainOutcomes[0].phase == "uncertain" && uncertainOutcomes[0].unconfirmedActions == 1,"Fluent output cannot hide an unconfirmed native operation")
        check(workingOutcomes.count == 1 && workingOutcomes[0].attemptedTools == ["change_calendar"] && uncertainOutcomes[0].attemptedTools == ["change_calendar"],"Running and uncertain outcomes retain the same typed work")
        check(uncertainService.activityContext(uncertainOutcomes[0].conversationID)?.attemptedTools[uncertainOutcomes[0].responseTurnID] == ["change_calendar"],"Activity metadata publishes completed tool traces while retaining uncertain outcomes")

        let reviewProvider=FictionalInference(),reviewContext=FictionalContext()
        let reviewContainer=try open("review-handover"),reviewService=service(reviewProvider,reviewContainer)
        let primaryID=reviewService.openPA()!,humanID=UUID(),responseID=UUID()
        let reviewID=reviewService.openReview(key:"mail:fictional-source",title:"Fictional engineering milestones",sourceKind:"mail",accountID:"fictional-mail",messageID:"fictional-source",identity:nil,chatID:nil,seeds:[.init(role:"assistant",content:"Fictional source plan only",completed:true)])!
        check(reviewService.activityContext(reviewID)?.reviewMessageID == "fictional-source","Stable Activity context retains exact Review source ownership")
        check(reviewService.activeID == primaryID && reviewService.feed?.turns.isEmpty == true,"Opening Review retains general feed and selection without inference")
        check(reviewService.topics.isEmpty,"Dedicated Review is excluded from legacy topics")
        reviewService.draft="Retained general draft"
        var reviewValid=true,reviewFinished:[AssistantTurnOutcome]=[],normalFinished:[AssistantTurnOutcome]=[]
        var reviewRuntime=reviewContext.runtime();reviewRuntime.finished={reviewFinished.append($0)}
        var normalRuntime=reviewContext.runtime();normalRuntime.finished={normalFinished.append($0)}
        reviewProvider.holdNext=true
        let submitted=Date.now.addingTimeInterval(-120)
        check(reviewService.sendReview(runtime:reviewRuntime,conversationID:reviewID,prompt:"Please explain the fictional dates",humanTurnID:humanID,responseTurnID:responseID,query:"engineering milestones",sourceContext:"fictional-source",selectionContext:"Only selected fictional project tasks; unselected Calendar proposals are excluded.",submitted:submitted,focusAreas:[.studies],valid:{reviewValid}),"Real Review uses the shared engine")
        await until{reviewProvider.waiting}
        check(reviewContext.requests.last?.history.contains{$0["content"]?.contains("unselected Calendar proposals are excluded") == true} == true && String(describing:reviewProvider.inputs[0]).contains("unselected Calendar proposals are excluded"),"The inference and intent ports capture the displayed checkbox selection")
        check(reviewService.activeID == primaryID && reviewService.draft == "Retained general draft" && reviewService.feed?.turns.isEmpty == true,"A held Review keeps general selection, draft and history")
        check(reviewService.conversation(reviewID)?.turns.contains{$0.id == humanID && $0.created == submitted} == true,"Review retains captured human ID and submission time")
        check(reviewService.send(runtime:normalRuntime,topicID:nil,prompt:"A separate foreground request",focusAreas:[.career]),"Explicit foreground request queues while Review unwinds")
        reviewValid=false;reviewService.cancel();reviewProvider.replies=[final("Separate foreground result")];reviewProvider.release()
        await until{!reviewService.busy}
        check(reviewFinished.count == 1 && reviewFinished[0].responseTurnID == responseID && normalFinished.isEmpty,"Review completion fires once and does not run a general job through its continuation")
        reviewService.continueForegroundAfterReview(runtime:normalRuntime)
        await until{!reviewService.busy && normalFinished.count == 1}
        check(reviewFinished.count == 1 && reviewService.feed?.turns.last?.content == "Separate foreground result","Normal handover retains its own finished callback and result")
        let normalInput=String(describing:reviewProvider.inputs.last!)
        check(!normalInput.contains("Fictional source plan only") && !normalInput.contains("Please explain the fictional dates"),"General inference never receives isolated Review history")
        check(reviewService.draft == "Retained general draft","Normal handover preserves unsent general draft")
        let reopenedReview=service(reviewProvider,reviewContainer)
        check(reopenedReview.conversation(reviewID)?.reviewKey == "mail:fictional-source" && reopenedReview.feed?.id == primaryID,"Reopening preserves Review identity separately from the primary feed")

        // The real AssistantService and PAMemoryStore share a current native
        // snapshot only within each synchronous ownership decision. There is
        // no provider, source collection, native write or personal state here.
        for revokeSource in [false,true] {
            let projectionProvider=FictionalInference(),projectionContext=FictionalContext()
            let projectionService=service(projectionProvider,try open(revokeSource ? "stream-source-withdrawal" : "stream-source-batching"))
            let sourceIdentity=MemorySourceIdentity(kind:.calendar,accountID:"fictional-provider",containerID:"fictional-calendar",itemID:"fictional-stream-item")
            let sourceQuote="Prepare the fictional Orion prototype."
            let sourceItem=NativeLearningItem(identity:sourceIdentity,revision:"fictional-current-v1",label:"Fictional Studies",text:sourceQuote,date:projectionContext.now,changed:Date.now)
            let sourceEvidence=MemorySourceEvidence(identity:sourceIdentity,revision:sourceItem.revision,label:sourceItem.label,quote:sourceQuote,observed:Date.now,sourceDate:sourceItem.date)
            let sourceFact=PAMemory(registration:projectionProvider.activeID,text:"A Calendar entry requests the fictional Orion prototype.",kind:.commitment,explicit:false,provenance:"Fictional Calendar source",evidence:sourceQuote,certainty:.inferred,durability:.situational,source:sourceEvidence,sourceState:.proposed)
            check(projectionService.memory.putSources([sourceFact],evidenceTexts:[sourceIdentity:sourceQuote],expectedRevision:projectionService.memory.revision),"Streaming batching fixture saves exact source evidence in disposable storage")
            let validation=NativeLearningValidationBatch()
            var sourceAvailable=true,validationDecisions=0,nativeQueries=0,nativeBuilds=0,withdrawnBuilds=0
            @MainActor func currentItems()->[NativeLearningItem]? {
                nativeQueries += 1
                return validation.items(.calendar) {
                    nativeBuilds += 1
                    if !sourceAvailable {withdrawnBuilds += 1;return nil}
                    return [sourceItem]
                }
            }
            projectionService.memory.sourcePermissionProjection={
                guard let items=currentItems() else {return []}
                return Set(projectionService.memory.records.filter{NativeLearningRules.permitted($0,items:items)}.map(\.id))
            }
            projectionContext.pageCapture={_,_,_,_,_ in
                .init(text:"{\"pages\":[{\"id\":\"fictional-current-source\",\"markdown\":\"Orion page summary\"}]}",pageIDs:["fictional-current-source"],memoryIDs:[sourceFact.id])
            }
            var projectionRuntime=projectionContext.runtime()
            projectionRuntime.state={
                // A current runtime acknowledgement can depend on the same
                // native kind as the independent source-memory ownership guard.
                _=currentItems()
                return projectionContext.state
            }
            projectionRuntime.withValidation={body in
                validationDecisions += 1
                return validation.withSnapshot(body)
            }
            projectionProvider.deltas=(1...200).map{"Fictional streamed token \($0). "}
            projectionProvider.replies=[final("Completed fictional current-source response")]
            var emittedDeltas=0,partialAtWithdrawal=""
            projectionProvider.afterDelta={
                emittedDeltas += 1
                if revokeSource && emittedDeltas == 50 {
                    partialAtWithdrawal=projectionService.feed?.turns.last?.content ?? ""
                    sourceAvailable=false
                }
            }
            let clock=ContinuousClock(),began=clock.now
            check(projectionService.send(runtime:projectionRuntime,topicID:nil,prompt:"Explain the fictional Orion prototype"),"Current-source streaming fixture starts the actual assistant service")
            // Preparation has separate current decisions; isolate the engine's
            // callback counts before its task first runs on the main actor.
            validationDecisions=0;nativeQueries=0;nativeBuilds=0;withdrawnBuilds=0
            await until{!projectionService.busy}
            let localElapsed=began.duration(to:clock.now)
            let projectedCapture=projectionService.feed?.turns.last?.contextCapture
            check(projectedCapture?.directMemoryIDs == [] && projectedCapture?.pageSupportingMemoryIDs == [sourceFact.id],"Source-backed streaming depends on page evidence without supplying an automatic raw fact list")
            check(validationDecisions == 2,"Two full boundary decisions protect 200 partial callbacks without rebuilding evidence between words")
            check(nativeQueries == validationDecisions*2 && nativeBuilds == validationDecisions,"Runtime and source-memory consumers share one current snapshot per boundary")
            if revokeSource {
                check(withdrawnBuilds > 0 && projectionService.error != nil,"The completion boundary freshly checks unavailable supporting evidence")
                check(!partialAtWithdrawal.isEmpty && projectionService.feed?.turns.last?.content != "Completed fictional current-source response" && projectionService.feed?.turns.last?.completed == false,"Changed supporting evidence cannot become a completed reply; provisional streamed text stays labelled partial")
            } else {
                check(projectionService.feed?.turns.last?.content == "Completed fictional current-source response" && projectionService.feed?.turns.last?.completed == true && projectionService.error == nil,"Batching retains authoritative completed text and ordinary chat behaviour")
            }
            check(projectionContext.sessions.allSatisfy{$0.calls.isEmpty},"Streaming validation never invokes tools or performs a save")
            print("Local current-source streaming:200 deltas; revoke=\(revokeSource); decisions \(validationDecisions); queries \(nativeQueries); builds \(nativeBuilds); elapsed \(localElapsed)")
        }
        do {
            let definitions=ReviewPlanTools.tools.first?["tools"] as? [[String:Any]] ?? []
            let normal=PAToolProtocol.tools.first?["tools"] as? [[String:Any]] ?? []
            check(definitions.contains{$0["name"] as? String == "prepare_review_actions"} && !normal.contains{$0["name"] as? String == "prepare_review_actions"},"Only Review inference receives the draft proposal tool")
            check(ReviewPlanTools.tools.count == 1 && ReviewPlanTools.tools[0]["name"] as? String == "pa", "Draft preparation retains the local pa tool namespace")
            let input=ReviewPlanTools.Input(revision:UUID(),actions:[.init(existingID:"issued-action",selected:false)])
            let args=String(decoding:try JSONEncoder().encode(input),as:UTF8.self)
            let call=PAFunctionCall(id:"draft",name:"prepare_review_actions",namespace:"pa",arguments:args)
            let parsed=try ReviewPlanTools.input(call)
            check(parsed.revision == input.revision && parsed.actions[0].existingID == "issued-action" && !parsed.actions[0].selected,"Typed plan requests preserve exact revision and unticked action identity")
            var foreign=call;foreign.namespace="foreign"
            do {_=try ReviewPlanTools.input(foreign);check(false,"Foreign namespace cannot prepare a Review plan")} catch {check(true,"Foreign namespace cannot prepare a Review plan")}
            var object=try JSONSerialization.jsonObject(with:Data(args.utf8)) as! [String:Any]
            var rows=object["actions"] as! [[String:Any]];rows[0]["nativeSave"]="attempted";object["actions"]=rows
            var unknown=call;unknown.arguments=String(decoding:try JSONSerialization.data(withJSONObject:object),as:UTF8.self)
            do {_=try ReviewPlanTools.input(unknown);check(false,"Unknown concrete fields cannot slip into a draft tool")} catch {check(true,"Unknown concrete fields cannot slip into a draft tool")}
        }
        do {
            let provider=FictionalInference(),context=FictionalContext(),store=try open("review-canonical-actions"),service=service(provider,store)
            let id=service.openReview(key:"mail:canonical",title:"Fictional actions",sourceKind:"mail",accountID:"mail",messageID:"canonical",identity:nil,chatID:nil,seeds:[])!
            var outcomes:[AssistantTurnOutcome]=[],executions=0
            var runtime=context.runtime();runtime.prepareReviewActions={_,_ in "{}"}
            runtime.executeReviewActions={_,valid,refresh in
                precondition(valid());executions += 1
                for name in ["A","B"] {
                    precondition(valid(),"The previous verified save must not invalidate this batch")
                    let item=LifeItem(registration:service.connection.activeID,kind:.space,title:name)
                    _=try service.projects.create([item],receipt:.init(id:"review-"+name,registration:item.registration,result:"Created "+name,itemID:item.id))
                    refresh(true)
                    precondition(valid(),"Only the self-authored project revision is adopted")
                }
                return .init(output:"{\"verified\":true}",confirmed:["a":"Created A","b":"Created B"])
            }
            runtime.finished={outcomes.append($0)}
            provider.replies=[response([nativeCall("execute_review_actions")]),final("Two actions completed")]
            check(service.sendReview(runtime:runtime,conversationID:id,prompt:"Add both",humanTurnID:UUID(),responseTurnID:UUID(),query:"Add both",sourceContext:"{}",selectionContext:"Issued exact actions",submitted:context.now,focusAreas:[],valid:{true}),"Review accepts canonical execution through its isolated conversation")
            await until{!service.busy}
            check(executions == 1 && context.sessions.first?.calls.isEmpty == true,"Prepared execution uses its canonical callback rather than generic native creation")
            check(outcomes.first?.confirmedActions == 2 && outcomes.first?.receipts == ["Created A","Created B"] && outcomes.first?.phase == "completed","Canonical execution contributes exact confirmed receipts and honest completion")
        }
        do {
            let provider=FictionalInference(),context=FictionalContext(),container=try open("chat-approval")
            let assistant=service(provider,container),id=assistant.openPA()!
            let snapshot=Data("fictional exact target snapshot".utf8)
            context.configure={session,_ in session.executeBody={call,_ in
                throw PAChatApprovalRequired(proposal:.init(toolName:call.name,arguments:"{\"exact\":\"fictional target\"}",snapshot:snapshot,outline:["Create fictional space"],details:["Inside fictional Engineering"]))
            }}
            var outcomes:[AssistantTurnOutcome]=[],executed:[UUID]=[],allowed=true
            var runtime=context.runtime()
            runtime.finished={outcomes.append($0)}
            runtime.approvalAvailable={_ in allowed}
            runtime.approveAction={proposal,valid in
                check(valid() && proposal.snapshot == snapshot,"Button approval keeps exact captured payload and current ownership")
                executed.append(proposal.id);return "Created fictional approved item"
            }
            provider.replies=[tools(["create_life_items","change_calendar"]),final("I already saved everything")]
            check(assistant.send(runtime:runtime,topicID:nil,prompt:"Set up the fictional modules"),"Action planning starts")
            await until{!assistant.busy}
            let turn=assistant.conversation(id)!.turns.last!
            check(turn.actionApprovals?.count == 2 && turn.actionApprovals?.allSatisfy{$0.phase == .pending} == true,"Multiple uncertain actions become saved proposals")
            check(turn.content.contains("Review the proposed actions") && !turn.content.contains("already saved"),"Pending approval overrides an invented completion claim")
            check(outcomes.last?.phase == "needsAnswer" && outcomes.last?.errors.isEmpty == true,"Approval is waiting for human input, not a failed action")
            check(executed.isEmpty,"Preparing an approval never executes a write")
            let reopened=service(provider,container)
            check(reopened.conversation(id)?.turns.last?.actionApprovals == turn.actionApprovals,"Never-started approvals survive reopening with the same identities")
            reopened.draft="An unsent variation"
            allowed=false
            check(!reopened.approveActions(runtime:runtime,conversationID:id,responseID:turn.id),"Withdrawn access prevents approval")
            allowed=true
            let before=provider.inputs.count
            check(reopened.approveActions(runtime:runtime,conversationID:id,responseID:turn.id),"Explicit button approval starts the captured actions")
            check(!reopened.approveActions(runtime:runtime,conversationID:id,responseID:turn.id),"A rapid second click cannot start a second save")
            await until{!reopened.busy}
            check(executed == turn.actionApprovals!.map(\.id),"Only the displayed exact actions execute once, in order")
            check(provider.inputs.count == before,"Button approval makes zero AI calls")
            check(reopened.draft == "An unsent variation","Approval preserves the unsent composer draft")
            check(reopened.conversation(id)?.turns.last?.actionApprovals?.allSatisfy{$0.phase == .completed && $0.approvedAt != nil} == true,"Verified results are persisted on the original proposals")
            check(!reopened.approveActions(runtime:runtime,conversationID:id,responseID:turn.id),"Completed approvals cannot be replayed")
            check(service(provider,container).conversation(id)?.turns.last?.actionApprovals?.allSatisfy{$0.phase == .completed} == true,"Completed receipts survive reopen")
        }
        do {
            let provider=FictionalInference(),context=FictionalContext(),assistant=service(provider,try open("approval-keeps-sibling")),id=assistant.openPA()!
            context.configure={session,_ in session.executeBody={call,_ in
                if call.name == "create_life_items" {throw ActionFailure.message("A different requested action could not be saved")}
                throw PAChatApprovalRequired(proposal:.init(toolName:call.name,arguments:"{}",snapshot:Data(),outline:["Fictional Calendar action"],details:[]))
            }}
            var outcomes:[AssistantTurnOutcome]=[],runtime=context.runtime()
            runtime.finished={outcomes.append($0)};runtime.approvalAvailable={_ in true};runtime.approveAction={_,_ in "Calendar event created"}
            provider.replies=[tools(["create_life_items","change_calendar"]),final("Approve the Calendar action")]
            check(assistant.send(runtime:runtime,topicID:nil,prompt:"Do the two fictional actions"),"Mixed failure and pending approval starts")
            await until{!assistant.busy}
            let response=assistant.conversation(id)!.turns.last!.id
            check(assistant.approveActions(runtime:runtime,conversationID:id,responseID:response),"The supported sibling can still be approved")
            await until{!assistant.busy}
            check(outcomes.last?.phase == "partial" && outcomes.last?.errors.contains("A different requested action could not be saved") == true,"Successful button approval retains the unrelated failed sibling")
        }
        do {
            let provider=FictionalInference(),context=FictionalContext(),container=try open("chat-approval-uncertainty")
            let assistant=service(provider,container),id=assistant.openPA()!
            context.configure={session,_ in session.executeBody={call,_ in
                throw PAChatApprovalRequired(proposal:.init(toolName:call.name,arguments:"{}",snapshot:Data(),outline:["Fictional change"],details:[]),stopInference:true)
            }}
            var runtime=context.runtime(),writes=0
            runtime.approvalAvailable={_ in true}
            runtime.approveAction={_,_ in writes += 1;throw PANativeActionUncertainty(operationKey:"fictional-key",message:"Check the existing save")}
            provider.replies=[tools(["change_calendar"])]
            check(assistant.send(runtime:runtime,topicID:nil,prompt:"Make the fictional change"),"Unavailable intent can prepare a complete local proposal")
            await until{!assistant.busy}
            let turn=assistant.conversation(id)!.turns.last!
            check(provider.inputs.count == 1 && turn.completed,"Unavailable intent stops inference without a provider retry")
            check(assistant.approveActions(runtime:runtime,conversationID:id,responseID:turn.id),"Human approval can execute the displayed complete proposal without intent inference")
            await until{!assistant.busy}
            check(writes == 1 && assistant.conversation(id)?.turns.last?.actionApprovals?.first?.phase == .attempted,"Uncertain save retains attempted state and never claims success")
            let reopened=service(provider,container)
            check(!reopened.approveActions(runtime:runtime,conversationID:id,responseID:turn.id),"Reopening never replays an attempted uncertain save")
        }
        do {
            let provider=FictionalInference(),context=FictionalContext(),container=try open("chat-approval-revision")
            let assistant=service(provider,container),id=assistant.openPA()!
            context.configure={session,_ in session.executeBody={call,_ in throw PAChatApprovalRequired(proposal:.init(toolName:call.name,arguments:"{}",snapshot:Data(),outline:["Fictional change"],details:[]),stopInference:true)}}
            var runtime=context.runtime();runtime.approvalAvailable={_ in true};runtime.approveAction={_,_ in preconditionFailure("A dismissed proposal cannot execute")}
            provider.replies=[tools(["change_calendar"])]
            check(assistant.send(runtime:runtime,topicID:nil,prompt:"Prepare the fictional change"),"Supersession fixture starts")
            await until{!assistant.busy}
            let responseID=assistant.conversation(id)!.turns.last!.id
            provider.replies=[final("Understood, cancelled")]
            check(assistant.send(runtime:runtime,topicID:nil,prompt:"Actually don't do that"),"A later human direction is accepted")
            await until{!assistant.busy}
            check(assistant.conversation(id)?.turns.first(where:{$0.id == responseID})?.actionApprovals?.first?.phase == .dismissed,"A later human direction dismisses old pending authority")
            check(!assistant.approveActions(runtime:runtime,conversationID:id,responseID:responseID),"Cancelled old proposals cannot be approved")
            provider.replies=[tools(["change_calendar"])]
            _=assistant.send(runtime:runtime,topicID:nil,prompt:"Prepare a different fictional change")
            await until{!assistant.busy}
            let dismissID=assistant.conversation(id)!.turns.last!.id,before=provider.inputs.count
            check(assistant.dismissActions(conversationID:id,responseID:dismissID),"Dismiss explicitly declines the saved proposals")
            check(assistant.conversation(id)?.turns.last?.actionApprovals?.allSatisfy{$0.phase == .dismissed} == true && provider.inputs.count == before,"Dismiss is local, persists the declined state and makes no inference")
            check(!assistant.approveActions(runtime:runtime,conversationID:id,responseID:dismissID),"A dismissed proposal cannot execute later")
        }
        do {
            let provider=FictionalInference(),context=FictionalContext(),assistant=service(provider,try open("chat-approval-queue"))
            context.configure={session,_ in session.executeBody={call,_ in throw PAChatApprovalRequired(proposal:.init(toolName:call.name,arguments:"{}",snapshot:Data(),outline:["Create A","Create B","Create C","Create D"],details:[]),stopInference:true)}}
            var runtime=context.runtime(),outcomes:[AssistantTurnOutcome]=[]
            runtime.approvalAvailable={_ in true};runtime.approveAction={_,_ in "Created four fictional items"};runtime.finished={outcomes.append($0)}
            _=assistant.queue.add(registration:provider.activeID,topicID:nil,prompt:"Queued fictional modules")
            _=assistant.queue.add(registration:provider.activeID,topicID:nil,prompt:"Later queued work")
            provider.replies=[tools(["create_life_items"])]
            assistant.resumeQueue(runtime:runtime)
            await until{!assistant.busy}
            let feed=assistant.feed!,turn=feed.turns.last!,queuedID=assistant.queue.items[0].id
            check(assistant.queue.items[0].state == .needsAnswer && assistant.queue.items[1].state == .waiting && provider.inputs.count == 1,"Approval pauses the general delegated queue before unrelated queued work")
            check(turn.approvalQueuedRequestID == queuedID,"The proposal retains its exact queued request association")
            check(assistant.approveActions(runtime:runtime,conversationID:feed.id,responseID:turn.id),"Queued proposal accepts local human approval")
            await until{!assistant.busy}
            check(assistant.queue.items[0].state == .completed && assistant.queue.items[1].state == .waiting,"Approval resolves only the associated queue request without replay or automatic continuation")
            check(outcomes.last?.confirmedActions == 4,"A four-item batch reports four created items rather than one receipt")
        }
        print("PASS \(count) actual assistant service contracts: persisted preparation/send/reopen, exact traces/receipts, setup, ownership cancellation, serial queues, native-read recovery and direct in-chat approval; fictional providers/storage/settings only, no dashboard or Keychain.")
    }
}
