import SwiftUI

@MainActor extension DashboardModel {
    func contextProjectIdentity(_ item: LifeItem) -> ContextPageReference {
        .init(kind: "projectIdentity", key: item.id.uuidString,
              revision: ContextKnowledgeRules.fingerprint(item.registration + ":" + item.id.uuidString + ":" + (item.conversationID?.uuidString ?? "shared")))
    }
    /// Local activity is an admission signal, not a claim that clarification is actually needed.
    func contextProjectQuestionCandidate(_ project: LifeItem, items: [LifeItem]) -> Bool {
        guard !project.kind.isWork,
              LifeItemQuery.path(project, in: items).allSatisfy({ ContextProjectQuestionRules.open(status: $0.status.rawValue) }) else { return false }
        let hasOpenWork = items.contains { item in
            guard item.kind.isWork, ContextProjectQuestionRules.open(status: item.status.rawValue) else { return false }
            let path = LifeItemQuery.path(item, in: items)
            return path.contains { $0.id == project.id } && path.allSatisfy { ContextProjectQuestionRules.open(status: $0.status.rawValue) }
        }
        return ContextProjectQuestionRules.candidate(status: project.status.rawValue, hasOpenWork: hasOpenWork,
            hasHumanNotes: !project.searchableNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    /// Actionable saved questions use only current local human ownership/activity, never source reconstruction.
    func visibleContextProjectQuestions() -> [ContextProjectQuestion] {
        guard assistant.memory.enabled else { return [] }
        let registration = chatGPT.activeID
        let projects = assistant.projects.items(registration, includeTopics: true)
        let purposePages = contextPages.pages(registration: registration).filter { $0.owner == .human && $0.kind == .note && $0.key.hasPrefix("project-purpose:") }
        return contextQuestions.questions(registration: registration).filter { question in
            let project = projects.first { $0.id == question.projectID }
            return ContextProjectQuestionRules.actionable(question, currentIdentity: project.map(contextProjectIdentity),
                candidate: project.map { contextProjectQuestionCandidate($0, items: projects) } ?? false,
                hasPurpose: purposePages.contains { ContextProjectQuestionRules.purpose($0, registration: registration, identity: question.identity) })
        }
    }
    /// Call after an ordinary manual purpose save. Only an exact verified human page can finish
    /// its current pending clarification; dismissal and answer history are never reopened.
    @discardableResult func acknowledgeProjectPurpose(_ page: ContextPage) throws -> Bool {
        guard page.kind == .note, page.key.hasPrefix("project-purpose:") else { return false }
        guard page.registration == chatGPT.activeID, let identity = page.references.first,
              ContextProjectQuestionRules.purpose(page, registration: chatGPT.activeID, identity: identity),
              let project = assistant.projects.items(page.registration, includeTopics: true).first(where: { !$0.kind.isWork && $0.id.uuidString == identity.key }),
              contextProjectIdentity(project) == identity,
              contextPages.page(id: page.id, registration: page.registration) == page else { throw ContextProjectQuestionFailure.stale }
        guard let question = contextQuestions.questions(registration: page.registration).first(where: { $0.projectID == project.id && $0.identity == identity }) else { return false }
        try contextQuestions.answer(id: question.id, registration: page.registration, expectedRevision: question.revision,
            pageID: page.id, pageRevision: page.revision)
        return true
    }
    func saveProjectPurpose(_ answer: String, question: ContextProjectQuestion, expectedPage: ContextPage?) throws {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard assistant.memory.enabled, question.registration == chatGPT.activeID, !text.isEmpty, text.count <= 6000,
              let project = assistant.projects.items(question.registration, includeTopics: true).first(where: { $0.id == question.projectID }),
              contextProjectIdentity(project) == question.identity,
              contextQuestions.questions(registration: question.registration).contains(where: { $0 == question }) else { throw ContextProjectQuestionFailure.stale }
        let key = "project-purpose:" + project.id.uuidString
        let id = ContextPage.stableID(registration: question.registration, kind: .note, key: key)
        let current = contextPages.page(id: id, registration: question.registration)
        let saved: ContextPage
        if let current, current.owner == .human, current.markdown == text, current.references == [question.identity] {
            // Recover only this exact local save if recording the question receipt previously failed.
            saved = current
        } else {
            guard current?.revision == expectedPage?.revision else { throw ContextPageFailure.stalePage }
            let page = ContextPage(registration: question.registration, kind: .note, key: key, owner: .human,
                title: "Purpose of " + String(project.title.prefix(50)), synopsis: "Project context stated by you", markdown: text, references: [question.identity])
            saved = try contextPages.save(page, expectedRevision: expectedPage?.revision)
        }
        guard contextPages.page(id: saved.id, registration: saved.registration)?.revision == saved.revision else { throw ContextPageFailure.stalePage }
        try contextQuestions.answer(id: question.id, registration: question.registration, expectedRevision: question.revision,
                                    pageID: saved.id, pageRevision: saved.revision)
    }
}

struct ContextProjectQuestionsSection: View {
    @Bindable var model: DashboardModel
    var questions: [ContextProjectQuestion]
    @State private var answering: ContextProjectQuestion?
    @State private var dismissed: ContextProjectQuestion?
    @State private var error: String?
    var body: some View {
        ForEach(questions) { question in
            VStack(alignment: .leading, spacing: 8) {
                Text(question.question).font(.callout).textSelection(.enabled)
                Text("Help 3PO understand this project's purpose.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Answer") { answering = question; error = nil }
                    Spacer()
                    Button("Dismiss") {
                        do { dismissed = try model.contextQuestions.dismiss(id: question.id, registration: question.registration, expectedRevision: question.revision); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                }.controlSize(.small)
            }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        }
        if let dismissed, dismissed.registration == model.chatGPT.activeID {
            HStack {
                Text("Question dismissed").font(.caption).foregroundStyle(.secondary)
                Button("Undo") {
                    do { try model.contextQuestions.undoDismiss(id: dismissed.id, registration: dismissed.registration, expectedRevision: dismissed.revision); self.dismissed = nil; error = nil }
                    catch { self.error = error.localizedDescription }
                }.controlSize(.small)
            }
        }
        if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        if let error = model.contextQuestions.error { Text(error).font(.caption).foregroundStyle(.orange) }
        EmptyView().sheet(item: $answering) { question in ContextProjectPurposeAnswerView(model: model, question: question) }
            .onChange(of: model.chatGPT.activeID) { answering = nil; dismissed = nil; error = nil }
    }
}
private struct ContextProjectPurposeAnswerView: View {
    @Bindable var model: DashboardModel
    var question: ContextProjectQuestion
    let expectedPage: ContextPage?
    @State private var answer = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(model: DashboardModel, question: ContextProjectQuestion) {
        self.model = model; self.question = question
        let id = ContextPage.stableID(registration: question.registration, kind: .note, key: "project-purpose:" + question.projectID.uuidString)
        expectedPage = model.contextPages.page(id: id, registration: question.registration)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(question.question).font(.title3.weight(.semibold))
            Text("Your answer becomes editable project context. It does not change your project notes or create a task.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $answer).font(.body).frame(minHeight: 140)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save context") {
                    do { try model.saveProjectPurpose(answer, question: question, expectedPage: expectedPage); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || answer.count > 6000 || question.registration != model.chatGPT.activeID)
            }
        }.padding(24).frame(width: 540).onChange(of: model.chatGPT.activeID) { dismiss() }
    }
}
