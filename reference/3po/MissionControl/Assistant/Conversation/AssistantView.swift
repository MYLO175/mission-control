import SwiftUI
import AppKit

/// Unchanged historical replies do not parse Markdown again for each streamed word.
struct AssistantReplyText:View,Equatable {
    var content:String
    var completed:Bool
    var errors:[String]? = nil
    var body:some View {
        let displayed=PAProse.display(PAIntentFailure.correctedLegacyReply(content,errors:errors))
        Text((try? AttributedString(markdown:displayed,options:.init(interpretedSyntax:.inlineOnlyPreservingWhitespace))) ?? AttributedString(displayed))
            .textSelection(.enabled).lineSpacing(3)
    }
}

/// Source controls keep observing their current services inside this subtree;
/// unchanged completed rows skip rebuilding on another row's streamed text.
private struct AssistantTranscriptRowContent<Content: View>: View, Equatable {
    var key: AssistantTranscriptRenderKey
    var colors: [WorkspaceColorRole: Color]
    var content: () -> Content
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key && lhs.colors == rhs.colors }
    var body: some View { content() }
}

struct AssistantActionApprovalView:View {
    @Bindable var model:DashboardModel
    var conversationID:UUID
    var turn:AssistantTurn
    var body:some View {
        if let proposals=turn.actionApprovals,!proposals.isEmpty {
            let available=proposals.allSatisfy{PAToolSession.approvalAvailable($0,model:model)}
            VStack(alignment:.leading,spacing:10) {
                if available {
                    ForEach(proposals) {proposal in
                        VStack(alignment:.leading,spacing:5) {
                            ForEach(Array(proposal.outline.enumerated()),id:\.offset) {_,line in
                                Label(PAProse.display(line),systemImage:proposal.phase == .completed ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(proposal.phase == .completed ? Color.green : Color.primary)
                            }
                            let notes=proposal.details.filter{$0.hasPrefix("Notes:") || $0.contains(" · Notes:")}
                            ForEach(Array(proposal.details.filter{!notes.contains($0)}.enumerated()),id:\.offset) {_,detail in Text(PAProse.display(detail)).font(.caption).textSelection(.enabled)}
                            if !notes.isEmpty {DisclosureGroup("Notes") {ForEach(Array(notes.enumerated()),id:\.offset) {_,detail in Text(PAProse.display(detail)).textSelection(.enabled)}}.font(.caption)}
                            if let result=proposal.result {Text(PAProse.display(result)).font(.caption).foregroundStyle(proposal.phase == .completed ? Color.green : Color.red)}
                            if proposal.phase == .dismissed {Text("Dismissed").font(.caption).foregroundStyle(.secondary)}
                            if proposal.phase == .attempted {Text(model.assistant.busy && model.assistant.requestTurnID == turn.id ? "Saving…" : "This save needs checking before another attempt.").font(.caption).foregroundStyle(.orange)}
                        }
                    }
                    if proposals.contains(where:{$0.phase == .pending}) && !proposals.contains(where:{$0.phase == .attempted || $0.phase == .failed}) {
                        HStack {
                            Button("Approve actions",systemImage:"checkmark") {model.approveChatActions(conversationID:conversationID,responseID:turn.id)}.buttonStyle(.borderedProminent)
                            Button("Dismiss") {model.dismissChatActions(conversationID:conversationID,responseID:turn.id)}
                        }.disabled(model.assistant.busy || model.chatGPT.busy || !model.heartbeat.deviceAvailable)
                    }
                } else {Text("These proposed actions are unavailable under the current account or source choices.").font(.caption).foregroundStyle(.secondary)}
            }.padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
        }
    }
}

#if DEBUG
struct ChatApprovalPreview:View {
    @Bindable var model:DashboardModel
    @State private var seeded=false
    var body:some View {
        AssistantPanel(model:model,assistant:model.assistant,readingMode:.constant(false))
            .padding(20).frame(minWidth:650,minHeight:600).preferredColorScheme(.dark)
            .task {
                guard !seeded else {return};seeded=true
                do {model.assistant.seedChatApprovalPreview(try await ReviewInboxEvaluation.chatApprovalFixture(model))}
                catch {model.assistant.error=error.localizedDescription}
            }
    }
}
#endif

struct AssistantPanel: View {
    @Environment(\.workspacePalette) private var palette
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    @Binding var readingMode: Bool
    var supportsReadingMode = true
    var widgetID: UUID? = nil
    var configuration: Binding<WidgetConfiguration>? = nil
    @State private var showRename = false
    @State private var composerFocused = false
    private var selectedID: UUID? { assistant.feed?.id }
    private var selectedTopicID:UUID? { nil }
    private var focusAreas:[LifeArea] {
        if configuration == nil { return LifeFocusRules.normalised(assistant.standaloneFocusSelections[model.chatGPT.activeID] ?? []) }
        if let saved=configuration?.wrappedValue.lifeFocusSelections?[model.chatGPT.activeID] { return LifeFocusRules.normalised(saved) }
        let legacy=configuration?.wrappedValue.paTopicSelections?[model.chatGPT.activeID].flatMap(UUID.init(uuidString:))
        return assistant.conversation(legacy)?.notebookAreas ?? []
    }
    private var focusBinding:Binding<[LifeArea]> { Binding(get:{focusAreas},set:{areas in
        guard let configuration else { assistant.standaloneFocusSelections[model.chatGPT.activeID]=areas.map(\.rawValue);return }
        var value=configuration.wrappedValue
        if value.lifeFocusSelections == nil { value.lifeFocusSelections=[:] }
        value.lifeFocusSelections?[model.chatGPT.activeID]=areas.map(\.rawValue);configuration.wrappedValue=value
    }) }
    private var topic: AssistantConversation? { assistant.conversation(selectedTopicID) }
    private var draftKey: UUID? { selectedTopicID ?? selectedID }
    private var sendingHere: Bool { assistant.busy && !assistant.profileBusy(selectedTopicID) && assistant.requestConversationID == selectedID && assistant.requestTopicID == selectedTopicID }
    private var errorHere: Bool { assistant.errorProfileSessionID == nil && (assistant.errorConversationID == nil || (assistant.errorConversationID == selectedID && assistant.errorTopicID == selectedTopicID)) }
    private var draft: Binding<String> {
        Binding(get:{ if let widgetID { return assistant.drafts.text(registration:model.chatGPT.activeID,widget:widgetID,conversation:draftKey) }; return assistant.draft },set:{ text in
            let current=widgetID.map{assistant.drafts.text(registration:model.chatGPT.activeID,widget:$0,conversation:draftKey)} ?? assistant.draft
            guard text != current else {return}
            model.heartbeat.noteDraftEditing()
            if let widgetID { assistant.drafts.set(text,registration:model.chatGPT.activeID,widget:widgetID,conversation:draftKey) } else { assistant.draft = text }
        })
    }
    private func turnVisible(_ turn: AssistantTurn) -> Bool {
        guard let delivery = turn.deliveryID else { return true }
        if delivery.hasPrefix("discovery:") {
            guard let record = model.proactive.record(delivery:delivery,model:model) else { return false }
            return model.proactive.visible(record,model:model)
        }
        if delivery.hasPrefix("learn-question:") {
            guard let record = model.memoryLearning.question(delivery:delivery,registration:model.chatGPT.activeID) else { return false }
            return model.memoryLearning.visible(record,assistant:assistant)
        }
        return true
    }
    private var imageDraftWidget:UUID { widgetID ?? UUID(uuidString:"00000000-0000-0000-0000-000000000001")! }
    private var attachedImages:[ChatImageAttachment] { assistant.drafts.images(registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey) }
    private var composerEmpty:Bool { draft.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && attachedImages.isEmpty }
    @State private var imageError:String?
    @State private var composerHeight:CGFloat=22
    private func pasteImage(_ board:NSPasteboard) {
        let registration=model.chatGPT.activeID,key=draftKey,widget=imageDraftWidget
        var added:[ChatImageAttachment]=[]
        do {
            guard attachedImages.count < ChatImageStore.maxImages else { throw ChatImageFailure.size }
            added=try assistant.images.paste(board,registration:registration)
            guard attachedImages.count+added.count <= ChatImageStore.maxImages else { throw ChatImageFailure.size }
            guard assistant.drafts.setImages(attachedImages+added,registration:registration,widget:widget,conversation:key) else { throw ChatImageFailure.storage }
            imageError=nil;model.heartbeat.noteDraftEditing()
        } catch { added.forEach(assistant.images.discard);imageError=error.localizedDescription }
    }
    private func removeImage(_ image:ChatImageAttachment) {
        if assistant.drafts.setImages(attachedImages.filter{$0.id != image.id},registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey) {
            assistant.images.discard(image);imageError=nil;model.heartbeat.noteDraftEditing()
        }
    }
    private func send() {
        let attachments=attachedImages
        let value = draft.wrappedValue, contextID = selectedTopicID, key = draftKey, registration = model.chatGPT.activeID
        if assistant.send(model:model,topicID:contextID,prompt:value,focusAreas:focusAreas,images:attachments) {
            transcriptScroll.reset()
            if let widgetID { assistant.drafts.set("",registration:registration,widget:widgetID,conversation:key) } else { assistant.draft = "" }
            _ = assistant.drafts.setImages([],registration:registration,widget:imageDraftWidget,conversation:key)
            imageError=nil
            assistant.drafts.flush()
        }
    }
    private func showDraft() {
        assistant.drafts.show(registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey)
        imageError=nil
    }
    @State private var dictation = DictationService()
    @State private var showDictation = false
    @State private var showMemory = false
    @State private var showSupportingFacts = false
    @State private var inspectingContext:PAContextCapture?
    @State private var showProfileSetup = false
    @State private var showBriefing = false
    @State private var visibleTurnLimit=40
    @State private var transcriptCache=AssistantTranscriptProjectionCache()
    @State private var transcriptScroll=AssistantTranscriptScrollState()
    @State private var transcriptUserScrolling=false
    @State private var sourceDiscovery:PADiscovery?
    @State private var reviewingProject:PADiscovery?
    @ViewBuilder private func discoveryActions(_ record: PADiscovery, compact: Bool = false, showsActionEntry:Bool = true) -> some View {
        if compact {
            HStack { if showsActionEntry {reviewDiscoveryButtons(record)} }
            HStack { discoverySourceButtons(record) }
        } else {
            HStack { if showsActionEntry {reviewDiscoveryButtons(record)}; discoverySourceButtons(record) }
        }
    }
    private func discoveryClaim(_ record: PADiscovery) -> NativeCreationClaim? {
        guard let id = UUID(uuidString:record.id) else { return nil }
        return model.nativeCreations.state.claims[record.registration + ":" + id.uuidString]
    }
    @ViewBuilder private func reviewDiscoveryButtons(_ record: PADiscovery) -> some View {
        let source=model.reviewSource(record)
        let current=model.reviewRecords(source)
        let related=current.isEmpty ? [record] : current
        let completed=model.reviewCompletedActions(source)
        let saved=Set(model.reviewWork.jobs(record.registration).filter{$0.source.key == source.key}.flatMap{$0.actions.filter{$0.phase == .saved}.map(\.id)})
        let pending=related.contains{ProactiveReviewRules.hasSuggestedAction($0) && !model.reviewDiscoveryCompleted($0) && $0.reviewState != "approved" && !saved.contains($0.id)}
        if completed > 0 {
            Label("\(completed) action\(completed == 1 ? "" : "s") completed",systemImage:"checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
            Button("View actions") {model.openReviewConversation(related)}
        }
        else if pending {Button("Explore suggested actions") {model.openReviewConversation(related)}}
        if record.reviewState == "pending" || discoveryClaim(record).map({$0.receipt == nil}) == true {Label("Save needs checking",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)}
    }
    private func lastDiscoveryEntries(_ turns:[AssistantTranscriptRow])->[String:UUID] {
        let records=Dictionary(model.proactive.state.records.filter{$0.registration == model.chatGPT.activeID}.map{($0.deliveryID,$0)},uniquingKeysWith:{first,_ in first})
        var last:[String:UUID]=[:]
        for row in turns {
            let turn=row.turn
            if let delivery=turn.deliveryID,let record=records[delivery],record.kind != "update" {last[model.reviewSource(record).key]=turn.id}
        }
        return last
    }
    @ViewBuilder private func discoverySourceButtons(_ record: PADiscovery) -> some View {
        Button(record.sourceKind == "whatsapp" ? "Source message" : "Source email") { if record.sourceKind == "whatsapp" { sourceDiscovery=record } else if let message = model.emailSummaries.highlights(model).first(where:{ $0.0.id == record.mailID })?.0 { model.select(message) } }
        Button("Dismiss") { model.proactive.dismiss(record,model:model) }
    }
    private func inspectContext(_ turn:AssistantTurn) {
        guard var capture=turn.contextCapture else {return}
        if capture.preparationNotes == nil {capture.preparationNotes=(turn.toolErrors ?? []).filter(PAReadPrerequisite.legacyPreparation)}
        inspectingContext=capture
    }
    var body: some View {
        let conversation=assistant.feed
        let page=transcriptCache.value(owner:assistant,revision:assistant.transcriptRevision,registration:model.chatGPT.activeID,feed:conversation,topic:topic,activeTurnID:assistant.requestTurnID,limit:visibleTurnLimit,visible:turnVisible)
        let displayedTurns=page.rows
        let discoveryEntries=lastDiscoveryEntries(displayedTurns)
        VStack(spacing: 8) {
            HStack(spacing:8) {
                Label(assistant.displayName,systemImage:"sparkles").font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength:4)
                if let completed=model.heartbeat.state.accounts[model.chatGPT.activeID]?.assessed {
                    TimelineView(.periodic(from:.now,by:60)) {context in
                        Text("Heartbeat \(completed.formatted(date:Calendar.current.isDate(completed,inSameDayAs:context.date) ? .omitted : .abbreviated,time:.shortened))")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .help("Last completed AI heartbeat: \(completed.formatted(date:.abbreviated,time:.shortened))")
                            .accessibilityLabel("Last completed heartbeat \(completed.formatted(date:.abbreviated,time:.shortened))")
                    }
                }
                LifeFocusPicker(selection:focusBinding).frame(maxWidth:160,alignment:.trailing)
                Menu {
                    Button("Name your PA…") { showRename = true }.disabled(assistant.busy)
                    Button("Context…") { showMemory = true }
                    Button(assistant.setupActive(selectedTopicID) ? "Continue context setup…" : "Set up my PA…") { showProfileSetup=true }.disabled(assistant.busy)
                    Text(assistant.contextEnabled ? "Apple source context enabled" : "Apple source context off")
                } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("PA options").accessibilityLabel("PA options")
                if supportsReadingMode { Button { readingMode.toggle() } label: { Image(systemName:readingMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.help(readingMode ? "Compact chat" : "Expand chat") }
            }.buttonStyle(.borderless).controlSize(.small)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if page.threadCount == 0 {
                            VStack(alignment:.leading,spacing:12) {
                                Text("A little clarity for your day").font(.headline)
                                Text("Ask about what's coming up, find an email, or tell me what needs doing.").font(.callout).foregroundStyle(.secondary)
                                VStack(alignment:.leading,spacing:6) {
                                    ForEach(["What should I focus on today?","What's coming up this week?"],id:\.self) { suggestion in
                                        Button(suggestion) { draft.wrappedValue = suggestion }.controlSize(.small)
                                    }
                                }
                            }.padding(.vertical,12)
                        }
                        if page.totalCount > visibleTurnLimit { Button("Earlier conversation (\(page.totalCount-visibleTurnLimit) messages)") { transcriptScroll.pause();visibleTurnLimit+=40 }.font(.caption).frame(maxWidth:.infinity) }
                        if visibleTurnLimit > 40 { Button("Collapse older conversation") { visibleTurnLimit=40;transcriptScroll.reset();if let id=page.lastVisibleTurn?.id {proxy.scrollTo(id,anchor:.bottom)} }.font(.caption).frame(maxWidth:.infinity) }
                        ForEach(displayedTurns) { row in
                            let turn=row.turn
                            if let separator=row.separator { Text(separator).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth:.infinity).padding(.vertical,6) }
                            let replyingHere = turn.role == "assistant" && sendingHere && assistant.requestTurnID == turn.id
                            AssistantTranscriptRowContent(key:.init(turn:turn,registration:model.chatGPT.activeID,conversationID:selectedID,topicID:selectedTopicID,lastTurnID:page.lastThreadTurnID,replying:replyingHere,toolStatus:replyingHere ? assistant.toolStatus : "",discoveryEntries:discoveryEntries),colors:palette.colors) {
                            HStack(alignment:.top) {
                            if turn.role == "user" { Spacer(minLength:35) }
                            VStack(alignment: .leading, spacing: 5) {
                                if let images=turn.images { ForEach(images) { image in PAImagePreview(image:image,store:assistant.images,registration:model.chatGPT.activeID) } }
                                if turn.content.isEmpty && (turn.images ?? []).isEmpty {
                                    Text(replyingHere ? (assistant.toolStatus.isEmpty ? "Thinking…" : assistant.toolStatus) : "This request didn't complete.").foregroundStyle(.secondary)
                                } else if turn.role == "assistant", turn.deliveryID?.hasPrefix("learned:") == true {
                                    HStack {
                                        Label("Provisional memory",systemImage:"brain").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                        Spacer()
                                        Button("Review supporting facts") { showSupportingFacts = true }.controlSize(.small)
                                    }
                                    Text(PAProse.display(turn.content.components(separatedBy:"\n\n").first ?? turn.content)).lineLimit(3).textSelection(.enabled)
                                    DisclosureGroup("Details") { Text(PAProse.display(turn.content)).textSelection(.enabled) }.font(.caption)
                                } else if turn.role == "assistant" {
                                    AssistantReplyText(content:turn.content,completed:turn.completed,errors:turn.toolErrors).equatable().id(turn.completed)
                                    if let selectedID {AssistantActionApprovalView(model:model,conversationID:selectedID,turn:turn)}
                                } else if !turn.content.isEmpty { Text(turn.content).textSelection(.enabled) }
                                if turn.completed, turn.role == "assistant",turn.id == page.lastThreadTurnID,let choices=turn.choices {
                                    ViewThatFits(in:.horizontal) {
                                        HStack { ForEach(choices,id:\.self) { choice in Button(choice) { draft.wrappedValue=choice; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) } }
                                        VStack(alignment:.leading) { ForEach(choices,id:\.self) { choice in Button(choice) { draft.wrappedValue=choice; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) } }
                                    }.controlSize(.small)
                                }
                                if let notes=turn.memoryNotes,!notes.isEmpty {
                                    DisclosureGroup("Memory tool notes") { ForEach(Array(notes.enumerated()),id:\.offset) { _,note in Text(note).font(.caption).foregroundStyle(.orange).textSelection(.enabled) } }
                                        .font(.caption)
                                }
                                if turn.role == "assistant",turn.completed,case let errors = PAReadPrerequisite.visibleFailures(unresolved:turn.unresolvedToolErrors,history:turn.toolErrors),!errors.isEmpty {
                                    DisclosureGroup("What went wrong") { ForEach(Array(errors.enumerated()),id:\.offset) { _,reason in Text(reason).font(.caption).textSelection(.enabled) } }.font(.caption)
                                }
                                if turn.role == "assistant", assistant.mailSearchTurnID == turn.id,
                                   assistant.mailSearchConversationID == selectedID, assistant.mailSearchTopicID == selectedTopicID,
                                   let lookup = assistant.visibleMailLookup, !lookup.status.isEmpty {
                                    DisclosureGroup("Mail search details") {
                                        VStack(alignment:.leading,spacing:6) {
                                            Text(lookup.status).foregroundStyle(.secondary).textSelection(.enabled)
                                            if !lookup.results.isEmpty {
                                                Menu("Mail sources") { ForEach(lookup.results) { message in Button(message.account + " · " + message.subject) { model.select(message) } } }
                                            }
                                            if lookup.hasUnavailable { Button("Retry unavailable reads") { draft.wrappedValue = "Retry unavailable mail reads."; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
                                            if lookup.hasMore { Button("Continue mail search") { draft.wrappedValue = "Continue the email search."; send() }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
                                        }.controlSize(.small)
                                    }.font(.caption).accessibilityIdentifier("pa-mail-search-details")
                                }
                                if replyingHere && !turn.content.isEmpty {
                                    Text(assistant.toolStatus.isEmpty ? "Thinking…" : assistant.toolStatus).font(.caption).foregroundStyle(.secondary)
                                }
                                if turn.role == "assistant", turn.contextCapture != nil, !replyingHere {
                                    Button { inspectContext(turn) } label: { Label("Sources & searches", systemImage: "magnifyingglass") }
                                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                                        .accessibilityIdentifier("pa-sources-searches-" + turn.id.uuidString)
                                }
                                if turn.deliveryID?.contains(":morning:") == true { Button("Briefing and sources") { showBriefing = true }.controlSize(.small) }
                                if let delivery = turn.deliveryID, let record = model.proactive.record(delivery:delivery,model:model) {
                                    ViewThatFits(in:.horizontal) {
                                    discoveryActions(record,showsActionEntry:discoveryEntries[model.reviewSource(record).key] == turn.id)
                                    VStack(alignment:.leading,spacing:6) { discoveryActions(record,compact:true,showsActionEntry:discoveryEntries[model.reviewSource(record).key] == turn.id) }
                                    }.controlSize(.small)

                                }
                                if let delivery = turn.deliveryID, let question = model.memoryLearning.question(delivery:delivery,registration:model.chatGPT.activeID) {
                                    DisclosureGroup("Why I’m asking") { Text("“" + question.evidence + "”").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.font(.caption)
                                    Button("Dismiss question") { model.memoryLearning.dismiss(question) }.controlSize(.small)
                                }
                                if turn.role == "assistant" && !turn.completed && assistant.requestTurnID != turn.id && !turn.content.isEmpty { Text("Partial response").font(.caption).foregroundStyle(.orange) }
                                if let date = turn.created { Text(date.formatted(date:.omitted,time:.shortened)).font(.caption2).foregroundStyle(.secondary) }
                            }.font(.callout).padding(12).frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children:.contain).accessibilityLabel(turn.role == "user" ? "Your message" : "PA message").background(palette[turn.role == "user" ? .userBubble : .assistantBubble],in:RoundedRectangle(cornerRadius:10))
                            .contextMenu {
                                if turn.contextCapture != nil {
                                    Button("Context details…") {inspectContext(turn)}
                                }
                            }
                            .accessibilityActions {
                                if turn.contextCapture != nil {
                                    Button("Context details") {inspectContext(turn)}
                                }
                            }
                            .accessibilityIdentifier("pa-turn-"+turn.id.uuidString)
                            if turn.role != "user" { Spacer(minLength:20) }
                            }
                            }.equatable().id(turn.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.onScrollGeometryChange(for:Double.self) { geometry in
                    Double(geometry.contentSize.height-geometry.visibleRect.maxY)
                } action: { _, distance in transcriptScroll.update(distanceFromBottom:distance,userScrolling:transcriptUserScrolling) }
                .onScrollPhaseChange { _, phase in transcriptUserScrolling = phase == .tracking || phase == .interacting || phase == .decelerating }
                .onChange(of:page.lastVisibleTurn?.content) { if transcriptScroll.followsBottom,let id=page.lastVisibleTurn?.id {proxy.scrollTo(id,anchor:.bottom)} }
                .onChange(of:page.lastVisibleTurn?.id) { if transcriptScroll.followsBottom,let id=page.lastVisibleTurn?.id {proxy.scrollTo(id,anchor:.bottom)} }
                .onChange(of:selectedID) { visibleTurnLimit=40;transcriptScroll.reset();if let id=page.lastVisibleTurn?.id {proxy.scrollTo(id,anchor:.bottom)} }
                .onChange(of:selectedTopicID) { visibleTurnLimit=40;transcriptScroll.reset();if let id=page.lastVisibleTurn?.id {proxy.scrollTo(id,anchor:.bottom)} }
                .onAppear { if let id=page.lastVisibleTurn?.id {proxy.scrollTo(id,anchor:.bottom)} }
            }
            if model.memoryLearning.canUndoQuestion(model.chatGPT.activeID) { HStack { Text("Question dismissed").font(.caption).foregroundStyle(.secondary); Button("Undo") { model.memoryLearning.undoQuestion(model.chatGPT.activeID) }.controlSize(.small); Spacer() } }
            if let error = assistant.error, errorHere, !model.chatGPT.usagePaused { DisclosureGroup("Request didn’t complete") { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }.font(.caption) }
            if model.chatGPT.usagePaused {
                HStack {
                    Text("Subscription access was rejected; saved sources remain available.").font(.caption).foregroundStyle(.secondary)
                    Button("Check access") { model.chatGPT.testConnection() }.disabled(model.chatGPT.busy || assistant.busy)
                    Button("Usage") { NSWorkspace.shared.open(URL(string:"https://chatgpt.com/settings/usage")!) }
                }
                DisclosureGroup("Access details") { Text(model.chatGPT.message).font(.caption).foregroundStyle(.orange) }.font(.caption)
            }
            if model.chatGPT.busy && !assistant.busy {
                HStack(spacing:6) {
                    ProgressView().controlSize(.mini)
                    Text(model.briefings.busy ? "Preparing today’s brief… You can draft a message while it finishes." : model.memoryLearning.busy ? "Learning conversation context… Start drafting to pause learning." : model.proactive.busy ? "Checking useful suggestions… Start drafting to pause the check." : model.emailSummaries.busy ? "Checking incoming mail… You can draft a message while it finishes." : "Checking your ChatGPT connection…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            let queued=assistant.queue.items.filter { $0.registration == model.chatGPT.activeID && $0.topicID == selectedTopicID && $0.state != .completed }
            if !queued.isEmpty {
                DisclosureGroup("Queued requests (\(queued.count))") {
                    ForEach(queued) { item in
                        HStack(alignment:.top) {
                            VStack(alignment:.leading) { Text(item.prompt.isEmpty ? "Attached image" : item.prompt).lineLimit(2);if let images=item.images,!images.isEmpty { Text("\(images.count) attached image(s)").font(.caption) }; Text(item.state == .interrupted ? "Interrupted — check the transcript before submitting again" : item.state == .running ? "Working…" : item.state == .needsAnswer ? "Waiting for your answer in chat" : "Waiting").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if item.state != .running { Button { assistant.discardQueued(item.id) } label:{ Image(systemName:"xmark") }.buttonStyle(.plain).help("Remove queued request") }
                        }
                    }
                    Button("Continue waiting requests") { assistant.resumeQueue(model:model) }.disabled(assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused)
                }.font(.caption)
            }
            if let queueError=assistant.queue.error { Text(queueError).font(.caption).foregroundStyle(.orange) }
            if let error = assistant.drafts.error, widgetID != nil { Text(error).font(.caption).foregroundStyle(.orange) }
            if let imageError { Text(imageError).font(.caption).foregroundStyle(.orange) }
            if !attachedImages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment:.top,spacing:10) {
                        ForEach(attachedImages) { image in
                            VStack(spacing:3) {
                                PAImagePreview(image:image,store:assistant.images,registration:model.chatGPT.activeID,compact:true)
                                Button { removeImage(image) } label:{ Label("Remove",systemImage:"xmark") }.font(.caption).buttonStyle(.plain).accessibilityLabel("Remove attached image")
                            }
                        }
                    }
                }.frame(height:88)
            }
            HStack {
                Button { showDictation = true } label: { Image(systemName:"mic") }.help("Dictate a message").accessibilityLabel("Dictate a message").disabled(widgetID != nil && !assistant.drafts.writable)
                ZStack(alignment:.topLeading) {
                    if draft.wrappedValue.isEmpty { Text(PAIdentity.placeholder(assistant.displayName)).foregroundStyle(.secondary).padding(.top,2).allowsHitTesting(false) }
                    PAChatComposer(text:draft,focused:Binding(get:{composerFocused},set:{composerFocused=$0}),height:$composerHeight,scope:ChatDraftRules.key(registration:model.chatGPT.activeID,widget:imageDraftWidget,conversation:draftKey),enabled:assistant.drafts.writable,textColor:NSColor(palette[.text]),pasteImage:pasteImage,submit:send)
                        .frame(height:composerHeight)
                }.padding(9).background(palette[.input],in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(palette[.border]))
                Button(sendingHere && composerEmpty ? "Stop" : assistant.busy ? "Queue" : "Send") { if sendingHere && composerEmpty { assistant.cancel() } else { send() } }
                    .frame(width:56)
                    .disabled(!sendingHere && ((widgetID != nil && !assistant.drafts.writable) || composerEmpty || (!model.chatGPT.inferenceVerified || (!assistant.busy && model.chatGPT.busy) || model.chatGPT.usagePaused)))
            }
            if errorHere && assistant.error?.contains("Choose the specific target") == true {
                Picker("Specific action target", selection: $model.assistantActions.selectedTarget) {
                    Text("Choose an item").tag("")
                    ForEach(model.assistantActions.targets) { Text($0.label).tag($0.id) }
                }
            }
        }.onAppear {
            if selectedID == nil { assistant.openPA() }
            showDraft()
        }.task(id:model.assistantFocusRequest?.id) {
            guard let request = model.assistantFocusRequest, request.widgetID == widgetID else { return }
            // Navigation first mounts the selected widget and its saved draft.
            await Task.yield()
            guard !Task.isCancelled, model.assistantFocusRequest == request else { return }
            composerFocused = true
            model.assistantFocusRequest = nil
        }.onDisappear { assistant.drafts.hide(widget:imageDraftWidget); assistant.drafts.flush() }
        .onChange(of:selectedID) { showDraft() }
        .onChange(of:selectedTopicID) { showProfileSetup=false; showDraft() }
        .onChange(of:model.chatGPT.activeID) { assistant.drafts.flush(); assistant.openPA(); showMemory = false; showSupportingFacts = false; inspectingContext=nil;showProfileSetup=false;sourceDiscovery=nil; showDraft() }
        .onChange(of:sourceDiscovery.map{model.proactive.visible($0,model:model)}) { _,available in if available == false {sourceDiscovery=nil} }
        .onChange(of:model.chatGPT.usagePaused) { _, paused in
            if !paused, assistant.error?.contains("subscription_sharing_usage_limit_exceeded") == true { assistant.error = nil }
        }.sheet(item:$reviewingProject) { record in
            LifeItemEditor(model:model,item:.init(registration:record.registration,kind:.space,title:String((record.sourceTitle ?? "New space").prefix(160)),notes:record.evidence),close:{reviewingProject=nil},reviewedSuggestion:record)
        }.sheet(isPresented:$showRename) { PANameEditor(assistant:assistant) }.sheet(isPresented:$showBriefing) { ScrollView { BriefingView(model:model,briefings:model.briefings) }.padding(20).frame(width:650,height:600) }.sheet(isPresented:$showMemory) { ContextPagesView(model:model,registration:model.chatGPT.activeID) }.sheet(isPresented:$showSupportingFacts) { PAMemoryView(memory:assistant.memory,registration:model.chatGPT.activeID,conversationID:selectedTopicID,topicTitle:topic?.title,learning:model.memoryLearning,assistant:assistant,checkContext:{ model.memoryLearning.check(model,manual:true) },organisation:model.lifeOrganisation,organiseContext:{ model.lifeOrganisation.check(model,manual:true,topic:selectedTopicID) },model:model,focusAreas:focusAreas) }.sheet(item:$inspectingContext) { capture in PAContextCaptureView(capture:capture,model:model,registration:model.chatGPT.activeID) }.sheet(item:$sourceDiscovery) { record in DiscoveryEvidenceView(record:record,model:model) }.sheet(isPresented:$showProfileSetup) {
            PAProfileSetupPanel(model:model,assistant:assistant,topicID:selectedTopicID,registration:model.chatGPT.activeID)
        }.sheet(isPresented:$showDictation) {
            DictationView(dictation:dictation) { text in draft.wrappedValue = draft.wrappedValue.isEmpty ? text : draft.wrappedValue + " " + text }
        }.padding(16)
    }
}
struct AssistantSourceSettings: View {
    enum Page { case assistant, background, memory }
    @Bindable var model: DashboardModel
    @Bindable var assistant: AssistantService
    @Environment(\.openWindow) private var openWindow
    var page: Page = .assistant
    @State private var showingActivity=false
    @State private var showingAssistantInstructions=false
    var body: some View {
        Group {
            switch page {
            case .assistant:
                Section("Assistant") {
                    LabeledContent("PA name",value:assistant.displayName)
                    PANameSetting(assistant:assistant)
                    Button("Assistant instructions…") { showingAssistantInstructions=true }
                        .disabled(model.chatGPT.activeID.isEmpty)
                    Text("Read and edit the same guidance in Context → Assistant instructions.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Use source context in assistant replies", isOn: $assistant.contextEnabled)
                    Text("When on, a reply may send the enabled Calendar and Reminders snapshots, recent email headers, saved email summaries, and separately enabled WhatsApp context to OpenAI through your ChatGPT connection. Dashboard refresh itself makes no AI requests.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Assistant source scope") {
                    sourceMenu("Calendar sources", sources: model.calendarData.sources, excluded: $assistant.excludedCalendars)
                    sourceMenu("Reminder lists", sources: model.reminderData.sources, excluded: $assistant.excludedLists)
                    sourceMenu("Mail accounts", sources: model.mailData.accounts.map { SourceOption(id: $0.id, title: $0.title, account: "", writable: false) }, excluded: $assistant.excludedAccounts)
                    Text("These choices control source context sent with assistant requests. Incoming email assessment, WhatsApp access, learning, task suggestions, and morning brief inclusion have separate controls.").font(.caption).foregroundStyle(.secondary)
                    Text("Calendar status: " + model.paOrientationHealth.detail).font(.caption).foregroundStyle(.secondary)
                    if let orientation = model.paOrientation {
                        Text(orientation.coverage(enabledCount:orientation.calendar.events.filter { !assistant.excludedCalendars.contains($0.calendarID) }.count)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Review inbox") {
                    Toggle("Prepare review items",isOn:$model.proactive.enabled)
                    Text(model.proactive.status(model)).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Check suggestions once") { model.proactive.check(model,manual:true) }.disabled(model.chatGPT.busy || model.proactive.busy || model.chatGPT.usagePaused)
                        if model.proactive.canUndo { Button("Undo dismissed suggestion") { model.proactive.undo(model) } }
                    }
                }
            case .background:
                Section("PA heartbeat") {
                    Toggle("Check on things automatically",isOn:$model.heartbeat.enabled)
                    Picker("Check every",selection:$model.heartbeat.intervalMinutes) { Text("15 minutes").tag(15);Text("30 minutes").tag(30);Text("1 hour").tag(60);Text("2 hours").tag(120) }
                    Toggle("Include email assessment",isOn:$model.emailSummaries.enabled)
                    Toggle("Include selected WhatsApp chats",isOn:$model.heartbeat.whatsappEnabled)
                    Toggle("Notify when review items are ready",isOn:$model.heartbeat.notificationsEnabled)
                    let progress=model.heartbeat.state.accounts[model.chatGPT.activeID]
                    LabeledContent("Last source check",value:progress?.checked?.formatted(date:.abbreviated,time:.shortened) ?? "Not recorded")
                    LabeledContent("Last completed heartbeat",value:progress?.assessed?.formatted(date:.abbreviated,time:.shortened) ?? "Not recorded")
                    LabeledContent("Automatic review",value:model.heartbeat.scheduleStatus(model))
                    Text("Each heartbeat analyses collected mail and enabled context, prepares review items and rewrites Today’s brief for the current time. Mail refreshes independently every five minutes. Missed checks catch up once on opening or waking.").font(.caption).foregroundStyle(.secondary)
                    Button("Open Review inbox") {model.workspace.showReviewInbox();openWindow(id:"dashboard")}.disabled(model.workspace.readOnly)
                    Button("View heartbeat history…") {showingActivity=true}
                    Button("Run heartbeat now") { model.heartbeat.check(model,manual:true) }.disabled(model.heartbeat.manualCheckBlockReason(model) != nil).help(model.heartbeat.manualCheckHelp(model))

                }
                Section("Other background work") {
                    Text("Heartbeats process submitted feedback, analyse saved sources, learn and organise useful context, suggest actions and update Today’s brief. A failed stage keeps completed work and tries fresh information next time. Context controls apply. Your queued requests use Continue queue.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Daily AI call limit") {
                    Picker("Daily limit",selection:$model.heartbeat.dailyCallLimit) { Text("Off").tag(0);ForEach([8,16,32,64,96],id:\.self) { Text("\($0) calls").tag($0) } }
                    Text(model.heartbeat.budgetStatus(model.chatGPT.activeID)).font(.caption).foregroundStyle(.secondary)
                    Text("Off by default. Optionally limit daily heartbeat AI calls, including email review, memory learning, suggestions and brief updates. One heartbeat can use several calls. ChatGPT account limits still apply.").font(.caption).foregroundStyle(.secondary)
                }
            case .memory:
                Section("Saved context") {
                    Toggle("Use saved context in PA replies",isOn:Binding(get:{assistant.memory.enabled},set:{assistant.memory.enabled=$0}))
                    Toggle("Allow context learning and maintenance",isOn:Binding(get:{assistant.memory.learningEnabled},set:{assistant.memory.learningEnabled=$0})).disabled(!assistant.memory.enabled)
                    Text("Human memories keep their evidence and correction history. Imported messages are attributed to their source and remain provisional. Forgetting a saved memory prevents the same evidence from being learned again.").font(.caption).foregroundStyle(.secondary)
                }
                Section("WhatsApp context learning") {
                    Text(model.sourceLearning.status(model)).font(.caption).foregroundStyle(.secondary)
                    Text("Selected chats allowed for review may also teach useful context. Receiving messages alone never learns. Manage selected chats in WhatsApp → PA chat access.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Review recent WhatsApp context") { model.sourceLearning.check(model,manual:true) }.disabled(model.chatGPT.busy || model.sourceLearning.busy || model.chatGPT.usagePaused || model.learningRuntime().whatsappLearningAccess.learnContext != true)
                        if model.sourceLearning.busy { Button("Stop learning") { model.sourceLearning.cancel() } }
                    }
                    if let error=model.sourceLearning.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
                Section("Source memory") {
                    Text("Sources allowed for review can also teach memory during a heartbeat. Refresh only collects data. Newly included sources baseline existing content; Review once can assess a small existing batch. Facts retain exact evidence and remain editable. Turn off Allow context learning and maintenance above to pause learning.").font(.caption).foregroundStyle(.secondary)
                    ForEach(NativeLearningRules.kinds,id:\.rawValue) { kind in
                        VStack(alignment:.leading,spacing:6) {
                            if model.learningRuntime().permitsReviewLearning(kind) {
                                Label(NativeSourceLearningService.title(kind)+" · included through review access",systemImage:"checkmark.circle")
                            } else {
                                Toggle("Learn from " + NativeSourceLearningService.title(kind),isOn:Binding(get:{model.nativeSourceLearning.enabled(kind,registration:model.chatGPT.activeID)},set:{model.nativeSourceLearning.setEnabled($0,kind:kind,model:model)}))
                            }
                            Text(model.nativeSourceLearning.status(kind,model:model)).font(.caption).foregroundStyle(.secondary)
                            Text(NativeSourceLearningService.coverage(kind)).font(.caption).foregroundStyle(.secondary)
                            Button("Review " + NativeSourceLearningService.title(kind) + " once") { model.nativeSourceLearning.check(model,kind:kind,manual:true) }
                                .disabled(!model.nativeSourceLearning.permittedKind(kind,model:model.learningRuntime()) || !assistant.memory.enabled || !assistant.memory.learningEnabled || !assistant.contextEnabled || model.chatGPT.busy || model.nativeSourceLearning.busy || model.sourceLearning.busy || model.chatGPT.usagePaused)
                        }
                    }
                    Text("At most 8 items and 4 facts per pass. Conversation, source learning and organisation share 4 automatic passes/day with a 30-minute gap. Review once is an explicit extra assessment, not a permission to edit Apple apps.").font(.caption).foregroundStyle(.secondary)
                    if model.nativeSourceLearning.busy { Button("Stop source learning") { model.nativeSourceLearning.cancel() } }
                    if let error=model.nativeSourceLearning.error { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
        }.sheet(isPresented:$showingActivity) {BackgroundActivityView(model:model)}
            .sheet(isPresented:$showingAssistantInstructions) {ContextPagesView(model:model,registration:model.chatGPT.activeID,feature:.assistant)}
            .onChange(of:model.chatGPT.activeID) {showingAssistantInstructions=false}
    }
    private func sourceMenu(_ title: String, sources: [SourceOption], excluded: Binding<Set<String>>) -> some View {
        Menu(title) {
            ForEach(sources) { source in
                Toggle(source.label, isOn: Binding(get: { !excluded.wrappedValue.contains(source.id) }, set: { enabled in if enabled { excluded.wrappedValue.remove(source.id) } else { excluded.wrappedValue.insert(source.id) } }))
            }
        }
    }
}

struct BackgroundActivityView:View {
    @Bindable var model:DashboardModel
    @Environment(\.dismiss) private var dismiss
    private var registration:String {model.chatGPT.activeID}
    private var runs:[PAReviewRun] {Array((model.heartbeat.state.accounts[registration]?.reviews ?? []).reversed())}
    private var retrying:Bool {model.heartbeat.state.accounts[registration]?.retryReason == "failure"}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("Heartbeat history").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") {dismiss()}.keyboardShortcut(.cancelAction)
            }
            HStack {
                Label(model.heartbeat.scheduleStatus(model),systemImage:"waveform.path.ecg")
                    .font(.callout).foregroundStyle(retrying ? .orange : .secondary)
                Spacer()
                Button("Run now") {model.heartbeat.check(model,manual:true)}
                    .disabled(model.heartbeat.manualCheckBlockReason(model) != nil)
                    .help(model.heartbeat.manualCheckHelp(model))
            }
            if retrying {Text("The last heartbeat did not finish. Saved work is kept; the next check runs automatically.").font(.caption).foregroundStyle(.secondary)}
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    if runs.isEmpty {Text("Heartbeats will appear here as they run.").foregroundStyle(.secondary).padding(.vertical,24)}
                    ForEach(runs) {run in
                        let running=model.heartbeat.reviewInProgress(run,registration:registration)
                        DisclosureGroup {
                            VStack(alignment:.leading,spacing:10) {
                                if let steps=run.steps {
                                    ForEach(steps) {step in
                                        VStack(alignment:.leading,spacing:3) {
                                            HStack {Text(step.title);Spacer();Text(step.status == "running" && !running ? "Interrupted" : step.label).foregroundStyle(step.status == "failed" ? .orange : .secondary)}
                                            if let detail=step.detail {Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}
                                        }
                                    }
                                }
                                Text(running ? model.heartbeat.statusFor(registration) : run.failure ?? run.detail)
                                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                HStack {
                                    Text("\(run.calls) AI call\(run.calls == 1 ? "" : "s")")
                                    Spacer()
                                    Text(run.manual ? "Run manually" : "Scheduled")
                                    if let finished=run.finished {Text("· \(max(0,Int(finished.timeIntervalSince(run.started))))s")}
                                }.font(.caption).foregroundStyle(.secondary)
                                if run.handled > 0 {Text("\(run.handled) items linked to existing plans or completed reminders").font(.caption).foregroundStyle(.secondary)}
                            }.padding(.top,10)
                        } label: {
                            VStack(alignment:.leading,spacing:5) {
                                HStack {
                                    Text(run.started.formatted(date:.abbreviated,time:.shortened)).font(.callout.weight(.semibold))
                                    Spacer()
                                    Text(run.outcome(running:running)).font(.caption.weight(.medium))
                                        .foregroundStyle(["paused","failed","interrupted"].contains(run.phase) ? .orange : run.briefUpdated == true ? .green : .secondary)
                                }
                                Text(running ? model.heartbeat.statusFor(registration) : run.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(12).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                    }
                    DisclosureGroup("Source status & usage") {
                        VStack(alignment:.leading,spacing:8) {
                            Text(model.heartbeat.budgetStatus(registration))
                            if let error=model.emailSummaries.error {Text("Email: "+error).foregroundStyle(.orange)}
                            if let error=model.proactive.error {Text("Suggestions: "+error).foregroundStyle(.orange)}
                            if let error=model.mailHealth.error {Text("Mail: "+error).foregroundStyle(.orange)}
                            Text(model.heartbeat.mailReviewStatus(model))
                            Text(model.emailSummaries.coverage(model))
                            Text("Calendar: "+model.paOrientationHealth.detail)
                            Text("Reminders: "+model.reminderHealth.detail)
                            Text("Completion evidence: "+model.completedReminderHealth.detail)
                        }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top,8)
                    }.padding(12)
                    ReviewHistoryView(model:model)
                    Text("Last 20 runs for this account. Opening history uses no AI. 3PO must be open and the Mac awake.").font(.caption).foregroundStyle(.secondary).padding(.horizontal,12)
                }
            }
        }.padding(24).frame(width:650,height:650)
            .onAppear {
                #if DEBUG
                model.heartbeat.seedHistoryPreview(registration,validationDetail:ReviewInboxEvaluation.dateDiagnosticPreview())
                #endif
            }
    }
}
