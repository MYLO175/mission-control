import SwiftUI

struct PAMemoryOverviewView:View {
    @Bindable var memory:PAMemoryStore
    var registration:String
    var topic:UUID? = nil
    var focus:[LifeArea] = []
    var model:DashboardModel?
    var inspect:(PAMemory)->Void
    @State private var query=""
    @State private var filter:MemoryAvailability?
    @State private var showingReviewPreferences=false
    private var rows:[MemoryInspectionRow] { MemoryInspection.rows(memory.records,permitted:Set(memory.permittedRecords.map(\.id)),registration:registration,topic:topic) }
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            GroupBox {
                VStack(alignment:.leading,spacing:9) {
                    Text("Your memory notebook").font(.headline)
                    Text("\(rows.count) saved records · \(rows.filter{$0.record.supersededBy == nil}.count) current versions · \(rows.filter{$0.availability == .available}.count) available" ).font(.callout.weight(.medium))
                    Text(memory.enabled ? "Available facts can be used when relevant. Each reply receives a bounded selection, not the whole notebook." : "Memory use is paused. Records stay saved and inspectable; none are selected for replies.").font(.caption).foregroundStyle(.secondary)
                    Text("\(rows.filter{$0.record.source == nil}.count) human-origin records · \(rows.filter{$0.record.source != nil}.count) source-origin records, including history").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            VStack(alignment:.leading,spacing:8) {
                Text("How it fits together").font(.headline)
                layer("Evidence", "Your statements and exact source quotes explain where a fact came from.","quote.bubble")
                layer("Saved facts", "Preferences, context and commitments keep certainty, dates and correction history.","brain")
                layer("Life map", "Areas organise usable facts and your saved projects. Branches navigate areas; recorded relationships have their own evidence.","point.3.connected.trianglepath.dotted")
                layer("Working context", "A reply also uses recent dialogue, preferences, bounded notebook notes and permitted cached sources or tool reads. Those are separate from permanent memory.","text.bubble")
                layer("Keep it current", "Corrections keep earlier versions. Retire sets human context aside; Restore brings it back. Unpinned classifications can be revisited, while your projects and original evidence stay intact.","arrow.triangle.2.circlepath")
                Text("Focus prefers relevant life areas; it does not grant source access. A source reporting ‘completed’ does not complete an Apple reminder.").font(.caption).foregroundStyle(.secondary)
            }
            if let model {
                GroupBox("Review preferences") {
                    HStack {Text("Feedback you save in Review becomes an editable preference in this same memory notebook.").font(.caption).foregroundStyle(.secondary);Spacer();Button("View preferences") {showingReviewPreferences=true}}
                }.sheet(isPresented:$showingReviewPreferences) {ReviewRelevancePreferencesView(model:model)}
                GroupBox("Current source context") {
                    VStack(alignment:.leading,spacing:8) {
                        Text(model.assistant.contextEnabled ? "Source context is enabled for PA requests." : "Source context is off; source read tools are unavailable.")
                        Text("Calendar/Reminders use their enabled source filters. Mail: " + model.mailCoverage)
                        ForEach(NativeLearningRules.kinds,id:\.rawValue) { kind in
                            Text(NativeSourceLearningService.title(kind) + " memory: " + model.nativeSourceLearning.status(kind,model:model))
                        }
                        let access=model.learningRuntime().whatsappLearningAccess
                        Text("WhatsApp: \(access.enabled ? access.chats.count : 0) selected chats · PA reads \(access.enabled ? "on" : "off") · learning \(access.enabled && access.learnContext == true ? "on" : "off")").font(.caption)
                        Text("These are current controls and cached coverage. Receiving content does not mean it has been assessed or remembered. No sources are refreshed by this view.").font(.caption).foregroundStyle(.secondary)
                    }.font(.callout).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            DisclosureGroup("Saved and excluded records") {
            VStack(alignment:.leading,spacing:8) {
                Picker("Record status",selection:$filter) {
                    Text("All statuses").tag(Optional<MemoryAvailability>.none)
                    ForEach(MemoryAvailability.allCases) { status in Text("\(status.title) (\(rows.filter{$0.availability == status}.count))").tag(Optional(status)) }
                }
                Text("Availability below is evaluated with today's access. The memory toggle pauses all use without changing these saved states.").font(.caption).foregroundStyle(.secondary)
                ForEach(rows.filter{filter == nil || $0.availability == filter}) { row in
                    Button { inspect(row.record) } label: {
                        VStack(alignment:.leading,spacing:4) { Text(row.record.text).foregroundStyle(.primary);Text(row.availability.title+" · "+row.availability.explanation).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9))
                    }.buttonStyle(.plain)
                }
            }
            }
            VStack(alignment:.leading,spacing:9) {
                Text("Try recall locally").font(.headline)
                Text("Recall Focus: "+(focus.isEmpty ? "All life areas" : focus.map(\.title).joined(separator:", "))).font(.caption).foregroundStyle(.secondary)
                TextField("For example: what do I know about Orion?",text:$query)
                let selection=memory.selection(registration,conversationID:topic,includeTopics:true,query:query,focus:focus)
                Text("\(selection.records.count) selected from \(selection.eligibleCount) available · up to 40 facts / 20 KB").font(.caption.weight(.medium))
                Text("No AI request. This previews saved-fact selection for this question and Focus. Replies also receive bounded Life notebook context and can make permitted tool reads. New replies have their own Context details.").font(.caption).foregroundStyle(.secondary)
                ForEach(selection.records.compactMap{$0["id"].flatMap(UUID.init(uuidString:))},id:\.self) { id in
                    if let record=rows.first(where:{$0.id == id})?.record {
                        Button { inspect(record) } label: { VStack(alignment:.leading,spacing:4) { Text(record.text);Text((selection.reasons[id] ?? []).joined(separator:" · ")).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,alignment:.leading) }.buttonStyle(.plain).padding(.vertical,4)
                    }
                }
            }
        }
    }
    private func layer(_ title:String,_ text:String,_ icon:String)->some View {
        HStack(alignment:.top,spacing:10) { Image(systemName:icon).frame(width:22);VStack(alignment:.leading,spacing:3) { Text(title).font(.callout.weight(.medium));Text(text).font(.caption).foregroundStyle(.secondary) } }
    }
}

struct PAMemoryEvidenceView:View {
    var record:PAMemory
    var sourcePermitted:Bool
    var body:some View {
        DisclosureGroup("Evidence and dates") {
            VStack(alignment:.leading,spacing:8) {
                Text(record.attribution+" · "+record.provenance).font(.caption)
                if record.reviewPreference == true {
                    Text(record.reviewInterpretation == nil ? "Review preference" : "Review preference · learned from your feedback").font(.caption)
                    if let about=record.reviewContext {Text("About: "+about).font(.caption)}
                    if let original=record.reviewFeedback,record.reviewInterpretation != nil {Text("Your feedback: “"+original+"”").textSelection(.enabled)}
                    if let context=record.reviewInterpretation {Text("Email context: "+context.subject+" · "+context.sender).font(.caption);Text(context.humanEdited ? "Preference edited by you" : "Interpretation by "+context.model).font(.caption)}
                }
                if record.source == nil,let evidence=record.evidence { Text("“"+evidence+"”").textSelection(.enabled) }
                if record.source != nil {
                    if sourcePermitted && record.sourceInvalidation != .forgotten {
                        ForEach(Array(record.allSourceEvidence.enumerated()),id:\.offset) { _,evidence in
                            VStack(alignment:.leading,spacing:3) {
                                Text(evidence.label+" · "+evidence.identity.kind.rawValue.capitalized).font(.caption.weight(.medium))
                                Text("“"+evidence.quote+"”").textSelection(.enabled)
                                if let date=evidence.sourceDate { Text("Message date: "+date.formatted(date:.abbreviated,time:.shortened)).font(.caption) }
                                Text("Observed: "+evidence.observed.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                                DisclosureGroup("Saved identity") { Text("Item: "+evidence.identity.itemID+"\nVersion: "+evidence.revision).font(.caption2).textSelection(.enabled) }.font(.caption)
                            }
                        }
                    } else {
                        Text("Quoted source text is unavailable under current source access; excluded from PA recall.").font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Retained evidence metadata") {
                            ForEach(Array(record.allSourceEvidence.enumerated()),id:\.offset) { _,evidence in
                                Text(evidence.identity.kind.rawValue.capitalized+" · item "+evidence.identity.itemID+" · version "+evidence.revision).font(.caption2).textSelection(.enabled)
                                if let date=evidence.sourceDate { Text("Message date: "+date.formatted(date:.abbreviated,time:.shortened)).font(.caption) }
                                Text("Observed: "+evidence.observed.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                            }
                        }.font(.caption)
                    }
                }
                if let date=record.sourceDate,record.source == nil { Text("Statement date: "+date.formatted(date:.abbreviated,time:.shortened)).font(.caption) }
                Text("Saved: "+record.created.formatted(date:.abbreviated,time:.shortened)+" · reviewed: "+record.reviewed.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                if let retired=record.retiredAt { Text("Retired from recall: "+retired.formatted(date:.abbreviated,time:.shortened)).font(.caption) }
                if let state=record.sourceState { Text("Source reports: "+state.rawValue+". Apple task status is separate.").font(.caption) }
                Text("Memory ID: "+record.id.uuidString).font(.caption2).textSelection(.enabled)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,6)
        }.font(.callout)
    }
}

private struct PAContextPageInspection: Identifiable {
    let id = UUID()
    let pageID: String?
}

struct PAContextCaptureView:View {
    var capture:PAContextCapture
    var model:DashboardModel
    var registration:String
    @State private var pageInspection: PAContextPageInspection?
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Context for this reply").font(.title2.weight(.semibold));Spacer();Button("Done") { dismiss() } }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("Prepared "+capture.captured.formatted(date:.abbreviated,time:.shortened)+" · "+capture.model).font(.caption)
                    Text("A record of prepared inputs and attempted tools, not proof the model relied on every fact or that an action succeeded. Inspect saved receipts for verified changes.").font(.callout).foregroundStyle(.secondary)
                    lookupHistory
                    Text("Focus: "+(capture.focusAreas.map{$0.isEmpty ? "All life areas" : $0.map(\.title).joined(separator:", ")} ?? "Legacy thread")).font(.callout)
                    if let purpose=capture.selectionPurpose {
                        Text("Selection purpose: "+purpose.replacingOccurrences(of:"Conversation",with:" conversation").replacingOccurrences(of:"Read",with:" read")).font(.caption)
                    }
                    if capture.usedFollowupContext == true {Text("The preceding human request helped resolve this follow-up.").font(.caption)}
                    if let bytes = capture.contextGuideBytes, let fingerprint = capture.contextGuideFingerprint {
                        Text("Starting guide: \(bytes) UTF-8 bytes · version \(String(fingerprint.prefix(12))). The trace stores its fingerprint, not its text.").font(.caption)
                    }
                    if let hints=capture.sourceHints,!hints.isEmpty {Text("Relevant source hints: "+hints.joined(separator:", ")+". Actual tool attempts are listed below.").font(.caption)}
                    initialMemoryContext
                    if !capture.notebookMemoryIDs.isEmpty {
                        facts("Recorded relationship evidence",capture.notebookMemoryIDs,caption:"Supporting identities retained by the project/relationship context")
                    }
                    if !capture.consultedMemoryIDs.isEmpty {
                        facts("Additional supporting evidence",capture.consultedMemoryIDs,caption:"Original records read directly or backing pages opened through tools; this is not a list of newly saved facts")
                    }
                    if let pageIDs = capture.contextPageIDs, !pageIDs.isEmpty {
                        Button("Inspect context pages (\(pageIDs.count) initially prepared)") { pageInspection = .init(pageID: nil) }
                            .help("Opens current page versions and their history. The trace stores identities, not another copy of their text.")
                    }
                    Text("\(capture.workspaceIDs.count) workspace items · \(capture.historyTurnIDs.count) dialogue turns, \(capture.excerptedHistoryIDs.count) excerpted").font(.callout)
                    Text(capture.sourceSnapshotIncluded ? "A permitted cached source snapshot was prepared (\(capture.sourceSnapshotBytes) UTF-8 bytes). Source bodies are not duplicated in this trace." : "No cached source snapshot was prepared.").font(.callout)
                    if capture.profileSetup { Text("Profile interview: memory-only tools; no cached source snapshot or Apple changes.").font(.caption) }
                    if let notes=capture.preparationNotes,!notes.isEmpty { DisclosureGroup("Tool preparation and action checks") {ForEach(notes,id:\.self) {Text($0).font(.caption)}} }
                    if !capture.attemptedTools.isEmpty { Text("Tools attempted: "+capture.attemptedTools.map{$0.replacingOccurrences(of:"_",with:" ")}.joined(separator:", ")).font(.callout) }
                    Text("PA preferences, the local clock and assistant/tool instructions are also prepared. The trace does not reveal model reasoning or claim which input influenced the answer.").font(.caption).foregroundStyle(.secondary)
                    Text("Facts below show their current version and availability. Corrected or forgotten facts can differ from what was prepared then. Search terms and filters are saved locally for newer replies; source bodies, full tool arguments and model reasoning are not copied here. Older replies have no retroactive search history.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.padding(24).frame(width:620,height:650)
            .sheet(item: $pageInspection) { request in ContextPagesView(model: model, registration: registration, pageID: request.pageID) }
    }
    private func lookupAvailable(_ fingerprint: String?, tool: String) -> Bool {
        guard let fingerprint, (capture.registration ?? registration) == model.chatGPT.activeID else { return false }
        return fingerprint == model.assistantLookupAccess(tool)
    }
    @ViewBuilder private var initialMemoryContext: some View {
        if let direct = capture.directMemoryIDs {
            if direct.isEmpty {
                Text("No separate saved-fact list was supplied.").font(.callout)
            } else {
                facts("Original facts supplied directly",direct,caption:"\(direct.count) original records supplied for this purpose-specific request")
            }
            if let supporting = capture.pageSupportingMemoryIDs, !supporting.isEmpty {
                facts("Evidence behind page context",supporting,caption:"Original records validating pages and working changes. These evidence links are separate from a direct feed of fact records.")
            }
        } else {
            facts("Supporting records for this older reply",capture.memoryIDs,caption:"This older trace combines directly supplied facts with page evidence and cannot distinguish them retrospectively.")
        }
    }
    private var lookupHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What 3PO looked up").font(.headline)
            if let query = capture.retrievalQuery {
                if lookupAvailable(capture.retrievalAccess, tool: "read_context_page") {
                    Text("Starting context for “" + query + "”").textSelection(.enabled)
                    Text("\(capture.contextPageIDs?.count ?? 0) context pages prepared" + (capture.contextGuideBytes != nil ? ", alongside the starting guide." : ".")).font(.caption).foregroundStyle(.secondary)
                } else { Text("Starting context search is unavailable under the current account or access choices.").font(.caption).foregroundStyle(.secondary) }
            }
            if capture.directMemoryIDs != nil, let pages = capture.contextPageIDs, !pages.isEmpty {
                Text("Pages supplied").font(.subheadline.weight(.semibold))
                if lookupAvailable(capture.retrievalAccess, tool: "read_context_page") {
                    ForEach(pages, id: \.self) { pageLink($0) }
                } else { Text("Page links are unavailable under the current account or access choices.").font(.caption).foregroundStyle(.secondary) }
            }
            if let lookups = capture.lookups {
                if lookups.isEmpty { Text("No additional lookups were recorded for this reply.").font(.caption).foregroundStyle(.secondary) }
                ForEach(lookups) { lookup in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(lookup.title).font(.subheadline.weight(.semibold))
                        if lookupAvailable(lookup.accessFingerprint, tool: lookup.tool) {
                            if let query = lookup.query, !query.isEmpty { Text("“" + query + "”").textSelection(.enabled) }
                            ForEach(Array(lookup.filters.enumerated()), id: \.offset) { _, filter in Text(filter).font(.caption).foregroundStyle(.secondary) }
                            if let id = lookup.targetID, lookup.tool == "read_context_page" { pageLink(id) }
                            if let id = lookup.targetID, lookup.tool == "search_whatsapp" {
                                Text("Chat: " + (model.whatsapp.chats.first { $0.id == id }?.name ?? "Selected chat")).font(.caption).foregroundStyle(.secondary)
                            }
                            if let id = lookup.targetID.flatMap(UUID.init(uuidString:)), lookup.tool == "read_life_items" {
                                Text("Space: " + (model.assistant.projects.items(registration, includeTopics: true).first { $0.id == id }?.title ?? "Unavailable space")).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach((lookup.pageIDs ?? []).filter { $0 != lookup.targetID }, id: \.self) { id in pageLink(id) }
                            Text(lookupOutcome(lookup)).font(.caption).foregroundStyle(lookup.status == "failed" ? Color.orange : Color.secondary)
                        } else { Text("Search details are unavailable under the current account or source access.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            } else { Text(capture.registration == nil ? "Search terms were not recorded for this older reply. Its prepared context and attempted tools are listed below." : "No additional lookups were recorded for this reply.").font(.caption).foregroundStyle(.secondary) }
            if let omitted = capture.omittedLookups, omitted > 0 { Text("\(omitted) earlier lookups omitted from this bounded history.").font(.caption).foregroundStyle(.secondary) }
            Text("Results are bounded. A completed lookup does not imply every source was searched.").font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }
    private func pageLink(_ id: String) -> some View {
        let topic = id.hasPrefix("area:") ? ContextTopicRoute.named(String(id.dropFirst(5)))?.title : nil
        let page = model.contextPages.pages(registration: registration).first { $0.id == id }
        let humanProject = page.flatMap { $0.kind == .project ? UUID(uuidString: $0.key) : nil }.flatMap { project in model.assistant.projects.items(registration, includeTopics: true).first { $0.id == project }?.title }
        let knownTopic = page.flatMap { $0.kind == .topic ? ContextTopicRoute.named($0.key)?.title : nil }
        let overview = page?.kind == .overview ? "Overview" : nil
        let humanTitle = page.flatMap { $0.owner == .human ? $0.title : nil }
        let title = ContextInstructionRoute.all.first(where: { $0.id == id })?.title ?? topic ?? humanProject ?? knownTopic ?? overview ?? humanTitle ?? "Context page"
        return Button("Open “" + title + "”") { pageInspection = .init(pageID: id) }.buttonStyle(.link).font(.caption)
    }
    private func lookupOutcome(_ lookup: AssistantLookupTrace) -> String {
        switch lookup.status {
        case "failed": return "Lookup failed"
        case "stopped": return "Lookup stopped"
        case "unavailable": return "Requested context was unavailable"
        case "running": return "Lookup unfinished; no completed result recorded"
        default:
            guard let count = lookup.resultCount else { return "Lookup completed" }
            let unit = switch lookup.tool {
            case "search_mail", "continue_mail": "emails returned"
            case "read_context_page": "context records returned"
            case "read_memory": "supporting facts returned"
            case "read_life_notebook": "supporting records returned, with bounded area notes"
            case "read_life_items": "project records returned, including parent context"
            case "read_calendar": "calendar occurrences returned"
            case "read_reminders": "incomplete reminders returned"
            case "search_whatsapp": "messages returned"
            case "list_whatsapp_chats": "selected chats returned"
            default: "results returned"
            }
            return "\(count) " + unit
        }
    }
    private func facts(_ title:String,_ ids:[UUID],caption:String)->some View {
        DisclosureGroup(title+" (\(ids.count))") {
            VStack(alignment:.leading,spacing:8) {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                let rows=MemoryInspection.rows(model.assistant.memory.records,permitted:Set(model.assistant.memory.permittedRecords.map(\.id)),registration:registration)
                ForEach(ids,id:\.self) { id in
                    if let row=rows.first(where:{$0.id == id}) {
                        VStack(alignment:.leading,spacing:4) { Text(row.record.source != nil && row.availability == .sourceUnavailable ? "Source-derived fact unavailable" : row.record.text);Text(row.availability.title).font(.caption).foregroundStyle(.secondary);PAMemoryEvidenceView(record:row.record,sourcePermitted:model.assistant.memory.permittedRecords.contains{$0.id == id}) }.padding(8)
                    } else { Text("Forgotten or unavailable record · "+id.uuidString).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }
}
