import SwiftUI
import EventKit

/// Local inspection and explicit human edits only. Opening this view starts no source or AI work.
struct ContextPagesView: View {
    @Bindable var model: DashboardModel
    private let registration: String
    private let storage: ObjectIdentifier?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expandedSections = Set(ContextSidebarSection.allCases)
    @State private var expandedProjects = Set<UUID>()
    @State private var selection: ContextPageDestination?
    @State private var editor: ContextPageEditRequest?
    @State private var history: ContextPageHistoryRequest?
    @State private var instructions: ContextPageInstructionRequest?
    @State private var choosingProject = false
    @State private var nextEditor: ContextPageEditRequest?
    @State private var forgetting: ContextPage?
    @State private var error: String?
    @State private var showingSupportingFacts = false
    private let initialProjectID: UUID?

    init(model: DashboardModel, registration: String? = nil, projectID: UUID? = nil, feature: ContextFeature? = nil, pageID: String? = nil) {
        self.model = model
        let registration = registration ?? model.chatGPT.activeID
        self.registration = registration
        storage = model.container.map(ObjectIdentifier.init)
        let page = pageID.flatMap { id in model.contextPages.pages(registration: registration).first { $0.id == id } }
        let project = projectID ?? (page?.kind == .project ? page.flatMap { UUID(uuidString: $0.key) } : nil)
        initialProjectID = project
        var destination: ContextPageDestination = feature.map { .feature($0) } ?? project.map { .project($0) } ?? .overview
        if let pageID {
            if let route = ContextInstructionRoute.all.first(where: { $0.id == pageID }) {
                destination = switch route { case .feature(let feature): .feature(feature); case .brief: .brief; case .review: .review; case .calendars: .calendars }
            } else if pageID.hasPrefix("area:"), let topic = ContextTopicRoute.named(String(pageID.dropFirst(5))) {
                let current = model.contextPages.pages(registration: registration).first { $0.kind == .topic && $0.key == topic.key }
                destination = current.map { .page($0.id) } ?? .area(topic.key)
            } else if project == nil { destination = .page(pageID) }
        }
        _selection = State(initialValue: destination)
    }
    private var owned: Bool { ContextPagesAccess.owned(model, registration: registration, storage: storage) }
    /// A direct project link can inspect its exact earlier topic, without opening every old topic.
    private var contextTopic: UUID? {
        guard let initialProjectID else { return nil }
        return model.assistant.projects.items(registration, includeTopics: true).first { $0.id == initialProjectID }?.conversationID
    }
    private var projects: [LifeItem] {
        model.assistant.projects.items(registration, topic: contextTopic, includeTopics: false).filter { !$0.kind.isWork }
    }
    var body: some View {
        let records = model.contextKnowledge(registration: registration, topic: contextTopic, includeTopics: false, purpose: .inspection)
        let pages = model.contextPages.pages(registration: registration)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Context").font(.title2.weight(.semibold)).accessibilityIdentifier("context-pages-title")
                Spacer()
                Button("Supporting facts and controls…") { showingSupportingFacts = true }
                    .controlSize(.small).disabled(!owned || registration.isEmpty)
                Menu("Add context") {
                    Button("Everyday context…") { openOverview() }
                    Button("Note…") { editor = .note(registration: registration) }
                    Button("Project purpose…") { choosingProject = true }.disabled(projects.isEmpty)
                }.disabled(!owned || registration.isEmpty || !model.contextPages.canSave)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Your PA’s readable context, recent changes and instructions. Supporting facts keep their original evidence and history.")
                .font(.callout).foregroundStyle(.secondary)
            if owned && !registration.isEmpty {
                HSplitView {
                    pageList(pages: pages, records: records)
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
                    ScrollView {
                        detail(pages: pages, records: records)
                            .id(selection)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }.frame(minWidth: 450)
                }
                ContextMaintenanceStatusView(model: model, registration: registration, pages: pages, records: records, projects: projects)
            } else {
                ContentUnavailableView("Connect your account", systemImage: "person.crop.circle", description: Text("Context pages stay with the account that owns them. Reopen this view after connecting your account."))
            }
            if let message = error ?? model.contextPages.error {
                Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
        }.padding(22).frame(width: 980, height: 740)
            .sheet(item: $editor) { ContextPageHumanEditor(model: model, request: $0) }
            .sheet(item: $history) { ContextPageHistoryView(model: model, request: $0) }
            .sheet(isPresented: $showingSupportingFacts) {
                PAMemoryView(memory: model.assistant.memory, registration: registration, conversationID: contextTopic,
                    topicTitle: model.assistant.conversation(contextTopic)?.title, learning: model.memoryLearning,
                    assistant: model.assistant, checkContext: { model.memoryLearning.check(model, manual: true) },
                    organisation: model.lifeOrganisation,
                    organiseContext: { model.lifeOrganisation.check(model, manual: true, topic: contextTopic) }, model: model)
            }
            .sheet(item: $instructions) { request in
                if request.registration == model.chatGPT.activeID {
                    if let capture = request.brief { BriefPromptEditor(model: model, briefings: model.briefings, capture: capture) }
                    else { ReviewPolicyView(model: model) }
                } else { Text("The account changed. Reopen the instructions.").padding(24) }
            }
            .sheet(isPresented: $choosingProject, onDismiss: {
                if let nextEditor { editor = nextEditor; self.nextEditor = nil }
            }) {
                ContextProjectPurposePicker(model: model, registration: registration, topic: contextTopic) { item in
                    nextEditor = try ContextPageEditRequest.project(item, model: model, registration: registration)
                    choosingProject = false
                }
            }
            .alert("Forget this context page?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
                Button("Cancel", role: .cancel) { forgetting = nil }
                Button("Forget page", role: .destructive) { forget() }
            } message: { Text("This removes the human page and its saved history. Its project, source records and other memories stay saved.") }
            .onChange(of: model.chatGPT.activeID) { editor = nil; history = nil; instructions = nil; showingSupportingFacts = false; choosingProject = false; nextEditor = nil; forgetting = nil; dismiss() }
    }

    private func pageList(pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        let available = Set(pages.filter { ContextPagesAccess.eligible($0, model: model, registration: registration, records: records) }.map(\.id))
        let descriptions = projectDescriptions(pages: pages, available: available)
        let hierarchy = ContextSidebarProjectTree(items: projects)
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let matching = searching ? Set(projects.filter { matches(ContextPagesAccess.projectLabel($0, all: projects) + " " + descriptions[$0.id, default: ""]) }.map(\.id)) : nil
        let rows = hierarchy.rows(matching: matching, expanded: expandedProjects)
        let topics = pages.filter { $0.kind == .topic && matches($0, available: available.contains($0.id)) }
        let notes = pages.filter { $0.kind == .note && matches($0, available: available.contains($0.id)) }
        return VStack(alignment: .leading, spacing: 10) {
            TextField("Search context pages", text: $query).textFieldStyle(.roundedBorder)
            List(selection: $selection) {
                Section("Context", isExpanded: sectionExpanded(.context, searching: searching)) {
                    if matches("3PO guide information index where to look") {
                        sidebarShortcut("3PO guide", symbol: "map", description: "Where to find information and instructions").tag(ContextPageDestination.guide)
                    }
                    if matches("Overview everyday context priorities") {
                        sidebarShortcut("Overview", symbol: "doc.text", description: "Everyday context and priorities").tag(ContextPageDestination.overview)
                    }
                    if matches("Working changes recent updates") {
                        sidebarShortcut("Working changes", symbol: "clock.arrow.circlepath", description: "New context since the last update").tag(ContextPageDestination.working)
                    }
                }
                Section("Projects", isExpanded: sectionExpanded(.projects, searching: searching)) {
                    ForEach(rows) { row in
                        projectRow(row, description: descriptions[row.id, default: "Awaiting first context page"], searching: searching)
                            .tag(ContextPageDestination.project(row.id))
                    }
                    if rows.isEmpty { Text(searching ? "No matching projects" : "No project spaces yet").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Topics", isExpanded: sectionExpanded(.topics, searching: searching)) {
                    ForEach(ContextTopicRoute.all) { route in
                        if !topics.contains(where: { $0.key == route.key }) && matches(route.title) {
                            sidebarShortcut(route.title, symbol: "doc.text", description: route.about).tag(ContextPageDestination.area(route.key))
                        }
                    }
                    ForEach(topics) { page in pageRow(page, available: available.contains(page.id)).tag(ContextPageDestination.page(page.id)) }
                    if topics.isEmpty { Text(searching ? "No matching topics" : "Awaiting maintained topic pages").font(.caption).foregroundStyle(.secondary) }
                }
                if !notes.isEmpty {
                    Section("Your notes", isExpanded: sectionExpanded(.notes, searching: searching)) {
                        ForEach(notes) { page in pageRow(page, available: available.contains(page.id)).tag(ContextPageDestination.page(page.id)) }
                    }
                }
                Section("Instructions", isExpanded: sectionExpanded(.instructions, searching: searching)) {
                    ForEach(ContextInstructionRoute.all) { route in
                        if matches(route.title) { Label(route.title, systemImage: route.symbol).tag(instructionDestination(route)) }
                    }
                }
            }.listStyle(.sidebar)
                .onAppear {
                    if let initialProjectID { expandedProjects.formUnion(hierarchy.ancestors(of: initialProjectID)) }
                }
        }
    }
    private func sectionExpanded(_ section: ContextSidebarSection, searching: Bool) -> Binding<Bool> {
        Binding(get: { searching || expandedSections.contains(section) }, set: { value in
            guard !searching else { return }
            if value { expandedSections.insert(section) } else { expandedSections.remove(section) }
        })
    }
    private func sidebarShortcut(_ title: String, symbol: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol).lineLimit(1)
            Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.vertical, 3)
    }
    private func projectRow(_ row: ContextSidebarProjectTree.Row, description: String, searching: Bool) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if row.hasChildren {
                Button {
                    if expandedProjects.contains(row.id) { expandedProjects.remove(row.id) } else { expandedProjects.insert(row.id) }
                } label: {
                    Image(systemName: row.expanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 16, height: 20)
                        .contentShape(Rectangle())
                }.buttonStyle(.borderless).disabled(searching)
                    .accessibilityLabel((row.expanded ? "Collapse " : "Expand ") + row.item.title)
                    .help(searching ? "Matching project paths stay open during search" : row.expanded ? "Hide nested spaces" : "Show nested spaces")
            } else { Color.clear.frame(width: 16, height: 20).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 3) {
                Label(row.item.title, systemImage: row.item.displaySymbol).lineLimit(1)
                Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.leading, CGFloat(min(row.depth, 8)) * 12).padding(.vertical, 3)
            .contentShape(Rectangle())
            .help(ContextPagesAccess.projectLabel(row.item, all: projects) + "\n" + description)
    }
    private func projectDescriptions(pages: [ContextPage], available: Set<String>) -> [UUID: String] {
        let byID = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary(projects.map { item in
            let purposeID = ContextPage.stableID(registration: registration, kind: .note, key: "project-purpose:" + item.id.uuidString)
            if let purpose = byID[purposeID], purpose.owner == .human, available.contains(purpose.id),
               let description = ContextSidebarText.summary(purpose.markdown) { return (item.id, description) }
            let id = ContextPage.stableID(registration: registration, kind: .project, key: item.id.uuidString)
            if let page = byID[id] {
                guard available.contains(id) else { return (item.id, "Supporting context unavailable") }
                return (item.id, ContextSidebarText.summary(page.synopsis) ?? ContextSidebarText.summary(page.markdown) ?? "Saved context page")
            }
            return (item.id, model.contextPages.identityStatus(id: id, registration: registration) == .preserved ? "Saved page needs a compatible version" : "Awaiting first context page")
        }, uniquingKeysWith: { first, _ in first })
    }
    private func pageRow(_ page: ContextPage, available: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(available ? page.title : ContextPagesAccess.kindTitle(page.kind), systemImage: page.owner == .human ? "doc.text" : "sparkles").lineLimit(1)
            Text(available ? (ContextSidebarText.summary(page.synopsis) ?? ContextSidebarText.summary(page.markdown) ?? (page.owner == .human ? "Written by you" : "Maintained by 3PO")) : "Supporting context unavailable")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.vertical, 3)
    }
    private func matches(_ text: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.localizedStandardContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private func matches(_ page: ContextPage, available: Bool) -> Bool {
        guard available else { return matches(ContextPagesAccess.kindTitle(page.kind)) }
        return matches(page.title + " " + page.synopsis + " " + page.markdown)
    }
    @ViewBuilder private func detail(pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        switch selection {
        case .guide:
            navigationGuide(pages: pages, records: records)
        case .area(let key):
            VStack(alignment: .leading, spacing: 18) {
                Text(ContextTopicRoute.named(key)?.title ?? "Topic context").font(.title2.weight(.semibold))
                Text("Useful factual context will be maintained when relevant information is available. You can set guidance for this area now.").foregroundStyle(.secondary)
                scopedInstructions(.topic(key), records: records)
            }
        case .overview:
            overview(pages: pages, records: records)
        case .working:
            ContextWorkingChangesView(model: model, registration: registration, topic: contextTopic, records: records)
        case .feature(let feature):
            featureInstructions(feature, pages: pages, records: records)
        case .page(let id):
            if let page = pages.first(where: { $0.id == id }) {
                pageDetail(page, records: records)
                if page.kind == .topic { scopedInstructions(.topic(page.key), records: records) }
            }
            else { ContentUnavailableView("Page unavailable", systemImage: "doc.text", description: Text("The page may have changed or been forgotten.")) }
        case .project(let id):
            if let item = projects.first(where: { $0.id == id }) {
                let pageID = ContextPage.stableID(registration: registration, kind: .project, key: item.id.uuidString)
                spaceDescription(item, records: records)
                projectContext(item, pages: pages, records: records)
                scopedInstructions(.space(item.id), records: records)
                spaceChildren(item, records: records)
                if let page = pages.first(where: { $0.id == pageID }) {
                    DisclosureGroup("Detailed maintained context") { pageDetail(page, records: records).padding(.top, 12) }.padding(.top, 16)
                }
                else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.title).font(.title2.weight(.semibold))
                        Label("Awaiting first maintained page", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                        Text("A heartbeat can gather relevant context for this existing project. Opening this page does not start analysis.").foregroundStyle(.secondary)
                        if !item.searchableNotes.isEmpty { Text("Project notes").font(.headline); ContextMarkdownBody(markdown: item.searchableNotes) }
                    }
                }
            } else { ContentUnavailableView("Project unavailable", systemImage: "folder", description: Text("This folder is no longer available in the current account.")) }
        case .brief:
            VStack(alignment: .leading, spacing: 16) {
                Text("Brief instructions").font(.title2.weight(.semibold))
                Text("Choose the focus and style of future briefs. Current-time, evidence and approval rules stay built in.").foregroundStyle(.secondary)
                if model.briefings.writingPromptReadable {
                    Button("Edit brief instructions…") { instructions = .init(registration: registration, brief: model.briefings.writingPrompt(registration)) }
                    ContextMarkdownBody(markdown: model.briefings.writingPrompt(registration).text)
                } else {
                    Label("Saved brief instructions could not be read. Original data is preserved; no default has replaced your writing.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        case .review:
            VStack(alignment: .leading, spacing: 16) {
                Text("Review guidance").font(.title2.weight(.semibold))
                Text("Your Review policy and feedback guide what deserves attention. They keep their existing controls and history.").foregroundStyle(.secondary)
                if model.emailSummaries.reviewPolicies.readable {
                    Button("Open Review guidance…") { instructions = .init(registration: registration) }
                    ContextMarkdownBody(markdown: model.emailSummaries.policy(registration).text)
                } else {
                    Label(model.emailSummaries.reviewPolicies.error ?? "Saved Review guidance could not be read. Original data is preserved.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        case .calendars: calendarGuide
        case nil:
            ContentUnavailableView("Your context, in readable pages", systemImage: "doc.text.magnifyingglass", description: Text("Select a page, describe a project, or add your everyday context. Relevant working changes remain available between heartbeats."))
        }
    }
    private func navigationGuide(pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        let ids = Set(projects.map(\.id))
        let roots = projects.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
        return VStack(alignment: .leading, spacing: 18) {
            Text("3PO guide").font(.title2.weight(.semibold))
            Text("3PO starts ordinary chats with a compact guide to your information, then opens relevant pages and tools. This map covers your spaces, topics and instructions; viewing it makes no AI request.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("Where to look").font(.headline)
                Text("Projects and topics explain background and purpose. Calendar and Reminders provide current schedules and tasks. Feature instructions describe how you want help. Working changes provide relevant information received since the last consolidation.")
                Text("Spaces inherit context and guidance from their parents. More specific guidance applies inside that subspace. Your own description takes priority over the maintained summary.").font(.callout).foregroundStyle(.secondary)
                Button("Edit assistant instructions…") { expandedSections.insert(.instructions); selection = .feature(.assistant) }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text("Your spaces").font(.headline)
            spaceTable(roots, records: records)
            Text("Your topics").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow { Text("Topic").font(.caption.weight(.semibold)); Text("What to look here for").font(.caption.weight(.semibold)) }
                ForEach(ContextTopicRoute.all) { route in
                    GridRow(alignment: .top) {
                        Button(route.title) {
                            expandedSections.insert(.topics)
                            // Preserve the saved navigation identity even when its support is
                            // unavailable; pageDetail displays the current withheld state.
                            let page = pages.first { $0.kind == .topic && $0.key == route.key }
                            selection = page.map { .page($0.id) } ?? .area(route.key)
                        }.buttonStyle(.link)
                        Text(route.about).font(.callout)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("Your instructions").font(.headline)
            Text("Open the relevant guidance for how 3PO should help. Instructions for a particular space or topic are inside its page. Instructions stay with their existing controls and do not grant access or approve actions.").font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                GridRow { Text("Instructions").font(.caption.weight(.semibold)); Text("When to use them").font(.caption.weight(.semibold)) }
                ForEach(ContextInstructionRoute.all) { route in
                    GridRow(alignment: .top) {
                        Button(route.title) { expandedSections.insert(.instructions); selection = instructionDestination(route) }.buttonStyle(.link)
                        Text(route.about).font(.callout)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("3PO keeps this guide small and opens detailed pages when they are useful.").font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("context-navigation-guide")
    }
    private func instructionDestination(_ route: ContextInstructionRoute) -> ContextPageDestination {
        switch route { case .feature(let feature): .feature(feature); case .brief: .brief; case .review: .review; case .calendars: .calendars }
    }
    private func spaceDescription(_ item: LifeItem, records: [ContextKnowledgeRecord]) -> some View {
        let row = model.contextSpaceDescriptions(registration: registration, items: [item], records: records).first
        let path = ContextHierarchyRules.ancestors(of: item.id, items: projects).map(\.title)
        return VStack(alignment: .leading, spacing: 8) {
            if !path.isEmpty { Text(path.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary) }
            Text(item.title).font(.title2.weight(.semibold))
            Text(row?.text.isEmpty == false ? row!.text : "No description yet. A heartbeat will review useful context for this space.").font(.callout)
            Text(row?.human == true ? "Description written by you" : "Description maintained by 3PO").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func spaceChildren(_ item: LifeItem, records: [ContextKnowledgeRecord]) -> some View {
        let children = projects.filter { $0.parentID == item.id }
        return VStack(alignment: .leading, spacing: 10) {
            if !children.isEmpty { Text("Subspaces").font(.headline); spaceTable(children, records: records) }
        }.padding(.top, 18)
    }
    private func spaceTable(_ items: [LifeItem], records: [ContextKnowledgeRecord]) -> some View {
        let rows = model.contextSpaceDescriptions(registration: registration, items: items, records: records)
        return Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow { Text("Space").font(.caption.weight(.semibold)); Text("Description").font(.caption.weight(.semibold)) }
            ForEach(rows) { row in
                GridRow(alignment: .top) {
                    Button(row.title) { selection = .project(row.id); expandedSections.insert(.projects); expandedProjects.formUnion(ContextSidebarProjectTree(items: projects).ancestors(of: row.id)) }.buttonStyle(.link)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.text.isEmpty ? "Not described yet" : row.text).font(.callout)
                        Text(row.human ? "Written by you" : "Maintained by 3PO").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func scopedInstructions(_ scope: ContextInstructionScope, records: [ContextKnowledgeRecord]) -> some View {
        let page = model.contextScopedInstruction(scope, registration: registration, records: records)
        let title: String = switch scope { case .space: "Instructions for this space"; case .topic: "Instructions for this area" }
        let inherited = model.contextGuidance(scopes: [scope], registration: registration, items: projects, records: records).rows.filter { $0["scope"] != scope.key }
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.headline); Spacer()
                    Button(page == nil ? "Add instructions…" : "Edit instructions…") {
                        do { editor = try .scoped(scope, model: model, registration: registration, records: records) }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!model.contextPages.canSave || ContextInstructionScope(key: scope.key) != scope)
                    if let page { Button("History…") { history = .init(page: page) } }
                }
                if let page { ContextMarkdownBody(markdown: page.markdown) }
                else { Text("Describe how you want 3PO to help here. Your instructions are kept separate from the factual description and are not rewritten by a heartbeat.").font(.callout).foregroundStyle(.secondary) }
                if !inherited.isEmpty {
                    DisclosureGroup("Inherited from parent spaces") {
                        ForEach(Array(inherited.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 4) { Text(row["title"] ?? "Parent instructions").font(.caption.weight(.semibold)); ContextMarkdownBody(markdown: row["markdown"] ?? "") }.padding(.top, 8)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.top, 16)
    }
    private func overview(pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        let overviews = pages.filter { $0.kind == .overview }
        return VStack(alignment: .leading, spacing: 20) {
            if overviews.isEmpty {
                Text("Overview").font(.title2.weight(.semibold))
                ContentUnavailableView("Your first overview is awaiting maintenance", systemImage: "doc.text.magnifyingglass",
                    description: Text("A heartbeat can turn useful permitted context into readable pages. Working changes are available while pages are waiting. Opening Context does not start analysis."))
                Button("Add everyday context…") { openOverview() }.disabled(!model.contextPages.canSave)
            } else {
                ForEach(overviews) { page in
                    pageDetail(page, records: records)
                    if page.id != overviews.last?.id { Divider() }
                }
            }
        }
    }
    private func featureInstructions(_ feature: ContextFeature, pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        let id = ContextPage.stableID(registration: registration, kind: .instruction, key: feature.rawValue)
        let page = pages.first { $0.id == id }
        let available = model.contextPages.identityStatus(id: id, registration: registration) != .preserved && (page.map { ContextPagesAccess.eligible($0, model: model, registration: registration, records: records) } ?? true)
        let currentText = model.featureInstruction(feature, registration: registration).text
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(feature.title).font(.title2.weight(.semibold))
                Spacer()
                if let page { Button("History…") { history = .init(page: page) } }
            }
            Text("Your guidance for future assistance. It does not grant source access or approve actions.").font(.callout).foregroundStyle(.secondary)
            if model.contextPages.isReadable && available {
                Text(page == nil ? (currentText == feature.defaultText ? "3PO default" : "Your existing guidance") : "Written by you").font(.caption).foregroundStyle(.secondary)
                ContextMarkdownBody(markdown: currentText)
                HStack {
                    Button("Edit instructions…") { editor = .feature(feature, page: page, registration: registration, currentText: currentText) }
                    Button("Use default…") { editor = .feature(feature, page: page, registration: registration, useDefault: true) }
                }.disabled(!model.contextPages.canSave)
            } else {
                Label("Saved instructions are unavailable. Their original text is preserved.", systemImage: "lock.doc").foregroundStyle(.secondary)
            }
        }
    }
    private func pageDetail(_ page: ContextPage, records: [ContextKnowledgeRecord]) -> some View {
        let available = ContextPagesAccess.eligible(page, model: model, registration: registration, records: records)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(available ? page.title : ContextPagesAccess.kindTitle(page.kind)).font(.title2.weight(.semibold))
                Spacer()
                Button("History…") { history = .init(page: page) }
            }
            Text((page.owner == .human ? "Written by you" : "Maintained by 3PO") + " · Updated " + page.updated.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
            if available {
                if !page.synopsis.isEmpty { Text(page.synopsis).font(.callout).foregroundStyle(.secondary) }
                ContextMarkdownBody(markdown: page.markdown)
                ContextPageSupportingContext(page: page, records: records).id(page.id)
            } else {
                Label("This saved text is withheld because its supporting context changed, memory use is paused, or access is no longer available. A later heartbeat can maintain the page using current permitted records.", systemImage: "lock.doc")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if page.owner == .human {
                    Button("Edit your page…") { editor = .existing(page) }.disabled(!available || !model.contextPages.canSave)
                    Button("Forget…", role: .destructive) { forgetting = page }.disabled(!model.contextPages.canSave)
                } else {
                    Button("Add context…") { editor = .note(registration: registration) }.disabled(!model.contextPages.canSave)
                }
            }
            if page.owner == .generated { Text("This is an automatically maintained summary. Add your own context in a separate note; your words will remain distinct from source interpretations.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func projectContext(_ item: LifeItem, pages: [ContextPage], records: [ContextKnowledgeRecord]) -> some View {
        let key = "project-purpose:" + item.id.uuidString
        let note = pages.first { $0.kind == .note && $0.key == key && $0.owner == .human }
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your description and context").font(.headline)
                    Spacer()
                    Button(note == nil ? "Write your description…" : "Edit your description…") {
                        do { editor = try .project(item, model: model, registration: registration) }
                        catch { self.error = error.localizedDescription }
                    }.disabled(!model.contextPages.canSave || (note.map { !ContextPagesAccess.eligible($0, model: model, registration: registration, records: records) } ?? false))
                }
                if let note, ContextPagesAccess.eligible(note, model: model, registration: registration, records: records) { ContextMarkdownBody(markdown: note.markdown) }
                else { Text(note == nil ? "Explain what this folder is for and what matters about it. Only what you type becomes your context." : "The saved note's project identity is unavailable. Its text remains saved.").font(.callout).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.top, 20)
    }
    private var calendarGuide: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calendar guide").font(.title2.weight(.semibold))
            Text("Describe what belongs in each calendar. Your words help choose a destination for a requested event; they do not create events or grant source access.").foregroundStyle(.secondary)
            if !ContextPagesAccess.calendarAccess(model) {
                Label("Calendar source context or Calendar access is off. Saved purpose notes stay preserved.", systemImage: "lock").foregroundStyle(.secondary)
            } else if model.calendarData.sources.isEmpty {
                Text("No calendar identities are cached yet. Refresh sources from the dashboard, then return here. Opening this guide does not read Calendar.").foregroundStyle(.secondary)
            } else {
                let sources = ContextPagesAccess.calendars(model)
                let guidance = model.calendarHumanGuidance(registration: registration)
                if !guidance.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Existing calendar context").font(.headline)
                            Text("3PO also uses this earlier human context when choosing a calendar. A separate purpose note can add detail.").font(.caption).foregroundStyle(.secondary)
                            ForEach(guidance, id: \.reference.contextKey) { record in ContextMarkdownBody(markdown: record.text) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if sources.isEmpty { Text("No calendars are selected for assistant context.").foregroundStyle(.secondary) }
                ForEach(sources) { source in
                    let id = ContextPage.stableID(registration: registration, kind: .calendarPurpose, key: model.calendarPageKey(source))
                    let page = model.contextPages.page(id: id, registration: registration)
                    let preserved = model.contextPages.identityStatus(id: id, registration: registration) == .preserved
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.label).font(.headline)
                                    if !source.writable { Text("Read-only calendar").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Button(page == nil ? "Describe…" : "Edit purpose…") { editor = .calendar(source, page: page, model: model, registration: registration) }
                                    .disabled(!model.contextPages.canSave || preserved || page.map { $0.owner != .human } == true)
                                if let page { Button("History…") { history = .init(page: page) } }
                            }
                            if let page, page.owner == .human, ContextPagesAccess.eligible(page, model: model, registration: registration, records: []) {
                                ContextMarkdownBody(markdown: page.markdown)
                                HStack {
                                    Text("Written by you · Updated " + page.updated.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Forget purpose…", role: .destructive) { forgetting = page }.controlSize(.small).disabled(!model.contextPages.canSave)
                                }
                            } else { Text(preserved ? "This saved guide needs a compatible version of 3PO. Its original text is preserved." : guidance.isEmpty ? "Not described. 3PO will not infer a purpose from the calendar's name." : "No separate purpose note. 3PO also uses the existing calendar context above.").font(.callout).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    private func openOverview() {
        let id = ContextPage.stableID(registration: registration, kind: .overview, key: "everyday")
        guard model.contextPages.identityStatus(id: id, registration: registration) != .preserved else { error = "This saved page needs a compatible version of 3PO. Its original data is preserved."; return }
        if let page = model.contextPages.page(id: id, registration: registration) {
            guard page.owner == .human, ContextPagesAccess.eligible(page, model: model, registration: registration, records: model.contextKnowledge(registration: registration, includeTopics: false, purpose: .inspection)) else { error = "The existing overview cannot be edited as a human page. Add a separate context note."; return }
            editor = .existing(page)
        } else { editor = .overview(registration: registration) }
    }
    private func forget() {
        guard let page = forgetting else { return }
        defer { forgetting = nil }
        guard owned, page.registration == registration, page.owner == .human else { error = "The account or page owner changed. Reopen the page before forgetting it."; return }
        if page.kind == .calendarPurpose && !ContextPagesAccess.eligible(page, model: model, registration: registration, records: []) { error = "This calendar's current identity or access changed. Its note remains saved."; return }
        do {
            try model.contextPages.forget(id: page.id, registration: registration, expectedRevision: page.revision)
            if selection == .page(page.id) { selection = nil }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// Current permitted records only. Missing old references are counted without exposing old text.
private struct ContextWorkingProjection {
    var records: [ContextKnowledgeRecord]
    var unavailableCount: Int
    // An absent reference may be outside this scope/bounded window; absence is not a new input.
    var count: Int { records.count }
    init(records: [ContextKnowledgeRecord], checkpoint: ContextPageCheckpoint?) {
        let prior = Dictionary((checkpoint?.references ?? []).filter { $0.kind != "projectIdentity" }.map { ($0.contextKey, $0.revision) }, uniquingKeysWith: { first, _ in first })
        let current = records.filter { $0.reference.kind != "projectIdentity" }
        let keys = Set(current.map { $0.reference.contextKey })
        self.records = current.filter { prior[$0.reference.contextKey] != $0.reference.revision }
            .sorted { $0.date == $1.date ? $0.reference.contextKey < $1.reference.contextKey : $0.date > $1.date }
        unavailableCount = prior.keys.filter { !keys.contains($0) }.count
    }
}

private struct ContextMaintenanceStatusView: View {
    @Bindable var model: DashboardModel
    var registration: String
    var pages: [ContextPage]
    var records: [ContextKnowledgeRecord]
    var projects: [LifeItem]
    private var updating: Bool {
        model.heartbeat.activeRegistration == registration && model.contextConsolidation.busy &&
        model.contextConsolidation.ownedHeartbeatRunID == model.heartbeat.ownedRunID
    }
    private var latestLearning: PAHeartbeatStep? {
        model.heartbeat.state.accounts[registration]?.reviews?.max { $0.started < $1.started }?.steps?.first { $0.id == "learning" }
    }
    var body: some View {
        let checkpoint = model.contextPages.checkpoint(registration: registration)
        let pending = ContextWorkingProjection(records: records, checkpoint: checkpoint)
        let maintained = pages.filter { $0.owner == .generated }
        let awaiting = projects.filter { item in model.contextPages.identityStatus(id: ContextPage.stableID(registration: registration, kind: .project, key: item.id.uuidString), registration: registration) == .missing }.count
        let unavailable = maintained.filter { !ContextPagesAccess.eligible($0, model: model, registration: registration, records: records) }.count
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 10) {
                if updating { ProgressView().controlSize(.small) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(pending: pending.count, awaiting: awaiting, maintained: maintained.count, unavailable: unavailable))
                        .font(.caption.weight(.medium)).accessibilityIdentifier("context-maintenance-status")
                    if model.contextPages.isReadable {
                        Text("\(maintained.count) maintained page\(maintained.count == 1 ? "" : "s") saved · \(awaiting) project page\(awaiting == 1 ? "" : "s") awaiting a first update")
                            .font(.caption).foregroundStyle(.secondary)
                        if let checkpoint {
                            Text("Last saved consolidation: " + checkpoint.updated.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button("Run heartbeat") { model.heartbeat.check(model, manual: true) }
                    .controlSize(.small).help(model.heartbeat.manualCheckHelp(model))
                    .disabled(registration != model.chatGPT.activeID || model.heartbeat.manualCheckBlockReason(model) != nil)
            }
            if updating {
                Text(model.contextConsolidation.status).font(.caption).foregroundStyle(.secondary)
                if let error = model.contextConsolidation.error { Text(error).font(.caption).foregroundStyle(.orange) }
            } else if let step = latestLearning, step.status == "failed" || step.status == "waiting" {
                Text("Latest context and learning stage: " + (step.detail ?? step.label))
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
        }.padding(.top, 8)
    }
    private func headline(pending: Int, awaiting: Int, maintained: Int, unavailable: Int) -> String {
        if !model.contextPages.isReadable { return "Saved context is unavailable; the original data is preserved." }
        if !model.assistant.memory.enabled { return "Context use is paused. Your saved pages remain preserved." }
        if updating { return "Updating context pages…" }
        if !model.assistant.memory.learningEnabled { return "Context maintenance is paused in supporting facts and controls." }
        if maintained == 0 { return "Awaiting first maintained pages; working changes are available to inspect." }
        if pending > 0 { return "\(pending) working change\(pending == 1 ? "" : "s") awaiting consolidation." }
        if awaiting > 0 { return "\(awaiting) project page\(awaiting == 1 ? "" : "s") awaiting maintenance." }
        if unavailable > 0 { return "\(unavailable) saved page\(unavailable == 1 ? " is" : "s are") unavailable in this current context." }
        return "Saved context pages are available."
    }
}

private struct ContextWorkingChangesView: View {
    @Bindable var model: DashboardModel
    var registration: String
    var topic: UUID?
    var records: [ContextKnowledgeRecord]
    var body: some View {
        let projection = ContextWorkingProjection(records: records, checkpoint: model.contextPages.checkpoint(registration: registration))
        let items = model.assistant.projects.items(registration, topic: topic, includeTopics: false)
        VStack(alignment: .leading, spacing: 16) {
            Text("Working changes").font(.title2.weight(.semibold))
            Text("Current permitted context since the last saved consolidation. Useful changes can inform your PA while maintained pages wait for their next update. This is a bounded view of saved context, not a full source history.")
                .font(.callout).foregroundStyle(.secondary)
            if !model.contextPages.isReadable {
                ContentUnavailableView("Maintenance history unavailable", systemImage: "lock.doc", description: Text("The saved checkpoint could not be read. No changes have been assumed processed."))
            } else if !model.assistant.memory.enabled {
                ContentUnavailableView("Context use is paused", systemImage: "pause.circle", description: Text("Use Supporting facts and controls to resume. Your saved pages and original records remain preserved."))
            } else {
                if projection.records.isEmpty {
                    Text("No new or changed records are available in this permitted projection.").font(.callout).foregroundStyle(.secondary)
                }
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(projection.records, id: \.reference.contextKey) { record in
                        ContextWorkingChangeRow(record: record, project: record.projectID.flatMap { id in items.first { $0.id == id } })
                    }
                }
                if projection.unavailableCount > 0 {
                    Label("\(projection.unavailableCount) earlier supporting reference\(projection.unavailableCount == 1 ? " is" : "s are") outside this current permitted view. Earlier text is withheld; this does not prove a plan was completed or cancelled.", systemImage: "lock.doc")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ContextWorkingChangeRow: View {
    var record: ContextKnowledgeRecord
    var project: LifeItem?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.caption.weight(.semibold))
                Spacer()
                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
            if let project, record.reference.kind == "project" {
                Text(project.title).font(.callout.weight(.medium))
                Text(project.status.title + (project.due.map { " · Due " + LifeWorkspaceRules.displayDate($0) } ?? "")).font(.caption).foregroundStyle(.secondary)
                if !project.searchableNotes.isEmpty { ContextMarkdownBody(markdown: project.searchableNotes) }
            } else {
                if record.reference.kind != "memory" && record.reference.kind != "human" && record.reference.kind != "action" { Text(record.title).font(.callout.weight(.medium)) }
                Text(PAProse.display(record.text)).font(.callout).textSelection(.enabled)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private var label: String {
        switch record.reference.kind {
        case "memory": "Supporting fact"
        case "human": "Your conversation"
        case "action": "Recorded app action"
        case "project": "Project change"
        case "page": "Your context"
        case "whatsapp": "Attributed message"
        case "native-calendar": "Calendar context"
        case "native-reminder": "Reminder context"
        case "native-mail": "Email context"
        default: "Context update"
        }
    }
}

private enum ContextSidebarSection: CaseIterable, Hashable { case context, projects, topics, notes, instructions }

/// A display-only forest. Missing parents become roots and cycles lose one display edge;
/// canonical project identities, order, parents and saved presentation are never changed.
private struct ContextSidebarProjectTree {
    struct Row: Identifiable {
        let item: LifeItem
        let depth: Int
        let hasChildren: Bool
        let expanded: Bool
        var id: UUID { item.id }
    }
    private let items: [LifeItem]
    private let parents: [UUID: UUID]
    private let children: [UUID: [LifeItem]]
    private let roots: [LifeItem]
    init(items: [LifeItem]) {
        var seen = Set<UUID>()
        let unique = items.filter { seen.insert($0.id).inserted }
        let ids = Set(unique.map(\.id))
        var parents = Dictionary(unique.compactMap { item -> (UUID, UUID)? in
            guard let parent = item.parentID, parent != item.id, ids.contains(parent) else { return nil }
            return (item.id, parent)
        }, uniquingKeysWith: { first, _ in first })
        var settled = Set<UUID>()
        for item in unique where !settled.contains(item.id) {
            var path = Set<UUID>(), next: UUID? = item.id
            while let id = next, let parent = parents[id], !settled.contains(id) {
                guard path.insert(id).inserted else { parents.removeValue(forKey: id); break }
                next = parent
            }
            settled.formUnion(path)
        }
        self.items = unique; self.parents = parents
        children = Dictionary(grouping: unique.filter { parents[$0.id] != nil }, by: { parents[$0.id]! })
        roots = unique.filter { parents[$0.id] == nil }
    }
    func ancestors(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>(), next = parents[id]
        while let id = next, result.insert(id).inserted { next = parents[id] }
        return result
    }
    func rows(matching: Set<UUID>?, expanded: Set<UUID>) -> [Row] {
        var included = matching ?? Set(items.map(\.id))
        if let matching { for id in matching { included.formUnion(ancestors(of: id)) } }
        var pending = roots.reversed().map { ($0, 0) }, rows: [Row] = [], seen = Set<UUID>()
        while let (item, depth) = pending.popLast() {
            guard included.contains(item.id), seen.insert(item.id).inserted else { continue }
            let nested = children[item.id, default: []]
            let open = matching != nil || expanded.contains(item.id)
            rows.append(.init(item: item, depth: depth, hasChildren: !nested.isEmpty, expanded: open))
            if open { pending.append(contentsOf: nested.reversed().map { ($0, depth + 1) }) }
        }
        return rows
    }
}

private enum ContextSidebarText {
    static func summary(_ markdown: String) -> String? {
        let lines = markdown.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let line = lines.first(where: { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("```") }) ?? lines.first else { return nil }
        let plain = PAProse.display(line).replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>*_`- \t"))
        guard !plain.isEmpty else { return nil }
        return String(plain.prefix(110)) + (plain.count > 110 ? "…" : "")
    }
}

private enum ContextPageDestination: Hashable { case guide, overview, working, area(String), page(String), project(UUID), feature(ContextFeature), brief, review, calendars }
private struct ContextPageInstructionRequest: Identifiable {
    let id = UUID()
    var registration: String
    var brief: BriefWritingPrompt? = nil
}
private struct ContextPageHistoryRequest: Identifiable { let id = UUID(); var page: ContextPage }

private struct ContextPageEditRequest: Identifiable {
    let id = UUID()
    var registration: String
    var kind: ContextPage.Kind
    var key: String
    var title: String
    var expected: ContextPage? = nil
    var calendar: SourceOption? = nil
    var projectReference: ContextPageReference? = nil
    var initialMarkdown: String? = nil
    static func feature(_ feature: ContextFeature, page: ContextPage?, registration: String, currentText: String? = nil, useDefault: Bool = false) -> Self {
        .init(registration: registration, kind: .instruction, key: feature.rawValue, title: feature.title,
              expected: page, initialMarkdown: useDefault ? feature.defaultText : page == nil ? (currentText ?? feature.defaultText) : nil)
    }
    static func note(registration: String) -> Self { .init(registration: registration, kind: .note, key: UUID().uuidString, title: "") }
    @MainActor static func scoped(_ scope: ContextInstructionScope, model: DashboardModel, registration: String, records: [ContextKnowledgeRecord]) throws -> Self {
        guard registration == model.chatGPT.activeID else { throw ContextPageFailure.unavailable }
        guard ContextInstructionScope(key: scope.key) == scope else { throw ContextPageFailure.unsupportedPage }
        let id = ContextPage.stableID(registration: registration, kind: .instruction, key: scope.key)
        guard model.contextPages.identityStatus(id: id, registration: registration) != .preserved else { throw ContextPageFailure.unsupportedPage }
        let existing = model.contextPages.page(id: id, registration: registration)
        if existing != nil, model.contextScopedInstruction(scope, registration: registration, records: records) == nil { throw ContextPageFailure.stalePage }
        switch scope {
        case .space(let project):
            guard let item = model.assistant.projects.items(registration, includeTopics: true).first(where: { $0.id == project && !$0.kind.isWork }) else { throw ContextPageFailure.unavailable }
            return .init(registration: registration, kind: .instruction, key: scope.key, title: "Instructions for " + item.title,
                         expected: existing, projectReference: ContextPagesAccess.projectIdentity(item))
        case .topic(let key):
            let title = LifeArea.allCases.first(where: { $0.rawValue == key })?.title ?? "Recent context"
            return .init(registration: registration, kind: .instruction, key: scope.key, title: title + " instructions", expected: existing)
        }
    }
    static func overview(registration: String) -> Self { .init(registration: registration, kind: .overview, key: "everyday", title: "Everyday context") }
    static func existing(_ page: ContextPage) -> Self {
        .init(registration: page.registration, kind: page.kind, key: page.key, title: page.title, expected: page,
              projectReference: page.references.first { $0.kind == "projectIdentity" })
    }
    @MainActor static func calendar(_ source: SourceOption, page: ContextPage?, model: DashboardModel, registration: String) -> Self {
        .init(registration: registration, kind: .calendarPurpose, key: model.calendarPageKey(source), title: "Calendar purpose", expected: page, calendar: source)
    }
    @MainActor static func project(_ item: LifeItem, model: DashboardModel, registration: String) throws -> Self {
        guard item.registration == registration, !item.kind.isWork,
              let current = model.assistant.projects.items(registration, includeTopics: true).first(where: { $0.id == item.id && !$0.kind.isWork }) else { throw ContextPageFailure.invalid("project identity") }
        let reference = ContextPagesAccess.projectIdentity(current)
        let key = "project-purpose:" + current.id.uuidString
        let id = ContextPage.stableID(registration: registration, kind: .note, key: key)
        guard model.contextPages.identityStatus(id: id, registration: registration) != .preserved else { throw ContextPageFailure.unsupportedPage }
        let page = model.contextPages.page(id: id, registration: registration)
        guard page?.owner == nil || page?.owner == .human else { throw ContextPageFailure.unsupportedPage }
        if let page {
            guard ContextPagesAccess.eligible(page, model: model, registration: registration, records: model.contextKnowledge(registration: registration, includeTopics: false, purpose: .inspection)) else { throw ContextPageFailure.stalePage }
        }
        return .init(registration: registration, kind: .note, key: key, title: "About " + current.title, expected: page, projectReference: reference)
    }
}

@MainActor private enum ContextPagesAccess {
    static func owned(_ model: DashboardModel, registration: String, storage: ObjectIdentifier?) -> Bool {
        registration == model.chatGPT.activeID && storage == model.container.map(ObjectIdentifier.init)
    }
    static func calendarAccess(_ model: DashboardModel) -> Bool {
        model.assistant.contextEnabled && EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }
    static func calendars(_ model: DashboardModel) -> [SourceOption] {
        guard calendarAccess(model) else { return [] }
        return model.calendarData.sources.filter { !model.assistant.excludedCalendars.contains($0.id) }.sorted { ($0.label, $0.id) < ($1.label, $1.id) }
    }
    static func eligible(_ page: ContextPage, model: DashboardModel, registration: String, records: [ContextKnowledgeRecord]) -> Bool {
        guard page.registration == registration, registration == model.chatGPT.activeID else { return false }
        if page.kind == .calendarPurpose {
            return page.owner == .human && calendars(model).contains { model.calendarPageKey($0) == page.key }
        }
        if page.owner == .human && page.kind == .instruction {
            if let scope = ContextInstructionScope(key: page.key) {
                switch scope {
                case .topic: return page.references.isEmpty
                case .space(let id):
                    return page.references.count == 1 && page.references.first?.key == id.uuidString &&
                        page.references.first.map { currentProjectIdentity($0, model: model, registration: registration) } == true
                }
            }
            return ContextFeature(rawValue: page.key) != nil && page.references.isEmpty
        }
        if page.owner == .human && (page.kind == .overview || page.kind == .note) {
            // Pausing recall does not hide the human's own writing. Project notes still need
            // their exact current folder/scope; source-supported pages keep the normal gate.
            if page.kind == .note && page.key.hasPrefix("project-purpose:") {
                guard page.references.count == 1, let reference = page.references.first,
                      reference.kind == "projectIdentity", page.key == "project-purpose:" + reference.key else { return false }
                return currentProjectIdentity(reference, model: model, registration: registration)
            }
            if page.references.isEmpty { return true }
        }
        return model.contextPageEligible(page, records: records)
    }
    static func projectIdentity(_ item: LifeItem) -> ContextPageReference {
        .init(kind: "projectIdentity", key: item.id.uuidString,
              revision: ContextKnowledgeRules.fingerprint(item.registration + ":" + item.id.uuidString + ":" + (item.conversationID?.uuidString ?? "shared")))
    }
    static func currentProjectIdentity(_ reference: ContextPageReference, model: DashboardModel, registration: String) -> Bool {
        guard reference.kind == "projectIdentity", registration == model.chatGPT.activeID,
              let item = model.assistant.projects.items(registration, includeTopics: true).first(where: { !$0.kind.isWork && $0.id.uuidString == reference.key }) else { return false }
        return item.registration == registration && projectIdentity(item) == reference
    }
    static func kindTitle(_ kind: ContextPage.Kind) -> String {
        switch kind { case .overview: "Everyday context"; case .project: "Project context"; case .topic: "Topic context"; case .calendarPurpose: "Calendar purpose"; case .instruction: "Feature instructions"; default: "Your context note" }
    }
    static func projectLabel(_ item: LifeItem, all: [LifeItem]) -> String {
        var names = [item.title], parent = item.parentID, seen: Set<UUID> = [item.id]
        while let id = parent, seen.insert(id).inserted, let value = all.first(where: { $0.id == id }) {
            names.insert(value.title, at: 0); parent = value.parentID
        }
        return names.joined(separator: " › ")
    }
}

private struct ContextPageHumanEditor: View {
    @Bindable var model: DashboardModel
    let request: ContextPageEditRequest
    private let storage: ObjectIdentifier?
    private let storeIdentity: ObjectIdentifier
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var markdown: String
    @State private var error: String?
    init(model: DashboardModel, request: ContextPageEditRequest) {
        self.model = model; self.request = request
        storage = model.container.map(ObjectIdentifier.init); storeIdentity = ObjectIdentifier(model.contextPages)
        _title = State(initialValue: request.title)
        _markdown = State(initialValue: request.initialMarkdown ?? (request.expected?.owner == .human ? request.expected!.markdown : ""))
    }
    private var owned: Bool { ContextPagesAccess.owned(model, registration: request.registration, storage: storage) && storeIdentity == ObjectIdentifier(model.contextPages) }
    private var bindingCurrent: Bool {
        guard owned else { return false }
        if let source = request.calendar {
            return ContextPagesAccess.calendars(model).contains { $0.id == source.id && model.calendarPageKey($0) == request.key }
        }
        if let reference = request.projectReference {
            return ContextPagesAccess.currentProjectIdentity(reference, model: model, registration: request.registration)
        }
        return true
    }
    private var readable: Bool {
        guard bindingCurrent else { return false }
        guard let page = request.expected else { return true }
        return page.owner == .human && ContextPagesAccess.eligible(page, model: model, registration: request.registration, records: model.contextKnowledge(registration: request.registration, purpose: .inspection))
    }
    private var validText: Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanTitle.isEmpty && cleanTitle.utf8.count <= ContextPageLimits.maximumTitleBytes && !title.contains("\0") &&
            !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && markdown.utf8.count <= ContextPageLimits.maximumMarkdownBytes && !markdown.contains("\0")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.kind == .instruction ? request.title : request.calendar == nil ? "Your context" : "Calendar purpose").font(.title2.weight(.semibold))
            Text(request.kind == .instruction ? "Describe how you want 3PO to help. This guidance stays separate from factual context, source access and action approval." : request.calendar == nil ? "Write only what you want 3PO to know. Your words stay separate from automatically maintained pages." : "Explain what belongs in this calendar. Saving changes only this local guide.").font(.callout).foregroundStyle(.secondary)
            if readable {
                if let source = request.calendar { Text(source.label).font(.headline) }
                else { TextField("Page title", text: $title).textFieldStyle(.roundedBorder) }
                TextEditor(text: $markdown).font(.body).padding(8).frame(minHeight: 280).border(Color.secondary.opacity(0.25)).accessibilityLabel("Your context Markdown")
                Text("Plain text or Markdown. Saving creates a new version; earlier versions remain in History.").font(.caption).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Context changed", systemImage: "lock.doc", description: Text("The account, project identity or source access changed. Your draft remains here; reopen the page after resolving the change."))
            }
            if title.utf8.count > ContextPageLimits.maximumTitleBytes { Text("Use a shorter page title.").font(.caption).foregroundStyle(.orange) }
            if markdown.utf8.count > ContextPageLimits.maximumMarkdownBytes { Text("Shorten this page before saving.").font(.caption).foregroundStyle(.orange) }
            if let error = error ?? model.contextPages.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(!readable || !validText || !model.contextPages.canSave)
            }
        }.padding(24).frame(width: 680, height: 620)
            .onChange(of: model.chatGPT.activeID) { dismiss() }
    }
    private func save() {
        guard owned, bindingCurrent, readable, validText, request.expected?.owner == nil || request.expected?.owner == .human else { error = "The account, page or supporting identity changed. Reopen the editor before saving."; return }
        let pageID = ContextPage.stableID(registration: request.registration, kind: request.kind, key: request.key)
        let current = model.contextPages.page(id: pageID, registration: request.registration)
        guard current?.revision == request.expected?.revision else { error = ContextPageFailure.stalePage.localizedDescription; return }
        var page = request.expected ?? ContextPage(registration: request.registration, kind: request.kind, key: request.key, owner: .human, title: title, markdown: "")
        page.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        page.markdown = markdown
        page.synopsis = ""
        if request.expected == nil, let reference = request.projectReference { page.references = [reference] }
        do {
            let saved = try model.contextPages.save(page, expectedRevision: request.expected?.revision)
            do { _ = try model.acknowledgeProjectPurpose(saved) }
            catch { self.error = "Your description was saved. Its matching clarification could not be marked answered: " + error.localizedDescription; return }
            dismiss()
        }
        catch { self.error = error.localizedDescription }
    }
}

private struct ContextPageHistoryView: View {
    @Bindable var model: DashboardModel
    let request: ContextPageHistoryRequest
    private let storage: ObjectIdentifier?
    private let storeIdentity: ObjectIdentifier
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var error: String?
    init(model: DashboardModel, request: ContextPageHistoryRequest) {
        self.model = model; self.request = request
        storage = model.container.map(ObjectIdentifier.init); storeIdentity = ObjectIdentifier(model.contextPages)
        _selected = State(initialValue: request.page.revision)
    }
    private var owned: Bool { ContextPagesAccess.owned(model, registration: request.page.registration, storage: storage) && storeIdentity == ObjectIdentifier(model.contextPages) }
    var body: some View {
        let versions = owned ? Array(model.contextPages.history(id: request.page.id, registration: request.page.registration).reversed()) : []
        let records = model.contextKnowledge(registration: request.page.registration, purpose: .inspection)
        let current = model.contextPages.page(id: request.page.id, registration: request.page.registration)
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Page history").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Saved versions are immutable. Restoring appends a new version and keeps the current one in history.").font(.callout).foregroundStyle(.secondary)
            Picker("Version", selection: $selected) {
                ForEach(Array(versions)) { version in
                    Text(version.page.updated.formatted(date: .abbreviated, time: .shortened) + (version.id == current?.revision ? " · Current" : ""))
                        .tag(Optional(version.id))
                }
            }
            ScrollView {
                if let version = versions.first(where: { $0.id == selected }) {
                    if ContextPagesAccess.eligible(version.page, model: model, registration: request.page.registration, records: records) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(version.page.title).font(.title3.weight(.semibold))
                            Text(version.page.owner == .human ? "Written by you" : "Maintained by 3PO").font(.caption).foregroundStyle(.secondary)
                            ContextMarkdownBody(markdown: version.page.markdown)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else { Text("This version's text is withheld because its supporting context or current access is unavailable. It cannot be restored now.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
            if current?.revision != request.page.revision { Text("The page changed while history was open. Reopen History before restoring a version.").font(.caption).foregroundStyle(.orange) }
            if let error = error ?? model.contextPages.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("Restore this version") { restore() }
                    .disabled(!owned || !model.contextPages.canSave || current?.revision != request.page.revision || selected == current?.revision || !versions.contains { $0.id == selected && ContextPagesAccess.eligible($0.page, model: model, registration: request.page.registration, records: records) })
            }
        }.padding(24).frame(width: 700, height: 620)
            .onChange(of: model.chatGPT.activeID) { dismiss() }
    }
    private func restore() {
        guard owned, let selected,
              let version = model.contextPages.history(id: request.page.id, registration: request.page.registration).first(where: { $0.id == selected }),
              ContextPagesAccess.eligible(version.page, model: model, registration: request.page.registration, records: model.contextKnowledge(registration: request.page.registration, purpose: .inspection)) else { error = "The account, source access or this version's supporting context changed. No version was restored."; return }
        do {
            try model.contextPages.restore(id: request.page.id, registration: request.page.registration, revision: selected, expectedRevision: request.page.revision)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ContextProjectPurposePicker: View {
    @Bindable var model: DashboardModel
    let registration: String
    var topic: UUID? = nil
    var choose: (LifeItem) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        let items = model.assistant.projects.items(registration, topic: topic, includeTopics: false).filter { !$0.kind.isWork }
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Describe a project").font(.title2.weight(.semibold)); Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Choose the existing folder this context belongs to. This creates no project or task.").font(.callout).foregroundStyle(.secondary)
            TextField("Find a project folder", text: $query).textFieldStyle(.roundedBorder)
            List(items.filter { query.isEmpty || ContextPagesAccess.projectLabel($0, all: items).localizedStandardContains(query) }) { item in
                Button {
                    do { try choose(item) }
                    catch { self.error = error.localizedDescription }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(ContextPagesAccess.projectLabel(item, all: items), systemImage: "folder")
                        Text("Created " + item.created.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, 4)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width: 580, height: 470)
            .onChange(of: model.chatGPT.activeID) { dismiss() }
    }
}

/// The caller has validated the entire current page; individual quotes also need an exact supplied record.
private struct ContextPageSupportingContext: View {
    var page: ContextPage
    var records: [ContextKnowledgeRecord]
    private var supported: [(quote: ContextPageQuote, record: ContextKnowledgeRecord)] {
        guard page.owner == .generated else { return [] }
        return (page.evidenceQuotes ?? []).compactMap { quote in
            guard let record = records.first(where: { $0.reference.id == quote.referenceID && page.references.contains($0.reference) }) else { return nil }
            return (quote, record)
        }
    }
    var body: some View {
        let rows = supported
        if !rows.isEmpty {
            DisclosureGroup("Supporting context") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows.indices, id: \.self) { index in
                        let row = rows[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(label(row.record)).font(.caption.weight(.semibold))
                            Text(row.quote.quote).font(.callout).textSelection(.enabled)
                            Text(row.record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(.top, 8)
            }.font(.caption)
        }
    }
    private func label(_ record: ContextKnowledgeRecord) -> String {
        switch record.reference.kind {
        case "human": "Your conversation"
        case "action": "Verified app action"
        case "project", "projectIdentity": "Project: " + record.title
        case "page": "Your context: " + record.title
        case "memory": "Saved memory"
        default: "Supporting record"
        }
    }
}

/// Render local Markdown without loading remote images or executing embedded content.
private struct ContextMarkdownBody: View {
    var markdown: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks.indices, id: \.self) { index in
                let block = blocks[index]
                if block.hasPrefix("### ") { inline(String(block.dropFirst(4))).font(.headline) }
                else if block.hasPrefix("## ") { inline(String(block.dropFirst(3))).font(.title3.weight(.semibold)) }
                else if block.hasPrefix("# ") { inline(String(block.dropFirst(2))).font(.title2.weight(.semibold)) }
                else { inline(block).font(.body) }
            }
        }.lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var blocks: [String] {
        markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }
}
