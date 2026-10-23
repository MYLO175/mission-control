import AppKit
import CryptoKit
import ImageIO
import Observation
import SwiftData

@MainActor @Observable final class ChatImageStore {
    static let maxImages = 4
    static let maxBytes = 2_000_000
    private let container:ModelContainer?
    private let directory:URL
    init(container:ModelContainer?,directory:URL? = nil) {
        self.container=container
        if let directory { self.directory=directory }
        else if let container,container.configurations.allSatisfy({$0.isStoredInMemoryOnly}) {
            self.directory=FileManager.default.temporaryDirectory.appendingPathComponent("missioncontrol-images-"+String(UInt(bitPattern:ObjectIdentifier(container))))
        } else {
            self.directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Mission Control/ChatImages",isDirectory:true)
        }
    }
    private func file(_ image:ChatImageAttachment)->URL { directory.appendingPathComponent(key(image).replacingOccurrences(of:":",with:"-")) }
    private func key(_ image:ChatImageAttachment)->String {
        let account=SHA256.hash(data:Data(image.registration.utf8)).map{String(format:"%02x",$0)}.joined()
        return "assistantImage:"+account+":"+image.id.uuidString
    }
    private func record(_ image:ChatImageAttachment)throws->Data? {
        guard let container else { throw ChatImageFailure.storage }
        return try LocalRecordRepository(container: container).read(key(image))
    }
    static func digest(_ data:Data)->String { SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined() }
    static func normalise(_ data:Data)throws->(Data,String,Int,Int) {
        guard !data.isEmpty,data.count <= 32_000_000,let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetCount(source) == 1,
              let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width=properties[kCGImagePropertyPixelWidth] as? Int,let height=properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,height > 0,Double(width)*Double(height) <= 100_000_000 else { throw ChatImageFailure.format }
        let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:2400,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true]
        guard let cg=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary) else { throw ChatImageFailure.format }
        let bitmap=NSBitmapImageRep(cgImage:cg)
        // Re-encoding drops EXIF/location metadata. Prefer lossless text screenshots.
        if let png=bitmap.representation(using:.png,properties:[:]),png.count <= maxBytes { return (png,"image/png",cg.width,cg.height) }
        // Composite alpha onto white before JPEG encoding.
        let flat=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:cg.width,pixelsHigh:cg.height,bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        guard let context=NSGraphicsContext(bitmapImageRep:flat) else { throw ChatImageFailure.format }
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        NSColor.white.setFill();NSRect(x:0,y:0,width:cg.width,height:cg.height).fill()
        context.cgContext.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height));NSGraphicsContext.restoreGraphicsState()
        for quality in [0.9,0.75,0.6] {
            if let jpeg=flat.representation(using:.jpeg,properties:[.compressionFactor:quality]),jpeg.count <= maxBytes { return (jpeg,"image/jpeg",cg.width,cg.height) }
        }
        throw ChatImageFailure.size
    }
    func paste(_ board:NSPasteboard,registration:String)throws->[ChatImageAttachment] {
        let data=(board.pasteboardItems ?? []).compactMap { $0.data(forType:.png) ?? $0.data(forType:.tiff) ?? $0.data(forType:NSPasteboard.PasteboardType("public.jpeg")) }
        guard !data.isEmpty,data.count <= Self.maxImages else { throw ChatImageFailure.format }
        var saved:[ChatImageAttachment]=[]
        do { for bytes in data { saved.append(try add(bytes,registration:registration)) };return saved }
        catch { saved.forEach(discard);throw error }
    }
    static func containsImage(_ board:NSPasteboard)->Bool {
        board.pasteboardItems?.contains { $0.types.contains(.png) || $0.types.contains(.tiff) || $0.types.contains(NSPasteboard.PasteboardType("public.jpeg")) } ?? false
    }
    func add(_ bytes:Data,registration:String)throws->ChatImageAttachment {
        guard !registration.isEmpty,let container else { throw ChatImageFailure.storage }
        let (data,mime,width,height)=try Self.normalise(bytes)
        let image=ChatImageAttachment(registration:registration,mimeType:mime,width:width,height:height,byteCount:data.count,digest:Self.digest(data))
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try data.write(to:file(image),options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file(image).path)
            try LocalRecordRepository(container: container).save(image, key: key(image))
        } catch { try? FileManager.default.removeItem(at:file(image));throw ChatImageFailure.storage }
        return image
    }
    func data(_ image:ChatImageAttachment,registration:String)throws->Data {
        guard image.registration == registration,image.byteCount > 0,image.byteCount <= Self.maxBytes,["image/png","image/jpeg"].contains(image.mimeType),
              image.width > 0,image.height > 0,max(image.width,image.height) <= 2400,
              let metadata=try record(image),try JSONDecoder().decode(ChatImageAttachment.self,from:metadata) == image else { throw ChatImageFailure.unavailable }
        guard let bytes=try? Data(contentsOf:file(image)) else { throw ChatImageFailure.unavailable }
        guard bytes.count == image.byteCount,Self.digest(bytes) == image.digest else { throw ChatImageFailure.unavailable }
        return bytes
    }
    func preview(_ image:ChatImageAttachment,registration:String,maxDimension:Int)->NSImage? {
        guard let data=try? data(image,registration:registration),let source=CGImageSourceCreateWithData(data as CFData,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxDimension,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return NSImage(cgImage:cg,size:.zero)
    }
    func discard(_ image:ChatImageAttachment) {
        guard let container,(try? record(image)) != nil else { return }
        do { try LocalRecordRepository(container: container).write([:], removing: [key(image)]);try? FileManager.default.removeItem(at:file(image)) } catch { }
    }
    func validate(_ images:[ChatImageAttachment],registration:String)throws {
        guard images.count <= Self.maxImages,Set(images.map(\.id)).count == images.count else { throw ChatImageFailure.size }
        for image in images { _ = try data(image,registration:registration) }
    }
    /// Only selected bounded conversation turns are eligible. Current attachments are mandatory;
    /// older images are newest-first within four images/eight MB, with explicit omission labels.
    func input(_ turns:[AssistantTurn],currentUserID:UUID,registration:String)throws->[[String:Any]] {
        var included:[String:Data]=[:],remaining=Self.maxImages
        for turn in turns.reversed() where turn.role == "user" {
            for image in turn.images ?? [] {
                if remaining == 0 { if turn.id == currentUserID { throw ChatImageFailure.size };continue }
                do { included[turn.id.uuidString+image.id.uuidString]=try data(image,registration:registration);remaining-=1 }
                catch { if turn.id == currentUserID { throw error } }
            }
        }
        return turns.map { turn in
            guard turn.role == "user",let images=turn.images,!images.isEmpty else { return ["role":turn.role,"content":turn.content] }
            var content:[[String:Any]]=[]
            if !turn.content.isEmpty { content.append(["type":"input_text","text":turn.content]) }
            for image in images {
                if let data=included[turn.id.uuidString+image.id.uuidString] { content.append(["type":"input_image","image_url":"data:"+image.mimeType+";base64,"+data.base64EncodedString(),"detail":"auto"]) }
                else { content.append(["type":"input_text","text":"[Earlier attached image omitted: unavailable or outside the bounded image context. Ask the human to paste it again if required.]"]) }
            }
            return ["role":"user","content":content]
        }
    }
}
enum ChatImageFailure: LocalizedError {
    case format,size,storage,unavailable
    var errorDescription:String? {
        switch self {
        case .format:return "Paste a still screenshot or image (PNG, TIFF or JPEG), up to 32 MB. Animated images are not supported."
        case .size:return "Attach up to four images per message. This image could not fit the size limit; crop it and paste again."
        case .storage:return "The image could not be saved. Your message is kept; please try pasting again."
        case .unavailable:return "An attached image is unavailable for this account. Remove it and paste it again; your text is kept."
        }
    }
}
