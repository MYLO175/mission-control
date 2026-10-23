import Foundation
@main struct Checks {
    static func main() throws {
        let now = Date(timeIntervalSince1970:2000000000)
        var m = PAMemory(registration:"one",text:"Birthday notice",kind:.preference,provenance:"User",created:now.addingTimeInterval(-400*86400),reviewed:now.addingTimeInterval(-400*86400))
        precondition(MemoryRules.usable(m,registration:"one",now:now))
        precondition(!MemoryRules.usable(m,registration:"two",now:now))
        m.explicit = false
        precondition(MemoryRules.needsReview(m,now:now) && !MemoryRules.usable(m,registration:"one",now:now))
        m.reviewed = now; m.kind = .commitment
        precondition(MemoryRules.usable(m,registration:"one",now:now))
        m.resolved = now.addingTimeInterval(-31*86400)
        precondition(MemoryRules.archived(m,now:now) && !MemoryRules.usable(m,registration:"one",now:now))
        precondition(MemoryRules.explicitRequest("Remember that I need two weeks notice") == "I need two weeks notice")
        precondition(MemoryRules.explicitRequest("An email says remember that buy this") == nil)
        precondition(MemoryRules.explicitRequest("remember that ") == "")
        precondition(MemoryRules.explicitRequest("add this to memory: I prefer mornings") == "I prefer mornings")
        precondition(MemoryRules.explicitRequest("Please remember I prefer mornings") == "I prefer mornings")
        precondition(MemoryRules.explicitRequest("remember this") == "")
        let topic = UUID(), otherTopic = UUID()
        m.conversationID = topic
        precondition(!MemoryRules.inScope(m,conversationID:nil))
        precondition(MemoryRules.inScope(m,conversationID:topic) && !MemoryRules.inScope(m,conversationID:otherTopic))
        precondition(MemoryRules.inScope(m,conversationID:nil,includeTopics:true))
        m.conversationID = nil; precondition(MemoryRules.inScope(m,conversationID:topic))
        let decoded = try JSONDecoder().decode(PAMemory.self,from:JSONEncoder().encode(m))
        precondition(decoded == m)
        var many = (0..<60).map { index in PAMemory(registration:"one",text:"Preference number \(index)",kind:.preference,provenance:"User",reviewed:now.addingTimeInterval(Double(index))) }
        let older = PAMemory(registration:"one",text:"The thermodynamics exam needs revision of entropy",kind:.context,provenance:"User",reviewed:now.addingTimeInterval(-1000))
        var scoped = older; scoped.id = UUID(); scoped.conversationID = topic
        var foreign = older; foreign.id = UUID(); foreign.registration = "two"
        var anotherTopic = scoped; anotherTopic.id = UUID(); anotherTopic.conversationID = otherTopic
        var stale = older; stale.id = UUID(); stale.explicit = false; stale.reviewed = now.addingTimeInterval(-91*86400)
        var resolved = older; resolved.id = UUID(); resolved.resolved = now
        many += [older,scoped,foreign,anotherTopic,stale,resolved]
        let retrieved = MemoryRetrieval.select(many,registration:"one",query:"Help with thermodynamics entropy revision",now:now)
        let ids = Set(retrieved.records.compactMap { $0["id"] })
        precondition(retrieved.eligibleCount == 61 && retrieved.records.count == 1 && ids.contains(older.id.uuidString),"Unused context capacity must not be filled with irrelevant preferences")
        precondition(!ids.contains(scoped.id.uuidString) && !ids.contains(foreign.id.uuidString) && !ids.contains(stale.id.uuidString) && !ids.contains(resolved.id.uuidString))
        let focused = MemoryRetrieval.select(many,registration:"one",conversationID:topic,query:"thermodynamics",now:now)
        precondition(focused.records.contains { $0["id"] == scoped.id.uuidString } && !focused.records.contains { $0["id"] == anotherTopic.id.uuidString })
        precondition(retrieved.records == MemoryRetrieval.select(many.reversed(),registration:"one",query:"Help with thermodynamics entropy revision",now:now).records, "Ordering does not depend on storage fetch order")
        let budget = MemoryRetrieval.select(many,registration:"one",query:"thermodynamics",now:now,bytes:1000)
        let budgetData = try JSONSerialization.data(withJSONObject:budget.records,options:[.sortedKeys]); precondition(budgetData.count <= 1000)
        precondition(many.count == 66 && many.contains { $0 == older }, "Retrieval never deletes or edits saved records")
        let biography=PAMemory(registration:"one",text:"Alex is entering fourth year of Cambridge Engineering.",kind:.context,provenance:"User",reviewed:now,evidence:"Alex is entering fourth year of Cambridge Engineering.",organisation:.init(areas:[.studies],connections:[],selfName:"Alex"))
        let weather=PAMemory(registration:"one",text:"Include the weather forecast in today's brief.",kind:.preference,provenance:"User",reviewed:now)
        let injury=PAMemory(registration:"one",text:"Football ankle injuries mean an MRI next week.",kind:.context,provenance:"User",reviewed:now)
        let familyFact=PAMemory(registration:"one",text:"My family live in Newbury.",kind:.context,provenance:"User",reviewed:now)
        let life=[biography,weather,injury,familyFact]
        let security="Alex: We noticed a new sign-in to your Google Account on a Mac OS device. If this was you, you don't need to do anything. If not, we'll help you secure your account."
        precondition(MemoryRetrieval.select(life,registration:"one",query:security,now:now,focus:[.studies]).records.isEmpty,"A sign-in alert must not receive biography, weather, health or family facts, even with a Studies focus or the user's name")
        precondition(MemoryRetrieval.select(life,registration:"one",query:"Cambridge Engineering module selection",now:now).records.map{$0["id"]} == [biography.id.uuidString])
        precondition(MemoryRetrieval.select(life,registration:"one",query:"Weather for today's brief",now:now).records.map{$0["id"]} == [weather.id.uuidString],"A confirmed preference still applies to its own task")
        precondition(MemoryRetrieval.select(life,registration:"one",query:"please help me with this",now:now).records.isEmpty)
        for query in ["", " ", "Alex", "please help me with this"] {
            precondition(MemoryRetrieval.select(life,registration:"one",query:query,now:now,focus:[.studies]).records.isEmpty,"Focus never turns an empty targeted question into broad biography")
        }
        let abbreviations=["AI","ML","CV","UK"].map { word in PAMemory(registration:"one",text:"\(word) matters to my career",kind:.context,provenance:"Fictional human",reviewed:now) }
        for memory in abbreviations {
            let word=String(memory.text.prefix(2))
            precondition(MemoryRetrieval.select(life+abbreviations,registration:"one",query:word.lowercased(),now:now,focus:[.studies]).records.map{$0["id"]} == [memory.id.uuidString],"Meaningful short terms select their own facts")
        }
        precondition(MemoryRetrieval.tokens("in on at to we AI ML CV UK") == ["ai","ml","cv","uk"],"Short filler words remain excluded")
        precondition(MemoryRetrieval.select(life,registration:"one",now:now).records.count == 4,"Explicit broad orientation remains available without changing the saved notebook")
        let securityQuery=MemoryRetrieval.emailQuery(subject:"Security alert",sender:"Google",body:security)
        precondition(MemoryRetrieval.select(life,registration:"one",query:securityQuery,now:now).records.isEmpty)
        let style=PAMemory(registration:"one",text:"My email reply writing style should be concise.",kind:.preference,provenance:"User",reviewed:now)
        let replyQuery=MemoryRetrieval.emailQuery(subject:"Prototype review",sender:"Orion tutor",body:"Please confirm whether the prototype is ready.",reply:true)
        precondition(MemoryRetrieval.select(life+[style],registration:"one",query:replyQuery,now:now).records.map{$0["id"]} == [style.id.uuidString],"Reply writing preferences belong to drafting, without pinning unrelated weather preferences")
        var huge = older; huge.id = UUID(); huge.text = String(repeating:"🧠",count:6000)
        precondition(MemoryRetrieval.select([huge,older],registration:"one",now:now).records.map { $0["id"] } == [older.id.uuidString])
        var stable = stale; stable.certainty = .stated; stable.durability = .stable
        precondition(MemoryRules.usable(stable,registration:"one",now:now))
        stable.certainty = .inferred
        precondition(!MemoryRules.usable(stable,registration:"one",now:now))
        let quote = "read my family group chat (it is called The Zoo)"
        let edge = MemoryConnection(subject:"Me",relation:"family chat",object:"The Zoo",evidence:quote)
        precondition(MemoryConnection.valid([edge],human:quote))
        precondition(!MemoryConnection.valid([edge],human:"read a different chat"))
        let actual="I’m studying 8 modules. My work is end–to–end.\nI play football."
        precondition(MemoryEvidence.match("i'm studying 8 modules",human:actual) == "I’m studying 8 modules")
        precondition(MemoryEvidence.match("end-to-end",human:actual) == "end–to–end")
        precondition(MemoryEvidence.match("end-to-end. I play",human:actual) == "end–to–end.\nI play")
        precondition(MemoryEvidence.match("I study engineering",human:actual) == nil)
        precondition(MemoryEvidence.match("",human:actual) == nil)
        precondition(MemoryEvidence.match(".*",human:actual) == nil, "Quotes must not become regex instructions")
        let supportedEdge=MemoryConnection(subject:"You",relation:"plays",object:"Football",evidence:"i play football")
        let inventedEdge=MemoryConnection(subject:"You",relation:"lives",object:"Mars",evidence:"I live on Mars")
        let retained=MemoryEvidence.supportedConnections([supportedEdge,inventedEdge],human:actual)
        precondition(retained.count == 1 && retained[0].evidence == "I play football")
        precondition(MemoryConnection.valid(retained,human:actual))
        var family = older; family.text = "The Zoo"; family.connections = [edge]
        let connected = MemoryRetrieval.select([family],registration:"one",query:"family",now:now)
        precondition(connected.records.first?["connections"]?.contains("The Zoo") == true)
        family.organisation = .init(areas:[.people],connections:[],selfName:nil)
        let stableContext = MemoryRetrieval.record(family)
        for _ in 0..<100 { precondition(MemoryRetrieval.record(family) == stableContext,"Unchanged structured memory must produce the same context for in-flight brief revision checks") }
        var changedFamily=family;changedFamily.organisation?.areas=[.home]
        precondition(MemoryRetrieval.record(changedFamily) != stableContext,"Real organisation changes still invalidate captured context")
        family.registration = "two"
        precondition(MemoryRetrieval.select([family],registration:"one",query:"family",now:now).records.isEmpty)
        var legacy = try JSONSerialization.jsonObject(with:JSONEncoder().encode(stable)) as! [String:Any]
        for key in ["certainty","durability","connections"] { legacy.removeValue(forKey:key) }
        let legacyMemory = try JSONDecoder().decode(PAMemory.self,from:JSONSerialization.data(withJSONObject:legacy))
        precondition(legacyMemory.certainty == nil && legacyMemory.durability == nil && legacyMemory.connections == nil)
        print("PASS: explicit retention, provisional review, account scope, resolved archive, anchored human memory request and round-trip")
    }
}
