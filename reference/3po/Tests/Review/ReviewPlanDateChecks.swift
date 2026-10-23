import Foundation

@main struct ReviewPlanDateChecks {
    static func main() {
        var total = 0
        let captured = ISO8601DateFormatter().date(from: "2026-10-13T22:30:00Z")!
        func check(_ expected: Bool, _ quote: String, title: String = "Technical milestone report", basis: String = "source", human: String? = nil,
                   kind: String = "calendar", start: String? = "2027-01-21", end: String? = nil, timed: Bool = false,
                   now: Date = captured, zone: String = "Europe/London", _ message: String) {
            let rejection = ReviewPlanDateRules.rejection(quote: quote, basis: basis, human: human ?? quote, title: title,
                kind: kind, start: start, end: end, hasTime: timed, now: now, timeZoneID: zone)
            precondition((rejection == nil) == expected, "\(message): \(rejection ?? "unexpected acceptance")")
            total += 1
        }
        let milestone = "Technical Milestone Report Submission\n4:00 pm, Thursday 21 January 2027"
        check(true, milestone, "Heading and date-only deadline marker")
        check(true, milestone, start: "2027-01-21T16:00:00Z", timed: true, "Exact timed deadline")
        check(true, milestone, kind: "projectTask", "Date-only project deadline retains timed evidence")
        check(true, "Technical milestone report is due 21 January 2027 at 4pm.", start: "2027-01-21T16:00:00Z", timed: true, "Compact 4pm")
        check(true, "Technical milestone report is due January 21st, 2027 at 16:00.", start: "2027-01-21T16:00:00Z", timed: true, "Month-first ordinal and 24-hour clock")
        check(false, milestone, start: "2027-01-22", "Wrong day")
        check(false, milestone, start: "2028-01-21", "Wrong year")
        check(false, milestone, start: "2027-01-21T15:00:00Z", timed: true, "Wrong clock")
        check(false, milestone, start: "2027-01-21T16:00:01Z", timed: true, "Invented seconds")
        check(false, milestone, start: "2027-01-21T16:00:00+01:00", timed: true, "Offset changes the local deadline instant")
        check(true, milestone, start: "2027-01-21T17:00:00+01:00", timed: true, "Equivalent instant rendered in captured zone")
        check(false, milestone, start: "2027-01-21T16:00:00Z", end: "2027-01-21T16:15:00Z", timed: true, "No invented explicit event duration")
        check(false, milestone, kind: "projectTask", start: "2027-01-21T16:00:00Z", timed: true, "Project due values stay date-only")
        let presentations = "Michaelmas Presentations (Mini-Conferences)\nScheduled between Thursday 26 November and Friday 27 November 2026, from 8:30 am to 5:00 pm."
        check(true, presentations, title: "Michaelmas presentations", start: "2026-11-26", end: "2026-11-27", "Shared-year multi-day range")
        check(true, presentations, title: "Michaelmas presentations", start: "2026-11-26T08:30:00Z", end: "2026-11-27T17:00:00Z", timed: true, "Quoted date and time window")
        check(false, presentations, title: "Michaelmas presentations", start: "2026-11-26", end: "2026-11-28", "Unsupported range extension")
        check(true, "Michaelmas presentations: 26–27 November 2026.", title: "Michaelmas presentations", start: "2026-11-26", end: "2026-11-27", "Compact en-dash range")
        check(true, "Michaelmas presentations: 26 to 27 Nov. 2026.", title: "Michaelmas presentations", start: "2026-11-26", end: "2026-11-27", "Abbreviated compact range")
        check(true, "Michaelmas presentations: 26 and 27 November 2026.", title: "Michaelmas presentations", start: "2026-11-26", end: "2026-11-27", "Compact and range")
        check(true, "Final Project Presentations\nScheduled for Friday 4 June 2027 (Week 5).", title: "Final project presentations", start: "2027-06-04", "Explicit calendar anchor with numbered-week annotation")
        check(false, "Technical milestone report due in Week 5.", "Unanchored numbered week")
        let hazard = "A hazard assessment form must be completed with your supervisor and submitted to the Safety Office."
        check(false, hazard, title: "Submit IIB hazard assessment", start: "2026-10-14", "Undated hazard quote cannot invent deadline")
        check(true, hazard, title: "Submit IIB hazard assessment", kind: "projectTask", start: nil, "Undated project task allowed")
        check(false, hazard + "\nTechnical milestone report is due 21 January 2027 at 4pm.", title: "Submit hazard assessment", "No unrelated report date borrowing")
        check(false, "Technical milestone report is due 21 January 2027. Final report is due 31 May 2027.", start: "2027-01-21", end: "2027-05-31", "Independent report deadlines are not one event range")
        check(false, "Final report due 31 May 2027.", title: "Technical milestone report", start: "2027-05-31", "Specific action title must match evidence")
        check(false, "Final presentations scheduled for 4 June 2027.", title: "Michaelmas presentations", start: "2027-06-04", "Shared generic action word does not identify the same deadline")
        check(false, "Technical milestone report due 21 January 2027 at 4pm, final report due 31 May 2027 at 5pm.", start: "2027-05-31", "No comma-clause action borrowing")
        check(false, "Technical milestone report due 21 January 2027 at 4pm, final report due 31 May 2027 at 5pm.", start: "2027-01-21T17:00:00Z", timed: true, "No clock borrowing from an unrelated date")
        check(true, "Michaelmas presentations scheduled from 26 November 2026 to 27 November 2026, from 8:30 am to 5pm.", title: "Michaelmas presentations", start: "2026-11-26T08:30:00Z", end: "2026-11-27T17:00:00Z", timed: true, "Repeated dates joined as explicit window")
        check(true, "Technical milestone report due 2027-01-21T16:00:00+01:00.", start: "2027-01-21T15:00:00Z", timed: true, "Exact quoted offset timestamp")
        check(true, "Technical milestone report due 2027-01-21T00:30:00+02:00.", start: "2027-01-20", "Offset timestamp date-only marker uses captured zone")
        check(false, "Technical milestone report due 21 January.", "Yearless source deadline requires year evidence")
        check(true, "Move the technical milestone report to 21 January.", basis: "human", "Human yearless named date uses next occurrence")
        check(false, "hi", title: "Submit hazard assessment", basis: "human", start: "2026-10-14", "Greeting cannot support arbitrary date")
        check(true, "Set the hazard assessment deadline for tomorrow.", title: "Submit hazard assessment", basis: "human", kind: "projectTask", start: "2026-10-14", "Explicit human relative project deadline")
        check(true, "Move it to tomorrow at 4pm.", basis: "human", start: "2026-10-14T15:00:00Z", timed: true, "Ordinary pronoun and captured BST clock")
        check(false, "Move it to tomorrow.", basis: "human", start: "2026-10-14T15:00:00Z", timed: true, "Relative day does not invent clock")
        check(false, "Move it to tomorrow.", basis: "human", start: "2026-10-15", "Relative request bound to captured day")
        check(false, "Move it to tomorrow.", basis: "human", human: "hi", start: "2026-10-14", "Human evidence must be exact current words")
        check(false, "Hazard assessment due tomorrow.", title: "Hazard assessment", start: "2026-10-14", "Source relative day has no sent-date anchor")
        let localNextDay = ISO8601DateFormatter().date(from: "2026-10-13T23:30:00Z")!
        check(true, "Move it to tomorrow.", basis: "human", start: "2026-10-15", now: localNextDay, "Captured local date differs from UTC")
        let beforeDST = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        check(true, "Move it to tomorrow at 4pm.", basis: "human", start: "2026-10-25T16:00:00Z", timed: true, now: beforeDST, "Relative date crosses DST without fixed 24-hour arithmetic")
        check(true, "Move it to the day after tomorrow.", basis: "human", start: "2026-10-15", "Day after tomorrow")
        check(true, "Move it in 2 weeks.", basis: "human", start: "2026-10-27", "Relative weeks")
        check(true, "Move it to next Tuesday.", basis: "human", start: "2026-10-20", "Next same weekday is strictly later")
        check(true, "Tomorrow please.", basis: "human", start: "2026-10-14", "Ordinary relative-date clarification")
        check(true, "Remind me tomorrow.", basis: "human", start: "2026-10-14", "Ordinary relative reminder request")
        check(true, "Move it to this Friday.", basis: "human", start: "2026-10-16", "This weekday uses captured week")
        check(false, "Move it to next week.", basis: "human", start: "2026-10-19", "Ambiguous week is not an exact day")
        check(false, "Technical milestone report due 30 February 2027.", start: "2027-02-30", "Impossible proposed date")
        check(false, milestone, start: "2027-01-21T25:00:00Z", timed: true, "Invalid clock")
        check(false, milestone, start: "2027-01-21T16:00:00Z", "Timed value with date-only mode")
        check(false, milestone, start: "2027-01-21", timed: true, "Date-only value with timed mode")
        check(false, milestone, start: "2027-01-21", end: "2027-01-20", "Reversed range")
        check(false, milestone, zone: "Invalid/Zone", "No time-zone fallback")
        check(false, milestone, basis: "model", "Model output is not authority/evidence basis")
        check(false, milestone, start: nil, "Calendar needs concrete date")
        check(false, milestone, kind: "projectTask", start: nil, end: "2027-01-21", "End without start rejected")
        print("Review plan date evidence: \(total)/\(total) source-free checks passed")
    }
}
