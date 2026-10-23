import Foundation

/// Fictional storage and completed classifier results; no personal sources or model-quality claim.
enum ReviewPolicyChecks {
    @MainActor static func run() throws {
        var data: Data?
        var writes = 0
        func store() -> ReviewPolicyStore {
            ReviewPolicyStore(load: {data}, persist: {next, expected in
                guard expected == data else {throw SummaryFailure.invalid}
                data = next; writes += 1
            })
        }
        let first = store(), original = first.policy("owner")
        precondition(original.isDefault && original.text == ReviewPolicyRules.defaultText && writes == 0)
        precondition(first.policy("other").registration == "other" && first.history("owner").isEmpty)
        let global = "Only surface direct personal requests, deadlines and changes to existing commitments; routine broadcasts stay quiet."
        precondition(first.save(global, registration: "owner", expected: original))
        let saved = first.policy("owner")
        precondition(saved.text == global && !saved.isDefault && saved.revision != original.revision)
        // Stage policy is present independently of words, examples, facts or source retrieval.
        precondition(saved.input["text"] == global && saved.input["revision"] == saved.revision)
        precondition(!first.save("Stale", registration: "owner", expected: original))
        precondition(!first.save("Other account", registration: "other", expected: saved))
        precondition(!first.save(" ", registration: "owner", expected: saved))
        precondition(!first.save(String(repeating: "a", count: ReviewPolicyRules.textLimit + 1), registration: "owner", expected: saved))
        let reopened = store()
        precondition(reopened.policy("owner") == saved && reopened.policy("other").isDefault)
        precondition(first.reset("owner", expected: saved))
        let reset = first.policy("owner")
        precondition(reset.isDefault && reset.text == original.text && reset.revision != original.revision)
        let earlier = first.history("owner").last!
        precondition(first.restore(earlier, expected: reset))
        let restored = first.policy("owner")
        precondition(restored.text == saved.text && restored.revision != saved.revision && first.history("owner").first?.restoredFrom == earlier.id)
        precondition(first.history("owner").count == 3)
        precondition(!first.restore(earlier, expected: first.policy("other")))
        // Another writer is detected against the exact persisted record before overwrite.
        let independent = store(), beforeIndependent = independent.policy("owner")
        precondition(independent.save("Show robotics results.", registration: "owner", expected: beforeIndependent))
        precondition(!first.save("Do not overwrite newer edits", registration: "owner", expected: restored))
        precondition(first.policy("owner") == independent.policy("owner"))
        let corrupt = Data("{broken legacy state".utf8)
        var corruptWrites = 0
        let blocked = ReviewPolicyStore(load: {corrupt}, persist: {_, _ in corruptWrites += 1})
        precondition(!blocked.readable && !blocked.save(global, registration: "owner", expected: blocked.policy("owner")) && corruptWrites == 0)
        let readOnly = ReviewPolicyStore(load: {nil}, persist: nil)
        precondition(!readOnly.writable && !readOnly.save(global, registration: "owner", expected: readOnly.policy("owner")))
        let failedData: Data? = nil
        let failure = ReviewPolicyStore(load: {failedData}, persist: {_, _ in throw SummaryFailure.invalid})
        precondition(!failure.save(global, registration: "owner", expected: failure.policy("owner")) && failure.history("owner").isEmpty && failedData == nil)
        let mismatch = ReviewPolicyStore(load: {nil}, persist: {_, _ in})
        precondition(!mismatch.save(global, registration: "owner", expected: mismatch.policy("owner")) && !mismatch.readable)

        // Negative decisions retain every supplied Review preference, not a generated summary's subset.
        let preference: [String: String] = ["id": UUID().uuidString, "purpose": "review preference", "text": "Routine university broadcasts can stay quiet.", "reviewAbout": "University newsletters"]
        let unrelated: [String: String] = ["id": UUID().uuidString, "text": "I study robotics."]
        let receipt = EmailReviewContextReceipt(policy: saved, memories: [preference, unrelated], discoveryRevision: nil)
        precondition(receipt.preferences == MemoryDependencyRules.capture([preference]))
        precondition(receipt.policy.matches(saved) && !receipt.policy.matches(reset))
        precondition(!ReviewPolicyRules.assessmentContextMatches(nil,policy:saved,discoveryRevision:nil),"Two absent legacy stamps do not prove the global policy actually used")
        precondition(!ReviewPolicyRules.assessmentContextMatches(nil,policy:saved,discoveryRevision:"legacy-feedback"),"Legacy feedback stamps alone cannot make an uncaptured policy current")
        precondition(ReviewPolicyRules.assessmentContextMatches(receipt,policy:saved,discoveryRevision:nil),"A real policy capture remains current with an intentionally empty discovery selection")
        precondition(!ReviewPolicyRules.assessmentContextMatches(receipt,policy:reset,discoveryRevision:nil),"Changed policy invalidates the exact captured assessment context")
        var discovered=receipt;discovered.discoveryRevision="selected-feedback-v1"
        precondition(ReviewPolicyRules.assessmentContextMatches(discovered,policy:saved,discoveryRevision:"selected-feedback-v1"))
        precondition(!ReviewPolicyRules.assessmentContextMatches(discovered,policy:saved,discoveryRevision:"selected-feedback-v2"),"New applicable feedback schedules reconsideration")
        precondition(MemoryDependencyRules.available(receipt.preferences, records: [preference, unrelated]))
        var corrected = preference; corrected["text"] = "Prioritise these broadcasts."
        precondition(!MemoryDependencyRules.available(receipt.preferences, records: [corrected, unrelated]))
        precondition(!MemoryDependencyRules.available(receipt.preferences, records: [unrelated]))
        let negative = EmailHeaderDecision(id: "quiet", registration: "owner", fingerprint: "f", received: .now, readBody: false, reviewContext: receipt)
        let reopenedNegative = try JSONDecoder().decode(EmailHeaderDecision.self, from: JSONEncoder().encode(negative))
        precondition(!reopenedNegative.readBody && reopenedNegative.reviewContext == receipt)

        let fields: [String: Any] = ["id": "fixture", "accountID": "fictional-mail", "account": "Fictional", "messageID": 1, "internetMessageID": "fixture@example.invalid", "sender": "Campus round-up <news@example.invalid>", "subject": "Activities around Cambridge", "received": "2026-10-21T09:00:00Z", "unread": true, "replied": false, "flagged": false]
        let message = try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: fields))
        func assessment(_ quote: String, attention: Bool = false, additional: [String: Any] = [:], context: EmailRelevanceContext = .init(), policy: ReviewPolicyCapture = original) throws -> EmailSummary {
            var output: [String: Any] = ["summary": "Fictional email", "attention": attention, "worthReading": true, "needsReply": false, "reason": attention ? "A direct personal request requires a decision." : "", "evidence": quote]
            output.merge(additional) {_, next in next}
            return try EmailSummary.decode(String(decoding: JSONSerialization.data(withJSONObject: output), as: UTF8.self), message: message, body: quote, registration: "owner", relevanceContext: context, reviewPolicy: policy)
        }
        let broadcast = try assessment("Explore societies, talks and exhibitions this week.")
        let promotion = try assessment("Save 20% before 31 October 2026.", additional: ["followUpDate": "2026-10-31", "followUpEvidence": "31 October 2026"])
        precondition(broadcast.worthReading == false && !EmailHighlightRules.needsReview(broadcast, replied: false))
        precondition(promotion.worthReading == false && promotion.followUpDate == nil && !EmailHighlightRules.visible(promotion))
        let direct = try assessment("Please confirm your interview attendance by 23 October.", attention: true)
        let changed = try assessment("Your booked interview has moved to 24 October.", attention: true)
        precondition(direct.attention && changed.attention && EmailHighlightRules.needsReview(direct, replied: false))
        let projectID = "life:" + UUID().uuidString
        let context = EmailRelevanceContext(workspace: [["id": projectID, "revision": UUID().uuidString, "title": "Robotics project"]])
        let quote = "New robotics dataset and evaluation results are available."
        let relevant = try assessment(quote, additional: ["personalRelevance": ["reason": "Evaluation data for the current robotics project", "evidence": quote, "workspaceIDs": [projectID]]], context: context)
        precondition(relevant.worthReading == true && !relevant.attention && relevant.personalRelevance?.workspace.first?.id == projectID)
        // Reproduce the model fixture's results case: exact source text alone is quiet,
        // while a citation to the supplied canonical feedback supports informational reading.
        let resultsQuote="Your fictional coding assessment results are ready to read."
        let resultsPreference:[String:String]=["id":UUID().uuidString,"purpose":"review preference","text":"Coding assessment results are important to me.","reviewAbout":"Coding assessment stages and results"]
        let resultsContext=EmailRelevanceContext(memories:[resultsPreference],memoryReceipts:MemoryDependencyRules.capture([resultsPreference]))
        let missingCitation=try assessment(resultsQuote,context:resultsContext)
        precondition(missingCitation.worthReading == false && missingCitation.personalRelevance == nil,"An uncited worthReading claim is not admitted just because positive feedback was supplied")
        let resultsRelevance:[String:Any]=["reason":"The human explicitly prioritises assessment results.","evidence":resultsQuote,"memoryIDs":[resultsPreference["id"]!]]
        let citedResults=try assessment(resultsQuote,additional:["personalRelevance":resultsRelevance],context:resultsContext)
        precondition(citedResults.worthReading == true && !citedResults.attention && citedResults.personalRelevance?.memories == resultsContext.memoryReceipts)
        for ids:[String:Any] in [["memoryIDs":[UUID().uuidString]],["preferenceIDs":[resultsPreference["id"]!]],["memoryIDs":[]]] {
            let invalidRelevance:[String:Any]=["reason":"The human explicitly prioritises assessment results.","evidence":resultsQuote].merging(ids){_,next in next}
            do {_ = try assessment(resultsQuote,additional:["personalRelevance":invalidRelevance],context:resultsContext);preconditionFailure("Unsupplied, misclassified or empty feedback citation admitted")}
            catch SummaryFailure.unsupportedEvidence {}
        }
        let humanPolicy = ReviewPolicyCapture(registration: "owner", revision: UUID().uuidString, text: "Show substantive robotics research results even when no action is required.", isDefault: false)
        let policyMatch: [String: Any] = ["reason": "The explicitly prioritised research results arrived.", "policyQuote": humanPolicy.text, "sourceQuote": quote]
        let priority = try assessment(quote, additional: ["policyRelevance": policyMatch], policy: humanPolicy)
        precondition(priority.worthReading == true && priority.policyRelevance?.policy?.matches(humanPolicy) == true && !priority.attention)
        var invalid = policyMatch; invalid["policyQuote"] = "Invented sender priority"
        do {_ = try assessment(quote, additional: ["policyRelevance": invalid], policy: humanPolicy); preconditionFailure("Invented policy quote accepted")} catch SummaryFailure.unsupportedEvidence {}
        do {_ = try assessment(quote, additional: ["policyRelevance": policyMatch]); preconditionFailure("Default policy used as a positive personal priority")} catch SummaryFailure.unsupportedEvidence {}
        let foreign = ReviewPolicyCapture(registration: "other", revision: humanPolicy.revision, text: humanPolicy.text, isDefault: false)
        do {_ = try assessment(quote, policy: foreign); preconditionFailure("Foreign policy accepted")} catch SummaryFailure.unsupportedEvidence {}
        // Saved informational cards remain persistent data; only new completed classifications are tightened.
        var previous = broadcast; previous.worthReading = true; previous.reviewPolicyVersion = 2
        let previousData = try JSONEncoder().encode(previous)
        let previousReadback = try JSONDecoder().decode(EmailSummary.self, from: previousData)
        precondition(previousReadback.worthReading == true && EmailHighlightRules.needsReview(previousReadback, replied: false))
        var withReceipt = priority; withReceipt.reviewContext = receipt
        let readback = try JSONDecoder().decode(EmailSummary.self, from: JSONEncoder().encode(withReceipt))
        precondition(readback.reviewContext == receipt && readback.policyRelevance == priority.policyRelevance)
        precondition(withReceipt.adviceRevision(replied: false) != priority.adviceRevision(replied: false))
        print("PASS Review policy: account ownership, global capture, persistence/CAS/readback, history/reset/restore, exact policy capture rollout, supplied feedback citation requirements, negative feedback receipts, quiet broadcasts/promotions, supported opportunities, direct requests/changes and preserved saved cards. No AI or source reads.")
    }
}
