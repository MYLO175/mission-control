import SwiftUI

struct WhatsAppSourceSummary:View {
    @Bindable var service:WhatsAppService
    let registration:String
    var heartbeatReviewEnabled=false
    private var access:WhatsAppAccess { service.access(for:registration) }
    private var selected:[WhatsAppChat] { WhatsAppReadRules.selectedChats(service.chats,selected:access.chats) }
    var body:some View {
        VStack(alignment:.leading,spacing:5) {
            Text("\(selected.count) selected chats · PA access \(access.enabled ? "on" : "off")").font(.subheadline.weight(.medium))
            if selected.isEmpty { Text("Choose the chats you want to share with your PA.").foregroundStyle(.secondary) }
            else { Text(selected.prefix(8).map(\.name).joined(separator:" · ") + (selected.count > 8 ? " · +\(selected.count-8) more" : "")).lineLimit(3) }
            HStack(spacing:12) {
                Label("Brief",systemImage:access.briefEnabled ? "checkmark.circle.fill" : "minus.circle")
                Label("Tasks",systemImage:access.enabled && access.includeInSuggestions == true ? "checkmark.circle.fill" : "minus.circle")
                Label("Learning",systemImage:access.enabled && (access.learnContext == true || access.briefEnabled || access.includeInSuggestions == true || heartbeatReviewEnabled) ? "checkmark.circle.fill" : "minus.circle")
            }.foregroundStyle(.secondary)
        }.font(.caption).padding(10).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
    }
}

struct WhatsAppSourcePicker: View {
    @Bindable var service: WhatsAppService
    let registration: String
    var heartbeatReviewEnabled=false
    @Environment(\.dismiss) private var dismiss
    @State private var search=""
    @State private var selectedOnly=false
    @State private var details=false
    private var access:WhatsAppAccess { service.access(for:registration) }
    private var selected:[WhatsAppChat] { WhatsAppReadRules.selectedChats(service.chats,selected:access.chats) }
    private var visible:[WhatsAppChat] {
        (selectedOnly ? selected : service.chats).filter { search.isEmpty || ($0.name+" "+$0.id).localizedCaseInsensitiveContains(search) }
    }
    private var counts:[String:Int] { Dictionary(service.messages.map { ($0.chat,1) },uniquingKeysWith:+) }
    private func change(_ edit:(inout WhatsAppAccess)->Void) { var next=access;edit(&next);service.setAccess(next,registration:registration) }
    var body:some View {
        let messageCounts=counts
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("WhatsApp sources").font(.title2.bold());Spacer();Button("Done") { dismiss() } }
            Text("Share only the chats you choose. Names and requested text use your ChatGPT connection; linked-device history can be partial.").font(.callout).foregroundStyle(.secondary)
            Toggle("Allow PA access",isOn:Binding(get:{access.enabled},set:{value in change { $0.enabled=value } }))
            HStack(spacing:20) {
                Toggle("Today’s brief",isOn:Binding(get:{access.includeInBrief == true},set:{value in change { $0.includeInBrief=value } }))
                Toggle("Task suggestions",isOn:Binding(get:{access.includeInSuggestions == true},set:{value in change { $0.includeInSuggestions=value } }))
                if access.briefEnabled || access.includeInSuggestions == true || heartbeatReviewEnabled {
                    Label("Learning included",systemImage:"checkmark.circle").help("Review access includes learning from selected chats. Allow memory learning in Memory settings controls whether learning runs.")
                } else {Toggle("Learn context",isOn:Binding(get:{access.learnContext == true},set:{value in change { $0.learnContext=value } }))}
            }.disabled(!access.enabled)
            DisclosureGroup("How these sources are used",isExpanded:$details) {
                ScrollView { Text("Brief: includes up to 40 cached messages from the last 48 hours, shortened to 800 characters each, in your existing morning preparation or explicit update. Tasks: optional idle checks compare up to eight recent messages with Calendar and Reminders; suggestions are reviewed before anything is created. Learning: review access includes small recent batches; useful conclusions retain evidence and remain provisional and editable. Allow memory learning in Memory settings controls automatic learning. Revoking source access excludes dependent beliefs from recall while preserving them locally. Reception makes no AI requests. Messages never authorise Calendar/Reminders changes. No sending, read receipts or full-history guarantee.").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:100)
            }.font(.caption)
            WhatsAppSourceSummary(service:service,registration:registration,heartbeatReviewEnabled:heartbeatReviewEnabled)
            HStack {
                TextField("Find a name or chat",text:$search)
                Picker("Show chats",selection:$selectedOnly) { Text("All chats").tag(false);Text("Selected (\(selected.count))").tag(true) }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Show chats").frame(width:230)
            }
            List(visible) { chat in
                Toggle(isOn:Binding(get:{access.chats.contains(chat.id)},set:{value in change { if value { $0.chats.insert(chat.id) } else { $0.chats.remove(chat.id) } } })) {
                    HStack {
                        Label(chat.name,systemImage:chat.group ? "person.2" : "person")
                        Spacer()
                        Text((messageCounts[chat.id] ?? 0) > 0 ? "\(messageCounts[chat.id] ?? 0) cached" : "No cached text").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical,3)
            }.overlay { if visible.isEmpty { ContentUnavailableView(selectedOnly ? "No selected chats" : "No matching chats",systemImage:"bubble.left",description:Text("Names appear as WhatsApp shares contacts with this linked device.")) } }
            if !service.namesStatus.isEmpty { Text(service.namesStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            HStack {
                Button(service.namesBusy ? "Refreshing names…" : "Refresh names") { service.refreshNames() }.disabled(!service.connected || service.namesBusy).help("Recover saved contact labels from WhatsApp; no message history or AI request")
                Text("\(service.chats.count) available · new chats stay excluded").font(.caption).foregroundStyle(.secondary)
                Spacer();Button("Clear selection") { change { $0.chats=[] } }.disabled(access.chats.isEmpty)
            }
        }.padding(20).frame(width:680,height:620)
        .onAppear { selectedOnly = !access.chats.isEmpty }
    }
}
