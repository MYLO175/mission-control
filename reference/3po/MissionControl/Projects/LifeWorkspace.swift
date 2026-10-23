import Foundation

enum LifeItemKind: String, Codable, CaseIterable, Identifiable {
    case space, task
    // Decode old records without changing their IDs, revisions or typed memory identities.
    // These compatibility values are never offered for new workspace content.
    case area, organisation, course, project, section, milestone, person, goal, resource
    static let allCases: [LifeItemKind] = [.space, .task]
    var workspaceKind: LifeItemKind { isWork ? .task : .space }
    var id: String { rawValue }
    var title: String { isWork ? "Task" : "Space" }
    var symbol: String { isWork ? "checkmark.circle" : "folder" }
    var isWork: Bool { self == .task || self == .milestone }
}
enum LifeItemStatus: String, Codable, CaseIterable, Identifiable {
    case planned, active, waiting, done, archived
    var id: String { rawValue }
    var title: String { switch self { case .planned: "To do"; case .active: "In progress"; case .waiting: "Waiting"; case .done: "Done"; case .archived: "Archived" } }
}
struct LifeItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var registration: String
    var conversationID: UUID? = nil
    var kind: LifeItemKind
    var title: String
    var parentID: UUID? = nil
    var notes = ""
    var notesFormatting:LifeNoteFormatting? = nil
    var additionalNotes:[LifeNote]? = nil
    var status: LifeItemStatus = .planned
    /// Local date, not an inferred instant or a mirrored Apple due date.
    var due: String? = nil
    var estimateMinutes: Int? = nil
    var areas: [LifeArea] = []
    var created = Date.now
    var updated = Date.now
    var revision = UUID()
    var sourceTurnID: String? = nil
    var humanEvidence: String? = nil
    var placement: LifeProjectPlacement? = nil
    var notebookEntityID: String? = nil
    /// Missing ownership is the existing human workspace. Life anchors contain navigation only.
    var ownership: String? = nil
    var sortOrder: Int? = nil
    var deletedAt: Date? = nil
    var deletedRoot: UUID? = nil
    var icon:String? = nil
    var displaySymbol:String { icon.flatMap{LifeProjectIcons.symbols.contains($0) ? $0 : nil} ?? kind.symbol }
}
/// Plain note text stays authoritative; font runs are an optional presentation sidecar.
struct LifeNoteRun:Codable,Equatable {
    var location:Int
    var length:Int
    var size:Double
    var bold:Bool
    var italic:Bool
}
struct LifeNoteFormatting:Codable,Equatable {
    var version=1
    var length:Int
    var runs:[LifeNoteRun]
    func valid(for text:String)->Bool {
        guard version == 1,length == text.utf16.count,runs.count <= 12000 else {return false}
        var end=0
        for run in runs {
            guard run.location >= end,run.length > 0,run.location <= length,run.length <= length-run.location,run.size.isFinite,(9...72).contains(run.size) else {return false}
            end=run.location+run.length
        }
        return true
    }
}
struct LifeNote:Codable,Identifiable,Equatable {
    var id=UUID()
    var text:String
    var formatting:LifeNoteFormatting? = nil
}
extension LifeItem {
    var noteCards:[LifeNote] {
        (notes.isEmpty ? [] : [LifeNote(id:id,text:notes,formatting:notesFormatting)])+(additionalNotes ?? [])
    }
    var searchableNotes:String { ([notes]+(additionalNotes ?? []).map(\.text)).joined(separator:"\n\n") }
}
enum LifeProjectIcons {
    static let symbols=["folder","book.closed","graduationcap","briefcase","laptopcomputer","lightbulb","wrench.and.screwdriver","leaf","house","person.2","star","flag","doc.text","chart.bar"]
    static func title(_ symbol:String)->String {
        switch symbol {case "folder":"Folder";case "book.closed":"Book";case "graduationcap":"Studies";case "briefcase":"Work";case "laptopcomputer":"Computer";case "lightbulb":"Idea";case "wrench.and.screwdriver":"Tools";case "leaf":"Wellbeing";case "house":"Home";case "person.2":"People";case "star":"Star";case "flag":"Goal";case "doc.text":"Note";default:"Progress"}
    }
}
enum LifeRelation: String, Codable, CaseIterable, Identifiable {
    case related, partOf, dependsOn, preparesFor, supports, supervisedBy, discusses, evidence, identifies
    var id: String { rawValue }
    var title: String { switch self {
    case .related: "Related to"; case .partOf: "Also part of"; case .dependsOn: "Depends on"
    case .preparesFor: "Prepares for"; case .supports: "Supports"; case .supervisedBy: "Supervised by"
    case .discusses: "Discusses"; case .evidence: "Supported by"; case .identifies: "Same item in memory"
    } }
}
enum LifeReferenceKind: String, Codable, CaseIterable { case item, memory, event, reminder, mail, whatsapp }
/// A pointer, never a second Calendar/Reminders record or a retained message body.
struct LifeReference: Codable, Equatable, Hashable {
    var kind: LifeReferenceKind
    var id: String
    var containerID: String? = nil
    var linkedIdentity: String? = nil
    var contentRevision: String? = nil
}
struct LifeItemLink: Codable, Identifiable, Equatable {
    var id = UUID()
    var registration: String
    var conversationID: UUID? = nil
    var from: UUID
    var relation: LifeRelation
    var target: LifeReference
    var created = Date.now
    var inferred: Bool? = nil
    var reason: String? = nil
}
struct LifeWorkspaceReceipt: Codable, Identifiable, Equatable {
    var id: String
    var registration: String
    var result: String
    var itemID: UUID?
    var created = Date.now
}
struct LifeWorkspaceState: Codable, Equatable {
    var version = 1
    var items: [LifeItem] = []
    var links: [LifeItemLink] = []
    var receipts: [LifeWorkspaceReceipt] = []
}
enum LifeWorkspaceFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
enum LifeWorkspaceRules {
    /// Enforce the simple hierarchy on new filing/type changes without rewriting legacy storage.
    static func validateChange(_ item: LifeItem, from old: LifeItem?, in items: [LifeItem]) throws {
        if old == nil || item.parentID != old?.parentID, let parent = item.parentID,
           items.first(where: { $0.id == parent })?.kind.isWork == true {
            throw LifeWorkspaceFailure.message("Choose a space to put this item inside. Tasks cannot contain other items.")
        }
        if item.kind.isWork, old?.kind.isWork == false, items.contains(where: { $0.parentID == item.id }) {
            throw LifeWorkspaceFailure.message("Move this space’s contents before changing it into a task.")
        }
    }
    static func key(_ label: String) -> String { label.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB")).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
    static func scoped(_ item: LifeItem, registration: String, topic: UUID?, includeTopics: Bool) -> Bool {
        item.registration == registration && (includeTopics || item.conversationID == nil || item.conversationID == topic)
    }
    static func ordered(_ items: [LifeItem]) -> [LifeItem] {
        var positions:[UUID:Int]=[:],counts:[String:Int]=[:]
        for item in items { let key=item.registration+":"+(item.conversationID?.uuidString ?? "shared")+":"+(item.parentID?.uuidString ?? "home");positions[item.id]=counts[key,default:0];counts[key,default:0]+=1 }
        return items.sorted { a,b in
            if a.parentID != b.parentID { return (a.parentID?.uuidString ?? "") < (b.parentID?.uuidString ?? "") }
            if a.parentID == b.parentID { let x=a.sortOrder ?? positions[a.id] ?? 0,y=b.sortOrder ?? positions[b.id] ?? 0;if x != y { return x < y } }
            return a.created == b.created ? a.id.uuidString < b.id.uuidString : a.created < b.created
        }
    }
    static func navigationAreas(_ item: LifeItem, in items: [LifeItem]) -> [LifeArea] {
        let known = LifeItemQuery.path(item,in:items).flatMap(\.areas)
        if !known.isEmpty { return Array(Set(known)).sorted{$0.rawValue < $1.rawValue} }
        return item.kind == .course ? [.studies] : item.kind == .project ? [.projects] : [.unsorted]
    }
    static func dateValid(_ value: String?) -> Bool {
        guard let value else { return true }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return value.count == 10 && formatter.date(from: value).map { formatter.string(from: $0) == value } == true
    }
    static func displayDate(_ value: String) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_GB"); formatter.calendar = Calendar(identifier:.gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from:value) else { return value }
        formatter.dateFormat = Calendar(identifier:.gregorian).component(.year,from:date) == Calendar(identifier:.gregorian).component(.year,from:.now) ? "d MMM" : "d MMM yyyy"
        return formatter.string(from:date)
    }
    static func descendants(_ id: UUID, in items: [LifeItem]) -> Set<UUID> {
        var found = Set<UUID>(), pending = [id]
        while let next = pending.popLast() {
            for child in items where child.parentID == next && found.insert(child.id).inserted { pending.append(child.id) }
        }
        return found
    }
    static func validate(_ state: LifeWorkspaceState) throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw LifeWorkspaceFailure.message(message) } }
        try require(state.version == 1 && state.items.filter{$0.deletedAt == nil}.count <= 5000 && state.links.count <= 10000, "Project storage has an unsupported format or size.")
        try require(Set(state.items.map(\.id)).count == state.items.count && Set(state.links.map(\.id)).count == state.links.count && Set(state.receipts.map(\.id)).count == state.receipts.count, "Duplicate project identities were rejected.")
        let byID = Dictionary(state.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for receipt in state.receipts { try require(!receipt.id.isEmpty && !receipt.registration.isEmpty && receipt.result.count <= 2000, "An operation receipt is invalid.") }
        for item in state.items {
            try require(item.icon.map{LifeProjectIcons.symbols.contains($0)} != false,"Choose a supported project icon.")
            try require(!item.registration.isEmpty && !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.title.count <= 160 && item.notes.count <= 12000 && dateValid(item.due) && item.estimateMinutes.map { (1...100000).contains($0) } != false && item.areas.count <= 3 && Set(item.areas).count == item.areas.count, "A project field is empty, too long or invalid.")
            let extraNotes=item.additionalNotes ?? []
            try require(extraNotes.count <= 100 && Set(extraNotes.map(\.id)).count == extraNotes.count && !extraNotes.contains{$0.id == item.id} && extraNotes.allSatisfy{$0.text.count <= 12000},"A note is too long or has a duplicate identity.")
            try require(item.notesFormatting.map{$0.valid(for:item.notes)} != false && extraNotes.allSatisfy{note in note.formatting.map{$0.valid(for:note.text)} != false},"Note formatting no longer matches its text.")
            try require(item.humanEvidence.map { !$0.isEmpty && $0.count <= 2000 } != false, "The project origin evidence is invalid.")
            try require(item.ownership == nil || ["workspace","life"].contains(item.ownership!), "Unknown item ownership.")
            try require(item.ownership != "life" || [.area,.organisation,.course,.person,.goal].contains(item.kind), "Life organisation cannot create project workspace content.")
            if let placement = item.placement {
                try require(["pending","running","paused","placed","question","unplaced"].contains(placement.status) && placement.reason.count <= 500 && placement.choices.count <= 3 && (placement.question?.count ?? 0) <= 200,"Project placement metadata is invalid.")
            }
            if let parentID = item.parentID {
                try require(item.deletedAt != nil || byID[parentID]?.deletedAt == nil, "An active item cannot be inside Recently deleted.")
                try require(byID[parentID].map { $0.registration == item.registration && $0.conversationID == item.conversationID } == true, "A parent must belong to the same account and scope.")
                var seen: Set<UUID> = [item.id], cursor: UUID? = parentID
                while let next = cursor {
                    try require(seen.insert(next).inserted, "An item cannot contain itself. Choose a different parent.")
                    try require(seen.count <= 32, "Use at most 31 levels of nesting.")
                    cursor = byID[next]?.parentID
                }
            }
        }
        for link in state.links {
            try require(byID[link.from].map { $0.registration == link.registration && $0.conversationID == link.conversationID } == true && !link.target.id.isEmpty && link.target.id.count <= 500, "A relationship has no valid owner.")
            if link.target.kind == .item {
                try require(UUID(uuidString: link.target.id).flatMap { byID[$0] }.map { $0.registration == link.registration && $0.conversationID == link.conversationID && $0.id != link.from } == true, "A relationship must target another item in the same account and scope.")
            }
            if link.target.kind == .memory { try require(UUID(uuidString: link.target.id) != nil, "A memory link needs its saved identity.") }
            if [.event, .reminder, .mail, .whatsapp].contains(link.target.kind) {
                try require(link.target.containerID.map { !$0.isEmpty && $0.count <= 500 } == true, "A source link needs its original container identity.")
            }
            if link.target.kind == .whatsapp {
                try require(link.target.linkedIdentity?.isEmpty == false && link.target.contentRevision?.isEmpty == false, "A WhatsApp link needs its linked identity and content version.")
            }
        }
        // Secondary containment and dependency links may cross branches but cannot form cycles.
        for relation in [LifeRelation.partOf, .dependsOn] {
            var adjacency: [UUID: [UUID]] = [:]
            if relation == .partOf { for item in state.items { if let parent = item.parentID { adjacency[item.id, default: []].append(parent) } } }
            for link in state.links where link.relation == relation && link.target.kind == .item {
                if let target = UUID(uuidString: link.target.id) { adjacency[link.from, default: []].append(target) }
            }
            var done = Set<UUID>(), visiting = Set<UUID>()
            func visit(_ id: UUID) throws {
                if done.contains(id) { return }
                try require(visiting.insert(id).inserted, "That relationship would create a circular dependency or hierarchy.")
                try require(visiting.count <= 64, "That dependency chain is too deep.")
                for next in adjacency[id] ?? [] { try visit(next) }
                visiting.remove(id); done.insert(id)
            }
            for id in adjacency.keys { try visit(id) }
        }
    }
}
