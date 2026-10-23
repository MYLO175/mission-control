import SwiftUI
import AppKit

// The active dashboard supplies its UI bindings; Settings/other windows cannot
// accidentally arrange a hidden page or present a form in the wrong window.
struct WorkspaceMenuActions {
    var sidebar: Binding<Bool>
    var editing: Binding<Bool>
    var newDashboard: () -> Void
    var addWidget: (WidgetKind) -> Void
    var customiseToolbar: () -> Void
    var customiseColors: () -> Void
}
private struct WorkspaceMenuKey: FocusedValueKey {
    typealias Value = WorkspaceMenuActions
}
extension FocusedValues {
    var workspaceMenu: WorkspaceMenuActions? {
        get { self[WorkspaceMenuKey.self] }
        set { self[WorkspaceMenuKey.self] = newValue }
    }
}
struct WorkspaceCommands: Commands {
    var model: DashboardModel
    @State private var textUndo = WorkspaceTextUndo()
    @FocusedValue(\.workspaceMenu) private var workspace
    @Environment(\.openWindow) private var openWindow
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAppearance") private var appearance = "system"
    @AppStorage("workspaceAccent") private var accent = "sage"
    var body: some Commands {
        CommandMenu("Dashboard") {
            Button("Open dashboard") { NSApp.activate(ignoringOtherApps:true); openWindow(id:"dashboard") }
            Button("Open Review inbox") {model.workspace.showReviewInbox();NSApp.activate(ignoringOtherApps:true);openWindow(id:"dashboard")}.disabled(model.workspace.readOnly)
            Button("New dashboard…") { workspace?.newDashboard() }.keyboardShortcut("n",modifiers:.command).disabled(workspace == nil)
            Menu("Add widget") {
                ForEach(WidgetKind.allCases,id:\.self) { kind in
                    Button(kind.title) { workspace?.addWidget(kind) }
                }
            }.disabled(workspace == nil || model.workspace.readOnly)
            Toggle("Edit layout",isOn:editing).disabled(workspace == nil || model.workspace.readOnly)
            Divider()
            Button("Run heartbeat") { model.heartbeat.check(model,manual:true) }.keyboardShortcut("r",modifiers:.command)
                .disabled(workspace == nil || model.heartbeat.manualCheckBlockReason(model) != nil)
            Button("Refresh sources only") { model.refresh() }.keyboardShortcut("r",modifiers:[.command,.option])
        }
        CommandGroup(replacing:.undoRedo) {
            Button(usesTextUndo ? "Undo" : model.undoLabel) {
                if !usesTextUndo || !textUndo.undoText() { model.undoLatest() }
            }.keyboardShortcut("z",modifiers:.command)
                .disabled(usesTextUndo ? !textUndo.canUndo : workspace == nil || model.latestUndo == nil || model.writing || model.assistant.busy)
            Button("Redo") { textUndo.redoText() }.keyboardShortcut("z",modifiers:[.command,.shift])
                .disabled(!textUndo.canRedo)
        }
        CommandGroup(after:.sidebar) {
            Toggle("Show dashboard sidebar",isOn:sidebar).disabled(workspace == nil)
            Button("Show assistant") {
                model.openAssistantComposer()
                NSApp.activate(ignoringOtherApps:true); openWindow(id:"dashboard")
            }.keyboardShortcut("j",modifiers:.command)
        }
        CommandGroup(after:.toolbar) {
            Button("Customise dashboard toolbar…") { workspace?.customiseToolbar() }.disabled(workspace == nil)
            Menu("Dashboard appearance") {
                Picker("Appearance",selection:$appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                Divider()
                Button("Customise colours…") { workspace?.customiseColors() }.disabled(workspace == nil)
            }
        }
    }
    private var usesTextUndo: Bool { textUndo.prefersText(over:workspace == nil ? nil : model.latestUndoDate) }
    private var sidebar: Binding<Bool> { workspace?.sidebar ?? .constant(false) }
    private var editing: Binding<Bool> { workspace?.editing ?? .constant(false) }
}

// Preserve the field editor's native Undo/Redo when typing. Outside text editing,
// Command-Z uses the same timestamp-ordered receipts as the toolbar Undo.
@MainActor @Observable private final class WorkspaceTextUndo {
    private(set) var editingText = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    private var editedAt: Date?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private var editor: NSTextView? {
        guard let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.isEditable else { return nil }
        return text
    }
    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching:[.keyUp,.leftMouseUp]) { [weak self] event in
            DispatchQueue.main.async { self?.refresh() }; return event
        }
        for name in [NSText.didChangeNotification,NSWindow.didBecomeKeyNotification,NSWindow.didResignKeyNotification,Notification.Name("NSUndoManagerDidUndoChangeNotification"),Notification.Name("NSUndoManagerDidRedoChangeNotification"),Notification.Name("NSUndoManagerDidCloseUndoGroupNotification")] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                DispatchQueue.main.async {
                    if name == NSText.didChangeNotification { self?.editedAt = .now }
                    self?.refresh()
                }
            })
        }
        refresh()
    }
    private func refresh() {
        editingText = editor != nil
        canUndo = editor?.undoManager?.canUndo ?? false
        canRedo = editor?.undoManager?.canRedo ?? false
    }
    func prefersText(over appDate: Date?) -> Bool {
        guard editingText else { return false }
        // Sheet fields must never undo a hidden dashboard change.
        if NSApp.keyWindow?.sheetParent != nil || NSApp.keyWindow?.attachedSheet != nil { return true }
        guard let appDate else { return true }
        return canUndo && (editedAt.map { $0 >= appDate } ?? false)
    }
    func undoText() -> Bool {
        guard let editor else { refresh(); return false }
        if editor.undoManager?.canUndo == true { editor.undoManager?.undo() }
        refresh(); return true
    }
    func redoText() {
        if editor?.undoManager?.canRedo == true { editor?.undoManager?.redo() }
        refresh()
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
