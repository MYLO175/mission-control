import Foundation
import EventKit

extension MailLookup: AssistantMailCursor { }

extension AssistantService {
    @discardableResult func beginSetup(model: DashboardModel, topic: UUID?) -> Bool {
        beginSetup(runtime: model.assistantRuntime(), topic: topic)
    }
    @discardableResult func sendProfile(model: DashboardModel, topic: UUID?, answer: String, control: Bool = false) -> Bool {
        sendProfile(runtime: model.assistantRuntime(), topic: topic, answer: answer, control: control)
    }
    @discardableResult func send(model: DashboardModel, topicID: UUID?, prompt: String, focusAreas: [LifeArea]? = nil, images: [ChatImageAttachment] = []) -> Bool {
        // An active assistant already owns the serial queue, including Review.
        // A running background provider call retains the existing disabled-Send
        // contract: keep the draft rather than cancel it before a send can start.
        guard busy || !connection.busy else {return false}
        if !busy,foregroundInputValid(prompt,images:images),topicID == nil || topics.contains(where:{$0.id == topicID}) {model.foregroundSendStarted()}
        return send(runtime: model.assistantRuntime(), topicID: topicID, prompt: prompt, focusAreas: focusAreas, images: images)
    }
    private func foregroundInputValid(_ prompt:String,images attachments:[ChatImageAttachment]=[])->Bool {
        (!prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !attachments.isEmpty) && ConversationRules.acceptsPrompt(prompt) &&
        !connection.usagePaused && connection.hasSession && connection.inferenceVerified && (try? images.validate(attachments,registration:connection.activeID)) != nil
    }
    func send(model: DashboardModel) {
        guard busy || !connection.busy else {return}
        if !busy,foregroundInputValid(draft) {model.foregroundSendStarted()}
        send(runtime: model.assistantRuntime())
    }
    func send(context: String?, model: DashboardModel) {
        guard busy || !connection.busy else {return}
        if !busy,foregroundInputValid(draft) {model.foregroundSendStarted()}
        send(context: context, runtime: model.assistantRuntime())
    }
    func resumeQueue(model: DashboardModel) { resumeQueue(runtime: model.assistantRuntime()) }
    func sourceSafeHistory(_ model: DashboardModel, feed: AssistantConversation, topic: AssistantConversation?) -> [AssistantTurn] {
        sourceSafeHistory(runtime: model.assistantRuntime(), feed: feed, topic: topic)
    }
    func localDiscoveryReview(_ prompt: String, model: DashboardModel, topicID: UUID?) -> PADiscovery? {
        guard let feed else { return nil }
        let turns = ConversationRules.thread(feed:feed,topic:conversation(topicID)).filter { $0.profileSessionID == nil }
        let records = model.proactive.currentAdvice(model).filter { $0.registration == connection.activeID && UUID(uuidString:$0.id) != nil }
        return ProactiveReviewRules.reference(prompt,turns:turns,records:records)
    }
    func snapshot(_ model: DashboardModel) -> String? {
        guard contextEnabled else { return nil }
        let events = model.paOrientation?.events(excluding:excludedCalendars) ?? model.calendarData.events.filter { !excludedCalendars.contains($0.calendarID) }
        let eventCount = model.paOrientation?.calendar.events.filter { !excludedCalendars.contains($0.calendarID) }.count ?? events.count
        let coverage = model.paOrientation?.coverage(limit:200,enabledCount:eventCount) ?? "Fallback: dashboard selected date and following seven days, first 60 events. The PA's 90-day calendar orientation is unavailable."
        let eventLimit = model.paOrientation == nil ? 60 : 200
        let tasks = model.reminderData.reminders.filter { !excludedLists.contains($0.listID) }
        let emails = model.mailData.messages.filter { !excludedAccounts.contains($0.accountID) }.sorted { $0.received > $1.received }
        let summaries = model.emailSummaries.highlights(model).filter{!model.acknowledgedEmail($0.0,$0.1)}.map { message,summary -> [String:Any] in
            ["id":message.id,"account":message.account,"subject":message.subject,"received":message.received.ISO8601Format(),"summary":summary.summary,"attention":EmailHighlightRules.needsAction(summary,replied:message.replied),"replied":message.replied,"assessmentCategory":EmailHighlightRules.category(summary,replied:message.replied),"reason":summary.reason,"evidence":summary.evidence,"followUpDate":summary.followUpDate ?? "none","summarisedAt":summary.created.ISO8601Format()]
        }
        let value: [String:Any] = [
            "now":Date.now.ISO8601Format(), "timezone":TimeZone.current.identifier, "localWeather":model.weather.context(),
            "calendarStatus":model.paOrientation == nil ? model.calendarHealth.detail : model.paOrientationHealth.detail, "calendarCoverage":coverage, "calendarCount":eventCount,
            "events":events.prefix(eventLimit).map { ["id":$0.id, "title":String($0.title.prefix(500)), "start":$0.allDay ? DateRules.localDate($0.start) : DateRules.localTimestamp($0.start), "end":$0.allDay ? DateRules.localDate(PAToolProtocol.exclusiveAllDayEnd($0.end)) : DateRules.localTimestamp($0.end), "allDay":$0.allDay, "source":$0.sourceLabel, "location":String($0.location.prefix(500))] as [String:Any] },
            "reminderStatus":model.reminderHealth.detail, "reminderCount":tasks.count,
            "reminders":tasks.prefix(80).map { ["id":$0.id, "title":String($0.title.prefix(500)), "due":DateRules.reminderDue($0), "hasTime":$0.hasTime, "source":$0.sourceLabel] as [String:Any] },
            "mailStatus":model.mailHealth.detail, "mailCoverage":model.mailCoverage, "mailHeaderCount":emails.count,
            "recentEmailHeaders":emails.prefix(20).map { ["id":$0.id, "sender":String($0.sender.prefix(500)), "subject":String($0.subject.prefix(500)), "received":$0.received.ISO8601Format(), "account":$0.account] },
            "reviewAcknowledgements":(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(model.reviewAcknowledgements()))) ?? [],
            "resolvedEmailRequests":model.emailSummaries.resolutionContext(model),
            "savedEmailSummaries":Array(summaries.prefix(20)), "emailSummaryCoverage":model.emailSummaries.coverage(model),
            "limits":"At most \(eventLimit) events, 80 reminders, 20 recent email headers and 20 saved summaries. No full email bodies. Excluded sources are omitted."
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
    /// Small initial orientation; exact item details are read through the same existing PA tools.
    func foregroundSnapshot(_ model:DashboardModel)->String? {
        guard contextEnabled else {return nil}
        let calendar=model.paOrientation?.calendar ?? model.calendarData
        let calendars=calendar.sources.filter{!excludedCalendars.contains($0.id)}
        let lists=model.reminderData.sources.filter{!excludedLists.contains($0.id)}
        let accounts=model.mailData.accounts.filter{!excludedAccounts.contains($0.id)}
        let now=Date.now,calendarCount=calendar.events.filter{!excludedCalendars.contains($0.calendarID)}.count
        let calendarCoverage:String
        if let orientation=model.paOrientation {
            let stale=Calendar.current.isDate(orientation.refreshed,inSameDayAs:now) ? "" : "Cached from an earlier day. "
            calendarCoverage=stale+"Calendar cache window "+DateRules.localDate(orientation.start)+" to "+DateRules.localDate(orientation.end)+" (end exclusive); \(calendarCount) enabled cached events. Refreshed "+DateRules.localTimestamp(orientation.refreshed)+". Event details are omitted; use read_calendar for the requested dates."
        } else {
            calendarCoverage="Cached dashboard snapshot; \(calendarCount) enabled cached events. The collected window is unavailable here. Event details are omitted; use read_calendar for the requested dates."
        }
        let acknowledgements=model.reviewAcknowledgements()
        let value:[String:Any] = [
            "now":DateRules.localTimestamp(now),"timezone":TimeZone.current.identifier,"localWeather":model.weather.context(),
            "calendarStatus":model.paOrientation == nil ? model.calendarHealth.detail : model.paOrientationHealth.detail,
            "calendarCount":calendarCount,
            "calendarCoverage":calendarCoverage,
            "calendarSources":calendars.prefix(60).map{["id":$0.id,"name":$0.label,"writable":$0.writable] as [String:Any]},
            "reminderStatus":model.reminderHealth.detail,"reminderCount":model.reminderData.reminders.filter{!excludedLists.contains($0.listID)}.count,
            "reminderSources":lists.prefix(60).map{["id":$0.id,"name":$0.label,"writable":$0.writable] as [String:Any]},
            "mailStatus":model.mailHealth.detail,"mailCoverage":model.mailCoverage,"mailHeaderCount":model.mailData.messages.filter{!excludedAccounts.contains($0.accountID)}.count,
            "mailAccounts":accounts.prefix(30).map{["id":$0.id,"name":$0.title]},
            "reviewAcknowledgements":(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(acknowledgements))) ?? [],
            "whatsappContextSupplied":PAToolSession.attentionUsesWhatsApp(model,acknowledgements:acknowledgements),
            "resolvedEmailRequests":model.emailSummaries.resolutionContext(model),
            "coverage":"Initial source orientation only. Source IDs/names above are metadata, not issued mutation destinations or item IDs. Use read_calendar/read_reminders for actual relevant items and fresh writable sources, read_attention for saved brief/assessments/suggestions, and selective search_mail/read_email for emails. Never infer an empty source from omitted details. All normal source permissions and write checks still apply."
        ]
        guard let data=try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else {return nil}
        return String(decoding:data,as:UTF8.self)
    }
}

extension DashboardModel {
    /// A local permission fingerprint for inspecting historical search terms.
    /// No source bodies, inference or evidence reconstruction is performed here.
    func assistantLookupAccess(_ tool: String) -> String? {
        guard AssistantLookupTrace.names.contains(tool) else { return nil }
        var value: [String: Any] = ["registration": chatGPT.activeID, "storage": reviewStorageIdentity]
        func whatsappAccess() -> [String: Any] {
            let access = whatsapp.access(for: chatGPT.activeID)
            return ["enabled": access.enabled, "chats": access.chats.sorted(), "identity": whatsapp.linkedIdentity]
        }
        switch tool {
        case "read_memory", "read_life_notebook", "read_context_page":
            guard assistant.memory.enabled else { return nil }
            value["memory"] = true
            value["calendars"] = assistant.excludedCalendars.sorted(); value["lists"] = assistant.excludedLists.sorted(); value["mail"] = assistant.excludedAccounts.sorted()
            value["sourceEnabled"] = assistant.contextEnabled
            value["whatsapp"] = whatsappAccess()
            let learning = learningRuntime()
            value["nativeLearningAccess"] = Dictionary(uniqueKeysWithValues: [MemorySourceKind.calendar, .reminder, .mail].map { ($0.rawValue, nativeSourceLearning.permittedKind($0, model: learning)) })
            value["emailReviewAccess"] = emailSummaries.enabled
            value["whatsappLearningAccess"] = learning.whatsappLearningAccess.learnContext == true
            value["calendarAuthorisation"] = EKEventStore.authorizationStatus(for: .event).rawValue
            value["reminderAuthorisation"] = EKEventStore.authorizationStatus(for: .reminder).rawValue
        case "read_life_items", "read_assistant_context": break
        case "search_mail", "continue_mail", "read_email":
            guard assistant.contextEnabled else { return nil }
            value["excluded"] = assistant.excludedAccounts.sorted(); value["accounts"] = mailData.accounts.map(\.id).sorted()
        case "read_calendar", "read_reminders", "read_item_details":
            guard assistant.contextEnabled else { return nil }
            value["calendars"] = assistant.excludedCalendars.sorted(); value["lists"] = assistant.excludedLists.sorted()
            value["calendarSources"] = calendarData.sources.map(\.id).sorted(); value["reminderSources"] = reminderData.sources.map(\.id).sorted()
            value["calendarAuthorisation"] = EKEventStore.authorizationStatus(for: .event).rawValue
            value["reminderAuthorisation"] = EKEventStore.authorizationStatus(for: .reminder).rawValue
        case "search_whatsapp", "list_whatsapp_chats":
            guard assistant.contextEnabled, whatsapp.access(for: chatGPT.activeID).enabled else { return nil }
            value["whatsapp"] = whatsappAccess()
        case "read_weather":
            guard assistant.contextEnabled, weather.enabled, weather.allowed else { return nil }
            value["weather"] = true
        default:
            guard assistant.contextEnabled else { return nil }
            value["sourceControls"] = assistant.contextEnabled
            value["mail"] = assistant.excludedAccounts.sorted(); value["calendars"] = assistant.excludedCalendars.sorted(); value["lists"] = assistant.excludedLists.sorted()
            value["whatsapp"] = whatsappAccess()
        }
        return ContextKnowledgeRules.fingerprint(ContextKnowledgeRules.json(value))
    }
    /// Only a submitted foreground instruction takes priority. Editing or
    /// revealing a saved draft never calls this handover.
    func foregroundSendStarted(interruptReview:Bool=true) {
        memoryLearning.cancel();sourceLearning.cancel();nativeSourceLearning.cancel();memoryMaintenance.cancel();lifeOrganisation.cancel()
        proactive.cancel();emailSummaries.cancelReviewFeedback();heartbeat.userStartedTyping()
        if interruptReview {reviewWork.interruptForForeground(chatGPT.activeID)}
    }
    /// Desktop composition only. A foreground turn consumes snapshots and typed
    /// tools; it never receives the dashboard itself.
    func assistantRuntime() -> AssistantRuntime {
        let capturedContainer = container
        var runtime=AssistantRuntime(clock: { .now }, state: { [weak self] in
            guard let self else { return nil }
            return nativeLearningValidation.withSnapshot { [self] in
                AssistantRuntimeState(attentionPreferencesReadable: self.assistant.memory.reviewPreferenceMigrationReadable,
                         resolvedRequests: self.emailSummaries.resolutionContext(self,limit:Int.max),
                         whatsappScope: self.whatsapp.scope(for: self.chatGPT.activeID,purpose:.conversation), weatherScope: self.weather.scope,weatherSupplied:self.weather.enabled && self.weather.allowed && self.weather.forecast?.usable() == true)
            }
        }, sourceSnapshot: { [weak self] in
            guard let self else { return nil }
            return assistant.foregroundSnapshot(self)
        }, deliveryAvailable: { [weak self] turn in
            guard let self else { return false }
            guard let delivery = turn.deliveryID else { return true }
            if delivery.hasPrefix("discovery:") {
                guard let record = proactive.record(delivery: delivery, model: self), proactive.visible(record, model: self) else { return false }
                let reviewText=(record.sourceTitle.map{$0+"\n"} ?? "")+record.message
                guard turn.content == record.message || turn.content == reviewText else {return false}
            } else if delivery.hasPrefix("learn-question:") {
                guard let record = memoryLearning.question(delivery: delivery, registration: chatGPT.activeID), memoryLearning.visible(record, assistant: assistant) else { return false }
            } else if delivery.contains(":morning:"), !briefings.allowsChatDelivery(delivery, content: turn.content, model: self) { return false }
            return true
        }, tools: { [self] request in
            PAToolSession(model: self, human: request.human, humanContext: request.humanContext,
                          topicID: request.topicID, turnID: request.turnID, mail: request.mail as? MailLookup,
                          history: request.history, focusAreas: request.focusAreas,inferenceModel:request.inferenceModel)
        }, afterTurn: { [weak self] in
            guard let self else { return }
            if !reviewWork.busy {projectPlacement.check(self)}
        },started:{ [weak self] in self?.assistantActivityStarted($0) },working:{ [weak self] in self?.assistantActivityStarted($0) },finished:{ [weak self] in self?.assistantActivityFinished($0) })
        runtime.streamingState = { [weak self] in
            guard let self else { return nil }
            return .init(storageCurrent: self.container === capturedContainer,
                         whatsappScope: self.whatsapp.scope(for: self.chatGPT.activeID, purpose: .conversation), weatherScope: self.weather.scope)
        }
        runtime.lookupAccess = { [weak self] in self?.assistantLookupAccess($0) }
        runtime.withValidation={ [weak self] decision in
            guard let self else {return false}
            return self.nativeLearningValidation.withSnapshot(decision)
        }
        runtime.contextPages = { [weak self] registration, query, topic, includeTopics, everyday in
            guard let self else { return .init() }
            let pages = self.captureContextPages(registration: registration, query: query, topic: topic, includeTopics: includeTopics, everyday: everyday)
            guard !everyday else { return pages }
            return pages.including(self.captureContextPages(registration: registration, query: nil, topic: topic, includeTopics: includeTopics, pageID: "instructions:review"), as: "reviewGuidance")
        }
        runtime.profileContextPages = { [weak self] registration, topic in
            self?.captureContextPages(registration: registration, query: nil, topic: topic, includeTopics: false, everyday: true, purpose: .setup) ?? .init()
        }
        runtime.pageKnowledgeAvailable = { [weak self] registration, versions in
            guard let self else { return false }
            return self.contextKnowledgeAvailable(registration: registration, versions: versions)
        }
        runtime.pageKnowledgeAvailability = { [weak self] registration, captures in
            guard let self else { return captures.map { _ in false } }
            return self.withContextPageAvailability(registration: registration, captures: captures) { available in
                captures.map { available($0) }
            }
        }
        runtime.ownedPageKnowledgeAvailable = { [weak self] registration, versions, ignored in
            self?.contextKnowledgeAvailable(registration: registration, versions: versions, ignoring: ignored) ?? false
        }
        runtime.ownedContextReferences = { [weak self] registration, keys in
            self?.contextReferencesForOwnedChanges(registration: registration, keys: keys) ?? keys
        }
        runtime.memoryMutationReferences = { [weak self] registration, call in
            self?.contextReferencesForMemoryMutation(registration: registration, call: call) ?? []
        }
        runtime.approvalAvailable={ [weak self] proposal in
            guard let self else {return false}
            return PAToolSession.approvalAvailable(proposal,model:self)
        }
        runtime.approveAction={ [weak self] proposal,valid in
            guard let self else {throw ActionFailure.message("The captured workspace is unavailable.")}
            return try await PAToolSession.performApproval(proposal,model:self,valid:valid)
        }
        return runtime
    }
    func approveChatActions(conversationID:UUID,responseID:UUID) {
        guard !assistant.busy,!chatGPT.busy,heartbeat.deviceAvailable else {return}
        foregroundSendStarted()
        var runtime=assistantRuntime()
        if let job=reviewWork.jobs(chatGPT.activeID,conversation:conversationID).first(where:{$0.responseTurnID == responseID && $0.mode == .conversation && $0.phase == .needsAnswer}) {
            let eventID="review:"+job.id.uuidString+":"+responseID.uuidString
            runtime.started={ [weak self] outcome in
                guard let self else {return}
                _=aiActivity.upsert(.init(id:eventID,registration:job.scope.registration,kind:.review,state:.running,title:job.source.title,message:"Saving approved actions…",created:job.created,destination:.review(targetID:conversationID.uuidString)))
            }
            runtime.finished={ [weak self] outcome in
                guard let self else {return}
                if reviewWork.finishChatApproval(jobID:job.id,registration:job.scope.registration,conversationID:conversationID,responseID:responseID,phase:ReviewWorkPhase(rawValue:outcome.phase) ?? .failed,message:outcome.message,error:outcome.errors.first,confirmedActions:outcome.confirmedActions),let updated=reviewWork.job(job.id) {reviewJobChanged(updated)}
            }
        }
        _=assistant.approveActions(runtime:runtime,conversationID:conversationID,responseID:responseID)
    }
    func dismissChatActions(conversationID:UUID,responseID:UUID) {
        guard assistant.dismissActions(conversationID:conversationID,responseID:responseID) else {return}
        _=aiActivity.acknowledge("action:"+responseID.uuidString,registration:chatGPT.activeID)
        for job in reviewWork.jobs(chatGPT.activeID,conversation:conversationID) where job.responseTurnID == responseID && job.mode == .conversation && job.phase == .needsAnswer {
            if reviewWork.finishChatApproval(jobID:job.id,registration:job.scope.registration,conversationID:conversationID,responseID:responseID,phase:.stopped,message:"Proposed actions dismissed",error:nil,confirmedActions:0),let updated=reviewWork.job(job.id) {reviewJobChanged(updated)}
            _=aiActivity.acknowledge("review:"+job.id.uuidString+":"+responseID.uuidString,registration:chatGPT.activeID)
        }
    }
}
