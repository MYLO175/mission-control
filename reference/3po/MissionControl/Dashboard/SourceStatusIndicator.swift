import SwiftUI

/// Keeps routine connection details available without a permanent header row.
struct SourceStatusIndicator: View {
    var title: String
    var health: SourceHealth
    var coverage:String? = nil
    var refresh:(()->Void)? = nil
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Group {
                if health.loading { ProgressView().controlSize(.mini) }
                else { Circle().fill(health.error != nil ? Color.orange : health.lastSuccess == nil ? Color.secondary : Color.green.opacity(0.75)).frame(width:6,height:6) }
            }.frame(width:16,height:20).contentShape(Rectangle())
        }.buttonStyle(.borderless).help(health.detail).accessibilityLabel(title + " status: " + health.detail)
            .popover(isPresented:$showing) {
                VStack(alignment:.leading,spacing:8) {
                    Text(title).font(.headline)
                    Text(health.detail).font(.callout).textSelection(.enabled)
                    if let coverage,!coverage.isEmpty {Text(coverage).font(.caption).foregroundStyle(.secondary)}
                    if let refresh {Button(health.error == nil ? "Refresh now" : "Retry now") {showing=false;refresh()}.disabled(health.loading)}
                    if let date = health.lastSuccess { Text("Last successful refresh " + date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth:320,alignment:.leading)
            }
    }
}
