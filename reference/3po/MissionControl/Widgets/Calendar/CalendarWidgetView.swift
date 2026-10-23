import SwiftUI

struct CalendarWidgetView: View {
    @Environment(\.workspacePalette) private var palette
    @Bindable var model: DashboardModel
    @Binding var configuration: WidgetConfiguration
    var widgetID: UUID? = nil
    #if DEBUG
    var previewFixture: CalendarDragFixture? = nil
    #endif
    @State private var snapshot = CalendarSnapshot(sources:[],events:[])
    @State private var loading = false
    @State private var error: String?
    @State private var updated: Date?
    @State private var showDatePicker = false
    @State private var selectedEvent: CalendarEventSelection?
    @State private var focusRequest = 0
    @State private var timelineSpace = UUID().uuidString
    @State private var dragCapture: CalendarEventDragCapture?
    @State private var pendingMove: AgendaEvent?
    @State private var moveError: String?
    @State private var mounted = false
    private var calendar: Calendar { .current }
    private var mode: String { configuration.calendarMode }
    private var range: DateInterval {
        if mode == "month" {
            let month = calendar.dateInterval(of:.month,for:configuration.date)!
            let start = calendar.dateInterval(of:.weekOfYear,for:month.start)!.start
            return DateInterval(start:start,end:calendar.date(byAdding:.day,value:42,to:start)!)
        }
        if mode == "week" { return calendar.dateInterval(of:.weekOfYear,for:configuration.date)! }
        let start = calendar.startOfDay(for:configuration.date)
        return DateInterval(start:start,end:calendar.date(byAdding:.day,value:mode == "day" ? 1 : 7,to:start)!)
    }
    private var events: [AgendaEvent] {
        snapshot.events.filter { !configuration.sourceExclusions.contains($0.calendarID) }.map { event in
            pendingMove?.id == event.id ? pendingMove! : event
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                Label("Calendar",systemImage:"calendar").font(.title3.weight(.semibold))
                SourceStatusIndicator(title:"Calendar",health:SourceHealth(lastSuccess:updated,error:error,loading:loading))
                Spacer(minLength:4)
                Menu { Button("Show all") { configuration.sourceExclusions = [] }; Divider(); ForEach(snapshot.sources) { source in
                    Toggle(source.displayLabel,isOn:Binding(get:{ !configuration.sourceExclusions.contains(source.id) },set:{ enabled in if enabled { configuration.sourceExclusions.remove(source.id) } else { configuration.sourceExclusions.insert(source.id) } }))
                } } label: { Image(systemName:"line.3.horizontal.decrease") }.menuStyle(.borderlessButton).fixedSize().help("Filter calendars").accessibilityLabel("Filter calendars")
                Button { model.newNativeItem(.event,date:configuration.date) } label: { Image(systemName:"plus") }.help("New event").accessibilityLabel("New event").disabled(model.writing)
                Picker("Calendar view",selection:$configuration.calendarMode) {
                    Text("Agenda").tag("agenda"); Text("Day").tag("day"); Text("Week").tag("week"); Text("Month").tag("month")
                }.pickerStyle(.menu).labelsHidden().frame(width:90)
            }.buttonStyle(.borderless).controlSize(.small)
            HStack(spacing:8) {
                Button { showDatePicker.toggle() } label: {
                    HStack(spacing:4) { Text(configuration.date.formatted(mode == "month" ? .dateTime.month(.wide).year() : .dateTime.weekday(.abbreviated).day().month(.wide))).font(.callout.weight(.medium)); Image(systemName:"chevron.down").font(.caption2) }
                }.help("Choose calendar date").accessibilityLabel("Choose calendar date").popover(isPresented:$showDatePicker) {
                    DatePicker("Calendar date",selection:$configuration.date,displayedComponents:.date).datePickerStyle(.graphical).labelsHidden().padding(12)
                }
                Spacer(minLength:4)
                Button { navigate(-1) } label: { Image(systemName:"chevron.left") }.help("Previous calendar period").accessibilityLabel("Previous calendar period")
                Button(mode == "day" || mode == "week" ? "Now" : "Today",action:returnToToday)
                Button { navigate(1) } label: { Image(systemName:"chevron.right") }.help("Next calendar period").accessibilityLabel("Next calendar period")
            }.buttonStyle(.borderless).controlSize(.small)
            if let error { Text((updated == nil ? "" : "Stale · ") + error).font(.caption).foregroundStyle(.orange).lineLimit(2) }
            if mode == "month" { monthView }
            else if mode == "day" || mode == "week" { timelineView }
            else { agendaView }
        }.padding(16).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .onAppear { mounted=true; returnToToday() }
            .onDisappear { mounted=false; dragCapture=nil }
            .onChange(of:widgetID) { dragCapture=nil; returnToToday() }
            .onChange(of:model.chatGPT.activeID) { dragCapture=nil }
            .onChange(of:model.sourceRevision) { dragCapture=nil }
            .onChange(of:configuration.calendarMode) { dragCapture=nil }
            .onChange(of:configuration.sourceExclusions) { dragCapture=nil }
            .task(id:"\(range.start.timeIntervalSince1970):\(range.end.timeIntervalSince1970):\(model.widgetCalendars.revision)") { await load() }
            .onChange(of:configuration.date) { showDatePicker = false; dragCapture=nil }
            .sheet(item:$selectedEvent) { NativeItemEditor(model:model,target:.event($0.event)) }
            .alert("Calendar move",isPresented:Binding(get:{ moveError != nil },set:{ if !$0 { moveError=nil } })) {
                Button("OK",role:.cancel) { moveError=nil }
            } message: { Text(moveError ?? "") }
    }
    private func returnToToday() {
        configuration.date = .now
        focusRequest += 1
    }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            let value: CalendarSnapshot
            #if DEBUG
            if let previewFixture { value = try await model.eventKit.calendarDragSnapshot(previewFixture,range:range) }
            else { value = ProcessInfo.processInfo.arguments.contains("--sample") ? model.calendarData : try await model.widgetCalendars.load(range) }
            #else
            value = ProcessInfo.processInfo.arguments.contains("--sample") ? model.calendarData : try await model.widgetCalendars.load(range)
            #endif
            try Task.checkCancellation(); snapshot = value; error = nil; updated = .now
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    private func navigate(_ direction: Int) {
        configuration.date = calendar.date(byAdding:mode == "month" ? .month : .day,value:direction * (mode == "week" ? 7 : 1),to:configuration.date)!
    }
    private func color(_ event: AgendaEvent) -> Color { DashboardView(model:model).sourceColor(event.calendarID,explicit:snapshot.sources.first { $0.id == event.calendarID }?.color) }
    private func dayEvents(_ date: Date) -> [AgendaEvent] { events.filter { DateRules.overlaps($0,day:date) } }
    private func select(_ event: AgendaEvent) { guard pendingMove == nil else { return }; selectedEvent = CalendarEventSelection(event:event) }
    private func canDrag(_ event: AgendaEvent) -> Bool {
        !model.writing && !model.assistant.busy && pendingMove == nil && !event.allDay && !ProcessInfo.processInfo.arguments.contains("--sample") && snapshot.sources.contains(where:{ $0.id == event.calendarID && $0.writable })
    }
    private func beginDrag(_ event: AgendaEvent) {
        guard dragCapture == nil, canDrag(event) else { return }
        dragCapture = CalendarEventDragCapture(event:event,account:model.chatGPT.activeID,sourceRevision:model.sourceRevision,widgetID:widgetID,date:configuration.date,mode:mode,exclusions:configuration.sourceExclusions)
    }
    private func dragStillValid(_ capture: CalendarEventDragCapture) -> Bool {
        mounted && capture.account == model.chatGPT.activeID && capture.sourceRevision == model.sourceRevision && capture.widgetID == widgetID && capture.date == configuration.date && capture.mode == mode && capture.exclusions == configuration.sourceExclusions
    }
    private func move(_ event: AgendaEvent, to start: Date?) {
        let capture = dragCapture; dragCapture=nil
        guard let capture, capture.event.id == event.id, dragStillValid(capture), canDrag(event), let start, start != event.start else { return }
        var preview=event; preview.start=start; preview.end=start.addingTimeInterval(event.end.timeIntervalSince(event.start))
        pendingMove=preview
        Task { @MainActor in
            defer { pendingMove=nil }
            do {
                try await model.moveCalendarEvent(capture.event,to:start,valid:{ dragStillValid(capture) })
                await load()
            } catch { await load(); moveError=error.localizedDescription }
        }
    }
    private func eventButton(_ event: AgendaEvent) -> some View {
        Button { select(event) } label: {
            HStack(alignment:.top,spacing:7) {
                RoundedRectangle(cornerRadius:2).fill(color(event)).frame(width:3)
                VStack(alignment:.leading,spacing:4) {
                    if !event.allDay { Text(event.start.formatted(date:.omitted,time:.shortened) + " – " + event.end.formatted(date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                    Text(event.title).font(.callout.weight(.medium)).lineLimit(3)
                    if !event.location.isEmpty { Text(event.location).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Text(snapshot.sources.first(where:{ $0.id == event.calendarID })?.displayLabel ?? event.sourceLabel).font(.caption2).foregroundStyle(color(event)).lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.padding(.vertical,5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var agendaView: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:12) {
                ForEach(0..<7,id:\.self) { offset in
                    let day = calendar.date(byAdding:.day,value:offset,to:range.start)!, items = dayEvents(day)
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.subheadline.weight(.semibold))
                    if items.isEmpty { Text("Nothing scheduled").font(.callout).foregroundStyle(.secondary) }
                    ForEach(items.filter(\.allDay)) { eventButton($0) }
                    ForEach(items.filter { !$0.allDay }) { eventButton($0) }
                    Divider()
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private var monthView: some View {
        GeometryReader { geo in
            let height = max(64,(geo.size.height-28)/6)
            VStack(spacing:4) {
                HStack { ForEach(0..<7,id:\.self) { i in Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday-1+i)%7]).font(.caption.weight(.semibold)).frame(maxWidth:.infinity) } }
                ScrollView {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:7),spacing:4) {
                        ForEach(0..<42,id:\.self) { offset in
                            let date = calendar.date(byAdding:.day,value:offset,to:range.start)!, items = dayEvents(date)
                            VStack(alignment:.leading,spacing:4) {
                                Button { configuration.date = date; configuration.calendarMode = "day" } label: {
                                    Text(date.formatted(.dateTime.day())).font(.caption.weight(.semibold)).foregroundStyle(calendar.isDateInToday(date) ? Color.accentColor : Color.primary)
                                }.buttonStyle(.plain).accessibilityLabel("Open " + date.formatted(date:.complete,time:.omitted))
                                ForEach(items.prefix(max(1,Int((height-28)/21)))) { event in Button { select(event) } label: { Text(event.title).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(3).background(color(event).opacity(0.12),in:RoundedRectangle(cornerRadius:3)) }.buttonStyle(.plain) }
                                if items.count > max(1,Int((height-28)/21)) { Text("+\(items.count-max(1,Int((height-28)/21))) more").font(.caption2).foregroundStyle(.secondary) }
                                Spacer(minLength:0)
                            }.padding(6).frame(maxWidth:.infinity).frame(height:height).background(Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:5))
                                .opacity(calendar.component(.month,from:date) == calendar.component(.month,from:configuration.date) ? 1 : 0.45)
                        }
                    }
                }
            }
        }
    }
    private var timelineView: some View {
        GeometryReader { geometry in
            let days = mode == "week" ? 7 : 1
            let width = CalendarTimelineFocus.columnWidth(available:max(1,geometry.size.width-14),days:days)
            let focusDay = days == 7 && range.contains(Date.now) ? Date.now : range.start
            let focus = focusRequest > 0 && range.contains(Date.now) ? max(Calendar.current.dateInterval(of:.hour,for:.now)!.start.addingTimeInterval(-3600),Calendar.current.startOfDay(for:.now)) : CalendarTimelineFocus.hour(on:focusDay,now:.now,events:events)
            let allDayCount = (0..<days).map { dayEvents(calendar.date(byAdding:.day,value:$0,to:range.start)!).filter(\.allDay).count }.max() ?? 0
            let allDayHeight = Double(min(3,allDayCount))*24 + (allDayCount > 3 ? 20 : 0)
            ScrollViewReader { proxy in
                ScrollView(days == 1 ? .vertical : [.horizontal,.vertical]) {
                    LazyVStack(spacing:0,pinnedViews:[.sectionHeaders]) {
                        Section {
                            HStack(alignment:.top,spacing:8) {
                                ForEach(0..<days,id:\.self) { offset in
                                    let day = calendar.date(byAdding:.day,value:offset,to:range.start)!
                                    CalendarDayTimeline(events:dayEvents(day).filter { !$0.allDay },day:day,color:color,select:select,canDrag:canDrag,coordinateSpace:timelineSpace,activeDragID:dragCapture?.event.id,beginDrag:beginDrag,previewStart:{ start,dx,dy in
                                        CalendarTimelineMove.destination(start:start,day:day,dx:dx,dy:dy,columnWidth:width,visibleDays:days,range:range)
                                    },move:move).frame(width:width)
                                        .zIndex(dayEvents(day).contains(where:{ $0.id == dragCapture?.event.id }) ? 1 : 0)
                                }
                            }.coordinateSpace(name:timelineSpace).padding(.bottom,10)
                        } header: {
                            HStack(alignment:.top,spacing:8) {
                                ForEach(0..<days,id:\.self) { offset in
                                    let day = calendar.date(byAdding:.day,value:offset,to:range.start)!
                                    VStack(alignment:.leading,spacing:6) {
                                        Text(day.formatted(.dateTime.weekday(.abbreviated).day())).font(.subheadline.weight(.semibold)).foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
                                        if allDayCount > 0 {
                                            let items = dayEvents(day).filter(\.allDay)
                                            VStack(alignment:.leading,spacing:3) {
                                                ForEach(items.prefix(3)) { event in Button { select(event) } label: { Text("All day · " + event.title).font(.caption2).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading).padding(4).background(color(event).opacity(0.12),in:RoundedRectangle(cornerRadius:4)) }.buttonStyle(.plain).help(event.title) }
                                                if items.count > 3 { Button("+\(items.count-3) all-day events") { configuration.date = day; configuration.calendarMode = "agenda" }.font(.caption2).buttonStyle(.borderless) }
                                            }.frame(height:allDayHeight,alignment:.top)
                                        }
                                    }.frame(width:width,alignment:.leading)
                                }
                            }.padding(.vertical,8)
                                .background(palette[.widget])
                                .overlay(alignment:.bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height:1) }
                        }
                    }.frame(width:Double(days)*width+Double(days-1)*8)

                }
                .task(id:"\(mode):\(range.start.timeIntervalSince1970):\(focusRequest)") {
                    await Task.yield()
                    proxy.scrollTo(CalendarTimelineFocus.anchor(focus),anchor:.top)
                }
            }
        }
    }
}
private struct CalendarEventSelection: Identifiable {
    let id = UUID()
    var event: AgendaEvent
}
private struct CalendarEventDragCapture {
    var event: AgendaEvent; var account: String?; var sourceRevision: Int; var widgetID: UUID?
    var date: Date; var mode: String; var exclusions: Set<String>
}
private struct CalendarDayTimeline: View {
    var events: [AgendaEvent]; var day: Date; var color: (AgendaEvent)->Color; var select: (AgendaEvent)->Void
    var canDrag: (AgendaEvent)->Bool
    var coordinateSpace: String
    var activeDragID: String?
    var beginDrag: (AgendaEvent)->Void
    var previewStart: (Date,Double,Double)->Date?
    var move: (AgendaEvent,Date?)->Void
    private var interval: DateInterval { Calendar.current.dateInterval(of:.day,for:day)! }
    private let hourHeight = CalendarTimelineFocus.hourHeight
    var body: some View {
        let hours = Int(interval.duration/3600)
        let work = CalendarTimelineFocus.workingHours(on:day)
        ZStack(alignment:.topLeading) {
            Rectangle().fill(Color.accentColor.opacity(0.035)).padding(.leading,40).frame(height:work.duration/3600*hourHeight).offset(y:work.start.timeIntervalSince(interval.start)/3600*hourHeight)
            // Real stacked row bounds let ScrollViewReader locate each hour.
            // Offset-only rows all retain their midnight layout origin.
            VStack(spacing:0) {
                ForEach(0..<hours,id:\.self) { hour in
                    let date = Calendar.current.date(byAdding:.hour,value:hour,to:interval.start)!
                    HStack(alignment:.top,spacing:4) {
                        Text(date.formatted(.dateTime.hour().minute())).font(.system(size:10)).foregroundStyle(.secondary).frame(width:36)
                        Rectangle().fill(Color.primary.opacity(0.07)).frame(height:1)
                    }.frame(height:hourHeight,alignment:.top).id(CalendarTimelineFocus.anchor(date))
                        .help(date.formatted(date:.omitted,time:.shortened) + " " + (Calendar.current.timeZone.abbreviation(for:date) ?? ""))
                }
            }
            GeometryReader { geo in
                ZStack(alignment:.topLeading) {
                    ForEach(CalendarTimelineLayout.segments(events,interval:interval)) { segment in
                        let height = max(CalendarTimelineFocus.minimumEventHeight,segment.end.timeIntervalSince(segment.start)/3600*hourHeight)
                        CalendarTimedEventCard(event:segment.event,color:color(segment.event),height:height,movable:canDrag(segment.event),coordinateSpace:coordinateSpace,select:{ select(segment.event) },beginDrag:{ beginDrag(segment.event) },previewStart:{ dx,dy in previewStart(segment.event.start,dx,dy) },move:{ dx,dy in move(segment.event,previewStart(segment.event.start,dx,dy)) })
                            .frame(width:max(1,(geo.size.width-40)/CGFloat(segment.lanes)-3),height:height)
                            .offset(x:40+CGFloat(segment.lane)*(geo.size.width-40)/CGFloat(segment.lanes),y:segment.start.timeIntervalSince(interval.start)/3600*hourHeight)
                            .zIndex(segment.id == activeDragID ? 1 : 0)
                    }
                }
            }
            TimelineView(.periodic(from:.now,by:60)) { context in
                if interval.contains(context.date) && context.date < interval.end {
                    HStack(spacing:0) { Circle().fill(.red).frame(width:6,height:6); Rectangle().fill(.red.opacity(0.8)).frame(height:1) }.padding(.leading,37).offset(y:context.date.timeIntervalSince(interval.start)/3600*hourHeight)
                        .accessibilityLabel("Current time " + context.date.formatted(date:.omitted,time:.shortened)).allowsHitTesting(false)
                }
            }
        }.frame(height:CGFloat(hours)*hourHeight).contentShape(Rectangle())
    }
}

// Measure against the stationary timeline, never the moving card's local bounds.
private struct CalendarTimedEventCard: View {
    var event: AgendaEvent
    var color: Color
    var height: Double
    var movable: Bool
    var coordinateSpace: String
    var select: ()->Void
    var beginDrag: ()->Void
    var previewStart: (Double,Double)->Date?
    var move: (Double,Double)->Void
    @GestureState private var translation = CGSize.zero
    private var moving: Bool { translation != .zero }
    private var title: String { event.title + " · " + event.start.formatted(date:.omitted,time:.shortened) }
    private var drag: some Gesture {
        DragGesture(minimumDistance:6,coordinateSpace:.named(coordinateSpace))
            .updating($translation) { value,state,transaction in transaction.disablesAnimations=true; state = value.translation }
            .onChanged { _ in beginDrag() }
            .onEnded { value in move(Double(value.translation.width),Double(value.translation.height)) }
    }
    private var card: some View {
        VStack(alignment:.leading,spacing:2) {
            Text(event.title).font(.caption2.weight(.medium)).lineLimit(height > 48 ? 3 : 1)
            if height > 38 { Text((moving ? previewStart(Double(translation.width),Double(translation.height)) ?? event.start : event.start).formatted(date:.omitted,time:.shortened)).font(.system(size:10)).foregroundStyle(.secondary) }
            Spacer(minLength:0)
        }.padding(.horizontal,5).padding(.vertical,height > 38 ? 5 : 2).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .background(color.opacity(moving ? 0.3 : 0.17),in:RoundedRectangle(cornerRadius:5))
            .overlay(alignment:.leading) { RoundedRectangle(cornerRadius:2).fill(color).frame(width:3) }.clipped()
            .overlay { if moving { RoundedRectangle(cornerRadius:5).stroke(color,lineWidth:1.5) } }
            .contentShape(Rectangle())
    }
    var body: some View {
        Group {
            if movable { card.gesture(drag.exclusively(before:TapGesture().onEnded { _ in select() })) } else { card.onTapGesture(perform:select) }
        }.offset(x:translation.width,y:translation.height).zIndex(moving ? 1 : 0)
            .transaction { $0.animation=nil }
            .help(title + (movable ? " · Drag to move this occurrence; click to edit." : " · Click to edit.")).accessibilityElement(children:.ignore).accessibilityLabel(title)
            .accessibilityAddTraits(.isButton).accessibilityAction(.default) { select() }
    }
}

#if DEBUG
// An isolated live check: only UUID-marked events in its own disposable calendar.
struct CalendarDragPreview: View {
    @Bindable var model: DashboardModel
    @State private var fixture: CalendarDragFixture?
    @State private var configuration = WidgetConfiguration(calendarMode:"day")
    @State private var error: String?
    var body: some View {
        VStack(spacing:8) {
            HStack {
                Text("Disposable Calendar drag check").font(.headline)
                Spacer()
                Button("Undo move") { model.undoLatest() }.disabled(model.latestUndo != "edit" || model.writing)
                Button("Verify native times") { Task { await verify() } }
                Button("Run save-path checks") { Task {
                    do { guard let fixture else { return }; error=try await CalendarDragValidation.run(model,fixture:fixture) }
                    catch { self.error=error.localizedDescription }
                } }.disabled(model.writing)
                Button("Remove fixtures and close") { Task {
                    do { if let fixture { try await model.eventKit.removeCalendarDragFixture(fixture) }; NSApp.terminate(nil) }
                    catch { self.error=error.localizedDescription }
                } }.disabled(model.writing)
            }.padding(.horizontal,16)
            if let error { Text(error).foregroundStyle(.orange) }
            if let fixture { CalendarWidgetView(model:model,configuration:$configuration,previewFixture:fixture) }
            else { ProgressView().task {
                do { fixture=try await model.eventKit.makeCalendarDragFixture(); configuration.date=fixture!.date }
                catch { self.error=error.localizedDescription }
            } }
        }.padding(.vertical,12)
    }
    private func verify() async {
        do {
            guard let fixture else { return }
            let range=DateInterval(start:fixture.date,end:fixture.date.addingTimeInterval(4*86400))
            let value=try await model.eventKit.calendarDragSnapshot(fixture,range:range)
            let data=try JSONEncoder().encode(value)
            try data.write(to:URL(fileURLWithPath:"/tmp/missioncontrol-calendar-drag-fixtures.json"),options:.atomic)
            error="Verified \(value.events.count) disposable occurrences; native times saved in the local diagnostic."
        } catch { self.error=error.localizedDescription }
    }
}
@MainActor private enum CalendarDragValidation {
    static func run(_ model: DashboardModel, fixture: CalendarDragFixture) async throws -> String {
        let range=DateInterval(start:fixture.date,end:fixture.date.addingTimeInterval(4*86400))
        func snapshot() async throws -> CalendarSnapshot { try await model.eventKit.calendarDragSnapshot(fixture,range:range) }
        func at(_ date: Date) async throws -> AgendaEvent {
            let matches=try await snapshot().events.filter{$0.start == date}
            guard matches.count == 1 else { throw IntegrationError.verification }; return matches[0]
        }
        var checks:[String:Bool]=[:]
        func check(_ condition: Bool,_ name: String) throws { checks[name]=condition; guard condition else { throw ActionFailure.message("Failed disposable check: " + name) } }
        let start=fixture.date.addingTimeInterval(9*3600), target=start.addingTimeInterval(5.25*3600)
        let original=try await at(start), details=try await model.eventKit.editSession(.event(original)).item
        let nativeZone=try await model.eventKit.calendarDragTimeZone(fixture,event:original)
        var stale=original; stale.modified = .distantPast
        var staleRefused=false
        do { try await model.moveCalendarEvent(stale,to:target) } catch { staleRefused=true }
        try check(staleRefused,"stale displayed native revision refused")
        try check(try await at(start).id == original.id,"stale revision refusal left native event unchanged")
        var validations=0,refused=false
        do {try await model.moveCalendarEvent(original,to:target,valid:{ validations += 1; return validations < 3 })} catch {refused=true}
        try check(refused && validations == 3,"controls changed immediately before save refused")
        try check(try await at(start).id == original.id,"refused move left native time unchanged")
        try await model.moveCalendarEvent(original,to:target)
        let moved=try await at(target), saved=try await model.eventKit.editSession(.event(moved)).item
        try check(saved.start == target && saved.end.timeIntervalSince(saved.start) == details.end.timeIntervalSince(details.start),"direct move saved start and preserved duration")
        try check(saved.title == details.title && saved.notes == details.notes && saved.location == details.location && saved.timeZoneID == details.timeZoneID && saved.alarms == details.alarms && saved.availability == details.availability,"notes location timezone alerts and availability preserved")
        try check(try await model.eventKit.calendarDragTimeZone(fixture,event:moved) == nativeZone,"native floating or explicit timezone representation preserved")
        _=try await model.undoAssistantAppleChange()
        try check(try await at(start).end == original.end,"direct move Undo restored original native time")
        let repeatedStart=fixture.date.addingTimeInterval(11*3600), repeatedTarget=repeatedStart.addingTimeInterval(2.25*3600)
        let repeated=try await at(repeatedStart)
        try await model.moveCalendarEvent(repeated,to:repeatedTarget)
        try check(try await at(repeatedTarget).end.timeIntervalSince(repeatedTarget) == 3600,"repeating occurrence moved directly")
        let later=try await snapshot().events.filter{$0.start >= fixture.date.addingTimeInterval(86400)}
        try check(later.count == 2 && later.allSatisfy{Calendar.current.component(.hour,from:$0.start) == 11},"later occurrences retained original time")
        _=try await model.undoAssistantAppleChange()
        try check(try await at(repeatedStart).end.timeIntervalSince(repeatedStart) == 3600,"repeating occurrence Undo restored selected time")
        let final=try await snapshot()
        try check(final.events.count == 5,"Undo did not duplicate repeating occurrences")
        let report:[String:Any]=["completed":Date.now.ISO8601Format(),"passed":checks.values.filter{$0}.count,"total":checks.count,"checks":checks,"scope":"Isolated UUID-marked native Calendar fixtures; production direct move and Undo, no AI or personal source reads."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:EvaluationOutput.url("/tmp/missioncontrol-calendar-drag-evaluation.json"),options:.atomic)
        return "PASS \(checks.count)/\(checks.count) native Calendar move checks."
    }
}
#endif
