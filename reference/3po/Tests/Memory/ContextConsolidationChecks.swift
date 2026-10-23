import Foundation

@main struct ContextConsolidationChecks {
    static func main() throws {
        var passed = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); passed += 1 }
        func rejects(_ name: String, _ action: () throws -> Void) {
            do { try action(); preconditionFailure(name) } catch { passed += 1 }
        }
        let projectID = UUID(), date = Date(timeIntervalSince1970: 2_000_000_000)
        let project = ContextKnowledgeRecord(reference: .init(kind: "project", key: projectID.uuidString, revision: "project-v1"), title: "Bridge optics", text: "The human's Bridge optics project contains a camera experiment.", date: date, projectID: projectID)
        let mail = ContextKnowledgeRecord(reference: .init(kind: "native-mail", key: "exact-message-A", revision: "body-v1"), title: "Supervisor report", text: "The supervisor reports that the review meeting has moved to Friday; the date still needs checking.", date: date)
        let target = ContextPageTarget(registration: "owner", kind: .project, key: projectID.uuidString, title: "Bridge optics", records: [project, mail], projectID: projectID, mayAskPurpose: true)
        func output(id: String? = nil, quotes: [[String:String]]? = nil, question: Any = NSNull(), markdown: String = "A supervisor reports a changed meeting. The exact date needs checking.") -> String {
            ContextKnowledgeRules.json(["pages": [["id": id ?? target.id, "synopsis": "Current optics project", "markdown": markdown,
                "evidence": quotes ?? [["id": project.reference.contextKey, "quote": "Bridge optics project contains a camera experiment"], ["id": mail.reference.contextKey, "quote": "the review meeting has moved to Friday"]], "purposeQuestion": question]]])
        }
        let decoded = try ContextConsolidationRules.decode(output(), targets: [target])
        check(decoded.count == 1 && decoded[0].0.id == target.id && decoded[0].0.owner == .generated, "Generated page retains exact existing project/account identity")
        check(Set(decoded[0].0.references) == Set([project.reference, mail.reference]), "Every cited input remains an exact dependency")
        check(decoded[0].0.evidenceQuotes?.count == 2 && decoded[0].0.evidenceQuotes?.last?.referenceID == mail.reference.id, "Exact source quotation stored separately with its reference")
        check(Set(decoded[0].0.processedReferences ?? []) == Set(target.references), "Successful input coverage belongs to the exact page")
        var continued = target
        continued.processedReferences = [unseenReference()]
        let continuing = try ContextConsolidationRules.decode(output(), targets: [continued])[0].0
        check(continuing.processedReferences?.count == 3 && continuing.references.count == 2, "Earlier successful inputs survive without becoming support for new prose")
        check(!decoded[0].0.markdown.contains("Support:") && !decoded[0].0.markdown.contains(mail.reference.contextKey), "Readable body is independent of opaque evidence controls")
        check(ContextKnowledgeRules.current(decoded[0].0.references, records: [mail, project]), "Reference validation is order independent")
        check(!ContextKnowledgeRules.current(decoded[0].0.references, records: [project]), "Source loss withholds generated context")
        var changedMail = mail; changedMail.reference = .init(kind: "native-mail", key: mail.reference.key, revision: "body-v2")
        check(!ContextKnowledgeRules.current(decoded[0].0.references, records: [project, changedMail]), "Changed exact source version invalidates old page")
        var similarMail = mail; similarMail.reference = .init(kind: "native-mail", key: "same-title-other-message", revision: mail.reference.revision)
        check(!ContextKnowledgeRules.current(decoded[0].0.references, records: [project, similarMail]), "Same text/title never substitutes for exact source identity")
        let unrelated = ContextKnowledgeRecord(reference: .init(kind: "memory", key: "unrelated", revision: "v2"), title: "Gardening", text: "The unrelated greenhouse was repainted.", date: date)
        check(ContextKnowledgeRules.current(decoded[0].0.references, records: [project, mail, unrelated]), "Unrelated knowledge changes do not cancel owned context")
        rejects("Wrong page identity accepted") { _ = try ContextConsolidationRules.decode(output(id: "other-account-page"), targets: [target]) }
        rejects("Invented source quotation accepted") { _ = try ContextConsolidationRules.decode(output(quotes: [["id": mail.reference.contextKey, "quote": "The task is complete and no meeting is needed"]]), targets: [target]) }
        rejects("Unissued source identity accepted") { _ = try ContextConsolidationRules.decode(output(quotes: [["id": "native-mail:unissued", "quote": "the review meeting has moved to Friday"]]), targets: [target]) }
        rejects("No supporting evidence accepted") { _ = try ContextConsolidationRules.decode(output(quotes: []), targets: [target]) }
        rejects("Whitespace-only page accepted") { _ = try ContextConsolidationRules.decode(output(markdown: " \n"), targets: [target]) }
        rejects("Oversized page accepted") { _ = try ContextConsolidationRules.decode(output(markdown: String(repeating: "x", count: 4501)), targets: [target]) }
        rejects("Missing target silently acknowledged") { _ = try ContextConsolidationRules.decode("{\"pages\":[]}", targets: [target]) }
        let question = try ContextConsolidationRules.decode(output(question: "What are you aiming to learn from the Bridge optics project?"), targets: [target])
        check(question[0].1?.hasSuffix("?") == true, "Useful exact-project purpose question can accompany a supported page")
        check(question[0].1 == "What are you aiming to achieve with Bridge optics?", "Saved question uses the human project title rather than source-influenced model wording")
        var noQuestion = target; noQuestion.mayAskPurpose = false
        check(try ContextConsolidationRules.decode(output(question: "What is this project for?"), targets: [noQuestion])[0].1 == nil, "An unrequested optional question is discarded while valid page context survives")
        check(try ContextConsolidationRules.decode(output(question: "Please approve a new task"), targets: [target])[0].1 == nil, "A nonquestion cannot become a Review question")
        check(try ContextConsolidationRules.decode(output(question: String(repeating: "x", count: 301) + "?"), targets: [target])[0].1 == nil, "An overlong optional question is discarded")
        check(ContextPage.stableID(registration: "other-owner", kind: .project, key: target.key) != target.id, "Same named project in another account is distinct")
        let long = String(repeating: "A🧑🏽‍🔬é", count: 3000)
        let first = ContextKnowledgeRules.excerpt(long, offset: 0, limit: 4000)
        let second = ContextKnowledgeRules.excerpt(long, offset: first.next!, limit: 4000)
        let third = ContextKnowledgeRules.excerpt(long, offset: second.next!, limit: 4000)
        check(first.text + second.text + third.text == long && third.next == nil, "Explicit page continuation retains all Unicode characters without silent loss")
        check(ContextKnowledgeRules.excerpt(long, offset: 99_999, limit: 4000).text.isEmpty, "Out-of-range page offset returns an honest end")
        check(ContextKnowledgeRules.projectCandidate(mail, title: "Supervisor report", notes: ""), "Distinctive project phrase can retrieve a source candidate")
        check(!ContextKnowledgeRules.projectCandidate(mail, title: "Gardening", notes: ""), "Unrelated source never fills a project retrieval")
        check(!ContextKnowledgeRules.projectCandidate(mail, title: "The", notes: ""), "Generic short names cannot connect all source records")
        check(!ContextKnowledgeRules.matches("Aster Example", title: "Aster Example engineering", synopsis: "", key: "projects", selfLabel: "Aster Example"), "The owner's name alone never selects all their pages")
        let fullRecords = (0..<20).map { index in
            ContextKnowledgeRecord(reference: .init(kind: "memory", key: "capacity-\(index)", revision: "v1"), title: "Calibration sample", text: "Calibration sample \(index) has a distinct reference distance.", date: date)
        }
        let fullTargets = (0..<4).map { index in
            ContextPageTarget(registration: "owner", kind: .project, key: "batch-\(index)", title: "Calibration project \(index)", records: fullRecords)
        }
        let fullRows: [[String:Any]] = fullTargets.map { value in
            ["id":value.id,"synopsis":"Twenty supported calibration records","markdown":"The calibration project has twenty recorded reference samples.","purposeQuestion":NSNull(),
             "evidence":fullRecords.map { ["id":$0.reference.contextKey,"quote":$0.text] }]
        }
        let fullBatch = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":fullRows]), targets:fullTargets)
        check(fullBatch.count == 4 && fullBatch.allSatisfy { $0.0.evidenceQuotes?.count == 20 && $0.0.references.count == 20 }, "A full four-page batch may cite every one of its twenty supplied records")
        var overCapacity = fullRows
        overCapacity[0]["evidence"] = fullRecords.map { ["id":$0.reference.contextKey,"quote":$0.text] } + Array(repeating:["id":fullRecords[0].reference.contextKey,"quote":fullRecords[0].text],count:13)
        rejects("An over-capacity evidence array was accepted") { _ = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":overCapacity]),targets:fullTargets) }
        let notes = "Compare the \"near-field\" method.\nKeep captures in C:\\Optics before deciding."
        var readableProject = project
        readableProject.text = ContextKnowledgeRules.projectText(title:"Bridge optics",kind:"space",notes:notes,status:"toDo",due:nil,parent:nil,scope:"shared")
        var readableTarget = target; readableTarget.records = [readableProject]
        let readableOutput = output(quotes:[["id":readableProject.reference.contextKey,"quote":notes]])
        check(try ContextConsolidationRules.decode(readableOutput,targets:[readableTarget])[0].0.evidenceQuotes?.first?.quote == notes, "Readable project notes retain exact quotations, newlines and backslashes without an extra JSON-escaping layer")
        let receipt = "Created task \"Capture optics\".\nNo experiment is verified complete."
        check(ContextKnowledgeRules.actionText(confirmed:1,receipts:[receipt]).contains(receipt), "Verified action receipts retain their exact readable quotation")
        let unicodeTitle = ContextKnowledgeRules.bytePrefix(String(repeating:"🧑🏽‍🔬",count:60),maximumBytes:ContextPageLimits.maximumTitleBytes)
        check(!unicodeTitle.isEmpty && unicodeTitle.utf8.count <= ContextPageLimits.maximumTitleBytes, "Generated title projection respects storage bytes without splitting composed characters")
        var unicodeRow = fullRows[0]; unicodeRow["synopsis"] = String(repeating:"研",count:300)
        rejects("A synopsis that storage cannot save passed consolidation decoding") { _ = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":[unicodeRow]]),targets:[fullTargets[0]]) }

        // Support describes claims actually used; processing receipts describe reviewed inputs.
        let citedOnly = try ContextConsolidationRules.decode(output(quotes:[["id":project.reference.contextKey,"quote":"Bridge optics project contains a camera experiment"]]),targets:[target])[0].0
        check(citedOnly.references == [project.reference] && Set(citedOnly.processedReferences ?? []) == Set(target.references), "Unused supplied source is processed without becoming an unrelated dependency")
        check(ContextKnowledgeRules.current(citedOnly.references,records:[project]), "Withdrawal of an unused input does not hide supported human context")
        let short = ContextKnowledgeRecord(reference:.init(kind:"memory",key:"short-preference",revision:"v1"),title:"Preference",text:"Vegan",date:date)
        var shortTarget = target;shortTarget.records=[short]
        let shortOutput=output(quotes:[["id":short.reference.contextKey,"quote":"Vegan"]],markdown:"The human stated a vegan preference.")
        check(try ContextConsolidationRules.decode(shortOutput,targets:[shortTarget])[0].0.references == [short.reference], "A complete short human statement can be quoted exactly")
        rejects("A partial short statement was accepted as evidence") { _=try ContextConsolidationRules.decode(output(quotes:[["id":short.reference.contextKey,"quote":"Veg"]]),targets:[shortTarget]) }
        rejects("A fabricated extension of a short statement was accepted") { _=try ContextConsolidationRules.decode(output(quotes:[["id":short.reference.contextKey,"quote":"Vegan for life"]]),targets:[shortTarget]) }
        var duplicate=target;duplicate.records=[project,project]
        rejects("Duplicate issued reference was silently acknowledged") { _=try ContextConsolidationRules.decode(output(quotes:[["id":project.reference.contextKey,"quote":"Bridge optics project contains a camera experiment"]]),targets:[duplicate]) }

        let purposeWords="The Bridge optics project compares two calibration methods; preserve this ongoing human purpose."
        let purpose=ContextKnowledgeRecord(reference:.init(kind:"page",key:"exact-human-purpose",revision:"purpose-v1"),title:"Human project purpose",text:purposeWords,date:date.addingTimeInterval(5000),projectID:projectID)
        var subject=project;subject.date=date.addingTimeInterval(6000)
        let updates=(0..<65).map { index in
            ContextKnowledgeRecord(reference:.init(kind:"human",key:"change-\(index)",revision:"v1"),title:"Fictional update",text:"Bridge optics update \(index) records a bounded calibration observation.",date:date.addingTimeInterval(Double(index)))
        }
        let originals=[subject,purpose]+updates,anchorKeys=[subject.reference.contextKey,purpose.reference.contextKey]
        func selection(_ current:[ContextKnowledgeRecord],_ previous:ContextPage?)->ContextPageTarget {
            ContextConsolidationSelection.target(registration:"owner",kind:.project,key:projectID.uuidString,title:"Bridge optics",candidates:current,previous:previous,anchorKeys:anchorKeys,projectID:projectID)!
        }
        func projection(_ value:ContextPageTarget)->ContextPage {
            let delta=value.records.last { value.pendingReferences.contains($0.reference) } ?? purpose
            let evidence=[subject,purpose,delta].filter { record in value.references.contains(record.reference) }
            let unique=Array(Dictionary(evidence.map {($0.reference.contextKey,$0)},uniquingKeysWith:{first,_ in first}).values).sorted{$0.reference.contextKey < $1.reference.contextKey}
            let row:[String:Any]=["id":value.id,"synopsis":"Current calibration purpose and changes","markdown":purposeWords+"\n"+delta.text,
                "evidence":unique.map{["id":$0.reference.contextKey,"quote":$0.text]},"purposeQuestion":NSNull()]
            return try! ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":[row]]),targets:[value])[0].0
        }
        var previous:ContextPage?,cycles=0,sawPrior=false,progress=true,anchorsPresent=true,bounded=true
        while cycles < 8 {
            let window=selection(originals,previous)
            if !window.hasPendingChanges {break}
            let reversed=selection(Array(originals.reversed()),previous)
            progress = progress && !window.pendingReferences.isEmpty && window.pendingReferences.count <= 20
            anchorsPresent = anchorsPresent && anchorKeys.allSatisfy { key in window.records.contains{$0.reference.contextKey == key} }
            bounded = bounded && window.records.count <= 52 && ContextKnowledgeRules.json(window.input).utf8.count <= 20_000
            check(window.references == reversed.references, "Window \(cycles) is deterministic under reordered canonical records")
            if let old=previous {
                sawPrior = true
                check(window.input["previousDraft"] != nil && window.previousPage?.markdown == old.markdown && old.references.allSatisfy(window.references.contains), "Window \(cycles) supplies the current prior purpose with every original support")
            }
            previous=projection(window);cycles += 1
        }
        let complete=selection(originals,previous)
        check(cycles >= 4 && progress && anchorsPresent && bounded && sawPrior, "More than forty pending changes preserve exact purpose anchors and continuously advance bounded windows")
        check(!complete.hasPendingChanges && complete.remainingPendingCount == 0 && Set(previous!.processedReferences ?? []) == Set(originals.map(\.reference)), "Every exact initial input is processed independently for the project")
        check(previous!.markdown.contains(purposeWords) && previous!.references.contains(purpose.reference), "Supported ongoing human purpose survives the full multi-window flow")
        let independent=ContextConsolidationSelection.target(registration:"owner",kind:.topic,key:"studies",title:"Studies",candidates:originals,previous:nil)!
        check(independent.hasPendingChanges && independent.processedReferences.isEmpty && independent.remainingPendingCount + independent.pendingReferences.count == originals.count, "Successful project windows cannot consume a topic's independent backlog")
        var revisedPurpose=purpose;revisedPurpose.reference = .init(kind:"page",key:purpose.reference.key,revision:"purpose-v2");revisedPurpose.text="The human corrected the project purpose: compare sensor alignment instead."
        let corrected=selection([subject,revisedPurpose]+updates,previous)
        check(corrected.previousPage == nil && corrected.input["previousDraft"] == nil && !ContextKnowledgeRules.json(corrected.input).contains(purposeWords), "A changed purpose prevents obsolete prior prose from entering the next request")
        check(corrected.pendingReferences.contains(revisedPurpose.reference) && !corrected.processedReferences.contains(purpose.reference), "The exact human correction is pending while its superseded version is removed from progress")
        let oldDelta=previous!.references.first{$0.kind == "human"}!
        let withdrawn=selection(originals.filter{$0.reference != oldDelta},previous)
        check(withdrawn.previousPage == nil && !withdrawn.references.contains(oldDelta) && !withdrawn.processedReferences.contains(oldDelta), "A withdrawn original is never carried forward from summary or progress metadata")
        check(withdrawn.references.contains(purpose.reference), "Withdrawal of a source keeps the independently current human purpose anchor")
        var uncited=updates[0];uncited.reference = .init(kind:"human",key:uncited.reference.key,revision:"v2");uncited.text="Bridge optics update zero has a new exact current version."
        let uncitedChanged=selection([subject,purpose,uncited]+Array(updates.dropFirst()),previous)
        check(uncitedChanged.previousPage != nil && uncitedChanged.pendingReferences.contains(uncited.reference), "An uncited earlier change becomes pending without invalidating useful supported prior prose")
        var wrongAccount=previous!;wrongAccount=ContextPage(registration:"other-owner",kind:.project,key:projectID.uuidString,owner:.generated,title:wrongAccount.title,markdown:wrongAccount.markdown,references:wrongAccount.references)
        check(selection(originals,wrongAccount).previousPage == nil && selection(originals,wrongAccount).processedReferences.isEmpty, "Another account's page cannot seed continuity or processing receipts")
        let coalesced=selection(originals+[subject,purpose],previous)
        check(Set(coalesced.references).count == coalesced.references.count, "Identical current reference duplicates coalesce before issuing model input")
        var conflicting=subject;conflicting.text="An inconsistent current row cannot silently win by position."
        let ambiguous=selection(originals+[conflicting],previous)
        check(!ambiguous.references.contains(subject.reference) && ambiguous.previousPage == nil, "Conflicting current identity rows fail closed rather than retargeting a page")

        let huge = String(repeating:"quoted \"\\🌱 ",count:800)
        let bulky=(0..<12).map { index in ContextKnowledgeRecord(reference:.init(kind:"memory",key:"bulky-\(index)",revision:"v1"),title:"Large bounded original",text:huge,date:date.addingTimeInterval(Double(index))) }
        var prior=previous!;prior.markdown=String(repeating:"🧑🏽‍🔬",count:900);prior.references=[subject.reference,purpose.reference]+Array(bulky.prefix(4).map(\.reference));prior.evidenceQuotes=nil
        let boundedPrior=selection([subject,purpose]+bulky,prior)
        check(boundedPrior.previousPage == nil && boundedPrior.input["previousDraft"] == nil, "An oversized prior is omitted instead of supplying its unsupported partial body")
        check(!boundedPrior.pendingReferences.isEmpty && anchorKeys.allSatisfy { key in boundedPrior.references.contains{$0.contextKey == key} } && ContextKnowledgeRules.json(boundedPrior.input).utf8.count <= 20_000, "Oversized prior fallback retains purpose, bounded originals and pending progress")
        check((boundedPrior.input["records"] as? [[String:Any]])?.contains{$0["excerpted"] as? String == "true"} == true, "Clipped original text is explicitly identified as incomplete model context")
        let overviewTarget=ContextPageTarget(registration:"owner",kind:.overview,key:"maintained",title:"Overview",records:[short])
        let otherTargets=(0..<9).map { index in ContextPageTarget(registration:"owner",kind:.project,key:"initial-\(index)",title:"Project \(index)",records:[project]) }
        var waitingTargets=otherTargets+[overviewTarget],served=Set<String>(),rounds=0
        while !waitingTargets.isEmpty && rounds < 4 {
            let ordered=ContextConsolidationSelection.ordered(waitingTargets,pages:[])
            if rounds == 0 {check(ordered.first?.id == overviewTarget.id, "Initial everyday overview is ordered before missing project pages")}
            let batch=ContextConsolidationSelection.batch(ordered,now:date,timezone:"UTC")
            check(!batch.isEmpty && batch.count <= 4 && ContextConsolidationSelection.input(batch,now:date,timezone:"UTC").utf8.count <= 30_000, "Initial population batch \(rounds) obeys exact complete-envelope bounds")
            served.formUnion(batch.map(\.id));waitingTargets.removeAll{served.contains($0.id)};rounds += 1
        }
        check(waitingTargets.isEmpty && served.count == 10 && rounds == 3, "Bounded initial batches eventually serve every finite missing project and overview")
        let budgetBatch=ContextConsolidationSelection.batch([boundedPrior]+otherTargets,now:date,timezone:String(repeating:"X",count:200))
        check(ContextConsolidationSelection.input(budgetBatch,now:date,timezone:String(repeating:"X",count:200)).utf8.count <= 30_000, "Batch measurement includes the actual clock and timezone metadata")

        let initial=selection(originals,nil)
        check(Set(initial.allPendingReferences) == Set(originals.map(\.reference)) && initial.pendingReferences.count == 20, "Initial snapshot exposes all outstanding exact refs independently of its first twenty-input window")
        let frozen=Dictionary(initial.allPendingReferences.map{($0.contextKey,$0.revision)},uniquingKeysWith:{first,_ in first})
        let arrivals=(0..<100).map { index in ContextKnowledgeRecord(reference:.init(kind:"human",key:"fresh-\(index)",revision:"new-v1"),title:"New arrival",text:"Fresh Bridge optics note \(index) must not extend the captured bootstrap.",date:date.addingTimeInterval(-1000+Double(index))) }
        var bootstrap:ContextPage?,bootstrapCalls=0
        while bootstrapCalls < 8 {
            let window=ContextConsolidationSelection.target(registration:"owner",kind:.project,key:projectID.uuidString,title:"Bridge optics",candidates:originals+arrivals,previous:bootstrap,anchorKeys:anchorKeys,projectID:projectID,eligibleReferences:frozen)!
            if !window.hasPendingChanges {break}
            check(!window.pendingReferences.isEmpty && window.records.allSatisfy{$0.reference.key.hasPrefix("fresh-") == false}, "Frozen bootstrap window \(bootstrapCalls) advances only initial pending originals plus current support")
            bootstrap=projection(window);bootstrapCalls += 1
        }
        let frozenDone=ContextConsolidationSelection.target(registration:"owner",kind:.project,key:projectID.uuidString,title:"Bridge optics",candidates:originals+arrivals,previous:bootstrap,anchorKeys:anchorKeys,projectID:projectID,eligibleReferences:frozen)!
        let ordinaryNext=selection(originals+arrivals,bootstrap)
        check(bootstrapCalls == 4 && !frozenDone.hasPendingChanges && frozenDone.pendingReferences.isEmpty && frozenDone.remainingPendingCount == 0, "Initial population terminates after its finite original snapshot despite one hundred fresh arrivals")
        check(frozenDone.allPendingReferences.count == 100 && ordinaryNext.hasPendingChanges && ordinaryNext.allPendingReferences.count == 100, "Fresh arrivals remain independently pending for the following ordinary heartbeat")
        let changedAfterSnapshot=ContextConsolidationSelection.target(registration:"owner",kind:.project,key:projectID.uuidString,title:"Bridge optics",candidates:[subject,purpose,uncited]+Array(updates.dropFirst()),previous:bootstrap,anchorKeys:anchorKeys,projectID:projectID,eligibleReferences:frozen)!
        check(changedAfterSnapshot.allPendingReferences.contains(uncited.reference) && !changedAfterSnapshot.pendingReferences.contains(uncited.reference) && !changedAfterSnapshot.references.contains(uncited.reference), "A new version of an initial nonanchor remains pending rather than being substituted for its frozen revision")
        let population = ContextPopulationSnapshot(initial:[initial],pages:[])
        let initialWork = population.remaining(current:[initial],records:originals,pages:[])
        check(population.references == frozen && initialWork.targetIDs == [initial.id] && initialWork.workCount == originals.count + 1, "Population freezes all exact initial inputs and one required initial page write")
        let firstPopulationPage = projection(initial)
        let firstPopulationTarget = ContextConsolidationSelection.target(registration:"owner",kind:.project,key:projectID.uuidString,title:"Bridge optics",candidates:originals,previous:firstPopulationPage,anchorKeys:anchorKeys,projectID:projectID,eligibleReferences:population.references)!
        let afterFirstWrite = population.remaining(current:[firstPopulationTarget],records:originals,pages:[firstPopulationPage])
        check(afterFirstWrite.workCount == originals.count - Set(firstPopulationPage.processedReferences ?? []).count && afterFirstWrite.workCount < initialWork.workCount, "A successful bounded write decreases exact per-page initial work rather than merely changing a store revision")
        let finishedWork = population.remaining(current:[frozenDone],records:originals+arrivals,pages:[bootstrap!])
        check(finishedWork.workCount == 0 && finishedWork.targetIDs.isEmpty, "Fresh nonfrozen arrivals cannot extend a completed initial page")
        var stayedFinished = true
        for index in 0..<8 {
            var changedSubject = subject, changedPurpose = purpose
            changedSubject.reference = .init(kind:subject.reference.kind,key:subject.reference.key,revision:"project-later-\(index)")
            changedSubject.text = "The human edited the current project between population calls: \(index)."
            changedPurpose.reference = .init(kind:purpose.reference.kind,key:purpose.reference.key,revision:"purpose-later-\(index)")
            changedPurpose.text = "The human edited their project purpose after the initial page finished: \(index)."
            let changedRecords = [changedSubject,changedPurpose]+updates+arrivals
            let changedTarget = ContextConsolidationSelection.target(registration:"owner",kind:.project,key:projectID.uuidString,title:"Bridge optics",candidates:changedRecords,previous:bootstrap,anchorKeys:anchorKeys,projectID:projectID,eligibleReferences:population.references)!
            let outstanding = population.remaining(current:[changedTarget],records:changedRecords,pages:[bootstrap!])
            stayedFinished = stayedFinished && changedTarget.previousPage == nil && outstanding.targetIDs.isEmpty && outstanding.workCount == 0
        }
        check(stayedFinished, "Continuous current project and human-purpose edits cannot reopen a completed frozen target even while its live page support is stale")

        let sharedPopulation = ContextPopulationSnapshot(initial:[initial,independent],pages:[])
        let sharedInitialWork = sharedPopulation.remaining(current:[initial,independent],records:originals,pages:[])
        check(sharedInitialWork.workCount == 2 * (originals.count + 1), "A shared canonical reference counts independently for every initial target that has not processed it")
        let sharedRemaining = sharedPopulation.remaining(current:[frozenDone,independent],records:originals,pages:[bootstrap!])
        check(sharedRemaining.targetIDs == [independent.id] && sharedRemaining.workCount == originals.count + 1, "Finishing a project cannot acknowledge the topic's shared pending records or its initial write")
        let newTarget = ContextPageTarget(registration:"owner",kind:.topic,key:"new-after-snapshot",title:"New target",records:[unrelated],allPendingReferences:[unrelated.reference])
        let withNewTarget = population.remaining(current:[frozenDone,newTarget],records:originals+[unrelated],pages:[bootstrap!])
        check(withNewTarget.workCount == 0 && withNewTarget.targetIDs.isEmpty && population.references[unrelated.reference.contextKey] == nil, "Targets and source identities first discovered after the snapshot wait for a later heartbeat")

        let sourceTarget = ContextPageTarget(registration:"owner",kind:.topic,key:"source-population",title:"Source changes",records:[project,mail],allPendingReferences:[project.reference,mail.reference])
        let sourcePage = ContextPage(registration:"owner",kind:.topic,key:sourceTarget.key,owner:.generated,title:sourceTarget.title,markdown:"An earlier supported source page.",references:[project.reference])
        let sourcePopulation = ContextPopulationSnapshot(initial:[sourceTarget],pages:[sourcePage])
        let originalSourceWork = sourcePopulation.remaining(current:[sourceTarget],records:[project,mail],pages:[sourcePage])
        let withdrawnSourceWork = sourcePopulation.remaining(current:[sourceTarget],records:[project],pages:[sourcePage])
        let versionedSourceWork = sourcePopulation.remaining(current:[sourceTarget],records:[project,changedMail],pages:[sourcePage])
        check(originalSourceWork.workCount == 2 && withdrawnSourceWork.workCount == 1 && versionedSourceWork.workCount == 1, "Withdrawal or replacement of an exact frozen source removes obsolete work without adopting its new version")
        check(sourcePopulation.remaining(current:[],records:[project,mail],pages:[sourcePage]).workCount == 0, "A target no longer eligible under current permissions cannot keep population running")
        let wrongAccountWork = population.remaining(current:[initial],records:originals,pages:[wrongAccount])
        check(wrongAccountWork.workCount == initialWork.workCount, "Another account's page cannot acknowledge a required initial write or pending inputs")
        let wrongAccountTarget = ContextPageTarget(registration:"other-owner",kind:initial.kind,key:initial.key,title:initial.title,records:originals,allPendingReferences:initial.allPendingReferences)
        check(population.remaining(current:[wrongAccountTarget],records:originals,pages:[wrongAccount]).workCount == 0, "A foreign-account target cannot join the captured population")

        let rebuildRecords = originals.filter { $0.reference != oldDelta }
        let rebuildPopulation = ContextPopulationSnapshot(initial:[withdrawn],pages:[previous!])
        let needsRebuild = rebuildPopulation.remaining(current:[withdrawn],records:rebuildRecords,pages:[previous!])
        var rebuiltPage = previous!; rebuiltPage.revision = UUID()
        let rebuiltWork = rebuildPopulation.remaining(current:[withdrawn],records:rebuildRecords,pages:[rebuiltPage])
        check(rebuildPopulation.references.isEmpty && needsRebuild.targetIDs == [complete.id] && needsRebuild.workCount == 1, "An initially stale page with no pending inputs still receives one captured rebuild")
        check(rebuiltWork.workCount == 0 && rebuiltWork.targetIDs.isEmpty, "That initial rebuild completes on its exact page revision advance and cannot repeat on global-store changes")
        check(rebuildPopulation.remaining(current:[withdrawn],records:rebuildRecords,pages:[previous!,wrongAccount]).workCount == 1, "An unrelated saved page cannot satisfy an initial target's required revision advance")

        let humanOwned=ContextPage(registration:"owner",kind:.project,key:projectID.uuidString,owner:.human,title:"Bridge optics",markdown:purposeWords)
        check(ContextConsolidationSelection.target(registration:"owner",kind:.project,key:projectID.uuidString,title:"Bridge optics",candidates:originals,previous:humanOwned) == nil, "The pure selection boundary cannot replace a human-owned page")

        let savedOverview=ContextPage(registration:"owner",kind:.overview,key:"maintained",owner:.generated,title:"Overview",markdown:"A saved current overview.",references:[short.reference],created:date,updated:date)
        let afterOverview=ContextConsolidationSelection.ordered([overviewTarget]+otherTargets,pages:[savedOverview])
        check(afterOverview.first?.kind == .project, "After initial overview creation, missing projects cannot be starved by another overview window")
        let olderProject=ContextPage(registration:"owner",kind:.project,key:otherTargets[0].key,owner:.generated,title:otherTargets[0].title,markdown:"An earlier project page.",references:[project.reference],created:date.addingTimeInterval(-500),updated:date.addingTimeInterval(-500))
        check(ContextConsolidationSelection.ordered([overviewTarget,otherTargets[0]],pages:[savedOverview,olderProject]).first?.id == olderProject.id, "An older existing project update precedes a freshly updated overview")
        var impossible=short;impossible.text="a"+String(repeating:"\u{0301}",count:5000)
        check(ContextConsolidationSelection.target(registration:"owner",kind:.topic,key:"bounded-unicode",title:"Bounded",candidates:[impossible],previous:nil) == nil, "An original with no complete grapheme inside its byte bound does not trigger an impossible evidence request")

        let retained32=[subject,purpose]+Array(updates.prefix(30))
        var capacityPrior=ContextPage(registration:"owner",kind:.project,key:projectID.uuidString,owner:.generated,title:"Bridge optics",markdown:purposeWords,references:retained32.map(\.reference))
        capacityPrior.processedReferences=retained32.map(\.reference)
        capacityPrior.evidenceQuotes=retained32.map{.init(referenceID:$0.reference.id,quote:$0.text)}
        let capacity=selection([subject,purpose]+Array(updates.prefix(50)),capacityPrior)
        check(capacity.records.count <= 52 && (1...20).contains(capacity.pendingReferences.count) && capacity.previousPage != nil && ContextKnowledgeRules.json(capacity.input).utf8.count <= 20_000, "Retained32 plus bounded new originals include segment metadata without losing a supported prior or pending progress")
        let capacityRow:[String:Any]=["id":capacity.id,"synopsis":"Supported retained purpose","markdown":purposeWords,"evidence":retained32.map{["id":$0.reference.contextKey,"quote":$0.text]},"purposeQuestion":NSNull()]
        let capacityPage=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":[capacityRow]]),targets:[capacity])[0].0
        check(capacityPage.references.count == 32 && capacityPage.evidenceQuotes?.count == 32 && Set(capacityPage.processedReferences ?? []) == Set(capacity.processedReferences + capacity.references), "Thirty-two cited support refs stay distinct from every exact processed original version")
        let passageSources: [(String,String)] = [
            ("short", "Vegan"),
            ("tail", String(repeating:"x",count:1000)+"Z"),
            ("multiline", String(repeating:"Optics line \"quoted\" C:\\Capture\nSecond line.\n",count:30)),
            ("unicode", String(repeating:"é e\u{0301} 🧑🏽‍🔬 \"\\\n",count:60)),
            ("long", String(repeating:"Original calibration passage. ",count:50))
        ]
        var passageRecords: [ContextKnowledgeRecord] = []
        for (name, words) in passageSources {
            let record = ContextKnowledgeRecord(reference:.init(kind:"memory",key:"passage-"+name,revision:"v1"),title:"Original "+name,text:words,date:date)
            passageRecords.append(record)
            let segments = ContextPageTarget.segments(record)
            check(!segments.isEmpty && segments.allSatisfy{(1...500).contains($0.text.count)} && segments.map(\.index) == Array(segments.indices), "\(name) source has complete bounded numbered character slices")
            check(Data(segments.map(\.text).joined().utf8) == Data(words.utf8), "\(name) source segments reconstruct every original Unicode, newline, quote and slash byte")
            check(Set(segments.map(\.id)).count == segments.count && segments.map(\.id) == ContextPageTarget.segments(record).map(\.id), "\(name) segment IDs are unique and deterministic")
            let issued = ContextPageTarget(registration:"owner",kind:.topic,key:"passage-"+name,title:record.title,records:[record]).input["records"] as! [[String:Any]]
            let rows = issued[0]["segments"] as! [[String:Any]]
            check(issued[0]["id"] as? String == "record_0" && issued[0]["referenceID"] as? String == record.reference.contextKey && issued[0]["revision"] as? String == record.reference.revision && issued[0]["title"] as? String == record.title && issued[0]["observed"] as? String == date.ISO8601Format() && rows.compactMap{$0["text"] as? String}.joined() == words && issued[0]["text"] == nil && issued[0]["originalCharacters"] as? Int == words.count && issued[0]["issuedCharacters"] as? Int == words.count, "\(name) issued record retains exact metadata and all source text once inside its segments")
        }
        var oversizedPassage = passageRecords[0]
        oversizedPassage.text = String(repeating:"🧑🏽‍🔬 calibration line \"original\"\n",count:300)
        oversizedPassage.relevance = "An exact human-linked project passage."
        let oversizedSlices = ContextPageTarget.segments(oversizedPassage)
        let issuedOversized = ContextPageTarget.suppliedText(oversizedPassage)
        let oversizedTarget = ContextPageTarget(registration:"owner",kind:.topic,key:"oversized-projection",title:"Bounded original",records:[oversizedPassage])
        let oversizedRow = (oversizedTarget.input["records"] as! [[String:Any]])[0]
        check(Data(oversizedSlices.map(\.text).joined().utf8) == Data(issuedOversized.utf8) && issuedOversized.count <= 1600 && issuedOversized.utf8.count <= 4000, "Segments retain every byte of the entire bounded issued projection without an additional truncation")
        check(oversizedRow["excerpted"] as? String == "true" && oversizedRow["originalCharacters"] as? Int == oversizedPassage.text.count && oversizedRow["issuedCharacters"] as? Int == issuedOversized.count && oversizedRow["relevance"] as? String == oversizedPassage.relevance, "Excerpt metadata states exact original and issued coverage while preserving relevance")
        check(oversizedPassage.text.count > issuedOversized.count && oversizedPassage.reference == passageRecords[0].reference && oversizedSlices.allSatisfy{ContextPageTarget.containsExact($0.text,in:oversizedPassage.text)}, "Bounded passage issuance leaves the full authoritative original and its reference untouched")
        let passage = passageRecords.first{$0.reference.key == "passage-multiline"}!
        let selectedSegment = ContextPageTarget.segments(passage)[1]
        var passageTarget = target; passageTarget.records = [passage,mail]
        let segmentOutput = output(quotes:[["id":passage.reference.contextKey,"segment":selectedSegment.id]],markdown:"The human's original optics record contains multiline calibration notes.")
        let passagePage = try ContextConsolidationRules.decode(segmentOutput,targets:[passageTarget])[0].0
        check(passagePage.evidenceQuotes == [.init(referenceID:passage.reference.id,quote:selectedSegment.text)] && passagePage.references == [passage.reference], "A known record/segment pair resolves locally to the exact untouched canonical passage")
        check(Set(passagePage.processedReferences ?? []) == Set([passage.reference,mail.reference]), "Uncited supplied input is processed without becoming support when evidence uses segments")
        let tinyTail = passageRecords.first{$0.reference.key == "passage-tail"}!
        var tailTarget = target; tailTarget.records = [tinyTail]
        let tailSegment = ContextPageTarget.segments(tinyTail).last!
        let tailPage = try ContextConsolidationRules.decode(output(quotes:[["id":tinyTail.reference.contextKey,"segment":tailSegment.id]]),targets:[tailTarget])[0].0
        check(tailSegment.text == "Z" && tailPage.evidenceQuotes?.first?.quote == "Z", "A final issued segment shorter than eight characters remains exact source evidence")
        var revisedPassage = passage; revisedPassage.reference = .init(kind:passage.reference.kind,key:passage.reference.key,revision:"v2")
        var revisedPassageTarget = passageTarget; revisedPassageTarget.records = [revisedPassage,mail]
        check(Set(ContextPageTarget.segments(revisedPassage).map(\.id)).isDisjoint(with:Set(ContextPageTarget.segments(passage).map(\.id))), "Every source revision receives different opaque segment identities")
        rejects("A segment from an old source revision was accepted") { _=try ContextConsolidationRules.decode(segmentOutput,targets:[revisedPassageTarget]) }
        rejects("A fabricated segment ID was accepted") { _=try ContextConsolidationRules.decode(output(quotes:[["id":passage.reference.contextKey,"segment":"segment:invented"]]),targets:[passageTarget]) }
        rejects("Another record's segment was accepted for a known original ID") { _=try ContextConsolidationRules.decode(output(quotes:[["id":mail.reference.contextKey,"segment":selectedSegment.id]]),targets:[passageTarget]) }
        var identicalPassage = passage
        identicalPassage.reference = .init(kind:passage.reference.kind,key:"different-original-same-words",revision:passage.reference.revision)
        var identicalTarget = passageTarget; identicalTarget.records = [passage,identicalPassage]
        check(Set(ContextPageTarget.segments(identicalPassage).map(\.id)).isDisjoint(with:Set(ContextPageTarget.segments(passage).map(\.id))), "Identical source text under another original identity has different segment IDs")
        rejects("Identical text silently substituted another original's segment identity") { _=try ContextConsolidationRules.decode(output(quotes:[["id":identicalPassage.reference.contextKey,"segment":selectedSegment.id]]),targets:[identicalTarget]) }
        rejects("An unissued source ID borrowed a valid segment") { _=try ContextConsolidationRules.decode(output(quotes:[["id":"memory:not-issued","segment":selectedSegment.id]]),targets:[passageTarget]) }
        rejects("A valid legacy quote silently repaired a forged segment") { _=try ContextConsolidationRules.decode(output(quotes:[["id":passage.reference.contextKey,"segment":"segment:invented","quote":String(passage.text.prefix(100))]]),targets:[passageTarget]) }
        rejects("Ambiguous combined quote and segment fields were accepted") { _=try ContextConsolidationRules.decode(output(quotes:[["id":passage.reference.contextKey,"segment":selectedSegment.id,"quote":selectedSegment.text]]),targets:[passageTarget]) }
        rejects("Evidence with no passage or legacy quote was accepted") { _=try ContextConsolidationRules.decode(output(quotes:[["id":passage.reference.contextKey]]),targets:[passageTarget]) }
        let decomposed = ContextKnowledgeRecord(reference:.init(kind:"memory",key:"literal-unicode",revision:"v1"),title:"Literal original",text:"The original says cafe\u{0301} today.",date:date)
        var literalTarget=target;literalTarget.records=[decomposed]
        rejects("A normalized but byte-different legacy quote was accepted as exact") { _=try ContextConsolidationRules.decode(output(quotes:[["id":decomposed.reference.contextKey,"quote":"says café today"]]),targets:[literalTarget]) }
        rejects("A paraphrased legacy quote was repaired") { _=try ContextConsolidationRules.decode(output(quotes:[["id":passage.reference.contextKey,"quote":"The calibration notes describe the optics capture."]]),targets:[passageTarget]) }
        let exactLegacy = String(passage.text.prefix(100))
        check(try ContextConsolidationRules.decode(output(quotes:[["id":passage.reference.contextKey,"quote":exactLegacy]]),targets:[passageTarget])[0].0.evidenceQuotes?.first?.quote == exactLegacy, "Exact legacy quotation transport remains compatible without approximation")
        let segmentRows: [[String:Any]] = fullTargets.map { value in
            ["id":value.id,"synopsis":"Twenty supported calibration records","markdown":"The calibration project retains its supplied reference samples.","purposeQuestion":NSNull(),
             "evidence":fullRecords.map { ["id":$0.reference.contextKey,"segment":ContextPageTarget.segments($0)[0].id] }]
        }
        let segmentBatch = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":segmentRows]),targets:fullTargets)
        check(segmentBatch.count == 4 && segmentBatch.allSatisfy{$0.0.references.count == 20 && $0.0.evidenceQuotes?.count == 20}, "A four-target twenty-record response resolves issued segments independently for every page")
        var tooManySegments = segmentRows
        tooManySegments[0]["evidence"] = Array(repeating:["id":fullRecords[0].reference.contextKey,"segment":ContextPageTarget.segments(fullRecords[0])[0].id],count:33)
        rejects("An over-capacity segment selection array passed the thirty-two-evidence bound") { _=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":tooManySegments]),targets:fullTargets) }

        func rejectsCategory(_ category:String,_ name:String,_ action:() throws -> Void) {
            do {try action();preconditionFailure(name)}
            catch let failure as ContextPageFailure {check(failure == .invalid(category),name+": received \(failure)")}
            catch {preconditionFailure(name+": unexpected error \(error)")}
        }
        var aliasOriginals=fullRecords
        aliasOriginals[0].text="The optics record says \"near-field\".\nKeep e\u{0301}, 🧑🏽‍🔬 and C:\\Capture byte-exact."
        let aliasTargets=fullTargets.enumerated().map {index,target -> ContextPageTarget in
            var value=target;value.records=index.isMultiple(of:2) ? aliasOriginals : Array(aliasOriginals.reversed());return value
        }
        let aliasRows:[[String:Any]]=aliasTargets.map {value in
            ["id":value.id,"synopsis":"Exact calibration context","markdown":"The project retains its supplied calibration context and qualifications.","purposeQuestion":NSNull(),
             "evidence":value.issuedRecords.map{["id":$0.id,"segment":$0.segments[0].id]}]
        }
        let aliasPages=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":aliasRows]),targets:aliasTargets).map{$0.0}
        check(aliasPages.count == 4 && zip(aliasPages,aliasTargets).allSatisfy{page,value in Set(page.references) == Set(value.references) && Set(page.processedReferences ?? []) == Set(value.references) && page.evidenceQuotes?.count == 20}, "Four twenty-record targets resolve short aliases to exact canonical support and processing coverage")
        check(zip(aliasPages,aliasTargets).allSatisfy{page,value in zip(page.evidenceQuotes ?? [],value.records).allSatisfy{quote,record in quote.referenceID == record.reference.id && Data(quote.quote.utf8) == Data(ContextPageTarget.suppliedText(record).utf8)}}, "Target-local alias resolution preserves original Unicode, multiline and slash text byte-exactly")
        check(aliasTargets[0].issuedRecords[0].id == aliasTargets[1].issuedRecords[0].id && aliasPages[0].evidenceQuotes?.first?.referenceID != aliasPages[1].evidenceQuotes?.first?.referenceID, "The same short alias in two targets resolves only inside each captured target")
        check(aliasTargets.allSatisfy{value in value.issuedRecords.enumerated().allSatisfy{index,issued in issued.id == "record_\(index)" && issued.record.reference == value.records[index].reference && issued.segments.allSatisfy{$0.id == "passage_\(index)_\($0.index)"}}}, "Every issued record and passage uses its exact small indexed alias")
        let aliasBatch=ContextConsolidationSelection.batch(aliasTargets,now:date,timezone:"UTC")
        check(!aliasBatch.isEmpty && aliasBatch.count <= 4 && aliasBatch.allSatisfy{ContextKnowledgeRules.json($0.input).utf8.count <= 20_000} && ContextConsolidationSelection.input(aliasBatch,now:date,timezone:"UTC").utf8.count <= 30_000, "Target and complete batch bounds include short aliases, canonical metadata and source passages")
        let aliasTarget=aliasTargets[0]
        func aliasOutput(_ evidence:[[String:String]])->String {
            ContextKnowledgeRules.json(["pages":[["id":aliasTarget.id,"synopsis":"Exact calibration context","markdown":"A supplied calibration passage remains current.","evidence":evidence,"purposeQuestion":NSNull()]]])
        }
        let aliasFirst=aliasTarget.issuedRecords[0], aliasSecond=aliasTarget.issuedRecords[1]
        let aliasOnly=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.id,"segment":aliasFirst.segments[0].id]]),targets:[aliasTarget])[0].0
        check(aliasOnly.references == [aliasFirst.record.reference] && Set(aliasOnly.processedReferences ?? []) == Set(aliasTarget.references) && aliasOnly.evidenceQuotes?.first?.referenceID == aliasFirst.record.reference.id, "An uncited issued alias is processed without being promoted to prose support or persisted as an identity")
        rejectsCategory("consolidation evidence record","An unknown short record alias was repaired") {_=try ContextConsolidationRules.decode(aliasOutput([["id":"record_999","segment":"passage_999_0"]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence record","An unissued canonical record was repaired") {_=try ContextConsolidationRules.decode(aliasOutput([["id":"memory:missing","quote":"A fabricated original source quote"]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence passage","An invented passage alias was repaired") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.id,"segment":"passage_0_999"]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence passage","A different record's issued passage alias was accepted") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.id,"segment":aliasSecond.segments[0].id]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence passage","A canonical ID and a short alias passage were silently combined") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.record.reference.contextKey,"segment":aliasFirst.segments[0].id]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence passage","A short ID and a legacy hashed passage were silently combined") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.id,"segment":ContextPageTarget.segments(aliasFirst.record)[0].id]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence selector","A quote under a short alias bypassed exact passage selection") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.id,"quote":aliasFirst.segments[0].text]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence selector","Ambiguous selectors were silently repaired") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.id,"segment":aliasFirst.segments[0].id,"quote":aliasFirst.segments[0].text]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence selector","An absent selector was silently repaired") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.id]]),targets:[aliasTarget])}
        rejectsCategory("consolidation evidence quote","A legacy paraphrase did not retain its safe fixed category") {_=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.record.reference.contextKey,"quote":"The entire optics calibration was completed successfully."]]),targets:[aliasTarget])}
        let compatibleCanonical=try ContextConsolidationRules.decode(aliasOutput([["id":aliasFirst.record.reference.contextKey,"segment":ContextPageTarget.segments(aliasFirst.record)[0].id]]),targets:[aliasTarget])[0].0
        check(compatibleCanonical.references == aliasOnly.references && compatibleCanonical.evidenceQuotes == aliasOnly.evidenceQuotes, "Legacy canonical ID plus hashed passage retains exact compatibility without alias fallback")
        let priorSupport=(capacity.input["previousDraft"] as! [String:Any])["supportIDs"] as! [String]
        check(Set(priorSupport) == Set(capacity.issuedRecords.filter{retained32.map(\.reference).contains($0.record.reference)}.map(\.id)) && priorSupport.allSatisfy{$0.hasPrefix("record_")}, "Earlier draft support points to current short aliases while durable references remain canonical")

        let pageInputs=ContextConsolidationRules.targetInputs(aliasTargets)
        check(pageInputs.enumerated().allSatisfy{index,row in row["id"] as? String == "page_\(index)" && row["referenceID"] as? String == aliasTargets[index].id}, "Every captured target exposes only its short page selector plus canonical diagnostic metadata")
        let pageAliasRows=aliasRows.enumerated().map {index,row -> [String:Any] in var value=row;value["id"]="page_\(index)";return value}
        let pageAliasResult=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":pageAliasRows]),targets:aliasTargets).map{$0.0}
        check(zip(pageAliasResult,aliasTargets).allSatisfy{page,target in page.id == target.id && page.registration == target.registration && Set(page.references) == Set(target.references) && Set(page.processedReferences ?? []) == Set(target.references)}, "All four short page selectors preserve exact canonical page and source identities with reversed source orders")
        let reorderedPages=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":Array(pageAliasRows.reversed())]),targets:aliasTargets).map{$0.0}
        check(reorderedPages.map(\.id) == aliasTargets.reversed().map(\.id) && reorderedPages.first?.evidenceQuotes?.first?.referenceID == aliasTargets.last?.records.first?.reference.id, "Output order cannot retarget a captured page alias or its target-local source aliases")
        var forgedPages=pageAliasRows;forgedPages[1]["id"]="page_999"
        rejectsCategory("consolidation IDs","An unissued short page ID was accepted") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":forgedPages]),targets:aliasTargets)}
        var mixedPages=pageAliasRows;mixedPages[1]["id"]=aliasTargets[1].id
        rejectsCategory("consolidation IDs","Mixed canonical and short page selectors were repaired") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":mixedPages]),targets:aliasTargets)}
        var duplicatePages=pageAliasRows;duplicatePages[1]["id"]="page_0"
        rejectsCategory("consolidation IDs","Repeated short page selectors silently acknowledged a missing page") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":duplicatePages]),targets:aliasTargets)}
        rejectsCategory("consolidation IDs","An omitted short page selector was silently acknowledged") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":Array(pageAliasRows.dropLast())]),targets:aliasTargets)}
        rejectsCategory("consolidation IDs","Duplicate canonical target inputs made page binding ambiguous") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":pageAliasRows]),targets:[aliasTargets[0],aliasTargets[0],aliasTargets[2],aliasTargets[3]])}
        let legacyPageResult=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":aliasRows]),targets:aliasTargets).map{$0.0}
        check(legacyPageResult.map(\.id) == pageAliasResult.map(\.id) && zip(legacyPageResult,pageAliasResult).allSatisfy{$0.evidenceQuotes == $1.evidenceQuotes}, "Complete legacy canonical page output remains exact and compatible")

        var schemaTargets=aliasTargets;schemaTargets[1].records=Array(aliasOriginals.prefix(7));schemaTargets[2].records=Array(originals.prefix(52))
        let resultTools=ContextConsolidationRules.tools(schemaTargets)
        let namespace=resultTools[0],resultFunctions=namespace["tools"] as! [[String:Any]],resultFunction=resultFunctions[0]
        let parameters=resultFunction["parameters"] as! [String:Any],rootProperties=parameters["properties"] as! [String:[String:Any]]
        let pagesSchema=rootProperties["pages"]!,pageItems=pagesSchema["items"] as! [String:Any],pageVariants=pageItems["anyOf"] as! [[String:Any]]
        let pageSchema=pageVariants[0],pageProperties=pageSchema["properties"] as! [String:[String:Any]]
        check(resultTools.count == 1 && namespace["type"] as? String == "namespace" && namespace["name"] as? String == "pa" && resultFunctions.count == 1 && resultFunction["type"] as? String == "function" && resultFunction["name"] as? String == "prepare_context_pages" && ContextConsolidationRules.resultTool == "prepare_context_pages" && resultFunction["strict"] as? Bool == true, "The result transport exposes exactly one strict data-only pa.prepare_context_pages function")
        check(parameters["type"] as? String == "object" && parameters["additionalProperties"] as? Bool == false && parameters["required"] as? [String] == ["pages"] && Set(rootProperties.keys) == ["pages"] && pagesSchema["minItems"] as? Int == schemaTargets.count && pagesSchema["maxItems"] as? Int == schemaTargets.count, "Typed result requires exactly the captured page count with no extra root properties")
        check(pageVariants.count == schemaTargets.count && pageVariants.enumerated().allSatisfy { index, variant in
            let properties=variant["properties"] as! [String:[String:Any]]
            return properties["id"]!["enum"] as? [String] == ["page_\(index)"] && Set(variant["required"] as! [String]) == Set(properties.keys) && variant["additionalProperties"] as? Bool == false
        }, "Typed variants bind each complete page result to one exact issued page")
        check(pageVariants.enumerated().allSatisfy { index, variant in
            let properties=variant["properties"] as! [String:[String:Any]],evidence=properties["evidence"]!,item=evidence["items"] as! [String:Any]
            let expected=Set(schemaTargets[index].issuedRecords.flatMap(\.segments).filter{!$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.map(\.id))
            return item["type"] as? String == "string" && Set(item["enum"] as! [String]) == expected && evidence["minItems"] as? Int == 1 && evidence["maxItems"] as? Int == 32
        }, "Typed evidence is one exact passage choice scoped to its page, without independently generated source and segment fields")
        check(pageProperties["synopsis"]!["maxLength"] as? Int == 300 && pageProperties["markdown"]!["maxLength"] as? Int == 4500 && Set(pageProperties["purposeQuestion"]!["type"] as! [String]) == ["string","null"] && pageProperties["purposeQuestion"]!["maxLength"] as? Int == 300, "Typed result keeps text bounds and an explicitly required nullable purpose question")
        check(ContextKnowledgeRules.json(resultTools).utf8.count <= 6000 && !ContextKnowledgeRules.json(resultTools).contains(schemaTargets[0].id) && !ContextKnowledgeRules.json(resultTools).contains(aliasOriginals[0].text), "The complete fifty-two-record typed schema stays under six kilobytes without canonical identities or source bodies")
        check(ContextConsolidationRules.tools([]).isEmpty && ContextConsolidationRules.tools(schemaTargets+[schemaTargets[0]]).isEmpty, "Empty or over-capacity result schemas expose no callable preparation tool")
        check(ContextConsolidationRules.instructions.contains("exactly one completed pa.prepare_context_pages call") && ContextConsolidationRules.instructions.contains("Do not answer in ordinary text or call any other tool") && ContextConsolidationRules.instructions.contains("never its canonical referenceID"), "Production instructions require one completed typed result with short page IDs and no ordinary text")


        let singleRows:[[String:Any]]=aliasTargets.enumerated().map {index,value in
            ["id":"page_\(index)","synopsis":"Exact selected passages","markdown":"The project retains the supplied original calibration context.","purposeQuestion":NSNull(),
             "evidence":value.issuedRecords.map{$0.segments[0].id}]
        }
        let singlePages=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":singleRows]),targets:aliasTargets).map{$0.0}
        check(singlePages.map(\.id) == aliasPages.map(\.id) && zip(singlePages,aliasPages).allSatisfy{$0.references == $1.references && $0.evidenceQuotes == $1.evidenceQuotes}, "One constrained passage choice retains the exact canonical evidence of the earlier two-field protocol")
        check(zip(singlePages,aliasTargets).allSatisfy{page,value in Set(page.processedReferences ?? []) == Set(value.references)}, "Single passage selectors never replace or broaden processed source coverage")
        var badSingle=singleRows;badSingle[0]["evidence"]=["passage_999_0"]
        rejectsCategory("consolidation evidence passage","A fabricated combined passage choice was repaired") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":badSingle]),targets:aliasTargets)}
        badSingle=singleRows;badSingle[0]["evidence"]=["passage_0_9"]
        rejectsCategory("consolidation evidence passage","An unissued segment index was repaired") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":badSingle]),targets:aliasTargets)}
        badSingle=singleRows;badSingle[0]["evidence"]=Array(repeating:"passage_0_0",count:33)
        rejectsCategory("consolidation page","Single-string evidence bypassed the thirty-two-passage bound") {_=try ContextConsolidationRules.decode(ContextKnowledgeRules.json(["pages":badSingle]),targets:aliasTargets)}
        var whitespace=aliasTargets[0];whitespace.records[0].text=String(repeating:" ",count:500)+"A useful original tail."
        let whitespaceTool=ContextConsolidationRules.tools([whitespace])[0]
        let whitespaceFunction=(whitespaceTool["tools"] as! [[String:Any]])[0]
        let whitespaceParameters=whitespaceFunction["parameters"] as! [String:Any]
        check(!ContextKnowledgeRules.json(whitespaceParameters).contains("passage_0_0") && ContextKnowledgeRules.json(whitespaceParameters).contains("passage_0_1"), "The typed picker never offers a whitespace-only passage as usable evidence")
        let worstRecord=ContextKnowledgeRecord(reference:.init(kind:"memory",key:"longest-original",revision:"v1"),title:"Long original",text:String(repeating:"a",count:1600),date:date)
        var longest=aliasTargets[0];longest.records=(0..<52).map{index in var value=worstRecord;value.reference = .init(kind:"memory",key:"long-\(index)",revision:"v1");return value}
        check(!ContextConsolidationRules.tools([longest]).isEmpty && ContextKnowledgeRules.json(ContextConsolidationRules.tools([longest])).utf8.count <= 6000, "A single maximum-capacity target retains an issuable bounded schema even with four passages per original")

        print("Context consolidation: \(passed) checks passed; fictional records, no model/source/native requests.")
    }
    static func unseenReference() -> ContextPageReference { .init(kind: "memory", key: "previously-processed", revision: "v1") }
}
