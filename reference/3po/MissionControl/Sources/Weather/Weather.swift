import Foundation

struct WeatherDay: Codable, Identifiable {
    var date: String
    var code: Int
    var low: Double
    var high: Double
    var rainChance: Double
    var windKmh: Double
    var id: String { date }
    var description: String { WeatherRules.description(code) }
    var symbol:String { WeatherRules.symbol(code) }
}
struct WeatherForecast: Codable {
    var fetched: Date
    var timezone: String
    var days: [WeatherDay]
    func today(now:Date = .now,timezone:TimeZone = .current)->WeatherDay? {
        guard usable(now:now,timezone:timezone) else { return nil }
        return days.first { $0.date == WeatherRules.day(now,timezone:timezone) }
    }
    func usable(now: Date = .now, timezone: TimeZone = .current) -> Bool {
        let age = now.timeIntervalSince(fetched)
        return age >= -60 && age <= 7200 && self.timezone == timezone.identifier && days.contains { $0.date == WeatherRules.day(now, timezone: timezone) }
    }
}
enum WeatherFailure: LocalizedError {
    case unavailable, invalid, timeout, denied, disabled
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Weather is unavailable. Try refreshing shortly."
        case .invalid: return "The weather provider returned an incomplete forecast."
        case .timeout: return "Location did not arrive within 30 seconds. Try again when Wi-Fi is available."
        case .denied: return "Allow 3PO in System Settings → Privacy & Security → Location Services."
        case .disabled: return "Local weather is turned off."
        }
    }
}
enum WeatherRules {
    static let provider = URL(string: "https://open-meteo.com/")!
    static func day(_ date: Date, timezone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timezone; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func url(latitude: Double, longitude: Double, timezone: TimeZone) throws -> URL {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { throw WeatherFailure.invalid }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        let coarse: (Double) -> String = { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), ($0 * 10).rounded() / 10) }
        url.queryItems = [URLQueryItem(name:"latitude",value:coarse(latitude)), URLQueryItem(name:"longitude",value:coarse(longitude)), URLQueryItem(name:"timezone",value:timezone.identifier), URLQueryItem(name:"forecast_days",value:"3"), URLQueryItem(name:"temperature_unit",value:"celsius"), URLQueryItem(name:"wind_speed_unit",value:"kmh"), URLQueryItem(name:"daily",value:"weather_code,temperature_2m_min,temperature_2m_max,precipitation_probability_max,wind_speed_10m_max")]
        return url.url!
    }
    private struct Response: Decodable {
        struct Daily: Decodable { var time: [String]; var weather_code: [Int]; var temperature_2m_min: [Double]; var temperature_2m_max: [Double]; var precipitation_probability_max: [Double]; var wind_speed_10m_max: [Double] }
        var timezone: String
        var daily_units: [String:String]
        var daily: Daily
    }
    static func decode(_ data: Data, now: Date = .now, timezone: TimeZone = .current) throws -> WeatherForecast {
        guard let r = try? JSONDecoder().decode(Response.self,from:data), r.timezone == timezone.identifier, r.daily_units["temperature_2m_min"] == "°C", r.daily_units["temperature_2m_max"] == "°C", r.daily_units["precipitation_probability_max"] == "%", r.daily_units["wind_speed_10m_max"] == "km/h" else { throw WeatherFailure.invalid }
        let d = r.daily, count = d.time.count
        guard count == 3, [d.weather_code.count,d.temperature_2m_min.count,d.temperature_2m_max.count,d.precipitation_probability_max.count,d.wind_speed_10m_max.count].allSatisfy({ $0 == count }) else { throw WeatherFailure.invalid }
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = timezone
        let days = try d.time.indices.map { i -> WeatherDay in
            let expected = day(calendar.date(byAdding:.day,value:i,to:now)!,timezone:timezone)
            guard d.time[i] == expected, validCodes.contains(d.weather_code[i]), (-100...70).contains(d.temperature_2m_min[i]), (-100...70).contains(d.temperature_2m_max[i]), d.temperature_2m_min[i] <= d.temperature_2m_max[i], (0...100).contains(d.precipitation_probability_max[i]), (0...500).contains(d.wind_speed_10m_max[i]) else { throw WeatherFailure.invalid }
            return WeatherDay(date:d.time[i],code:d.weather_code[i],low:d.temperature_2m_min[i],high:d.temperature_2m_max[i],rainChance:d.precipitation_probability_max[i],windKmh:d.wind_speed_10m_max[i])
        }
        return WeatherForecast(fetched:now,timezone:timezone.identifier,days:days)
    }
    static let validCodes: Set<Int> = [0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99]
    static func symbol(_ code:Int)->String {
        switch code {
        case 0: return "sun.max.fill"
        case 1,2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45,48: return "cloud.fog.fill"
        case 51,53,55: return "cloud.drizzle.fill"
        case 56,57,66,67: return "cloud.sleet.fill"
        case 61,63,65,80,81,82: return "cloud.rain.fill"
        case 71,73,75,77,85,86: return "cloud.snow.fill"
        case 95,96,99: return "cloud.bolt.rain.fill"
        default: return "cloud"
        }
    }
    static func description(_ code: Int) -> String {
        switch code { case 0: return "Clear"; case 1,2: return "Partly cloudy"; case 3: return "Overcast"; case 45,48: return "Fog"; case 51,53,55: return "Drizzle"; case 56,57,66,67: return "Freezing rain"; case 61,63,65,80,81,82: return "Rain"; case 71,73,75,77,85,86: return "Snow"; case 95,96,99: return "Thunderstorms"; default: return "Unavailable" }
    }
}
