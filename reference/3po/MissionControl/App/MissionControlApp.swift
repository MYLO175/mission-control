import SwiftUI
import AppKit
import UserNotifications
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--small-window") || arguments.contains("--dark-window") else { return }
        // SwiftUI may restore a fullscreen window after didFinishLaunching.
        // Retry after restoration and identify the dashboard without relying on
        // its title (which can be empty while fullscreen).
        for attempt in 1...4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt)) {
                guard let window = NSApp.windows.first(where: { $0.isVisible && !$0.isFloatingPanel }) else { return }
                if arguments.contains("--dark-window") { window.appearance = NSAppearance(named: .darkAqua) }
                if arguments.contains("--small-window") {
                    if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                    else { window.setContentSize(NSSize(width: 820, height: 640)); window.center() }
                }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
@main struct MissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model:DashboardModel
    init() {
        #if DEBUG
        let evaluationDebug = true
        #else
        let evaluationDebug = false
        #endif
        switch EvaluationLaunchGuard.decision(arguments:ProcessInfo.processInfo.arguments, isDebug:evaluationDebug) {
        case .proceed: break
        case .exit(let code, let output):
            (code == 0 ? FileHandle.standardOutput : FileHandle.standardError).write(Data(output.utf8))
            Darwin.exit(code)
        }
        let dashboard=DashboardModel()
        if dashboard.storageOwnershipBlocked {
            let alert=NSAlert()
            alert.messageText="3PO is already using this storage"
            alert.informativeText="Close the other copy of 3PO before opening this one. No saved data was opened or changed."
            alert.addButton(withTitle:"Close this copy")
            alert.runModal()
            Darwin.exit(0)
        }
        // Apply the approved centre/right layout once. Retain the human's visible
        // item choices/order and every unrelated native toolbar preference.
        if !ProcessInfo.processInfo.arguments.contains(where:{$0.hasPrefix("--preview") || $0.hasPrefix("--validate") || $0.hasPrefix("--render") || $0.hasPrefix("--evaluation")}) {
            let defaults=UserDefaults.standard,key="NSToolbar Configuration mission-control.workspace.native-toolbar"
            if !defaults.bool(forKey:"workspaceToolbarCentredActionsV1"),var value=defaults.dictionary(forKey:key),let ids=value["TB Item Identifiers"] as? [String],ids.contains("assistant") {
                let trailing=ids.filter{!["sidebar","assistant","NSToolbarFlexibleSpaceItem"].contains($0)}
                value["TB Item Identifiers"]=(ids.contains("sidebar") ? ["sidebar"] : [])+["NSToolbarFlexibleSpaceItem","assistant","NSToolbarFlexibleSpaceItem"]+trailing
                defaults.set(value,forKey:key);defaults.set(true,forKey:"workspaceToolbarCentredActionsV1")
            }
        }
        _model=State(initialValue:dashboard)
        #if DEBUG
        // This local diagnostic must not depend on a visible window mounting while the Mac is locked.
        if ProcessInfo.processInfo.arguments.contains("--render-projects") || EvaluationLaunchGuard.modes.contains(where: { mode in mode.first.map(ProcessInfo.processInfo.arguments.contains) ?? false }) {
            DispatchQueue.main.async { dashboard.start() }
        }
        #endif
    }
    @AppStorage("workspaceAppearance") private var appearance = "system"
    private var selectedColorScheme: ColorScheme? {
        if ProcessInfo.processInfo.arguments.contains("--dark-window") { return .dark }
        switch appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }
    private var reviewTrial:Bool {ProcessInfo.processInfo.arguments.contains("--preview-review-conversation")}
    var body: some Scene {
        Window(reviewTrial ? "3PO · Review trial" : "3PO", id: reviewTrial ? "reviewConversationTrial" : ProcessInfo.processInfo.arguments.contains("--preview-chat-approval") ? "chatApprovalPreview" : ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") ? "reviewInboxPreview" : ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") ? "reviewInboxValidation" : ProcessInfo.processInfo.arguments.contains("--preview-life-and-plans") ? "lifePlansPreview" : ProcessInfo.processInfo.arguments.contains("--validate-commitment-reports") ? "commitmentValidation" : ProcessInfo.processInfo.arguments.contains("--validate-advice-context") ? "adviceValidation" : ProcessInfo.processInfo.arguments.contains("--preview-memory-review") ? "memoryReviewPreview" : "dashboard") {
            #if DEBUG
            if reviewTrial {
                ReviewConversationTrialView()
            } else if ProcessInfo.processInfo.arguments.contains("--preview-chat-approval") {
                ChatApprovalPreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-calendar-drag") {
                CalendarDragPreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-review-inbox") {
                if ProcessInfo.processInfo.arguments.contains("--heartbeat-progress-preview") {HeartbeatProgressPreviewScreen(model:model)}
                else if ProcessInfo.processInfo.arguments.contains("--workspace-colours-preview") {WorkspaceThemePreview()}
                else {ReviewInboxPreview(model:model).preferredColorScheme(selectedColorScheme)}
            } else if ProcessInfo.processInfo.arguments.contains("--preview-life-and-plans") {
                LifeAndPlanPreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-settings") {
                if ProcessInfo.processInfo.arguments.contains("--heartbeat-history") {BackgroundActivityView(model:model).preferredColorScheme(selectedColorScheme)}
                else {SettingsView(model:model).preferredColorScheme(selectedColorScheme)}
            } else if ProcessInfo.processInfo.arguments.contains("--preview-memory-review") {
                MemoryReviewPreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-memory-inspection") {
                MemoryInspectionPreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-images") {
                ChatImageInteractivePreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-projects") {
                LifeProjectInteractivePreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--preview-source-timeline") {
                SourceTimelinePreview(model:model)
            } else if ProcessInfo.processInfo.arguments.contains("--render-projects") || ProcessInfo.processInfo.arguments.contains("--validate-review-inbox") || ProcessInfo.processInfo.arguments.contains("--validate-commitment-reports") || ProcessInfo.processInfo.arguments.contains("--validate-advice-context") || ProcessInfo.processInfo.arguments.contains("--validate-native-memory") || ProcessInfo.processInfo.arguments.contains("--inspect-luna-access") || ProcessInfo.processInfo.arguments.contains("--validate-memory-inspection") || ProcessInfo.processInfo.arguments.contains("--validate-source-timeline") || ProcessInfo.processInfo.arguments.contains("--validate-native-capabilities") || ProcessInfo.processInfo.arguments.contains("--validate-native-editors") {
                Text("Running disposable validation…").padding().task {model.start()}
            } else { WorkspaceView(model:model).preferredColorScheme(selectedColorScheme) }
            #else
            WorkspaceView(model:model).preferredColorScheme(selectedColorScheme)
            #endif
        }.defaultSize(width: ProcessInfo.processInfo.arguments.contains("--small-window") ? 820 : 1200, height: ProcessInfo.processInfo.arguments.contains("--small-window") ? 640 : 780)
        .windowToolbarStyle(.unifiedCompact(showsTitle:false))
        .commands {
            if !reviewTrial {
            WorkspaceCommands(model:model)
            HelpCommands()
            #if DEBUG
            CommandGroup(after: .help) {
                Menu("Developer checks") {
                Button("Run disposable Calendar check") { model.validateCalendarIntegration() }
                Button("Invalidate today's test briefing") { model.briefings.invalidateToday(model) }
                Button("Check proactive suggestions (fictional)") { model.validateProactivePrompt() }.keyboardShortcut("p",modifiers:[.command,.option,.shift])
                Button("Check Mail search folders") { model.validateMailFolders() }.keyboardShortcut("m",modifiers:[.command,.option,.shift])
                Button("Run disposable editor check") { let current = model; Task { guard !current.writing else { return }; current.writing = true; defer { current.writing = false; current.refresh(retryMail:false) }; do { current.validationReport = try await current.eventKit.validateNativeEditors() } catch { current.validationReport = error.localizedDescription } } }
                Button("Run disposable action check") { let current = model; Task { guard !current.writing else { return }; current.writing = true; defer { current.writing = false }; do { current.validationReport = try await current.eventKit.validateDisposableActions() } catch { current.validationReport = error.localizedDescription } } }
                Button("Check memory learning (fictional)") { model.validateMemoryLearning() }
                Button("Check life notebook intelligence (fictional)") { model.validateLifeNotebook() }
                Button("Preview compact dashboard") { if let window = NSApp.windows.first(where:{ $0.isVisible && !$0.isFloatingPanel }) { window.setContentSize(NSSize(width:820,height:640)); window.center() } }
                Button("Restore dashboard window size") { if let window = NSApp.windows.first(where:{ $0.isVisible && !$0.isFloatingPanel }) { window.setContentSize(NSSize(width:1200,height:780)); window.center() } }
                Button("Check email triage (fictional)") { let current = model; Task { do { current.validationReport = try await current.emailSummaries.validateTriage(current) } catch { current.validationReport = error.localizedDescription } } }
                Button("Clean assistant action fixtures") { let current = model; Task { do { current.validationReport = try await current.assistantActions.cleanupFixtures(current) } catch { current.validationReport = error.localizedDescription } } }
                }
            }
            #endif
            }
        }
        MenuBarExtra(isInserted:.constant(!reviewTrial)) {
            MenuContent(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("3PO")
        }
        Settings { if reviewTrial {Text("Review trial · use the demo controls in the toolbar.").padding()} else {SettingsView(model: model).preferredColorScheme(selectedColorScheme)} }
        Window("3PO Help",id:"help") {
            if reviewTrial {Text("Review trial · scripted example data and simulated jobs.").padding()} else {PAHelpView(model:model).preferredColorScheme(selectedColorScheme)}
        }.defaultSize(width:760,height:650)
    }
}
struct HelpCommands:Commands {
    @Environment(\.openWindow) private var openWindow
    var body:some Commands {
        CommandGroup(replacing:.help) {
            Button("3PO Help") { openWindow(id:"help") }.keyboardShortcut("?",modifiers:[.command,.shift])
        }
    }
}
struct MenuContent: View {
    var model: DashboardModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("Open dashboard") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "dashboard") }
        Button("Run heartbeat") { model.heartbeat.check(model,manual:true) }.disabled(model.heartbeat.manualCheckBlockReason(model) != nil).help(model.heartbeat.manualCheckHelp(model))
        Button("Refresh sources only") { model.refresh() }.help("Update cached sources without AI")
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit 3PO") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
