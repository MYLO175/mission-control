#if DEBUG
import Foundation
import SwiftData

/// Fictional storage and completed transport only; every selection, page read,
/// consolidation receipt and foreground ownership decision uses production code.
@MainActor enum ContextPagesEvaluation {
    static func run() async throws -> [String: Bool] {
        guard ProcessInfo.processInfo.arguments.contains("--validate-advice-context") else { throw IntegrationError.verification }
        var checks = try consolidationChecks()
        checks.merge(try humanEvidenceChecks(), uniquingKeysWith: { $1 })
        checks.merge(try await pageReadChecks(), uniquingKeysWith: { $1 })
        checks.merge(try instructionChecks(), uniquingKeysWith: { $1 })
        checks.merge(try emailPageChecks(), uniquingKeysWith: { $1 })
        checks.merge(try primaryContextChecks(), uniquingKeysWith: { $1 })
        checks.merge(try projectionReuseChecks(), uniquingKeysWith: { $1 })
        checks.merge(try hierarchyGuideChecks(), uniquingKeysWith: { $1 })
        checks.merge(try navigationDirectoryChecks(), uniquingKeysWith: { $1 })
        checks.merge(try guideOverflowChecks(), uniquingKeysWith: { $1 })
        checks.merge(try largeAncestryChecks(), uniquingKeysWith: { $1 })
        checks.merge(try await ownedMutationChecks(), uniquingKeysWith: { $1 })
        return checks
    }

    private static func projectionReuseChecks() throws -> [String: Bool] {
        let fixture=try ContextPagesFixture()
        defer {fixture.clean()}
        let model=fixture.model,owner=fixture.registration
        let fact=PAMemory(registration:owner,text:"Fictional stable optical research context.",kind:.context,provenance:"Fictional human")
        guard model.assistant.memory.put(fact) else {throw IntegrationError.verification}
        let space=try model.assistant.projects.save(.init(registration:owner,kind:.space,title:"Fictional optics"),expected:nil)
        let initial=model.contextKnowledge(registration:owner).map(\.input)
        let builds=model.contextRecordProjections.builds
        var identical=true
        for _ in 0..<200 {identical = identical && model.contextKnowledge(registration:owner).map(\.input) == initial}
        var checks=["Context repeated validation reuses only identical canonical formatting":identical && model.contextRecordProjections.builds == builds]
        checks["Context warmed records still respect restricted memory IDs"] = !model.contextKnowledge(registration:owner,allowedMemoryIDs:[]).contains{$0.memoryID != nil}
        var renamed=space;renamed.title="Fictional updated optics"
        _=try model.assistant.projects.save(renamed,expected:space.revision)
        let updated=model.contextKnowledge(registration:owner)
        let changedProject=updated.first{$0.reference.kind == "project" && $0.projectID == space.id}
        let oldProjectRevision=initial.first{$0["id"] == "project:"+space.id.uuidString}?["revision"]
        checks["Context project edits rebuild cached formatting and exact revisions"] = changedProject?.title == renamed.title && oldProjectRevision != nil && changedProject?.reference.revision != oldProjectRevision
        let quote="Fictional source proposes an optical experiment."
        let evidence=MemorySourceEvidence(identity:.init(kind:.calendar,accountID:"fictional-account",containerID:"fictional-calendar",itemID:"fictional-event"),revision:"v1",label:"Fictional Calendar",quote:quote,observed:.now,sourceDate:.now)
        let source=PAMemory(registration:owner,text:quote,kind:.context,explicit:false,provenance:"Fictional source",evidence:quote,certainty:.inferred,durability:.situational,source:evidence)
        guard model.assistant.memory.putSources([source],evidenceTexts:[evidence.identity:quote],expectedRevision:model.assistant.memory.revision) else {throw IntegrationError.verification}
        var permitted=Set([source.id])
        model.assistant.memory.sourcePermissionProjection={permitted}
        let warmSource=model.contextKnowledge(registration:owner).contains{$0.memoryID == source.id}
        let sourceRevision=model.assistant.memory.revision
        checks["Context warmed source records stay excluded from human-only purposes"] = warmSource && !model.contextKnowledge(registration:owner,purpose:.email).contains{$0.memoryID == source.id}
        permitted=[]
        checks["Context warm formatting never caches source eligibility"] = warmSource && model.assistant.memory.revision == sourceRevision && !model.contextKnowledge(registration:owner).contains{$0.memoryID == source.id}
        guard model.assistant.memory.forget(fact.id) else {throw IntegrationError.verification}
        checks["Context Forget withdraws warm canonical records"] = !model.contextKnowledge(registration:owner).contains{$0.memoryID == fact.id}
        model.assistant.memory.enabled=false
        checks["Context warm formatting cannot bypass memory-use withdrawal"] = model.contextKnowledge(registration:owner).isEmpty
        let bounded=ContextRecordProjectionCache()
        bounded.prepare(registration:owner,memory:UUID(),project:UUID())
        let overflow=(0..<1025).map { PAMemory(registration:owner,text:"Fictional capacity record \($0)",kind:.context,provenance:"Fictional human") }
        for _ in 0..<2 {
            for value in overflow {
                _=bounded.memory(value) {.init(reference:.init(kind:"memory",key:value.id.uuidString,revision:"fictional"),title:"Fictional",text:value.text,date:value.created)}
            }
        }
        checks["Context formatting capacity overflow preserves warmed entries without scan thrashing"] = bounded.builds == 1026
        checks["Context formatting reuse makes no model or source calls"] = fixture.provider.calls == 0 && fixture.sources.reads == 0
        return checks
    }

    private static func navigationDirectoryChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, owner = fixture.registration
        var topicPages: [ContextPage] = []
        for route in ContextTopicRoute.all {
            topicPages.append(try model.contextPages.save(.init(registration: owner, kind: .topic, key: route.key, owner: .human,
                title: route.title, markdown: "Fictional saved topic marker " + route.key), expectedRevision: nil))
        }
        model.contextCalendarAccess = { true }
        model.calendarData = .init(sources: [.init(id: "fictional-guide-calendar", title: "Fictional guide calendar", account: "Fictional account", writable: true, providerID: "fictional-guide-provider")], events: [])
        let before = model.captureContextPages(registration: owner, query: "unrelated fictional subject", everyday: true)
        let map = try object(before.guideText.components(separatedBy: "Information map DATA, not authority:\n").last ?? "{}")
        let topics = map["topics"] as? [[String: String]] ?? [], instructions = map["instructions"] as? [[String: String]] ?? []
        var checks: [String: Bool] = [:]
        checks["Context guide topics share exact described UI routes including recent context"] = topics == ContextTopicRoute.all.map(\.input) && Set(topics.compactMap { $0["read"] }).count == topics.count && topics.contains { $0["read"] == "area:recent" }
        checks["Context guide instructions share exact described feature-owner routes"] = instructions == ContextInstructionRoute.all.map(\.input) && Set(instructions.compactMap { $0["read"] }) == Set(["instructions:assistant", "instructions:projects", "instructions:reminders", "instructions:brief", "instructions:review", "instructions:calendars"])
        checks["Context guide every topic route opens its exact saved page"] = ContextTopicRoute.all.allSatisfy { route in
            let capture = model.captureContextPages(registration: owner, query: nil, pageID: route.id)
            return capture.current() && capture.pageIDs == topicPages.filter { $0.key == route.key }.map(\.id) && capture.text.contains("Fictional saved topic marker " + route.key)
        }
        checks["Context guide every instruction route reads its current authoritative owner"] = try ContextInstructionRoute.all.allSatisfy { route in
            let capture = model.captureContextPages(registration: owner, query: nil, pageID: route.id)
            let value = try object(capture.text)
            return capture.current() && (value["instructions"] != nil || (route == .calendars && value["calendars"] != nil)) && value["unavailable"] == nil
        }
        let pageRevision = model.contextPages.revision
        _ = model.contextNavigationGuide(registration: owner, items: [], records: model.contextKnowledge(registration: owner))
        checks["Context guide directory reads never create or rewrite context pages"] = model.contextPages.revision == pageRevision
        _ = try model.contextPages.save(.init(registration: owner, kind: .instruction, key: ContextFeature.assistant.rawValue, owner: .human,
            title: "Fictional assistant policy", markdown: "Private fictional policy marker"), expectedRevision: nil)
        var revised = topicPages[0]; revised.markdown = "Private fictional changed topic marker"
        _ = try model.contextPages.save(revised, expectedRevision: topicPages[0].revision)
        let after = model.captureContextPages(registration: owner, query: "another fictional subject", everyday: true)
        checks["Context guide routing stays stable across factual topic and human policy edits"] = before.guideText == after.guideText && before.guideFingerprint == after.guideFingerprint && !after.guideText.contains("Private fictional")
        checks["Context guide unknown routes return only an error without unrelated working context"] = try ["area:careeer", "missing-fictional-page", "instructions:unknown"].allSatisfy { id in
            let capture = model.captureContextPages(registration: owner, query: nil, pageID: id)
            let value = try object(capture.text)
            return value["unavailable"] != nil && value.count == 1 && capture.pageIDs.isEmpty && capture.referenceVersions.isEmpty && capture.guideText.isEmpty
        }
        let targeted = model.captureContextPages(registration: owner, query: "unrelated bulletin", purpose: .email)
        checks["Context guide directory does not widen targeted source-assessment context"] = targeted.guideText.isEmpty && !targeted.text.contains(ContextTopicRoute.all[0].about)
        model.assistant.memory.enabled = false
        checks["Context guide expanded directory still respects memory-use withdrawal"] = model.captureContextPages(registration: owner, query: nil, everyday: true).guideText.isEmpty
        return checks
    }

    private static func hierarchyGuideChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, owner = fixture.registration
        let parent = try model.assistant.projects.save(.init(registration: owner, kind: .space, title: "Fictional Lark engineering"), expected: nil)
        var childValue = LifeItem(registration: owner, kind: .space, title: "Fictional Lyra optics")
        childValue.parentID = parent.id
        let child = try model.assistant.projects.save(childValue, expected: nil)
        let other = try model.assistant.projects.save(.init(registration: owner, kind: .space, title: "Fictional unrelated studio"), expected: nil)
        let empty = try model.assistant.projects.save(.init(registration: owner, kind: .space, title: "Fictional empty space"), expected: nil)
        func saveGuidance(_ scope: ContextInstructionScope, text: String, reference: ContextPageReference? = nil) throws -> ContextPage {
            try model.contextPages.save(.init(registration: owner, kind: .instruction, key: scope.key, owner: .human,
                title: "Fictional scoped instructions", markdown: text, references: reference.map { [$0] } ?? []), expectedRevision: nil)
        }
        let parentGuide = try saveGuidance(.space(parent.id), text: "Use SI units for engineering plans.", reference: model.contextProjectIdentity(parent))
        let childGuide = try saveGuidance(.space(child.id), text: "For optics, report measurement uncertainty.", reference: model.contextProjectIdentity(child))
        let siblingGuide = try saveGuidance(.space(other.id), text: "Unrelated studio guidance must stay scoped.", reference: model.contextProjectIdentity(other))
        let topicGuide = try saveGuidance(.topic(LifeArea.studies.rawValue), text: "Explain study concepts using worked examples.")
        let records = model.contextKnowledge(registration: owner, includeTopics: false)
        let items = model.assistant.projects.items(owner, includeTopics: false).filter { !$0.kind.isWork }
        let rows = model.contextSpaceDescriptions(registration: owner, items: items, records: records)
        var checks: [String: Bool] = [:]
        checks["Context hierarchy every empty/new space has a deterministic row before synthesis"] = Set(rows.map(\.id)) == Set([parent.id, child.id, other.id, empty.id]) && rows.allSatisfy { $0.text.isEmpty }
        checks["Context hierarchy rows retain the exact canonical parent identity"] = rows.first { $0.id == child.id }?.parentID == parent.id && ContextHierarchyRules.ancestors(of: child.id, items: items).map(\.id) == [parent.id]
        checks["Context hierarchy index/inspection never creates a maintained page"] = model.contextPages.pages(registration: owner).allSatisfy { $0.kind == .instruction }
        let childID = ContextPage.stableID(registration: owner, kind: .project, key: child.id.uuidString)
        let captured = model.captureContextPages(registration: owner, query: nil, pageID: childID)
        let childObject = try object(captured.text)
        let instructions = childObject["scopeInstructions"] as? [[String: String]] ?? []
        checks["Context hierarchy parent guidance precedes specific child guidance"] = instructions.map { $0["scope"] } == [ContextInstructionScope.space(parent.id).key, ContextInstructionScope.space(child.id).key]
        checks["Context hierarchy unrelated branch guidance is not supplied"] = !captured.text.contains(siblingGuide.markdown) && captured.referenceVersions["page:" + siblingGuide.id] == nil
        checks["Context hierarchy inherited guidance captures exact human versions and filing"] = captured.referenceVersions["page:" + parentGuide.id] == parentGuide.revision.uuidString && captured.referenceVersions["page:" + childGuide.id] == childGuide.revision.uuidString && captured.referenceVersions["project:" + child.id.uuidString] != nil && captured.current()
        let parentID = ContextPage.stableID(registration: owner, kind: .project, key: parent.id.uuidString)
        let parentRead = model.captureContextPages(registration: owner, query: nil, pageID: parentID)
        checks["Context hierarchy reading a parent offers exact child page navigation"] = (try object(parentRead.text)["subspaces"] as? [[String: String]])?.contains { $0["id"] == childID } == true
        let areaRead = model.captureContextPages(registration: owner, query: nil, pageID: "area:" + LifeArea.studies.rawValue)
        checks["Context hierarchy area instructions are available before a generated topic page"] = areaRead.text.contains(topicGuide.markdown) && areaRead.referenceVersions["page:" + topicGuide.id] == topicGuide.revision.uuidString
        let a = model.captureContextPages(registration: owner, query: "optics background", everyday: true)
        let b = model.captureContextPages(registration: owner, query: "different current question", everyday: true)
        checks["Context guide stays identical across requests with unchanged structure"] = !a.guideText.isEmpty && a.guideText == b.guideText && a.guideFingerprint == b.guideFingerprint
        checks["Context guide routes root spaces and areas without listing every nested page"] = a.guideText.contains(parent.title) && a.guideText.contains("area:" + LifeArea.studies.rawValue) && !a.guideText.contains(childID)
        checks["Context guide plus dynamic ordinary input share the twenty KB bound"] = a.text.utf8.count + a.guideText.utf8.count <= 20_000
        checks["Context guide is not injected into targeted email input"] = model.captureContextPages(registration: owner, query: "unrelated broadcast", purpose: .email).guideText.isEmpty
        let purpose = try model.contextPages.save(.init(registration: owner, kind: .note, key: "project-purpose:" + child.id.uuidString,
            owner: .human, title: "About optics", markdown: "Compare camera calibration methods.\nKeep the same physical rig.", references: [model.contextProjectIdentity(child)]), expectedRevision: nil)
        let currentRecords = model.contextKnowledge(registration: owner, includeTopics: false)
        let described = model.contextSpaceDescriptions(registration: owner, items: items, records: currentRecords).first { $0.id == child.id }
        checks["Context hierarchy human description takes priority and remains distinct"] = described?.human == true && described?.text == "Compare camera calibration methods." && model.contextPages.page(id: purpose.id, registration: owner)?.markdown == purpose.markdown
        checks["Context hierarchy consolidation receives labelled original parent context"] = model.contextConsolidation.targets(model, registration: owner).first { $0.key == child.id.uuidString }?.records.contains { $0.projectID == parent.id && $0.relevance?.contains("Inherited context") == true } == true
        func saveAncestorOnly(_ item: LifeItem, ancestor: LifeItem) throws -> ContextPage {
            guard let target = model.contextConsolidation.targets(model, registration: owner).first(where: { $0.key == item.id.uuidString }),
                  let evidence = target.records.first(where: { $0.reference.kind == "project" && $0.projectID == ancestor.id }) else { throw IntegrationError.verification }
            let output: [String: Any] = ["pages": [["id": target.id, "synopsis": "Supported inherited context", "markdown": "Parent context: " + evidence.text,
                "evidence": [["id": evidence.reference.contextKey, "quote": String(evidence.text.prefix(80))]]]]]
            let page = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(output), targets: [target])[0].0
            return try model.contextPages.save(page, expectedRevision: nil)
        }
        let inheritedPage = try saveAncestorOnly(child, ancestor: parent)
        checks["Context hierarchy generated inheritance binds filing independently of selected quotes"] = inheritedPage.evidenceQuotes?.allSatisfy { $0.referenceID != ContextPageReference.stableID(kind: "project", key: child.id.uuidString) } == true && inheritedPage.references.contains { $0.kind == "project" && $0.key == child.id.uuidString } && model.contextPageEligible(inheritedPage, records: model.contextKnowledge(registration: owner))
        checks["Context hierarchy human instructions never become extracted facts/page evidence"] = !model.contextKnowledge(registration: owner, purpose: .maintenance).contains { $0.reference.key == parentGuide.id || $0.reference.key == topicGuide.id }
        var revised = parentGuide; revised.markdown = "Updated engineering guidance from the human."
        _ = try model.contextPages.save(revised, expectedRevision: parentGuide.revision)
        checks["Context hierarchy editing inherited instructions invalidates only exact prior capture"] = !captured.current() && !model.contextKnowledgeAvailable(registration: owner, versions: captured.referenceVersions)
        let beforeMove = model.captureContextPages(registration: owner, query: nil, pageID: childID)
        var moved = child; moved.parentID = other.id
        _ = try model.assistant.projects.save(moved, expected: child.revision)
        checks["Context hierarchy moving a child withholds persisted old inherited prose"] = !model.contextPageEligible(inheritedPage, records: model.contextKnowledge(registration: owner))
        checks["Context hierarchy moving a child invalidates captured inheritance"] = !beforeMove.current() && !model.contextKnowledgeAvailable(registration: owner, versions: beforeMove.referenceVersions)
        let afterMove = model.captureContextPages(registration: owner, query: nil, pageID: childID)
        checks["Context hierarchy a fresh child read follows its new exact parent"] = afterMove.text.contains(siblingGuide.markdown) && !afterMove.text.contains(revised.markdown) && afterMove.current()
        var inheritedOnlyValue = LifeItem(registration: owner, kind: .space, title: "Fictional inherited-only branch")
        inheritedOnlyValue.parentID = parent.id
        let inheritedOnly = try model.assistant.projects.save(inheritedOnlyValue, expected: nil)
        let inheritedOnlyID = ContextPage.stableID(registration: owner, kind: .project, key: inheritedOnly.id.uuidString)
        let inheritedOnlyCapture = model.captureContextPages(registration: owner, query: nil, pageID: inheritedOnlyID)
        var inheritedMoved = inheritedOnly; inheritedMoved.parentID = other.id
        _ = try model.assistant.projects.save(inheritedMoved, expected: inheritedOnly.revision)
        checks["Context hierarchy filing is guarded even without a child instruction page"] = inheritedOnlyCapture.referenceVersions["project:" + inheritedOnly.id.uuidString] != nil && !inheritedOnlyCapture.current()
        var chain: [LifeItem] = [], previous: UUID?
        for index in 0..<7 {
            var value = LifeItem(registration: owner, kind: .space, title: "Fictional deep space \(index)")
            value.parentID = previous
            let saved = try model.assistant.projects.save(value, expected: nil)
            _ = try saveGuidance(.space(saved.id), text: String(repeating: "Bounded human guidance. ", count: 100), reference: model.contextProjectIdentity(saved))
            chain.append(saved); previous = saved.id
        }
        let bounded = model.contextGuidance(scopes: [.space(chain.last!.id)], registration: owner,
            items: model.assistant.projects.items(owner, includeTopics: false), records: model.contextKnowledge(registration: owner, includeTopics: false))
        checks["Context hierarchy bounded guidance always retains the most specific child"] = bounded.rows.last?["scope"] == ContextInstructionScope.space(chain.last!.id).key && ContextKnowledgeRules.json(bounded.rows).utf8.count <= 4800 && bounded.rows.count < chain.count
        let deepPage = try saveAncestorOnly(chain.last!, ancestor: chain.first!)
        var movedIntermediate = chain[3]; movedIntermediate.parentID = nil
        _ = try model.assistant.projects.save(movedIntermediate, expected: chain[3].revision)
        checks["Context hierarchy moving an intermediate ancestor withholds persisted inherited prose"] = !model.contextPageEligible(deepPage, records: model.contextKnowledge(registration: owner)) && deepPage.references.contains { $0.kind == "project" && $0.key == chain[3].id.uuidString }
        let phaseOne = try model.assistant.projects.save(.init(registration: owner, kind: .space, title: "Fictional phase 1"), expected: nil)
        let phaseTwo = try model.assistant.projects.save(.init(registration: owner, kind: .space, title: "Fictional phase 2"), expected: nil)
        _ = try saveGuidance(.space(phaseOne.id), text: "First phase instruction", reference: model.contextProjectIdentity(phaseOne))
        let secondPhase = try saveGuidance(.space(phaseTwo.id), text: "Second phase instruction", reference: model.contextProjectIdentity(phaseTwo))
        let phaseCapture = model.captureContextPages(registration: owner, query: "Please use Fictional phase 1 guidance")
        checks["Context hierarchy full title guidance preserves numeric distinctions"] = phaseCapture.text.contains("First phase instruction") && !phaseCapture.text.contains(secondPhase.markdown)
        var cycleA = LifeItem(registration: owner, kind: .space, title: "Fictional cycle A")
        var cycleB = LifeItem(registration: owner, kind: .space, title: "Fictional cycle B")
        cycleA.parentID = cycleB.id; cycleB.parentID = cycleA.id
        checks["Context hierarchy malformed ancestry terminates without mutating identities"] = ContextHierarchyRules.ancestors(of: cycleA.id, items: [cycleA, cycleB]).map(\.id) == [cycleB.id]
        checks["Context hierarchy unknown instruction scopes remain unavailable"] = ContextInstructionScope(key: "topic:unsupported-future-area") == nil
        checks["Context guide and scope fixtures make zero model/source calls"] = fixture.provider.calls == 0 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        model.chatGPT.activeID = "fictional-other-owner"
        checks["Context guide and inherited instructions stay account bound"] = !afterMove.current() && model.captureContextPages(registration: owner, query: nil, everyday: true).guideText.isEmpty
        return checks
    }

    private static func guideOverflowChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, owner = fixture.registration
        var last: LifeItem?
        for index in 0..<7 {
            var value = LifeItem(registration: owner, kind: .space, title: "Fictional overflow space \(index)")
            value.parentID = last?.id
            last = try model.assistant.projects.save(value, expected: nil)
            _ = try model.contextPages.save(.init(registration: owner, kind: .instruction, key: ContextInstructionScope.space(last!.id).key, owner: .human,
                title: "Fictional scoped guide", markdown: String(repeating: "Guidance for this space. ", count: 80), references: [model.contextProjectIdentity(last!)]), expectedRevision: nil)
        }
        for feature in ContextFeature.allCases {
            _ = try model.contextPages.save(.init(registration: owner, kind: .instruction, key: feature.rawValue, owner: .human,
                title: feature.title, markdown: String(repeating: "Human feature instructions. ", count: 50)), expectedRevision: nil)
        }
        for index in 0..<10 {
            _ = try model.assistant.projects.save(.init(registration: owner, kind: .space,
                title: "Fictional extra root \(index) with a deliberately long descriptive title"), expected: nil)
        }
        let huge = try model.contextPages.save(.init(registration: owner, kind: .overview, key: "everyday", owner: .human,
            title: "Fictional composed character", markdown: "a" + String(repeating: "\u{0300}", count: 4800)), expectedRevision: nil)
        let capture = model.captureContextPages(registration: owner, query: last!.title, everyday: true)
        let value = try object(capture.text)
        return [
            "Context guide survives dynamic overflow and retains its exact dependency validator": value["unavailable"] != nil && !capture.guideText.isEmpty && capture.guideFingerprint == ContextKnowledgeRules.fingerprint(capture.guideText) && capture.current(),
            "Context guide overflow discards omitted page and scoped instruction dependencies": capture.pageIDs.isEmpty && capture.referenceVersions["page:" + huge.id] == nil && !capture.referenceVersions.keys.contains { $0.hasPrefix("page:") },
            "Context guide overflow still shares the complete twenty KB ordinary bound": capture.text.utf8.count + capture.guideText.utf8.count <= 20_000,
            "Context guide overflow performs no inference or source reads": fixture.provider.calls == 0 && fixture.sources.reads == 0
        ]
    }

    private static func largeAncestryChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, owner = fixture.registration
        var chain: [LifeItem] = []
        for index in 0..<9 {
            var item = LifeItem(registration: owner, kind: .space, title: "Fictional large hierarchy \(index)")
            item.parentID = chain.last?.id
            item.notes = String(repeating: "Fictional long original project notes. ", count: 200)
            chain.append(try model.assistant.projects.save(item, expected: nil))
        }
        let child = chain.last!
        guard let target = model.contextConsolidation.targets(model, registration: owner).first(where: { $0.key == child.id.uuidString }),
              let evidence = target.records.first(where: { $0.reference.kind == "project" && $0.projectID != child.id }),
              let unissued = chain.first(where: { item in item.parentID != nil && !target.records.contains { $0.reference.kind == "project" && $0.projectID == item.id } }) else { throw IntegrationError.verification }
        let input = ContextConsolidationRules.targetInputs([target])[0]
        let output: [String: Any] = ["pages": [["id": target.id, "synopsis": "Bounded inherited context", "markdown": "Supported parent information",
            "evidence": [["id": evidence.reference.contextKey, "quote": String(evidence.text.prefix(80))]]]]]
        let page = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(output), targets: [target])[0].0
        let saved = try model.contextPages.save(page, expectedRevision: nil)
        let currentBefore = model.contextPageEligible(saved, records: model.contextKnowledge(registration: owner))
        var moved = unissued; moved.parentID = nil
        _ = try model.assistant.projects.save(moved, expected: unissued.revision)
        return [
            "Context hierarchy large original ancestor notes retain bounded processable targets": ContextKnowledgeRules.json(input).utf8.count <= ContextConsolidationSelection.maximumTargetBytes && ContextConsolidationSelection.batch([target], now: .now, timezone: "Europe/London").count == 1 && target.structuralReferences.count == 9,
            "Context hierarchy unissued ancestor bodies remain exact metadata dependencies": currentBefore && saved.references.contains { $0.kind == "project" && $0.key == unissued.id.uuidString } && !model.contextPageEligible(saved, records: model.contextKnowledge(registration: owner)),
            "Context hierarchy large ancestry verification makes no source or model calls": fixture.provider.calls == 0 && fixture.sources.reads == 0
        ]
    }

    /// Produces supported fictional provider output; no selection algorithm lives here.
    @discardableResult private static func consolidate(_ target: ContextPageTarget, in fixture: ContextPagesFixture,
                                                       checkpoint: Bool = false) throws -> ContextPage {
        guard let evidence = target.records.first else { throw IntegrationError.verification }
        let output: [String: Any] = ["pages": [["id": target.id, "synopsis": "Fictional supported context",
            "markdown": "# Fictional context\n\n" + evidence.text,
            "evidence": [["id": evidence.reference.contextKey, "quote": String(evidence.text.prefix(80))]]]]]
        let decoded = try ContextConsolidationRules.decode(ContextKnowledgeRules.json(output), targets: [target])
        guard let page = decoded.first?.0 else { throw IntegrationError.verification }
        let store = fixture.model.contextPages, previous = store.page(id: target.id, registration: fixture.registration)
        var expected: [String: UUID] = [:]
        if let previous { expected[page.id] = previous.revision }
        let oldCheckpoint = store.checkpoint(registration: fixture.registration)
        let refs = Array(Dictionary(((oldCheckpoint?.references ?? []) + target.references).map { ($0.contextKey, $0) }, uniquingKeysWith: { _, new in new }).values)
        let saved = try store.saveBatch([page], expectedRevisions: expected,
            checkpoint: checkpoint ? .init(registration: fixture.registration, references: refs) : nil,
            expectedCheckpointRevision: checkpoint ? oldCheckpoint?.revision : nil)
        guard let result = saved.first else { throw IntegrationError.verification }
        return result
    }

    private static func consolidationChecks() throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        var facts: [PAMemory] = []
        for index in 0..<27 {
            let fact = PAMemory(registration: registration, text: "Fictional cobalt study fact \(index) concerns a distinct engineering exercise.",
                kind: .context, provenance: "Fictional human fixture", created: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
                organisation: .init(areas: [.studies], connections: []))
            guard model.assistant.memory.put(fact) else { throw IntegrationError.verification }
            facts.append(fact)
        }
        guard let first = model.contextConsolidation.targets(model, registration: registration).first(where: { $0.kind == .topic && $0.key == LifeArea.studies.rawValue }) else { throw IntegrationError.verification }
        let firstPage = try consolidate(first, in: fixture, checkpoint: true)
        let firstIDs = Set(first.references.map(\.contextKey))
        let overflow = Set(facts.map { "memory:" + $0.id.uuidString }).subtracting(firstIDs)
        checks["Context pages bound first target and leave record 21 onward unprocessed"] = first.records.count == 20 && overflow.count == 7 && firstPage.processedReferences?.count == 20
        checks["Context pages checkpoint acknowledges only supplied batch records"] = Set(model.contextPages.checkpoint(registration: registration)?.references.map(\.contextKey) ?? []).isDisjoint(with: overflow)
        let working = model.captureContextPages(registration: registration, query: "cobalt study")
        let workingRows = try object(working.text)["workingChanges"] as? [[String: String]] ?? []
        checks["Context pages overflow stays available as working context before consolidation"] = overflow.isSubset(of: Set(workingRows.compactMap { $0["id"] }))
        guard let second = model.contextConsolidation.targets(model, registration: registration).first(where: { $0.id == first.id }) else { throw IntegrationError.verification }
        checks["Context pages next target prioritises all independently pending overflow"] = second.hasPendingChanges && overflow.isSubset(of: Set(second.references.map(\.contextKey)))
        let secondPage = try consolidate(second, in: fixture, checkpoint: true)
        checks["Context pages accumulate per-page progress beyond one twenty-record window"] = Set(secondPage.processedReferences?.map(\.contextKey) ?? []) == Set(facts.map { "memory:" + $0.id.uuidString })
        checks["Context pages quiet target stops after every current version was processed"] = !model.contextConsolidation.targets(model, registration: registration).contains(where: { $0.id == first.id })
        checks["Context pages progress survives reopening actual storage"] = ContextPageStore(container: model.container).page(id: secondPage.id, registration: registration)?.processedReferences == secondPage.processedReferences

        let shared = try ContextPagesFixture()
        defer { shared.clean() }
        let sharedFact = PAMemory(registration: shared.registration, text: "Fictional cobalt study preference is to compare worked engineering examples.", kind: .preference,
            provenance: "Fictional human fixture", organisation: .init(areas: [.about, .studies], connections: []))
        guard shared.model.assistant.memory.put(sharedFact) else { throw IntegrationError.verification }
        let targets = shared.model.contextConsolidation.targets(shared.model, registration: shared.registration)
        guard let overview = targets.first(where: { $0.kind == .overview }), let topic = targets.first(where: { $0.kind == .topic && $0.key == LifeArea.studies.rawValue }) else { throw IntegrationError.verification }
        _ = try consolidate(overview, in: shared, checkpoint: true)
        let after = shared.model.contextConsolidation.targets(shared.model, registration: shared.registration)
        checks["Context pages shared fact global acknowledgement cannot consume another target"] = after.contains { $0.id == topic.id && $0.hasPendingChanges && $0.references.contains { $0.key == sharedFact.id.uuidString } }
        checks["Context pages completed overview remains quiet while sibling target is pending"] = !after.contains(where: { $0.id == overview.id })
        _ = try consolidate(topic, in: shared)
        checks["Context pages sibling target quiets only after its own successful batch"] = !shared.model.contextConsolidation.targets(shared.model, registration: shared.registration).contains(where: { $0.id == topic.id })
        checks["Context pages fixture makes no real inference requests"] = fixture.provider.calls == 0 && shared.provider.calls == 0 && fixture.sources.reads == 0 && shared.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        let questionProject = try shared.model.assistant.projects.save(.init(registration: shared.registration, kind: .space, title: "Fictional purpose question"), expected: nil)
        _ = try shared.model.contextQuestions.offer(registration: shared.registration, projectID: questionProject.id, identity: shared.model.contextProjectIdentity(questionProject), question: "What are you aiming to achieve with this fictional project?")
        checks["Context questions share the existing daily allowance with conversation learning"] = !shared.model.learningRuntime().canOfferQuestion(shared.registration, .now)
        checks["Context questions pending clarification suppresses more project-purpose offers"] = shared.model.contextConsolidation.targets(shared.model, registration: shared.registration).allSatisfy { !$0.mayAskPurpose }
        if let pending = shared.model.contextQuestions.questions(registration: shared.registration).first {
            _ = try shared.model.contextQuestions.dismiss(id: pending.id, registration: shared.registration, expectedRevision: pending.revision)
        }
        checks["Context question dismissal does not reopen the same day's question allowance"] = !shared.model.learningRuntime().canOfferQuestion(shared.registration, .now)
        checks["Context questions leave the next day's learning allowance available"] = shared.model.learningRuntime().canOfferQuestion(shared.registration, Date.now.addingTimeInterval(86400))
        return checks
    }

    private static func emailPageChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        let project = try model.assistant.projects.save(.init(registration: registration, kind: .space, title: "Fictional workshop"), expected: nil)
        let purpose = try model.contextPages.save(.init(registration: registration, kind: .note, key: "project-purpose:" + project.id.uuidString, owner: .human, title: "Purpose of fictional workshop", markdown: "Compare cobalt spectroscopy calibration methods using a small optical rig.", references: [model.contextProjectIdentity(project)]), expectedRevision: nil)
        _ = try model.contextPages.save(.init(registration: registration, kind: .overview, key: "everyday", owner: .human, title: "Everyday orientation", markdown: "Fictional cobalt interests and unrelated personal background."), expectedRevision: nil)
        let raw: [String: Any] = ["id": "fictional-cobalt-email", "accountID": "fictional-mail", "account": "Fictional Mail", "messageID": 1, "internetMessageID": "cobalt@example.invalid", "sender": "Dr Kestrel", "subject": "Cobalt spectroscopy calibration guide", "received": Date.now.ISO8601Format(), "unread": true, "replied": false, "flagged": false]
        let message = try JSONDecoder().decode(MailMessage.self, from: JSONSerialization.data(withJSONObject: raw))
        let body = "The cobalt spectroscopy calibration guide compares practical optical methods."
        let captured = model.emailSummaries.relevanceContext(message, model: model, body: body)
        let header = model.emailSummaries.relevanceContext(message, model: model, header: true)
        let stamp = model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        var checks: [String: Bool] = [:]
        checks["Context email purpose-only discovery selects the exact active human project"] = captured.memories.isEmpty && captured.workspace.contains { $0["id"] == "life:" + project.id.uuidString } && captured.contextPages.contains { $0["id"] == purpose.id }
        checks["Context email excludes everyday orientation and raw working changes"] = captured.contextPages.allSatisfy { $0["id"] == purpose.id } && captured.input["workingChanges"] == nil
        let bodyBytes = try JSONSerialization.data(withJSONObject: EmailRelevanceRules.pageInput(captured.contextPages)).count
        let headerBytes = try JSONSerialization.data(withJSONObject: EmailRelevanceRules.pageInput(header.contextPages)).count
        checks["Context email body and header page payloads obey encoded bounds"] = bodyBytes <= 3500 && headerBytes <= 1200
        checks["Context email exact current page dependencies are available"] = captured.contextPageDependencies?["page:" + purpose.id] == purpose.revision.uuidString && model.emailSummaries.relevanceContextAvailable(captured, model: model)
        let unrelated = try model.contextPages.save(.init(registration: registration, kind: .note, key: "unrelated-fern", owner: .human, title: "Gardening", markdown: "Keep the fictional fern in indirect light."), expectedRevision: nil)
        checks["Context email unrelated human notes do not trigger reclassification"] = stamp == model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body) && model.emailSummaries.relevanceContextAvailable(captured, model: model)
        var revised = purpose; revised.markdown += "\nThe comparison now focuses on repeatable optical measurements."
        let updated = try model.contextPages.save(revised, expectedRevision: purpose.revision)
        checks["Context email changed human purpose rejects stale classification and changes discovery"] = !model.emailSummaries.relevanceContextAvailable(captured, model: model) && stamp != model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        let current = model.emailSummaries.relevanceContext(message, model: model, body: body)
        let currentStamp = model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        var generated = ContextPage(registration: registration, kind: .topic, key: "cobalt", owner: .generated, title: "Cobalt calibration", markdown: "A short generated synopsis of the human's optical comparison.", references: [.init(kind: "page", key: updated.id, revision: updated.revision.uuidString)])
        let first = try model.contextPages.save(generated, expectedRevision: nil)
        generated.markdown += "\nThe original purpose stays authoritative."
        _ = try model.contextPages.save(generated, expectedRevision: first.revision)
        checks["Context email generated rephrasing alone does not trigger another assessment"] = currentStamp == model.emailSummaries.reviewPreferenceStamp(message, model: model, evidence: body)
        try model.contextPages.forget(id: unrelated.id, registration: registration, expectedRevision: unrelated.revision)
        model.assistant.memory.enabled = false
        checks["Context email paused memory withdraws prior page-backed input"] = !model.emailSummaries.relevanceContextAvailable(current, model: model) && model.emailSummaries.relevanceContext(message, model: model, body: body).contextPages.isEmpty
        checks["Context email fixtures make no source or subscription requests"] = fixture.sources.reads == 0 && fixture.provider.calls == 0 && model.aiUsage.state.records.isEmpty
        return checks
    }

    private static func primaryContextChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        let fact = PAMemory(registration: registration, text: "I research light propagation using repeatable measurements.", kind: .context, provenance: "Fictional human fixture")
        guard model.assistant.memory.put(fact) else { throw IntegrationError.verification }
        let reference = ContextPageReference(kind: "memory", key: fact.id.uuidString, revision: MemoryDependencyRules.fingerprint(MemoryRetrieval.record(fact)))
        let topic = try model.contextPages.save(.init(registration: registration, kind: .topic, key: "cobalt", owner: .generated,
            title: "Cobalt optics", synopsis: "Cobalt calibration context", markdown: "The Cobalt optics work compares repeatable measurements of light propagation.", references: [reference]), expectedRevision: nil)
        _ = try model.contextPages.save(.init(registration: registration, kind: .overview, key: "maintained", owner: .generated,
            title: "Everyday overview", markdown: "The human researches light propagation.", references: [reference]), expectedRevision: nil)
        _ = try model.contextPages.save(.init(registration: registration, kind: .overview, key: "everyday", owner: .human,
            title: "Everyday context", markdown: "Prefer practical explanations."), expectedRevision: nil)
        let ordinary = model.captureContextPages(registration: registration, query: "Cobalt optics", includeTopics: false, everyday: true)
        let broad = try object(ordinary.text)
        let automatic = model.automaticMemory(.brief, query: "Cobalt optics")
        var checks: [String: Bool] = [:]
        checks["Primary context separate orientation allowance retains a relevant topic beside two overviews"] = ordinary.pageIDs.contains(topic.id) && ordinary.pageIDs.count == 3
        checks["Primary context automatic pages resolve support beyond old lexical fact selection"] = automatic.records.isEmpty && automatic.contextPageDependencies[reference.contextKey] == reference.revision && automatic.pageContext.contains("Cobalt optics")
        checks["Primary context preserves captured feature purpose for later dependency checks"] = automatic.contextPageDependencies["context-purpose:brief"] == "1" && model.contextPageDependenciesAvailable(automatic.contextPageDependencies, registration: registration)
        checks["Primary context ordinary chat automatically receives human feature guidance"] = (broad["featureInstructions"] as? [[String: String]])?.count == ContextFeature.allCases.count
        let email = model.captureContextPages(registration: registration, query: "Cobalt optics", includeTopics: false, purpose: .email)
        let emailObject = try object(email.text)
        checks["Primary context email resolves all relevant human support without raw working context"] = email.pageIDs.contains(topic.id) && ((emailObject["workingChanges"] as? [[String: String]]) ?? []).isEmpty
        let defaultGuidance = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:projects")
        let instruction = try model.contextPages.save(.init(registration: registration, kind: .instruction, key: ContextFeature.projects.rawValue, owner: .human,
            title: ContextFeature.projects.title, markdown: "Keep Cobalt experiment work in its existing project space."), expectedRevision: nil)
        let guidance = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:projects")
        checks["Primary context edited feature guidance replaces default and invalidates prior capture"] = !defaultGuidance.current() && guidance.current() && guidance.text.contains("existing project space")
        let reviewConversation = model.captureContextPages(registration: registration, query: "Cobalt optics", includeTopics: false, everyday: false)
        checks["Primary context Review conversations receive the same saved feature guidance without everyday orientation"] = (try object(reviewConversation.text)["featureInstructions"] as? [[String: String]])?.count == ContextFeature.allCases.count && reviewConversation.referenceVersions["instruction:projects"] == instruction.revision.uuidString && reviewConversation.referenceVersions["instruction:assistant"] != nil
        checks["Primary context feature instructions never enter fact extraction or generated page evidence"] = !model.contextKnowledge(registration: registration, purpose: .maintenance).contains { $0.reference.key == instruction.id } && !model.contextConsolidation.targets(model, registration: registration).flatMap(\.records).contains { $0.reference.key == instruction.id }
        model.contextCalendarAccess = { true }
        let calendar = SourceOption(id: "fictional-cobalt-calendar", title: "Cobalt", account: "Fictional university", writable: true, providerID: "fictional-university-provider")
        model.calendarData = .init(sources: [calendar], events: [])
        let calendarFact = PAMemory(registration: registration, text: "Use my Fictional university calendar for Cobalt research events.", kind: .preference, provenance: "Fictional human calendar guidance")
        let inferredCalendarFact = PAMemory(registration: registration, text: "Perhaps Cobalt belongs in the personal calendar.", kind: .preference, explicit: false, provenance: "Fictional provisional interpretation", certainty: .inferred)
        guard model.assistant.memory.put(calendarFact), model.assistant.memory.put(inferredCalendarFact), model.assistant.memory.saveReviewPreference("Do not surface unrelated calendar newsletters.", registration: registration, about: "Fictional Review feedback") else { throw IntegrationError.verification }
        let calendarContext = model.calendarPurposeCapture(sources: [calendar], registration: registration)
        let calendarObject = try object(calendarContext.text)
        let humanGuidance = calendarObject["humanGuidance"] as? [[String: String]] ?? []
        let calendarRows = calendarObject["calendars"] as? [[String: Any]] ?? []
        checks["Primary context calendar routing reuses exact existing human guidance without creating a second purpose note"] = humanGuidance.count == 1 && humanGuidance.first?["text"] == calendarFact.text && calendarContext.referenceVersions["memory:" + calendarFact.id.uuidString] != nil && model.contextPages.pages(registration: registration).allSatisfy { $0.kind != .calendarPurpose }
        checks["Primary context provisional calendar interpretations never become human routing guidance"] = !model.calendarHumanGuidance(registration: registration).contains { $0.memoryID == inferredCalendarFact.id } && calendarContext.referenceVersions["memory:" + inferredCalendarFact.id.uuidString] == nil
        checks["Primary context calendar routing exposes current account and provider alongside exact source IDs"] = calendarRows.first?["account"] as? String == calendar.account && calendarRows.first?["providerID"] as? String == calendar.providerID && calendarContext.current()
        guard model.assistant.memory.forget(calendarFact.id) else { throw IntegrationError.verification }
        checks["Primary context forgotten calendar guidance revokes both live and persisted capture"] = !calendarContext.current() && !model.contextKnowledgeAvailable(registration: registration, versions: calendarContext.referenceVersions) && model.calendarHumanGuidance(registration: registration).isEmpty
        let currentConversation = model.captureContextPages(registration: registration, query: "Cobalt optics", includeTopics: false, everyday: true)
        let captures = Array(repeating: currentConversation.referenceVersions, count: 40) + [email.referenceVersions]
        let individuallyAvailable = captures.map { model.contextKnowledgeAvailable(registration: registration, versions: $0) }
        let buildsBefore = model.contextKnowledgeBuildCount
        var escapedAvailability: (([String: String]?) -> Bool)?
        let sharedAvailable = model.withContextPageAvailability(registration: registration, captures: captures) { available in
            escapedAvailability = available
            return captures.map { available($0) }
        }
        checks["Primary context shared advice validation preserves exact results with one projection per purpose"] = sharedAvailable == individuallyAvailable && sharedAvailable.allSatisfy { $0 } && model.contextKnowledgeBuildCount - buildsBefore == 2
        checks["Primary context a captured validation cannot be reused after its synchronous scope"] = escapedAvailability?(currentConversation.referenceVersions) == false && escapedAvailability?(nil) == true
        var staleVersions = currentConversation.referenceVersions
        staleVersions[reference.contextKey] = "fictional-earlier-version"
        var unknownPurpose = currentConversation.referenceVersions
        unknownPurpose["context-purpose:unknown-feature"] = "1"
        let mixedVersions = [staleVersions, currentConversation.referenceVersions, unknownPurpose]
        let mixedResult = model.withContextPageAvailability(registration: registration, captures: mixedVersions) { available in mixedVersions.map { available($0) } }
        checks["Primary context mixed historical versions cannot invalidate current receipts or admit unknown purposes"] = mixedResult == [false, true, false]
        guard model.assistant.memory.forget(fact.id) else { throw IntegrationError.verification }
        let afterForget = model.withContextPageAvailability(registration: registration, captures: [currentConversation.referenceVersions]) { $0(currentConversation.referenceVersions) }
        checks["Primary context a later advice pass rebuilds after supporting evidence is forgotten"] = !afterForget
        model.chatGPT.activeID = "fictional-other-context-owner"
        checks["Primary context source-free policies remain account scoped"] = !guidance.current() && !ordinary.current()
        checks["Primary context inspection and captures make no model or source calls"] = fixture.provider.calls == 0 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        return checks
    }

    private static func humanEvidenceChecks() throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for operation in ["forget", "correct"] {
            let fixture = try ContextPagesFixture()
            defer { fixture.clean() }
            let model = fixture.model, registration = fixture.registration, turnID = UUID()
            let oldWords = "Fictional cobalt workshop is my current research project."
            try fixture.human(oldWords, id: turnID)
            let fact = PAMemory(registration: registration, text: oldWords, kind: .context, provenance: "Fictional human fixture", sourceTurnID: turnID.uuidString,
                evidence: oldWords, organisation: .init(areas: [.studies], connections: []))
            guard model.assistant.memory.put(fact) else { throw IntegrationError.verification }
            let records = model.contextKnowledge(registration: registration)
            let refs = records.filter { $0.memoryID == fact.id || $0.reference.kind == "human" && $0.reference.key == turnID.uuidString }.map(\.reference)
            let page = try model.contextPages.save(.init(registration: registration, kind: .topic, key: "fictional-" + operation, owner: .generated,
                title: "Cobalt workshop", synopsis: "Fictional research context", markdown: oldWords, references: refs), expectedRevision: nil)
            let humanPage = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-human-" + operation, owner: .human,
                title: "Cobalt human context", markdown: oldWords, references: refs), expectedRevision: nil)
            let humanVersion = ContextPageReference(kind: "page", key: humanPage.id, revision: humanPage.revision.uuidString)
            let indirectPage = try model.contextPages.save(.init(registration: registration, kind: .topic, key: "fictional-indirect-" + operation, owner: .generated,
                title: "Cobalt indirect context", markdown: oldWords, references: [humanVersion]), expectedRevision: nil)
            let minimalVersions = [humanVersion.contextKey: humanVersion.revision]
            checks["Context pages \(operation) initially validates transitive human-page support"] = model.contextKnowledgeAvailable(registration: registration, versions: minimalVersions) && model.contextPageEligible(indirectPage, records: model.contextKnowledge(registration: registration))
            let captured = model.captureContextPages(registration: registration, query: "cobalt workshop", pageID: page.id)
            checks["Context pages \(operation) initially captures canonical fact and original human turn"] = captured.current() && refs.count == 2 && captured.referenceVersions["human:" + turnID.uuidString] != nil && captured.pageIDs == [page.id]
            var replacementID: UUID?
            if operation == "forget" {
                guard model.assistant.memory.forget(fact.id) else { throw IntegrationError.verification }
            } else {
                let replacementTurn = UUID(), words = "Fictional cobalt workshop is complete; my current research project is the amber laboratory."
                try fixture.human(words, id: replacementTurn)
                let replacement = PAMemory(registration: registration, text: words, kind: .context, provenance: "Fictional human correction", sourceTurnID: replacementTurn.uuidString,
                    evidence: words, organisation: .init(areas: [.studies], connections: []))
                guard model.assistant.memory.correct(fact.id, with: replacement) else { throw IntegrationError.verification }
                replacementID = replacement.id
            }
            let current = model.contextKnowledge(registration: registration)
            let fresh = model.captureContextPages(registration: registration, query: "cobalt workshop", pageID: page.id)
            checks["Context pages \(operation) suppresses the old human turn as well as its old fact"] = !current.contains { $0.reference.key == turnID.uuidString || $0.memoryID == fact.id }
            checks["Context pages \(operation) invalidates previously supplied generated prose"] = !captured.current() && !fresh.pageIDs.contains(page.id) && !model.contextKnowledgeAvailable(registration: registration, versions: captured.referenceVersions)
            checks["Context pages \(operation) invalidates transitive human-page receipts without copied source bodies"] = !model.contextKnowledgeAvailable(registration: registration, versions: minimalVersions) && !model.contextPageEligible(indirectPage, records: current)
            checks["Context pages \(operation) preserves saved page and immutable history"] = model.contextPages.page(id: page.id, registration: registration) == page && model.contextPages.history(id: page.id, registration: registration).count == 1
            if let replacementID {
                checks["Context pages correction keeps the current replacement available"] = current.contains { $0.memoryID == replacementID && $0.text.contains("amber laboratory") }
                checks["Context pages correction preserves original canonical lineage"] = model.assistant.memory.records.first(where: { $0.id == fact.id })?.supersededBy == replacementID
            }
            fixture.model.chatGPT.activeID = "fictional-other-account"
            checks["Context pages \(operation) cannot retrieve another account's facts or pages"] = model.contextKnowledge(registration: registration).isEmpty && model.captureContextPages(registration: registration, query: nil).text == "{}"
        }
        return checks
    }

    private static func pageReadChecks() async throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        // Escaping, Unicode and >12 KB exercise the final JSON byte bound as well as character offsets.
        let body = String(repeating: "ab\"\\🌱", count: 2500)
        let page = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-long-read", owner: .human,
            title: "Cobalt long read", markdown: body), expectedRevision: nil)
        let tools = PAToolSession(model: model, human: "Read the cobalt long read", humanContext: "Read the cobalt long read", topicID: nil,
            turnID: UUID(), evaluationMemory: model.assistant.memory, evaluationProjects: model.assistant.projects, inferenceModel: fixture.provider.selectedModel)
        var restored = "", offset = 0, bounds = true, offsets = true, chunks = 0, complete = false
        for index in 0..<16 {
            let call = PAFunctionCall(id: "fictional-page-chunk-\(index)", name: "read_context_page", namespace: "pa",
                arguments: ContextKnowledgeRules.json(["id": page.id, "query": NSNull(), "offset": String(offset)]))
            let text = try await tools.execute(call, valid: { true })
            bounds = bounds && text.utf8.count <= 32_000
            let payload = try object(text)
            guard let row = (payload["pages"] as? [[String: String]])?.first, let excerpt = row["markdown"], let next = row["nextOffset"] else { break }
            offsets = offsets && row["offset"] == String(offset) && row["totalCharacters"] == String(body.count)
            restored += excerpt; chunks += 1
            if next == "end" { complete = true; break }
            guard let number = Int(next), number > offset else { offsets = false; break }
            offset = number
        }
        var checks: [String: Bool] = [:]
        checks["Context pages real tool continuation reads every stored long-page character"] = body.utf8.count > 12_000 && complete && chunks > 1 && restored == body
        checks["Context pages real tool continuation uses exact increasing character offsets"] = offsets
        checks["Context pages every encoded continuation stays within final payload bytes"] = bounds
        checks["Context pages real tool records the exact human-page version"] = tools.consultedContextVersions["page:" + page.id] == page.revision.uuidString && tools.pageContextAvailable
        for index in 0..<38 {
            _ = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-directory-\(index)", owner: .human,
                title: "Cobalt note \(index)", synopsis: "Fictional context", markdown: String(repeating: "\"\\🌱", count: 600)), expectedRevision: nil)
        }
        for index in 0..<22 {
            guard model.assistant.memory.put(.init(registration: registration, text: "Cobalt pending fact \(index): " + String(repeating: "\"\\🌱", count: 300), kind: .context, provenance: "Fictional fixture")) else { throw IntegrationError.verification }
        }
        for feature in ContextFeature.allCases {
            _ = try model.contextPages.save(.init(registration: registration, kind: .instruction, key: feature.rawValue, owner: .human,
                title: feature.title, markdown: String(repeating: "\"\\🌱", count: 1700)), expectedRevision: nil)
        }
        let broad = model.captureContextPages(registration: registration, query: nil, everyday: true)
        let broadObject = try object(broad.text)
        let directory = broadObject["directory"] as? [[String: String]] ?? []
        checks["Context pages ordinary whole payload stays bounded with directory and pending changes"] = broad.text.utf8.count <= 20_000 && broadObject["unavailable"] == nil && !directory.isEmpty
        checks["Context pages directory reports stored pages omitted by its input bound"] = (broadObject["directoryCount"] as? Int ?? 0) > directory.count
        let policies = broadObject["featureInstructions"] as? [[String: String]] ?? []
        checks["Context pages large feature policies retain bounded orientation and explicit continuation"] = policies.count == 3 && policies.allSatisfy { $0["partial"] == "true" && $0["readMore"]?.hasPrefix("instructions:") == true } && !broad.pageIDs.isEmpty
        let visibleChanges = broadObject["workingChanges"] as? [[String: String]] ?? []
        let suppliedMemory = Set(visibleChanges.compactMap { $0["id"] })
        checks["Context pages omitted working rows do not retain hidden memory dependencies"] = broad.referenceVersions.keys.filter { $0.hasPrefix("memory:") }.allSatisfy { suppliedMemory.contains($0) }
        var edited = page; edited.markdown += "\nIndependent human edit"
        _ = try model.contextPages.save(edited, expectedRevision: page.revision)
        checks["Context pages actual read tool rejects later human-page edit"] = !tools.pageContextAvailable
        checks["Context pages read and directory operations make zero inference calls"] = fixture.provider.calls == 0 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        return checks
    }

    private static func instructionChecks() throws -> [String: Bool] {
        let fixture = try ContextPagesFixture()
        defer { fixture.clean() }
        let model = fixture.model, registration = fixture.registration
        var checks: [String: Bool] = [:]
        let prompt = model.briefings.writingPrompt(registration)
        let briefWords = "Prioritise fictional cobalt laboratory commitments. " + String(repeating: "\"\\🌱", count: 1800)
        try model.briefings.saveWritingPrompt(briefWords, expected: prompt, model: model)
        let brief = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:brief")
        let briefObject = try object(brief.text)
        checks["Context pages brief instructions carry exact bounded versioned text"] = brief.current() && brief.text.utf8.count <= 32_000 && (briefObject["instructions"] as? [String: String])?["nextOffset"] != "end" && brief.referenceVersions["instruction:brief"] != nil
        try model.briefings.saveWritingPrompt("Use the revised fictional cobalt brief preferences.", expected: model.briefings.writingPrompt(registration), model: model)
        checks["Context pages brief edit invalidates exact prior instruction capture"] = !brief.current() && !model.contextKnowledgeAvailable(registration: registration, versions: brief.referenceVersions)
        let policy = model.emailSummaries.policy(registration)
        guard model.emailSummaries.savePolicy("Only surface meaningful fictional cobalt changes. " + String(repeating: "\"\\🌱", count: 1700), registration: registration, expected: policy) else { throw IntegrationError.verification }
        for index in 0..<18 {
            guard model.assistant.memory.saveReviewPreference("Fictional cobalt feedback \(index): " + String(repeating: "\"\\🌱", count: 400), registration: registration, about: String(repeating: "f", count: 280)) else { throw IntegrationError.verification }
        }
        let review = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:review")
        let reviewObject = try object(review.text), feedback = reviewObject["feedback"] as? [[String: String]] ?? []
        checks["Context pages Review policy and feedback obey one final payload bound"] = review.current() && review.text.utf8.count <= 32_000 && reviewObject["unavailable"] == nil && !feedback.isEmpty && (reviewObject["feedbackCount"] as? Int) == 18
        checks["Context pages Review policy capture retains canonical feedback receipts"] = review.referenceVersions["instruction:review"] != nil && review.referenceVersions.keys.filter { $0.hasPrefix("memory:") }.count == feedback.count
        guard model.emailSummaries.savePolicy("Only surface meaningful revised fictional cobalt changes.", registration: registration, expected: model.emailSummaries.policy(registration)) else { throw IntegrationError.verification }
        checks["Context pages Review edit invalidates exact prior policy capture"] = !review.current() && !model.contextKnowledgeAvailable(registration: registration, versions: review.referenceVersions)
        checks["Context pages feature instructions share existing saved authorities"] = model.contextPages.pages(registration: registration).isEmpty
        let currentBrief = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:brief")
        let currentReview = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:review")
        model.chatGPT.activeID = "fictional-other-account"
        checks["Context pages feature instruction captures reject account changes"] = !currentBrief.current() && !currentReview.current() && model.captureContextPages(registration: registration, query: nil, pageID: "instructions:brief").text == "{}" && model.captureContextPages(registration: registration, query: nil, pageID: "instructions:review").text == "{}"
        model.chatGPT.activeID = registration

        model.contextCalendarAccess = { true }
        let calendars = (0..<80).map { SourceOption(id: "fictional-calendar-\($0)", title: "Calendar \($0)", account: "Fictional calendar account", writable: true, providerID: "fictional-provider-\($0)") }
        model.calendarData = .init(sources: calendars, events: [])
        var purposes: [String: ContextPage] = [:]
        for source in calendars {
            let page = try model.contextPages.save(.init(registration: registration, kind: .calendarPurpose, key: model.calendarPageKey(source), owner: .human,
                title: "Calendar purpose", markdown: "Fictional cobalt appointments only. " + String(repeating: "\"\\🌱", count: 650)), expectedRevision: nil)
            purposes[source.id] = page
        }
        let guide = model.captureContextPages(registration: registration, query: nil, pageID: "instructions:calendars")
        let guideObject = try object(guide.text), rows = guideObject["calendars"] as? [[String: Any]] ?? []
        checks["Context pages calendar guide bounds encoded purposes and reports omitted sources"] = guide.current() && guide.text.utf8.count <= 20_000 && !rows.isEmpty && (guideObject["omittedCount"] as? Int) == calendars.count - rows.count && rows.count < calendars.count && rows.allSatisfy { $0["purposeTruncated"] as? Bool == true }
        guard let firstID = rows.first?["id"] as? String, var purpose = purposes[firstID] else { throw IntegrationError.verification }
        purpose.markdown += "\nRevised human purpose"
        _ = try model.contextPages.save(purpose, expectedRevision: purpose.revision)
        checks["Context pages calendar purpose edit invalidates prior guide capture"] = !guide.current() && !model.contextKnowledgeAvailable(registration: registration, versions: guide.referenceVersions)
        let exact = model.calendarPurposeCapture(sources: [calendars[0]], registration: registration)
        var renamed = calendars[0]; renamed.account = "Renamed account label"; renamed.title = "Renamed calendar label"
        let renamedGuide = model.calendarPurposeCapture(sources: [renamed], registration: registration)
        let renamedRows = try object(renamedGuide.text)["calendars"] as? [[String: Any]]
        checks["Context pages calendar guide retains human writing after cosmetic labels change"] = model.calendarPageKey(renamed) == model.calendarPageKey(calendars[0]) && renamedRows?.first?["purpose"] as? String != "Not described"
        var changed = calendars[0]; changed.providerID = "different-fictional-provider"; changed.account = "Different fictional account"
        model.calendarData = .init(sources: [changed] + Array(calendars.dropFirst()), events: [])
        let retargeted = model.calendarPurposeCapture(sources: [changed], registration: registration)
        let retargetedRows = try object(retargeted.text)["calendars"] as? [[String: Any]]
        checks["Context pages calendar purpose cannot follow reused label or source ID across provider accounts"] = !exact.current() && retargetedRows?.first?["purpose"] as? String == "Not described"
        model.calendarData = .init(sources: calendars, events: [])
        let permitted = model.calendarPurposeCapture(sources: [calendars[0]], registration: registration)
        model.assistant.excludedCalendars.insert(calendars[0].id)
        let excludedRows = try object(model.calendarPurposeCapture(sources: [calendars[0]], registration: registration).text)["calendars"] as? [[String: Any]]
        checks["Context pages calendar exclusion revokes supplied guidance"] = !permitted.current() && excludedRows?.isEmpty == true
        model.assistant.excludedCalendars.remove(calendars[0].id)
        let owned = model.calendarPurposeCapture(sources: [calendars[0]], registration: registration)
        model.chatGPT.activeID = "fictional-other-account"
        checks["Context pages calendar guide rejects a changed connected account"] = !owned.current() && model.calendarPurposeCapture(sources: calendars, registration: registration).text == "{}"
        model.chatGPT.activeID = registration
        model.contextCalendarAccess = { false }
        checks["Context pages calendar permission withdrawal revokes guidance without OS reads"] = !owned.current() && model.calendarPurposeCapture(sources: calendars, registration: registration).text == "{}"
        checks["Context pages instruction fixtures make zero inference requests"] = fixture.provider.calls == 0 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
        return checks
    }

    private static func ownedMutationChecks() async throws -> [String: Bool] {
        var checks: [String: Bool] = [:]
        for kind in ["memory", "project"] {
            for independentEdit in [false, true] {
                let fixture = try ContextPagesFixture()
                defer { fixture.clean() }
                let model = fixture.model, registration = fixture.registration, sourceTurn = UUID()
                let words = "Fictional cobalt workshop has a human-approved research purpose."
                try fixture.human(words, id: sourceTurn)
                let fact = PAMemory(registration: registration, text: words, kind: .context, provenance: "Fictional human fixture", sourceTurnID: sourceTurn.uuidString,
                    evidence: words, organisation: .init(areas: [.projects], connections: []))
                guard model.assistant.memory.put(fact) else { throw IntegrationError.verification }
                var project: LifeItem?
                if kind == "project" {
                    project = try model.assistant.projects.save(.init(registration: registration, kind: .space, title: "Cobalt workshop"), expected: nil)
                }
                let knowledge = model.contextKnowledge(registration: registration)
                let support = knowledge.filter { record in
                    if let project { return record.reference.kind == "projectIdentity" && record.reference.key == project.id.uuidString }
                    return record.memoryID == fact.id || record.reference.kind == "human" && record.reference.key == sourceTurn.uuidString
                }.map(\.reference)
                let page = try model.contextPages.save(.init(registration: registration, kind: .note, key: "fictional-owned-purpose", owner: .human,
                    title: "Cobalt workshop purpose", markdown: words, references: support), expectedRevision: nil)
                let prompt = kind == "memory" ? "Forget my cobalt workshop memory and report the saved result." : "Delete the cobalt workshop project and report the saved result."
                let tools = ContextPagesMutationTools(model: model, memoryID: fact.id, projectID: project?.id)
                let args: [String: Any] = kind == "memory" ? ["operation": "forget", "id": fact.id.uuidString, "text": NSNull(), "authorization": prompt] : ["id": project!.id.uuidString, "keepChildren": false, "authorization": prompt]
                fixture.provider.responseCall = .init(id: "fictional-owned-" + kind, name: kind == "memory" ? "change_memory" : "delete_life_item", namespace: "pa", arguments: ContextKnowledgeRules.json(args))
                fixture.provider.holdFinal = true
                var runtime = model.assistantRuntime(), capturedReferences: [String: String] = [:]
                let capture = runtime.contextPages
                runtime.contextPages = { registration, query, topic, includeTopics, everyday in
                    let value = capture(registration, query, topic, includeTopics, everyday)
                    capturedReferences = value.referenceVersions
                    return value
                }
                runtime.tools = { _ in tools }
                runtime.sourceSnapshot = { nil }
                let whatsapp = WhatsAppSourceScope(registration: registration, linkedIdentity: "fictional-unused", revision: UUID())
                runtime.state = { .init(attentionPreferencesReadable: true, resolvedRequests: [], whatsappScope: whatsapp, weatherScope: "fictional-unused", weatherSupplied: false) }
                runtime.afterTurn = {}; runtime.started = { _ in }; runtime.working = { _ in }; runtime.finished = { _ in }
                let conversation = model.assistant.openPA()
                let started = model.assistant.send(runtime: runtime, topicID: nil, prompt: prompt)
                await waitUntil { fixture.provider.held != nil || !model.assistant.busy }
                let label = "Context pages owned \(kind) \(independentEdit ? "with later edit" : "without later edit")"
                let reachedFinal = fixture.provider.held != nil
                checks[label + " captures the exact human page and source human turn"] = capturedReferences["page:" + page.id] == page.revision.uuidString && capturedReferences["human:" + sourceTurn.uuidString] != nil
                checks[label + " reaches final inference after exactly one real local mutation"] = started && reachedFinal && tools.writes == 1
                let minimalPageVersion = ["page:" + page.id: page.revision.uuidString]
                checks[label + " validates transitive page support using only explicitly owned changes"] = reachedFinal && model.contextKnowledgeAvailable(registration: registration, versions: minimalPageVersion, ignoring: tools.adopted)
                var editedRevision: UUID?
                if independentEdit, reachedFinal {
                    var edited = page; edited.markdown = words + "\nThe human independently revised this purpose while the reply was being prepared."
                    editedRevision = try model.contextPages.save(edited, expectedRevision: page.revision).revision
                }
                fixture.provider.release()
                await waitUntil { !model.assistant.busy }
                let turn = conversation.flatMap { model.assistant.conversation($0)?.turns.last }
                let saved = kind == "memory" ? !model.assistant.memory.records.contains(where: { $0.id == fact.id }) : model.assistant.projects.items(registration, includeTopics: true).isEmpty
                checks[label + " preserves one verified mutation and its receipt"] = saved && tools.writes == 1 && tools.receipts.count == 1 && turn?.actionResult?.confirmedActions == 1
                if independentEdit {
                    checks[label + " refuses final prose after independent human revision"] = reachedFinal && !model.assistant.busy && model.assistant.error != nil && turn?.content.contains(ContextPagesInference.finalText) == false && turn?.actionResult?.phase != "completed"
                    checks[label + " retains the independently saved page version"] = editedRevision != nil && model.contextPages.page(id: page.id, registration: registration)?.revision == editedRevision && !model.contextKnowledgeAvailable(registration: registration, versions: minimalPageVersion, ignoring: tools.adopted)
                } else {
                    checks[label + " completes its authorised turn despite retiring its own context"] = reachedFinal && !model.assistant.busy && model.assistant.error == nil && turn?.content.contains(ContextPagesInference.finalText) == true && turn?.actionResult?.phase == "completed"
                }
                checks[label + " uses completed fictional transport without subscription requests"] = fixture.provider.calls == 2 && fixture.sources.reads == 0 && model.aiUsage.state.records.isEmpty
                if !reachedFinal || (independentEdit == (model.assistant.error == nil)) {
                    let detail = label + ": calls=\(fixture.provider.calls), writes=\(tools.writes), phase=\(turn?.actionResult?.phase ?? "missing"), error=\(model.assistant.error ?? "none")\n"
                    FileHandle.standardError.write(Data(detail.utf8))
                }
                if model.assistant.busy { model.assistant.cancel(); await waitUntil { !model.assistant.busy } }
            }
        }
        return checks
    }

    private static func object(_ text: String) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw IntegrationError.verification }
        return value
    }
    private static func waitUntil(_ finished: @MainActor () -> Bool) async {
        for _ in 0..<40_000 { if finished() { return }; await Task.yield() }
    }
}

@MainActor private final class ContextPagesFixture {
    let model: DashboardModel
    let sources: ContextPagesNativeFixture
    let provider = ContextPagesInference()
    let settings: UserDefaults
    let suite: String
    let images: URL
    var registration: String { provider.activeID }
    init() throws {
        guard ProcessInfo.processInfo.arguments.contains("--validate-advice-context") else { throw IntegrationError.verification }
        let sourcePort = ContextPagesNativeFixture(); sources = sourcePort
        model = DashboardModel(nativeSources: sourcePort)
        guard let container = model.container else { throw IntegrationError.verification }
        suite = "3PO.context-pages-fixture." + UUID().uuidString
        guard let settings = UserDefaults(suiteName: suite) else { throw IntegrationError.verification }
        self.settings = settings
        images = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        settings.set(true, forKey: "assistantContextEnabled"); settings.set(true, forKey: "paMemoryEnabled")
        model.assistant = AssistantService(connection: provider, container: container, settings: settings, imageDirectory: images)
        model.chatGPT.activeID = provider.activeID
        model.contextCalendarAccess = { false }
    }
    func clean() { provider.release(); settings.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: images) }
    func human(_ words: String, id: UUID) throws {
        guard model.assistant.openReview(key: "fictional-context-human-" + id.uuidString, title: "Fictional context", sourceKind: "fictional", accountID: nil, messageID: nil, identity: nil, chatID: nil,
            seeds: [.init(id: id, role: "user", content: words, completed: true)]) != nil else { throw IntegrationError.verification }
    }
}

@MainActor private final class ContextPagesNativeFixture: NativeSourceReading {
    private(set) var reads = 0
    func calendar(from: Date, to: Date) async throws -> CalendarSnapshot { reads += 1; return .init(sources: [], events: []) }
    func reminders() async throws -> ReminderSnapshot { reads += 1; return .init(sources: [], reminders: []) }
    func completedReminders(excluded: Set<String>, now: Date) async throws -> [CompletedReminder] { reads += 1; return [] }
}

@MainActor private final class ContextPagesInference: PAInferenceConnection {
    static let finalText = "Fictional owned context change completed and verified."
    var activeID = "fictional-context-pages-owner", selectedModel = "fictional-model"
    var busy = false, usagePaused = false, inferenceVerified = true, hasSession = true
    var calls = 0, responseCall: PAFunctionCall?, holdFinal = false
    var held: CheckedContinuation<Void, Never>?
    func streamResponse(input: [[String: String]], instructions: String, model: String?, effort: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> String {
        throw ActionFailure.message("Context-page fixture requires completed fictional transport.")
    }
    func toolResponse(input: [[String: Any]], instructions: String, tools: [[String: Any]], model: String, purpose: AIRequestPurpose, onDelta: @escaping (String) -> Void) async throws -> PAResponse {
        calls += 1
        if calls == 1, let responseCall {
            return .init(text: "", output: [["type": "function_call", "call_id": responseCall.id, "name": responseCall.name, "arguments": responseCall.arguments]], calls: [responseCall])
        }
        if holdFinal { await withCheckedContinuation { held = $0 } }
        return .init(text: Self.finalText, output: [], calls: [])
    }
    func release() { let continuation = held; held = nil; continuation?.resume() }
}

@MainActor private final class ContextPagesMutationCursor: AssistantMailCursor {
    var status = "Fictional fixture has no Mail search", results: [MailMessage] = [], hasMore = false, hasUnavailable = false
}

/// Only the final local action boundary is replaced. Actual stores mutate and the
/// real assistant must decide whether its captured context can be adopted.
@MainActor private final class ContextPagesMutationTools: AssistantToolSession {
    let model: DashboardModel
    let memoryID: UUID
    let projectID: UUID?
    let calendar = CalendarSnapshot(sources: [], events: []), reminders = ReminderSnapshot(sources: [], reminders: [])
    var itemDetails: [String: NativeEditDetails] = [:]
    var consultedMemory: Set<UUID>
    var consultedWorkspace: Set<UUID>
    var receipts: [String] = [], memoryNotes: [String] = []
    var clarification: (String, [String])?
    var mailCursor: any AssistantMailCursor = ContextPagesMutationCursor()
    private(set) var writes = 0, adopted = Set<String>()
    func adoptContextChanges(_ keys: Set<String>) { adopted.formUnion(keys) }
    init(model: DashboardModel, memoryID: UUID, projectID: UUID?) {
        self.model = model; self.memoryID = memoryID; self.projectID = projectID
        consultedMemory = [memoryID]; consultedWorkspace = projectID.map { [$0] } ?? []
    }
    func execute(_ call: PAFunctionCall, valid: @escaping NativeWriteValidity) async throws -> String {
        guard valid(), writes == 0 else { throw IntegrationError.verification }
        if let projectID {
            guard call.name == "delete_life_item" else { throw IntegrationError.verification }
            try model.assistant.projects.trash(projectID, registration: model.chatGPT.activeID, keepChildren: false, expectedRevision: model.assistant.projects.revision)
        } else {
            guard call.name == "change_memory", model.assistant.memory.forget(memoryID) else { throw IntegrationError.verification }
        }
        writes += 1
        receipts.append("Fictional \(projectID == nil ? "memory forgotten" : "project moved to Recently deleted") and verified")
        return ContextKnowledgeRules.json(["verified": true, "id": (projectID ?? memoryID).uuidString])
    }
}
#endif
