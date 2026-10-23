import Foundation

extension LifeNotebook {
    /// Read-only projection: original facts/evidence and saved record IDs remain authoritative.
    func integrating(_ items: [LifeItem], links itemLinks: [LifeItemLink]) -> LifeNotebook {
        let items=items.filter{$0.deletedAt == nil}
        let itemLinks=itemLinks.filter{edge in items.contains{$0.id == edge.from && $0.registration == edge.registration && $0.conversationID == edge.conversationID}}
        var result = self, mapping: [String:String] = [:]
        let facts=Dictionary(notes.flatMap(\.records).map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        var lineage: [UUID: Set<UUID>] = [:]
        for id in facts.keys {
            lineage[id, default: []].insert(id)
            for earlier in memoryHistory[id] ?? [] { lineage[earlier, default: []].insert(id) }
        }
        func currentFacts(for savedID:UUID)->Set<UUID> { lineage[savedID] ?? [] }
        func resolvedKind(_ item: LifeItem) -> LifeEntityKind {
            if item.kind == .space {
                // Generic folders have no inferred semantic type. An exact human-reviewed
                // identity can still represent a course/project in the memory notebook.
                let bound = entities.filter { entity in
                    entity.id != Self.selfID && entity.kind != .person && entity.kind != .concept &&
                    entity.id.hasPrefix((item.conversationID?.uuidString ?? "shared") + ":") &&
                    (item.notebookEntityID == entity.id || itemLinks.contains { edge in
                        edge.from == item.id && edge.relation == .identifies && edge.target.kind == .memory &&
                        edge.target.containerID == entity.id && UUID(uuidString: edge.target.id).map { !entity.memoryIDs.isDisjoint(with: currentFacts(for: $0)) } == true
                    })
                }
                return bound.count == 1 ? bound[0].kind : .concept
            }
            return switch item.kind { case .organisation: .organisation; case .course: .course; case .project: .project; case .person: .person; case .goal: .goal; default: .concept }
        }
        let kinds = Dictionary(uniqueKeysWithValues: items.map { ($0.id, resolvedKind($0)) })
        func kind(_ item: LifeItem) -> LifeEntityKind { kinds[item.id] ?? .concept }
        for entity in entities where entity.id != Self.selfID {
            let exact = items.filter { $0.kind != .space && kind($0) == entity.kind && entity.kind != .person && entity.kind != .concept && Self.key($0.title) == Self.key(entity.label) && entity.id.hasPrefix(($0.conversationID?.uuidString ?? "shared") + ":") }
            let explicit = itemLinks.filter { edge in edge.relation == .identifies && edge.target.kind == .memory && edge.target.containerID == entity.id && UUID(uuidString:edge.target.id).map{!entity.memoryIDs.isDisjoint(with:currentFacts(for:$0))} == true }.compactMap { edge in items.first { $0.id == edge.from && kind($0) == entity.kind } }
            let materialised=items.filter{$0.notebookEntityID == entity.id && kind($0) == entity.kind}
            let candidates = !explicit.isEmpty ? explicit : !materialised.isEmpty ? materialised : exact
            if Set(candidates.map(\.id)).count == 1, let item = candidates.first { mapping[entity.id] = "life:" + item.id.uuidString }
        }
        var merged: [String:LifeEntity] = [:]
        for var entity in entities {
            entity.id = mapping[entity.id] ?? entity.id
            if var old = merged[entity.id] { old.memoryIDs.formUnion(entity.memoryIDs);old.areas.formUnion(entity.areas);merged[entity.id]=old } else { merged[entity.id]=entity }
        }
        for item in items {
            let id = "life:" + item.id.uuidString
            var entity = merged[id] ?? .init(id:id,label:item.title,kind:kind(item),areas:[],memoryIDs:[])
            for reference in itemLinks.filter({$0.from == item.id && $0.target.kind == .memory}) {
                if let savedID=UUID(uuidString:reference.target.id) { entity.memoryIDs.formUnion(currentFacts(for:savedID)) }
            }
            entity.label=item.title;entity.kind=kind(item);entity.areas.formUnion(LifeWorkspaceRules.navigationAreas(item,in:items));merged[id]=entity
        }
        result.entities=merged.values.sorted { $0.id < $1.id }
        result.links=links.map { edge in var edge=edge;edge.from=mapping[edge.from] ?? edge.from;edge.to=mapping[edge.to] ?? edge.to;return edge }
        result.anchors=items.map { item in
            .init(id:"life:"+item.id.uuidString,label:item.title,kind:item.kind.workspaceKind.rawValue,parent:item.parentID.map { "life:"+$0.uuidString },areas:Array(merged["life:"+item.id.uuidString]?.areas ?? []).sorted{$0.rawValue < $1.rawValue},notes:String(item.searchableNotes.prefix(600)),path:LifeItemQuery.path(item,in:items).map(\.title),relations:itemLinks.filter{edge in edge.from == item.id && edge.target.kind == .item && items.contains(where:{$0.id.uuidString == edge.target.id})}.map{$0.relation.rawValue+":"+$0.target.id},memoryIDs:merged["life:"+item.id.uuidString]?.memoryIDs ?? [])
        }
        for area in Set(result.anchors.flatMap(\.areas)) where !result.notes.contains(where:{$0.area == area}) { result.notes.append(.init(area:area,records:[])) }
        return result
    }
}
