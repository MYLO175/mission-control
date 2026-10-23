import Foundation

/// Local evidence checks for a newly proposed or changed date. Never call this
/// when executing a human-approved, captured creation payload.
enum ReviewPlanDateRules {
    /// `now` and `timeZoneID` belong to the captured human turn, not execution.
    /// A date-only marker is valid for a timed deadline; the caller must retain
    /// the exact timed quote in its displayed details/notes.
    static func rejection(quote: String, basis: String, human: String, title: String,
                          kind: String, start: String?, end: String?, hasTime: Bool,
                          now: Date, timeZoneID: String) -> String? {
        guard ["source", "human"].contains(basis), ["calendar", "reminder", "projectTask", "project"].contains(kind),
              let zone = TimeZone(identifier: timeZoneID) else {
            return "The date evidence or time zone is unavailable."
        }
        guard let start else {
            return end != nil || hasTime || kind == "calendar" ? "A Calendar date or complete date mode is required." : nil
        }
        guard !start.isEmpty, !["projectTask","project"].contains(kind) || !hasTime,
              let proposedStart = proposed(start, timed: hasTime, zone: zone),
              end.map({ proposed($0, timed: hasTime, zone: zone) != nil }) ?? true else {
            return "The suggested date is invalid or uses the wrong date mode."
        }
        let proposedEnd = end.flatMap { proposed($0, timed: hasTime, zone: zone) }
        guard proposedEnd.map({ $0.date >= proposedStart.date }) ?? true else { return "The suggested date range is reversed." }
        let evidence = normalise(quote).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty, evidence.utf8.count <= 16_000, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              basis != "human" || normalise(human).contains(evidence) else {
            return "A new date needs an exact supporting source or human quote."
        }
        let segments = evidence.components(separatedBy: .newlines).flatMap {
            $0.components(separatedBy: try! NSRegularExpression(pattern: "[;!?]|\\.(?=\\s+[a-z])|\\s+and\\s+(?!(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b)(?=[a-z])"))
        }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var supported: [Facts] = []
        for (index, segment) in segments.enumerated() {
            var facts = facts(segment, human: basis == "human", now: now, zone: zone)
            let ownContext = relevant(segment, title: title, human: basis == "human")
            // Mail often places a heading on the line directly above its date.
            // Only borrow that heading when it contains no competing date.
            let heading = index > 0 && dateContinuation(segment) && relevant(segments[index - 1], title: title, human: basis == "human") &&
                self.facts(segments[index - 1], human: basis == "human", now: now, zone: zone).days.isEmpty
            if ownContext || heading {
                if basis == "source", !facts.dateWindow {
                    let text = segment as NSString
                    let ordered = facts.days.sorted { $0.range.location < $1.range.location }
                    for point in ordered {
                        let previousEnd = ordered.filter { NSMaxRange($0.range) <= point.range.location }.map { NSMaxRange($0.range) }.max() ?? 0
                        let context = text.substring(with: NSRange(location: previousEnd, length: NSMaxRange(point.range) - previousEnd))
                        if relevant(context, title: title, human: false) || (heading && previousEnd == 0) { facts.supportedDays.insert(point.day) }
                    }
                } else { facts.supportedDays = Set(facts.days.map(\.day)) }
                supported.append(facts)
            }
        }
        guard supported.contains(where: { supports(proposedStart, timed: hasTime, facts: $0) }) else {
            return "The quote does not support this action's suggested date or time."
        }
        // Both endpoints must belong to one supporting action/date clause. An
        // unrelated second deadline must not turn into the first event's end.
        if let proposedEnd, !supported.contains(where: {
            supports(proposedStart, timed: hasTime, facts: $0) && supports(proposedEnd, timed: hasTime, facts: $0)
        }) { return "The quote does not support this action's complete date range." }
        return nil
    }

    private struct Day: Hashable {
        var year: Int; var month: Int; var day: Int
        func date(_ zone: TimeZone) -> Date? {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            guard let result = calendar.date(from: DateComponents(year: year, month: month, day: day)),
                  calendar.component(.year, from: result) == year, calendar.component(.month, from: result) == month,
                  calendar.component(.day, from: result) == day else { return nil }
            return result
        }
    }
    private struct Proposed { var date: Date; var day: Day; var hour: Int; var minute: Int; var second: Int }
    private struct Dated { var day: Day; var range: NSRange }
    private struct Clock { var hour: Int; var minute: Int; var second: Int; var range: NSRange }
    private struct Facts {
        var days: [Dated]; var clocks: [Clock]; var instants: [Date]; var dateWindow: Bool; var supportedDays: Set<Day> = []
    }
    private static func proposed(_ text: String, timed: Bool, zone: TimeZone) -> Proposed? {
        let pattern = timed ? "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:Z|[+-]\\d{2}:\\d{2})$" : "^\\d{4}-\\d{2}-\\d{2}$"
        guard matches(pattern, text).count == 1 else { return nil }
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let rawDay = Day(year: parts[0], month: parts[1], day: parts[2])
        guard rawDay.date(zone) != nil else { return nil }
        let date: Date
        if timed {
            let formatter = ISO8601DateFormatter()
            guard let parsed = formatter.date(from: text) else { return nil }
            let clock = text.dropFirst(11).prefix(8).split(separator: ":").compactMap { Int($0) }
            guard clock.count == 3, clock[0] < 24, clock[1] < 60, clock[2] < 60 else { return nil }
            if !text.hasSuffix("Z") {
                let offset = text.suffix(5).split(separator: ":").compactMap { Int($0) }
                guard offset.count == 2, offset[0] < 24, offset[1] < 60 else { return nil }
            }
            date = parsed
        } else { date = rawDay.date(zone)! }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let local = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return Proposed(date: date, day: .init(year: local.year!, month: local.month!, day: local.day!),
                        hour: local.hour!, minute: local.minute!, second: local.second!)
    }
    private static func supports(_ value: Proposed, timed: Bool, facts: Facts) -> Bool {
        guard facts.supportedDays.contains(value.day) else { return false }
        // An explicit offset timestamp supplies an instant independently of the
        // display zone; month-name/relative dates use the captured local zone.
        if timed, facts.instants.contains(value.date) { return true }
        let relevantDays = facts.days.filter { $0.day == value.day }
        guard !relevantDays.isEmpty else { return false }
        if !timed { return true }
        return facts.clocks.contains { clock in
            guard clock.hour == value.hour, clock.minute == value.minute, clock.second == value.second else { return false }
            if facts.dateWindow { return true }
            let distance = facts.days.map { ($0.day, gap($0.range, clock.range)) }
            guard let nearest = distance.map(\.1).min() else { return false }
            return distance.contains { $0.0 == value.day && $0.1 == nearest }
        }
    }

    private static let monthPattern = "(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"
    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
    private static func facts(_ text: String, human: Bool, now: Date, zone: TimeZone) -> Facts {
        let string = text as NSString
        var days: [Dated] = []; var instants: [Date] = []
        func add(_ year: Int?, _ month: Int?, _ day: Int?, _ range: NSRange) {
            guard let year, let month, let day else { return }
            let value = Day(year: year, month: month, day: day)
            if value.date(zone) != nil { days.append(.init(day: value, range: range)) }
        }
        for match in matches("\\b(\\d{4})-(\\d{2})-(\\d{2})(?:t\\d{2}:\\d{2}:\\d{2}(?:z|[+-]\\d{2}:\\d{2}))?\\b", text) {
            let timestamp = string.substring(with: match.range).uppercased()
            if timestamp.contains("T") {
                if let parsed = proposed(timestamp, timed: true, zone: zone) {
                    instants.append(parsed.date); add(parsed.day.year, parsed.day.month, parsed.day.day, match.range)
                }
            } else { add(int(match, 1, string), int(match, 2, string), int(match, 3, string), match.range) }
        }
        let years = Set(matches("\\b(?:19|20|21)\\d{2}\\b", text).compactMap { Int(string.substring(with: $0.range)) })
        let sharedYear = years.count == 1 ? years.first : nil
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let today = calendar.startOfDay(for: now)
        func year(_ match: NSTextCheckingResult, _ index: Int, _ month: Int?, _ day: Int?) -> Int? {
            if let explicit = int(match, index, string) { return explicit }
            if let sharedYear { return sharedYear }
            guard human, let month, let day else { return nil }
            let current = calendar.component(.year, from: today)
            let candidate = Day(year: current, month: month, day: day)
            guard let date = candidate.date(zone) else { return nil }
            return date >= today ? current : current + 1
        }
        for match in matches("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(" + monthPattern + ")\\.?\\s*(?:,?\\s*(\\d{4}))?\\b", text) {
            let month = months[String(string.substring(with: match.range(at: 2)).prefix(3))]
            let day = int(match, 1, string)
            add(year(match, 3, month, day), month, day, match.range)
        }
        for match in matches("\\b(" + monthPattern + ")\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?\\b", text) {
            let month = months[String(string.substring(with: match.range(at: 1)).prefix(3))]
            let day = int(match, 2, string)
            add(year(match, 3, month, day), month, day, match.range)
        }
        let compact = matches("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s*(?:-|to|and)\\s*(\\d{1,2})(?:st|nd|rd|th)?\\s+(" + monthPattern + ")\\.?\\s*(?:,?\\s*(\\d{4}))?\\b", text)
        for match in compact {
            let month = months[String(string.substring(with: match.range(at: 3)).prefix(3))]
            let first = int(match, 1, string), last = int(match, 2, string)
            let y = year(match, 4, month, first)
            add(y, month, first, match.range); add(y, month, last, match.range)
        }
        // Explicit human relative instructions use the original turn's day.
        // Source-relative wording has no source-sent anchor in this API.
        if human {
            for match in matches("\\b(day after tomorrow|tomorrow|today|in\\s+\\d{1,3}\\s+(?:days?|weeks?))\\b", text) {
                let wording = string.substring(with: match.range)
                let amount: Int
                if wording == "today" { amount = 0 }
                else if wording == "tomorrow" { amount = 1 }
                else if wording == "day after tomorrow" { amount = 2 }
                else {
                    let number = matches("\\d+", wording).first.map { Int((wording as NSString).substring(with: $0.range))! }!
                    amount = number * (wording.contains("week") ? 7 : 1)
                }
                if let date = calendar.date(byAdding: .day, value: amount, to: today) {
                    let c = calendar.dateComponents([.year, .month, .day], from: date)
                    add(c.year, c.month, c.day, match.range)
                }
            }
            if days.isEmpty {
                let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
                for match in matches("\\b(next|this)\\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\\b", text) {
                    let day = weekdays[string.substring(with: match.range(at: 2))]!
                    let current = calendar.component(.weekday, from: today)
                    let modifier = string.substring(with: match.range(at: 1))
                    // 'Next' is the next strictly later weekday. 'This' is the
                    // named day of the captured Monday-to-Sunday week.
                    let amount = modifier == "next" ? ((day - current + 6) % 7 + 1) : ((day + 5) % 7 - (current + 5) % 7)
                    if let date = calendar.date(byAdding: .day, value: amount, to: today) {
                        let c = calendar.dateComponents([.year, .month, .day], from: date)
                        add(c.year, c.month, c.day, match.range)
                    }
                }
            }
        }
        var clocks: [Clock] = []
        let clockPattern = "(?<![a-z0-9])([0-2]?\\d)(?::([0-5]\\d)(?::([0-5]\\d))?)?\\s*(a\\.?m\\.?|p\\.?m\\.?)(?![a-z])|(?<![a-z0-9])([01]?\\d|2[0-3]):([0-5]\\d)(?::([0-5]\\d))?(?!\\d)"
        for match in matches(clockPattern, text) {
            if let hour = int(match, 1, string), (1...12).contains(hour) {
                let pm = string.substring(with: match.range(at: 4)).hasPrefix("p")
                clocks.append(.init(hour: hour % 12 + (pm ? 12 : 0), minute: int(match, 2, string) ?? 0,
                                    second: int(match, 3, string) ?? 0, range: match.range))
            } else if let hour = int(match, 5, string) {
                clocks.append(.init(hour: hour, minute: int(match, 6, string)!, second: int(match, 7, string) ?? 0, range: match.range))
            }
        }
        let ordered = days.sorted { $0.range.location < $1.range.location }
        let joinedRange = ordered.indices.dropFirst().contains { index in
            let first = ordered[index - 1], second = ordered[index]
            guard NSMaxRange(first.range) <= second.range.location else { return false }
            let join = string.substring(with: NSRange(location: NSMaxRange(first.range), length: second.range.location - NSMaxRange(first.range)))
            return !matches("^\\s*(?:-|to)\\s*(?:(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\s+)?$", join).isEmpty
        }
        let window = !compact.isEmpty || joinedRange || (Set(days.map(\.day)).count > 1 && text.contains("between") && text.contains(" and "))
        return Facts(days: days, clocks: clocks, instants: instants, dateWindow: window)
    }

    private static func relevant(_ text: String, title: String, human: Bool) -> Bool {
        let titleWords = words(title), evidenceWords = words(text)
        let overlap = titleWords.intersection(evidenceWords).count
        if !titleWords.isEmpty, overlap >= max(titleWords.count == 1 ? 1 : 2, (titleWords.count + 1) / 2) { return true }
        guard human else { return false }
        if !titleWords.isEmpty, !matches("^(?:today|tomorrow|day after tomorrow|in\\s+\\d{1,3}\\s+(?:days?|weeks?)|(?:next|this)\\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))(?:\\s+at\\s+\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)?)?(?:\\s+please)?[.!]?$", text).isEmpty { return true }
        // Ordinary follow-up phrasing can identify the current action by pronoun.
        // A greeting or unrelated date mention is not action evidence.
        return !matches("\\b(?:add|set|create|schedule|remind|put|move|change|make|update|do|reschedule)\\b", text).isEmpty &&
            (!matches("\\b(?:it|that|this|those|them|me|deadline|task|calendar|reminder|report|presentation)\\b", text).isEmpty || overlap > 0)
    }
    private static func dateContinuation(_ text: String) -> Bool {
        !matches("^(?:\\d|scheduled\\b|due\\b|on\\b|from\\b|between\\b|at\\b|monday\\b|tuesday\\b|wednesday\\b|thursday\\b|friday\\b|saturday\\b|sunday\\b|" + monthPattern + "\\b)", text).isEmpty
    }
    private static func words(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["the", "a", "an", "and", "or", "for", "to", "of", "in", "on", "at", "by", "with", "from", "my", "your", "our", "this", "that", "it", "please", "add", "set", "create", "schedule", "remind", "put", "move", "change", "make", "update", "do", "submit", "complete", "required", "due", "deadline", "task", "entry", "calendar", "reminder", "project", "iib", "part", "engineering"]
        return Set(matches("[a-z0-9]+", normalise(text)).compactMap { match in
            var word = (normalise(text) as NSString).substring(with: match.range)
            if word == "submission" { word = "submit" }
            else if word.hasSuffix("s"), word.count > 4 { word.removeLast() }
            return word.count > 1 && !ignored.contains(word) ? word : nil
        })
    }
    private static func normalise(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
    }
    private static func matches(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
    }
    private static func int(_ match: NSTextCheckingResult, _ index: Int, _ text: NSString) -> Int? {
        let range = match.range(at: index); return range.location == NSNotFound ? nil : Int(text.substring(with: range))
    }
    private static func gap(_ left: NSRange, _ right: NSRange) -> Int {
        max(0, max(left.location - NSMaxRange(right), right.location - NSMaxRange(left)))
    }
}

private extension String {
    func components(separatedBy expression: NSRegularExpression) -> [String] {
        let text = self as NSString; var cursor = 0; var parts: [String] = []
        for match in expression.matches(in: self, range: NSRange(startIndex..., in: self)) {
            parts.append(text.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = NSMaxRange(match.range)
        }
        parts.append(text.substring(from: cursor)); return parts
    }
}
