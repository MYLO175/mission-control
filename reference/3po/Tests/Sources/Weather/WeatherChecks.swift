import Foundation
@main struct WeatherChecks {
    static func main() throws {
        let timezone = TimeZone(identifier:"Europe/London")!
        let now = ISO8601DateFormatter().date(from:"2026-10-24T23:30:00Z")!
        let url = try WeatherRules.url(latitude:52.123456,longitude:-0.123456,timezone:timezone)
        let query = Dictionary(uniqueKeysWithValues:URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.map { ($0.name,$0.value!) })
        precondition(query["latitude"] == "52.1" && query["longitude"] == "-0.1" && !url.absoluteString.contains("123456"))
        precondition(query["forecast_days"] == "3" && query["timezone"] == timezone.identifier)
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = timezone
        let dates = (0..<3).map { WeatherRules.day(calendar.date(byAdding:.day,value:$0,to:now)!,timezone:timezone) }
        precondition(dates == ["2026-10-25","2026-10-26","2026-10-27"])
        var fixture: [String:Any] = ["timezone":timezone.identifier,"daily_units":["temperature_2m_min":"°C","temperature_2m_max":"°C","precipitation_probability_max":"%","wind_speed_10m_max":"km/h"],"daily":["time":dates,"weather_code":[0,61,3],"temperature_2m_min":[4,5,6],"temperature_2m_max":[14,15,16],"precipitation_probability_max":[0,90,20],"wind_speed_10m_max":[10,20,15]]]
        let decoded = try WeatherRules.decode(JSONSerialization.data(withJSONObject:fixture),now:now,timezone:timezone)
        precondition(decoded.days[1].description == "Rain" && decoded.usable(now:now,timezone:timezone))
        precondition(!decoded.usable(now:now.addingTimeInterval(7201),timezone:timezone))
        precondition(!decoded.usable(now:now,timezone:TimeZone(identifier:"America/New_York")!))
        precondition(decoded.today(now:now,timezone:timezone)?.date == dates[0])
        precondition(decoded.today(now:now.addingTimeInterval(7201),timezone:timezone) == nil)
        precondition(decoded.today(now:now,timezone:TimeZone(identifier:"America/New_York")!) == nil)
        // A fresh pre-midnight cache remains valid after midnight, but its first day is yesterday.
        let beforeMidnight = ISO8601DateFormatter().date(from:"2026-10-25T23:30:00Z")!
        let afterMidnight = beforeMidnight.addingTimeInterval(3600)
        var rollover = decoded; rollover.fetched = beforeMidnight
        precondition(rollover.today(now:afterMidnight,timezone:timezone)?.date == "2026-10-26")
        precondition(rollover.today(now:afterMidnight,timezone:timezone)?.symbol == "cloud.rain.fill")
        precondition(decoded.days[0].symbol == "sun.max.fill" && decoded.days[2].symbol == "cloud.fill")
        let saved = try JSONEncoder().encode(decoded)
        precondition(!String(data:saved,encoding:.utf8)!.contains("latitude"))
        let restored = try JSONDecoder().decode(WeatherForecast.self,from:saved)
        precondition(restored.days.count == 3)
        func rejects(_ fixture: [String:Any]) throws {
            do { _ = try WeatherRules.decode(JSONSerialization.data(withJSONObject:fixture),now:now,timezone:timezone); preconditionFailure("Invalid forecast accepted") } catch WeatherFailure.invalid { }
        }
        fixture["timezone"] = "UTC"; try rejects(fixture); fixture["timezone"] = timezone.identifier
        var daily = fixture["daily"] as! [String:Any]
        daily["precipitation_probability_max"] = [101,0,0]; fixture["daily"] = daily; try rejects(fixture)
        daily["precipitation_probability_max"] = [0,0]; fixture["daily"] = daily; try rejects(fixture)
        daily["precipitation_probability_max"] = [0,0,0]; daily["time"] = ["2026-10-24","2026-10-25","2026-10-26"]; fixture["daily"] = daily; try rejects(fixture)
        do { _ = try WeatherRules.url(latitude:Double.nan,longitude:0,timezone:timezone); preconditionFailure() } catch WeatherFailure.invalid { }
        print("PASS weather: coarse coordinates, DST/local dates, units, invalid/partial forecasts, cache freshness, persistence without coordinates.")
    }
}
