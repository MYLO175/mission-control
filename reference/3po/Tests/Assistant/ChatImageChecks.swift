import AppKit
import SwiftData

@main struct Checks {
    @MainActor static func main() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("pa-image-check-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let container=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let store=ChatImageStore(container:container,directory:root)
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:3000,pixelsHigh:1400,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let fixture=bitmap.representation(using:.png,properties:[:])!
        let image=try store.add(fixture,registration:"one")
        precondition(image.width == 2400 && image.height == 1120 && image.byteCount <= 2_000_000)
        let saved=try store.data(image,registration:"one")
        let loadedBytes=try ChatImageStore(container:container,directory:root).data(image,registration:"one");precondition(loadedBytes == saved)
        let records=try container.mainContext.fetch(FetchDescriptor<CachedDashboard>())
        precondition(records.first!.data.count < 1000,"Screenshot bytes must not burden dashboard cache scans")
        let permissions=try FileManager.default.attributesOfItem(atPath:root.path)[.posixPermissions] as! Int
        precondition(permissions == 0o700)
        do { _ = try store.data(image,registration:"two");preconditionFailure("Cross-account input") } catch {}
        var forged=image;forged.digest="wrong"
        do { _ = try store.data(forged,registration:"one");preconditionFailure("Changed attachment") } catch {}
        do { _ = try store.add(Data("not an image".utf8),registration:"one");preconditionFailure("Bad image") } catch {}
        let board=NSPasteboard(name:NSPasteboard.Name("pa-image-test-"+UUID().uuidString));defer { board.releaseGlobally() }
        board.setData(fixture,forType:.png)
        precondition(ChatImageStore.containsImage(board))
        let pasted=try store.paste(board,registration:"one");precondition(pasted.count == 1)
        let drafts=ChatDraftStore(container:container),widget=UUID(),topic=UUID()
        precondition(drafts.setImages([image],registration:"one",widget:widget,conversation:topic))
        drafts.show(registration:"one",widget:widget,conversation:topic)
        precondition(drafts.hasDraft(registration:"one"));drafts.hide(widget:widget);precondition(!drafts.hasDraft(registration:"one"))
        let reloaded=ChatDraftStore(container:container)
        precondition(reloaded.images(registration:"one",widget:widget,conversation:topic) == [image])
        precondition(reloaded.images(registration:"two",widget:widget,conversation:topic).isEmpty && reloaded.images(registration:"one",widget:widget,conversation:UUID()).isEmpty)
        var human=AssistantTurn(role:"user",content:"",completed:true);human.images=[image]
        let decoded=try JSONDecoder().decode(AssistantTurn.self,from:JSONEncoder().encode(human));precondition(decoded.images == [image])
        let queue=PARequestQueue(container:container)
        precondition(queue.add(registration:"one",topicID:topic,prompt:"",images:[image]))
        precondition(PARequestQueue(container:container).items.first?.images == [image])
        precondition(!queue.add(registration:"two",topicID:topic,prompt:"Look",images:[image]))
        let next=AssistantTurn(role:"user",content:"What colour is it?",completed:true)
        let replay=ConversationRules.replayTurns([human,.init(role:"assistant",content:"A screenshot.",completed:true),next],currentUserID:next.id)
        let input=try store.input(replay,currentUserID:next.id,registration:"one")
        let content=input[0]["content"] as! [[String:Any]];precondition(content.first?["type"] as? String == "input_image")
        precondition((content.first?["image_url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
        var turns:[AssistantTurn]=[]
        for _ in 0..<6 { let item=try store.add(fixture,registration:"one");var turn=AssistantTurn(role:"user",content:"Image",completed:true);turn.images=[item];turns.append(turn) }
        let bounded=try store.input(turns,currentUserID:turns.last!.id,registration:"one")
        let parts=bounded.flatMap{$0["content"] as? [[String:Any]] ?? []}
        precondition(parts.filter{$0["type"] as? String == "input_image"}.count == 4)
        precondition(parts.contains{($0["text"] as? String)?.contains("Earlier attached image omitted") == true})
        let repeated=Array(0..<6).map { _ -> AssistantTurn in var turn=AssistantTurn(role:"user",content:"Again",completed:true);turn.images=[image];return turn }
        let repeatedInput=try store.input(repeated,currentUserID:repeated.last!.id,registration:"one")
        precondition(repeatedInput.flatMap{$0["content"] as? [[String:Any]] ?? []}.filter{$0["type"] as? String == "input_image"}.count == 4)
        store.discard(image)
        let omitted=try store.input([human,next],currentUserID:next.id,registration:"one")
        precondition((omitted[0]["content"] as! [[String:Any]]).first?["type"] as? String == "input_text")
        do { _ = try store.input([human],currentUserID:human.id,registration:"one");preconditionFailure("Missing current image silently omitted") } catch {}
        precondition(drafts.setImages([],registration:"one",widget:widget,conversation:topic))
        precondition(ChatDraftStore(container:container).images(registration:"one",widget:widget,conversation:topic).isEmpty)
        let diskURL=root.appendingPathComponent("draft.store"),byteRoot=root.appendingPathComponent("saved-images")
        var diskImage:ChatImageAttachment!
        do {
            let disk=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(url:diskURL,cloudKitDatabase:.none))
            diskImage=try ChatImageStore(container:disk,directory:byteRoot).add(fixture,registration:"disk-account")
            let diskDraft=ChatDraftStore(container:disk)
            precondition(diskDraft.setImages([diskImage],registration:"disk-account",widget:widget,conversation:topic))
        }
        do {
            let disk=try ModelContainer(for:CachedDashboard.self,configurations:ModelConfiguration(url:diskURL,cloudKitDatabase:.none))
            let resumed=ChatDraftStore(container:disk).images(registration:"disk-account",widget:widget,conversation:topic)
            precondition(resumed == [diskImage])
            let bytes=try ChatImageStore(container:disk,directory:byteRoot).data(resumed[0],registration:"disk-account")
            precondition(bytes.count == diskImage.byteCount)
        }
        print("PASS: screenshot normalisation/private byte storage, reload/integrity/account isolation, image-only draft/queue persistence, actual image request construction, follow-up replay, image bounds and missing-current refusal")
    }
}
