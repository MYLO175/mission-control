import SwiftUI

struct NativeItemEditor: View {
    @Bindable var model: DashboardModel
    var target: NativeEditTarget
    var proposedMove: NativeEventMoveProposal? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: NativeEditDetails?
    @State private var edited: NativeEditDetails?
    @State private var sources: [SourceOption] = []
    @State private var loading = true
    @State private var error: String?
    @State private var saving = false
    @State private var dateSelected = false
    @State private var changeScope: NativeChangeScope = .occurrence
    @State private var showingDelete = false
    @State private var deleteRequestID = UUID()
    private var creation: NativeCreationRequest? { if case .create(let request) = target { return request }; return nil }
    private var canCreate: Bool { creation.map { !($0.requiresDateSelection) || dateSelected } ?? true }
    private var review:NativeDateReview? { switch target {case .reviewEvent(_,let value),.reviewReminder(_,let value):return value;default:return nil} }
    private var isEvent: Bool { switch target { case .event,.reviewEvent: return true; case .reminder,.reviewReminder: return false; case .create(let request): return request.kind == .event } }
    private func field<Value>(_ path: WritableKeyPath<NativeEditDetails,Value>, fallback: Value) -> Binding<Value> {
        Binding(get:{ edited?[keyPath:path] ?? fallback },set:{ edited?[keyPath:path] = $0 })
    }
    private func eventDate(_ path: WritableKeyPath<NativeEditDetails,Date>) -> Binding<Date> {
        Binding(get:{ edited?[keyPath:path] ?? .now },set:{
            if path == \NativeEditDetails.start, let item = edited { edited = NativeEditRules.movingStart(item,to:$0) }
            else { edited?[keyPath:path] = $0 }
            dateSelected = true
        })
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Label(creation == nil ? (isEvent ? "Event details" : "Reminder details") : (isEvent ? "New event" : "New reminder"),systemImage:isEvent ? "calendar" : "checklist").font(.title2.weight(.semibold)); Spacer(); if loading || saving { ProgressView().controlSize(.small) } }
            if let request = creation, let claim = model.nativeCreations.state.claims[request.key] {
                if let receipt = claim.receipt { Label("Already created: " + receipt.title + " · " + receipt.destination,systemImage:"checkmark.circle").font(.callout) }
                else { Text("A previous save needs checking in Apple Calendar or Reminders. It will not be repeated.").font(.callout).foregroundStyle(.orange) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let baseline, let edited {
                if let evidence = creation?.evidence { Text(evidence).font(.callout).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled) }
                if creation?.suggestedHasTime == true,creation?.suggestedEnd == nil,isEvent { Text("The source gives a deadline, not a duration. This is a 15-minute calendar marker; adjust it before approving.").font(.caption).foregroundStyle(.secondary) }
                if !canCreate { Text("Choose the event date and time from the email before creating it. The suggested form is not a confirmed booking.").font(.caption).foregroundStyle(.secondary) }
                if !baseline.writable { Label("This source is read-only.",systemImage:"lock").font(.callout).foregroundStyle(.secondary) }
                else if baseline.recurring && isEvent {
                    Picker("Apply changes to",selection:$changeScope) { Text("Only this event").tag(NativeChangeScope.occurrence);Text("This and all future events").tag(NativeChangeScope.futureEvents) }
                    Text("Earlier events stay unchanged. Repeat-pattern changes require this and all future events. Series changes cannot be undone here.").font(.caption).foregroundStyle(.secondary)
                } else if baseline.recurring { Text("Edits apply to the repeating reminder. Deleting removes that reminder and its future repeats. Series changes cannot be undone here.").font(.caption).foregroundStyle(.secondary) }
                if proposedMove != nil { Text("Review the proposed time below. The event keeps its duration and is only moved when you save.").font(.callout).foregroundStyle(.secondary) }
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if let evidence=review?.evidence {Text(evidence).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)}
                        TextField("Title",text:field(\.title,fallback:"")).textFieldStyle(.roundedBorder)
                        Picker(isEvent ? "Calendar" : "List",selection:field(\.sourceID,fallback:baseline.sourceID)) {
                            ForEach(sources.filter { $0.writable || $0.id == baseline.sourceID }) { Text($0.label + ($0.writable ? "" : " · Read-only")).tag($0.id) }
                        }.disabled(baseline.recurring && isEvent && changeScope == .occurrence)
                        if isEvent {
                            Toggle("All day",isOn:Binding(get:{ self.edited?.allDay ?? false },set:{ enabled in if let value = self.edited { self.edited = NativeEditRules.allDay(value,enabled:enabled) } }))
                            DatePicker("Starts",selection:eventDate(\.start),displayedComponents:edited.allDay ? .date : [.date,.hourAndMinute])
                            if edited.allDay {
                                DatePicker("Last day",selection:Binding(get:{ Calendar.current.date(byAdding:.day,value:-1,to:self.edited?.end ?? .now)! },set:{ self.edited?.end = Calendar.current.date(byAdding:.day,value:1,to:Calendar.current.startOfDay(for:$0))!; dateSelected = true }),displayedComponents:.date)
                            } else { DatePicker("Ends",selection:eventDate(\.end),displayedComponents:[.date,.hourAndMinute]) }
                            TextField("Location",text:field(\.location,fallback:"")).textFieldStyle(.roundedBorder)
                        } else {
                            Toggle("Due date",isOn:Binding(get:{ self.edited?.due != nil },set:{ enabled in self.edited?.due = enabled ? Calendar.current.startOfDay(for:.now) : nil; if !enabled { self.edited?.hasTime = false } }))
                            if edited.due != nil {
                                Toggle("Include time",isOn:field(\.hasTime,fallback:false))
                                DatePicker("Due",selection:Binding(get:{ self.edited?.due ?? .now },set:{ self.edited?.due = $0 }),displayedComponents:edited.hasTime ? [.date,.hourAndMinute] : .date)
                            }
                        }
                        NativeRepeatEditor(rules:field(\.recurrenceRules,fallback:[]))
                            .disabled(baseline.recurring && isEvent && changeScope == .occurrence)
                        TextField("URL",text:field(\.url,fallback:"")).textFieldStyle(.roundedBorder)
                        if !isEvent {
                            Picker("Priority",selection:field(\.priority,fallback:0)) { Text("None").tag(0);Text("High").tag(1);Text("Medium").tag(5);Text("Low").tag(9); if ![0,1,5,9].contains(edited.priority) { Text("Native priority \(edited.priority)").tag(edited.priority) } }
                        } else {
                            Picker("Availability",selection:field(\.availability,fallback:-1)) { Text("Not supported").tag(-1);Text("Busy").tag(0);Text("Free").tag(1);Text("Tentative").tag(2);Text("Unavailable").tag(3) }.disabled(baseline.availability == -1 && creation == nil)
                            Picker("Time zone",selection:field(\.timeZoneID,fallback:TimeZone.current.identifier)) { ForEach(TimeZone.knownTimeZoneIdentifiers,id:\.self) { Text($0).tag($0) } }.disabled(edited.allDay)
                        }
                        VStack(alignment:.leading,spacing:8) {
                            HStack { Text("Alerts").font(.subheadline.weight(.semibold));Spacer();Button("Add alert") { self.edited?.alarms.append(.init(offset:-900)) }.disabled(edited.alarms.count >= 8) }
                            ForEach(edited.alarms.indices,id:\.self) { index in
                                HStack {
                                    if edited.alarms[index].absolute != nil {
                                        DatePicker("At",selection:Binding(get:{self.edited?.alarms[index].absolute ?? .now},set:{self.edited?.alarms[index].absolute=$0}))
                                    } else {
                                        TextField("Minutes before",value:Binding(get:{-(self.edited?.alarms[index].offset ?? 0)/60},set:{self.edited?.alarms[index].offset = -$0*60}),format:.number)
                                    }
                                    Button("Remove") { self.edited?.alarms.remove(at:index) }
                                }
                            }
                            Text("Location, email and sound alerts already attached to the native item are preserved.").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Notes").font(.subheadline.weight(.semibold))
                        TextEditor(text:field(\.notes,fallback:"")).frame(minHeight:115).padding(5).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.primary.opacity(0.12)))
                        if isEvent && !edited.allDay || !isEvent && edited.hasTime { Text("Times shown in " + (isEvent ? edited.timeZoneID : TimeZone.current.identifier)).font(.caption).foregroundStyle(.secondary) }
                    }.disabled(!baseline.canEdit || saving).padding(2)
                        .environment(\.timeZone,isEvent ? (TimeZone(identifier:edited.timeZoneID) ?? .current) : .current)
                }
            } else if loading { Text("Loading the current Apple item…").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
            Spacer(minLength:0)
            Divider()
            HStack {
                Button(saving ? "Saving…" : "Cancel") { dismiss() }.disabled(saving).keyboardShortcut(.cancelAction)
                if error != nil && !saving { Button(creation == nil ? "Reload current item" : "Reset form") { Task { await load() } } }
                if creation == nil && review == nil, let baseline, baseline.writable {
                    Button("Delete…",role:.destructive) { showingDelete=true }.disabled(saving || model.writing || model.assistant.busy)
                }
                Spacer()
                if let baseline, baseline.canEdit {
                    Button(creation == nil ? (baseline.recurring && isEvent ? (changeScope == .futureEvents ? (review == nil ? "Save future events" : "Approve future events") : (review == nil ? "Save this event" : "Approve this event")) : (review == nil ? "Save changes" : "Approve changes")) : (isEvent ? "Create event" : "Create reminder")) { Task { await save() } }.keyboardShortcut(.defaultAction).disabled(saving || model.writing || model.assistant.busy || (creation == nil && edited == baseline) || !canCreate || (creation.map { !NativeCreationRules.allowed(model.nativeCreations.state,key:$0.key) } ?? false))
                }
            }
        }.padding(24).frame(width:520,height:620).interactiveDismissDisabled(saving).task { await load() }
            .confirmationDialog(isEvent ? "Delete event?" : "Delete reminder?",isPresented:$showingDelete,titleVisibility:.visible) {
                if let baseline {
                    if isEvent {
                        Button("Delete only this event",role:.destructive) { Task { await delete(.occurrence) } }
                        if baseline.recurring { Button("Delete all future events",role:.destructive) { Task { await delete(.futureEvents) } } }
                    } else { Button(baseline.recurring ? "Delete repeating reminder" : "Delete reminder",role:.destructive) { Task { await delete(baseline.recurring ? .reminderSeries : .occurrence) } } }
                }
                Button("Cancel",role:.cancel) {}
            } message: { Text("Deletion cannot be undone in 3PO. Deleting future events also removes this event; earlier events remain.") }

    }
    private func load() async {
        loading = true; error = nil; dateSelected = false; defer { loading = false }
        guard !ProcessInfo.processInfo.arguments.contains("--sample") else { error = "Sample items are read-only; open the normal app to edit Apple items."; return }
        do {
            let session:NativeEditSession
            #if DEBUG
            if let preview=ReviewInboxEvaluation.previewSession(target) {session=preview}
            else {session=try await model.eventKit.editSession(target)}
            #else
            session=try await model.eventKit.editSession(target)
            #endif
            try Task.checkCancellation(); baseline = session.item; edited = session.item; changeScope = session.item.kind == .reminder && session.item.recurring ? .reminderSeries : .occurrence; sources = session.sources
            if let creation,creation.suggestedStart != nil { edited=NativeCreationRules.applyingSuggestion(creation,to:session.item);dateSelected=true }
            if let proposedMove { edited = try NativeEditRules.moved(session.item,proposal:proposedMove) }
            if let review {
                guard review.registration == model.chatGPT.activeID,model.proactive.canReview(review.discoveryID,model:model),session.item.modified == review.expectedModified else { throw ActionFailure.message("The proposal, source or Apple item changed. Return to Review inbox for current work.") }
                edited=try review.applying(to:session.item)
            }
        } catch is CancellationError {} catch {if review != nil {baseline=nil;edited=nil};self.error = error.localizedDescription }
    }
    private func delete(_ scope: NativeChangeScope) async {
        guard let baseline else { return }
        saving=true;error=nil;defer {saving=false}
        do { try await model.deleteNativeItem(baseline:baseline,scope:scope,requestID:deleteRequestID);dismiss() }
        catch { self.error=error.localizedDescription }
    }
    private func save() async {
        guard let baseline, let edited else { return }
        saving = true; error = nil; defer { saving = false }
        do {
            if let request = creation { try await model.createNativeItem(request,baseline:baseline,edited:edited,dateSelected:dateSelected) }
            else { try await model.saveNativeEdit(baseline:baseline,edited:edited,scope:changeScope,review:review) }
            dismiss()
        }
        catch { self.error = error.localizedDescription }
    }
}
