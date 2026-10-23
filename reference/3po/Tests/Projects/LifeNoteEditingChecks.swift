import Foundation
import AppKit

@main struct LifeNoteEditingChecks {
    @MainActor static func main() throws {
        _=NSApplication.shared
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:600,height:400),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let editor=LifeNoteTextView(frame:NSRect(x:0,y:0,width:600,height:400))
        editor.isRichText=true;editor.allowsUndo=true;editor.importsGraphics=false
        window.contentView=editor;window.makeFirstResponder(editor)
        editor.undoManager?.groupsByEvent=false
        let state=LifeNoteEditorState(text:"",formatting:nil);state.editor=editor;editor.state=state
        func load(_ text:String,formatting:LifeNoteFormatting?=nil) {
            editor.textStorage?.setAttributedString(LifeNoteText.attributed(text,formatting:formatting))
            editor.typingAttributes=[.font:LifeNoteText.font()]
            editor.setSelectedRange(NSRange(location:0,length:0))
            if let manager=editor.undoManager {while manager.groupingLevel > 0 {manager.endUndoGrouping()};manager.removeAllActions();manager.beginUndoGrouping()}
            state.refresh(editor)
        }
        func traits(_ location:Int)->NSFontTraitMask {
            NSFontManager.shared.traits(of:editor.attributedString().attribute(.font,at:location,effectiveRange:nil) as! NSFont)
        }
        func undo() {
            guard let manager=editor.undoManager else {preconditionFailure("Native text Undo is unavailable")}
            editor.breakUndoCoalescing()
            while manager.groupingLevel > 0 {manager.endUndoGrouping()}
            precondition(manager.canUndo);manager.undo();manager.beginUndoGrouping();state.refresh(editor)
        }
        load("Design notes")
        editor.setSelectedRange(NSRange(location:0,length:6));state.refresh(editor)
        let boldKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"b",charactersIgnoringModifiers:"b",isARepeat:false,keyCode:11)!
        editor.keyDown(with:boldKey)
        precondition(editor.string == "Design notes" && traits(0).contains(.boldFontMask) && !traits(7).contains(.boldFontMask))
        undo()
        precondition(editor.string == "Design notes" && !traits(0).contains(.boldFontMask),"Formatting participates in native text Undo")
        editor.setSelectedRange(NSRange(location:7,length:5));state.refresh(editor)
        let italicKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"i",charactersIgnoringModifiers:"i",isARepeat:false,keyCode:34)!
        editor.keyDown(with:italicKey)
        precondition(traits(7).contains(.italicFontMask) && !traits(0).contains(.italicFontMask))
        editor.changeFont(size:22)
        precondition((editor.attributedString().attribute(.font,at:7,effectiveRange:nil) as! NSFont).pointSize == 22 && traits(7).contains(.italicFontMask))
        let rich=LifeNoteText.formatting(editor.attributedString())
        let restored=LifeNoteText.attributed(editor.string,formatting:rich)
        precondition(rich.valid(for:editor.string) && LifeNoteText.formatting(restored) == rich)
        load("")
        editor.insertText("*",replacementRange:NSRange(location:NSNotFound,length:0))
        editor.insertText(" ",replacementRange:NSRange(location:NSNotFound,length:0))
        editor.insertText("First",replacementRange:NSRange(location:NSNotFound,length:0))
        precondition(editor.string == "•\tFirst")
        editor.insertNewline(nil);editor.insertText("Second",replacementRange:NSRange(location:NSNotFound,length:0))
        precondition(editor.string == "•\tFirst\n•\tSecond")
        editor.insertNewline(nil);editor.insertNewline(nil)
        precondition(editor.string == "•\tFirst\n•\tSecond\n","Return on an empty bullet leaves the list")
        load("")
        editor.toggleBullets()
        precondition(editor.selectedRange().length == 0 && editor.selectedRange().location == 2)
        editor.insertText("Toolbar bullet",replacementRange:NSRange(location:NSNotFound,length:0))
        precondition(editor.string == "•\tToolbar bullet","Typing after the bullet button must keep its prefix")
        load("First\nSecond")
        editor.setSelectedRange(NSRange(location:0,length:12));editor.toggleBullets()
        precondition(editor.string == "•\tFirst\n•\tSecond")
        editor.toggleBullets()
        precondition(editor.string == "First\nSecond")
        load("•\tExisting")
        editor.insertNewline(nil)
        precondition(editor.string == "\n•\tExisting","Return before a marker must not duplicate it")
        load("One 🌱 idea")
        editor.setSelectedRange(NSRange(location:0,length:editor.attributedString().length));editor.changeFont(size:28,bold:true,italic:true)
        let unicode=LifeNoteText.formatting(editor.attributedString())
        precondition(unicode.valid(for:editor.string) && LifeNoteText.attributed(editor.string,formatting:unicode).string == "One 🌱 idea")
        load("")
        let pasted=NSAttributedString(string:"Large pasted text",attributes:[.font:NSFont.boldSystemFont(ofSize:120),.foregroundColor:NSColor.red])
        editor.insertText(pasted,replacementRange:NSRange(location:NSNotFound,length:0))
        let normalized=LifeNoteText.formatting(editor.attributedString())
        precondition(normalized.valid(for:editor.string) && normalized.runs.allSatisfy{$0.size <= 72})
        precondition(editor.attributedString().attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor != .red,"Imported colour does not override the workspace appearance")
        window.close()
        print("PASS: native selection formatting, Command-B/Command-I, text Undo, size/traits roundtrip, automatic/continued/ended bullets, toolbar bullets, selected paragraphs, Unicode and bounded pasted styles")
    }
}
