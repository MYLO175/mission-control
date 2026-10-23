#if DEBUG
import AppKit
import SwiftData
import SwiftUI

@MainActor enum ChatImageEvaluation {
    static func fixture() throws -> Data {
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:700,pixelsHigh:360,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill();NSRect(x:0,y:0,width:700,height:360).fill()
        ("WILLOW 731" as NSString).draw(at:NSPoint(x:35,y:260),withAttributes:[.font:NSFont.boldSystemFont(ofSize:60),.foregroundColor:NSColor.black])
        NSColor.systemGreen.setFill();let triangle=NSBezierPath();triangle.move(to:NSPoint(x:130,y:210));triangle.line(to:NSPoint(x:40,y:45));triangle.line(to:NSPoint(x:220,y:45));triangle.close();triangle.fill()
        NSColor.systemPurple.setFill();NSBezierPath(ovalIn:NSRect(x:390,y:50,width:155,height:155)).fill()
        guard let data=bitmap.representation(using:.png,properties:[:]) else { throw ChatImageFailure.format };return data
    }
    static func run(_ model:DashboardModel) async throws->[String:Any] {
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=ChatImageStore(container:container),account=model.chatGPT.activeID,selected=model.chatGPT.selectedModel
        let image=try store.add(fixture(),registration:account)
        var first=AssistantTurn(role:"user",content:"Read the large label at the top. Reply with the label only.",completed:true);first.images=[image]
        let instructions="You are analysing fictional image fixtures. Answer the current question from the image. No tools or source access."
        let one=try store.input([first],currentUserID:first.id,registration:account)
        try PAToolProtocol.boundedInput(one)
        let result=try await model.chatGPT.toolResponse(input:one,instructions:instructions,tools:[],model:selected,purpose:.diagnostic,onDelta:{_ in})
        guard model.chatGPT.activeID == account,model.chatGPT.selectedModel == selected else { throw ChatImageFailure.unavailable }
        let answer=AssistantTurn(role:"assistant",content:result.text,completed:true)
        let next=AssistantTurn(role:"user",content:"What colour is the triangle in that screenshot? Reply with one colour word.",completed:true)
        let replay=ConversationRules.replayTurns([first,answer,next],currentUserID:next.id)
        let input=try ChatImageStore(container:container).input(replay,currentUserID:next.id,registration:account)
        try PAToolProtocol.boundedInput(input)
        let follow=try await model.chatGPT.toolResponse(input:input,instructions:instructions,tools:[],model:selected,purpose:.diagnostic,onDelta:{_ in})
        let checks=["actual screenshot label":result.text.uppercased().contains("WILLOW 731"),"saved attachment follow-up":follow.text.lowercased().contains("green"),"account/model retained":model.chatGPT.activeID == account && model.chatGPT.selectedModel == selected]
        return ["passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"model":selected,"boundary":"Two completed subscription requests with fictional raster input and reloaded private attachment store. No personal sources, native writes or transcript changes."]
    }
}
struct ChatImageInteractivePreview:View {
    @Bindable var model:DashboardModel
    private let widget=UUID(uuidString:"00000000-0000-0000-0000-000000000009")!
    @State private var seeded=false
    var body:some View {
        VStack {
            Text("Disposable screenshot-paste preview").font(.headline)
            Text("Fictional storage; no Apple source startup. Copy the fixture, then paste into the chatbox.").font(.caption)
            Button("Copy fictional screenshot") {
                if let data=try? ChatImageEvaluation.fixture() { NSPasteboard.general.clearContents();NSPasteboard.general.setData(data,forType:.png) }
            }
            AssistantPanel(model:model,assistant:model.assistant,readingMode:.constant(false),supportsReadingMode:false,widgetID:widget)
        }.frame(minWidth:340,minHeight:460).onAppear { if !seeded { seeded=true;model.assistant.openPA() } }
    }
}
#endif
