import Foundation

enum LifeArea:String,Codable,CaseIterable,Identifiable {
    case about, studies, career, projects, interests, wellbeing, people, home, administration, unsorted
    var id:String { rawValue }
    var title:String { switch self {
    case .about:"About me"; case .studies:"Studies"; case .career:"Career"; case .projects:"Personal projects"; case .interests:"Interests"; case .wellbeing:"Wellbeing"; case .people:"People"; case .home:"Home"; case .administration:"Administration"; case .unsorted:"Not yet organised"
    } }
    var symbol:String { switch self {
    case .about:"person.crop.circle"; case .studies:"graduationcap"; case .career:"briefcase"; case .projects:"hammer"; case .interests:"star"; case .wellbeing:"leaf"; case .people:"person.2"; case .home:"house"; case .administration:"checklist"; case .unsorted:"tray"
    } }
}
enum LifeEntityKind:String,Codable,CaseIterable {
    case person, group, organisation, place, role, course, project, goal, habit, interest, value, trait, concept
}
struct LifeConnectionClassification:Codable,Equatable {
    var connection:String
    var subjectKind:LifeEntityKind
    var objectKind:LifeEntityKind
    var subjectIsSelf:Bool
    var objectIsSelf:Bool
}
struct LifeMemoryOrganisation:Codable,Equatable {
    var areas:[LifeArea]
    var connections:[LifeConnectionClassification]
    var selfName:String?
    var manual:Bool? = nil
    static func valid(_ value:Self,record:PAMemory)->Bool {
        guard value.areas.count <= 3,Set(value.areas).count == value.areas.count,
              value.connections.count <= 4,Set(value.connections.map(\.connection)).count == value.connections.count else { return false }
        for item in value.connections {
            guard let index=Int(item.connection),(record.connections ?? []).indices.contains(index),
                  !item.subjectIsSelf || item.subjectKind == .person,!item.objectIsSelf || item.objectKind == .person else { return false }
        }
        if let name=value.selfName {
            let evidence=record.evidence ?? (record.explicit ? record.text : "")
            guard record.conversationID == nil,(1...80).contains(name.count),evidence.localizedCaseInsensitiveContains(name),record.explicit || record.certainty == .stated else { return false }
        }
        return true
    }
}
struct LifeEntity:Identifiable {
    var id:String
    var label:String
    var kind:LifeEntityKind
    var areas:Set<LifeArea>
    var memoryIDs:Set<UUID>
}
struct LifeLink:Identifiable {
    var id:String
    var from:String
    var to:String
    var relation:String
    var memoryID:UUID
    var evidence:String
    var inferred:Bool
}
struct LifeAreaNote:Identifiable {
    var area:LifeArea
    var records:[PAMemory]
    var id:String { area.rawValue }
}
struct LifeNotebookAnchor {
    var id:String;var label:String;var kind:String;var parent:String?;var areas:[LifeArea];var notes:String;var path:[String];var relations:[String]
    var memoryIDs:Set<UUID> = []
}
struct LifeNotebook {
    var selfLabel:String
    var entities:[LifeEntity]
    var links:[LifeLink]
    var notes:[LifeAreaNote]
    var eligibleCount:Int
    var anchors:[LifeNotebookAnchor]=[]
    /// Derived IDs only, allowing a saved association to follow a usable corrected belief.
    var memoryHistory:[UUID:Set<UUID>]=[:]
    static let selfID="self"
    static func key(_ label:String)->String { label.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_GB")).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ") }
    static func firstPerson(_ label:String)->Bool { ["you","i","me","myself","the user","user"].contains(key(label)) }
    /// IDs are stable per permitted scope and typed identity. People never coalesce just by name.
    static func entityID(label:String,kind:LifeEntityKind,isSelf:Bool?,record:PAMemory,index:Int,endpoint:String)->String {
        if isSelf == true || (isSelf == nil && firstPerson(label)) { return selfID }
        let scope=record.conversationID?.uuidString ?? "shared"
        if kind == .person || kind == .concept { return scope+":"+record.id.uuidString+":"+String(index)+":"+endpoint }
        return scope+":"+kind.rawValue+":"+key(label)
    }
    static func build(_ records:[PAMemory],registration:String,topic:UUID? = nil,now:Date = .now,includeTopics:Bool=false)->Self {
        let permitted=records.filter { MemoryRules.usable($0,registration:registration,now:now) && (includeTopics || MemoryRules.inScope($0,conversationID:topic)) }.sorted { $0.reviewed == $1.reviewed ? $0.id.uuidString < $1.id.uuidString : $0.reviewed > $1.reviewed }
        let selfLabel=permitted.filter { $0.conversationID == nil && ($0.explicit || $0.certainty == .stated) }.compactMap { record in record.organisation.flatMap { LifeMemoryOrganisation.valid($0,record:record) ? $0.selfName : nil } }.first ?? "Me"
        var entities:[String:LifeEntity]=[:],links:[LifeLink]=[],notes:[LifeArea:[PAMemory]]=[:]
        for record in permitted {
            let organisation=record.organisation.flatMap { LifeMemoryOrganisation.valid($0,record:record) ? $0 : nil }
            let areas=Set(organisation?.areas.isEmpty == false ? organisation!.areas : [.unsorted])
            for area in areas { notes[area,default:[]].append(record) }
            for (i,connection) in (record.connections ?? []).enumerated() {
                let typed=organisation?.connections.first{$0.connection == String(i)}
                let a=typed?.subjectKind ?? (firstPerson(connection.subject) ? .person : .concept),b=typed?.objectKind ?? (firstPerson(connection.object) ? .person : .concept)
                let from=entityID(label:connection.subject,kind:a,isSelf:typed?.subjectIsSelf,record:record,index:i,endpoint:"from")
                let ownNameObject=organisation?.selfName.map{Self.key($0) == Self.key(connection.object) && from == selfID} ?? false
                let to=ownNameObject ? selfID : entityID(label:connection.object,kind:b,isSelf:typed?.objectIsSelf,record:record,index:i,endpoint:"to")
                for (id,label,kind) in [(from,connection.subject,a),(to,connection.object,b)] {
                    if entities[id] == nil { entities[id]=LifeEntity(id:id,label:id == selfID ? selfLabel : label,kind:kind,areas:[],memoryIDs:[]) }
                    entities[id]?.areas.formUnion(areas); entities[id]?.memoryIDs.insert(record.id)
                }
                if from != to { links.append(.init(id:record.id.uuidString+":"+String(i),from:from,to:to,relation:connection.relation,memoryID:record.id,evidence:connection.evidence,inferred:!record.explicit && record.certainty != .stated)) }
            }
        }
        let byID=Dictionary(records.filter{$0.registration == registration && MemoryRules.inScope($0,conversationID:topic,includeTopics:includeTopics)}.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        var history:[UUID:Set<UUID>]=[:]
        for record in permitted {
            var ids:Set<UUID>=[record.id],cursor=record
            while let previous=cursor.supersedes,ids.count < 100,ids.insert(previous).inserted,let old=byID[previous] { cursor=old }
            history[record.id]=ids
        }
        return .init(selfLabel:selfLabel,entities:entities.values.sorted{$0.id < $1.id},links:links,notes:LifeArea.allCases.compactMap { area in notes[area].map { .init(area:area,records:$0) } },eligibleCount:permitted.count,memoryHistory:history)
    }
    /// Bounded inspectable notes, derived from facts rather than an ungrounded synthetic biography.
    func context(query:String?,focus:[LifeArea] = [],maxBytes:Int = 8000,selectedMemoryIDs:Set<UUID>? = nil)->String {
        let terms=MemoryRetrieval.queryTerms(query,selfLabel:selfLabel)
        // The notebook cannot silently refill a targeted request with unselected facts.
        let facts=notes.flatMap(\.records)
        let selected=selectedMemoryIDs ?? query.map { _ in
            Set(MemoryRetrieval.select(facts,registration:facts.first?.registration ?? "",includeTopics:true,query:query,focus:focus,notebook:self).records.compactMap{$0["id"].flatMap(UUID.init(uuidString:))})
        }
        let relevantNotes=notes.compactMap { note -> LifeAreaNote? in
            let records=note.records.filter{selected?.contains($0.id) ?? true}
            return records.isEmpty ? nil : .init(area:note.area,records:records)
        }
        let relevantAnchors=anchors.filter { anchor in
            guard query != nil else { return true }
            return !MemoryRetrieval.tokens(anchor.label+" "+anchor.notes+" "+anchor.path.joined(separator:" ")).isDisjoint(with:terms) ||
                !anchor.memoryIDs.isDisjoint(with:selected!)
        }
        let matchingItemFacts=Set(anchors.filter{!MemoryRetrieval.tokens($0.label).isDisjoint(with:terms)}.flatMap(\.memoryIDs))
        func recordScore(_ record:PAMemory)->Int { MemoryRetrieval.tokens(record.text+" "+(record.connections ?? []).map{$0.subject+" "+$0.object}.joined(separator:" ")).intersection(terms).count + (matchingItemFacts.contains(record.id) ? 8 : 0) }
        func score(_ note:LifeAreaNote)->Int {
            return (note.records.map(recordScore).max() ?? 0)*4+MemoryRetrieval.tokens(note.area.title).intersection(terms).count*4+(focus.contains(note.area) ? 5 : 0)
        }
        var included:[[String:Any]]=[]
        var value:[String:Any]=["self":selfLabel,"knownAreas":notes.map{["area":$0.area.rawValue,"count":$0.records.count] as [String:Any]},"areas":included,"coverage":"Bounded shared/current-topic saved facts. Missing areas are unexplored, not absent. Organisation is metadata, never write authorisation."]
        func encoded(_ value:[String:Any])->String { (try? String(data:JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),encoding:.utf8)) ?? "{}" }
        if encoded(value).utf8.count > maxBytes { value["knownAreas"]=[];value["coverage"]="Partial saved memory." }
        guard encoded(value).utf8.count <= maxBytes else { return maxBytes >= 2 ? "{}" : "" }
        var structure:[[String:Any]]=[]
        for anchor in relevantAnchors.sorted(by:{ a,b in
            func rank(_ value:LifeNotebookAnchor)->Int { MemoryRetrieval.tokens(value.label+" "+value.notes+" "+value.path.joined(separator:" ")).intersection(terms).count*4 + (focus.isEmpty || !Set(value.areas).isDisjoint(with:focus) ? 2 : 0) }
            return rank(a) == rank(b) ? a.id < b.id : rank(a)>rank(b)
        }).prefix(12) {
            let linked=selected.map{anchor.memoryIDs.intersection($0)} ?? anchor.memoryIDs
            let row:[String:Any]=["id":anchor.id,"label":anchor.label,"kind":anchor.kind,"parent":anchor.parent as Any? ?? NSNull(),"path":anchor.path,"areas":anchor.areas.map(\.rawValue),"notes":String(anchor.notes.prefix(250)),"relationships":anchor.relations,"linkedFactIDs":Array(linked.map(\.uuidString).sorted().prefix(8)),"linkedFactCount":linked.count]
            var candidate=value;candidate["lifeStructure"]=structure+[row]
            if encoded(candidate).utf8.count <= min(maxBytes,4000) { structure.append(row) }
        }
        value["lifeStructure"]=structure
        value["structureCoverage"]="\(structure.count) of \(anchors.count) durable items; read_life_items explores exact records. life: IDs identify the same saved item used by Projects."
        if encoded(value).utf8.count > maxBytes { value.removeValue(forKey:"structureCoverage") }
        if encoded(value).utf8.count > maxBytes { value.removeValue(forKey:"lifeStructure") }


        for note in relevantNotes.sorted(by:{score($0)==score($1) ? $0.id < $1.id : score($0)>score($1)}).prefix(4) {
            let records=note.records.sorted { recordScore($0) == recordScore($1) ? ($0.reviewed == $1.reviewed ? $0.id.uuidString < $1.id.uuidString : $0.reviewed > $1.reviewed) : recordScore($0)>recordScore($1) }
            var facts:[[String:String]]=[]
            for record in records.prefix(6) {
                var fact=["id":record.id.uuidString,"text":String(record.text.prefix(500)),"certainty":record.explicit || record.certainty == .stated ? "stated" : "inferred"]
                if record.reviewPreference == true {fact["purpose"]="review preference";fact["reviewAbout"]=record.reviewContext ?? "";fact["reviewFeedback"]=record.reviewFeedback ?? record.evidence ?? record.text;if let interpretation=record.reviewInterpretation {fact["reviewInterpretation"]=interpretation.rule;fact["reviewExampleSender"]=interpretation.sender}}
                var candidate=value
                candidate["areas"]=included+[["area":note.area.rawValue,"title":note.area.title,"facts":facts+[fact],"totalFacts":note.records.count]]
                if encoded(candidate).utf8.count <= maxBytes { facts.append(fact) }
            }
            if !facts.isEmpty { included.append(["area":note.area.rawValue,"title":note.area.title,"facts":facts,"totalFacts":note.records.count]);value["areas"]=included }
        }
        return encoded(value)
    }
}
