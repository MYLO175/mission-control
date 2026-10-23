import SwiftUI
struct PAMemoryGraphView: View {
    var graph:PAMemoryGraph
    var records:[PAMemory]
    var inspect:(PAMemory)->Void
    var height:CGFloat = 350
    @State private var selected:String?
    private func position(_ i:Int,_ count:Int,_ size:CGSize)->CGPoint {
        if count == 1 { return .init(x:size.width/2,y:size.height/2) }
        let angle=Double(i)*2*Double.pi/Double(max(count,1))-Double.pi/2
        return .init(x:size.width/2+cos(angle)*max(0,size.width/2-72),y:size.height/2+sin(angle)*max(0,size.height/2-42))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Recorded connections" + (graph.omittedEdges > 0 ? " · showing a bounded map" : "")).font(.headline)
            Text("Select a node to inspect its evidence. Dashed links are provisional. This shows recorded connections, not everything the PA knows.").font(.caption).foregroundStyle(.secondary)
            if graph.nodes.isEmpty { ContentUnavailableView("No connections recorded yet",systemImage:"point.3.connected.trianglepath.dotted",description:Text("As useful facts are learned from your conversations, their connections appear here.")) }
            else {
                GeometryReader { geometry in
                    let points=Dictionary(uniqueKeysWithValues:graph.nodes.enumerated().map { ($0.element.id,position($0.offset,graph.nodes.count,geometry.size)) })
                    ZStack {
                        Canvas { context,size in
                            for edge in graph.edges {
                                guard let from=points[edge.from],let to=points[edge.to] else { continue }
                                var path=Path(); path.move(to:from); path.addLine(to:to)
                                context.stroke(path,with:.color(selected == edge.from || selected == edge.to ? .accentColor : .secondary.opacity(0.3)),style:StrokeStyle(lineWidth:1.5,dash:edge.inferred ? [4,4] : []))
                            }
                        }.accessibilityHidden(true)
                        ForEach(graph.nodes) { node in
                            Button { selected=node.id } label: {
                                Text(node.label).font(.caption.weight(.medium)).lineLimit(2).multilineTextAlignment(.center).padding(8).frame(width:120).background(selected == node.id ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain).position(points[node.id] ?? .zero).accessibilityLabel("Inspect " + node.label)
                        }
                    }
                }.frame(height:height)
                if let selected {
                    ForEach(graph.edges.filter { $0.from == selected || $0.to == selected }) { edge in
                        VStack(alignment:.leading,spacing:5) {
                            Text((graph.nodes.first{$0.id == edge.from}?.label ?? edge.from) + " → " + edge.relation + " → " + (graph.nodes.first{$0.id == edge.to}?.label ?? edge.to)).font(.callout.weight(.medium))
                            Text("“"+edge.evidence+"”").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if let record=records.first(where:{$0.id == edge.memoryID}) { Button("Inspect memory") { inspect(record) }.controlSize(.small) }
                        }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                    }
                }
            }
        }
    }
}
