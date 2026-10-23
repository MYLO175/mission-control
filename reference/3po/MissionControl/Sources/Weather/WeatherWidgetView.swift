import SwiftUI
import AppKit

struct WeatherWidgetView:View {
    @Bindable var weather:WeatherService
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label("Weather",systemImage:"cloud.sun").font(.title3.weight(.semibold))
                Spacer()
                if weather.loading { ProgressView().controlSize(.small) }
                Button { weather.startRefresh(allowPrompt:true,force:true) } label:{Image(systemName:"arrow.clockwise")}
                    .buttonStyle(.borderless).help("Refresh nearby forecast").accessibilityLabel("Refresh weather")
                    .disabled(!weather.enabled || weather.loading || (!weather.allowed && weather.authorization != .notDetermined))
            }.fixedSize(horizontal:false,vertical:true)
            if weather.enabled,weather.allowed,let forecast=weather.forecast,let today=forecast.today() {
                WeatherForecastFace(today:today,days:forecast.days,timezone:forecast.timezone)
                HStack(alignment:.firstTextBaseline) {
                    Link("Open-Meteo · Nearby area",destination:WeatherRules.provider)
                    Spacer(minLength:4)
                    Text(forecast.fetched.formatted(date:.omitted,time:.shortened)).foregroundStyle(.secondary)
                }.font(.caption2).fixedSize(horizontal:false,vertical:true)
                if let error=weather.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            } else {
                VStack(spacing:12) {
                    Image(systemName:"cloud.sun").font(.system(size:42,weight:.light)).foregroundStyle(.secondary)
                    Text(weather.enabled ? "Your nearby forecast" : "Local weather is off").font(.headline)
                    Text(weather.status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !weather.enabled { Button("Enable local weather") { weather.enabled=true } }
                    else if !weather.allowed {
                        if weather.authorization == .notDetermined { Button("Use my location") { weather.startRefresh(allowPrompt:true,force:true) }.disabled(weather.loading) }
                        else { Button("Location settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!) } }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .onAppear { weather.startRefresh() }
    }
}

struct WeatherForecastFace:View {
    var today:WeatherDay
    var days:[WeatherDay]
    var timezone:String
    @Environment(\.workspacePalette) private var palette
    private func temperature(_ value:Double)->String { value.formatted(.number.precision(.fractionLength(0)))+"°" }
    private func label(_ day:WeatherDay)->String {
        if day.id == today.id { return "Today" }
        let parser=DateFormatter();parser.locale=Locale(identifier:"en_US_POSIX");parser.timeZone=TimeZone(identifier:timezone);parser.dateFormat="yyyy-MM-dd"
        guard let date=parser.date(from:day.date) else { return day.date }
        let formatter=DateFormatter();formatter.timeZone=parser.timeZone;formatter.dateFormat="EEE";return formatter.string(from:date)
    }
    var body:some View {
        GeometryReader { bounds in
        let compact=bounds.size.height < 155
        VStack(alignment:.leading,spacing:compact ? 6 : 10) {
            GeometryReader { geometry in
                let size=geometry.size
                HStack(spacing:16) {
                    Image(systemName:today.symbol).symbolRenderingMode(.hierarchical).foregroundStyle(palette[.accent])
                        .font(.system(size:max(18,min(size.height*0.62,size.width*0.23)),weight:.light)).frame(width:size.width*0.32)
                    VStack(alignment:.leading,spacing:2) {
                        Text(temperature(today.high)).font(.system(size:max(18,min(size.height*0.54,size.width*0.27)),weight:.light,design:.rounded)).monospacedDigit()
                        Text(today.description).font((bounds.size.height < 85 ? Font.caption : Font.callout).weight(.medium)).lineLimit(1)
                        if bounds.size.height >= 85 { Text("Forecast high · Low \(temperature(today.low))C").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.frame(width:size.width,height:size.height)
            }
            if bounds.size.height >= 65 { HStack {
                Label("\(Int(today.rainChance))% rain",systemImage:"drop.fill")
                Spacer(minLength:4)
                Label("Up to \(Int(today.windKmh)) km/h",systemImage:"wind")
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75) }
            if !compact { HStack(spacing:8) {
                ForEach(days.filter{$0.date >= today.date}.prefix(3)) { day in
                    VStack(spacing:5) {
                        Text(label(day)).font(.caption.weight(.medium))
                        HStack(spacing:5) { Image(systemName:day.symbol).foregroundStyle(palette[.accent]);Text(temperature(day.high));Text(temperature(day.low)).foregroundStyle(.secondary) }.font(.caption)
                    }.frame(maxWidth:.infinity).padding(.vertical,9).background(palette[.assistantBubble].opacity(0.65),in:RoundedRectangle(cornerRadius:12))
                }
            }.fixedSize(horizontal:false,vertical:true) }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }
    }
}
