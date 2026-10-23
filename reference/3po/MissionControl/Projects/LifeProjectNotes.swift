import SwiftUI
import AppKit
import Observation

struct LifeNoteEditing:Identifiable {
    let id=UUID()
    let item:LifeItem
    /// The item's own ID denotes its original note; nil starts an additional note.
    let noteID:UUID?
    var note:LifeNote? { item.noteCards.first{$0.id == noteID} }
}

struct LifeNotesSection:View {
    @Bindable var model:DashboardModel
    let item:LifeItem
    var availableWidth:CGFloat
    var availableHeight:CGFloat
    var edit:(LifeNoteEditing)->Void
    @Environment(\.workspacePalette) private var palette
    @State private var error:String?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                Text("Notes").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { edit(.init(item:item,noteID:nil)) } label: {Image(systemName:"plus").frame(width:26,height:26).contentShape(Rectangle())}
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Add note").help("Add a note")
                    .disabled(model.assistant.projects.readOnly || item.registration != model.chatGPT.activeID)
            }
            if item.noteCards.isEmpty {
                Button { edit(.init(item:item,noteID:nil)) } label: {
                    Label("Add a note",systemImage:"plus").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth:.infinity,minHeight:72,alignment:.leading).padding(16)
                        .background(palette[.accent].opacity(0.06),in:RoundedRectangle(cornerRadius:12))
                }.buttonStyle(.plain).frame(maxWidth:320).disabled(model.assistant.projects.readOnly || item.registration != model.chatGPT.activeID)
            } else {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:ProjectNotesLayout.minimumWidth(availableWidth),maximum:360),spacing:14,alignment:.top)],alignment:.leading,spacing:14) {
                    ForEach(item.noteCards) { note in
                        LifeNoteCard(note:note,previewLimit:ProjectNotesLayout.previewHeight(availableHeight:availableHeight,width:availableWidth,count:item.noteCards.count),edit:{edit(.init(item:item,noteID:note.id))},remove:{remove(note)})
                    }
                }
            }
            if let error {Text(error).font(.caption).foregroundStyle(.orange)}
        }.padding(.top,10)
    }
    private func remove(_ note:LifeNote) {
        guard item.registration == model.chatGPT.activeID else {error="Account changed. Reopen this note.";return}
        var value=item
        if note.id == item.id {value.notes="";value.notesFormatting=nil}
        else {value.additionalNotes?.removeAll{$0.id == note.id}}
        do {_=try model.assistant.projects.save(value,expected:item.revision)}
        catch {self.error=error.localizedDescription}
    }
}

private struct LifeNoteCard:View {
    let note:LifeNote
    var previewLimit:CGFloat
    var edit:()->Void
    var remove:()->Void
    @Environment(\.workspacePalette) private var palette
    @State private var expanded=false
    @State private var naturalHeight:CGFloat=0
    private var text:Text {Text(AttributedString(LifeNoteText.attributed(note.text,formatting:note.formatting)))}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            Button(action:edit) {
                text.foregroundStyle(palette[.text].opacity(0.9)).fixedSize(horizontal:false,vertical:true)
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .onGeometryChange(for:CGFloat.self) {$0.size.height} action:{naturalHeight=$0}
                    .frame(height:expanded || naturalHeight == 0 ? nil : min(naturalHeight,previewLimit),alignment:.topLeading)
                    .clipped()
                    .frame(maxWidth:.infinity,minHeight:64,alignment:.topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Edit note").accessibilityValue(note.text).help("Click to edit note")
            HStack {
                if naturalHeight > previewLimit+1 {
                    Button(expanded ? "Show less" : "Show more") {expanded.toggle()}.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Menu {
                    Button("Edit note",action:edit)
                    Button("Delete note",role:.destructive,action:remove)
                } label:{Image(systemName:"ellipsis").frame(width:22,height:18)}
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(.secondary).accessibilityLabel("Note options")
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.topLeading)
            .background(palette[.accent].opacity(0.085),in:RoundedRectangle(cornerRadius:12))
            .overlay(alignment:.top) {RoundedRectangle(cornerRadius:1).fill(palette[.accent].opacity(0.2)).frame(height:2).padding(.horizontal,14).allowsHitTesting(false)}
    }
}

/// Native text selection, spelling, IME, paste and text Undo stay inside this editor.
struct LifeProjectNotesSheet:View {
    @Bindable var model:DashboardModel
    let capture:LifeNoteEditing
    @Environment(\.dismiss) private var dismiss
    @State private var editor:LifeNoteEditorState
    @State private var error:String?
    init(model:DashboardModel,capture:LifeNoteEditing) {
        self.model=model;self.capture=capture
        _editor=State(initialValue:LifeNoteEditorState(text:capture.note?.text ?? "",formatting:capture.note?.formatting))
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.firstTextBaseline) {
                Text(capture.note == nil ? "New note" : "Note").font(.title2.weight(.semibold))
                Spacer()
                Text(capture.item.title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing:6) {
                Picker("Text size",selection:Binding(get:{editor.pointSize},set:{editor.setSize($0)})) {
                    ForEach(Array(Set([11,13,15,18,22,28,36,editor.pointSize])).sorted(),id:\.self) {Text("\($0) pt").tag($0)}
                }.labelsHidden().frame(width:88).accessibilityLabel("Text size")
                Divider().frame(height:20).padding(.horizontal,5)
                formatButton("bold",label:"Bold",selected:editor.bold,shortcut:"⌘B") {editor.toggleBold()}
                formatButton("italic",label:"Italic",selected:editor.italic,shortcut:"⌘I") {editor.toggleItalic()}
                Divider().frame(height:20).padding(.horizontal,5)
                formatButton("list.bullet",label:"Bullet list",selected:editor.bulleted,shortcut:"* then Space") {editor.toggleBullets()}
                Spacer()
            }.padding(8).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:9))
            LifeNoteNativeEditor(state:editor)
                .frame(minHeight:260,maxHeight:.infinity)
                .background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(.secondary.opacity(0.15)))
            Text("⌘B bold   ·   ⌘I italic   ·   * then Space for bullets").font(.caption).foregroundStyle(.secondary)
            if let error {Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)}
            HStack {
                Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {save()}.keyboardShortcut("s",modifiers:.command)
                    .disabled(capture.item.registration != model.chatGPT.activeID || model.assistant.projects.readOnly || editor.text.count > 12000)
            }
        }.padding(24).frame(width:620,height:520)
    }
    private func formatButton(_ symbol:String,label:String,selected:Bool,shortcut:String,action:@escaping ()->Void)->some View {
        Button(action:action) {Image(systemName:symbol).font(.system(size:14,weight:.medium)).frame(width:30,height:28)
                .background(selected ? Color.accentColor.opacity(0.16) : .clear,in:RoundedRectangle(cornerRadius:5))}
            .buttonStyle(.plain).help(label+" ("+shortcut+")").accessibilityLabel(label).accessibilityValue(selected ? "On" : "Off")
    }
    private func save() {
        guard capture.item.registration == model.chatGPT.activeID else {error="Account changed; your draft has not been saved.";return}
        guard editor.text.count <= 12000 else {error="Keep each note within 12,000 characters.";return}
        var value=capture.item
        if let id=capture.noteID {
            if id == value.id {value.notes=editor.text;value.notesFormatting=editor.formatting}
            else if let index=value.additionalNotes?.firstIndex(where:{$0.id == id}) {
                value.additionalNotes?[index].text=editor.text;value.additionalNotes?[index].formatting=editor.formatting
            } else {error="This note is no longer available. Your draft is kept.";return}
        } else if !editor.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            // A previously empty legacy note field remains the first note, without migration.
            if value.notes.isEmpty {value.notes=editor.text;value.notesFormatting=editor.formatting}
            else {
                var notes=value.additionalNotes ?? []
                notes.append(.init(text:editor.text,formatting:editor.formatting));value.additionalNotes=notes
            }
        } else {dismiss();return}
        do {_=try model.assistant.projects.save(value,expected:capture.item.revision,notesFormattingIsCurrent:true);dismiss()}
        catch {self.error=error.localizedDescription}
    }
}
