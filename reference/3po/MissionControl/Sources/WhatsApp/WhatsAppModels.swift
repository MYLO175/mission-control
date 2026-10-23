import Foundation

struct WhatsAppReadMessage: Codable, Identifiable, Equatable {
    let id: String
    let chat: String
    let sender: String
    let text: String
    let sentByMe: Bool
    let time: Double
}
struct WhatsAppChat: Codable, Identifiable {
    let id: String
    let name: String
    let group: Bool
}
struct WhatsAppAccess: Codable, Equatable {
    var enabled = false
    var chats: Set<String> = []
    var includeInBrief: Bool? = nil
    var learnContext: Bool? = nil
    var includeInSuggestions:Bool? = nil
    /// Durable access changes survive a disabled interval/reopen; no source content.
    var learningAccessRevision:UUID? = nil
    var briefEnabled: Bool { enabled && includeInBrief == true && !chats.isEmpty }
}
struct WhatsAppBriefSnapshot {
    let messages: [WhatsAppReadMessage]
    let total: Int
    let start: Date
    let end: Date
}
struct WhatsAppSourceScope: Equatable {
    let registration: String
    let linkedIdentity: String
    let revision: UUID
    var identityRevision:UUID? = nil
}
enum WhatsAppReadPurpose:String,CaseIterable {case conversation,brief,suggestions}
/// Request ownership follows the relevant account and read permission. Learning
/// and another consumer's opt-ins do not revoke an already permitted read.
struct WhatsAppReadAccessRevisions {
    private var values:[String:UUID]=[:]
    private(set) var identityRevision=UUID()
    mutating func invalidateIdentity() {identityRevision=UUID()}
    func revision(key:String,purpose:WhatsAppReadPurpose)->UUID {values[key+":"+purpose.rawValue] ?? UUID(uuidString:"00000000-0000-0000-0000-000000000000")!}
    mutating func record(key:String,previous:WhatsAppAccess,current:WhatsAppAccess) {
        for purpose in WhatsAppReadPurpose.allCases where !WhatsAppReadRules.sameReadAccess(previous,current,purpose:purpose) {values[key+":"+purpose.rawValue]=UUID()}
    }
}
enum WhatsAppReadRules {
    static func sameReadAccess(_ left:WhatsAppAccess,_ right:WhatsAppAccess,purpose:WhatsAppReadPurpose)->Bool {
        guard left.enabled == right.enabled,left.chats == right.chats else {return false}
        switch purpose {
        case .conversation:return true
        case .brief:return (left.includeInBrief == true) == (right.includeInBrief == true)
        case .suggestions:return (left.includeInSuggestions == true) == (right.includeInSuggestions == true)
        }
    }
    static func recordingLearningAccess(_ access:WhatsAppAccess,previous:WhatsAppAccess)->WhatsAppAccess {
        var value=access
        let changed=access.enabled != previous.enabled || access.chats != previous.chats || access.learnContext != previous.learnContext || access.includeInBrief != previous.includeInBrief || access.includeInSuggestions != previous.includeInSuggestions
        value.learningAccessRevision=changed ? UUID() : previous.learningAccessRevision
        return value
    }
    static func accessKey(registration: String, linkedIdentity: String) -> String? {
        guard !registration.isEmpty, !linkedIdentity.isEmpty else { return nil }
        return registration + ":" + linkedIdentity
    }
    static func access(_ saved: [String:WhatsAppAccess], registration: String, linkedIdentity: String) -> WhatsAppAccess {
        guard let key=accessKey(registration:registration,linkedIdentity:linkedIdentity) else { return .init() }
        return saved[key] ?? .init()
    }
    static func selectedChats(_ chats:[WhatsAppChat],selected:Set<String>)->[WhatsAppChat] {
        let known=Dictionary(chats.map { ($0.id,$0) },uniquingKeysWith:{first,_ in first})
        return selected.map { known[$0] ?? WhatsAppChat(id:$0,name:"Chat not currently available",group:$0.hasSuffix("@g.us")) }
            .sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    static func validSearchRange(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        guard start < end, calendar.startOfDay(for:start) == start, calendar.startOfDay(for:end) == end,
              let days=calendar.dateComponents([.day],from:start,to:end).day else { return false }
        return (1...90).contains(days)
    }
    // A bounded snapshot for the existing daily job, never a historical indexing pass.
    static func brief(_ messages: [WhatsAppReadMessage], access: WhatsAppAccess, now: Date) -> WhatsAppBriefSnapshot {
        let start=now.addingTimeInterval(-48*3600)
        let matches=messages.filter { access.briefEnabled && access.chats.contains($0.chat) && $0.time >= start.timeIntervalSince1970*1000 && $0.time <= now.timeIntervalSince1970*1000 }
            .sorted { $0.time == $1.time ? $0.id < $1.id : $0.time > $1.time }
        return .init(messages:Array(matches.prefix(40)),total:matches.count,start:start,end:now)
    }
    static func matches(_ messages: [WhatsAppReadMessage], allowed: Set<String>, chat: String?, query: String, start: Date, end: Date) -> [WhatsAppReadMessage] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return messages.filter { item in
            let date=Date(timeIntervalSince1970:item.time/1000)
            return allowed.contains(item.chat) && (chat == nil || chat == item.chat) && date >= start && date < end && terms.allSatisfy { (item.text + " " + item.sender).lowercased().contains($0) }
        }.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time > $1.time }
    }
    static func search(_ messages: [WhatsAppReadMessage], allowed: Set<String>, chat: String?, query: String, start: Date, end: Date, offset: Int) -> (page: [WhatsAppReadMessage], total: Int) {
        let found=matches(messages,allowed:allowed,chat:chat,query:query,start:start,end:end)
        return (Array(found.dropFirst(max(0,offset)).prefix(30)),found.count)
    }
}

struct WhatsAppSearchCursor {
    let allowed: Set<String>
    let chat: String?
    let query: String
    let start: Date
    let end: Date
    let fetched: Date
    private let matches: [WhatsAppReadMessage]
    init(messages: [WhatsAppReadMessage], allowed: Set<String>, chat: String?, query: String, start: Date, end: Date, fetched: Date = .now) {
        self.allowed=allowed;self.chat=chat;self.query=query.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
        self.start=start;self.end=end;self.fetched=fetched
        matches=WhatsAppReadRules.matches(messages,allowed:allowed,chat:chat,query:query,start:start,end:end)
    }
    func page(messages: [WhatsAppReadMessage], allowed: Set<String>, chat: String?, query: String, start: Date, end: Date, offset: Int) throws -> (page: [WhatsAppReadMessage], total: Int) {
        guard allowed == self.allowed, chat == self.chat, query.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator:" ") == self.query, start == self.start, end == self.end else { throw WhatsAppSearchFailure.restart }
        let fresh=WhatsAppReadRules.matches(messages,allowed:allowed,chat:chat,query:query,start:start,end:end)
        guard fresh == matches else { throw WhatsAppSearchFailure.changed }
        return (Array(matches.dropFirst(max(0,offset)).prefix(30)),matches.count)
    }
}
enum WhatsAppSearchFailure: LocalizedError {
    case restart, changed
    var errorDescription: String? {
        switch self {
        case .restart: return "Start this WhatsApp search at page 0 in the current turn before requesting later pages."
        case .changed: return "The relevant WhatsApp cache changed during this search. Start again at page 0; previous results may be outdated."
        }
    }
}

struct WhatsAppReadEvent: Decodable {
    var snapshotID: String?
    var status: String?
    var connected: Bool?
    var png: String?
    var messages: [WhatsAppReadMessage]?
    var coverage: String?
    var chats: [WhatsAppChat]?
    var identity: String?
    var namesBusy:Bool?
    var namesStatus:String?
    var revoked: Bool?
}
