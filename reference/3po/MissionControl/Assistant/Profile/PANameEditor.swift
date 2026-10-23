import SwiftUI

struct PANameSetting:View {
    @Bindable var assistant:AssistantService
    @State private var showing=false
    var body:some View {
        Button("Name your PA…") { showing=true }.sheet(isPresented:$showing) { PANameEditor(assistant:assistant) }
    }
}
struct PANameEditor:View {
    @Bindable var assistant:AssistantService
    @Environment(\.dismiss) private var dismiss
    @State private var draft=""
    @FocusState private var focused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Name your PA").font(.title2.weight(.semibold))
            Text("Choose a name that feels right. Your conversations, topics and memory stay with the same assistant.").font(.callout).foregroundStyle(.secondary)
            TextField("For example, 3PO",text:$draft).textFieldStyle(.roundedBorder).focused($focused)
            if PAIdentity.validated(draft) == nil { Text("Use a name of 1–40 characters on one line.").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Use Your PA") { draft=PAIdentity.defaultName }
                Spacer();Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { if let name=PAIdentity.validated(draft) { assistant.displayName=name;dismiss() } }.keyboardShortcut(.defaultAction).disabled(PAIdentity.validated(draft) == nil)
            }
        }.padding(24).frame(width:420).onAppear { draft=assistant.displayName;focused=true }
    }
}
