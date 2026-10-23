#if DEBUG
import SwiftUI
import AppKit
@MainActor enum WeatherWidgetPreview {
    static func render() {
        let days=[WeatherDay(date:"2026-10-04",code:2,low:8,high:21,rainChance:10,windKmh:12),WeatherDay(date:"2026-10-05",code:61,low:9,high:18,rainChance:65,windKmh:20),WeatherDay(date:"2026-10-06",code:0,low:7,high:19,rainChance:5,windKmh:10)]
        for (name,width,height,mode) in [("short",CGFloat(320),CGFloat(170),"dark"),("tiny",CGFloat(250),CGFloat(150),"dark"),("compact",CGFloat(320),CGFloat(260),"dark"),("wide",CGFloat(650),CGFloat(320),"dark"),("large",CGFloat(650),CGFloat(600),"light")] {
            var colours=WorkspaceColorOverrides();colours.profiles=WorkspaceColorTheme.threePO.profiles
            let palette=WorkspacePalette.resolved(raw:colours.encoded,mode:mode,theme:"warm",accent:"sage")
            let view=VStack(alignment:.leading,spacing:10) {
                HStack { Label("Weather",systemImage:"cloud.sun").font(.title3.weight(.semibold));Spacer();Image(systemName:"arrow.clockwise") }
                WeatherForecastFace(today:days[0],days:days,timezone:"Europe/London")
                HStack { Text("Open-Meteo · Nearby area");Spacer();Text("22:08").foregroundStyle(.secondary) }.font(.caption2)
            }.padding(16).frame(width:width,height:height).environment(\.workspacePalette,palette).foregroundStyle(palette[.text]).background(palette[.widget],in:RoundedRectangle(cornerRadius:20)).padding(20).background(palette[.canvas]).preferredColorScheme(mode == "dark" ? .dark : .light)
            let renderer=ImageRenderer(content:view);renderer.scale=2;renderer.proposedSize = .init(width:width+40,height:height+40)
            if let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) { try? data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-weather-"+name+".png"),options:.atomic) }
        }
    }
}
#endif
