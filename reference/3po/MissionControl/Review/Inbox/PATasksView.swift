import SwiftUI
import AppKit

struct ReviewInboxEmailCard:Identifiable {
    var message:MailMessage
    var summary:EmailSummary
    var discoveries:[PADiscovery]
    var handling:EmailHandling?
    var needsReview:Bool
    var id:String {message.id}
}
struct ReviewInboxProjection {
    var questions:[BriefingQuestion]
    var learningQuestions:[PALearningQuestion]
    var discoveries:[PADiscovery]
    var emails:[(MailMessage,EmailSummary)]
    var highlights:[(MailMessage,EmailSummary)]
    var emailCards:[ReviewInboxEmailCard]
    var standaloneDiscoveries:[PADiscovery]
    var handled:[(MailMessage,EmailSummary,EmailHandling)]
    var resolved:[(MailMessage,EmailSummary,EmailResolution)]
    var pending:[PAQueuedRequest]
    var pendingCount:Int
    var contextQuestions: [ContextProjectQuestion] = []
}
extension DashboardModel {
    func reviewCreationClaim(_ item:PADiscovery)->NativeCreationClaim? {
        guard nativeCreations.readable,let id=UUID(uuidString:item.id) else {return nil}
        return nativeCreations.state.claims[item.registration+":"+id.uuidString]
    }
    func reviewDiscoveryCompleted(_ item:PADiscovery)->Bool {
        if item.nativeTarget != nil {return item.reviewState == "approved"}
        if ["project","projectTask"].contains(item.kind) {return !assistant.projects.readOnly && assistant.projects.receipt("project-suggestion:"+item.id,registration:item.registration) != nil}
        return reviewCreationClaim(item)?.receipt != nil
    }
    var reviewInbox:ReviewInboxProjection {preparedReview.value(self)}
    var reviewInboxPendingCount:Int {preparedReview.value(self).pendingCount}

}
struct ReviewInboxBadge:View {
    var count:Int
    var body:some View {
        if count > 0 {Text(count > 99 ? "99+" : String(count)).font(.system(size:10,weight:.semibold)).monospacedDigit().foregroundStyle(.white).padding(.horizontal,5).frame(minWidth:17,minHeight:17).background(Color.red,in:Capsule()).accessibilityLabel("\(count) items need review")}
    }
}
struct PATasksView: View {
    @Bindable var model: DashboardModel
    @AppStorage("settingsSelectedPage") private var settingsPage="General"
    @Environment(\.openSettings) private var openSettings
    @State private var refiningSuggestion:PADiscovery?
    @State private var refinement=""
    @State private var reviewingProject:PADiscovery?
    @State private var editing: EmailSummary?
    @State private var draft=""
    @State private var copied=false
    @State private var draftSaved=false
    @State private var sourceDiscovery:PADiscovery?
    @State private var showingActivity=false
    @State private var answering:BriefingQuestion?
    @State private var answer=""
    @State private var answerError:String?
    @State private var answeringLearning:PALearningQuestion?
    private func discoveryTitle(_ item:PADiscovery)->String? {
        item.sourceTitle ?? (item.needsDateClarification && item.sourceKind != "whatsapp" ? model.emailSummaries.records.first{$0.id == item.mailID && $0.registration == item.registration}?.message?.subject : nil)
    }
    private func dateLabel(_ date:Date?,hasTime:Bool,fallback:String)->String {date?.formatted(date:.abbreviated,time:hasTime ? .shortened : .omitted) ?? fallback}
    private var reviewBusy:Bool {model.heartbeat.busy || model.proactive.busy || model.emailSummaries.busy}
    private var reviewRetrying:Bool {
        model.heartbeat.state.accounts[model.chatGPT.activeID]?.retryReason == "failure"
    }
    private var reviewStatus:String {
        let feedback=model.emailSummaries.feedback.items(model.chatGPT.activeID).filter{model.emailSummaries.feedbackMemory($0,model:self.model) == nil}
        if feedback.contains(where:{$0.state == .learning || $0.state == .saving}) {return "Learning your feedback in the background…"}
        if feedback.contains(where:{$0.state == .queued}) {return "Feedback saved for the next heartbeat"}
        if reviewBusy {return "Reviewing your sources…"}
        if !model.heartbeat.readable {return "Review history unavailable. See Activity for details."}
        return model.heartbeat.scheduleStatus(model)
    }
    private func completedProposal(_ item:PADiscovery,source:ReviewWorkSource)->Bool {
        model.reviewDiscoveryCompleted(item) || item.reviewState == "approved" || model.reviewWork.jobs(item.registration).contains { job in
            job.source.key == source.key && job.actions.contains{$0.id == item.id && $0.phase == .saved}
        }
    }
    private func lastSuggestionEntryIDs(_ values:[PADiscovery])->Set<String> {
        var last:[String:String]=[:]
        for item in values where item.kind != "update" {last[item.registration+":"+model.reviewSource(item).key]=item.id}
        return Set(last.values)
    }
    @ViewBuilder private func suggestionEntry(_ item:PADiscovery)->some View {
        let source=model.reviewSource(item)
        let current=model.reviewRecords(source)
        let related=current.isEmpty ? [item] : current
        let proposals=related.filter{$0.kind != "update"}
        let completed=model.reviewCompletedActions(source)
        if completed > 0 || completedProposal(item,source:source) {
            Label("\(max(1,completed)) action\(max(1,completed) == 1 ? "" : "s") completed",systemImage:"checkmark.circle.fill").foregroundStyle(.secondary)
            Button("View actions") {model.openReviewConversation(related)}
        }
        else if proposals.contains(where:{ProactiveReviewRules.hasSuggestedAction($0) && !completedProposal($0,source:source)}) {
            Button("Explore suggested actions") {model.openReviewConversation(related)}
        }
    }
    @ViewBuilder private func discoveryContent(_ item:PADiscovery,embedded:Bool=false,emailTitle:String?=nil,showsActionEntry:Bool=true)->some View {
        VStack(alignment:.leading,spacing:8) {
            if let change=item.proposedChange {
                Label("Needs approval · " + (change.target.kind == "event" ? "Calendar" : "Reminders"),systemImage:"calendar.badge.clock").font(.caption.weight(.semibold))
                Text(change.target.title).font(.callout.weight(.semibold))
                Text(dateLabel(change.target.start ?? change.target.due,hasTime:change.target.hasTime,fallback:"No date") + " → " + dateLabel(change.date(),hasTime:change.hasTime,fallback:change.newDate)).font(.callout).textSelection(.enabled)
                Text("Inferred connection · " + change.connection).font(.caption).foregroundStyle(.secondary)
            }
            if let removal=item.proposedRemoval {
                Label("Needs approval · Remove from Calendar",systemImage:"calendar.badge.minus").font(.caption.weight(.semibold))
                Text(removal.target.title).font(.callout.weight(.semibold))
                Text(dateLabel(removal.target.start,hasTime:removal.target.hasTime,fallback:"No date")).font(.callout).textSelection(.enabled)
                Text("Only this occurrence").font(.caption).foregroundStyle(.secondary)
                Text("Removal cannot be undone in 3PO.").font(.caption).foregroundStyle(.secondary)
            }
            if !embedded || item.nativeTarget == nil {
                Label(item.kind == "reply" ? "Reply draft" : item.kind == "update" ? "Update" : item.kind == "change" ? "Date change" : item.kind == "remove" ? "Calendar removal" : "Missing plan",systemImage:item.kind == "calendar" ? "calendar.badge.plus" : "checklist").font(.caption).foregroundStyle(.secondary)
            }
            if let title=discoveryTitle(item),!embedded || (title != emailTitle && title != item.nativeTarget?.title) { Text(title).font(.callout.weight(.semibold)) }
            if !embedded || item.nativeTarget == nil {Text(PAProse.display(item.message)).textSelection(.enabled)}
            if !embedded,let details=model.preparedSourceDetails(item) {ReviewSourceLabel(details:details,showsTitle:true)}
            if let reply=item.replyDraft {
                Text(reply).font(.callout).textSelection(.enabled).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                Text("Check the details before using this draft.").font(.caption2).foregroundStyle(.secondary)
            }
            if !embedded {
                ReviewFeedbackButton(model:model,topic:discoveryTitle(item) ?? item.message,email:model.preparedFeedbackEmail(item),isCurrent:{model.proactive.state.records.first(where:{$0.id == item.id}).map{ProactiveRules.reviewProjection($0) == item && model.proactive.preparedReviewAvailable($0,model:model)} == true})
            }
            if let project=item.proposedProjectTask { Label("Task in " + project.target.title,systemImage:"folder").font(.caption);Text(project.connection).font(.caption).foregroundStyle(.secondary) }
            if let date=item.proposedDate { Text(dateLabel(date.date(),hasTime:date.hasTime,fallback:date.start) + (date.end.map{" to " + dateLabel(date.date($0),hasTime:date.hasTime,fallback:$0)} ?? "")).font(.callout).textSelection(.enabled) }
            Button("Source evidence") { sourceDiscovery=item }.buttonStyle(.borderless).font(.caption)
            if item.reviewState == "pending" || model.reviewCreationClaim(item).map({$0.receipt == nil}) == true {
                Label("Save needs checking; it will not be repeated",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if showsActionEntry,item.kind != "update" {suggestionEntry(item)}
                Spacer()
                if !embedded {Button("Dismiss") {model.proactive.dismiss(item,model:model)}.disabled(model.writing)}
            }.controlSize(.small)
            if model.reviewApprovalErrorAccount == item.registration,model.reviewApprovalErrorID == item.id,let error=model.reviewApprovalError {Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
        }
    }
    @State private var showingRelevance=false
    var body: some View {
        let inbox=model.reviewInbox,questions=inbox.questions,learningQuestions=inbox.learningQuestions,discoveries=inbox.discoveries,emails=inbox.emails,emailCards=inbox.emailCards,standaloneDiscoveries=inbox.standaloneDiscoveries,pending=inbox.pending
        let standaloneEntryIDs=lastSuggestionEntryIDs(standaloneDiscoveries)
        return VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Review inbox",systemImage:"tray.full").font(.title3.weight(.semibold))
                ReviewInboxBadge(count:inbox.pendingCount)
                Spacer()
                Button {showingRelevance=true} label:{Image(systemName:"slider.horizontal.3")}.buttonStyle(.borderless).help("Review guidance and feedback").accessibilityLabel("Review guidance")
                Button { showingActivity=true } label:{Image(systemName:"clock.arrow.circlepath")}
                    .buttonStyle(.borderless).help("Background activity and details").accessibilityLabel("Background activity")
                Button { model.heartbeat.check(model,manual:true) } label:{Image(systemName:"waveform.path.ecg")}
                    .buttonStyle(.borderless).help(model.heartbeat.manualCheckHelp(model)).accessibilityLabel("Run heartbeat")
                    .disabled(model.heartbeat.manualCheckBlockReason(model) != nil)
            }
            HStack(spacing:8) {
                if reviewBusy {ProgressView().controlSize(.mini)}
                Text(reviewStatus).font(.caption).foregroundStyle(reviewRetrying ? Color.orange : Color.secondary)
                    .fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                if model.heartbeat.dailyCallLimit > 0,model.heartbeat.state.accounts[model.chatGPT.activeID]?.retryReason == "allowance" {
                    Button("Limit settings…") {settingsPage="Background";openSettings()}.buttonStyle(.borderless).font(.caption)
                }
            }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:12) {
                    if !questions.isEmpty || !learningQuestions.isEmpty || !inbox.contextQuestions.isEmpty {Text("Questions for you").font(.headline)}
                    ContextProjectQuestionsSection(model: model, questions: inbox.contextQuestions)
                    ForEach(questions) {item in
                        VStack(alignment:.leading,spacing:8) {
                            Label("Your answer would help",systemImage:"questionmark.bubble").font(.caption).foregroundStyle(.secondary)
                            Text(PAProse.display(item.question)).font(.callout).textSelection(.enabled)
                            DisclosureGroup("Context") {ForEach(item.sourceIDs,id:\.self) {id in if let source=item.snapshot.sources.first(where:{$0.id == id}) {Text(source.label + (source.date.map{" · " + $0.formatted(date:.abbreviated,time:.shortened)} ?? "")).font(.caption).textSelection(.enabled)}}}
                            HStack {Button("Answer") {answering=item;answer="";answerError=nil};Spacer();Button("Dismiss") {_ = model.briefings.resolveQuestion(item,model:model,answered:false)}}.controlSize(.small)
                        }.taskCard()
                    }
                    ForEach(learningQuestions) {item in
                        VStack(alignment:.leading,spacing:8) {
                            Label("Getting to know you",systemImage:"questionmark.bubble").font(.caption).foregroundStyle(.secondary)
                            Text(PAProse.display(item.text)).font(.callout)
                            DisclosureGroup("Why I’m asking") {Text(item.evidence).font(.caption).textSelection(.enabled)}
                            HStack {Button("Answer") {answeringLearning=item;answer="";answerError=nil};Spacer();Button("Dismiss") {model.memoryLearning.dismiss(item)}}.controlSize(.small)
                        }.taskCard()
                    }
                    if !standaloneDiscoveries.isEmpty { Text("From your background review").font(.headline) }
                    ForEach(standaloneDiscoveries) { item in
                        discoveryContent(item,showsActionEntry:standaloneEntryIDs.contains(item.id)).taskCard()
                    }
                    if !emailCards.isEmpty { Text("Emails to review").font(.headline) }
                    ForEach(emailCards) { card in
                        let message=card.message,summary=card.summary
                        VStack(alignment:.leading,spacing:8) {
                            Label(card.handling?.label ?? (!card.needsReview ? "Reviewed" : summary.replyDraft == nil ? (summary.attention ? "Needs attention" : "Update") : "Reply draft ready"),systemImage:card.handling != nil || !card.needsReview ? "checkmark.circle" : summary.replyDraft == nil ? "checklist" : "pencil.line").font(.caption).foregroundStyle(.secondary)
                            Text(message.subject).font(.callout.weight(.semibold)).lineLimit(2)
                            ReviewSourceLabel(details:.email(message))
                            Text(PAProse.display(summary.reason.isEmpty ? summary.summary : summary.reason)).font(.callout).textSelection(.enabled)
                            if let handling=card.handling {
                                Text("Inferred connection to “"+handling.native.title+"” · "+handling.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                Button("Keep in review") {model.emailSummaries.keepForReview(summary.id,model:model)}.buttonStyle(.borderless).font(.caption)
                            }
                            if summary.keepInReview == true {HStack {Text("Kept in review by you").font(.caption).foregroundStyle(.secondary);Button("Use inferred status") {model.emailSummaries.keepForReview(summary.id,model:model,keep:false)}.buttonStyle(.borderless).font(.caption)}}
                            if let reply=summary.replyDraft {
                                VStack(alignment:.leading,spacing:5) {
                                    Text("Suggested reply").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    if summary.replyDraftEdited == true,summary.replyDraftCheckedBody != summary.bodyFingerprint {Text("Your saved draft is preserved, but the email changed. Review its details.").font(.caption).foregroundStyle(.orange)}
                                    Text(reply).font(.callout).textSelection(.enabled)
                                    Text("Check placeholders and details before using it.").font(.caption2).foregroundStyle(.secondary)
                                }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
                            }
                            if summary.replyDraft == nil,EmailReplyDraftRules.canReply(summary,message:message) {
                                Text(EmailReplyDraftRules.needsBackgroundDraft(summary,message:message) ? "Reply preparation pending" : "Check details before preparing a reply").font(.caption).foregroundStyle(.secondary)
                            }
                            if let relevance=summary.personalRelevance {Label(relevance.reason,systemImage:"person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(.secondary)}
                            let completedSource=ReviewWorkSource(key:"mail:"+message.id,title:message.subject,kind:"mail",accountID:message.accountID,messageID:message.id)
                            let completedActions=model.reviewCompletedActions(completedSource)
                            if completedActions > 0 {
                                HStack {Label("\(completedActions) action\(completedActions == 1 ? "" : "s") completed",systemImage:"checkmark.circle.fill").foregroundStyle(.secondary);Button("View actions") {model.openReviewSource(message)};Spacer()}.controlSize(.small)
                            }
                            let proposals=card.discoveries.filter{$0.kind != "update"},updates=card.discoveries.filter{$0.kind == "update"}
                            let pendingProposals=proposals.filter{ProactiveReviewRules.hasSuggestedAction($0) && !completedProposal($0,source:completedSource)}
                            let hasSummaryDraft=summary.replyDraft.map{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty} == true && !proposals.contains{$0.replyDraft != nil} && !model.reviewSummaryDraftCompleted(message)
                            if proposals.contains(where:{$0.reviewState == "pending" || model.reviewCreationClaim($0).map({$0.receipt == nil}) == true}) {
                                Label("A save needs checking",systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                            }
                            if completedActions == 0 && (!pendingProposals.isEmpty || hasSummaryDraft) {
                                Button("Explore suggested actions") {model.openReviewSource(message)}.controlSize(.small)
                            }
                            if !updates.isEmpty {
                                DisclosureGroup("Background context") {
                                    ForEach(updates) { item in discoveryContent(item,embedded:true,emailTitle:message.subject,showsActionEntry:false) }
                                }
                            }
                            HStack {
                                ReviewFeedbackButton(model:model,topic:message.subject,email:.init(message:message,summary:summary),isCurrent:{model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)})
                                Button("View email") { model.select(message) }
                                Spacer(); Button("Dismiss") { model.emailSummaries.dismiss(message.id,model:model,expectedRegistration:summary.registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary)) }
                            }.controlSize(.small)
                        }.taskCard()
                    }
                    if !pending.isEmpty { Text("Delegated work").font(.headline) }
                    ForEach(pending) { item in
                        VStack(alignment:.leading,spacing:6) {
                            Label(item.state == .completed ? "PA work ready" : item.state == .needsAnswer ? "Your answer needed" : item.state == .running ? "PA working" : item.state == .interrupted ? "Check interrupted work" : "Queued for your PA",systemImage:"bubble.left.and.bubble.right").font(.caption).foregroundStyle(.secondary)
                            Text(item.prompt).lineLimit(3)
                            if let result=item.result { DisclosureGroup("Result") { Text(result).textSelection(.enabled) } }
                            if let focus=item.focusAreas,!focus.isEmpty { Text(focus.map(\.title).joined(separator:" · ")).font(.caption2).foregroundStyle(.secondary) }
                            if item.state != .running { HStack { if item.state == .waiting { Button("Continue queue") { model.assistant.resumeQueue(model:model) }.disabled(model.assistant.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }; Button("Remove") { model.assistant.discardQueued(item.id) } }.controlSize(.small) }
                        }.taskCard()
                    }
                    if emailCards.isEmpty && standaloneDiscoveries.isEmpty && pending.isEmpty && questions.isEmpty && learningQuestions.isEmpty && inbox.contextQuestions.isEmpty {
                        ContentUnavailableView("Nothing waiting for review",systemImage:"checkmark.circle",description:Text("Proposed changes, useful updates and prepared work appear here when enabled sources reveal something useful."))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .sheet(isPresented:$showingRelevance) {ReviewPolicyView(model:model)}
        .onChange(of:model.chatGPT.activeID) {showingRelevance=false}
        .sheet(item:$answering) {question in
            VStack(alignment:.leading,spacing:16) {
                Text(question.question).font(.headline)
                TextEditor(text:$answer).frame(minHeight:100).font(.body)
                if let answerError {Text(answerError).font(.caption).foregroundStyle(.orange)}
                HStack {Button("Cancel") {answering=nil};Spacer();Button("Send answer") {
                    guard questions.contains(where:{$0.id == question.id}) else {answerError="This question’s supporting context changed. Run a fresh heartbeat.";return}
                    let text="About your question “"+question.question+"”: "+answer.trimmingCharacters(in:.whitespacesAndNewlines)
                    if model.assistant.send(model:model,topicID:nil,prompt:text,focusAreas:[]) {
                        _ = model.briefings.resolveQuestion(question,model:model,answered:true);answering=nil
                    } else {answerError="Your PA is busy. Your answer is kept here; send it when ready."}
                }.disabled(answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.assistant.busy || model.chatGPT.busy || model.writing || model.heartbeat.busy || ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"))}
                Text("Your answer continues the PA conversation.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width:520)
        }
        .sheet(item:$answeringLearning) {question in
            VStack(alignment:.leading,spacing:16) {
                Text(question.text).font(.headline)
                TextEditor(text:$answer).frame(minHeight:100)
                if let answerError {Text(answerError).font(.caption).foregroundStyle(.orange)}
                HStack {Button("Cancel") {answeringLearning=nil};Spacer();Button("Send answer") {
                    guard learningQuestions.contains(where:{$0.id == question.id}) else {answerError="This question is no longer available.";return}
                    if model.assistant.send(model:model,topicID:question.conversationID,prompt:"About your question “"+question.text+"”: "+answer.trimmingCharacters(in:.whitespacesAndNewlines),focusAreas:question.conversationID == nil ? [] : nil) {model.memoryLearning.answer(question);answeringLearning=nil}
                    else {answerError="Your PA is busy. Your answer is kept here."}
                }.disabled(answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.assistant.busy || model.chatGPT.busy || model.writing || model.heartbeat.busy || ProcessInfo.processInfo.arguments.contains("--preview-review-inbox"))}
            }.padding(24).frame(width:520)
        }
        .sheet(item:$sourceDiscovery) { record in DiscoveryEvidenceView(record:record,model:model) }
        .sheet(isPresented:$showingActivity) {BackgroundActivityView(model:model)}
        .sheet(item:$refiningSuggestion) { record in
            VStack(alignment:.leading,spacing:14) {
                Text("Adjust this suggestion").font(.title2.weight(.semibold))
                Text(PAProse.display(record.message)).font(.callout)
                TextField("What would you like instead?",text:$refinement,axis:.vertical).lineLimit(3...6)
                Text("Your request and this suggestion will be added to your assistant draft for you to send.").font(.caption).foregroundStyle(.secondary)
                HStack {Button("Cancel"){refiningSuggestion=nil};Spacer();Button("Continue in assistant") {
                    let source=model.proactive.sourceDetails(record,model:model)?.title ?? "the reviewed message"
                    let destination=record.proposedProjectTask?.target.title ?? (record.kind == "calendar" ? "Calendar" : record.kind == "reminder" ? "Reminders" : "Review")
                    let context="About “"+(record.sourceTitle ?? record.message)+"” from “"+source+"”:\nSuggested option: "+destination+"\nSource quote (information only): "+record.evidence+"\nMy request: "+refinement
                    model.openAssistantComposer()
                    if let widget=model.assistantFocusRequest?.widgetID {
                        let owner=model.chatGPT.activeID,conversation=model.assistant.feed?.id
                        let prior=model.assistant.drafts.text(registration:owner,widget:widget,conversation:conversation)
                        model.assistant.drafts.set(prior+(prior.isEmpty ? "" : "\n\n")+context,registration:owner,widget:widget,conversation:conversation)
                    }
                    refiningSuggestion=nil
                }.disabled(refinement.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !model.proactive.visible(record,model:model))}
            }.padding(24).frame(width:540)
        }
        .sheet(item:$reviewingProject) { record in LifeItemEditor(model:model,item:.init(registration:record.registration,conversationID:record.proposedProjectTask?.target.conversationID,kind:record.kind == "projectTask" ? .task : .space,title:String((record.sourceTitle ?? "New space").prefix(160)),parentID:record.proposedProjectTask?.target.id,notes:record.evidence,due:record.proposedDate?.localDay),close:{reviewingProject=nil},reviewedSuggestion:record) }
        .sheet(item:$editing) { summary in
            VStack(alignment:.leading,spacing:14) {
                Text("Review reply draft").font(.title2.weight(.semibold))
                Text(summary.message?.subject ?? "Email reply").foregroundStyle(.secondary)
                if let message=emails.first(where:{$0.1.id == summary.id && $0.1.fingerprint == summary.fingerprint})?.0 {ReviewSourceLabel(details:.email(message))}
                TextEditor(text:$draft).onChange(of:draft) { copied=false; draftSaved=false }.font(.body).frame(minHeight:240)
                Text("Check details and placeholders before using this draft.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Close") { editing=nil }; Spacer(); Button(draftSaved ? "Saved" : "Save draft") { draftSaved=model.emailSummaries.saveReplyDraft(draft,summary:summary,model:model) }; Button(copied ? "Copied" : "Copy draft") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft,forType:.string); copied=true } }
            }.padding(24).frame(width:560)
        }.onChange(of:model.chatGPT.activeID) { editing=nil; draft="";sourceDiscovery=nil;reviewingProject=nil;answering=nil;answeringLearning=nil;answer="" }
        .onChange(of:discoveries.map(\.id)) { if let sourceDiscovery,!discoveries.contains(where:{$0.id == sourceDiscovery.id}) { self.sourceDiscovery=nil } }.onChange(of:model.assistant.excludedAccounts) { if let account=editing?.message?.accountID,model.assistant.excludedAccounts.contains(account) { editing=nil; draft="" } }
    }
}
private extension View {
    func taskCard()->some View { padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12)) }
}

struct CalendarRemovalReviewSheet:View {
    var model:DashboardModel
    var session:CalendarRemovalReviewSession
    @Environment(\.dismiss) private var dismiss
    @State private var saving=false
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Label("Remove this Calendar occurrence?",systemImage:"calendar.badge.minus").font(.title2.weight(.semibold))
            Text(session.baseline.title).font(.headline)
            Text(session.baseline.start.formatted(date:.complete,time:session.baseline.allDay ? .omitted : .shortened))
            Text("This event repeats. Approval removes only the occurrence shown above. Other occurrences stay in Calendar.").font(.callout)
            Text(PAProse.display(session.record.message)).textSelection(.enabled)
            DisclosureGroup("Source evidence") {Text(session.record.evidence).font(.callout).textSelection(.enabled)}
            Text("Removal cannot be undone in 3PO.").font(.caption).foregroundStyle(.secondary)
            if let error {Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)}
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction).disabled(saving)
                Spacer()
                Button(saving ? "Approving…" : "Approve this occurrence") {Task {
                    saving=true;defer {saving=false}
                    do {try await model.saveCalendarRemoval(session.record,baseline:session.baseline,selectedModel:session.selectedModel,sourceScope:session.sourceScope,occurrenceConfirmed:true);dismiss()}
                    catch {self.error=error.localizedDescription}
                }}.disabled(saving || model.writing || model.assistant.busy || !model.proactive.canReview(session.record.id,model:model))
            }
        }.padding(24).frame(width:520).interactiveDismissDisabled(saving)
    }
}

struct ReviewHistoryView:View {
    @Bindable var model:DashboardModel
    var body:some View {
        let handled=model.reviewInbox.handled,resolved=model.reviewInbox.resolved
        let retired=model.proactive.state.records.filter{$0.registration == model.chatGPT.activeID && $0.retiredAt != nil}
        DisclosureGroup("Review history") {
            VStack(alignment:.leading,spacing:12) {
                Text("Saved background decisions that an action was planned or addressed. A later heartbeat can reconsider them. Keep in review restores the email.").font(.caption).foregroundStyle(.secondary)
                ForEach(handled,id:\.0.id) {message,summary,value in
                    VStack(alignment:.leading,spacing:6) {Text(message.subject).font(.callout.weight(.semibold));Text(PAProse.display(value.reason)).font(.caption);Text(value.native.title).font(.caption).foregroundStyle(.secondary);HStack {Button("View email") {model.select(message)};Button("Keep in review") {model.emailSummaries.keepForReview(summary.id,model:model)}}.controlSize(.small)}.taskCard()
                }
                ForEach(resolved,id:\.0.id) {message,summary,value in
                    VStack(alignment:.leading,spacing:6) {Text(message.subject).font(.callout.weight(.semibold));Text(PAProse.display(value.reason)).font(.caption);DisclosureGroup("Evidence") {Text("Earlier request: “"+value.requestQuote+"”");Text("Confirmation: “"+value.confirmation.quote+"”");if let confirmation=model.emailSummaries.sourceAssessments(model).first(where:{$0.0.id == value.confirmation.messageID})?.0 {Button("View confirmation") {model.select(confirmation)}}}.font(.caption);HStack {Button("View email") {model.select(message)};Button("Keep in review") {model.emailSummaries.keepForReview(summary.id,model:model)}}.controlSize(.small)}.taskCard()
                }
                ForEach(retired) {item in
                    VStack(alignment:.leading,spacing:6) {Text(item.sourceTitle ?? item.message).font(.callout.weight(.semibold));Text(item.retirementReason ?? "Retired during a heartbeat.").font(.caption);Button("Keep in review") {model.proactive.restoreRetired(item,model:model)}.controlSize(.small);if let date=item.retiredAt {Text("Reviewed " + date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}}.taskCard()
                }
                if handled.isEmpty && resolved.isEmpty && retired.isEmpty {Text("No saved addressed items.").font(.caption).foregroundStyle(.secondary)}
                Text("Dismiss acknowledges the displayed concern. Undo restores it. Feedback is saved separately in PA memory.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top,8)
        }.padding(12)
    }
}
