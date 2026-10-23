import Foundation

struct LifeLinkOption: Identifiable {
    var reference: LifeReference
    var title: String
    var detail: String
    var id: String { reference.kind.rawValue + ":" + (reference.containerID ?? "") + ":" + reference.id }
}
@MainActor enum LifeWorkspaceContext {
    static func options(_ model: DashboardModel, registration: String, topic: UUID?, includeTopics: Bool) -> [LifeLinkOption] {
        guard registration == model.chatGPT.activeID else { return [] }
        let assistant = model.assistant
        var options: [LifeLinkOption] = assistant.projects.items(registration, topic: topic, includeTopics: includeTopics).map {
            .init(reference: .init(kind: .item, id: $0.id.uuidString), title: $0.title, detail: $0.kind.title)
        }
        if assistant.memory.enabled {
            options += assistant.memory.permittedRecords.filter { MemoryRules.usable($0, registration: registration) && (includeTopics || MemoryRules.inScope($0, conversationID: topic)) }.map {
                .init(reference: .init(kind: .memory, id: $0.id.uuidString), title: $0.text, detail: $0.attribution)
            }
        }
        guard assistant.contextEnabled else { return options }
        options += model.calendarData.events.filter { !assistant.excludedCalendars.contains($0.calendarID) }.map {
            .init(reference: .init(kind: .event, id: $0.id, containerID: $0.calendarID), title: $0.title, detail: "Calendar · " + $0.start.formatted(date: .abbreviated, time: .shortened))
        }
        options += model.reminderData.reminders.filter { !assistant.excludedLists.contains($0.listID) }.map {
            .init(reference: .init(kind: .reminder, id: $0.id, containerID: $0.listID), title: $0.title, detail: "Reminder · " + $0.sourceLabel)
        }
        options += model.mailData.messages.filter { !assistant.excludedAccounts.contains($0.accountID) }.prefix(200).map {
            .init(reference: .init(kind: .mail, id: $0.id, containerID: $0.accountID, contentRevision: $0.internetMessageID), title: $0.subject, detail: "Mail · " + $0.sender)
        }
        let access = model.whatsapp.access(for: registration)
        if access.enabled {
            let names = Dictionary(model.whatsapp.chats.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            options += model.whatsapp.messages.filter { access.chats.contains($0.chat) }.suffix(100).map {
                .init(reference: .init(kind: .whatsapp, id: $0.id, containerID: $0.chat, linkedIdentity: model.whatsapp.linkedIdentity, contentRevision: SourceContextRules.revision($0)), title: String($0.text.prefix(160)), detail: "WhatsApp · " + (names[$0.chat] ?? "Selected chat"))
            }
        }
        return options
    }
    static func resolve(_ reference: LifeReference, model: DashboardModel, registration: String, topic: UUID?, includeTopics: Bool) -> LifeLinkOption? {
        guard registration == model.chatGPT.activeID else { return nil }
        let assistant = model.assistant
        switch reference.kind {
        case .item:
            guard let id = UUID(uuidString:reference.id), let item = assistant.projects.items(registration, topic:topic, includeTopics:includeTopics).first(where: { $0.id == id }) else { return nil }
            return .init(reference:reference, title:item.title, detail:item.kind.title)
        case .memory:
            guard assistant.memory.enabled, let id = UUID(uuidString:reference.id), let item = assistant.memory.permittedRecords.first(where: { $0.id == id && MemoryRules.usable($0,registration:registration) && (includeTopics || MemoryRules.inScope($0,conversationID:topic)) }) else { return nil }
            return .init(reference:reference, title:item.text, detail:item.attribution)
        case .event:
            guard assistant.contextEnabled, let item = model.calendarData.events.first(where: { $0.id == reference.id && $0.calendarID == reference.containerID && !assistant.excludedCalendars.contains($0.calendarID) }) else { return nil }
            return .init(reference:reference, title:item.title, detail:"Calendar · " + item.start.formatted(date:.abbreviated,time:.shortened))
        case .reminder:
            guard assistant.contextEnabled, let item = model.reminderData.reminders.first(where: { $0.id == reference.id && $0.listID == reference.containerID && !assistant.excludedLists.contains($0.listID) }) else { return nil }
            return .init(reference:reference, title:item.title, detail:"Reminder · " + item.sourceLabel)
        case .mail:
            guard assistant.contextEnabled, let item = model.mailData.messages.first(where: { $0.id == reference.id && $0.accountID == reference.containerID && $0.internetMessageID == reference.contentRevision && !assistant.excludedAccounts.contains($0.accountID) }) else { return nil }
            return .init(reference:reference, title:item.subject, detail:"Mail · " + item.sender)
        case .whatsapp:
            let access = model.whatsapp.access(for:registration)
            guard assistant.contextEnabled, access.enabled, reference.linkedIdentity == model.whatsapp.linkedIdentity, let chat = reference.containerID, access.chats.contains(chat),
                  let item = model.whatsapp.messages.first(where: { $0.id == reference.id && $0.chat == chat }), SourceContextRules.revision(item) == reference.contentRevision else { return nil }
            let name = model.whatsapp.chats.first(where: { $0.id == chat })?.name ?? "Selected chat"
            return .init(reference:reference, title:String(item.text.prefix(160)), detail:"WhatsApp · " + name)
        }
    }
}
