import SwiftUI

struct PAMemoryView: View {
    @Bindable var memory: PAMemoryStore
    var registration: String
    var conversationID: UUID? = nil
    var topicTitle: String? = nil
    var learning: MemoryLearningService?
    var assistant: AssistantService?
    var checkContext: (() -> Void)?
    var organisation:LifeOrganisationService?
    var organiseContext:(()->Void)?
    var model:DashboardModel?
    var focusAreas:[LifeArea]=[]
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PAMemory?
    @State private var text = ""
    @State private var search = ""
    @State private var presentation="Overview"
    @State private var scope: UUID?
    @State private var kind = MemoryKind.preference
    @State private var provisional = false
    @State private var forgotten: [PAMemory]?
    @State private var organising:PAMemory?
    @State private var planReports:PAMemory?
    @State private var selectedArea:LifeArea?
    @State private var showHistory=false
    @State private var editError:String?
    @State private var lineage:Set<UUID>?
    var body: some View {
        let permittedIDs=Set(memory.permittedRecords.map(\.id))
        VStack(alignment:.leading,spacing:16) {
            HStack { Label("Supporting facts and controls",systemImage:"doc.text.magnifyingglass").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() } }
            if let error = memory.error { Text(error).foregroundStyle(.orange).font(.caption) }
            Text("Original facts, evidence, correction history and learning controls behind your Context pages.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("Supporting facts view",selection:$presentation) { Text("Overview").tag("Overview"); Text("Facts").tag("List"); Text("Life areas").tag("Connections"); if model != nil { Text("Review").tag("Review") };Text("Controls").tag("Controls") }.pickerStyle(.segmented).labelsHidden().frame(width:470)
                if presentation == "List" { TextField("Search memories and connections",text:$search) }
            }
            if presentation == "List" { HStack { Toggle("Show earlier versions",isOn:$showHistory).font(.caption);if lineage != nil { Button("Show all facts") { lineage=nil;search="" } } } }
            ScrollView {
                if presentation == "Overview" {
                    PAMemoryOverviewView(memory:memory,registration:registration,topic:conversationID,focus:focusAreas,model:model) { item in presentation="List";lineage=nil;search=item.text;showHistory=item.supersededBy != nil }
                } else if presentation == "Review",let model {
                    MemoryMaintenanceView(model:model) { ids in presentation="List";search="";lineage=Set(ids);showHistory=false }
                } else if presentation == "Controls" { controls
                } else if presentation == "Connections" {
                    Text("Areas organise currently usable facts and workspace items. Area branches are navigation; inspect facts for their recorded relationships.").font(.caption).foregroundStyle(.secondary)
                    let notebook=memory.notebook(registration,topic:conversationID,includeTopics:true)
                    LifeNotebookMapView(notebook:notebook,notes:notebook.notes,selectedArea:$selectedArea)
                    if let note=notebook.notes.first(where:{$0.area == selectedArea}) { LifeNotebookAreaView(notebook:notebook,note:note) { item in presentation="List";lineage=nil;search=item.text } }
                } else {
                LazyVStack(alignment:.leading,spacing:12) {
                    ForEach(memory.items(registration).filter { (lineage?.contains($0.id) ?? true) && (showHistory || $0.supersededBy == nil) && (search.isEmpty || ($0.text + " " + ($0.reviewContext ?? "") + " " + ($0.connections ?? []).map { $0.subject + " " + $0.relation + " " + $0.object }.joined(separator:" ")).localizedCaseInsensitiveContains(search)) }) { item in
                        VStack(alignment:.leading,spacing:6) {
                            HStack { Text(item.conversationID.map { "Earlier topic · " + (assistant?.conversation($0)?.title ?? "Saved topic") } ?? "Shared").font(.caption).foregroundStyle(.secondary); Text(item.kind.rawValue.capitalized).font(.caption.weight(.semibold)); if item.supersededBy != nil { Text("Earlier version").font(.caption).foregroundStyle(.secondary) } else if item.supersedes != nil { Text("Corrected").font(.caption).foregroundStyle(.secondary) };if item.resolved != nil { Text(MemoryRules.archived(item) ? "Archived" : "Resolved").font(.caption).foregroundStyle(.secondary) }; if MemoryRules.needsReview(item) { Text("Review needed").foregroundStyle(.orange).font(.caption) }; Spacer() }
                            Text(item.text).textSelection(.enabled)
                            let availability=MemoryInspection.rows([item],permitted:permittedIDs,registration:registration).first?.availability ?? .sourceUnavailable
                            Text((memory.enabled ? "" : "Memory use paused · ")+availability.title+" · "+availability.explanation).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array((item.connections ?? []).enumerated()),id:\.offset) { _, edge in Text(edge.subject + " → " + edge.relation + " → " + edge.object).font(.caption).foregroundStyle(.secondary) }
                            PAMemoryEvidenceView(record:item,sourcePermitted:permittedIDs.contains(item.id))
                            if item.kind == .commitment && item.supersededBy == nil { Button("Remembered plan reports…") { planReports=item }.controlSize(.small).disabled(!memory.enabled || !permittedIDs.contains(item.id) || !MemoryRules.usable(item,registration:registration)) }
                            if item.supersedes != nil || item.supersededBy != nil {
                                Button("View version history") { search="";showHistory=true;lineage=Set(memory.lineage(item.id).map(\.id)) }.controlSize(.small)
                            }
                            HStack {
                                if item.supersededBy != nil { Button("Restore this version") { memory.restoreVersion(item.id) } }
                                else {
                                if !item.explicit && item.certainty != .stated { Button("Confirm") { memory.accept(item.id) } }
                                Button("Edit") { editing = item; text = item.text; kind = item.kind; provisional = !item.explicit && item.certainty != .stated; scope = item.conversationID }
                                Button("Organise") { organising=item }
                                if item.source == nil && item.kind != .commitment { Button(item.retiredAt == nil ? "Retire from recall" : "Restore to recall") { memory.retire(item.id,retired:item.retiredAt == nil,expectedRevision:memory.revision) } }
                                if item.resolved == nil && item.kind == .commitment { Button("Mark resolved") { memory.resolve(item.id) } }
                                if item.resolved != nil { Button("Reopen") { memory.reopen(item.id) } }
                                }
                                Button("Forget") { let versions=memory.versionFamily(item.id);if memory.forget(item.id) { forgotten = versions } }
                            }.controlSize(.small)
                        }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                    }
                    if memory.items(registration).isEmpty { Text("Tell your PA ‘Remember that…’, or add something below.").foregroundStyle(.secondary).padding(.vertical) }
                }
            }
            }
            if let forgotten { HStack { Text("Memory forgotten").font(.caption); Button("Undo") { if memory.restoreForgotten(forgotten) { self.forgotten = nil } }; Spacer() } }
            if presentation == "List" {
            Divider()
            Text(editing == nil ? "Add a memory" : "Edit memory").font(.headline)
            if let editError { Text(editError).font(.caption).foregroundStyle(.orange) }
            TextField("For example: I need two weeks to arrange birthday presents",text:$text,axis:.vertical).lineLimit(2...4)
            Picker("Memory scope",selection:$scope) { Text("Shared PA memory").tag(Optional<UUID>.none); if let conversationID { Text(topicTitle ?? "This topic").tag(Optional(conversationID)) }; if let scope, scope != conversationID { Text(assistant?.conversation(scope)?.title ?? "Saved topic").tag(Optional(scope)) } }
            HStack { Picker("Kind",selection:$kind) { ForEach(MemoryKind.allCases,id:\.self) { Text($0.rawValue.capitalized).tag($0) } }.frame(width:230); Toggle("Provisional",isOn:$provisional); Spacer() }
            HStack { if editing != nil { Button("Cancel edit") { clear() } }; Spacer(); Button("Save memory") {
                if let editing,memory.records.first(where:{$0.id == editing.id}) != editing { editError="This memory changed while you were editing. Reopen it before saving.";return }
                var item = editing ?? PAMemory(registration:registration,text:text,kind:kind,provenance:"Added by you in Memory")
                if item.text != text { item.connections=nil; item.organisation=nil; item.source=nil; item.supportingSources=nil; item.sourceState=nil; item.sourceInvalidation=nil; item.certainty=nil; item.durability=nil; item.evidence=text; item.provenance="Edited by you in Memory"; item.sourceTurnID=nil; item.sourceDate = .now }
                item.text = text; item.kind = kind; item.explicit = !provisional; item.conversationID = scope
                if item.kind == .commitment { item.retiredAt=nil }
                if scope != nil { item.organisation?.selfName=nil }
                if let editing,editing.text != text {
                    item.id=UUID();if memory.correct(editing.id,with:item) { clear() }
                } else if memory.put(item) { clear() }
            }.disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || registration.isEmpty) }
            }
        }.sheet(item:$organising) { item in LifeOrganisationEditor(memory:memory,record:item) }
        .sheet(item:$planReports) { item in CommitmentReportsView(memory:memory,recordID:item.id,registration:registration) }
        .onChange(of:registration) { planReports=nil;organising=nil;clear() }
        .onAppear { scope = conversationID }.onChange(of:memory.learningEnabled) { _, enabled in if !enabled { learning?.cancel();organisation?.cancel();model?.sourceLearning.cancel();model?.nativeSourceLearning.cancel();model?.memoryMaintenance.cancel() } }.onChange(of:memory.enabled) { _, enabled in if !enabled { learning?.cancel();organisation?.cancel();model?.sourceLearning.cancel();model?.nativeSourceLearning.cancel();model?.memoryMaintenance.cancel() } }.padding(24).frame(width:720,height:720)
    }
    private var controls:some View { VStack(alignment:.leading,spacing:14) {
            Toggle("Use saved context in chats and briefs",isOn:$memory.enabled)
            Toggle("Allow context learning and maintenance",isOn:$memory.learningEnabled)
            Text("Allows conversation learning, separately opted-in source learning, organisation and optional memory review through your ChatGPT plan. Directly stated stable facts persist; inferred entries remain provisional. Source opt-ins are in Settings → Context. No email backlog is processed. Pausing stops future learning; explicit memories still work.").font(.caption).foregroundStyle(.secondary)
            if let learning, let assistant { HStack { Text(learning.status(assistant)).font(.caption).foregroundStyle(.secondary); Spacer(); if learning.busy { Button("Stop") { learning.cancel() } } else { Button("Check context") { checkContext?() }.disabled(assistant.connection.busy || assistant.busy || assistant.connection.usagePaused || !assistant.connection.inferenceVerified || !assistant.contextEnabled || assistant.hasDraft || !memory.enabled || !memory.learningEnabled) } }; if let error = learning.error { Text(error).font(.caption).foregroundStyle(.orange) } }
            if let learning {
                Toggle("Ask occasional useful learning questions",isOn:Binding(get:{ learning.questionsEnabled },set:{ learning.questionsEnabled = $0; learning.cancel() }))
                Text("At most one new learning or project-purpose question per day. Questions stay in Review with Answer, Dismiss and Undo. They use existing learning or context-maintenance work; no separate question request or notification.").font(.caption).foregroundStyle(.secondary)
            }
            if let organisation {
                Toggle("Organise saved facts into life areas",isOn:Binding(get:{organisation.automatic},set:{organisation.automatic=$0}))
                HStack { Text("Classifies new human facts and revisits unpinned classifications after 30 days: at most eight per pass, two automatic passes per day within the shared learning allowance. Organise now can revisit them sooner. It preserves facts/evidence and your pinned organisation; it never resolves, retires or deletes facts.").font(.caption).foregroundStyle(.secondary);Spacer();if organisation.busy { Button("Stop") { organisation.cancel() } } else { Button("Organise now") { organiseContext?() }.disabled(assistant?.busy == true || assistant?.connection.busy == true || assistant?.connection.inferenceVerified != true || assistant?.connection.usagePaused == true || !memory.enabled || !memory.learningEnabled) } }
                if let error=organisation.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Text("Focus draws on this account’s permitted life notebook, including memories from earlier topics. Source access still controls source-derived context. Inferred context needs review after 90 days; stable directly stated facts persist until corrected, retired or forgotten. Retire sets human context aside reversibly; Resolve handles a remembered commitment. Apple reminders and projects keep their own state.").font(.callout).foregroundStyle(.secondary)
        } }
    private func clear() { editing = nil; text = ""; provisional = false; kind = .preference; scope = conversationID;editError=nil }
}
