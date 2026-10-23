import Foundation
import SwiftData

/// Fictional production-retrieval scenarios. Contract failures fail the suite; semantic
/// aspirations are measured separately so lexical success cannot claim paraphrase recall.
@main struct MemoryQualityChecks {
    @MainActor static func main() throws {
        // Process-only defaults prevent a human's memory-off setting changing this
        // fictional fixture, without writing their preferences or persistent store.
        UserDefaults.standard.setVolatileDomain(["paMemoryEnabled": true, "paMemoryLearningEnabled": true], forName: UserDefaults.argumentDomain)
        let now = Date.now
        var checks = 0, failures: [String] = []
        func check(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures.append(label); print("FAIL: \(label)") }
        }
        func fact(_ index: Int, _ text: String, area: LifeArea = .studies, account: String = "owner", kind: MemoryKind = .context) -> PAMemory {
            PAMemory(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!, registration: account, text: text, kind: kind, provenance: "Fictional quality fixture", created: now, reviewed: now, evidence: text, certainty: .stated, durability: .stable, organisation: .init(areas: [area], connections: []))
        }
        func ids(_ selection: MemorySelection) -> Set<UUID> {
            Set(selection.records.compactMap { $0["id"].flatMap(UUID.init(uuidString:)) })
        }
        func contextIDs(_ context: String, field: String = "facts") throws -> Set<String> {
            let json = try JSONSerialization.jsonObject(with: Data(context.utf8)) as! [String: Any]
            if field == "anchors" { return Set((json["lifeStructure"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }) }
            return Set((json["areas"] as? [[String: Any]] ?? []).flatMap { $0["facts"] as? [[String: String]] ?? [] }.compactMap { $0["id"] })
        }

        let shortFacts = [fact(1, "AI work is my main career priority.", area: .career), fact(2, "ML roles interest me.", area: .career), fact(3, "My CV needs a project section.", area: .career), fact(4, "I prefer UK employers.", area: .career)].map { record in
            var earlier = record
            earlier.created = now.addingTimeInterval(-45 * 86400)
            earlier.reviewed = earlier.created
            return earlier
        }
        let distractors = (100..<170).map { fact($0, "I enjoy fictional unrelated activity \($0).", area: .studies, kind: .preference) }
        let corpus = shortFacts + distractors
        for (index, query) in ["AI", "ml", "CV", "uk"].enumerated() {
            let selected = MemoryRetrieval.select(corpus, registration: "owner", query: query, now: now, focus: [.studies])
            check(ids(selected) == [shortFacts[index].id], "\(query) finds the older relevant fact under distractors and contrary Focus")
            check(selected.reasons[shortFacts[index].id]?.contains("Words match your question") == true, "\(query) has the production lexical reason")
        }
        check(MemoryRetrieval.tokens("AI, ML; CV / UK") == ["ai", "ml", "cv", "uk"], "Meaningful two-letter terms survive normalisation")
        check(MemoryRetrieval.tokens("I am at an AI event in the UK").contains("ai"), "Short terms survive in ordinary sentences")
        check(MemoryRetrieval.tokens("I me my to in on at an of or do it be we us he as so if").isEmpty, "Ordinary short filler remains excluded")
        for query in ["", "  ", "Please help me with this", "Me", "AI"] {
            let expected: Set<UUID> = query == "AI" ? [shortFacts[0].id] : []
            check(ids(MemoryRetrieval.select(corpus, registration: "owner", query: query, now: now, focus: [.studies])) == expected, "Targeted '\(query)' never uses Focus as unrelated filler")
        }
        check(!MemoryRetrieval.select(corpus, registration: "owner", query: nil, now: now, focus: [.studies]).records.isEmpty, "Null deliberately requests broad orientation")
        check(MemoryRetrieval.select(corpus, registration: "owner", query: "Unknown zephyr", now: now).records.isEmpty, "No matching saved fact is a valid answer")
        check(MemoryRetrieval.select(corpus, registration: "other", query: "AI", now: now).records.isEmpty, "Another account never supplies relevant-looking facts")
        let forward = MemoryRetrieval.select(corpus, registration: "owner", query: "AI ML CV UK", now: now)
        check(forward.records == MemoryRetrieval.select(corpus.reversed(), registration: "owner", query: "AI ML CV UK", now: now).records, "Retrieval ordering is independent of storage order")
        for bytes in [2, 500, 1_000, 20_000] {
            let selected = MemoryRetrieval.select(corpus, registration: "owner", query: nil, now: now, bytes: bytes)
            check(try JSONSerialization.data(withJSONObject: selected.records, options: [.sortedKeys]).count <= bytes, "Production record context stays within \(bytes) bytes")
        }

        var identity = fact(5, "My name is Alex.", area: .about)
        identity.organisation?.selfName = "Alex"
        var notebook = LifeNotebook.build(corpus + [identity], registration: "owner", now: now)
        notebook.anchors = [.init(id: "life:fictional-study", label: "Study folder", kind: "space", parent: nil, areas: [.studies], notes: "", path: [], relations: [])]
        for query in ["", "Alex", "please help me with this"] {
            let context = notebook.context(query: query, focus: [.studies])
            check(try contextIDs(context).isEmpty, "Notebook excludes unrelated facts for targeted '\(query)'")
            check(try contextIDs(context, field: "anchors").isEmpty, "Notebook excludes Focus-only anchors for targeted '\(query)'")
        }
        let aiSelection = MemoryRetrieval.select(corpus + [identity], registration: "owner", query: "AI", now: now, focus: [.studies], notebook: notebook)
        check(try contextIDs(notebook.context(query: "AI", focus: [.studies], selectedMemoryIDs: ids(aiSelection))) == [shortFacts[0].id.uuidString], "Notebook shares actual selected IDs without an independent refill")
        check(try contextIDs(notebook.context(query: nil, focus: [.studies]), field: "anchors") == ["life:fictional-study"], "Broad notebook orientation retains exact saved anchors")
        check(try contextIDs(notebook.context(query: "Study folder"), field: "anchors") == ["life:fictional-study"], "A matching anchor remains available without linked facts")

        // Disposable storage exercises real version, feedback and source-permission paths.
        let container = try ModelContainer(for: CachedDashboard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = PAMemoryStore(container: container)
        check(distractors.allSatisfy { store.put($0) }, "Fictional distractor corpus is saved")
        let old = fact(10, "I am building Lantern for my engineering project.", area: .projects)
        let renamed = fact(11, "I renamed my engineering project to Beacon.", area: .projects)
        check(store.put(old) && store.correct(old.id, with: renamed), "Project rename is a real versioned correction")
        check(ids(store.selection("owner", query: "Beacon engineering")) == [renamed.id], "Renamed current fact wins recall under unrelated preferences")
        check(store.selection("owner", query: "Lantern").records.isEmpty, "The superseded name cannot resurrect old prose")
        check(store.records.first(where: { $0.id == old.id })?.evidence == old.evidence, "Correction keeps the original evidence and identity")
        check(store.retire(renamed.id, retired: true, expectedRevision: store.revision), "Human retirement succeeds")
        check(store.selection("owner", query: "Beacon").records.isEmpty, "Retirement removes current recall")
        let reloaded = PAMemoryStore(container: container)
        check(reloaded.selection("owner", query: "Beacon").records.isEmpty, "Retirement survives reopening")
        check(reloaded.retire(renamed.id, retired: false, expectedRevision: reloaded.revision), "Human Restore brings retired context back")
        check(ids(reloaded.selection("owner", query: "Beacon")) == [renamed.id], "Restored current fact keeps its exact identity")
        check(reloaded.restoreVersion(old.id), "Earlier-version Restore creates a new current version")
        let restored = reloaded.records.first { $0.registration == "owner" && $0.supersededBy == nil && $0.supersedes == renamed.id }!
        check(restored.id != old.id && restored.id != renamed.id && restored.evidence == old.evidence, "Version Restore keeps evidence without reusing earlier identities")
        check(ids(reloaded.selection("owner", query: "Lantern")) == [restored.id], "Restored belief becomes the sole relevant version")
        let lineage = reloaded.versionFamily(restored.id)
        check(reloaded.forget(restored.id), "Forget removes the current correction lineage")
        check(reloaded.selection("owner", query: "Lantern Beacon").records.isEmpty && Set(reloaded.records.map(\.id)).isDisjoint(with: Set(lineage.map(\.id))), "Forgotten versions cannot enter recall")
        check(reloaded.restoreForgotten(lineage), "Forget Undo restores original stored identities")
        check(ids(reloaded.selection("owner", query: "Lantern")) == [restored.id], "Forget Undo retains the original current version and evidence")

        let feedback = "These can stay quiet, but new stages and results matter to me."
        check(reloaded.saveReviewPreference(feedback, registration: "owner", about: "Graduate assessment confirmations"), "Human feedback saves into canonical memory")
        let preference = reloaded.reviewPreferences("owner")[0]
        let feedbackResult = reloaded.selection("owner", query: "Graduate assessment receipt")
        check(ids(feedbackResult) == [preference.id] && feedbackResult.records.first?["text"] == feedback && feedbackResult.records.first?["evidence"] == feedback, "Topic relevance supplies exact conditional feedback and evidence")
        check(reloaded.selection("owner", query: "Supermarket discounts").records.isEmpty, "Feedback is not pinned to unrelated questions")
        check(reloaded.selection("other", query: "Graduate assessment").records.isEmpty, "Feedback remains account-owned")
        check(reloaded.retire(preference.id, retired: true, expectedRevision: reloaded.revision) && reloaded.selection("owner", query: "Graduate assessment").records.isEmpty, "Disabled feedback leaves recall without losing history")
        check(reloaded.retire(preference.id, retired: false, expectedRevision: reloaded.revision) && ids(reloaded.selection("owner", query: "Graduate assessment")) == [preference.id], "Restored feedback regains its original identity")

        let rawFeedback="These emails aren't important"
        let rule="Routine University Internal Communications team newsletters can stay quiet. Personal requests and new obligations still matter."
        let interpretation=ReviewFeedbackInterpretation(rule:rule,sender:"University Internal Communications team <updates@university.example.invalid>",subject:"Key information for autumn term",accountID:"fictional-mail",messageID:"fictional-newsletter",internetMessageID:"newsletter@example.invalid",headerFingerprint:String(repeating:"a",count:64),bodyFingerprint:String(repeating:"b",count:64),model:"fictional-model")
        check(reloaded.saveReviewPreference(rawFeedback,registration:"contextual",about:"Key information for autumn term",interpretation:interpretation),"Contextual feedback saves a reasoned preference")
        let learned=reloaded.reviewPreferences("contextual")[0]
        check(learned.text == rule && learned.text != rawFeedback && learned.evidence == rawFeedback && learned.reviewFeedback == rawFeedback && learned.certainty == .inferred && !learned.explicit,"Usable memory is the interpretation; exact human words remain evidence")
        let future=reloaded.selection("contextual",query:"University Internal Communications team <updates@university.example.invalid> Campus travel update")
        check(ids(future) == [learned.id] && future.records.first?["text"] == rule,"New subject from the same communications sender recalls the reasoned preference")
        check(reloaded.selection("contextual",query:"Footwear Shop <sales@retail.example.invalid> Discounts").records.isEmpty,"Unrelated shop email does not recall the preference")
        check(reloaded.selection("other",query:"University Internal Communications team").records.isEmpty,"Contextual preference remains account-owned")
        let reloadedLearned=PAMemoryStore(container:container).reviewPreferences("contextual")[0]
        check(reloadedLearned == learned,"Interpretation and exact context receipt survive reload")
        let receipt=MemoryDependencyRules.capture(future.records)
        var edited=interpretation;edited.rule="Prioritise University Internal Communications team newsletters.";edited.humanEdited=true
        check(reloaded.saveReviewPreference(rawFeedback,registration:"contextual",expected:learned,about:"University Internal Communications team",interpretation:edited),"Human edits reasoned preference with version history")
        let revisedLearned=reloaded.reviewPreferences("contextual")[0]
        check(revisedLearned.text == edited.rule && revisedLearned.evidence == edited.rule && revisedLearned.reviewFeedback == rawFeedback && revisedLearned.explicit && revisedLearned.supersedes == learned.id,"Edited interpretation is human evidence and original feedback remains inspectable")
        check(!MemoryDependencyRules.available(receipt,records:reloaded.selection("contextual",query:"University Internal Communications team").records),"Editing the learned preference invalidates old advice receipts")
        var genericEdit=revisedLearned;genericEdit.id=UUID();genericEdit.text="I only want occasional campus notices.";genericEdit.evidence=genericEdit.text
        check(reloaded.correct(revisedLearned.id,with:genericEdit),"General memory correction preserves the canonical lineage")
        let corrected=reloaded.reviewPreferences("contextual")[0]
        check(corrected.reviewInterpretation == nil && corrected.reviewFeedback == genericEdit.text,"General correction cannot retain a contradictory old interpretation")
        check(reloaded.retire(corrected.id,retired:true,expectedRevision:reloaded.revision) && reloaded.selection("contextual",query:"campus notices").records.isEmpty,"Disabling reasoned preference withdraws recall")
        check(reloaded.retire(corrected.id,retired:false,expectedRevision:reloaded.revision) && ids(reloaded.selection("contextual",query:"campus notices")) == [corrected.id],"Restore retains the preference identity")
        check(reloaded.forget(corrected.id) && reloaded.reviewPreferences("contextual",includeRetired:true).isEmpty,"Forget removes contextual preference lineage")
        check(reloaded.saveReviewPreference(rawFeedback,registration:"kind-conversion",interpretation:interpretation),"Learned preference is available for explicit kind conversion")
        let originalKind=reloaded.reviewPreferences("kind-conversion")[0]
        var newKind=originalKind;newKind.kind = .context
        check(reloaded.put(newKind),"Generic memory editor can convert a learned preference without changing prose")
        let converted=reloaded.records.first{$0.registration == "kind-conversion" && $0.supersededBy == nil}!
        check(converted.id != originalKind.id && converted.supersedes == originalKind.id && converted.kind == .context && converted.reviewPreference == nil && converted.reviewInterpretation == nil && converted.text == originalKind.text && converted.evidence == originalKind.evidence && MemoryRules.usable(converted,registration:"kind-conversion"),"Kind conversion retains history and evidence while clearing incompatible review metadata")
        var malformed=learned;malformed.reviewInterpretation?.rule="A conflicting rule"
        check(!MemoryRules.usable(malformed,registration:"contextual"),"Malformed interpretation is preserved but unavailable for recall")
        check(MemoryRules.needsReview(learned,now:learned.reviewed.addingTimeInterval(91*86400)),"Inferred preference retains the existing 90-day provisional review boundary")

        let quote = "The robotics meeting has moved to Friday."
        let source = MemorySourceEvidence(identity: .init(kind: .mail, accountID: "fictional-mail", containerID: "Inbox", itemID: "message-1"), revision: "version-1", label: "Fictional organiser", quote: quote, observed: now, sourceDate: now)
        let report = PAMemory(registration: "owner", text: quote, kind: .commitment, explicit: false, provenance: "Fictional source report", reviewed: now, evidence: quote, certainty: .inferred, durability: .situational, source: source, sourceState: .changed)
        check(reloaded.putSource(report, sourceText: quote, expectedRevision: reloaded.revision), "Exact fictional source evidence saves through the production gate")
        check(reloaded.selection("owner", query: "Robotics meeting").records.isEmpty, "Absent runtime permission excludes source memory")
        reloaded.sourceIsPermitted = { $0.source?.revision == "version-1" }
        check(ids(reloaded.selection("owner", query: "Robotics meeting")) == [report.id], "Current permitted source version is recalled")
        check(reloaded.selection("owner", query: "Robotics meeting", includeSources: false).records.isEmpty, "Human-only consumers exclude source reports")
        check(reloaded.selection("owner", query: "Robotics meeting", sourceFilter: { _ in false }).records.isEmpty, "Purpose-specific consent can exclude an otherwise permitted source")
        reloaded.sourceIsPermitted = { _ in false }
        check(reloaded.selection("owner", query: "Robotics meeting").records.isEmpty && reloaded.records.contains { $0.id == report.id && $0.resolved == nil }, "Source cache/access loss hides evidence without claiming completion or deleting it")
        reloaded.sourceIsPermitted = { _ in true }
        check(reloaded.invalidateSource(source.identity, registration: "owner", previousRevision: "version-1", reason: .changed), "Exact changed source version invalidates")
        check(reloaded.selection("owner", query: "Robotics meeting").records.isEmpty && reloaded.records.contains { $0.id == report.id }, "Invalidated source history is preserved outside recall")

        // Matched retrieval cases and hard negatives. These exercise existing local
        // production selection, including cached indexes containing unusable records.
        var localCases: [(String, [PAMemory], Set<UUID>)] = []
        let inflections = [
            ("application", "My graduate applications close in November."),
            ("responsibility", "My responsibilities include coordinating the robotics team."),
            ("meeting", "My supervision meetings take place on Fridays."),
            ("deadlines", "The coursework deadline is next Tuesday."),
            ("organisation", "Organization of the lab equipment is my job."),
            ("prioritising", "Prioritizing graduate recruitment is important this term.")
        ]
        for (offset, pair) in inflections.enumerated() {
            let relevant = fact(300 + offset, pair.1)
            localCases.append((pair.0, [relevant] + distractors, [relevant.id]))
        }
        let acronym = fact(320, "I take Probabilistic Machine Learning (PML).")
        let courseDeadline = fact(321, "Probabilistic Machine Learning coursework is due on Friday.")
        let machineOnly = fact(322, "The machine workshop closes at five.")
        let learningOnly = fact(323, "I enjoy learning piano.")
        let unrelatedAcronym = fact(324, "Project Management Lab (PML) meets weekly.")
        localCases.append(("PML", [acronym, courseDeadline, machineOnly, learningOnly] + distractors, [acronym.id, courseDeadline.id]))
        let mlExpansion = fact(325, "My career interest is Machine Learning (ML).", area: .career)
        let mlDetails = fact(326, "Machine Learning roles with research responsibility interest me.", area: .career)
        localCases.append(("ML", [mlExpansion, mlDetails, machineOnly, learningOnly], [mlExpansion.id, mlDetails.id]))
        for (offset, pair) in [("James", "My friend Jame plays cricket."), ("Mars", "I have a mar on my table."), ("class", "I own a classic car."), ("organ", "I study organisation theory.")].enumerated() {
            localCases.append((pair.0, [fact(340 + offset, pair.1)], []))
        }
        // Exact retrieval should remain unchanged, including the negative topic boundaries.
        let exactSupervision = fact(350, "My supervision takes place on Fridays.")
        localCases.append(("supervision", [exactSupervision, machineOnly], [exactSupervision.id]))
        var localHits = 0, localExpected = 0, localSelected = 0, localWrong = 0
        for (query, records, desired) in localCases {
            let actual = ids(MemoryRetrieval.select(records, registration: "owner", query: query, now: now, focus: [.career]))
            localHits += actual.intersection(desired).count; localExpected += desired.count
            localSelected += actual.count; localWrong += actual.subtracting(desired).count
            check(actual == desired, "Local matched/negative query '\(query)' retrieves exactly the supported facts")
        }
        print("LOCAL QUALITY MEASURE: relevant recall \(localHits)/\(localExpected); precision \(localHits)/\(localSelected); irrelevant \(localWrong); cases \(localCases.count). Fictional matched vocabulary, not general semantic quality.")
        let abbreviationReason = MemoryRetrieval.select([acronym, courseDeadline], registration: "owner", query: "PML", now: now).reasons[courseDeadline.id]
        check(abbreviationReason?.contains("Matches an abbreviation explicitly recorded by you") == true && abbreviationReason?.contains("Words match your question") == false, "Derived abbreviation recall explains its actual reason without claiming literal words")
        let ambiguousRecords = [acronym, courseDeadline, unrelatedAcronym]
        check(ids(MemoryRetrieval.select(ambiguousRecords, registration: "owner", query: "PML", now: now)) == [acronym.id, unrelatedAcronym.id], "Conflicting explicit abbreviation meanings do not expand to an arbitrary course")
        var otherAccountAlias = acronym; otherAccountAlias.id = fact(360, "").id; otherAccountAlias.registration = "other"
        var retiredAlias = acronym; retiredAlias.id = fact(361, "").id; retiredAlias.retiredAt = now
        var supersededAlias = acronym; supersededAlias.id = fact(362, "").id; supersededAlias.supersededBy = UUID()
        var topicAlias = acronym; topicAlias.id = fact(363, "").id; topicAlias.conversationID = UUID()
        var inferredAlias = acronym; inferredAlias.id = fact(364, "").id; inferredAlias.explicit = false; inferredAlias.certainty = .inferred
        var sourceAlias = acronym; sourceAlias.id = fact(365, "").id; sourceAlias.source = source
        for alias in [otherAccountAlias, retiredAlias, supersededAlias, topicAlias, inferredAlias, sourceAlias] {
            let records = [alias, courseDeadline]
            let lexical = MemoryLexicalIndex(records)
            let selected = MemoryRetrieval.select(records, registration: "owner", query: "PML", now: now, lexical: lexical)
            check(!ids(selected).contains(courseDeadline.id), "An unavailable, foreign, scoped, inferred or source declaration cannot extend a cached-index query")
        }
        let globalCache = MemoryLexicalIndex([acronym, courseDeadline])
        check(MemoryRetrieval.select([courseDeadline], registration: "owner", query: "PML", now: now, lexical: globalCache).records.isEmpty, "Removing the alias declaration from the eligible candidate set removes its cached influence")
        var foreignConflict = unrelatedAcronym; foreignConflict.registration = "other"
        check(ids(MemoryRetrieval.select([acronym, courseDeadline, foreignConflict], registration: "owner", query: "PML", now: now, lexical: MemoryLexicalIndex([acronym, courseDeadline, foreignConflict]))) == [acronym.id, courseDeadline.id], "A foreign account's conflicting abbreviation does not poison the current account")
        let undeclared = fact(366, "Probabilistic Machine Learning coursework closes Friday.")
        check(MemoryRetrieval.select([undeclared], registration: "owner", query: "PML", now: now).records.isEmpty, "Initialisms are never guessed from capital letters alone")
        let nearName = fact(367, "Probability Machine Learning coursework closes Friday.")
        check(ids(MemoryRetrieval.select([acronym, nearName], registration: "owner", query: "PML", now: now)) == [acronym.id], "A similar course name does not inherit another course's abbreviation")
        let falseDeclaration = fact(368, "My Banana Project (PML) is unrelated to the course.")
        check(ids(MemoryRetrieval.select([falseDeclaration, courseDeadline], registration: "owner", query: "PML", now: now)) == [falseDeclaration.id], "Parentheses without matching initials create no inferred alias")
        let ownNamedAlias = fact(369, "My name is PML.", area: .about)
        var ownName = ownNamedAlias; ownName.organisation?.selfName = "PML"
        check(MemoryRetrieval.select([ownName, acronym, courseDeadline], registration: "owner", query: "PML", now: now).records.isEmpty, "An own-name-only query cannot seed abbreviation expansion")
        let commonApplications = (400..<430).map { fact($0, "I track applications for fictional employer \($0).", area: .career) }
        let specific = fact(431, "Beacon is recruiting this autumn.", area: .career)
        check(ids(MemoryRetrieval.select(commonApplications + [specific], registration: "owner", query: "Beacon applications", now: now, limit: 1)) == [specific.id], "Distinctive topic words outrank frequent long vocabulary under a tight context cap")
        let bounded = MemoryRetrieval.select(commonApplications + [specific, acronym, courseDeadline], registration: "owner", query: "PML applications Beacon", now: now, bytes: 1500)
        check(try JSONSerialization.data(withJSONObject: bounded.records, options: [.sortedKeys]).count <= 1500, "Abbreviation and morphological matches still obey the exact byte cap")
        check(MemoryRetrieval.select(commonApplications + [specific, acronym, courseDeadline], registration: "owner", query: "PML applications Beacon", now: now, limit: 2).records.count <= 2, "Improved ranking still obeys the exact record cap")
        let longQuery = String(repeating: "ordinary query payload ", count: 1000) + "PML"
        check(ids(MemoryRetrieval.select([acronym, courseDeadline, machineOnly, learningOnly], registration: "owner", query: longQuery, now: now)) == [acronym.id, courseDeadline.id], "A long query adds no partial expansion phrase matches")


        // Measure semantic aspirations with desired relevance, without asserting that a
        // known miss is a passing capability or freezing that limitation into a contract.
        let semanticFacts = [fact(20, "I want to work in artificial intelligence.", area: .career), fact(21, "I favour employers in Britain.", area: .career)]
        let exploratory = [("ML careers", semanticFacts[0].id), ("UK roles", semanticFacts[1].id)]
        var hits = 0, irrelevant = 0
        for (query, desired) in exploratory {
            let selected = ids(MemoryRetrieval.select(semanticFacts + distractors, registration: "owner", query: query, now: now))
            hits += selected.contains(desired) ? 1 : 0
            irrelevant += selected.subtracting([desired]).count
            if !selected.contains(desired) { print("QUALITY GAP: '\(query)' missed the semantically relevant fictional fact") }
        }
        print("QUALITY MEASURE: paraphrase recall \(hits)/\(exploratory.count); irrelevant selected facts \(irrelevant). This does not measure actual model answers.")
        print("CONTRACT CHECKS: \(checks - failures.count)/\(checks) passed; \(failures.count) failed. Fictional data; no inference or native source reads.")
        if !failures.isEmpty { exit(1) }
    }
}
