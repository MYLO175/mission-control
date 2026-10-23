import Foundation
import CoreGraphics

@main
struct WorkspaceChecks {
    static func projectPageChecks() throws {
        let folder=UUID(),sibling=UUID()
        var config=WidgetConfiguration();config.projectView="Board";config.sourceExclusions=["native-source"]
        let original=try JSONEncoder().encode(config)
        let legacy=try JSONDecoder().decode(WidgetConfiguration.self,from:original)
        precondition(legacy.projectHiddenSections == nil && ProjectPageSection.allCases.allSatisfy{legacy.showsProjectSection($0,registration:"a",folder:folder)})
        config.setProjectSection(.tasks,visible:false,registration:"a",folder:folder)
        config.setProjectSection(.notes,visible:false,registration:"a",folder:folder)
        let restored=try JSONDecoder().decode(WidgetConfiguration.self,from:JSONEncoder().encode(config))
        precondition(!restored.showsProjectSection(.tasks,registration:"a",folder:folder) && !restored.showsProjectSection(.notes,registration:"a",folder:folder))
        precondition(restored.showsProjectSection(.spaces,registration:"a",folder:folder) && restored.showsProjectSection(.tasks,registration:"a",folder:sibling) && restored.showsProjectSection(.tasks,registration:"b",folder:folder))
        config.projectHiddenSections?["a"]?[folder.uuidString]?.append("future-section")
        config.setProjectSection(.tasks,visible:true,registration:"a",folder:folder)
        precondition(config.showsProjectSection(.tasks,registration:"a",folder:folder) && !config.showsProjectSection(.notes,registration:"a",folder:folder))
        precondition(config.projectHiddenSections?["a"]?[folder.uuidString]?.contains("future-section") == true && config.sourceExclusions == legacy.sourceExclusions && config.projectView == legacy.projectView)
        config.setProjectSection(.spaces,visible:false,registration:"a",folder:folder)
        precondition(!config.showsProjectSection(.spaces,registration:"a",folder:folder),"All sections can be hidden and independently restored")
        let roomy=ProjectNotesLayout.previewHeight(availableHeight:700,width:1000,count:3)
        let crowded=ProjectNotesLayout.previewHeight(availableHeight:100,width:1000,count:3)
        let stacked=ProjectNotesLayout.previewHeight(availableHeight:700,width:300,count:3)
        precondition(roomy > 500 && crowded >= 96 && crowded < roomy && stacked < roomy,"Notes use spare page height and share it across grid rows")
        precondition(ProjectNotesLayout.previewHeight(availableHeight:-300,width:240,count:1) == crowded,"A crowded page keeps a readable preview even below the fold")
        print("Project section persistence, legacy defaults, account/folder isolation and responsive notes passed")
    }
    static func main() throws {
        try savedThemeChecks()
        try projectPageChecks()
        var folderConfig=WidgetConfiguration();folderConfig.projectView="Overview";folderConfig.projectFolderViews=["fictional-a":["folder-1":"Board","folder-2":"List"],"fictional-b":["folder-1":"Outline"]]
        let folderRestored=try JSONDecoder().decode(WidgetConfiguration.self,from:JSONEncoder().encode(folderConfig))
        precondition(folderRestored == folderConfig && folderRestored.projectFolderViews?["fictional-a"]?["folder-1"] == "Board")
        var page=DashboardPage(title:"Study",widgets:[]); page.symbol="graduationcap"
        let decodedPage=try JSONDecoder().decode(DashboardPage.self,from:JSONEncoder().encode(page))
        assert(decodedPage.displayIcon == "graduationcap" && decodedPage == page)
        var legacyPage=try JSONSerialization.jsonObject(with:JSONEncoder().encode(page)) as! [String:Any]
        legacyPage.removeValue(forKey:"symbol")
        let oldPage=try JSONDecoder().decode(DashboardPage.self,from:JSONSerialization.data(withJSONObject:legacyPage)); assert(oldPage.symbol == nil)
        let defaults = WidgetConfiguration()
        assert(defaults.sourceExclusions.isEmpty)
        assert(defaults.calendarMode == "agenda" && defaults.reminderGrouping == "lists")
        assert(defaults.conversationID == nil)
        assert(defaults.briefShowsWeather == nil,"Old widgets show the weather card by default")
        var hiddenWeather=defaults;hiddenWeather.briefShowsWeather=false
        let hiddenWeatherRoundTrip=try JSONDecoder().decode(WidgetConfiguration.self,from:JSONEncoder().encode(hiddenWeather))
        assert(hiddenWeatherRoundTrip == hiddenWeather && hiddenWeatherRoundTrip.briefShowsWeather == false,"Widget-local weather visibility persists without changing source exclusions")

        let weather=WidgetPlacement(kind:.weather,rect:GridRect(x:0,y:0,w:3,h:3))
        let weatherRoundTrip=try JSONDecoder().decode(WidgetPlacement.self,from:JSONEncoder().encode(weather))
        assert(weatherRoundTrip == weather && weatherRoundTrip.kind == .weather)
        assert(WidgetKind.weather.minimumColumns == 3 && WidgetKind.weather.minimumRows == 3)
        let base = WidgetPlacement(kind: .calendar, rect: GridRect(x: 0, y: 0, w: 4, h: 5))
        assert(GridRules.valid(GridRect(x: 4, y: 0, w: 4, h: 5), among: [base]), "Edge touching is allowed")
        assert(!GridRules.valid(GridRect(x: 3, y: 0, w: 4, h: 5), among: [base]), "Horizontal overlap is rejected")
        assert(!GridRules.valid(GridRect(x: 0, y: 4, w: 4, h: 5), among: [base]), "Vertical overlap is rejected")
        assert(!GridRules.valid(GridRect(x: 10, y: 0, w: 3, h: 4), among: []), "Right overflow is rejected")
        assert(!GridRules.valid(GridRect(x: 0, y: -1, w: 1, h: 1), among: []), "Negative rows are rejected")
        assert(!GridRules.valid(GridRect(x: 0, y: 0, w: 0, h: 1), among: []), "Empty dimensions are rejected")
        assert(GridRules.valid(base.rect, among: [base], excluding: base.id), "The edited placement can be excluded")

        let unknown = WidgetPlacement(kindRaw: "futureWidget", rect: GridRect(x: 0, y: 0, w: 4, h: 4))
        assert(unknown.kind == nil)
        let unknownRoundTrip = try JSONDecoder().decode(WidgetPlacement.self, from: JSONEncoder().encode(unknown))
        assert(unknownRoundTrip == unknown && unknownRoundTrip.kindRaw == "futureWidget")

        var configuration = WidgetConfiguration()
        configuration.sourceExclusions = ["source-a", "source-b"]
        configuration.calendarMode = "week"
        configuration.reminderGrouping = "dueDate"
        configuration.reminderCollapsedLists=["account-one":["source-a"],"account-two":["source-b"]]
        configuration.conversationID = UUID()
        configuration.conversationSelections = ["account-one":UUID(),"account-two":UUID()]
        configuration.paTopicSelections = ["account-one":"","account-two":UUID().uuidString]
        configuration.lifeFocusSelections = ["account-one":["studies","career"],"account-two":[]]
        configuration.projectRoots = ["account-one":UUID().uuidString,"account-two":""]
        configuration.lifeMapView = "Structure";configuration.projectView = "Board"; configuration.projectOnlyUnfinished = true
        configuration.clockStyle="calendar";configuration.clockAlignment="leading";configuration.clockUses24Hour=true
        configuration.colourProfiles = ["light":["widget":"#FFEEEE"],"dark":["widget":"#332222","text":"#FFFFFF"]]
        var legacyConfiguration = try JSONSerialization.jsonObject(with:JSONEncoder().encode(configuration)) as! [String:Any]
        legacyConfiguration.removeValue(forKey:"colourProfiles")
        let migratedColours = try JSONDecoder().decode(WidgetConfiguration.self,from:JSONSerialization.data(withJSONObject:legacyConfiguration))
        assert(migratedColours.colourProfiles == nil && migratedColours.paTopicSelections == configuration.paTopicSelections,"Old layouts inherit theme and retain topic selections")
        for key in ["lifeMapView","lifeFocusSelections","clockStyle","clockAlignment","clockUses24Hour","projectRoots","projectView","projectOnlyUnfinished","reminderCollapsedLists"] { legacyConfiguration.removeValue(forKey:key) }
        let migratedFocus=try JSONDecoder().decode(WidgetConfiguration.self,from:JSONSerialization.data(withJSONObject:legacyConfiguration))
        assert(migratedFocus.lifeMapView == nil && migratedFocus.projectRoots == nil && migratedFocus.projectView == nil && migratedFocus.projectOnlyUnfinished == nil,"Old dashboards decode without project preferences")
        assert(migratedFocus.lifeFocusSelections == nil && migratedFocus.clockStyle == nil && migratedFocus.clockAlignment == nil && migratedFocus.clockUses24Hour == nil && migratedFocus.paTopicSelections == configuration.paTopicSelections,"New preferences are optional; old topic selection and layout survive")
        assert(migratedFocus.reminderCollapsedLists == nil && migratedFocus.sourceExclusions == configuration.sourceExclusions,"Legacy reminder lists begin expanded without changing source filters")
        let state = GridRules.defaults()
        let stateRoundTrip = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        assert(stateRoundTrip == state, "Workspace state survives JSON encoding")
        assert(state.schemaVersion == 1 && state.pages.map(\.title) == ["Today", "Planning", "Sources"])
        assert(state.selectedPageID == state.pages[0].id)
        assert(state.pages[0].widgets.map(\.rect) == [
            GridRect(x: 0, y: 0, w: 4, h: 7),
            GridRect(x: 4, y: 0, w: 3, h: 7),
            GridRect(x: 7, y: 0, w: 5, h: 7)
        ])

        let configuredPlacement = WidgetPlacement(kind: .conversation, rect: GridRect(x: 0, y: 0, w: 4, h: 5), configuration: configuration)
        let placementRoundTrip = try JSONDecoder().decode(WidgetPlacement.self, from: JSONEncoder().encode(configuredPlacement))
        assert(placementRoundTrip == configuredPlacement)
        assert(placementRoundTrip.configuration.reminderCollapsedLists?["account-one"] == ["source-a"] && placementRoundTrip.configuration.reminderCollapsedLists?["account-two"] == ["source-b"],"Collapsed lists persist per account and widget using exact source IDs")

        let row = (0..<GridRules.columns).map { column in
            WidgetPlacement(kind: .overview, rect: GridRect(x: column, y: 0, w: 1, h: 1))
        }
        let next = GridRules.firstFree(kind: .calendar, in: row)
        assert(next == GridRect(x: 0, y: 1, w: 4, h: 5), "Search advances to the first free row")
        assert(GridRules.firstFree(kind: .mail, in: []) == GridRect(x: 0, y: 0, w: 4, h: 4))
        assert(
            GridRules.firstFree(kind: .calendar, in: [base]) == GridRect(x: 4, y: 0, w: 4, h: 5),
            "Search checks columns from left to right before advancing rows"
        )

        let orderedWidgets = [
            WidgetPlacement(kind: .mail, rect: GridRect(x: 0, y: 0, w: 4, h: 4)),
            WidgetPlacement(kindRaw: "futureWidget", rect: GridRect(x: 4, y: 0, w: 4, h: 4)),
            WidgetPlacement(kind: .calendar, rect: GridRect(x: 8, y: 0, w: 4, h: 5))
        ]
        let orderedPage = DashboardPage(title: "Order", widgets: orderedWidgets)
        let orderedPageRoundTrip = try JSONDecoder().decode(DashboardPage.self, from: JSONEncoder().encode(orderedPage))
        assert(orderedPageRoundTrip.widgets == orderedWidgets, "Placement order survives JSON encoding")

        assert(GridRules.valid(GridRect(x:0,y:3,w:4,h:5),among:[],rowLimit:8))
        assert(!GridRules.valid(GridRect(x:0,y:4,w:4,h:5),among:[],rowLimit:8),"Canvas bottom is bounded")
        let filled = [WidgetPlacement(kind:.calendar,rect:GridRect(x:0,y:0,w:12,h:8))]
        assert(GridRules.firstFree(kind:.reminders,in:filled,rows:8) == nil,"Full pages cannot grow downward")
        let legacy = try JSONDecoder().decode(DashboardPage.self,from:Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"title\":\"Legacy\",\"widgets\":[]}".utf8))
        assert(legacy.canvasRows == nil && GridRules.rows(legacy) == 8)
        let tall = DashboardPage(title:"Legacy tall",widgets:[WidgetPlacement(kind:.calendar,rect:GridRect(x:0,y:3,w:12,h:15))])
        assert(GridRules.rows(tall) == 18,"Existing extents are preserved rather than cropped")
        for size in [(1100.0,600.0),(750.0,430.0),(1600.0,1000.0)] {
            let geometry = WorkspaceGeometry(width:size.0,height:size.1,rows:8)
            let full = geometry.frame(GridRect(x:0,y:0,w:12,h:8))
            assert(abs(full.width-size.0) < 0.001 && abs(full.height-size.1) < 0.001)
            let origin = GridRect(x:1,y:1,w:4,h:5)
            let before = geometry.frame(origin)
            let smooth = geometry.preview(origin:origin,dx:7,dy:9,resizing:false,minimumColumns:4,minimumRows:5)
            assert(abs(smooth.minX-before.minX-7) < 0.001 && abs(smooth.minY-before.minY-9) < 0.001,"Preview tracks pixel movement before snapping")
            let moved = geometry.target(origin:origin,dx:geometry.xStep*2,dy:geometry.yStep,resizing:false,minimumColumns:4,minimumRows:5)
            assert(moved == GridRect(x:3,y:2,w:4,h:5),"Movement is measured against the immutable gesture origin")
            let edge = geometry.target(origin:origin,dx:10000,dy:10000,resizing:false,minimumColumns:4,minimumRows:5)
            assert(edge == GridRect(x:8,y:3,w:4,h:5))
            let resized = geometry.target(origin:origin,dx:10000,dy:10000,resizing:true,minimumColumns:4,minimumRows:5)
            assert(resized == GridRect(x:1,y:1,w:11,h:7),"Resize clamps at canvas edges")
            let minimum = geometry.target(origin:origin,dx:-10000,dy:-10000,resizing:true,minimumColumns:4,minimumRows:5)
            assert(minimum == origin)
            let pointerSize = geometry.preview(origin:origin,dx:5,dy:7,resizing:true,minimumColumns:4,minimumRows:5)
            assert(abs(pointerSize.width-before.width-5) < 0.001 && abs(pointerSize.height-before.height-7) < 0.001)
        }

        let earlier = Date(timeIntervalSince1970:100), later = earlier.addingTimeInterval(1)
        assert(UndoOrder.latest(layout:earlier,completion:later,edit:nil) == "completion")
        assert(UndoOrder.latest(layout:later,completion:earlier,edit:nil) == "layout")
        assert(UndoOrder.latest(layout:earlier,completion:nil,edit:later) == "edit")
        assert(UndoOrder.latest(layout:nil,completion:nil,edit:nil) == nil)
        assert(UndoOrder.latest(layout:earlier,completion:earlier,edit:nil,email:later) == "email")
        assert(UndoOrder.latest(layout:later,completion:nil,edit:nil,discovery:earlier) == "layout")
        assert(UndoOrder.latest(layout:nil,completion:earlier,edit:nil,question:later) == "question")
        assert(UndoOrder.latest(layout:nil,completion:nil,edit:nil,discovery:later) == "discovery")
        assert(UndoOrder.latest(layout:earlier,completion:nil,edit:nil,memoryReview:later) == "memoryReview")
        assert(UndoOrder.latest(layout:earlier,completion:nil,edit:nil,project:later) == "project")
        assert(UndoOrder.latest(layout:later,completion:nil,edit:nil,project:earlier) == "layout")
        assert(UndoOrder.latest(layout:earlier,completion:nil,edit:nil,question:earlier,reviewQuestion:later) == "reviewQuestion")
        let hidden = ToolbarRules.setting(.date,visible:false,hidden:"future-control")
        assert(!ToolbarRules.visible(.date,hidden:hidden) && ToolbarRules.visible(.refresh,hidden:hidden))
        assert(ToolbarRules.setting(.date,visible:true,hidden:hidden) == "future-control")
        var clock = WidgetConfiguration(); clock.clockShowsTime = false; clock.clockShowsSeconds = true
        let clockData = try JSONEncoder().encode(clock), restoredClock = try JSONDecoder().decode(WidgetConfiguration.self,from:clockData)
        assert(restoredClock.clockShowsTime == false && restoredClock.clockShowsSeconds == true)
        assert(WidgetKind.clock.minimumRows == 2 && WidgetKind.clock.minimumColumns == 3)
        print("PASS: named theme persistence and revision guards, fixed viewport geometry, continuous previews, workspace persistence, clock preferences, toolbar preservation and latest-supported Undo ordering")
    }
    static func savedThemeChecks() throws {
        let colors = ##"{"profiles":{"light":{"canvas":"#EEF1F3"},"dark":{"canvas":"#101823","futureRole":"#AABBCC"},"futureMode":{"canvas":"#112233"}},"futureMetadata":{"keep":true}}"##
        var library=try WorkspaceThemeLibrary(raw:#"{"futureLibrary":"preserve"}"#)
        let recipe=SavedWorkspaceTheme(name:"  Evening  ",colorOverrides:colors,baseTheme:"native",accent:"ocean")
        try library.save(recipe)
        var reopened=try WorkspaceThemeLibrary(raw:library.encoded)
        let saved=reopened.themes[0]
        precondition(saved.id == recipe.id && saved.name == "Evening" && saved.colorOverrides == colors && saved.baseTheme == "native" && saved.accent == "ocean","Reopening retains both palettes, inherited roles, base style and accent")
        var sameColors=recipe;sameColors.id=UUID();sameColors.name="Morning"
        try reopened.save(sameColors)
        precondition(reopened.selected(sameColors.id.uuidString,colors:colors,baseTheme:"native",accent:"ocean")?.name == "Morning","Identical palettes retain the explicitly selected name")
        precondition(reopened.selected(recipe.id.uuidString,colors:"{}",baseTheme:"native",accent:"ocean") == nil && reopened.selected("",colors:colors,baseTheme:"native",accent:"ocean") == nil,"Modified colours and built-in selection do not misidentify a saved theme")
        let identicalReopened=try WorkspaceThemeLibrary(raw:reopened.encoded)
        precondition(identicalReopened.selected(sameColors.id.uuidString,colors:colors,baseTheme:"native",accent:"ocean")?.id == sameColors.id,"Selection identity survives a library reopen")
        var root=try JSONSerialization.jsonObject(with:Data(try library.encoded.utf8)) as! [String:Any]
        var row=(root["themes"] as! [[String:Any]])[0];row["id"]=recipe.id.uuidString.lowercased();row["futureRecipe"]="preserve";root["themes"]=[row]
        reopened=try WorkspaceThemeLibrary(raw:String(decoding:try JSONSerialization.data(withJSONObject:root),as:UTF8.self))
        var renamed=saved;renamed.name="Night study"
        try reopened.save(renamed,expected:saved)
        let renamedRoot=try JSONSerialization.jsonObject(with:Data(try reopened.encoded.utf8)) as! [String:Any]
        let rows=renamedRoot["themes"] as! [[String:Any]]
        precondition(rows.count == 1 && rows[0]["futureRecipe"] as? String == "preserve" && renamedRoot["futureLibrary"] as? String == "preserve","Rename handles lower-case IDs and retains unknown fields without duplicate recipes")
        var duplicate=recipe;duplicate.id=UUID();duplicate.name=" NIGHT STUDY "
        let unchanged=try reopened.encoded
        do {try reopened.save(duplicate);preconditionFailure("Duplicate name accepted")} catch {}
        do {try reopened.save(renamed,expected:saved);preconditionFailure("Stale revision accepted")} catch {}
        do {try reopened.remove(saved);preconditionFailure("Stale deletion accepted")} catch {}
        let afterRejection=try reopened.encoded
        precondition(afterRejection == unchanged,"Rejected changes preserve the original library")
        var invalid=recipe;invalid.colorOverrides=##"{"profiles":{"light":{"canvas":"#badhex"}}}"##
        do {try reopened.save(invalid);preconditionFailure("Invalid palette accepted")} catch {}
        for raw in ["broken",#"{"version":2,"themes":[]}"#,#"{"themes":{}}"#] {
            do {_=try WorkspaceThemeLibrary(raw:raw);preconditionFailure("Invalid library accepted")} catch {}
        }
        let current=reopened.themes[0]
        try reopened.remove(current)
        let empty=try WorkspaceThemeLibrary(raw:reopened.encoded)
        precondition(empty.themes.isEmpty && current.colorOverrides == colors,"Removing a recipe leaves its active colour snapshot intact")
        var inherited=try WorkspaceThemeLibrary(raw:"{}");try inherited.save(.init(name:"Inherited",colorOverrides:"{}",baseTheme:"warm",accent:"sage"))
        let inheritedReopened=try WorkspaceThemeLibrary(raw:inherited.encoded)
        precondition(inheritedReopened.themes[0].colorOverrides == "{}","Default inheritance remains inheritance")
        let nearLimit=String(decoding:try JSONSerialization.data(withJSONObject:["futureMetadata":String(repeating:"x",count:1_048_500)]),as:UTF8.self)
        var full=try WorkspaceThemeLibrary(raw:nearLimit)
        let beforeFull=try full.encoded
        do {try full.save(recipe);preconditionFailure("Unreadable oversized library persisted")} catch {}
        let afterFull=try full.encoded
        precondition(full.themes.isEmpty && beforeFull == afterFull,"Storage bounds reject writes atomically, preserving valid future metadata")
    }
}
