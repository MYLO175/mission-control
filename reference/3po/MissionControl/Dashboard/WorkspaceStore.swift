import Foundation
import Observation
import SwiftData

@MainActor @Observable final class WorkspaceStore {
    private(set) var state: WorkspaceState
    var error: String?
    var canUndo: Bool { previous != nil }
    private(set) var undoDate: Date?
    var readOnly: Bool { !readable }
    private var previous: WorkspaceState?
    private let container: ModelContainer?
    private var readable = true
    private let sample = ProcessInfo.processInfo.arguments.contains("--sample")
    var selected: DashboardPage { state.pages.first(where: { $0.id == state.selectedPageID }) ?? state.pages[0] }
    init(container: ModelContainer?, calendars: Set<String>, lists: Set<String>, accounts: Set<String>, date: Date) {
        self.container = container
        var initial = GridRules.defaults()
        initial.pages.append(DashboardPage(title:"Assistant",widgets:[WidgetPlacement(kindRaw:"conversation",rect:GridRect(x:0,y:0,w:12,h:10))]))
        for p in initial.pages.indices { for w in initial.pages[p].widgets.indices {
            let kind = initial.pages[p].widgets[w].kind
            initial.pages[p].widgets[w].configuration.sourceExclusions = kind == .calendar ? calendars : kind == .reminders ? lists : kind == .mail ? accounts : []
            initial.pages[p].widgets[w].configuration.date = date
        } }
        for p in initial.pages.indices { initial.pages[p].canvasRows = GridRules.rows(initial.pages[p]) }
        state = initial
        guard !sample else { return }
        do {
            if let record = try LocalRecordRepository.read("workspace", container: container) {
                let saved = try JSONDecoder().decode(WorkspaceState.self,from:record)
                guard saved.schemaVersion == 1, !saved.pages.isEmpty,
                      saved.pages.allSatisfy({ page in Set(page.widgets.map(\.id)).count == page.widgets.count && page.widgets.allSatisfy { GridRules.valid($0.rect,among:page.widgets,excluding:$0.id) } }),
                      Set(saved.pages.map(\.id)).count == saved.pages.count else { throw WorkspaceFailure.invalid }
                state = saved
                // Preserve legacy coordinates and all widgets, fitting their complete extent to the viewport.
                for p in state.pages.indices { state.pages[p].canvasRows = GridRules.rows(state.pages[p]) }
                if !saved.pages.contains(where: { $0.id == saved.selectedPageID }) { state.selectedPageID = saved.pages[0].id }
            } else { try save() }
        } catch { readable = false; self.error = "Saved workspace could not be read. Its original record is preserved; changes are disabled. " + error.localizedDescription }
    }
    private static func savedWorkspace()->FetchDescriptor<CachedDashboard> {
        var request=FetchDescriptor<CachedDashboard>(predicate:#Predicate{$0.key == "workspace"})
        request.fetchLimit=1
        return request
    }
    private func save() throws {
        guard !sample else { return }
        guard let container else { throw WorkspaceFailure.storage }
        try LocalRecordRepository(container: container).save(state, key: "workspace")
    }
    private func change(_ body: (inout WorkspaceState) -> Void, undoable: Bool = true) {
        guard readable else { return }
        let old = state
        body(&state)
        do { try save(); if undoable && old != state { previous = old; undoDate = .now }; error = nil }
        catch { state = old; self.error = "Workspace change was not saved. " + error.localizedDescription }
    }
    func select(_ id: UUID) { guard state.selectedPageID != id,state.pages.contains(where: { $0.id == id }) else { return }; change({ $0.selectedPageID = id },undoable:false) }
    func addPage(_ title: String = "New dashboard", symbol: String? = nil) {
        var page = DashboardPage(title:String(title.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80)).isEmpty ? "New dashboard" : String(title.prefix(80)),widgets:[],canvasRows:8)
        page.symbol = symbol.flatMap { DashboardSymbols.choices.contains($0) ? $0 : nil }
        change { $0.pages.append(page); $0.selectedPageID = page.id }
    }
    func rename(_ id: UUID, title: String) {
        let value = String(title.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80)); guard !value.isEmpty else { return }
        change { if let i = $0.pages.firstIndex(where: { $0.id == id }) { $0.pages[i].title = value } }
    }
    func configurePage(_ id: UUID, title: String, symbol: String?) {
        let title=String(title.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
        guard !title.isEmpty, symbol == nil || DashboardSymbols.choices.contains(symbol!) else { return }
        change { state in if let index=state.pages.firstIndex(where:{$0.id == id}) { state.pages[index].title=title; state.pages[index].symbol=symbol } }
    }
    func duplicate(_ id: UUID) {
        guard var page = state.pages.first(where: { $0.id == id }) else { return }
        page.id = UUID(); page.title += " copy"; for i in page.widgets.indices { page.widgets[i].id = UUID() }
        change { $0.pages.append(page); $0.selectedPageID = page.id }
    }
    func movePage(_ id: UUID, offset: Int) {
        guard let i = state.pages.firstIndex(where: { $0.id == id }), state.pages.indices.contains(i+offset) else { return }
        change { $0.pages.swapAt(i,i+offset) }
    }
    func removePage(_ id: UUID) {
        guard state.pages.count > 1 else { return }
        change { $0.pages.removeAll { $0.id == id }; if $0.selectedPageID == id { $0.selectedPageID = $0.pages[0].id } }
    }
    func addWidget(_ kind: WidgetKind) {
        guard let rect = GridRules.firstFree(kind:kind,in:selected.widgets,rows:GridRules.rows(selected)) else { error = "This dashboard is full. Make room in Edit mode or add a new dashboard."; return }
        let widget = WidgetPlacement(kindRaw:kind.rawValue,rect:rect)
        change { state in if let i = state.pages.firstIndex(where: { $0.id == state.selectedPageID }) { state.pages[i].widgets.append(widget) } }
    }
    func update(_ widget: WidgetPlacement) {
        guard GridRules.valid(widget.rect,among:selected.widgets,excluding:widget.id,rowLimit:GridRules.rows(selected)) else { return }
        change { state in if let p = state.pages.firstIndex(where: { $0.id == state.selectedPageID }), let w = state.pages[p].widgets.firstIndex(where: { $0.id == widget.id }) { state.pages[p].widgets[w] = widget } }
    }
    func removeWidget(_ id: UUID) { change { state in if let p = state.pages.firstIndex(where: { $0.id == state.selectedPageID }) { state.pages[p].widgets.removeAll { $0.id == id } } } }
    func fullPage(_ widget: WidgetPlacement) {
        var full = widget; let budget = selected.widgets.count == 1 ? GridRules.rows(selected) : max(8,widget.kind?.minimumRows ?? 4)
        full.rect = GridRect(x:0,y:0,w:12,h:budget)
        if selected.widgets.count == 1 { update(full) }
        else { full.id = UUID(); let page = DashboardPage(title:widget.kind?.title ?? "Widget",widgets:[full],canvasRows:budget); change { $0.pages.append(page); $0.selectedPageID = page.id } }
    }
    func showAssistant() {
        if let page = state.pages.first(where:{ $0.widgets.contains { $0.kind == .conversation } }) { select(page.id) }
        else {
            addPage("Assistant"); addWidget(.conversation)
            if let widget = selected.widgets.first { fullPage(widget) }
        }
    }

    func showReviewInbox() {
        if let page=state.pages.first(where:{$0.widgets.contains{$0.kind == .tasks}}) {select(page.id)}
        else {
            let page=DashboardPage(title:"Review inbox",widgets:[WidgetPlacement(kind:.tasks,rect:GridRect(x:0,y:0,w:12,h:8))],canvasRows:8)
            change {$0.pages.append(page);$0.selectedPageID=page.id}
        }
    }

    func undo() { guard let old = previous, readable else { return }; let current = state; state = old; do { try save(); previous = nil; undoDate = nil; error = nil } catch { state = current; self.error = "Layout Undo could not be saved." } }
}
enum WorkspaceFailure: LocalizedError {
    case invalid, storage
    var errorDescription: String? { self == .invalid ? "Invalid or unsupported layout version." : "Local workspace storage is unavailable." }
}
