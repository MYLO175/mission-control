import Foundation
import SwiftData

@MainActor private final class FictionalInference: PAInferenceConnection {
    var activeID = "fixture"
    var selectedModel = "fictional"
    var busy = false
    var usagePaused = false
    var inferenceVerified = true
    var hasSession = true
    var answer = "{\"memories\":[]}"
    var calls = 0
    var requestedModels:[String]=[]
    var inputs:[[[String:String]]]=[]
    var onCall: (() -> Void)?
    var hold: (() async -> Void)?
    func streamResponse(input: [[String:String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        calls += 1;requestedModels.append(model ?? "");inputs.append(input);onCall?();if let hold {await hold()};return answer
    }
    func toolResponse(input: [[String:Any]], instructions: String, tools: [[String:Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse { fatalError("Learning cannot execute foreground tools") }
}
@MainActor private final class FictionalAssistant: LearningAssistantReading {
    let connection: any PAInferenceConnection
    let memory: PAMemoryStore
    var busy = false
    var hasDraft = false
    var contextEnabled = true
    var contextRevision = UUID()
    var topics: [AssistantConversation] = []
    var excludedCalendars = Set<String>()
    var excludedLists = Set<String>()
    var excludedAccounts = Set<String>()
    var turns: [MemoryLearningTurn] = []
    var acknowledged = 0
    init(_ connection: any PAInferenceConnection, memory: PAMemoryStore) { self.connection = connection; self.memory = memory }
    func learningTurns() -> [MemoryLearningTurn] { turns }
    func acknowledgeLearned(_ learned: [LearnedMemory]) { acknowledged += learned.count }
}
@MainActor private final class FictionalWhatsApp: WhatsAppLearningReading {
    var messages: [WhatsAppReadMessage] = []
    var chats: [WhatsAppChat] = [.init(id:"chat", name:"Fictional", group:true)]
    var accessValue = WhatsAppAccess(enabled:true, chats:["chat"], learnContext:true)
    var revision = UUID()
    func scope(for registration: String) -> WhatsAppSourceScope { .init(registration:registration, linkedIdentity:"fictional-device", revision:revision) }
    func access(for registration: String) -> WhatsAppAccess { accessValue }
}

@main struct LearningRuntimeChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); count += 1 }
        let suite = "3PO.learning-fixture." + UUID().uuidString
        let settings = UserDefaults(suiteName:suite)!
        defer { settings.removePersistentDomain(forName:suite) }
        let preferencesBeforeConstruction = NSDictionary(dictionary:settings.persistentDomain(forName:suite) ?? [:])
        let container = try ModelContainer(for:CachedDashboard.self, configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let inference = FictionalInference(), memory = PAMemoryStore(container:container, settings:settings)
        let assistant = FictionalAssistant(inference, memory:memory), whatsapp = FictionalWhatsApp()
        let budget = LearningBudget(container:container)
        var now = Date.now, writing = false, activity = LearningActivity(), sourceRevision = 0
        var native: [NativeLearningItem] = []
        let runtime = LearningRuntime(assistant:assistant, inference:inference, learningBudget:budget, whatsapp:whatsapp, now:{now}, activity:{activity}, writing:{writing}, sourceRevision:{sourceRevision}, nativeItems:{kind,_ in kind == .reminder ? native : nil})
        let conversation = MemoryLearningService(container:container, settings:settings)
        let sources = NativeSourceLearningService(container:container)
        let messages = SourceContextLearningService(container:container)
        let organisation = LifeOrganisationService(container:container, settings:settings)
        let maintenance = MemoryMaintenanceService(container:container)
        check(preferencesBeforeConstruction.isEqual(to:settings.persistentDomain(forName:suite) ?? [:]), "Constructing memory and learning services must not persist default controls")
        func wait(_ isBusy: () -> Bool) async {
            for _ in 0..<10_000 { if !isBusy() { return }; await Task.yield() }
            preconditionFailure("A fictional service failed to finish")
        }
        assistant.turns = [.init(id:"intro", text:"I study Materials Engineering", created:now)]
        inference.answer = "{\"memories\":[{\"turnID\":\"intro\",\"text\":\"Studies Materials Engineering\",\"kind\":\"context\",\"evidence\":\"I study Materials Engineering\",\"certainty\":\"stated\",\"durability\":\"stable\"}]}"
        conversation.check(runtime)
        await wait { conversation.busy }
        check(inference.calls == 1 && memory.records.count == 1 && assistant.acknowledged == 1, "Actual conversation learning must persist a supported human fact")
        check(budget.receipts("fixture")[.conversation] == now, "Actual claim must use the supplied clock")
        check(PAMemoryStore(container:container, settings:settings).records.map(\.id) == memory.records.map(\.id), "The learned identity must survive reopen")
        assistant.turns.append(.init(id:"second", text:"My project is about optics", created:now))
        assistant.hasDraft = true; now.addTimeInterval(1800)
        conversation.check(runtime)
        check(inference.calls == 1 && !conversation.busy, "Foreground draft prevents a learning claim")
        assistant.hasDraft = false; activity.otherWorkBusy = true
        conversation.check(runtime)
        check(inference.calls == 1, "Other background work prevents overlap")
        activity.otherWorkBusy = false; inference.answer = "{\"memories\":[]}"
        inference.onCall = { inference.activeID = "changed" }
        conversation.check(runtime)
        await wait { conversation.busy }
        check(inference.calls == 2 && conversation.error != nil && memory.records.count == 1, "Account drift rejects late learning output")
        inference.activeID = "fixture"; inference.onCall = nil; now.addTimeInterval(1800)
        conversation.check(runtime)
        check(inference.calls == 2 && !conversation.busy, "Failed conversation claim remains paused")
        conversation.check(runtime, manual:true)
        await wait { conversation.busy }
        check(inference.calls == 3 && conversation.error == nil, "Human review explicitly resumes one paused pass")

        sources.setEnabled(true, kind:.reminder, model:runtime)
        check(inference.calls == 3, "Opt-in baselines cached content without inference")
        native = [.init(identity:.init(kind:.reminder, accountID:"fixture", containerID:"list", itemID:"item"), revision:"one", label:"Fictional task", text:"Prepare the optics report", date:now, changed:now)]
        inference.answer = "{\"facts\":[]}"
        sources.check(runtime, kind:.reminder)
        await wait { sources.busy }
        check(inference.calls == 4 && sources.error == nil, "Actual native learning consumes one permitted cached delta")
        check(budget.receipts("fixture")[.nativeSources] == now, "Native receipt uses the same shared budget and clock")
        now.addTimeInterval(1800); native[0].revision = "two"; native[0].changed = now
        inference.onCall = { sourceRevision += 1;native[0].revision = "changed-exact-item" }
        sources.check(runtime, kind:.reminder)
        await wait { sources.busy }
        check(inference.calls == 5 && sources.error != nil, "An exact assessed-item revision change rejects native output")
        inference.onCall = nil; now.addTimeInterval(1800)
        sources.check(runtime, kind:.reminder)
        check(inference.calls == 5 && !sources.busy, "Failed native claim is never silently replayed")

        // Use explicit human review for remaining services; automatic daily slots
        // were consumed above and must retain their original shared allowance.
        whatsapp.messages = [.init(id:"message", chat:"chat", sender:"contact", text:"Please prepare the optics report", sentByMe:false, time:now.timeIntervalSince1970 * 1000)]
        messages.check(runtime, manual:true)
        await wait { messages.busy }
        check(inference.calls == 6 && messages.error == nil, "Actual WhatsApp service accepts a selected cached batch through its reader port")
        inference.answer = "{\"entries\":[]}"
        organisation.check(runtime, manual:true)
        await wait { organisation.busy }
        check(inference.calls == 7 && organisation.error == nil, "Actual organisation runs without dashboard or source access")
        inference.answer = "{\"proposals\":[]}"
        maintenance.check(runtime, manual:true)
        await wait { maintenance.busy }
        check(inference.calls == 8 && maintenance.error == nil, "Actual maintenance proposes review without a dashboard")
        check(memory.records.count == 1, "Empty source/organisation/review output cannot invent facts")
        check(budget.receipts("fixture")[.organisation] == nil && budget.receipts("fixture")[.maintenance] == nil && budget.receipts("fixture")[.whatsapp] == nil, "Manual passes cannot advance automatic fairness receipts")
        writing = true; conversation.check(runtime, manual:true)
        check(inference.calls == 8, "Native writing prevents competing learning work")
        writing = false
        assistant.turns.append(.init(id:"third", text:"I value careful preparation", created:now))
        inference.answer = "{\"memories\":[{\"turnID\":\"third\",\"text\":\"Values careful preparation\",\"kind\":\"preference\",\"evidence\":\"I value careful preparation\"}]}"
        inference.onCall = { assistant.busy = true }
        conversation.check(runtime, manual:true)
        await wait { conversation.busy }
        check(inference.calls == 9 && conversation.error != nil && memory.records.count == 1, "A foreground request without a draft still rejects late learning output")
        check(MemoryLearningService(container:container, settings:settings).state.accounts["fixture"]?.paused == true, "Foreground interruption keeps the durable failed claim paused after reopen")
        assistant.busy=false;inference.onCall=nil;inference.activeID="owned-fixture";now.addTimeInterval(86400)
        var ownerValid=true,permission=true,claims=0,seenRun:String?
        let owned=LearningRuntime(assistant:assistant,inference:inference,learningBudget:budget,whatsapp:whatsapp,now:{now},activity:{activity},writing:{writing},sourceRevision:{sourceRevision},nativeItems:{kind,_ in kind == .reminder ? native : nil},ownership:.init(runID:"heartbeat-A",validate:{if !ownerValid {throw MemoryLearningFailure.changed}},claim:{claims += 1}),reviewNativePermission:{_ in permission},reviewWhatsAppPermission:{permission})
        memory.sourceIsPermitted={sources.permits($0,model:owned)}
        native=[];sources.check(owned,kind:.reminder)
        check(!sources.enabled(.reminder,registration:inference.activeID) && sources.permittedKind(.reminder,model:owned),"Inherited source permission never rewrites saved opt-ins")
        check(claims == 0 && !sources.busy,"Inherited source permission establishes a baseline without inference")
        native=[.init(identity:.init(kind:.reminder,accountID:"fixture",containerID:"list",itemID:"owned-item"),revision:"one",label:"Fictional task",text:"Prepare the optics report",date:now,changed:now)]
        let itemID=native[0].id
        inference.answer="{\"facts\":[{\"itemID\":\"\(itemID)\",\"text\":\"The reminder requests preparation of the optics report\",\"quote\":\"Prepare the optics report\",\"kind\":\"commitment\",\"areas\":[\"studies\"],\"state\":\"proposed\"}]}"
        inference.onCall={seenRun=sources.ownedHeartbeatRunID}
        sources.check(owned,kind:.reminder);await wait{sources.busy}
        check(claims == 1 && seenRun == "heartbeat-A" && sources.ownedHeartbeatRunID == nil,"Actual owned learner claims once and clears exact run identity after finishing")
        check(memory.records.last?.organisation?.areas == [.studies] && memory.records.last?.source != nil,"Source learning saves inline organisation with exact source evidence")
        let learnedSource=memory.records.last!
        permission=false
        check(!sources.permits(learnedSource,model:owned),"Withdrawing inherited review permission immediately withdraws source recall")
        let callsBeforeBlocked=inference.calls
        sources.check(owned,kind:.reminder)
        check(inference.calls == callsBeforeBlocked,"Revoked permission cannot start source inference")
        permission=true;now.addTimeInterval(1800);native[0].revision="two";native[0].changed=now
        inference.onCall={ownerValid=false}
        let factsBefore=memory.records.count
        sources.check(owned,kind:.reminder);await wait{sources.busy}
        check(claims == 2 && sources.error != nil && memory.records.count == factsBefore,"Parent ownership loss rejects late child facts before commit")
        ownerValid=true;inference.onCall=nil;now.addTimeInterval(1800)
        sources.check(owned,kind:.reminder)
        check(claims == 2 && !sources.busy,"A fresh heartbeat never resumes a failed learning claim")
        whatsapp.accessValue.learnContext=false
        check(owned.whatsappLearningAccess.learnContext == true && whatsapp.accessValue.learnContext == false,"WhatsApp review inheritance is effective access, not a stored opt-in mutation")
        permission=false
        check(owned.whatsappLearningAccess.learnContext != true,"WhatsApp learning inheritance is revoked with review permission")
        permission=true;inference.activeID="owned-whatsapp";inference.answer="{\"facts\":[]}"
        whatsapp.messages=[.init(id:"older",chat:"chat",sender:"contact",text:"Please prepare the report",sentByMe:false,time:now.timeIntervalSince1970*1000)]
        messages.check(owned)
        check(!messages.busy && claims == 2,"A newly inherited WhatsApp scope baselines its current cache")
        now.addTimeInterval(1)
        whatsapp.messages.append(.init(id:"new",chat:"chat",sender:"contact",text:"Please prepare a diagram",sentByMe:false,time:now.timeIntervalSince1970*1000))
        messages.check(owned);await wait{messages.busy}
        check(claims == 3 && messages.error == nil,"Only new inherited WhatsApp deltas run under a persisted owned claim")

        do {
            let isolated=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let p=FictionalInference(),m=PAMemoryStore(container:isolated,settings:settings),w=FictionalWhatsApp()
            let a=FictionalAssistant(p,memory:m),b=LearningBudget(container:isolated)
            var clock=now,revision=0,items:[NativeLearningItem]=[]
            let r=LearningRuntime(assistant:a,inference:p,learningBudget:b,whatsapp:w,now:{clock},activity:{.init()},writing:{false},sourceRevision:{revision},nativeItems:{kind,_ in kind == .mail ? items : nil})
            let learner=NativeSourceLearningService(container:isolated)
            learner.setEnabled(true,kind:.mail,model:r)
            items=[.init(identity:.init(kind:.mail,accountID:"fictional-mail",containerID:"inbox",itemID:"target"),revision:"one",label:"Fictional report",text:"The report needs a prototype",date:clock,changed:clock)]
            p.answer="{\"facts\":[]}"
            p.onCall={
                revision += 1 // An unrelated EventKit notification.
                items.append(.init(identity:.init(kind:.mail,accountID:"fictional-mail",containerID:"inbox",itemID:"unrelated"),revision:"one",label:"Fictional unrelated message",text:"Another message arrived",date:clock,changed:clock))
            }
            learner.check(r,kind:.mail);await wait{learner.busy}
            check(p.calls == 1 && learner.error == nil,"Unrelated EventKit notifications and unissued Mail arrivals do not discard an unchanged exact assessment")
            clock.addTimeInterval(1801);items[0].revision="two";items[0].changed=clock
            p.onCall={items[0].revision="three"}
            learner.check(r,kind:.mail);await wait{learner.busy}
            check(p.calls == 2 && learner.error != nil,"Changing the exact issued Mail item still rejects its late assessment")
            p.onCall=nil;clock.addTimeInterval(1801)
            let reopened=NativeSourceLearningService(container:isolated)
            reopened.check(r,kind:.mail)
            check(p.calls == 2 && !reopened.busy,"An actual exact-source failure remains paused across reopening")
        }
        do {
            let isolated=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let p=FictionalInference(),m=PAMemoryStore(container:isolated,settings:settings),w=FictionalWhatsApp()
            let a=FictionalAssistant(p,memory:m),b=LearningBudget(container:isolated)
            var clock=now
            w.accessValue.learnContext=false
            let r=LearningRuntime(assistant:a,inference:p,learningBudget:b,whatsapp:w,now:{clock},activity:{.init()},writing:{false},sourceRevision:{0},nativeItems:{_,_ in nil},reviewWhatsAppPermission:{true})
            m.sourceIsPermitted={SourceContextRules.permitted($0,access:r.whatsappLearningAccess,linkedIdentity:"fictional-device",messages:w.messages)}
            let learner=SourceContextLearningService(container:isolated)
            w.messages=[.init(id:"old-A",chat:"chat",sender:"fictional",text:"Please prepare the old report",sentByMe:false,time:clock.addingTimeInterval(-21600).timeIntervalSince1970*1000)]
            learner.check(r)
            check(p.calls == 0 && !learner.busy,"Initial inherited access establishes a no-inference baseline")
            var expanded=w.accessValue;expanded.chats.insert("second-chat")
            w.accessValue=WhatsAppReadRules.recordingLearningAccess(expanded,previous:w.accessValue);w.revision=UUID()
            w.chats.append(.init(id:"second-chat",name:"Second fictional chat",group:true))
            w.messages.append(.init(id:"old-B",chat:"second-chat",sender:"fictional",text:"Please prepare the old diagram",sentByMe:false,time:clock.addingTimeInterval(-21600).timeIntervalSince1970*1000))
            learner.check(r)
            let expandedReopen=SourceContextLearningService(container:isolated)
            expandedReopen.check(r)
            check(p.calls == 0 && !expandedReopen.busy,"Adding a chat baselines its old cached text and persists that boundary across reopen")
            clock.addTimeInterval(1)
            let fresh=WhatsAppReadMessage(id:"fresh-B",chat:"second-chat",sender:"fictional",text:"Please prepare a new diagram",sentByMe:false,time:clock.timeIntervalSince1970*1000)
            w.messages.append(fresh)
            let freshID=SourceContextRules.recent([fresh],chats:w.chats,allowed:w.accessValue.chats,now:clock)[0].id
            p.answer="{\"facts\":[{\"messageID\":\"\(freshID)\",\"text\":\"A message requests a new diagram\",\"quote\":\"Please prepare a new diagram\",\"kind\":\"commitment\",\"areas\":[],\"state\":\"proposed\"}]}"
            expandedReopen.check(r);await wait{expandedReopen.busy}
            check(p.calls == 1 && expandedReopen.error == nil && m.records.count == 1,"New post-grant messages remain eligible for exact attributed learning")
            let evidenceBefore=m.records
            var disabled=w.accessValue;disabled.enabled=false
            w.accessValue=WhatsAppReadRules.recordingLearningAccess(disabled,previous:w.accessValue)
            check(m.permittedRecords.isEmpty,"Access withdrawal immediately excludes earlier source facts without deleting them")
            // No learner/heartbeat check observes the disabled interval.
            clock.addTimeInterval(1801)
            w.messages.append(.init(id:"disabled-gap",chat:"second-chat",sender:"fictional",text:"Old text received before access resumes",sentByMe:false,time:clock.addingTimeInterval(-60).timeIntervalSince1970*1000))
            var resumed=w.accessValue;resumed.enabled=true
            w.accessValue=WhatsAppReadRules.recordingLearningAccess(resumed,previous:w.accessValue);w.revision=UUID()
            let resumedReopen=SourceContextLearningService(container:isolated)
            resumedReopen.check(r)
            check(p.calls == 1 && !resumedReopen.busy && m.records == evidenceBefore,"A durable access generation baselines old text after an unobserved opt-out/re-enable and reopen, preserving earlier evidence")
            clock.addTimeInterval(1);w.messages.append(.init(id:"post-resume",chat:"second-chat",sender:"fictional",text:"A genuinely new post-resume message",sentByMe:false,time:clock.timeIntervalSince1970*1000))
            p.answer="{\"facts\":[]}"
            resumedReopen.check(r);await wait{resumedReopen.busy}
            check(p.calls == 2 && resumedReopen.error == nil,"New post-resume deltas still run within the original shared allowance")
            let saved=try LocalRecordRepository.read("paSourceContextLearning",container:isolated)!
            let text=String(decoding:saved,as:UTF8.self)
            check(!text.contains("second-chat") && !text.contains("disabled-gap") && !text.contains("Please prepare"),"Access receipts contain only opaque chat/message membership and revisions")
        }
        do {
            let isolated=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let p=FictionalInference(),m=PAMemoryStore(container:isolated,settings:settings),w=FictionalWhatsApp()
            let a=FictionalAssistant(p,memory:m),b=LearningBudget(container:isolated)
            var clock=now,heartbeatWhatsApp=true,epoch:UUID?=nil
            w.accessValue.learnContext=false
            let r=LearningRuntime(assistant:a,inference:p,learningBudget:b,whatsapp:w,now:{clock},activity:{.init()},writing:{false},sourceRevision:{0},nativeItems:{_,_ in nil},reviewWhatsAppPermission:{heartbeatWhatsApp},reviewWhatsAppRevision:{epoch})
            w.messages=[.init(id:"global-old",chat:"chat",sender:"fictional",text:"An old cached project request",sentByMe:false,time:clock.addingTimeInterval(-3600).timeIntervalSince1970*1000)]
            let initial=SourceContextLearningService(container:isolated)
            initial.check(r)
            check(p.calls == 0 && r.whatsappLearningAccess.learnContext == true,"Global heartbeat permission admits learning with an initial no-inference baseline")
            heartbeatWhatsApp=false;epoch=UUID()
            clock.addTimeInterval(1801)
            w.messages.append(.init(id:"global-disabled-gap",chat:"chat",sender:"fictional",text:"A request received before the global grant resumes",sentByMe:false,time:clock.addingTimeInterval(-60).timeIntervalSince1970*1000))
            // No learner check observes the disabled interval; its source choices
            // and source-specific permission generation remain unchanged.
            heartbeatWhatsApp=true;epoch=UUID()
            let resumed=SourceContextLearningService(container:isolated)
            resumed.check(r)
            check(p.calls == 0 && !resumed.busy,"An unobserved global off/on interval is baselined across learner reopening")
            let persisted=try LocalRecordRepository(container:isolated).decode("paSourceContextLearning",as:SourceContextState.self)!
            check(persisted.scopes.values.first?.learningAccess?.reviewRevision == epoch,"The inherited global grant is retained as an opaque exact access receipt")
            clock.addTimeInterval(1)
            w.messages.append(.init(id:"global-new",chat:"chat",sender:"fictional",text:"A new post-grant project request",sentByMe:false,time:clock.timeIntervalSince1970*1000))
            p.answer="{\"facts\":[]}"
            let unchanged=SourceContextLearningService(container:isolated)
            unchanged.check(r);await wait{unchanged.busy}
            check(p.calls == 1 && unchanged.error == nil,"An unchanged persisted grant does not rebaseline a genuinely new delta after reopen")
            var explicit=w.accessValue;explicit.learnContext=true
            w.accessValue=WhatsAppReadRules.recordingLearningAccess(explicit,previous:w.accessValue)
            let independentlyAllowed=SourceContextLearningService(container:isolated)
            independentlyAllowed.check(r)
            check(r.whatsappReviewLearningRevision == nil && p.calls == 1,"Explicit source-learning permission is independent of the global heartbeat grant")
            heartbeatWhatsApp=false;epoch=UUID();clock.addTimeInterval(1801)
            w.messages.append(.init(id:"explicit-new",chat:"chat",sender:"fictional",text:"A new independently permitted request",sentByMe:false,time:clock.timeIntervalSince1970*1000))
            let explicitReopen=SourceContextLearningService(container:isolated)
            explicitReopen.check(r);await wait{explicitReopen.busy}
            check(p.calls == 2 && explicitReopen.error == nil,"Changing the heartbeat flag does not reset an independent explicit source grant or lose its new deltas")
            var inherited=w.accessValue;inherited.learnContext=false
            w.accessValue=WhatsAppReadRules.recordingLearningAccess(inherited,previous:w.accessValue)
            heartbeatWhatsApp=true;epoch=UUID()
            let late=SourceContextLearningService(container:isolated);late.check(r)
            clock.addTimeInterval(1801)
            w.messages.append(.init(id:"late-global",chat:"chat",sender:"fictional",text:"A request whose grant changes during inference",sentByMe:false,time:clock.timeIntervalSince1970*1000))
            p.onCall={epoch=UUID()}
            late.check(r);await wait{late.busy}
            check(p.calls == 3 && late.error != nil,"A changed inherited grant rejects late output even when effective Boolean access ends unchanged")
            p.onCall=nil;clock.addTimeInterval(1801)
            let paused=SourceContextLearningService(container:isolated);paused.check(r)
            check(p.calls == 3 && !paused.busy,"Grant-change interruption retains the original failed-claim pause across reopen")
        }
        try await capturedSourceMemoryChecks(now:now,check:check)
        try await conversationContextChecks(now:now,check:check)
        print("PASS \(count) actual learning-service checks: injected providers/clock, persistence, foreground priority, exact supplied memory/candidate guards, source/account drift, pauses, explicit recovery; no dashboard, credentials or personal sources.")
    }
    @MainActor private static func conversationContextChecks(now:Date,check:(Bool,String)->Void)async throws {
        let successes:Set<String>=["unrelated save","unrelated Forget","questions disabled","model changed","draft opened","unrelated native edit"]
        let scenarios=["unrelated save","unrelated Forget","questions disabled","model changed","draft opened","unrelated native edit","supplied changed","supplied forgotten","history changed","batch suppressed","memory off/on","learning off/on","context off/on","Stop","external writer"]
        for scenario in scenarios {
            let suite="3PO.conversation-context-fixture."+UUID().uuidString,settings=UserDefaults(suiteName:suite)!
            defer {settings.removePersistentDomain(forName:suite)}
            let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
            let p=FictionalInference(),m=PAMemoryStore(container:container,settings:settings),w=FictionalWhatsApp(),budget=LearningBudget(container:container)
            let a=FictionalAssistant(p,memory:m),learner=MemoryLearningService(container:container,settings:settings)
            var clock=now,nativeWriting=false
            let runtime=LearningRuntime(assistant:a,inference:p,learningBudget:budget,whatsapp:w,now:{clock},activity:{.init()},writing:{nativeWriting},sourceRevision:{0},nativeItems:{_,_ in nil})
            let selected=PAMemory(registration:p.activeID,text:"I study optics report preparation.",kind:.context,provenance:"Fictional human")
            let unrelated=PAMemory(registration:p.activeID,text:"I enjoy woodland walks.",kind:.context,provenance:"Fictional human",sourceTurnID:"another-turn")
            check(m.put(selected) && m.put(unrelated),scenario+" seeds bounded conversation context")
            let firstQuote="I study optics and prepare reports.",newQuote="I prefer a quiet study room."
            a.turns=[.init(id:"learn-target",text:firstQuote+" "+newQuote,created:clock),.init(id:"question-target",text:"I might take the optics workshop next term.",created:clock)]
            let old=PAMemory(registration:p.activeID,text:"Previously studied optics reports",kind:.context,explicit:false,provenance:"Fictional earlier learning",sourceTurnID:"learn-target",evidence:firstQuote)
            check(m.put(old),scenario+" seeds earlier belief")
            var correction=old;correction.id=UUID();correction.text="The earlier optics report plan was corrected."
            check(m.correct(old.id,with:correction),scenario+" preserves exact superseded history")
            let historical=m.records.first{$0.id == old.id}!
            var suppressionTarget=PAMemory(registration:p.activeID,text:"A retired provisional statement",kind:.context,explicit:false,provenance:"Fictional earlier learning",sourceTurnID:"learn-target")
            suppressionTarget.retiredAt=clock
            if scenario == "batch suppressed" {check(m.put(suppressionTarget),scenario+" seeds an unselected turn-suppression target")}
            p.answer=String(decoding:try JSONSerialization.data(withJSONObject:["memories":[["turnID":"learn-target","text":"Prefers a quiet study room","kind":"preference","evidence":newQuote]],"question":["turnID":"question-target","text":"Should I keep the optics workshop as a tentative plan?","evidence":"I might take the optics workshop next term."]]),as:UTF8.self)
            var release:CheckedContinuation<Void,Never>?
            p.hold={await withCheckedContinuation {release=$0}}
            learner.check(runtime)
            for _ in 0..<10_000 {if release != nil {break};await Task.yield()}
            guard let release else {preconditionFailure("Conversation fixture did not reach held inference")}
            var mutation=true
            switch scenario {
            case "unrelated save":mutation=m.put(PAMemory(registration:p.activeID,text:"I like fictional pottery.",kind:.preference,provenance:"Fictional human"))
            case "unrelated Forget":mutation=m.forget(unrelated.id)
            case "questions disabled":learner.questionsEnabled=false
            case "model changed":p.selectedModel="future-model"
            case "draft opened":a.hasDraft=true
            case "unrelated native edit":nativeWriting=true
            case "supplied changed":var edited=selected;edited.text="I now study mirrors instead of optics reports.";mutation=m.put(edited)
            case "supplied forgotten":mutation=m.forget(selected.id)
            case "history changed":var edited=historical;edited.text="The historical source wording was edited.";mutation=m.put(edited)
            case "batch suppressed":mutation=m.forget(suppressionTarget.id)
            case "memory off/on":m.enabled=false;m.enabled=true
            case "learning off/on":m.learningEnabled=false;m.learningEnabled=true
            case "context off/on":a.contextEnabled=false;a.contextRevision=UUID();a.contextEnabled=true;a.contextRevision=UUID()
            case "Stop":learner.cancel()
            case "external writer":mutation=PAMemoryStore(container:container,settings:settings).put(PAMemory(registration:p.activeID,text:"A separate writer saved this garden plan.",kind:.context,provenance:"Fictional human"))
            default:preconditionFailure("Unknown conversation fixture")
            }
            let recordsAfterMutation=m.records
            release.resume()
            for _ in 0..<10_000 {if !learner.busy {break};await Task.yield()}
            check(mutation && !learner.busy && p.calls == 1 && p.requestedModels == ["fictional"],scenario+" completes one bounded held conversation assessment")
            let learned=m.records.first{$0.text == "Prefers a quiet study room"}
            if successes.contains(scenario) {
                check(learner.error == nil && learned?.sourceTurnID == "learn-target",scenario+" saves the supported fact against current state")
                check(recordsAfterMutation.allSatisfy{m.records.contains($0)},scenario+" preserves every concurrent saved record and historical version")
                check((learner.state.questions ?? []).count == (scenario == "questions disabled" ? 0 : 1),scenario+" question policy affects only a new question")
            } else {
                check(learner.error != nil && learned == nil,scenario+" rejects only the conflicting or revoked assessment")
                p.hold=nil;p.onCall=nil;a.hasDraft=false;nativeWriting=false;clock.addTimeInterval(1801)
                let reopened=MemoryLearningService(container:container,settings:settings);reopened.check(runtime)
                check(!reopened.busy && p.calls == 1 && reopened.state.accounts[p.activeID]?.paused == true,scenario+" preserves the attempted failure pause across reopening")
                if scenario == "external writer" {check(PAMemoryStore(container:container,settings:settings).records.contains{$0.text == "A separate writer saved this garden plan."},scenario+" retains the external writer's data under CAS rejection")}
            }
            if scenario != "external writer" {check(PAMemoryStore(container:container,settings:settings).records == m.records,scenario+" preserves canonical storage readback")}
        }
    }
    @MainActor private static func capturedSourceMemoryChecks(now:Date,check:(Bool,String)->Void)async throws {
        let successful:Set<String>=["unrelated save","unrelated forget","selected organisation","held unrelated save","model changed","draft opened","other-kind enabled","other-kind disabled","unrelated native edit"]
        let cases=["unrelated save","unrelated forget","selected organisation","held unrelated save","selected changed","selected forgotten","candidate changed","candidate forgotten","candidate corrected","candidate pinned","held selected changed","controls off/on","source changed","model changed","draft opened","other-kind enabled","other-kind disabled","active-kind disabled","unrelated native edit","Stop"]
        for lane in ["native","whatsapp"] {
            for scenario in cases {
                let suite="3PO.source-dependency-fixture."+UUID().uuidString
                let settings=UserDefaults(suiteName:suite)!
                // The fixture owns a separate defaults suite; no app preferences are used.
                defer {settings.removePersistentDomain(forName:suite)}
                let isolated=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
                let p=FictionalInference(),m=PAMemoryStore(container:isolated,settings:settings),w=FictionalWhatsApp(),b=LearningBudget(container:isolated)
                let a=FictionalAssistant(p,memory:m)
                var clock=now,items:[NativeLearningItem]=[],sourcePermitted=true,nativeWriting=false
                let r=LearningRuntime(assistant:a,inference:p,learningBudget:b,whatsapp:w,now:{clock},activity:{.init()},writing:{nativeWriting},sourceRevision:{0},nativeItems:{kind,_ in kind == .reminder && sourcePermitted ? items : nil})
                let native=NativeSourceLearningService(container:isolated),whatsapp=SourceContextLearningService(container:isolated)
                let selected=PAMemory(registration:p.activeID,text:"I study optics report preparation.",kind:.context,provenance:"Fictional human")
                let unrelated=PAMemory(registration:p.activeID,text:"I enjoy woodland walks.",kind:.preference,provenance:"Fictional human")
                check(m.put(selected) && m.put(unrelated),lane+" seeds independent human context")
                let oldQuote="Prepare the earlier Zephyr diagram",newQuote="Prepare the updated optics report"
                let oldDate=clock.addingTimeInterval(-60)
                let oldEvidence:MemorySourceEvidence
                if lane == "native" {
                    items=[.init(identity:.init(kind:.reminder,accountID:"fixture",containerID:"list",itemID:"dependency-item"),revision:"one",label:"Fictional task",text:oldQuote,date:oldDate,changed:oldDate)]
                    native.setEnabled(true,kind:.reminder,model:r)
                    m.sourceIsPermitted={native.permits($0,model:r)}
                    oldEvidence = .init(identity:items[0].identity,revision:items[0].revision,label:items[0].label,quote:oldQuote,observed:oldDate,sourceDate:oldDate)
                } else {
                    w.messages=[.init(id:"dependency-old",chat:"chat",sender:"fictional",text:oldQuote,sentByMe:false,time:oldDate.timeIntervalSince1970*1000)]
                    m.sourceIsPermitted={sourcePermitted && SourceContextRules.permitted($0,access:r.whatsappLearningAccess,linkedIdentity:"fictional-device",messages:w.messages)}
                    whatsapp.check(r)
                    let prior=SourceContextRules.recent(w.messages,chats:w.chats,allowed:w.accessValue.chats,now:clock)[0]
                    oldEvidence = .init(identity:.init(kind:.whatsapp,accountID:"fictional-device",containerID:"chat",itemID:prior.itemID,linkedIdentity:"fictional-device"),revision:prior.revision,label:prior.chatName,quote:oldQuote,observed:oldDate,sourceDate:oldDate)
                }
                let candidate=PAMemory(registration:p.activeID,text:"A source requested the earlier Zephyr diagram.",kind:.commitment,explicit:false,provenance:"Fictional source",created:oldDate,reviewed:oldDate,evidence:oldQuote,sourceDate:oldDate,certainty:.inferred,durability:.situational,source:oldEvidence,sourceState:.proposed)
                check(m.putSource(candidate,sourceText:oldQuote,expectedRevision:m.revision),lane+" seeds an exact source replacement candidate")
                clock.addTimeInterval(1)
                var receipt=""
                if lane == "native" {
                    items[0].revision="two";items[0].text=newQuote;items[0].changed=clock
                    receipt=NativeLearningRules.receipt(p.activeID,items[0])
                    p.answer="{\"facts\":[{\"itemID\":\"\(items[0].id)\",\"text\":\"The reminder now requests the updated optics report\",\"quote\":\"\(newQuote)\",\"kind\":\"commitment\",\"areas\":[],\"updatesMemoryID\":\"\(candidate.id.uuidString)\",\"state\":\"changed\"}]}"
                } else {
                    let fresh=WhatsAppReadMessage(id:"dependency-new",chat:"chat",sender:"fictional",text:newQuote,sentByMe:false,time:clock.timeIntervalSince1970*1000)
                    w.messages.append(fresh)
                    let target=SourceContextRules.recent([fresh],chats:w.chats,allowed:w.accessValue.chats,now:clock)[0]
                    receipt=SourceContextRules.assessmentKey(registration:p.activeID,linkedIdentity:"fictional-device",message:target)
                    p.answer="{\"facts\":[{\"messageID\":\"\(target.id)\",\"text\":\"A later message requests the updated optics report\",\"quote\":\"\(newQuote)\",\"kind\":\"commitment\",\"areas\":[],\"updatesMemoryID\":\"\(candidate.id.uuidString)\",\"state\":\"changed\"}]}"
                }
                if scenario == "other-kind disabled" {native.setEnabled(true,kind:.mail,model:r)}
                var mutationSucceeded=true,expectedHumanRecords:[PAMemory]=[]
                func mutate() {
                    switch scenario {
                    case "unrelated save","held unrelated save":mutationSucceeded=m.put(PAMemory(registration:p.activeID,text:"I like fictional ceramics.",kind:.preference,provenance:"Fictional human"))
                    case "unrelated forget":mutationSucceeded=m.forget(unrelated.id)
                    case "selected organisation":mutationSucceeded=m.organise(selected.id,value:.init(areas:[.studies],connections:[]),expectedRevision:m.revision)
                    case "selected changed","held selected changed":var edited=selected;edited.text="I no longer study optics report preparation.";mutationSucceeded=m.put(edited)
                    case "selected forgotten":mutationSucceeded=m.forget(selected.id)
                    case "candidate changed":var edited=candidate;edited.text="A human edited the earlier source interpretation.";mutationSucceeded=m.put(edited)
                    case "candidate forgotten":mutationSucceeded=m.forget(candidate.id)
                    case "candidate corrected":mutationSucceeded=m.correct(candidate.id,with:PAMemory(registration:p.activeID,text:"This earlier report is superseded by my correction.",kind:.context,provenance:"Fictional human"))
                    case "candidate pinned":var edited=candidate;edited.organisation = .init(areas:[.studies],connections:[],manual:true);mutationSucceeded=m.put(edited)
                    case "controls off/on":m.learningEnabled=false;m.learningEnabled=true
                    case "model changed":p.selectedModel="future-model"
                    case "unrelated native edit":nativeWriting=true
                    case "draft opened":a.hasDraft=true
                    case "other-kind enabled":native.setEnabled(true,kind:.mail,model:r)
                    case "other-kind disabled":native.setEnabled(false,kind:.mail,model:r)
                    case "active-kind disabled":if lane == "native" {native.setEnabled(false,kind:.reminder,model:r)} else {w.accessValue.enabled=false}
                    case "source changed":if lane == "native" {items[0].revision="three"} else {sourcePermitted=false}
                    case "Stop":if lane == "native" {native.cancel()} else {whatsapp.cancel()}
                    default:preconditionFailure("Unknown fixture scenario")
                    }
                    expectedHumanRecords=m.records.filter{$0.source == nil}
                }
                var release:CheckedContinuation<Void,Never>?
                if scenario.hasPrefix("held ") {p.hold={await withCheckedContinuation {release=$0}}} else {p.onCall=mutate}
                if lane == "native" {native.check(r,kind:.reminder)} else {whatsapp.check(r)}
                if scenario.hasPrefix("held ") {
                    for _ in 0..<10_000 {if release != nil {break};await Task.yield()}
                    guard let release else {preconditionFailure("The held source fixture did not reach inference")}
                    mutate();release.resume()
                }
                for _ in 0..<10_000 {if !native.busy && !whatsapp.busy {break};await Task.yield()}
                let error=lane == "native" ? native.error : whatsapp.error
                check(mutationSucceeded && p.calls == 1 && p.requestedModels == ["fictional"] && !native.busy && !whatsapp.busy,lane+" "+scenario+" executes one real service fixture")
                if let input=p.inputs.first?.first?["content"],let json=try JSONSerialization.jsonObject(with:Data(input.utf8)) as? [String:Any] {
                    let existing=json["existingMemory"] as? [[String:String]] ?? [],candidates=json["updatableSourceMemory"] as? [[String:Any]] ?? []
                    check(existing.contains{$0["text"] == selected.text} && !existing.contains{$0["text"] == candidate.text} && candidates.contains{$0["id"] as? String == candidate.id.uuidString},lane+" "+scenario+" supplies the fact and independent exact candidate")
                } else {check(false,lane+" produces inspectable fictional input")}
                if successful.contains(scenario) {
                    check(error == nil && m.sourceAssessmentDate(receipt) != nil && m.records.first{$0.id == candidate.id}?.supersededBy != nil,lane+" "+scenario+" merges against current memory without losing exact replacement history")
                    check(m.records.filter{$0.source == nil} == expectedHumanRecords,lane+" "+scenario+" preserves every concurrent human save Forget and organisation change exactly")
                } else {
                    check(error != nil && m.sourceAssessmentDate(receipt) == nil && !m.records.contains{$0.supersedes == candidate.id && $0.source != nil},lane+" "+scenario+" rejects late output before saving any assessment receipt")
                    p.onCall=nil;p.hold=nil;clock.addTimeInterval(1801)
                    if lane == "native" {let reopened=NativeSourceLearningService(container:isolated);reopened.check(r,kind:.reminder);check(!reopened.busy && p.calls == 1,lane+" "+scenario+" keeps failed claims paused across reopen")}
                    else {let reopened=SourceContextLearningService(container:isolated);reopened.check(r);check(!reopened.busy && p.calls == 1,lane+" "+scenario+" keeps failed claims paused across reopen")}
                }
            }
        }
    }
}
