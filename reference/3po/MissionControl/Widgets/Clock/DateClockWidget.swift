import SwiftUI
import AppKit

struct DateClockWidget:View {
    @Binding var configuration:WidgetConfiguration
    private var showsTime:Bool { configuration.clockShowsTime ?? true }
    private var seconds:Bool { configuration.clockShowsSeconds ?? false }
    var body:some View {
        TimelineView(.periodic(from:.now,by:seconds && showsTime ? 1 : 30)) { context in
            VStack(spacing:8) {
                HStack {
                    Text(context.date.formatted(.dateTime.weekday(.wide))).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Menu {
                        Picker("Layout",selection:Binding(get:{configuration.clockStyle ?? "auto"},set:{configuration.clockStyle=$0})) { Text("Adaptive").tag("auto");Text("Digital").tag("digital");Text("Calendar").tag("calendar") }
                        Picker("Alignment",selection:Binding(get:{configuration.clockAlignment ?? "centre"},set:{configuration.clockAlignment=$0})) { Text("Centre").tag("centre");Text("Leading").tag("leading") }
                        Divider()
                        Toggle("Show clock",isOn:Binding(get:{showsTime},set:{configuration.clockShowsTime=$0}))
                        Toggle("Show seconds",isOn:Binding(get:{seconds},set:{configuration.clockShowsSeconds=$0})).disabled(!showsTime)
                        Toggle("24-hour time",isOn:Binding(get:{configuration.clockUses24Hour ?? false},set:{configuration.clockUses24Hour=$0})).disabled(!showsTime)
                    } label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width:22).accessibilityLabel("Date and clock options")
                }.fixedSize(horizontal:false,vertical:true)
                DateClockFace(date:context.date,configuration:configuration)
            }.padding(16)
        }
    }
}
struct DateClockFace:View {
    var date:Date
    var configuration:WidgetConfiguration
    private var showsTime:Bool { configuration.clockShowsTime ?? true }
    private var seconds:Bool { configuration.clockShowsSeconds ?? false }
    private var leading:Bool { configuration.clockAlignment == "leading" }
    private var time:String {
        if configuration.clockUses24Hour == true {
            var calendar=Calendar.current;calendar.timeZone = .current
            let parts=calendar.dateComponents([.hour,.minute,.second],from:date)
            return String(format:seconds ? "%02d:%02d:%02d" : "%02d:%02d",arguments:seconds ? [parts.hour ?? 0,parts.minute ?? 0,parts.second ?? 0] : [parts.hour ?? 0,parts.minute ?? 0])
        }
        return seconds ? date.formatted(.dateTime.hour().minute().second()) : date.formatted(date:.omitted,time:.shortened)
    }
    // Measure the actual localised text rather than guessing its width or capping large widgets.
    private func fittedFont(_ text:String,width:CGFloat,height:CGFloat,weight:NSFont.Weight,monospaced:Bool=false)->CGFloat {
        let base=monospaced ? NSFont.monospacedDigitSystemFont(ofSize:100,weight:weight) : NSFont.systemFont(ofSize:100,weight:weight)
        let font=base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor:$0,size:100) } ?? base
        let measured=(text as NSString).size(withAttributes:[.font:font])
        let lineHeight=max(measured.height,font.ascender-font.descender+font.leading)
        return max(1,100*min(max(1,width)/max(1,measured.width),max(1,height)/max(1,lineHeight))*0.96)
    }
    @ViewBuilder private func adaptiveFace(size:CGSize)->some View {
        let alignment:HorizontalAlignment=leading ? .leading : .center
        let day=date.formatted(.dateTime.day()),month=date.formatted(.dateTime.month(.wide))
        if showsTime && size.width > size.height*1.8 {
            let gap=min(24,size.width*0.035),dateWidth=(size.width-gap)*0.26,timeWidth=size.width-gap-dateWidth
            HStack(spacing:gap) {
                VStack(alignment:alignment,spacing:size.height*0.035) {
                    Text(day).font(.system(size:fittedFont(day,width:dateWidth,height:size.height*0.72,weight:.semibold),weight:.semibold,design:.rounded))
                    Text(month).font(.system(size:fittedFont(month,width:dateWidth,height:size.height*0.2,weight:.medium),weight:.medium,design:.rounded)).foregroundStyle(.secondary)
                }.frame(width:dateWidth,height:size.height,alignment:leading ? .leading : .center)
                Text(time).font(.system(size:fittedFont(time,width:timeWidth,height:size.height*0.94,weight:.light,monospaced:true),weight:.light,design:.rounded)).monospacedDigit().frame(width:timeWidth,height:size.height)
            }
        } else if showsTime {
            let dateLabel=date.formatted(.dateTime.day().month(.wide))
            VStack(alignment:alignment,spacing:size.height*0.04) {
                Text(dateLabel).font(.system(size:fittedFont(dateLabel,width:size.width,height:size.height*0.25,weight:.medium),weight:.medium,design:.rounded)).foregroundStyle(.secondary)
                Text(time).font(.system(size:fittedFont(time,width:size.width,height:size.height*0.65,weight:.light,monospaced:true),weight:.light,design:.rounded)).monospacedDigit()
            }
        } else {
            VStack(alignment:alignment,spacing:size.height*0.035) {
                Text(day).font(.system(size:fittedFont(day,width:size.width,height:size.height*0.72,weight:.semibold),weight:.semibold,design:.rounded))
                Text(month).font(.system(size:fittedFont(month,width:size.width,height:size.height*0.2,weight:.medium),weight:.medium,design:.rounded)).foregroundStyle(.secondary)
            }
        }
    }
    var body:some View {
        GeometryReader { geometry in
            let size=geometry.size,style=configuration.clockStyle ?? "auto"
            let alignment:HorizontalAlignment=leading ? .leading : .center
            Group {
                if style == "auto" {
                    adaptiveFace(size:size)
                } else if style == "calendar" {
                    VStack(alignment:alignment,spacing:4) {
                        Text(date.formatted(.dateTime.day())).font(.system(size:min(180,max(36,min(size.width*0.42,size.height*0.5))),weight:.semibold,design:.rounded))
                        Text(date.formatted(.dateTime.month(.wide).year())).font(.system(size:min(32,max(16,size.height*0.1)),weight:.medium,design:.rounded)).foregroundStyle(.secondary)
                        if showsTime { Text(time).font(.system(size:min(42,max(18,size.height*0.14)),weight:.light,design:.rounded)).monospacedDigit() }
                    }
                } else {
                    VStack(alignment:alignment,spacing:10) {
                        Text(date.formatted(.dateTime.day().month(.wide))).font(.system(size:min(46,max(20,min(size.width*0.095,size.height*0.18))),weight:.medium,design:.rounded)).foregroundStyle(showsTime ? .secondary : .primary)
                        if showsTime { Text(time).font(.system(size:min(180,max(28,min(size.width/(seconds ? 5.5 : 4.2),size.height*0.4))),weight:.light,design:.rounded)).monospacedDigit() }
                    }
                }
            }.lineLimit(1).minimumScaleFactor(0.5).frame(width:size.width,height:size.height,alignment:leading ? .leading : .center)
        }
    }
}
