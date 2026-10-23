import SwiftUI
import AppKit

/// A native plain-text editor retains standard selection, text paste and Undo.
/// Only image paste is intercepted; no clipboard reads occur on mount or refresh.
struct PAChatComposer: NSViewRepresentable {
    @Binding var text:String
    @Binding var focused:Bool
    @Binding var height:CGFloat
    var scope:String
    var enabled:Bool
    var textColor:NSColor
    var pasteImage:(NSPasteboard)->Void
    var submit:()->Void
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        let editor=PAComposerTextView();editor.delegate=context.coordinator;editor.isRichText=false;editor.importsGraphics=false;editor.allowsUndo=true
        editor.drawsBackground=false;editor.font = .systemFont(ofSize:NSFont.systemFontSize)
        editor.textContainerInset=NSSize(width:0,height:2);editor.isVerticallyResizable=true;editor.isHorizontallyResizable=false
        editor.autoresizingMask=[.width];editor.textContainer?.widthTracksTextView=true;editor.textContainer?.lineFragmentPadding=0
        editor.setAccessibilityLabel("PA message");editor.setAccessibilityHelp("Type a message or paste a screenshot. Press Return to send; Shift-Return for a new line.")
        scroll.documentView=editor;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let editor=scroll.documentView as? PAComposerTextView else { return }
        context.coordinator.parent=self
        if editor.scope != scope { editor.scope=scope;editor.undoManager?.removeAllActions() }
        if editor.string != text { editor.string=text;editor.undoManager?.removeAllActions() }
        editor.isEditable=enabled;editor.textColor=textColor
        editor.pasteImage=pasteImage;editor.submit=submit
        editor.focusChanged={ value in if focused != value { focused=value } }
        if focused && enabled && editor.window?.firstResponder !== editor {
            DispatchQueue.main.async { guard editor.scope == scope,editor.isEditable else { return };editor.window?.makeFirstResponder(editor) }
        }
        context.coordinator.measure(editor)
    }
    final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:PAChatComposer
        init(_ parent:PAChatComposer) { self.parent=parent }
        func textDidChange(_ notification:Notification) {
            guard let editor=notification.object as? PAComposerTextView else { return }
            parent.text=editor.string;measure(editor)
        }
        func measure(_ editor:NSTextView) {
            guard let layout=editor.layoutManager,let container=editor.textContainer else { return }
            layout.ensureLayout(for:container)
            let line=layout.defaultLineHeight(for:editor.font ?? NSFont.systemFont(ofSize:NSFont.systemFontSize))
            let value=min(line*4+4,max(22,layout.usedRect(for:container).height+4))
            if abs(parent.height-value)>0.5 { DispatchQueue.main.async { self.parent.height=value } }
        }
    }
}
final class PAComposerTextView:NSTextView {
    var scope=""
    var pasteImage:((NSPasteboard)->Void)?
    var submit:(()->Void)?
    var focusChanged:((Bool)->Void)?
    override var readablePasteboardTypes:[NSPasteboard.PasteboardType] { [.png,.tiff,NSPasteboard.PasteboardType("public.jpeg")]+super.readablePasteboardTypes }
    override func paste(_ sender:Any?) {
        guard isEditable else { return }
        if ChatImageStore.containsImage(.general) { pasteImage?(.general) } else { super.paste(sender) }
    }
    override func insertNewline(_ sender:Any?) {
        if NSApp.currentEvent?.modifierFlags.intersection([.shift,.option]).isEmpty == false { super.insertNewline(sender) }
        else { submit?() }
    }
    override func becomeFirstResponder()->Bool { let result=super.becomeFirstResponder();if result { focusChanged?(true) };return result }
    override func resignFirstResponder()->Bool { let result=super.resignFirstResponder();if result { focusChanged?(false) };return result }
}

struct PAImagePreview:View {
    var image:ChatImageAttachment
    var store:ChatImageStore
    var registration:String
    var compact=false
    @State private var loaded:NSImage?
    @State private var expanded=false
    var body:some View {
        Button { expanded=true } label: {
            if let loaded { Image(nsImage:loaded).resizable().scaledToFit().frame(maxWidth:compact ? 90 : 300,maxHeight:compact ? 64 : 190).clipShape(RoundedRectangle(cornerRadius:6)) }
            else { Label("Image unavailable",systemImage:"photo").font(.caption) }
        }.buttonStyle(.plain).disabled(loaded == nil).accessibilityLabel("Attached image, \(image.width) by \(image.height). Open preview")
        .task(id:registration+image.id.uuidString) { loaded=store.preview(image,registration:registration,maxDimension:compact ? 180 : 600) }
        .onChange(of:registration) { loaded=nil;expanded=false }
        .sheet(isPresented:$expanded) {
            VStack { if let full=store.preview(image,registration:registration,maxDimension:2400) { Image(nsImage:full).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity) };Button("Done") { expanded=false }.keyboardShortcut(.cancelAction) }
                .padding(16).frame(minWidth:400,idealWidth:800,maxWidth:1000,minHeight:300,idealHeight:650,maxHeight:800)
        }
    }
}
