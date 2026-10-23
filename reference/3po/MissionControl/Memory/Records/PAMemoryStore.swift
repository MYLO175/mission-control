import Foundation
import Observation
import SwiftData

@MainActor @Observable final class PAMemoryStore {
    private(set) var state = MemoryEnvelope()
    var records: [PAMemory] { state.records }
    private(set) var error: String?
    private(set) var revision = UUID()
    /// Human controls have their own generation; ordinary fact saves do not revoke an owned job.
    private(set) var controlsRevision = UUID()
    /// Reading saved memory is independent of permission to learn new facts.
    private(set) var useRevision = UUID()
    var enabled = true { didSet { if !restoringSettings && enabled != oldValue { settings.set(enabled,forKey:"paMemoryEnabled"); revision = UUID(); controlsRevision = UUID();useRevision = UUID() } } }
    var learningEnabled = true { didSet { if !restoringSettings && learningEnabled != oldValue { settings.set(learningEnabled,forKey:"paMemoryLearningEnabled");revision = UUID();controlsRevision = UUID() } } }
    private let settings: UserDefaults
    @ObservationIgnored private var restoringSettings = true
    private let container: ModelContainer?
    private var writable = true
    private var loadedBytes: Data?
    private var reviewPreferenceMigration: ReviewPreferenceConversion.Receipt?
    private(set) var reviewPreferenceMigrationReadable = true
    private(set) var reviewPreferenceMigrationError: String?
    @ObservationIgnored var notebookProjection: ((LifeNotebook,String,UUID?,Bool)->LifeNotebook)?
    @ObservationIgnored var notebookProjectionRevision: (() -> UUID)?
    @ObservationIgnored private var preparedNotebook: (key: NotebookKey, value: LifeNotebook)?
    @ObservationIgnored private var preparedLexical: (revision: UUID, value: MemoryLexicalIndex)?
    @ObservationIgnored private(set) var notebookBuildCount = 0
    private struct NotebookKey: Equatable {
        var memory: UUID
        var workspace: UUID?
        var registration: String
        var topic: UUID?
        var includeTopics: Bool
        var suppliedIDs: Set<UUID>
        var currentIDs: Set<UUID>
    }
    @ObservationIgnored var sourceIsPermitted:(PAMemory)->Bool = { _ in false }
    @ObservationIgnored var sourcePermissionProjection:(()->Set<UUID>)?
    var permittedRecords:[PAMemory] {
        guard records.contains(where:{$0.source != nil}) else {return records}
        let projected=sourcePermissionProjection?()
        return records.filter{record in record.source == nil || (!record.sourceSuppressionKeys.contains{state.suppressed[record.registration,default:[]].contains($0)} && (projected.map{$0.contains(record.id)} ?? sourceIsPermitted(record)))}
    }
    #if DEBUG
    func loadReviewFixture(_ records:[PAMemory]) {
        guard ProcessInfo.processInfo.arguments.contains("--preview-memory-review") else { return }
        _=change{$0.records=records}
    }
    #endif
    func sourceAssessmentDate(_ key:String)->Date? { state.sourceAssessmentReceipts?[key] }
    init(container: ModelContainer?, settings: UserDefaults = .standard) {
        self.container = container
        self.settings = settings
        enabled = settings.object(forKey:"paMemoryEnabled") as? Bool ?? true
        learningEnabled = settings.object(forKey:"paMemoryLearningEnabled") as? Bool ?? true
        do {
            if let container {
                reviewPreferenceMigration = try ReviewPreferenceConversion.run(repository: LocalRecordRepository(container: container))
            }
            loadedBytes = try LocalRecordRepository.read("paMemory", container: container)
            if let record = loadedBytes {
                state = try MemoryEnvelope.decode(record)
                guard Set(records.map(\.id)).count == records.count else { throw MemoryLearningFailure.invalid }
            }
        } catch {
            writable = false
            reviewPreferenceMigrationReadable = false
            reviewPreferenceMigrationError = "Saved memory or older attention preferences could not be safely converted. Original records are preserved; changes are disabled."
            self.error = reviewPreferenceMigrationError
        }
        restoringSettings = false
    }
    /// Old advice may retain exact legacy receipts. Validate only the immutable
    /// conversion proof and unchanged current memory; never retrieve legacy data.
    func matchesConvertedReviewPreference(id: String, revision: String, registration: String, direction: String) -> Bool {
        guard enabled, reviewPreferenceMigrationReadable, let proof = reviewPreferenceMigration?.items.first(where: {
            $0.memory.id.uuidString == id && $0.legacyRevision.uuidString == revision && $0.memory.registration == registration && $0.direction == direction
        }) else { return false }
        let expected=MemoryDependencyRules.fingerprint(MemoryRetrieval.record(proof.memory))
        return records.contains { $0.id == proof.memory.id && MemoryRules.usable($0, registration: registration) && MemoryDependencyRules.fingerprint(MemoryRetrieval.record($0)) == expected }
    }
    func items(_ registration: String) -> [PAMemory] { records.filter { $0.registration == registration }.sorted { $0.reviewed > $1.reviewed } }
    func suppressed(_ registration: String) -> Set<String> { state.suppressed[registration] ?? [] }
    var canSaveReviewPreference:Bool {writable && container != nil}
    func reviewPreferences(_ registration:String,includeRetired:Bool=false)->[PAMemory] {
        records.filter{$0.registration == registration && $0.source == nil && $0.reviewPreference == true && $0.supersededBy == nil && (includeRetired || MemoryRules.usable($0,registration:registration))}.sorted{$0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created > $1.created}
    }
    /// Exact human evidence stays separate from optional contextual interpretation.
    @discardableResult func saveReviewPreference(_ text:String,registration:String,expected:PAMemory? = nil,about:String="",interpretation:ReviewFeedbackInterpretation? = nil,id:UUID=UUID())->Bool {
        let words=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !registration.isEmpty,!words.isEmpty,words.count <= 2000,about.count <= 300,interpretation?.valid ?? true else {error="Check your feedback and its interpretation before saving.";return false}
        if let expected {guard records.first(where:{$0.id == expected.id}) == expected,expected.registration == registration,expected.reviewPreference == true,expected.source == nil,expected.supersededBy == nil else {error="This memory changed. Reopen it before saving.";return false}}
        else if records.contains(where:{$0.id == id}) {error="This feedback already has a saved memory. Reopen it before making another change.";return false}
        let inferred=interpretation != nil && interpretation?.humanEdited != true
        var value=PAMemory(registration:registration,text:interpretation?.rule ?? words,kind:.preference,explicit:!inferred,provenance:inferred ? "Interpreted from your Review feedback and email" : expected == nil ? "Your Review feedback" : "Review preference edited by you",evidence:interpretation?.humanEdited == true ? interpretation?.rule : words,sourceDate:.now,certainty:inferred ? .inferred : .stated,durability:.stable)
        value.id=id
        value.reviewPreference=true;value.reviewContext=about.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? nil : about.trimmingCharacters(in:.whitespacesAndNewlines);value.retiredAt=expected?.retiredAt
        value.reviewInterpretation=interpretation;value.reviewFeedback=words
        return expected.map{correct($0.id,with:value)} ?? put(value)
    }
    @discardableResult func put(_ memory: PAMemory) -> Bool {
        guard !memory.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !memory.registration.isEmpty else { return false }
        var value = memory; value.text = String(value.text.prefix(2000)); value.reviewed = .now
        if value.reviewInterpretation?.rule != nil,value.reviewInterpretation?.rule != value.text {value.reviewInterpretation=nil;value.reviewFeedback=value.text}
        let old=records.first{$0.id == value.id}
        if let old,old.reviewPreference == true,value.kind != .preference {
            value.id=UUID()
            return correct(old.id,with:value)
        }
        value.commitmentGroup=value.kind == .commitment && old?.kind == .commitment && old?.registration == value.registration && old?.conversationID == value.conversationID ? old?.commitmentGroup : nil
        value.commitmentGroupRevision=value.commitmentGroup != nil ? old?.commitmentGroupRevision : nil
        return change { state in if let i = state.records.firstIndex(where:{ $0.id == value.id }) { state.records[i] = value } else { state.records.append(value) } }
    }
    @discardableResult func forget(_ id: UUID) -> Bool {
        let family=versionFamily(id),ids=Set(family.map(\.id))
        return change { state in
            var owners=state.sourceForgetOwners ?? [:],baseline=state.sourceSuppressionBaseline ?? [:]
            for memory in family {
                if let turn=memory.sourceTurnID { state.suppressed[memory.registration,default:[]].insert(turn) }
                for key in memory.sourceSuppressionKeys {
                    // A legacy suppression without an owner is never removed by a newer Undo.
                    if state.suppressed[memory.registration,default:[]].contains(key) && owners[memory.registration]?[key] == nil { baseline[memory.registration,default:[]].insert(key) }
                    var account=owners[memory.registration] ?? [:]
                    account[key,default:[]].insert(memory.id);owners[memory.registration]=account
                    state.suppressed[memory.registration,default:[]].insert(key)
                }
            }
            state.sourceForgetOwners=owners;state.sourceSuppressionBaseline=baseline
            state.records.removeAll { ids.contains($0.id) }
            for index in state.records.indices {
                let record=state.records[index]
                if record.sourceSuppressionKeys.contains(where:{state.suppressed[record.registration,default:[]].contains($0)}) { state.records[index].sourceInvalidation = .forgotten }
            }
        }
    }
    /// Forget a current belief's whole correction lineage; an explicitly selected earlier version only removes that version.
    func versionFamily(_ id:UUID)->[PAMemory] {
        guard let record=records.first(where:{$0.id == id}) else { return [] }
        guard record.supersededBy == nil else { return [record] }
        let byID=Dictionary(records.filter{$0.registration == record.registration}.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        var result=[record],seen:Set<UUID>=[id],cursor=record
        while let previous=cursor.supersedes,seen.insert(previous).inserted,let value=byID[previous] { result.append(value);cursor=value }
        return result
    }
    /// Inspection follows either direction without changing Forget's deliberately narrower semantics.
    func lineage(_ id:UUID)->[PAMemory] {
        guard let initial=records.first(where:{$0.id == id}) else { return [] }
        let account=Dictionary(records.filter{$0.registration == initial.registration}.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        var ids:Set<UUID>=[id],pending=[id]
        while let next=pending.popLast(),let record=account[next] {
            for link in [record.supersedes,record.supersededBy].compactMap({$0}) where account[link] != nil && ids.insert(link).inserted { pending.append(link) }
        }
        return records.filter{ids.contains($0.id)}.sorted{$0.created == $1.created ? $0.id.uuidString < $1.id.uuidString : $0.created < $1.created}
    }
    @discardableResult func restoreForgotten(_ records:[PAMemory])->Bool {
        guard !records.isEmpty,Set(records.map(\.id)).count == records.count,records.allSatisfy({record in !self.records.contains(where:{$0.id == record.id})}) else { error="Memory changed after Forget; restoration stopped.";return false }
        return change { state in
            state.records.append(contentsOf:records)
            var owners=state.sourceForgetOwners ?? [:]
            for record in records {
                for key in record.sourceSuppressionKeys {
                    guard var account=owners[record.registration],var ids=account[key] else { continue }
                    ids.remove(record.id)
                    if ids.isEmpty {
                        account.removeValue(forKey:key)
                        if state.sourceSuppressionBaseline?[record.registration]?.contains(key) != true { state.suppressed[record.registration,default:[]].remove(key) }
                    } else { account[key]=ids }
                    owners[record.registration]=account
                }
            }
            state.sourceForgetOwners=owners
            for index in state.records.indices where state.records[index].sourceInvalidation == .forgotten {
                let record=state.records[index]
                if !record.sourceSuppressionKeys.contains(where:{state.suppressed[record.registration,default:[]].contains($0)}) { state.records[index].sourceInvalidation=nil }
            }
        }
    }
    /// Only an executor with a captured source snapshot can call this. No ingestion is enabled by this API.
    /// Human memories cannot be overwritten by a source fact, even if the wording matches.
    @discardableResult func putSource(_ value:PAMemory,sourceText:String,expectedRevision:UUID)->Bool {
        putSources([value],sourceTexts:[value.id:sourceText],expectedRevision:expectedRevision)
    }
    @discardableResult func putSources(_ values:[PAMemory],sourceTexts:[UUID:String],expectedRevision:UUID)->Bool {
        let evidenceTexts=Dictionary(values.compactMap{value in value.source.flatMap{source in sourceTexts[value.id].map{(source.identity,$0)}}},uniquingKeysWith:{first,_ in first})
        return putSources(values,evidenceTexts:evidenceTexts,expectedRevision:expectedRevision)
    }
    /// A source may supersede only an issued, current provisional belief from that same conversation.
    /// Every quotation is checked, and the old/new version links are saved in one transaction.
    @discardableResult func putSources(_ values:[PAMemory],evidenceTexts:[MemorySourceIdentity:String],expectedRevision:UUID,assessmentIDs:[String]=[],replacementSources:[UUID:MemorySourceEvidence]=[:],now:Date = .now)->Bool {
        guard revision == expectedRevision,assessmentIDs.count <= 8,Set(assessmentIDs).count == assessmentIDs.count,assessmentIDs.allSatisfy({$0.range(of:"^source-assessment:[a-f0-9]{64}$",options:.regularExpression) != nil}) else { error="Source assessment identity or captured state changed.";return false }
        if !assessmentIDs.isEmpty && assessmentIDs.allSatisfy({state.sourceAssessmentReceipts?[$0] != nil}) { return true }
        guard values.count <= 4,Set(values.map(\.id)).count == values.count,
              Set(values.compactMap(\.supersedes)).count == values.compactMap(\.supersedes).count,
              values.allSatisfy({ value in
            guard let source=value.source,let sourceText=evidenceTexts[source.identity],value.commitmentGroup == nil,value.commitmentGroupRevision == nil,value.allSourceEvidence.count <= 3,
                  Set(value.allSourceEvidence.map(\.identity)).count == value.allSourceEvidence.count,
                  value.allSourceEvidence.allSatisfy({evidence in evidence.identity.kind == source.identity.kind && evidence.identity.accountID == source.identity.accountID && evidence.identity.containerID == source.identity.containerID && evidence.identity.linkedIdentity == source.identity.linkedIdentity && evidenceTexts[evidence.identity].map{evidence.valid(in:$0)} == true}),
                  (value.supportingSources ?? []).allSatisfy({evidence in guard let date=evidence.sourceDate,let primaryDate=source.sourceDate else { return false };return date <= primaryDate}),
                  value.sourceState == nil || value.kind == .commitment else { return false }
            if let previous=value.supersedes {
                guard let old=records.first(where:{$0.id == previous}),MemoryRules.usable(old,registration:value.registration,now:now),!old.explicit,old.sourceTurnID == nil,old.source != nil,
                      old.organisation?.manual != true,source.identity.kind == old.source?.identity.kind,source.identity.accountID == old.source?.identity.accountID,
                      source.identity.containerID == old.source?.identity.containerID,source.identity.linkedIdentity == old.source?.identity.linkedIdentity else { return false }
                if source.identity.kind != .whatsapp {
                    // Mutable native items retain their old quote in version history. A changed
                    // due/start/received date is not required, and stale quotes are not dependencies.
                    guard replacementSources[previous] == old.source,source.identity == old.source?.identity,
                          source.revision != old.source?.revision,source.observed > old.source!.observed,
                          value.allSourceEvidence.count == 1,sourceIsPermitted(value) else { return false }
                } else {
                    guard sourceIsPermitted(old),value.allSourceEvidence.contains(where:{$0.identity == old.source?.identity && $0.revision == old.source?.revision}),
                          let date=source.sourceDate,let oldDate=old.source?.sourceDate,date > oldDate else { return false }
                }
            }
            return !value.registration.isEmpty && value.sourceInvalidation == nil && value.sourceTurnID == nil && value.conversationID == nil && !value.explicit && value.certainty == .inferred && value.durability == .situational && value.kind != .preference && !value.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && value.text.count <= 500 && value.evidence == source.quote && MemoryConnection.valid(value.connections,human:sourceText) && value.organisation?.selfName == nil && value.organisation?.manual != true && (value.organisation.map({LifeMemoryOrganisation.valid($0,record:value)}) ?? true) && value.supersededBy == nil && !records.contains(where:{$0.id == value.id})
        }) else { error="Source memory failed its evidence or captured-state checks.";return false }
        let fresh=values.filter { value in !value.sourceSuppressionKeys.contains{state.suppressed[value.registration,default:[]].contains($0)} && !records.contains(where:{$0.registration == value.registration && MemoryLearningRules.normalised($0.text) == MemoryLearningRules.normalised(value.text) && ($0.explicit || ($0.source?.identity == value.source?.identity && $0.source?.revision == value.source?.revision))}) }
        guard !fresh.isEmpty || !assessmentIDs.isEmpty else { return true }
        return change { state in
            for var value in fresh {
                if let previous=value.supersedes,let index=state.records.firstIndex(where:{$0.id == previous}) {
                    if value.kind == .commitment { value.commitmentGroup=state.records[index].commitmentGroup }
                    state.records[index].supersededBy=value.id
                }
                state.records.append(value)
            }
            if !assessmentIDs.isEmpty {
                var receipts=(state.sourceAssessmentReceipts ?? [:]).filter{$0.value >= now.addingTimeInterval(-7*86400)}
                for id in assessmentIDs { receipts[id]=now }
                let sorted=receipts.sorted { left,right in
                    if left.value == right.value { return left.key < right.key }
                    return left.value > right.value
                }
                var retained:[String:Date]=[:]
                for item in sorted.prefix(4000) { retained[item.key]=item.value }
                state.sourceAssessmentReceipts=retained
            }
        }
    }
    /// Invalidate only the exact observed version, so delayed edits cannot hide a newer belief.
    @discardableResult func invalidateSource(_ identity:MemorySourceIdentity,registration:String,previousRevision:String,reason:MemorySourceInvalidation)->Bool {
        let ids=Set(records.filter{$0.registration == registration && $0.allSourceEvidence.contains{$0.identity == identity && $0.revision == previousRevision} && $0.sourceInvalidation == nil}.map(\.id))
        guard !ids.isEmpty else { return true }
        return change { state in for index in state.records.indices where ids.contains(state.records[index].id) { state.records[index].sourceInvalidation=reason } }
    }
    @discardableResult func accept(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].explicit = true; state.records[i].reviewed = .now } } }
    @discardableResult func resolve(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].resolved = .now } } }
    @discardableResult func reopen(_ id: UUID) -> Bool { change { state in if let i = state.records.firstIndex(where:{ $0.id == id }) { state.records[i].resolved = nil; state.records[i].reviewed = .now } } }
    /// A local human review connects identities, not facts, truth states or native tasks.
    @discardableResult func connectCommitments(_ first:UUID,_ second:UUID,registration:String,expectedRevision:UUID)->Bool {
        let available=enabled ? permittedRecords : []
        guard revision == expectedRevision,let a=available.first(where:{$0.id == first && $0.registration == registration}),let b=available.first(where:{$0.id == second && $0.registration == registration}),CommitmentRules.linkable(a,b) else { error="These reports changed, are unavailable, or already belong to different plans. Reopen them before connecting.";return false }
        let group=a.commitmentGroup ?? b.commitmentGroup ?? UUID()
        let current=records.filter{$0.registration == registration && $0.conversationID == a.conversationID && $0.supersededBy == nil && $0.commitmentGroup == group}
        guard Set(current.map(\.id)).union([first,second]).count <= 12 else { error="This plan already has 12 reports. Keep separate plans rather than combine more.";return false }
        return change { state in for index in state.records.indices where state.records[index].id == first || state.records[index].id == second { state.records[index].commitmentGroup=group } }
    }
    @discardableResult func disconnectCommitment(_ id:UUID,registration:String,expectedRevision:UUID)->Bool {
        guard revision == expectedRevision,let record=records.first(where:{$0.id == id && $0.registration == registration}),record.kind == .commitment,record.supersededBy == nil else { error="This report changed. Reopen it before disconnecting.";return false }
        return change { state in if let index=state.records.firstIndex(where:{$0.id == id}) { state.records[index].commitmentGroup=nil;state.records[index].commitmentGroupRevision=nil } }
    }
    /// A human chooses what to set aside. This never deletes evidence or edits a workspace item.
    @discardableResult func retire(_ id:UUID,retired:Bool,expectedRevision:UUID)->Bool {
        guard revision == expectedRevision,let record=records.first(where:{$0.id == id}),record.source == nil,record.kind != .commitment,record.supersededBy == nil else { error="Memory changed, or this record uses commitment/source history instead. Nothing was retired.";return false }
        return change { state in if let index=state.records.firstIndex(where:{$0.id == id}) {
            state.records[index].retiredAt=retired ? .now : nil
            if !retired { state.records[index].reviewed = .now }
        } }
    }
    /// Correct a current belief atomically, keeping the original ID, wording and evidence as history.
    @discardableResult func correct(_ id:UUID,with replacement:PAMemory)->Bool {
        guard let old=records.first(where:{$0.id == id}),old.supersededBy == nil,old.registration == replacement.registration,
              replacement.id != id,!records.contains(where:{$0.id == replacement.id}),!replacement.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { error="This is no longer the current memory, or its replacement is invalid.";return false }
        var next=replacement;next.text=String(next.text.prefix(2000));next.supersedes=id;next.supersededBy=nil;next.created = .now;next.reviewed = .now
        if next.kind != .preference,next.reviewPreference == true {next.reviewPreference=nil;next.reviewInterpretation=nil;next.reviewFeedback=nil;next.reviewContext=nil}
        if next.reviewInterpretation?.rule != nil,next.reviewInterpretation?.rule != next.text {next.reviewInterpretation=nil;next.reviewFeedback=next.text}
        next.commitmentGroup=next.kind == .commitment && next.conversationID == old.conversationID ? old.commitmentGroup : nil
        next.commitmentGroupRevision=next.commitmentGroup != nil ? old.commitmentGroupRevision : nil
        return change { state in if let index=state.records.firstIndex(where:{$0.id == id}) { state.records[index].supersededBy=next.id;state.records.append(next) } }
    }
    /// Restoration is itself a new correction, avoiding cycles or loss of intervening evidence.
    @discardableResult func restoreVersion(_ id:UUID)->Bool {
        guard let original=records.first(where:{$0.id == id}),original.supersededBy != nil else { return false }
        var current=original,seen=Set<UUID>()
        while let next=current.supersededBy {
            guard seen.insert(current.id).inserted,seen.count <= 100,let record=records.first(where:{$0.id == next && $0.registration == original.registration}) else { error="This memory history is incomplete; nothing was changed.";return false }
            current=record
        }
        var restored=original;restored.id=UUID();restored.conversationID=current.conversationID;restored.explicit=true;restored.certainty = .stated
        restored.resolved=nil;restored.retiredAt=nil;restored.source=nil;restored.supportingSources=nil;restored.sourceState=nil;restored.sourceInvalidation=nil;restored.sourceTurnID=nil;restored.provenance="Earlier version restored by you";restored.sourceDate = .now
        if restored.conversationID != nil { restored.organisation?.selfName=nil }
        return correct(current.id,with:restored)
    }
    @discardableResult func merge(_ learned: [LearnedMemory], registration: String, sourceDates: [String:Date] = [:], sourceTopics: [String:UUID] = [:], now: Date = .now) -> Bool {
        change { state in
            for entry in learned where !state.suppressed[registration,default:[]].contains(entry.turnID) {
                // Revisiting an old human turn must not resurrect its corrected belief under new prose.
                // Other distinct evidence in that rich turn remains eligible to be learned.
                guard !state.records.contains(where:{ old in
                    old.registration == registration && old.conversationID == sourceTopics[entry.turnID] && old.sourceTurnID == entry.turnID && (old.supersededBy != nil || old.retiredAt != nil) &&
                    (MemoryLearningRules.normalised(old.text) == MemoryLearningRules.normalised(entry.text) || old.evidence.map{MemoryLearningRules.normalised($0) == MemoryLearningRules.normalised(entry.evidence)} == true)
                }) else { continue }
                guard !state.records.contains(where:{  $0.source == nil && $0.registration == registration && $0.conversationID == sourceTopics[entry.turnID] && $0.supersededBy == nil && $0.resolved == nil && MemoryLearningRules.normalised($0.text) == MemoryLearningRules.normalised(entry.text) }) else { continue }
                state.records.append(PAMemory(registration:registration,text:entry.text,kind:entry.kind,explicit:false,provenance:"Learned from your conversation",created:now,reviewed:now,sourceTurnID:entry.turnID,evidence:entry.evidence,sourceDate:sourceDates[entry.turnID],conversationID:sourceTopics[entry.turnID],certainty:entry.certainty,durability:entry.durability,connections:entry.connections,organisation:entry.organisation))
            }
        }
    }
    @discardableResult func organise(_ id:UUID,value:LifeMemoryOrganisation,expectedRevision:UUID)->Bool {
        organise([LifeOrganisationEntry(id:id,organisation:value)],expectedRevision:expectedRevision)
    }
    @discardableResult func organise(_ entries:[LifeOrganisationEntry],expectedRevision:UUID)->Bool {
        guard revision == expectedRevision,Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ entry in records.first(where:{$0.id == entry.id}).map { LifeMemoryOrganisation.valid(entry.organisation,record:$0) && $0.organisation?.manual != true && entry.organisation.manual != true } ?? false }) else { error="Memory changed, organisation is pinned, or classification was invalid."; return false }
        guard !entries.isEmpty else { return true }
        return change { state in for entry in entries { if let index=state.records.firstIndex(where:{$0.id == entry.id}) { state.records[index].organisation=entry.organisation } } }
    }
    /// A local organisation edit is explicitly pinned and never changes the original fact/evidence.
    @discardableResult func setOrganisation(_ id:UUID,value:LifeMemoryOrganisation?)->Bool {
        guard let record=records.first(where:{$0.id == id}),value.map({LifeMemoryOrganisation.valid($0,record:record)}) ?? true else { return false }
        return change { state in if let index=state.records.firstIndex(where:{$0.id == id}) { var value=value; value?.manual=true; state.records[index].organisation=value } }
    }
    private func prepareNotebook(_ candidates: [PAMemory], registration: String, topic: UUID?, includeTopics: Bool, now: Date) -> LifeNotebook {
        let scoped = candidates.filter { $0.registration == registration && MemoryRules.inScope($0,conversationID:topic,includeTopics:includeTopics) }
        let key = NotebookKey(memory:revision,workspace:notebookProjectionRevision?(),registration:registration,topic:topic,includeTopics:includeTopics,suppliedIDs:Set(scoped.map(\.id)),currentIDs:Set(scoped.filter{MemoryRules.usable($0,registration:registration,now:now)}.map(\.id)))
        // Recheck permissions and temporal usability before every cache lookup.
        // Custom projections without a revision provider remain uncached.
        let cacheable = notebookProjection == nil || notebookProjectionRevision != nil
        if cacheable, let preparedNotebook, preparedNotebook.key == key { return preparedNotebook.value }
        let base = LifeNotebook.build(scoped,registration:registration,topic:topic,now:now,includeTopics:includeTopics)
        let value = notebookProjection?(base,registration,topic,includeTopics) ?? base
        notebookBuildCount += 1
        if cacheable { preparedNotebook = (key,value) }
        return value
    }
    func notebook(_ registration:String,topic:UUID? = nil,includeTopics:Bool=false,now:Date = .now,includeSources:Bool = true,sourceFilter:((PAMemory)->Bool)? = nil)->LifeNotebook {
        let candidates = (includeSources ? permittedRecords : records.filter{$0.source == nil}).filter{$0.source == nil || (sourceFilter?($0) ?? true)}
        return prepareNotebook(enabled ? candidates : [],registration:registration,topic:topic,includeTopics:includeTopics,now:now)
    }
    func selection(_ registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil, focus:[LifeArea] = [],includeSources:Bool = true,sourceFilter:((PAMemory)->Bool)? = nil,now:Date = .now) -> MemorySelection {
        guard enabled else {return MemorySelection(records:[],eligibleCount:0)}
        return selectionContext(registration,conversationID:conversationID,includeTopics:includeTopics,query:query,focus:focus,includeSources:includeSources,sourceFilter:sourceFilter,now:now).selection
    }
    /// Selection and notebook share one permission-filtered, current snapshot.
    func selectionContext(_ registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil, focus:[LifeArea] = [],includeSources:Bool = true,sourceFilter:((PAMemory)->Bool)? = nil,now:Date = .now) -> (selection:MemorySelection,notebook:LifeNotebook) {
        guard enabled else { return (MemorySelection(records:[],eligibleCount:0),prepareNotebook([],registration:registration,topic:conversationID,includeTopics:includeTopics,now:now)) }
        let candidates=(includeSources ? permittedRecords : records.filter{$0.source == nil}).filter{$0.source == nil || (sourceFilter?($0) ?? true)}
        let projected=prepareNotebook(candidates,registration:registration,topic:conversationID,includeTopics:includeTopics,now:now)
        if preparedLexical?.revision != revision { preparedLexical = (revision, MemoryLexicalIndex(records)) }
        return (MemoryRetrieval.select(candidates,registration:registration,conversationID:conversationID,includeTopics:includeTopics,query:query,now:now,focus:focus,notebook:projected,lexical:preparedLexical?.value),projected)
    }
    func context(_ registration: String, conversationID: UUID? = nil, includeTopics: Bool = false, query: String? = nil,includeSources:Bool = true,now:Date = .now) -> [[String:String]] {
        selection(registration,conversationID:conversationID,includeTopics:includeTopics,query:query,includeSources:includeSources,now:now).records
    }
    private func change(_ mutation: (inout MemoryEnvelope) -> Void) -> Bool {
        guard writable, let container else { error = "Memory storage is unavailable; nothing was changed."; return false }
        let old = state,previousGroups=CommitmentRules.memberships(state.records); mutation(&state)
        let groups=CommitmentRules.memberships(state.records)
        for key in groups.keys where groups[key] != previousGroups[key] {
            let version=UUID()
            for index in state.records.indices where state.records[index].supersededBy == nil && CommitmentRules.groupKey(state.records[index]) == key { state.records[index].commitmentGroupRevision=version }
        }
        do {
            let data = try LocalRecordCoding.preservingUnknown(state, original: ReviewPreferenceConversion.envelopeOriginal(loadedBytes))
            try LocalRecordRepository(container: container).write(["paMemory": data], expected: ["paMemory": LocalRecordVersion(loadedBytes)])
            loadedBytes = data
            revision = UUID(); error = nil; return true
        } catch { state = old; self.error = "Memory change could not be saved."; return false }
    }
}

/// A storage conversion, never a second retrieval path. The receipt retains the
/// original revision/evidence and proves an identical legacy batch was consumed.
enum ReviewPreferenceConversion {
    static let legacyKey = "reviewRelevancePreferences"
    static let receiptKey = "reviewPreferenceConversion.v1"
    struct Legacy: Codable {
        var id: UUID
        var registration: String
        var topic: String
        var direction: String
        var revision: UUID
        var inactive: Bool
    }
    struct Item: Codable {
        var legacyRevision: UUID
        var direction: String
        var memory: PAMemory
    }
    struct Receipt: Codable {
        var version = 1
        var original: Data
        var migratedAt: Date
        var items: [Item]
    }
    /// Preserve opaque fields even when converting the old bare memory array.
    static func envelopeOriginal(_ data: Data?) throws -> Data? {
        guard let data else { return nil }
        let value = try JSONSerialization.jsonObject(with: data)
        guard value is [Any] else { return data }
        return Data("{\"version\":1,\"records\":".utf8) + data + Data(",\"suppressed\":{}}".utf8)
    }
    @MainActor static func run(repository: LocalRecordRepository, now: Date = .now) throws -> Receipt? {
        let legacyBytes = try repository.read(legacyKey)
        let receiptBytes = try repository.read(receiptKey)
        let receipt = try receiptBytes.map { try JSONDecoder().decode(Receipt.self, from: $0) }
        if let receipt {
            guard receipt.version == 1, Set(receipt.items.map { $0.memory.id }).count == receipt.items.count else { throw LocalRecordFailure.unsupportedFields }
        }
        guard let legacyBytes else { return receipt }
        let memoryBytes = try repository.read("paMemory")
        if let receipt {
            // An identical old backup must not resurrect deleted/edited memories.
            guard receipt.original == legacyBytes else { throw LocalRecordFailure.changed }
            try repository.write([:], removing: [legacyKey], expected: [legacyKey: .bytes(legacyBytes), receiptKey: LocalRecordVersion(receiptBytes), "paMemory": LocalRecordVersion(memoryBytes)])
            return receipt
        }
        let values = try JSONDecoder().decode([Legacy].self, from: legacyBytes)
        guard let rows = try JSONSerialization.jsonObject(with: legacyBytes) as? [[String: Any]], rows.count == values.count,
              rows.allSatisfy({ Set($0.keys) == Set(["id", "registration", "topic", "direction", "revision", "inactive"]) }),
              Set(values.map(\.id)).count == values.count,
              values.allSatisfy({ !$0.registration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.topic.count <= 300 && ["more", "less"].contains($0.direction) }) else { throw LocalRecordFailure.unsupportedFields }
        var envelope = try memoryBytes.map(MemoryEnvelope.decode) ?? MemoryEnvelope()
        guard Set(envelope.records.map(\.id)).count == envelope.records.count,
              Set(envelope.records.map(\.id)).isDisjoint(with: values.map(\.id)) else { throw LocalRecordFailure.changed }
        let items = values.map { value -> Item in
            let words = (value.direction == "more" ? "Prioritise information about: " : "Give less attention to routine information about: ") + value.topic
            var memory = PAMemory(registration: value.registration, text: words, kind: .preference, explicit: true, provenance: "Your earlier Review attention choice (converted locally)", created: now, reviewed: now, retiredAt: value.inactive ? now : nil, evidence: value.topic, certainty: .stated, durability: .stable)
            memory.id = value.id
            memory.reviewPreference = true
            memory.reviewFeedback = words
            memory.reviewContext = value.topic
            return Item(legacyRevision: value.revision, direction: value.direction, memory: memory)
        }
        envelope.records.append(contentsOf: items.map(\.memory))
        let proof = Receipt(original: legacyBytes, migratedAt: now, items: items)
        let data = try LocalRecordCoding.preservingUnknown(envelope, original: envelopeOriginal(memoryBytes))
        try repository.write(["paMemory": data, receiptKey: JSONEncoder().encode(proof)], removing: [legacyKey], now: now, expected: [legacyKey: .bytes(legacyBytes), "paMemory": LocalRecordVersion(memoryBytes), receiptKey: .missing])
        return proof
    }
}
