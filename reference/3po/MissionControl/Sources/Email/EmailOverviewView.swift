import SwiftUI
struct EmailOverviewView: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var configuration: Binding<WidgetConfiguration>? = nil
    @State private var filter = "All"
    @State private var limit = 6
    @State private var showRelevance=false
    private var available: [(MailMessage,EmailSummary)] {
        model.reviewInbox.highlights.filter { message,summary in
            !(configuration?.wrappedValue.sourceExclusions.contains(message.accountID) ?? false) && (filter == "All" || (filter == "Needs action" ? EmailHighlightRules.needsAction(summary,replied:message.replied) : filter == "Worth reading" ? summary.worthReading == true && !EmailHighlightRules.needsAction(summary,replied:message.replied) : summary.followUpDate != nil))
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Label("Email summary",systemImage:"envelope.badge").font(.title3.weight(.semibold)); Spacer()
                Button {showRelevance=true} label:{Image(systemName:"slider.horizontal.3")}.help("Review guidance").accessibilityLabel("Review guidance")
                Button { summaries.process(model,resume:true) } label: { Image(systemName:"arrow.clockwise") }.help("Check incoming mail").accessibilityLabel("Check incoming mail").disabled(!summaries.enabled || summaries.busy || model.chatGPT.busy || model.assistant.busy || model.chatGPT.usagePaused || !model.chatGPT.inferenceVerified)
                if summaries.busy { ProgressView().controlSize(.small); Button("Stop") { summaries.cancel() } }
            }
            HStack {
                Picker("Show",selection:$filter) { ForEach(["All","Needs action","Worth reading","Future dates"],id:\.self) { Text($0).tag($0) } }.labelsHidden().frame(maxWidth:160)
                if let configuration {
                    Menu("Accounts") {
                        ForEach(model.mailData.accounts) { account in
                            Toggle(account.title,isOn:Binding(get:{ !configuration.wrappedValue.sourceExclusions.contains(account.id) },set:{ on in var value = configuration.wrappedValue; if on { value.sourceExclusions.remove(account.id) } else { value.sourceExclusions.insert(account.id) }; configuration.wrappedValue = value }))
                        }
                    }
                }
                Spacer(minLength:0)
            }
            if summaries.canUndoDismiss { HStack { Text("Suggestion dismissed").font(.caption).foregroundStyle(.secondary); Button("Undo") { summaries.undoDismiss(model) }.controlSize(.small); Spacer() } }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:250),spacing:12,alignment:.top)],alignment:.leading,spacing:12) {
                    ForEach(Array(available.prefix(limit)),id:\.0.id) { message,summary in
                        VStack(alignment:.leading,spacing:8) {
                            HStack(alignment:.top) {
                                Text(EmailHighlightRules.category(summary,replied:message.replied)).font(.caption.weight(.semibold)).foregroundStyle(summary.attention ? Color.accentColor : Color.secondary)
                                Spacer()
                                ReviewFeedbackButton(model:model,topic:message.subject,email:.init(message:message,summary:summary),isCurrent:{model.emailSummaries.feedbackSourceCurrent(message,summary:summary,model:model)})
                                Button { summaries.dismiss(message.id,model:model,expectedRegistration:summary.registration,expectedVersion:ReviewAcknowledgementRules.emailVersion(message,summary)) } label: { Image(systemName:"xmark") }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).help("Dismiss suggestion").accessibilityLabel("Dismiss email suggestion")
                            }
                            Text(message.subject).font(.callout.weight(.semibold)).lineLimit(2)
                            Text(PAProse.display(summary.summary)).font(.callout).lineSpacing(3).lineLimit(4).textSelection(.enabled)
                            if let date = summary.followUpDate { Label(date,systemImage:"calendar").font(.caption).foregroundStyle(.secondary) }
                            if let relevance=summary.personalRelevance {Label(relevance.reason,systemImage:"person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(.secondary)}
                            DisclosureGroup("Why this matters") {
                                VStack(alignment:.leading,spacing:6) { Text(PAProse.display(summary.summary)).textSelection(.enabled); if !summary.reason.isEmpty { Text(PAProse.display(summary.reason)) }; if !summary.evidence.isEmpty { Text("“" + summary.evidence + "”").foregroundStyle(.secondary).textSelection(.enabled) } }.font(.caption)
                            }.font(.caption)
                            HStack { Text(message.account + " · " + message.received.formatted(date:.abbreviated,time:.omitted)).font(.caption2).foregroundStyle(.secondary); Spacer(); Button("Read original") { model.select(message) }.buttonStyle(.link).font(.caption) }
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                    }
                    }
                    if available.count > limit { Button("Show more (\(available.count-limit))") { limit += 6 }.controlSize(.small) }
                    if available.isEmpty { ContentUnavailableView("Nothing highlighted here",systemImage:"envelope.open",description:Text(!summaries.enabled ? "Enable incoming email monitoring in Settings. It reads relevant new mail without summarising the historical inbox." : "No saved suggestions match this view. Coverage is partial while new mail is being checked.")) }
                    DisclosureGroup("Coverage and controls") {
                        VStack(alignment:.leading,spacing:8) {
                            Text(summaries.coverage(model)).font(.caption).foregroundStyle(.secondary)
                            Text("AI suggestions can be mistaken. Reply flags are hints; email is read-only here. Dismiss hides a suggestion without changing Mail.").font(.caption).foregroundStyle(.secondary)
                            if summaries.rejectedCount(model) > 0 { Button("Retry skipped assessments") { summaries.retryRejected(model) }.disabled(summaries.busy || model.chatGPT.busy || model.chatGPT.usagePaused) }
                        }.padding(.top,6)
                    }.font(.caption)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if summaries.paused || model.chatGPT.usagePaused { Text(model.chatGPT.usagePaused ? "Subscription processing paused; saved suggestions are available." : "Monitoring paused. Check incoming mail to resume one bounded batch.").font(.caption).foregroundStyle(.orange) }
            if let error = summaries.error { DisclosureGroup("Monitoring details") { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }.font(.caption) }
        }.sheet(isPresented:$showRelevance) {ReviewPolicyView(model:model)}.onChange(of:model.chatGPT.activeID) {showRelevance=false}.onChange(of:filter) { limit = 6 }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
}
struct EmailSummarySettings: View {
    @Bindable var model: DashboardModel
    @Bindable var summaries: EmailSummaryService
    var body: some View {
        Section("Incoming email assessment") {
            Picker("Email summary model", selection: $summaries.modelID) {
                Text("Use assistant model").tag("")
                ForEach(model.chatGPT.models) { Text($0.name).tag($0.id) }
            }.disabled(summaries.busy)
            Picker("Email reasoning", selection: $summaries.effort) {
                Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
            }.disabled(summaries.busy)
            Text("Heartbeats analyse collected permitted mail and prepare relevant reply drafts through your ChatGPT plan. Mail refreshes separately every five minutes. Completed assessments are reused; collection issues are shown without discarding collected data. A failed AI check tries again at the next heartbeat. Nothing is sent.").font(.caption)
            Text("Choose permitted mail accounts in Settings → Assistant → Assistant source scope. Mailbox filters change only the source view.").font(.caption).foregroundStyle(.secondary)
        }
    }
}


struct ReviewFeedbackButton:View {
    @Bindable var model:DashboardModel
    var topic:String
    var email:ReviewFeedbackEmail? = nil
    var isCurrent:()->Bool
    @State private var showingFeedback=false
    @State private var savedRule:String?
    var body:some View {
        VStack(alignment:.leading,spacing:6) {
            Button("Feedback") {showingFeedback=true}.controlSize(.small).help("Let your PA learn what matters from your feedback and this email").disabled(email.flatMap{model.emailSummaries.feedback.latest(model.chatGPT.activeID,messageID:$0.message.id)}.map{$0.pending && model.emailSummaries.feedbackMemory($0,model:model) == nil} ?? false)
            if let email,let job=model.emailSummaries.feedback.latest(model.chatGPT.activeID,messageID:email.message.id) {ReviewFeedbackProgressView(model:model,job:job)}
            else if let savedRule {DisclosureGroup("Saved preference") {Text(savedRule).font(.caption).textSelection(.enabled)}.font(.caption)}
        }
        .sheet(isPresented:$showingFeedback) {ReviewFeedbackEditor(model:model,topic:topic,email:email,isCurrent:isCurrent,onSaved:{savedRule=$0})}
        .onChange(of:model.chatGPT.activeID) {showingFeedback=false;savedRule=nil}
    }
}
struct ReviewFeedbackEditor:View {
    @Bindable var model:DashboardModel
    var topic:String=""
    var email:ReviewFeedbackEmail? = nil
    var expected:PAMemory? = nil
    var isCurrent:()->Bool={true}
    var onSaved:(String)->Void={_ in}
    private let registration:String
    @Environment(\.dismiss) private var dismiss
    @State private var words:String
    @State private var about:String
    @State private var learnedRule:String
    @State private var error:String?
    init(model:DashboardModel,topic:String="",email:ReviewFeedbackEmail?=nil,expected:PAMemory?=nil,isCurrent:@escaping ()->Bool={true},onSaved:@escaping (String)->Void={_ in}) {
        self.model=model;self.topic=topic;self.email=email;self.expected=expected;self.isCurrent=isCurrent;self.onSaved=onSaved;registration=model.chatGPT.activeID
        _words=State(initialValue:expected?.reviewFeedback ?? expected?.evidence ?? expected?.text ?? "")
        _about=State(initialValue:expected?.reviewContext ?? String(topic.prefix(300)))
        _learnedRule=State(initialValue:expected?.reviewInterpretation?.rule ?? "")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(expected == nil ? "Feedback" : "Edit review preference").font(.title2.weight(.semibold))
            LabeledContent("About") {TextField("Optional topic",text:$about).textFieldStyle(.roundedBorder).accessibilityLabel("Feedback topic")}
            Text("You can keep the email's subject or change this to make the preference broader or more specific.").font(.caption).foregroundStyle(.secondary)
            Text("What should your PA learn about what is worth reviewing?").font(.headline)
            TextEditor(text:$words).frame(height:110).font(.body).border(Color.secondary.opacity(0.25))
            if expected?.reviewInterpretation != nil {
                Text("Saved preference").font(.headline)
                TextEditor(text:$learnedRule).frame(height:90).font(.body).border(Color.secondary.opacity(0.25))
                Text("Edit the learned preference directly. Changing your feedback or topic clears the old interpretation; you can write a new preference or keep only your words.").font(.caption).foregroundStyle(.secondary)
            } else if email != nil {
                Text("Your feedback is saved for the next heartbeat. You can dismiss the email and carry on; the feedback remains in Review preferences, where Process now starts it immediately. Your original words remain as evidence.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("This preference is saved locally. Feedback on an email also lets your PA reason about that email's context.").font(.caption).foregroundStyle(.secondary)
            }
            Text("For example: ‘These emails aren't important’ can mean routine newsletters from this communications team can stay quiet. Dismiss only means acknowledged.").font(.caption).foregroundStyle(.secondary)
            if !model.assistant.memory.enabled {Text("Memory use is paused. The preference will be saved and used when you turn it back on.").font(.caption).foregroundStyle(.secondary)}
            if let error {Text(error).font(.caption).foregroundStyle(.orange)}
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button(email != nil && expected == nil ? "Submit feedback" : "Save to memory") {save()}.keyboardShortcut(.defaultAction).disabled(words.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || words.count > 2000 || about.count > 300 || learnedRule.count > 1200)
            }
        }.padding(24).frame(width:560)
        .onChange(of:model.chatGPT.activeID) {dismiss()}
        .onChange(of:words) {if expected?.reviewInterpretation != nil {learnedRule=""}}
        .onChange(of:about) {if expected?.reviewInterpretation != nil {learnedRule=""}}
    }
    private func save() {
        guard registration == model.chatGPT.activeID,isCurrent() else {error="The item or account changed. Reopen Feedback before saving.";return}
        if let email,expected == nil {
            guard model.emailSummaries.submitReviewFeedback(email,words:words,about:about,model:model) else {error=model.emailSummaries.feedback.error;return}
            dismiss();return
        }
        var interpretation:ReviewFeedbackInterpretation?
        if !learnedRule.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,let previous=expected?.reviewInterpretation {interpretation=previous;interpretation?.rule=learnedRule.trimmingCharacters(in:.whitespacesAndNewlines);interpretation?.humanEdited=true}
        guard model.assistant.memory.saveReviewPreference(words,registration:registration,expected:expected,about:about,interpretation:interpretation) else {error=model.assistant.memory.error;return}
        onSaved(interpretation?.rule ?? words);dismiss()
    }
}
struct ReviewFeedbackProgressView:View {
    @Bindable var model:DashboardModel
    var job:ReviewFeedbackJob
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            if let saved=model.emailSummaries.feedbackMemory(job,model:model) {
                DisclosureGroup("Saved preference") {Text(saved.text).textSelection(.enabled)}
                if job.state != .saved {Button("Update saved status") {_=model.emailSummaries.feedback.markSaved(job.id)}}
            } else {
                HStack {if job.state == .learning || job.state == .saving {ProgressView().controlSize(.mini)};Text(job.state == .stopped && model.emailSummaries.feedback.activeID == job.id ? "Stopping feedback…" : job.status);if job.pending {Button("Stop") {model.emailSummaries.feedback.stop(job.id)}}}
                if job.state == .queued {Button("Process now") {_=model.emailSummaries.processFeedbackNow(job,model:model)}}
                if let error=job.error {Text(error).foregroundStyle(.orange).textSelection(.enabled)}
                if !job.pending && job.state != .saved && model.emailSummaries.feedback.activeID != job.id {
                    HStack {Button("Retry learning") {_=model.emailSummaries.retryFeedback(job,model:model)};Button("Save only my words") {_=model.emailSummaries.saveFeedbackWords(job,model:model)}}
                }
            }
            if let error=model.emailSummaries.feedback.error {Text(error).foregroundStyle(.orange)}
        }.font(.caption).controlSize(.small)
    }
}
struct ReviewRelevancePreferencesView:View {
    @Bindable var model:DashboardModel
    private let registration:String
    @Environment(\.dismiss) private var dismiss
    @State private var editingMemory:PAMemory?
    @State private var addingMemory=false
    @State private var error:String?
    init(model:DashboardModel) {self.model=model;registration=model.chatGPT.activeID}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {Text("Review preferences").font(.title2.weight(.semibold));Spacer();Button("Done") {dismiss()}}
            Text("Your PA saves the preference it learns. Original feedback and edit history remain available as evidence. Dismiss simply clears the item; it does not teach a preference.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(model.emailSummaries.feedback.items(registration).filter{$0.state != .saved && model.emailSummaries.feedbackMemory($0,model:model) == nil}) {job in
                        VStack(alignment:.leading,spacing:6) {Text(job.about.isEmpty ? "Submitted feedback" : job.about).font(.callout.weight(.semibold));DisclosureGroup("Your feedback") {Text(job.words).textSelection(.enabled)};ReviewFeedbackProgressView(model:model,job:job)}.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                    }
                    ForEach(model.assistant.memory.reviewPreferences(registration,includeRetired:true)) {value in
                        HStack(alignment:.top) {
                            VStack(alignment:.leading,spacing:5) {if let about=value.reviewContext {Text(about).font(.callout.weight(.semibold))};Text(value.text).textSelection(.enabled);if let original=value.reviewFeedback,value.reviewInterpretation != nil {DisclosureGroup("Your feedback") {Text(original).font(.caption).textSelection(.enabled)}};Text(value.retiredAt == nil ? "Saved in PA memory" : "Disabled").font(.caption).foregroundStyle(.secondary)}
                            Spacer()
                            Menu {Button("Edit") {editingMemory=value};Button(value.retiredAt == nil ? "Disable" : "Restore") {
                                guard model.assistant.memory.retire(value.id,retired:value.retiredAt == nil,expectedRevision:model.assistant.memory.revision) else {error=model.assistant.memory.error;return}
                            }} label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).fixedSize()
                        }.padding(12).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:10))
                    }
                    if model.assistant.memory.reviewPreferences(registration,includeRetired:true).isEmpty {Text("Use Feedback on an item to explain what matters to you, or add a preference below.").foregroundStyle(.secondary).padding(.vertical)}
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if let error=error ?? model.assistant.memory.reviewPreferenceMigrationError {Text(error).font(.caption).foregroundStyle(.orange)}
            HStack {
                Button("Add preference…") {addingMemory=true}
                Spacer()
            }
        }.padding(24).frame(width:620,height:430).sheet(item:$editingMemory) {ReviewFeedbackEditor(model:model,expected:$0)}.sheet(isPresented:$addingMemory) {ReviewFeedbackEditor(model:model)}.onChange(of:model.chatGPT.activeID) {dismiss()}
    }
}
