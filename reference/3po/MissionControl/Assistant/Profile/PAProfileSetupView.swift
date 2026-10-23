import SwiftUI

/// A resumable interview with a separate persisted answer draft; normal PA drafts never change.
struct PAProfileSetupPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model:DashboardModel
    @Bindable var assistant:AssistantService
    let topicID:UUID?
    let registration:String
    @FocusState private var answerFocused:Bool
    private var owned:Bool { model.chatGPT.activeID == registration }
    private var session:UUID? { assistant.profileSession(topicID) }
    private var turns:[AssistantTurn] { owned ? assistant.profileTurns(topicID) : [] }
    private var reply:AssistantTurn? { turns.last(where:{$0.role == "assistant"}) }
    private var working:Bool { owned && assistant.profileBusy(topicID) }
    private var active:Bool { owned && assistant.setupActive(topicID) && session != nil }
    private var ready:Bool { owned && !assistant.busy && !model.chatGPT.busy && !model.chatGPT.usagePaused && model.chatGPT.inferenceVerified }
    private var answer:Binding<String> {
        Binding(get:{ guard let session else { return "" }; return assistant.drafts.text(registration:registration,widget:session,conversation:topicID) },set:{ text in
            guard owned,let session else { return }
            assistant.drafts.set(text,registration:registration,widget:session,conversation:topicID)
        })
    }
    private func next(_ text:String,control:Bool=false) {
        guard owned else { return }
        model.memoryLearning.cancel()
        if assistant.sendProfile(model:model,topic:topicID,answer:text,control:control),!control { answer.wrappedValue=""; assistant.drafts.flush() }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                Label("Get to know you",systemImage:"person.crop.circle.badge.questionmark").font(.title2.bold())
                Spacer()
                Button("Close") { assistant.drafts.flush(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("One question at a time. We’ll build on what your PA already knows, and explore what’s missing.").foregroundStyle(.secondary)
            if !active {
                Spacer()
                VStack(alignment:.leading,spacing:12) {
                    Text("Build a useful picture of your life").font(.headline)
                    Text("Talk about what matters to you. Useful facts and connections are saved as you go. You can skip anything or finish whenever you like.").foregroundStyle(.secondary)
                    Button(session == nil ? "Start setup" : "Start another session") { model.memoryLearning.cancel(); _=assistant.beginSetup(model:model,topic:topicID) }.buttonStyle(.borderedProminent).disabled(!ready)
                }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:16))
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        Text("YOUR NEXT QUESTION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if working {
                            Text(assistant.toolStatus.isEmpty ? "Thinking…" : assistant.toolStatus).font(.title3)
                        } else if let reply,reply.completed {
                            Text(reply.content).font(.title3).textSelection(.enabled)
                        } else {
                            Text("Ready to continue when you are.").font(.title3)
                        }
                    }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:16))
                }.frame(minHeight:100,maxHeight:170)
                TextEditor(text:answer).font(.body).padding(8).frame(minHeight:120,maxHeight:180).background(.background,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(.quaternary)).focused($answerFocused).disabled(working || !owned || !assistant.drafts.writable)
                if let error=assistant.error,assistant.errorTopicID == topicID,assistant.errorProfileSessionID == session { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                if let notes=reply?.memoryNotes,!notes.isEmpty {
                    DisclosureGroup("Memory tool notes") { ScrollView { VStack(alignment:.leading) { ForEach(Array(notes.enumerated()),id:\.offset) { _,note in Text(note).font(.caption).foregroundStyle(.orange).textSelection(.enabled) } } }.frame(maxHeight:80) }.font(.caption)
                }
                HStack {
                    if working { Button("Stop") { assistant.cancel() } }
                    else {
                        Button("Skip question") { next("Skip this question and ask about a different useful area. This is a control, not a personal fact.",control:true) }.disabled(!ready)
                        if reply?.completed != true {
                            Button("Continue") { next("Continue the interview with one small question. Use the latest saved answer; do not invent or repeat a save already recorded. This is a control, not a personal fact.",control:true) }.disabled(!ready)
                        }
                    }
                    Spacer()
                    Button("Next") { next(answer.wrappedValue) }.buttonStyle(.borderedProminent).disabled(!ready || answer.wrappedValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || reply?.completed != true)
                }
                HStack {
                    Text("Answers stay saved. Memory uses supported facts, not a complete transcript.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Finish setup") { assistant.endSetup(topicID); assistant.drafts.flush(); dismiss() }
                }
            }
            if !assistant.memory.enabled { Text("Memory saving is off. Answers stay in this interview; enable memory in Settings to retain facts.").font(.caption).foregroundStyle(.orange) }
            if !model.chatGPT.inferenceVerified || model.chatGPT.usagePaused { Text("Verify your ChatGPT connection or check its usage in Settings to continue.").font(.caption).foregroundStyle(.secondary) }
        }.padding(28).frame(width:640,height:570)
        .onChange(of:working) { _,busy in if !busy { answerFocused=true } }
        .onChange(of:model.chatGPT.activeID) { dismiss() }
        .onDisappear { assistant.drafts.flush() }
    }
}
