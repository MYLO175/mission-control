import Foundation

extension DashboardModel {
    func contextPageDependenciesAvailable(_ versions:[String:String]?,registration:String)->Bool {
        ContextPageDependencyRules.available(versions) {self.contextKnowledgeAvailable(registration:registration,versions:$0)}
    }
    func whatsappDependenciesAvailable(_ dependencies:[WhatsAppWindowDependency]?,use:AutomaticMemoryUse)->Bool {
        guard let dependencies,!dependencies.isEmpty else { return true }
        let access=whatsapp.access(for:chatGPT.activeID)
        guard assistant.contextEnabled,use.allowsWhatsApp(enabled:access.enabled,brief:access.briefEnabled,suggestions:access.includeInSuggestions == true,heartbeat:heartbeat.whatsappEnabled),dependencies.count <= MemoryDependencyRules.sourceChatLimit,Set(dependencies.map(\.chatID)).count == dependencies.count else { return false }
        return dependencies.allSatisfy { value in
            !value.linkedIdentity.isEmpty && value.linkedIdentity == whatsapp.linkedIdentity && access.chats.contains(value.chatID) &&
            whatsapp.windowFingerprint(chat:value.chatID) == value.fingerprint
        }
    }
    private func automaticMemorySourceAllowed(_ record:PAMemory,use:AutomaticMemoryUse)->Bool {
        record.allSourceEvidence.allSatisfy { source in
            switch source.identity.kind {
            case .calendar,.reminder:return true // Current projection already checks exact native versions and filters.
            case .mail:return emailSummaries.enabled
            case .whatsapp:
                let access=whatsapp.access(for:record.registration)
                return use.allowsWhatsApp(enabled:access.enabled,brief:access.briefEnabled,suggestions:access.includeInSuggestions == true,heartbeat:heartbeat.whatsappEnabled)
            }
        }
    }
    func automaticMemory(_ use:AutomaticMemoryUse,query:String? = nil,mailAccounts:Set<String>? = nil,whatsappReady:Bool = true)->AutomaticMemoryCapture {
        // A source assessment without a retrieval subject must not fall back to a biography.
        // The daily brief remains an explicitly broad day-planning consumer.
        let selection=PAWorkingContext.prepare(memory:assistant.memory,registration:chatGPT.activeID,purpose:use == .brief ? .dailyBrief : .suggestions,query:query ?? (use == .brief ? nil : ""),includeTopics:false,sourceFilter:{record in
            self.automaticMemorySourceAllowed(record,use:use) && record.allSourceEvidence.allSatisfy{source in
                (source.identity.kind != .mail || mailAccounts?.contains(source.identity.accountID) ?? true) && (source.identity.kind != .whatsapp || whatsappReady)
            }
        },includeNotebook:false).selection
        let selected=Set(selection.records.compactMap{$0["id"]})
        var chats=Set(assistant.memory.records.filter{selected.contains($0.id.uuidString)}.flatMap(\.allSourceEvidence).filter{$0.identity.kind == .whatsapp}.map{$0.identity.containerID})
        let purpose = ContextKnowledgePurpose(rawValue: use.rawValue) ?? .suggestions
        let pages=captureContextPages(registration:chatGPT.activeID,query:query ?? (use == .brief ? nil : ""),includeTopics:false,everyday:false,purpose:purpose,mailAccounts:mailAccounts,whatsappReady:whatsappReady,includeSourceChanges:use == .brief)
        let versions=pages.current() ? pages.referenceVersions : [:]
        chats.formUnion(assistant.memory.permittedRecords.filter { pages.memoryIDs.contains($0.id) }.flatMap(\.allSourceEvidence).filter { $0.identity.kind == .whatsapp }.map { $0.identity.containerID })
        let supplied = Set(versions.keys)
        chats.formUnion(contextKnowledge(registration:chatGPT.activeID,includeTopics:false,purpose:purpose,mailAccounts:mailAccounts,whatsappReady:whatsappReady).filter { supplied.contains($0.reference.contextKey) }.compactMap(\.whatsappChatID))
        return .init(records:selection.records,dependencies:MemoryDependencyRules.capture(selection.records),eligibleCount:selection.eligibleCount,whatsappChats:chats,pageContext:versions.isEmpty ? "{}" : AutomaticMemoryCapture.pagePayload(pages.text),contextPageDependencies:versions,workspaceIDs:pages.workspaceIDs)
    }
    func memoryDependenciesAvailable(_ dependencies:[MemoryDependency]?,use:AutomaticMemoryUse)->Bool {
        guard let dependencies,!dependencies.isEmpty else { return true }
        return MemoryDependencyRules.available(dependencies,records:memoryDependencyRecords(dependencies,use:use).map(MemoryRetrieval.record))
    }
    func memoryDependencyRecords(_ dependencies:[MemoryDependency],use:AutomaticMemoryUse)->[PAMemory] {
        let ids=Set(dependencies.map(\.id))
        guard assistant.memory.enabled else {return []}
        let candidates=assistant.memory.records.filter {
            ids.contains($0.id.uuidString) && MemoryRules.usable($0,registration:chatGPT.activeID) &&
            MemoryRules.inScope($0,conversationID:nil,includeTopics:use == .brief) && automaticMemorySourceAllowed($0,use:use)
        }
        // Exact human-only dependencies need no source projection. Source-backed
        // candidates still pass the same suppression and current-evidence checks.
        guard candidates.contains(where:{$0.source != nil}) else {return candidates}
        let permitted=Set(assistant.memory.permittedRecords.map(\.id))
        return candidates.filter{permitted.contains($0.id)}
    }
}
