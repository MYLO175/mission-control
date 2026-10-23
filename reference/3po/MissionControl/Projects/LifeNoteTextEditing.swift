import SwiftUI
import AppKit
import Observation

@MainActor enum LifeNoteText {
    static func font(size:Double=13,bold:Bool=false,italic:Bool=false)->NSFont {
        var font=NSFont.systemFont(ofSize:size,weight:bold ? .bold : .regular)
        if italic {font=NSFontManager.shared.convert(font,toHaveTrait:.italicFontMask)}
        return font
    }
    static func attributed(_ text:String,formatting:LifeNoteFormatting?)->NSAttributedString {
        let value=NSMutableAttributedString(string:text,attributes:[.font:font()])
        if let formatting,formatting.valid(for:text) {
            for run in formatting.runs {value.addAttribute(.font,value:font(size:run.size,bold:run.bold,italic:run.italic),range:NSRange(location:run.location,length:run.length))}
        }
        paragraphs(value)
        return value
    }
    static func formatting(_ value:NSAttributedString)->LifeNoteFormatting {
        var runs:[LifeNoteRun]=[]
        value.enumerateAttribute(.font,in:NSRange(location:0,length:value.length)) {attribute,range,_ in
            let font=attribute as? NSFont ?? font()
            let traits=NSFontManager.shared.traits(of:font)
            runs.append(.init(location:range.location,length:range.length,size:Double(min(72,max(9,font.pointSize))),bold:traits.contains(.boldFontMask),italic:traits.contains(.italicFontMask)))
        }
        return .init(length:value.length,runs:runs)
    }
    static func paragraphs(_ value:NSMutableAttributedString) {
        let text=value.string as NSString
        var location=0
        while location < text.length {
            let range=text.paragraphRange(for:NSRange(location:location,length:0))
            let style=NSMutableParagraphStyle();style.paragraphSpacing=5
            if text.substring(with:range).hasPrefix("•\t") {
                style.headIndent=20;style.tabStops=[NSTextTab(textAlignment:.left,location:20)]
            }
            value.addAttribute(.paragraphStyle,value:style,range:range);location=NSMaxRange(range)
        }
    }
}

@MainActor @Observable final class LifeNoteEditorState {
    var text:String
    var formatting:LifeNoteFormatting?
    var pointSize=13
    var bold=false
    var italic=false
    var bulleted=false
    @ObservationIgnored weak var editor:LifeNoteTextView?
    init(text:String,formatting:LifeNoteFormatting?) {self.text=text;self.formatting=formatting}
    func refresh(_ view:LifeNoteTextView) {
        text=view.string;formatting=LifeNoteText.formatting(view.attributedString())
        let font=view.typingAttributes[.font] as? NSFont ?? LifeNoteText.font()
        let traits=NSFontManager.shared.traits(of:font)
        pointSize=Int(font.pointSize.rounded());bold=traits.contains(.boldFontMask);italic=traits.contains(.italicFontMask)
        let range=(view.string as NSString).paragraphRange(for:view.selectedRange())
        bulleted=(view.string as NSString).substring(with:range).hasPrefix("•\t")
    }
    func toggleBold() {editor?.changeFont(bold:!bold)}
    func toggleItalic() {editor?.changeFont(italic:!italic)}
    func setSize(_ size:Int) {editor?.changeFont(size:Double(size))}
    func toggleBullets() {editor?.toggleBullets()}
}

struct LifeNoteNativeEditor:NSViewRepresentable {
    let state:LifeNoteEditorState
    func makeCoordinator()->Coordinator {Coordinator(state)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        let view=LifeNoteTextView();view.isRichText=true;view.importsGraphics=false;view.allowsUndo=true
        view.drawsBackground=false;view.textColor = .labelColor;view.font=LifeNoteText.font()
        view.isVerticallyResizable=true;view.isHorizontallyResizable=false
        view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true
        view.textContainerInset=NSSize(width:12,height:12);view.textContainer?.lineFragmentPadding=0
        view.textStorage?.setAttributedString(LifeNoteText.attributed(state.text,formatting:state.formatting))
        var typing=state.text.isEmpty ? [.font:LifeNoteText.font()] : view.attributedString().attributes(at:0,effectiveRange:nil)
        typing[.foregroundColor]=NSColor.labelColor;view.typingAttributes=typing
        view.delegate=context.coordinator;view.state=state;state.editor=view
        view.setAccessibilityLabel("Note text")
        view.setAccessibilityHelp("Rich text note. Command B for bold, Command I for italics. Type an asterisk and space to start a bullet list.")
        scroll.documentView=view
        DispatchQueue.main.async {view.window?.makeFirstResponder(view);state.refresh(view)}
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {}
    final class Coordinator:NSObject,NSTextViewDelegate {
        let state:LifeNoteEditorState
        init(_ state:LifeNoteEditorState) {self.state=state}
        func textDidChange(_ notification:Notification) {if let view=notification.object as? LifeNoteTextView {state.refresh(view)}}
        func textViewDidChangeSelection(_ notification:Notification) {if let view=notification.object as? LifeNoteTextView {state.refresh(view)}}
    }
}

@MainActor final class LifeNoteTextView:NSTextView {
    weak var state:LifeNoteEditorState?
    override func keyDown(with event:NSEvent) {
        if event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "b":changeFont(bold:!(state?.bold ?? false));return
            case "i":changeFont(italic:!(state?.italic ?? false));return
            default:break
            }
        }
        super.keyDown(with:event)
    }
    func changeFont(size:Double?=nil,bold:Bool?=nil,italic:Bool?=nil) {
        let selected=selectedRange()
        func changed(_ current:NSFont)->NSFont {
            let traits=NSFontManager.shared.traits(of:current)
            return LifeNoteText.font(size:size ?? Double(current.pointSize),bold:bold ?? traits.contains(.boldFontMask),italic:italic ?? traits.contains(.italicFontMask))
        }
        if selected.length > 0 {
            let value=NSMutableAttributedString(attributedString:attributedString().attributedSubstring(from:selected))
            value.enumerateAttribute(.font,in:NSRange(location:0,length:value.length)) {attribute,range,_ in
                value.addAttribute(.font,value:changed(attribute as? NSFont ?? LifeNoteText.font()),range:range)
            }
            breakUndoCoalescing()
            guard shouldChangeText(in:selected,replacementString:nil) else {return}
            textStorage?.replaceCharacters(in:selected,with:value)
            didChangeText();setSelectedRange(selected)
        }
        var attributes=typingAttributes
        attributes[.font]=changed(attributes[.font] as? NSFont ?? LifeNoteText.font());typingAttributes=attributes
        state?.refresh(self);refocusAfterFormatting()
    }
    func toggleBullets() {
        let text=string as NSString,selected=selectedRange()
        let paragraphs=text.paragraphRange(for:selected)
        let original=text.substring(with:paragraphs)
        let lines=original.components(separatedBy:"\n")
        let nonempty=lines.filter{!$0.isEmpty}
        let remove = !nonempty.isEmpty && nonempty.allSatisfy{$0.hasPrefix("•\t")}
        let value=NSMutableAttributedString(attributedString:attributedString().attributedSubstring(from:paragraphs))
        // Edit from the end so existing fonts and earlier ranges keep their identity.
        var starts:[Int]=[],offset=0
        for line in lines {starts.append(offset);offset+=(line as NSString).length+1}
        for index in lines.indices.reversed() {
            if index == lines.count-1 && lines[index].isEmpty && original.hasSuffix("\n") {continue}
            if remove {if lines[index].hasPrefix("•\t") {value.deleteCharacters(in:NSRange(location:starts[index],length:2))}}
            else if !lines[index].hasPrefix("•\t") {value.insert(NSAttributedString(string:"•\t",attributes:typingAttributes),at:starts[index])}
        }
        LifeNoteText.paragraphs(value)
        super.insertText(value,replacementRange:paragraphs)
        if selected.length == 0 {setSelectedRange(NSRange(location:min(paragraphs.location+value.length,max(paragraphs.location,selected.location+(remove ? -2 : 2))),length:0))}
        else {setSelectedRange(NSRange(location:paragraphs.location,length:value.length))}
        state?.refresh(self);refocusAfterFormatting()
    }
    private func refocusAfterFormatting() {
        // Let the popup/menu consume its current key before returning to text input.
        DispatchQueue.main.async {[weak self] in
            guard let self,let window=self.window,window.isKeyWindow else {return}
            window.makeFirstResponder(self)
        }
    }
    override func insertText(_ insertString:Any,replacementRange:NSRange) {
        let insertion=(insertString as? String) ?? (insertString as? NSAttributedString)?.string
        let selected=replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if insertion == " ",selected.length == 0,!hasMarkedText() {
            let text=string as NSString,paragraph=text.paragraphRange(for:selected)
            let prefix=text.substring(with:NSRange(location:paragraph.location,length:selected.location-paragraph.location))
            if prefix == "*" || prefix == "-" {
                breakUndoCoalescing()
                super.insertText(NSAttributedString(string:"•\t",attributes:typingAttributes),replacementRange:NSRange(location:paragraph.location,length:prefix.utf16.count))
                return
            }
        }
        // Imported fonts are reduced to the supported size/bold/italic model; graphics stay out.
        if let rich=insertString as? NSAttributedString {
            let normalized=LifeNoteText.attributed(rich.string,formatting:LifeNoteText.formatting(rich))
            super.insertText(normalized,replacementRange:replacementRange)
        } else {super.insertText(insertString,replacementRange:replacementRange)}
    }
    override func insertNewline(_ sender:Any?) {
        let selected=selectedRange(),text=string as NSString
        let paragraph=text.paragraphRange(for:selected)
        let line=text.substring(with:paragraph).trimmingCharacters(in:.newlines)
        if selected.length == 0,selected.location >= paragraph.location+2,line.hasPrefix("•\t") {
            if line.dropFirst(2).trimmingCharacters(in:.whitespaces).isEmpty {
                super.insertText("",replacementRange:NSRange(location:paragraph.location,length:2))
                var attributes=typingAttributes;attributes[.paragraphStyle]=NSMutableParagraphStyle();typingAttributes=attributes
            } else {super.insertText(NSAttributedString(string:"\n•\t",attributes:typingAttributes),replacementRange:selected)}
        } else {super.insertNewline(sender)}
    }
    override func didChangeText() {
        if let textStorage {LifeNoteText.paragraphs(textStorage)}
        super.didChangeText()
    }
}
