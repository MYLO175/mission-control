import Foundation
@main struct Checks {
    static func main() throws {
        let topic=UUID(),other=UUID()
        let quote="My family chat is The Zoo"
        var record=PAMemory(registration:"one",text:quote,kind:.context,provenance:"Human",connections:[.init(subject:"You",relation:"family chat",object:"The Zoo",evidence:quote)])
        let shared=PAMemoryGraph.build([record],registration:"one",topic:nil)
        precondition(shared.nodes.count == 2 && shared.edges.count == 1 && shared.edges[0].evidence == quote)
        record.conversationID=topic
        precondition(PAMemoryGraph.build([record],registration:"one",topic:nil).nodes.isEmpty)
        precondition(PAMemoryGraph.build([record],registration:"one",topic:other).nodes.isEmpty)
        precondition(PAMemoryGraph.build([record],registration:"two",topic:topic).nodes.isEmpty)
        precondition(PAMemoryGraph.build([record],registration:"one",topic:topic).nodes.count == 2)
        record.resolved = .now
        precondition(PAMemoryGraph.build([record],registration:"one",topic:topic).nodes.isEmpty)
        record.resolved=nil;record.explicit=false;record.certainty = .inferred
        precondition(PAMemoryGraph.build([record],registration:"one",topic:topic).edges[0].inferred)
        let records=(0..<20).map { i in PAMemory(registration:"one",text:"Project \(i)",kind:.context,provenance:"Human",connections:[.init(subject:"You",relation:"project",object:"Project \(i)",evidence:"I work on project \(i)")]) }
        let bounded=PAMemoryGraph.build(records,registration:"one",topic:nil)
        precondition(bounded.nodes.count <= 12 && bounded.omittedEdges > 0)
        precondition(bounded.edges == PAMemoryGraph.build(records.reversed(),registration:"one",topic:nil).edges)
        let reload=try JSONDecoder().decode(PAMemory.self,from:JSONEncoder().encode(record))
        precondition(reload.connections == record.connections)
        print("PASS: graph account/topic isolation, evidence, resolved omission, inferred links, bounded deterministic projection and relation persistence")
    }
}
