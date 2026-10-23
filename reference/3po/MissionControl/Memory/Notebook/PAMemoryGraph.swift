import Foundation
struct MemoryGraphNode: Identifiable, Equatable { var id:String; var label:String }
struct MemoryGraphEdge: Identifiable, Equatable {
    var id:String; var from:String; var to:String; var relation:String; var memoryID:UUID; var evidence:String; var inferred:Bool
}
struct PAMemoryGraph {
    var nodes:[MemoryGraphNode]
    var edges:[MemoryGraphEdge]
    var omittedEdges:Int
    static func key(_ label:String)->String { label.lowercased().split(whereSeparator:{$0.isWhitespace}).joined(separator:" ") }
    static func build(_ records:[PAMemory],registration:String,topic:UUID?,now:Date = .now,maxNodes:Int = 12)->Self {
        var labels:[String:String]=[:],edges:[MemoryGraphEdge]=[],omitted=0
        let permitted=records.filter { MemoryRules.usable($0,registration:registration,now:now) && MemoryRules.inScope($0,conversationID:topic) }.sorted { $0.id.uuidString < $1.id.uuidString }
        for record in permitted {
            for (i,value) in (record.connections ?? []).prefix(4).enumerated() {
                let from=key(value.subject),to=key(value.object)
                guard !from.isEmpty,!to.isEmpty,!value.relation.isEmpty else { continue }
                let new=Set([from,to]).subtracting(labels.keys)
                guard edges.count < 80,labels.count+new.count <= max(1,min(40,maxNodes)) else { omitted+=1; continue }
                if labels[from] == nil { labels[from]=value.subject }
                if labels[to] == nil { labels[to]=value.object }
                edges.append(.init(id:record.id.uuidString+":"+String(i),from:from,to:to,relation:value.relation,memoryID:record.id,evidence:value.evidence,inferred:!record.explicit && record.certainty != .stated))
            }
        }
        return .init(nodes:labels.map { .init(id:$0.key,label:$0.value) }.sorted {$0.id < $1.id},edges:edges,omittedEdges:omitted)
    }
}
