import SwiftUI

struct LifeCanonicalMapView:View {
    var notebook:LifeNotebook
    var focus:[LifeArea]
    var open:(UUID)->Void
    @Environment(\.workspacePalette) private var palette
    private var anchors:[LifeNotebookAnchor] {
        guard !focus.isEmpty else { return notebook.anchors }
        let matched=notebook.anchors.filter{!Set($0.areas).isDisjoint(with:focus)}
        var ids=Set(matched.map(\.id))
        for node in matched { var cursor=node.parent;while let id=cursor,ids.insert(id).inserted { cursor=notebook.anchors.first{$0.id == id}?.parent } }
        return notebook.anchors.filter{ids.contains($0.id)}
    }
    private var ordered:[LifeNotebookAnchor] {
        let values=anchors
        var output:[LifeNotebookAnchor]=[]
        func visit(_ parent:String?) { for node in values.filter({$0.parent == parent}) { output.append(node);visit(node.id) } }
        visit(nil);return output
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:8) {
                Label(notebook.selfLabel,systemImage:"person.crop.circle.fill").font(.headline).foregroundStyle(palette[.accent]).padding(.bottom,6)
                ForEach(Array(ordered.prefix(80)),id:\.id) { node in
                    Button { if let id=UUID(uuidString:String(node.id.dropFirst(5))) { open(id) } } label: {
                        HStack(alignment:.top,spacing:8) {
                            Image(systemName:LifeItemKind(rawValue:node.kind)?.symbol ?? "circle").foregroundStyle(node.areas.first?.colour ?? palette[.accent]).frame(width:18)
                            VStack(alignment:.leading,spacing:4) {
                                Text(node.label).font(.callout.weight(.semibold)).foregroundStyle(palette[.text]).lineLimit(2)
                                if !node.relations.isEmpty {
                                    ForEach(Array(node.relations.prefix(3)),id:\.self) { relation in
                                        let parts=relation.split(separator:":",maxSplits:1).map(String.init)
                                        if parts.count == 2,let target=notebook.anchors.first(where:{$0.id == "life:"+parts[1]}) { Text((LifeRelation(rawValue:parts[0])?.title ?? "Related to")+" "+target.label).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                    }
                                }
                                let facts=node.memoryIDs.count
                                if facts > 0 { Text("\(facts) linked \(facts == 1 ? "fact" : "facts")").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }.padding(9).background(palette[.input].opacity(0.65),in:RoundedRectangle(cornerRadius:9))
                    }.buttonStyle(.plain).padding(.leading,CGFloat(min(6,max(0,node.path.count-1)))*12)
                }
                if ordered.count > 80 { Text("Showing 80 items. Use Structure search to narrow the map.").font(.caption).foregroundStyle(.secondary) }
                let other=notebook.notes.filter{focus.isEmpty || focus.contains($0.area)}
                if !other.isEmpty {
                    Text("Other life context").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top,8)
                    ForEach(other) { note in
                        DisclosureGroup { ForEach(Array(note.records.prefix(8))) { record in Text(record.text).font(.caption).textSelection(.enabled).padding(.vertical,3) } } label: { Label(note.area.title,systemImage:note.area.symbol).font(.callout).foregroundStyle(note.area.colour) }
                    }
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
