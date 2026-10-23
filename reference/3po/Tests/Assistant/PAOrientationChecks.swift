import Foundation
@main struct PAOrientationChecks {
    static func main() throws {
        let now = Calendar.current.startOfDay(for:.now), end = Calendar.current.date(byAdding:.day,value:90,to:now)!
        let events = [AgendaEvent(id:"b",calendarID:"allowed",title:"Same",start:now,end:now.addingTimeInterval(3600),allDay:false,location:"",sourceLabel:""),AgendaEvent(id:"a",calendarID:"excluded",title:"Same",start:now,end:now.addingTimeInterval(3600),allDay:false,location:"",sourceLabel:""),AgendaEvent(id:"c",calendarID:"allowed",title:"Later",start:end.addingTimeInterval(-3600),end:end,allDay:false,location:"",sourceLabel:"")]
        let state = PAOrientation(start:now,end:end,refreshed:now,calendar:.init(sources:[],events:events.reversed()))
        precondition(state.events(excluding:["excluded"]).map(\.id) == ["b","c"])
        precondition(state.events(excluding:[],limit:1).count == 1)
        precondition(state.coverage(enabledCount:2).contains("end exclusive") && state.coverage(enabledCount:2).contains("outside this window/cap"))
        precondition(state.coverage(now:Calendar.current.date(byAdding:.day,value:1,to:now)!,enabledCount:2).hasPrefix("Cached from an earlier day."))
        let restored = try JSONDecoder().decode(PAOrientation.self,from:JSONEncoder().encode(state))
        precondition(restored.events(excluding:["excluded"]).map(\.id) == ["b","c"] && restored.end == end)
        print("PASS PA orientation: independent date range, stable identity/order, source exclusions, caps, stale coverage and persistence.")
    }
}
