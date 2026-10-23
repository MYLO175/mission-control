import Foundation
@main struct Checks {
    static func main() throws {
        let now = Date(timeIntervalSince1970:2000000000)
        let turns = (0..<20).map { MemoryLearningTurn(id:String($0),text:"I prefer at least two weeks of advance notice.",created:now.addingTimeInterval(Double($0))) }
        let progress = MemoryLearningRules.progress(turns:turns.reversed(),prior:nil,suppressed:[],day:"day")
        precondition(progress.skippedAtOrientation == 12)
        let batch = MemoryLearningRules.batch(turns.reversed(),seen:progress.seen,suppressed:[])
        precondition(batch.map(\.id) == (12..<20).map(String.init))
        var next = progress; next.seen.formUnion(batch.map(\.id))
        precondition(MemoryLearningRules.batch(turns,seen:next.seen,suppressed:[]).isEmpty)
        precondition(MemoryLearningRules.batch(turns,seen:progress.seen,suppressed:["19"]).count == 7)
        var unknown = turns[0]; unknown.dateKnown = false
        let input = try MemoryLearningRules.input(turns:[unknown],existing:[],timezone:"Europe/London")
        precondition(input.contains("unknown") && input.contains("dateKnown"))
        let good = "{\"memories\":[{\"turnID\":\"12\",\"text\":\"Prefers two weeks of advance notice.\",\"kind\":\"preference\",\"evidence\":\"two weeks of advance notice\"}]}"
        let valid = try MemoryLearningRules.decode(good,turns:batch); precondition(valid.count == 1)
        let introduction=MemoryLearningTurn(id:"intro",text:"I study Materials Engineering. My family chat is called The Nest.",created:now)
        let parts="{\"memories\":[{\"turnID\":\"intro\",\"text\":\"Studies Materials Engineering\",\"kind\":\"context\",\"evidence\":\"I study Materials Engineering\"},{\"turnID\":\"intro\",\"text\":\"Family chat is The Nest\",\"kind\":\"context\",\"evidence\":\"My family chat is called The Nest\"}]}"
        let multiple=try MemoryLearningRules.decode(parts,turns:[introduction]);precondition(multiple.count == 2 && multiple.allSatisfy{$0.turnID == "intro"})
        func encode(_ values: [LearnedMemory]) throws -> String {
            String(data:try JSONSerialization.data(withJSONObject:["memories":try JSONSerialization.jsonObject(with:JSONEncoder().encode(values))]),encoding:.utf8)!
        }
        var classified=multiple[0];classified.organisation = .init(areas:[.studies],connections:[],selfName:nil)
        let typed=try MemoryLearningRules.decode(encode([classified]),turns:[introduction]);precondition(typed[0].organisation?.areas == [.studies])
        for metadata in [
            LifeMemoryOrganisation(areas:[.studies],connections:[.init(connection:"0",subjectKind:.person,objectKind:.course,subjectIsSelf:true,objectIsSelf:false)],selfName:nil),
            LifeMemoryOrganisation(areas:[.studies],connections:[],selfName:"An invented name"),
            LifeMemoryOrganisation(areas:[.studies],connections:[],selfName:nil,manual:true)
        ] {
            classified.organisation=metadata
            let retained=try MemoryLearningRules.decode(encode([classified]),turns:[introduction])
            precondition(retained.count == 1 && retained[0].text == classified.text && retained[0].evidence == classified.evidence && retained[0].organisation == nil,"Unsupported navigation must not discard a faithful fact")
        }
        let excessive = try encode((12..<17).map { LearnedMemory(turnID:String($0),text:"Supported",kind:.preference,evidence:"two weeks of advance notice") })
        let duplicate = try encode([valid[0],valid[0]])
        var long = valid[0]; long.text = String(repeating:"x",count:501)
        for bad in [good.replacingOccurrences(of:"\"12\"",with:"\"999\""),good.replacingOccurrences(of:"two weeks of advance notice\"",with:"invented evidence\""),good.replacingOccurrences(of:"\"preference\"",with:"\"execute\""),excessive,duplicate,try encode([long])] {
            do { _ = try MemoryLearningRules.decode(bad,turns:batch); fatalError("Accepted invalid model data") } catch {}
        }
        let empty = try MemoryLearningRules.decode("{\"memories\":[]}",turns:batch); precondition(empty.isEmpty)
        next.lastAttempt = now; precondition(!MemoryLearningRules.allowed(next,now:now,manual:false))
        next.lastAttempt = now.addingTimeInterval(-901); next.attempts = 4
        precondition(!MemoryLearningRules.allowed(next,now:now,manual:false)); precondition(MemoryLearningRules.allowed(next,now:now,manual:true))
        let tomorrow = MemoryLearningRules.progress(turns:turns,prior:next,suppressed:[],day:"tomorrow")
        precondition(tomorrow.attempts == 0 && tomorrow.seen == next.seen)
        next.paused = true; next.attempts = 0
        precondition(!MemoryLearningRules.allowed(next,now:now,manual:false))
        let memory = PAMemory(registration:"one",text:"Existing explicit",kind:.preference,provenance:"User")
        let old = try MemoryEnvelope.decode(JSONEncoder().encode([memory]))
        precondition(old.records[0].explicit && old.suppressed.isEmpty)
        var envelope = old; envelope.suppressed["one"] = ["12"]
        let restored = try MemoryEnvelope.decode(JSONEncoder().encode(envelope))
        precondition(restored.suppressed["one"] == ["12"] && restored.records.count == 1)
        do { _ = try MemoryEnvelope.decode(Data("{\"version\":99,\"records\":[],\"suppressed\":{}}".utf8)); fatalError("Accepted unknown version") } catch {}
        let topic = UUID(), otherTopic = UUID()
        let scoped = [MemoryLearningTurn(id:"general",text:"I prefer concise replies",created:now),MemoryLearningTurn(id:"study",text:"My project is about optics",created:now.addingTimeInterval(1),conversationID:topic),MemoryLearningTurn(id:"other",text:"My other project is acoustics",created:now.addingTimeInterval(2),conversationID:otherTopic),MemoryLearningTurn(id:"study-two",text:"I study in the library",created:now.addingTimeInterval(3),conversationID:topic)]
        precondition(MemoryLearningRules.batch(scoped,seen:[],suppressed:[]).map(\.id) == ["general"])
        precondition(MemoryLearningRules.batch(scoped,seen:["general"],suppressed:[]).map(\.id) == ["study","study-two"])
        let questionJSON = "{\"memories\":[],\"question\":{\"turnID\":\"study\",\"text\":\"How much preparation time should I allow for your optics project?\",\"evidence\":\"My project is about optics\"}}"
        let assessment = try MemoryLearningRules.assessment(questionJSON,turns:scoped,questionAllowed:true)
        precondition(assessment.memories.isEmpty && assessment.question?.turnID == "study")
        for (bad,allowed) in [(questionJSON,false),(questionJSON.replacingOccurrences(of:"My project is about optics",with:"Invented quote"),true),(questionJSON.replacingOccurrences(of:"How much preparation time should I allow for your optics project?",with:"Not a question"),true),(questionJSON.replacingOccurrences(of:"\"study\"",with:"\"not-a-turn\""),true)] {
            do { _ = try MemoryLearningRules.assessment(bad,turns:scoped,questionAllowed:allowed); preconditionFailure("Invalid question accepted") } catch {}
        }
        let conflicting = questionJSON.replacingOccurrences(of:"\"memories\":[]",with:"\"memories\":[{\"turnID\":\"study\",\"text\":\"My project is about optics\",\"kind\":\"context\",\"evidence\":\"My project is about optics\"}]")
        do { _ = try MemoryLearningRules.assessment(conflicting,turns:scoped,questionAllowed:true); preconditionFailure("Learned and queried the same fact") } catch {}
        let q = LearningQuestionRules.record(assessment.question!,turns:scoped,prior:[],registration:"one",now:now)!
        precondition(q.conversationID == topic && q.turnID == "study")
        precondition(LearningQuestionRules.record(assessment.question!,turns:scoped,prior:[q],registration:"one",now:now) == nil)
        let today = BriefingRules.day(now)
        precondition(!LearningQuestionRules.allowed(progress:MemoryLearningProgress(),records:[q],registration:"one",day:today))
        precondition(LearningQuestionRules.allowed(progress:MemoryLearningProgress(),records:[q],registration:"two",day:today))
        precondition(LearningQuestionRules.allowed(progress:MemoryLearningProgress(),records:[q],registration:"one",day:"tomorrow"))
        var claimed = MemoryLearningProgress(); claimed.lastQuestionDay = today
        precondition(!LearningQuestionRules.allowed(progress:claimed,records:[],registration:"one",day:today))
        claimed.day = today
        let questionProgress = MemoryLearningRules.progress(turns:[],prior:claimed,suppressed:[],day:"tomorrow")
        precondition(questionProgress.lastQuestionDay == today)
        let legacyProgress = "{\"version\":1,\"accounts\":{\"one\":{\"seen\":[],\"skippedAtOrientation\":0,\"day\":\"today\",\"attempts\":0,\"paused\":false}}}"
        let legacyState = try JSONDecoder().decode(MemoryLearningState.self,from:Data(legacyProgress.utf8))
        precondition(legacyState.questions == nil && legacyState.accounts["one"]?.lastQuestionDay == nil)
        var savedQuestion = q; savedQuestion.dismissed = true
        var questionState = MemoryLearningState(); questionState.questions = [savedQuestion]; questionState.accounts["one"] = claimed
        let questionReload = try JSONDecoder().decode(MemoryLearningState.self,from:JSONEncoder().encode(questionState))
        precondition(questionReload.questions == [savedQuestion] && questionReload.accounts["one"]?.lastQuestionDay == today)
        precondition(!q.deliveryID.hasPrefix("discovery:") && !q.deliveryID.contains(":morning:"))
        print("PASS: bounded orientation/batches, evidence and ID validation, daily/interval/pause controls, explicit migration/suppression, single-scope batches, grounded optional daily questions, legacy state and dismissal roundtrip")
    }
}
