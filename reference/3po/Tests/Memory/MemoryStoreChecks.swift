import Foundation
import SwiftData
@main struct Checks {
    @MainActor static func main() throws {
        let controlSuite="fictional-memory-controls-"+UUID().uuidString
        let controlSettings=UserDefaults(suiteName:controlSuite)!
        defer {controlSettings.removePersistentDomain(forName:controlSuite)}
        let controls=PAMemoryStore(container:nil,settings:controlSettings),initialControls=controls.controlsRevision
        let enabled=controls.enabled,learning=controls.learningEnabled
        controls.enabled=enabled;controls.learningEnabled=learning
        precondition(controls.controlsRevision == initialControls,"No-op memory settings retain ownership")
        controls.enabled.toggle();controls.enabled.toggle()
        precondition(controls.controlsRevision != initialControls && controls.enabled == enabled,"Off/on recall changes still revoke captured jobs")
        let recallControls=controls.controlsRevision
        controls.learningEnabled.toggle();controls.learningEnabled.toggle()
        precondition(controls.controlsRevision != recallControls && controls.learningEnabled == learning,"Off/on learning changes still revoke captured jobs")
        let configuration = ModelConfiguration(isStoredInMemoryOnly:true)
        let container = try ModelContainer(for:CachedDashboard.self,configurations:configuration)
        var store = PAMemoryStore(container:container)
        let reviewWords="Assessment submission confirmations can stay quiet. Assessment invitations, results and new stages are important to me."
        precondition(store.saveReviewPreference(reviewWords,registration:"review-account"))
        let preference=store.reviewPreferences("review-account")[0]
        precondition(preference.text == reviewWords && preference.evidence == reviewWords && preference.source == nil && preference.kind == .preference && preference.explicit && preference.conversationID == nil)
        let reviewReload=PAMemoryStore(container:container)
        precondition(reviewReload.reviewPreferences("review-account") == [preference] && reviewReload.reviewPreferences("other").isEmpty)
        precondition(reviewReload.selection("review-account",query:"coding assessment invitation",includeSources:false).records.first?["purpose"] == "review preference")
        precondition(reviewReload.selection("review-account",query:"unrelated shopping sale",includeSources:false).records.isEmpty)
        precondition(reviewReload.saveReviewPreference("Assessment results are important; routine submission receipts can stay quiet.",registration:"review-account",expected:preference))
        let revised=reviewReload.reviewPreferences("review-account")[0]
        precondition(revised.id != preference.id && revised.supersedes == preference.id && reviewReload.lineage(revised.id).count == 2 && reviewReload.records.first{$0.id == preference.id}?.evidence == reviewWords)
        precondition(!reviewReload.saveReviewPreference("Stale overwrite",registration:"review-account",expected:preference))
        precondition(reviewReload.retire(revised.id,retired:true,expectedRevision:reviewReload.revision) && reviewReload.reviewPreferences("review-account").isEmpty)
        precondition(reviewReload.retire(revised.id,retired:false,expectedRevision:reviewReload.revision) && reviewReload.reviewPreferences("review-account").count == 1)
        precondition(!reviewReload.saveReviewPreference("",registration:"review-account") && !reviewReload.saveReviewPreference(String(repeating:"x",count:2001),registration:"review-account"))
        precondition(reviewReload.forget(revised.id) && reviewReload.reviewPreferences("review-account").isEmpty)
        precondition(!store.forget(preference.id)) // A stale owner cannot overwrite the newer correction/Forget.
        store = PAMemoryStore(container:container)
        precondition(store.forget(preference.id))
        precondition(store.saveReviewPreference("These can stay quiet, but new deadlines matter.",registration:"context-account",about:"Assessment submission confirmations"))
        let contextual=store.reviewPreferences("context-account")[0]
        precondition(contextual.text == "These can stay quiet, but new deadlines matter." && contextual.reviewContext == "Assessment submission confirmations" && store.selection("context-account",query:"Coding assessment submitted",includeSources:false).records.first?["reviewAbout"] == contextual.reviewContext)
        precondition(store.selection("context-account",query:"Shopping discounts",includeSources:false).records.isEmpty)
        precondition(store.forget(contextual.id))
        let initialRevision = store.revision
        let learned = LearnedMemory(turnID:"one",text:"Needs two weeks notice",kind:.preference,evidence:"I need two weeks notice")
        let messageDate = Date(timeIntervalSince1970:1_790_000_000)
        precondition(store.merge([learned],registration:"account",sourceDates:["one":messageDate]))
        precondition(store.records.count == 1 && store.records[0].explicit == false && store.records[0].sourceTurnID == "one")
        precondition(store.revision != initialRevision)
        precondition(store.records[0].sourceDate == messageDate && store.records[0].evidence == learned.evidence)
        var duplicate = learned; duplicate.text = "NEEDS  TWO WEEKS NOTICE"
        precondition(store.merge([duplicate],registration:"account") && store.records.count == 1)
        let saved = store.records[0]
        precondition(store.accept(saved.id) && store.records[0].explicit)
        let reload = PAMemoryStore(container:container)
        precondition(reload.records[0].explicit && reload.records[0].sourceDate == messageDate)
        precondition(reload.forget(saved.id) && reload.records.isEmpty && reload.suppressed("account") == ["one"])
        let forgotten = PAMemoryStore(container:container)
        precondition(forgotten.records.isEmpty && forgotten.suppressed("account") == ["one"])
        precondition(forgotten.merge([learned],registration:"account") && forgotten.records.isEmpty)
        precondition(forgotten.put(saved) && forgotten.records.count == 1)
        precondition(forgotten.resolve(saved.id) && forgotten.context("account").isEmpty)
        precondition(forgotten.reopen(saved.id) && forgotten.context("account").count == 1)
        let undated = LearnedMemory(turnID:"legacy",text:"Uses a separate project list",kind:.context,evidence:"I use a separate project list")
        precondition(forgotten.merge([undated],registration:"account"))
        precondition(forgotten.records.first(where:{ $0.sourceTurnID == "legacy" })?.sourceDate == nil)
        let unavailable = PAMemoryStore(container:nil)
        let unavailableRevision = unavailable.revision
        precondition(!unavailable.put(saved) && unavailable.records.isEmpty)
        precondition(unavailable.revision == unavailableRevision)
        store = PAMemoryStore(container:container)
        let topic = UUID(), otherTopic = UUID()
        let topicEntry = PAMemory(registration:"scope-account",text:"My fictional study project is optics",kind:.context,provenance:"Test",conversationID:topic)
        let sharedEntry = PAMemory(registration:"scope-account",text:"I prefer short answers",kind:.preference,provenance:"Test")
        precondition(store.put(topicEntry) && store.put(sharedEntry))
        precondition(store.context("scope-account").count == 1)
        precondition(store.context("scope-account",conversationID:topic).count == 2)
        precondition(store.context("scope-account",conversationID:otherTopic).count == 1)
        precondition(store.context("scope-account",includeTopics:true).count == 2)
        let oldFact=store.records.first(where:{$0.id == sharedEntry.id})!,revision=store.revision
        let structure=LifeMemoryOrganisation(areas:[.about],connections:[],selfName:nil)
        precondition(store.organise(sharedEntry.id,value:structure,expectedRevision:revision))
        let organised=store.records.first(where:{$0.id == sharedEntry.id})!
        precondition(organised.text == oldFact.text && organised.evidence == oldFact.evidence && organised.reviewed == oldFact.reviewed && organised.id == oldFact.id)
        precondition(!store.organise(topicEntry.id,value:structure,expectedRevision:revision),"Reject a stale captured memory revision")
        let organisationRevision=store.revision
        let unknown=LifeOrganisationEntry(id:UUID(),organisation:structure)
        precondition(!store.organise([.init(id:topicEntry.id,organisation:structure),unknown],expectedRevision:organisationRevision))
        precondition(store.records.first(where:{$0.id == topicEntry.id})?.organisation == nil,"A malformed batch is atomic")
        precondition(store.setOrganisation(sharedEntry.id,value:structure))
        precondition(store.records.first(where:{$0.id == sharedEntry.id})?.organisation?.manual == true)
        precondition(!store.organise(sharedEntry.id,value:structure,expectedRevision:store.revision),"Automatic classification cannot overwrite a manual pin")
        precondition(PAMemoryStore(container:container).records.first(where:{$0.id == sharedEntry.id})?.organisation?.manual == true)
        let original=PAMemory(registration:"history",text:"I study Chemistry",kind:.context,provenance:"Human",sourceTurnID:"original-turn",evidence:"I study Chemistry")
        precondition(store.put(original))
        let savedOriginal=store.records.first(where:{$0.id == original.id})!
        var correction=original;correction.id=UUID();correction.text="I now study Physics";correction.evidence="I now study Physics";correction.sourceTurnID="correction-turn"
        precondition(store.correct(original.id,with:correction))
        precondition(store.records.first(where:{$0.id == original.id})?.text == savedOriginal.text && store.records.first(where:{$0.id == original.id})?.evidence == savedOriginal.evidence)
        precondition(store.context("history").map{$0["text"]} == [correction.text])
        let oldParaphrase=LearnedMemory(turnID:"original-turn",text:"Studying Chemistry",kind:.context,evidence:"I study Chemistry")
        let anotherFact=LearnedMemory(turnID:"original-turn",text:"Also plays tennis",kind:.context,evidence:"I also play tennis")
        precondition(store.merge([oldParaphrase,anotherFact],registration:"history"))
        precondition(!store.context("history").contains(where:{$0["text"] == oldParaphrase.text}),"Old evidence cannot resurrect a superseded belief with different wording")
        let otherID=store.records.first(where:{$0.registration == "history" && $0.text == anotherFact.text})!.id
        precondition(store.forget(otherID),"Distinct evidence in the same rich turn remains eligible")
        precondition(!store.correct(original.id,with:correction),"A stale earlier belief cannot be corrected again")
        let reloadedHistory=PAMemoryStore(container:container)
        precondition(reloadedHistory.context("history").count == 1 && reloadedHistory.restoreVersion(original.id))
        let restoredCurrent=reloadedHistory.records.first(where:{$0.registration == "history" && $0.supersededBy == nil})!
        precondition(restoredCurrent.id != original.id && restoredCurrent.id != correction.id && restoredCurrent.text == original.text)
        precondition(restoredCurrent.supersedes == correction.id && reloadedHistory.context("history").count == 1)
        let versions=reloadedHistory.versionFamily(restoredCurrent.id)
        precondition(versions.count == 3 && reloadedHistory.forget(restoredCurrent.id) && reloadedHistory.context("history").isEmpty)
        precondition(reloadedHistory.records.allSatisfy{$0.registration != "history"} && reloadedHistory.suppressed("history").isSuperset(of:["original-turn","correction-turn"]))
        precondition(reloadedHistory.restoreForgotten(versions) && reloadedHistory.context("history").map{$0["text"]} == [original.text])
        precondition(!reloadedHistory.restoreForgotten(versions),"Undo cannot duplicate a restored lineage")
        store = PAMemoryStore(container:container)
        let origin=MemorySourceIdentity(kind:.whatsapp,accountID:"source-account",containerID:"family",itemID:"message-1",linkedIdentity:"linked-test")
        let quote="Alex is starting a robotics project next week."
        let evidence=MemorySourceEvidence(identity:origin,revision:"version-1",label:"The Nest · fictional message",quote:quote,observed:.now,sourceDate:.now)
        let sourceFact=PAMemory(registration:"sources",text:"A family message mentions Alex starting a robotics project.",kind:.context,explicit:false,provenance:"Source assessment",evidence:quote,certainty:.inferred,durability:.situational,source:evidence)
        store.sourceIsPermitted={ _ in true }
        let sourceRevision=store.revision
        precondition(!store.putSource(sourceFact,sourceText:"Unrelated text",expectedRevision:sourceRevision))
        var unsafe=sourceFact;unsafe.explicit=true
        precondition(!store.putSource(unsafe,sourceText:quote,expectedRevision:sourceRevision),"A source cannot claim human confirmation")
        unsafe=sourceFact;unsafe.certainty = .stated
        precondition(!store.putSource(unsafe,sourceText:quote,expectedRevision:sourceRevision),"A sender's statement is not the owner's assertion")
        unsafe=sourceFact;unsafe.source?.identity.linkedIdentity=nil
        precondition(!store.putSource(unsafe,sourceText:quote,expectedRevision:sourceRevision),"WhatsApp source identity includes its linked account")
        var invalidBatch=sourceFact;invalidBatch.id=UUID();invalidBatch.evidence="Invented evidence"
        let beforeBatch=store.records.count
        precondition(!store.putSources([sourceFact,invalidBatch],sourceTexts:[sourceFact.id:quote,invalidBatch.id:quote],expectedRevision:sourceRevision))
        precondition(store.records.count == beforeBatch && store.revision == sourceRevision,"Malformed source batches never partially save")
        precondition(store.putSource(sourceFact,sourceText:quote,expectedRevision:sourceRevision))
        let afterSource=store.revision
        precondition(!store.putSource(sourceFact,sourceText:quote,expectedRevision:sourceRevision),"Stale source jobs cannot commit")
        var same=sourceFact;same.id=UUID()
        precondition(store.putSource(same,sourceText:quote,expectedRevision:afterSource) && store.records.filter{$0.registration == "sources"}.count == 1)
        precondition(store.context("sources").first?["certainty"]?.contains("source interpretation") == true)
        precondition(store.notebook("sources").eligibleCount == 1)
        precondition(store.notebook("sources",includeSources:false).eligibleCount == 0)
        precondition(store.notebook("sources",sourceFilter:{_ in false}).eligibleCount == 0)
        precondition(store.notebook("sources",sourceFilter:{_ in true}).eligibleCount == 1)
        precondition(store.invalidateSource(origin,registration:"other",previousRevision:"version-1",reason:.deleted) && store.context("sources").count == 1)
        precondition(store.invalidateSource(origin,registration:"sources",previousRevision:"old-version",reason:.changed) && store.context("sources").count == 1)
        precondition(store.invalidateSource(origin,registration:"sources",previousRevision:"version-1",reason:.accessRemoved) && store.context("sources").isEmpty)
        precondition(store.records.contains{$0.id == sourceFact.id},"Invalidation preserves the original evidence")
        let sourceReload=PAMemoryStore(container:container);sourceReload.sourceIsPermitted={ _ in true }
        precondition(sourceReload.records.first(where:{$0.id == sourceFact.id})?.sourceInvalidation == .accessRemoved && sourceReload.context("sources").isEmpty,"Invalidation survives restart")
        var forgettable=sourceFact;forgettable.id=UUID();forgettable.source?.revision="version-forget"
        precondition(store.putSource(forgettable,sourceText:quote,expectedRevision:store.revision))
        precondition(store.forget(forgettable.id))
        forgettable.id=UUID()
        precondition(store.putSource(forgettable,sourceText:quote,expectedRevision:store.revision) && !store.records.contains{$0.id == forgettable.id},"Forget suppresses source-version relearning")
        store.sourceIsPermitted={ _ in false }
        precondition(store.context("sources").isEmpty)
        store.sourceIsPermitted={ _ in true }
        precondition(store.context("sources",includeSources:false).isEmpty,"Automatic legacy briefs can use human-only memory")
        let budget=LearningBudget(container:container),clock=Date(timeIntervalSince1970:2_000_000_000)
        for pass in 0..<4 { precondition(budget.claim("quota",manual:false,now:clock.addingTimeInterval(Double(pass)*3600))) }
        let quotaReload=LearningBudget(container:container)
        precondition(!quotaReload.claim("quota",manual:false,now:clock.addingTimeInterval(5*3600)),"Shared automatic quota survives restart")
        precondition(quotaReload.claim("quota",manual:true,now:clock.addingTimeInterval(5*3600)),"Explicit bounded checks can bypass the automatic quota")
        precondition(quotaReload.claim("quota",manual:false,now:clock.addingTimeInterval(24*3600)),"A later local day has a new allowance")
        precondition(!quotaReload.claim("quota",manual:false,now:clock.addingTimeInterval(24*3600+300)),"Shared cooldown survives claims")
        let independentHuman=LearnedMemory(turnID:"source-confirming-human",text:sourceFact.text,kind:.context,evidence:"I am starting a robotics project",certainty:.stated,durability:.stable)
        precondition(store.merge([independentHuman],registration:"sources"))
        precondition(store.context("sources",includeSources:false).count == 1,"A later human statement is not lost by deduplication against a source guess")
        print("PASS: atomic learned merge/dedup, confirmation, reload, Forget suppression across reload, Undo restore, resolve/reopen and unavailable storage")
    }
}
