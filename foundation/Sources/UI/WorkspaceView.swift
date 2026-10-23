import SwiftUI

struct WorkspaceView: View {
    @Bindable var model: FoundationModel
    @Environment(\.colorScheme) private var colorScheme
    private var theme: WorkspaceTheme { .current(dark: colorScheme == .dark) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Rectangle().fill(theme.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(theme.line).frame(height: 1)
                Group {
                    switch model.selection {
                    case "today": today
                    case "settings": settings
                    default: chat
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.notice.isEmpty {
                    Text(model.notice).font(.callout).foregroundStyle(theme.ink).textSelection(.enabled)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(theme.user)
                }
            }.background(theme.canvas)
        }.foregroundStyle(theme.ink).tint(theme.accent)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").font(.title2).foregroundStyle(theme.accent)
                Text(AppIdentity.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
            }.padding(.top, 26)
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR SPACE").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2).opacity(0.5).padding(.bottom, 8)
                navigation("Conversation", icon: "bubble.left.and.bubble.right", id: "chat")
                navigation("Today", icon: "sun.max", id: "today")
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                Text("A little more room\nfor what matters.").font(.system(size: 15, weight: .medium, design: .serif)).lineSpacing(4).opacity(0.65)
                navigation("Settings", icon: "slider.horizontal.3", id: "settings").padding(.top, 12)
                Text(model.preview ? "Fictional preview" : "Your personal workspace").font(.caption2).opacity(0.45)
            }.padding(.bottom, 20)
        }.padding(.horizontal, 20).background(theme.sidebar)
    }
    private func navigation(_ label: String, icon: String, id: String) -> some View {
        Button { model.selection = id } label: {
            Label(label, systemImage: icon).font(.system(size: 13, weight: model.selection == id ? .semibold : .regular))
                .padding(.vertical, 11).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(model.selection == id ? theme.card.opacity(0.85) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.selection == "chat" ? "A place to think clearly." : model.selection == "today" ? "Make space for today." : "Make yourself at home.")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                Text(model.selection == "chat" ? "Think it through. Find a next step." : model.selection == "today" ? "A simple brief, shaped by what you share." : "Your account and your workspace.")
                    .font(.system(size: 12)).opacity(0.55)
            }
            Spacer()
            Label(model.preview ? "PREVIEW" : model.connection?.hasSession == true ? "CONNECTED" : "YOUR SPACE", systemImage: "circle.fill")
                .font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(theme.accent)
                .padding(.horizontal, 12).padding(.vertical, 8).background(theme.user, in: Capsule())
        }.padding(.horizontal, 30).padding(.vertical, 24)
    }
    private var chat: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 0) {
                HStack { Label("Conversation", systemImage: "bubble.left").font(.system(size: 13, weight: .semibold)); Spacer(); Text("JUST BETWEEN YOU & YOUR SPACE").font(.system(size: 8, weight: .medium)).tracking(1).opacity(0.4) }
                    .padding(20)
                Rectangle().fill(theme.line).frame(height: 1)
                if model.preview {
                    previewConversation
                } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        ConversationStack(lazy: !model.preview) {
                            if model.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Image(systemName: "sparkles").font(.title).foregroundStyle(theme.accent)
                                    Text("What would you like to make room for?").font(.system(size: 23, weight: .medium, design: .serif))
                                    Text("Bring a question, an idea or the shape of your day.").font(.callout).opacity(0.6)
                                    if model.connection?.hasSession != true { Button("Connect in Settings") { model.selection = "settings" }.buttonStyle(.bordered) }
                                }.padding(.vertical, 30)
                            }
                            ForEach(model.messages) { message in
                                messageRow(message)
                            }
                            if model.isRunning {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(AppIdentity.name.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(theme.accent)
                                    Text(model.liveText.isEmpty ? "Thinking…" : model.liveText).font(.system(size: 14)).lineSpacing(5)
                                }.id("live")
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(24)
                    }.onChange(of: model.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
                        .onChange(of: model.liveText) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                }
                HStack(alignment: .bottom, spacing: 12) {
                    if model.preview {
                        Text("What's on your mind?").foregroundStyle(theme.ink.opacity(0.4)).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField("What's on your mind?", text: $model.draft, axis: .vertical).textFieldStyle(.plain).lineLimit(1...5)
                            .disabled(model.storageBlocked || model.connection?.hasSession != true).onSubmit { model.send() }
                    }
                    Button { model.isRunning ? model.stop() : model.send() } label: {
                        Image(systemName: model.isRunning ? "stop.fill" : "arrow.up").font(.system(size: 12, weight: .bold))
                            .frame(width: 31, height: 31).foregroundStyle(theme.card).background(theme.accent, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).disabled(!model.isRunning && (!model.ready || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }.padding(14).background(theme.canvas, in: RoundedRectangle(cornerRadius: 12)).padding(18)
            }.background(theme.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.line, lineWidth: 1))
            briefCard.frame(width: 260)
        }.padding(28)
    }
    private var previewConversation: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(model.messages) { message in messageRow(message) }
            Spacer(minLength: 0)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func messageRow(_ message: ChatMessage) -> some View {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(message.role == "user" ? "YOU" : AppIdentity.name.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(theme.accent)
                                    Text(message.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                                    if !message.completed { Text("Interrupted response").font(.caption2).opacity(0.55) }
                                }.padding(message.role == "user" ? 16 : 0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(message.role == "user" ? theme.user.opacity(0.7) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                                    .id(message.id)
    }
    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: "sun.max").foregroundStyle(theme.accent); Text(model.brief.map { Calendar.current.isDateInToday($0.created) } == false && !model.preview ? "LATEST BRIEF" : "TODAY'S BRIEF").font(.system(size: 10, weight: .semibold)).tracking(1.5); Spacer() }
            Text(model.preview ? "Friday, 23 October" : (model.brief?.created ?? Date.now).formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.system(size: 12)).opacity(0.5)
            Text("One good thing\nat a time.").font(.system(size: 27, weight: .medium, design: .serif)).lineSpacing(4)
            Rectangle().fill(theme.line).frame(height: 1)
            if let brief = model.brief {
                Text(brief.text).font(.system(size: 13)).lineSpacing(6)
                if !model.preview { Text("Generated " + brief.created.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).opacity(0.5) }
            }
            else { Text("Share your priorities, then ask for a little clarity for the day.").font(.callout).lineSpacing(5).opacity(0.7) }
            Button("Open today", systemImage: "arrow.up.right") { model.selection = "today" }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent).padding(.top, 10)
            Text("Based on what you've shared.").font(.system(size: 10)).opacity(0.45)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(theme.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.line, lineWidth: 1))
    }
    private var today: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("What matters today?").font(.system(size: 24, weight: .medium, design: .serif))
                    Text("A few priorities are enough. Add anything you'd like your brief to consider.").font(.callout).opacity(0.6)
                    TextEditor(text: $model.priorities).font(.body).frame(minHeight: 140).padding(10).scrollContentBackground(.hidden)
                        .background(theme.canvas, in: RoundedRectangle(cornerRadius: 10)).disabled(model.preview || model.storageBlocked || model.connection?.hasSession != true)
                    Button("Generate today's brief", systemImage: "sparkles") { model.generateBrief() }.buttonStyle(.borderedProminent).disabled(!model.ready)
                    Text("Generated when you ask. Uses your priorities and recent conversation.").font(.caption).opacity(0.55)
                    if model.isRunning { ProgressView(); Button("Stop") { model.stop() } }
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading).background(theme.card, in: RoundedRectangle(cornerRadius: 18))
                briefCard.frame(width: 300)
            }.padding(28)
        }
    }
    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let connection = model.connection {
                    ConnectionPanel(connection: connection).disabled(model.isRunning)
                } else {
                    Label("This preview uses fictional information.", systemImage: "eye").font(.title3)
                    Text("Open the app normally when you're ready to connect your own ChatGPT account.").opacity(0.6)
                }
                Divider()
                Text("Your information").font(.headline)
                Text("Conversations, drafts, priorities and briefs are saved on this Mac, separately for each connected account. Credentials are held in Keychain. Messages and the context needed to answer them are sent to your connected model. No external sources or background jobs are connected yet.").font(.callout).lineSpacing(5)
                Text("Recent completed conversation is supplied for continuity. Interrupted responses are excluded. Local workspace files are not encrypted by this app.").font(.caption).opacity(0.6)
            }.padding(30).frame(maxWidth: 780, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ConnectionPanel: View {
    @Bindable var connection: ChatGPTConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your ChatGPT account").font(.system(size: 24, weight: .medium, design: .serif))
            Text("Connect your own eligible ChatGPT subscription. Requests use your plan allowance.").font(.callout).foregroundStyle(.secondary)
            if !connection.accounts.isEmpty {
                Picker("Account", selection: $connection.activeID) { ForEach(connection.accounts) { Text($0.name).tag($0.id) } }
                    .disabled(connection.busy).onChange(of: connection.activeID) { connection.switchAccount() }
            }
            HStack {
                Button("Continue with ChatGPT") { connection.signIn() }.buttonStyle(.borderedProminent).disabled(connection.busy)
                if !connection.accounts.isEmpty { Button("Add account") { connection.signIn(addAccount: true) }.disabled(connection.busy) }
                if connection.busy { ProgressView().controlSize(.small); Button("Cancel") { connection.cancel() } }
            }
            if !connection.models.isEmpty {
                Picker("Model", selection: $connection.selectedModel) { Text("Choose a model").tag(""); ForEach(connection.models) { Text($0.name).tag($0.id) } }
                    .disabled(connection.busy).onChange(of: connection.selectedModel) { connection.selectionChanged() }
            }
            HStack {
                Button("Refresh models") { connection.refreshModels() }
                Button("Check access · 1 request") { connection.testConnection() }
                Button("Sign out") { connection.signOut() }
            }.disabled(connection.busy || !connection.hasSession)
            Text(connection.message).font(.callout).textSelection(.enabled)
            if !connection.diagnostic.isEmpty { DisclosureGroup("Last connection issue") { Text(connection.diagnostic).font(.caption).textSelection(.enabled) } }
            Link("Manage ChatGPT usage and app access", destination: URL(string: "https://chatgpt.com/settings/usage")!).font(.callout)
            Text("Sign-in and model discovery do not confirm inference. The explicit access check sends one short request before chat is enabled.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ConversationStack<Content: View>: View {
    let lazy: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        if lazy { LazyVStack(alignment: .leading, spacing: 22, content: content) }
        else { VStack(alignment: .leading, spacing: 22, content: content) }
    }
}
