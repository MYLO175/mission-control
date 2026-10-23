#if DEBUG
import SwiftUI
import AppKit
@MainActor enum DateClockPreview {
    static func render() {
        let date=ISO8601DateFormatter().date(from:"2026-10-04T21:30:00Z")!
        for (name,width,height,style) in [("compact",CGFloat(320),CGFloat(240),"auto"),("wide",CGFloat(1000),CGFloat(350),"auto"),("user-size",CGFloat(650),CGFloat(320),"auto"),("large",CGFloat(1200),CGFloat(700),"auto"),("seconds",CGFloat(650),CGFloat(320),"auto"),("calendar",CGFloat(480),CGFloat(460),"calendar"),("digital",CGFloat(500),CGFloat(350),"digital")] {
            var configuration=WidgetConfiguration();configuration.clockStyle=style;configuration.clockUses24Hour=true;configuration.clockShowsSeconds=name == "seconds"
            var colours=WorkspaceColorOverrides();colours.profiles=WorkspaceColorTheme.threePO.profiles
            let palette=WorkspacePalette.resolved(raw:colours.encoded,mode:"dark",theme:"warm",accent:"sage")
            let view=VStack(alignment:.leading,spacing:10) {
                HStack { Text("Sunday").font(.subheadline).foregroundStyle(.secondary);Spacer();Image(systemName:"ellipsis") }
                DateClockFace(date:date,configuration:configuration)
            }.padding(20).frame(width:width,height:height).foregroundStyle(palette[.text]).background(palette[.widget],in:RoundedRectangle(cornerRadius:20)).padding(20).background(palette[.canvas]).preferredColorScheme(.dark)
            let renderer=ImageRenderer(content:view);renderer.scale=2;renderer.proposedSize = .init(width:width+40,height:height+40)
            if let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-clock-"+name+".png"),options:.atomic) }
        }
    }
}
#endif
