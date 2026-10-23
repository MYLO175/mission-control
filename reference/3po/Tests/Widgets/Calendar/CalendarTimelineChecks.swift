import Foundation
@main struct Checks {
    static func main() {
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Europe/London")!
        func day(_ y:Int,_ m:Int,_ d:Int)->DateInterval { calendar.dateInterval(of:.day,for:calendar.date(from:DateComponents(year:y,month:m,day:d))!)! }
        func event(_ id:String,_ start:Date,_ end:Date)->AgendaEvent { .init(id:id,calendarID:"test",title:id,start:start,end:end,allDay:false,location:"",sourceLabel:"Test") }
        let range = day(2026,10,2), start = range.start.addingTimeInterval(9*3600)
        let a = event("a",start,start.addingTimeInterval(3600)), b = event("b",start.addingTimeInterval(1800),start.addingTimeInterval(7200)), c = event("c",start.addingTimeInterval(3600),start.addingTimeInterval(5400))
        let result = CalendarTimelineLayout.segments([c,b,a],interval:range)
        assert(result.map(\.id) == ["a","b","c"])
        assert(result.map(\.lane) == [0,1,0]); assert(result.allSatisfy { $0.lanes == 2 })
        let overnight = CalendarTimelineLayout.segments([event("night",range.start.addingTimeInterval(-3600),range.start.addingTimeInterval(1800))],interval:range)
        assert(overnight[0].start == range.start && overnight[0].end == range.start.addingTimeInterval(1800))
        assert(day(2026,3,29).duration == 23*3600 && day(2026,10,25).duration == 25*3600)
        let fall = day(2026,10,25), first = fall.start.addingTimeInterval(1.5*3600), second = first.addingTimeInterval(3600)
        assert(calendar.component(.hour,from:first) == calendar.component(.hour,from:second))
        let repeated = CalendarTimelineLayout.segments([event("first",first,first.addingTimeInterval(600)),event("second",second,second.addingTimeInterval(600))],interval:fall)
        assert(repeated.count == 2 && repeated[1].start.timeIntervalSince(repeated[0].start) == 3600)
        assert(CalendarTimelineFocus.columnWidth(available:700,days:7) == 125)
        assert(CalendarTimelineFocus.columnWidth(available:900,days:1) == 900)
        assert(CalendarTimelineFocus.columnWidth(available:1200,days:7)*7+48 == 1200)
        let early = range.start.addingTimeInterval(3*3600), afternoon = range.start.addingTimeInterval(15*3600)
        assert(calendar.component(.hour,from:CalendarTimelineFocus.hour(on:range.start,now:early,events:[],calendar:calendar)) == 8)
        assert(calendar.component(.hour,from:CalendarTimelineFocus.hour(on:range.start,now:afternoon,events:[],calendar:calendar)) == 14)
        let future = day(2026,10,4)
        assert(calendar.component(.hour,from:CalendarTimelineFocus.hour(on:future.start,now:early,events:[],calendar:calendar)) == 8)
        let morningEvent = event("early",future.start.addingTimeInterval(7*3600),future.start.addingTimeInterval(8*3600))
        assert(calendar.component(.hour,from:CalendarTimelineFocus.hour(on:future.start,now:early,events:[morningEvent],calendar:calendar)) == 6)
        let work = CalendarTimelineFocus.workingHours(on:fall.start,calendar:calendar)
        assert(calendar.component(.hour,from:work.start) == 9 && calendar.component(.hour,from:work.end) == 18)
        assert(work.duration == 9*3600)
        assert(CalendarTimelineFocus.anchor(fall.start.addingTimeInterval(3600)) != CalendarTimelineFocus.anchor(fall.start.addingTimeInterval(7200)))
        let dropped = CalendarTimelineMove.start(on:range.start,y:9.14*CalendarTimelineFocus.hourHeight,calendar:calendar)!
        assert(dropped == range.start.addingTimeInterval(9.25*3600))
        assert(CalendarTimelineMove.start(on:range.start,y:-1,calendar:calendar) == nil && CalendarTimelineMove.start(on:range.start,y:.nan,calendar:calendar) == nil)
        assert(CalendarTimelineMove.start(on:fall.start,y:1.5*CalendarTimelineFocus.hourHeight,calendar:calendar) == first)
        assert(CalendarTimelineMove.start(on:fall.start,y:2.5*CalendarTimelineFocus.hourHeight,calendar:calendar) == second)
        let spring = day(2026,3,29)
        assert(CalendarTimelineMove.start(on:spring.start,y:2000,calendar:calendar) == spring.end.addingTimeInterval(-900))
        let shifted = CalendarTimelineMove.translated(start:afternoon,day:range.start,dx:100,dy:52,columnWidth:125,visibleDays:7,range:DateInterval(start:range.start,end:range.start.addingTimeInterval(7*86400)),calendar:calendar)!
        assert(shifted.day == range.end && shifted.y == 16*52)
        let single = CalendarTimelineMove.translated(start:afternoon,day:range.start,dx:300,dy:-52,columnWidth:900,visibleDays:1,range:range,calendar:calendar)!
        assert(single.day == range.start && single.y == 14*52)
        assert(CalendarTimelineMove.translated(start:afternoon,day:range.start,dx:-500,dy:0,columnWidth:125,visibleDays:7,range:range,calendar:calendar) == nil)
        assert(CalendarTimelineMove.translated(start:afternoon,day:range.start,dx:.nan,dy:0,columnWidth:125,visibleDays:7,range:range,calendar:calendar) == nil)
        let dstDrag = CalendarTimelineMove.translated(start:second,day:fall.start,dx:0,dy:0,columnWidth:900,visibleDays:1,range:fall,calendar:calendar)!
        assert(CalendarTimelineMove.start(on:dstDrag.day,y:dstDrag.y,calendar:calendar) == second)
        assert(CalendarTimelineMove.destination(start:start,day:range.start,dx:0,dy:65,columnWidth:900,visibleDays:1,range:range,calendar:calendar) == start.addingTimeInterval(4500))
        assert(CalendarTimelineMove.destination(start:range.start.addingTimeInterval(-3600),day:range.start,dx:0,dy:52,columnWidth:900,visibleDays:1,range:range,calendar:calendar) == range.start)
        assert(CalendarTimelineMove.destination(start:start,day:range.start,dx:-500,dy:0,columnWidth:125,visibleDays:7,range:range,calendar:calendar) == nil)
        assert(CalendarTimelineMove.destination(start:second,day:fall.start,dx:0,dy:0,columnWidth:900,visibleDays:1,range:fall,calendar:calendar) == second)
        print("PASS: overlap lanes, clipped overnight moves, quarter-hour direct drops, week boundaries, viewport focus and distinct repeated DST hours")
    }
}
