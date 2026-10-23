import SwiftUI

struct LifeFocusPicker:View {
    @Binding var selection:[LifeArea]
    @State private var showing=false
    @Environment(\.workspacePalette) private var palette
    var body:some View {
        Button { showing.toggle() } label: {
            HStack(spacing:5) { Image(systemName:"scope");Text(LifeFocusRules.label(selection)).lineLimit(1) }
                .font(.caption.weight(.medium)).padding(.horizontal,10).padding(.vertical,6)
                .background(palette[.assistantBubble],in:Capsule())
        }.buttonStyle(.plain).help("Focus on one or more areas of your life").accessibilityLabel("Life focus: " + LifeFocusRules.label(selection))
            .popover(isPresented:$showing,arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:9) {
                    Text("Focus on your life").font(.headline)
                    Text("Choose several areas, or leave everything available. This keeps the same PA conversation.").font(.caption).foregroundStyle(.secondary)
                    Button("All areas") { selection=[] }.buttonStyle(.borderless)
                    ForEach(LifeArea.allCases.filter{$0 != .unsorted}) { area in
                        Toggle(isOn:Binding(get:{selection.contains(area)},set:{ enabled in
                            let values=enabled ? selection+[area] : selection.filter{$0 != area}
                            selection=LifeFocusRules.normalised(values.map(\.rawValue))
                        })) { Label(area.title,systemImage:area.symbol).foregroundStyle(area.colour) }
                            .toggleStyle(.checkbox)
                    }
                }.padding(16).frame(width:250)
            }
    }
}
