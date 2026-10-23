import SwiftUI
import AppKit

struct WorkspaceColorOverrides: Codable {
    var profiles: [String:[String:String]] = [:]
    init(raw: String) { self = (try? JSONDecoder().decode(Self.self,from:Data(raw.utf8))) ?? Self() }
    init() {}
    var encoded: String { String(data:(try? JSONEncoder().encode(self)) ?? Data(),encoding:.utf8) ?? "{}" }
    static func components(_ hex: String) -> (Double,Double,Double)? {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, value.allSatisfy({ $0.isHexDigit }), let number = UInt32(value,radix:16) else { return nil }
        return (Double((number >> 16) & 255)/255,Double((number >> 8) & 255)/255,Double(number & 255)/255)
    }
    func color(_ role: WorkspaceColorRole, mode: String) -> Color? {
        guard let hex = profiles[mode]?[role.rawValue], let (r,g,b) = Self.components(hex) else { return nil }
        return Color(.sRGB,red:r,green:g,blue:b,opacity:1)
    }
    mutating func set(_ role: WorkspaceColorRole, mode: String, color: Color?) {
        if let color, let rgb = NSColor(color).usingColorSpace(.sRGB) {
            profiles[mode,default:[:]][role.rawValue] = String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
        } else { profiles[mode]?[role.rawValue] = nil }
    }
}
enum WorkspaceColorRole: String, CaseIterable, Identifiable {
    case canvas, sidebar, widget, text, accent, border, assistantBubble, userBubble, input
    var id: String { rawValue }
    var title: String { switch self {
    case .canvas:return "Dashboard background"; case .sidebar:return "Sidebar background"; case .widget:return "Widget background"
    case .text:return "Text"; case .accent:return "Accent and controls"; case .border:return "Widget borders"
    case .assistantBubble:return "PA message bubbles"; case .userBubble:return "Your message bubbles"; case .input:return "Chat input background"
    } }
}
enum WorkspaceColorTheme: String, CaseIterable, Identifiable {
    case sage, ocean, graphite, rose, threePO = "3po"
    var id: String { rawValue }
    var title: String { switch self { case .sage: "Warm sage"; case .ocean: "Ocean"; case .graphite: "Graphite"; case .rose: "Rose"; case .threePO: "3PO" } }
    var detail: String { switch self {
    case .sage: "Warm ivory and calm greens"
    case .ocean: "Cool whites and deep blue"
    case .graphite: "Neutral greys and a restrained blue accent"
    case .rose: "Soft blush and muted plum"
    case .threePO: "Polished gold, warm ivory and midnight bronze"
    } }
    func profile(_ mode: String) -> [String:String] {
        let light: [String], dark: [String]
        switch self {
        case .threePO:
            light = ["F5EFDF","EAE1C9","FFFCF3","352A18","826017","D9C99E","F2EAD5","E8D7AC","FBF7EA"]
            dark = ["19160F","211C12","2B2418","F6EED9","E0BA63","51422A","352C1D","4B3B20","211C12"]
        case .sage:
            light = ["F4F2EA","EAEDE3","FFFEFA","26332C","456B54","DDE3D8","EEF1E9","DCE9DD","F8F9F3"]
            dark = ["171E1A","1C2620","222D26","E8EFE8","A5CBAA","36483B","2C3A30","334B3A","1A241D"]
        case .ocean:
            light = ["EDF3F8","E3EDF5","FFFFFF","20364A","2C678F","D6E2EC","EEF4F8","DCECF8","F5F8FB"]
            dark = ["101C28","142333","1C2D3E","E5EEF6","91C5E8","324B62","243A4D","2B4C65","142333"]
        case .graphite:
            light = ["F0F1F3","E6E8EC","FFFFFF","292D35","496486","DADDE3","F0F1F4","E0E7F1","F7F8FA"]
            dark = ["181A1F","1D2026","252830","ECEEF3","AEC2DF","3B404C","30343E","354359","1D2026"]
        case .rose:
            light = ["F6F0F1","EFE5E9","FFFBFC","412D39","86516C","E7D7DF","F5ECEF","EFDFE8","FAF4F7"]
            dark = ["241B22","2C202A","342731","F2E8EF","D6A9C2","503C49","41313D","503B4D","291E27"]
        }
        let roles: [WorkspaceColorRole] = [.canvas,.sidebar,.widget,.text,.accent,.border,.assistantBubble,.userBubble,.input]
        return Dictionary(uniqueKeysWithValues:zip(roles,mode == "dark" ? dark : light).map { ($0.rawValue,"#" + $1) })
    }
    var profiles: [String:[String:String]] { ["light":profile("light"),"dark":profile("dark")] }
}
struct WorkspacePalette {
    var colors: [WorkspaceColorRole:Color]
    subscript(_ role: WorkspaceColorRole) -> Color { colors[role]! }
    static func resolved(raw: String, mode: String, theme: String, accent: String) -> Self {
        let dark = mode == "dark", overrides = WorkspaceColorOverrides(raw:raw)
        func native(_ value: NSColor) -> Color {
            let appearance = NSAppearance(named:dark ? .darkAqua : .aqua)!
            var result = value
            appearance.performAsCurrentDrawingAppearance { result = value.usingColorSpace(.sRGB) ?? value }
            return Color(nsColor:result)
        }
        let tint: Color = accent == "blue" ? .blue : accent == "rose" ? Color(red:0.69,green:0.36,blue:0.43) : dark ? Color(red:0.60,green:0.76,blue:0.64) : Color(red:0.32,green:0.48,blue:0.38)
        let canvas = theme == "native" ? native(.windowBackgroundColor) : dark ? Color(red:0.12,green:0.13,blue:0.12) : Color(red:0.96,green:0.95,blue:0.92)
        let text = overrides.color(.text,mode:mode) ?? native(.labelColor)
        let accentColor = overrides.color(.accent,mode:mode) ?? tint
        let defaults: [WorkspaceColorRole:Color] = [.canvas:canvas,.sidebar:canvas,.widget:native(.controlBackgroundColor),.text:text,.accent:accentColor,.border:text.opacity(0.06),.assistantBubble:text.opacity(0.035),.userBubble:accentColor.opacity(0.12),.input:native(.textBackgroundColor)]
        return .init(colors:Dictionary(uniqueKeysWithValues:WorkspaceColorRole.allCases.map { ($0,overrides.color($0,mode:mode) ?? defaults[$0]!) }))
    }
    static var standard: Self { resolved(raw:"{}",mode:NSApp?.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? "dark" : "light",theme:"native",accent:"blue") }
}
private struct WorkspacePaletteKey: EnvironmentKey { static var defaultValue: WorkspacePalette { .standard } }
extension EnvironmentValues {
    var workspacePalette: WorkspacePalette { get { self[WorkspacePaletteKey.self] } set { self[WorkspacePaletteKey.self] = newValue } }
}
struct WorkspaceColorEditor: View {
    @AppStorage("workspaceColorOverrides") private var raw = "{}"
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAccent") private var accent = "sage"
    @AppStorage("workspaceSavedThemes") private var savedThemes = "{}"
    @AppStorage("workspaceSelectedSavedTheme") private var selectedSavedTheme = ""
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "light"
    @State private var themeName:WorkspaceThemeNameDraft?
    @State private var themeError:String?
    @State private var themeUndo:(previous:String,expected:String,previousSelection:String,expectedSelection:String)?
    private var library:WorkspaceThemeLibrary? {try? .init(raw:savedThemes)}
    private var currentTheme:SavedWorkspaceTheme? {library?.selected(selectedSavedTheme,colors:raw,baseTheme:theme,accent:accent)}
    private var overrides: WorkspaceColorOverrides { .init(raw:raw) }
    private var palette: WorkspacePalette { .resolved(raw:raw,mode:mode,theme:theme,accent:accent) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("Workspace colours").font(.title2.weight(.semibold)); Spacer(); Picker("Palette",selection:$mode) { Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented).labelsHidden().frame(width:150) }
            Text("Changes save automatically. Light and dark keep their own colours; System appearance switches between them.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("Theme",selection:Binding(get:{ currentTheme.map{"saved:"+$0.id.uuidString} ?? (overrides.profiles.isEmpty ? "defaults" : WorkspaceColorTheme.allCases.first(where:{ $0.profiles == overrides.profiles })?.rawValue ?? "custom") },set:{ selected in
                    if selected.hasPrefix("saved:"),let value=library?.themes.first(where:{"saved:"+$0.id.uuidString == selected}) {applyTheme(value);return}
                    selectedSavedTheme=""
                    var value = overrides
                    if selected == "defaults" { value.profiles = [:] }
                    else if let preset = WorkspaceColorTheme(rawValue:selected) { value.profiles = preset.profiles }
                    raw = value.encoded
                })) {
                    Text("Custom / current").tag("custom")
                    Text("Theme defaults").tag("defaults")
                    ForEach(WorkspaceColorTheme.allCases) { Text($0.title).tag($0.rawValue) }
                    if let library,!library.themes.isEmpty {Section("My themes") {ForEach(library.themes) {Text($0.name).tag("saved:"+$0.id.uuidString)}}}
                }.frame(width:240)
                Spacer()
                Text("Applies light and dark").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Save as theme…") {themeName = .init(value:.init(name:"",colorOverrides:raw,baseTheme:theme,accent:accent))}.disabled(library == nil || !WorkspaceThemeLibrary.validColors(raw))
                Menu("My themes") {
                    if let library {ForEach(library.themes) {value in
                        Menu(value.name) {
                            Button("Use theme") {applyTheme(value)}
                            Button("Update from current colours") {saveTheme(.init(id:value.id,name:value.name,colorOverrides:raw,baseTheme:theme,accent:accent),expected:value)}
                            Button("Rename…") {themeName = .init(value:value,expected:value)}
                            Button("Remove saved theme") {do {var current=try WorkspaceThemeLibrary(raw:savedThemes);try current.remove(value);try commit(current,selection:selectedSavedTheme == value.id.uuidString ? "" : nil)} catch {themeError=error.localizedDescription}}
                        }
                    }}
                }.disabled(library?.themes.isEmpty != false)
                Spacer()
                if let undo=themeUndo,savedThemes == undo.expected {Button("Undo theme change") {savedThemes=undo.previous;if selectedSavedTheme == undo.expectedSelection {selectedSavedTheme=undo.previousSelection};themeUndo=nil;themeError=nil}.buttonStyle(.borderless)}
            }.controlSize(.small)
            if let error=themeError {Text(error).font(.caption).foregroundStyle(.orange)}
            if library == nil {Text("Saved themes are unavailable. Their storage is preserved.").font(.caption).foregroundStyle(.orange)}
            preview
            ScrollView {
                VStack(spacing:12) {
                    ForEach(WorkspaceColorRole.allCases) { role in
                        HStack {
                            Text(role.title).frame(maxWidth:.infinity,alignment:.leading)
                            ColorPicker(role.title,selection:binding(role),supportsOpacity:false).labelsHidden()
                            WorkspaceHexField(value:overrides.profiles[mode]?[role.rawValue] ?? "",title:role.title) { hex in
                                var value = overrides
                                value.profiles[mode,default:[:]][role.rawValue] = hex
                                raw = value.encoded
                            }.id(mode + role.rawValue)
                            Button("Default") { var value = overrides; value.set(role,mode:mode,color:nil); raw = value.encoded }.buttonStyle(.borderless).disabled(overrides.profiles[mode]?[role.rawValue] == nil).help("Use the theme's default for " + role.title.lowercased())
                        }
                    }
                }.padding(4)
            }
            HStack { Button("Reset this palette") { var value = overrides; value.profiles[mode] = nil; raw = value.encoded }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:580,height:680).onAppear { mode = scheme == .dark ? "dark" : "light" }
            .sheet(item:$themeName) {draft in WorkspaceThemeNameEditor(draft:draft) {value in try saveThemeOrThrow(value,expected:draft.expected)}}
    }
    private func applyTheme(_ value:SavedWorkspaceTheme) {raw=value.colorOverrides;theme=value.baseTheme;accent=value.accent;selectedSavedTheme=value.id.uuidString}
    private func commit(_ value:WorkspaceThemeLibrary,selection:String? = nil)throws {
        let previous=savedThemes,previousSelection=selectedSavedTheme,next=try value.encoded;savedThemes=next
        if let selection {selectedSavedTheme=selection}
        themeUndo=(previous,next,previousSelection,selectedSavedTheme);themeError=nil
    }
    private func saveThemeOrThrow(_ value:SavedWorkspaceTheme,expected:SavedWorkspaceTheme?,selectCurrent:Bool = false)throws {var current=try WorkspaceThemeLibrary(raw:savedThemes);try current.save(value,expected:expected);try commit(current,selection:expected == nil || selectedSavedTheme == value.id.uuidString || selectCurrent ? value.id.uuidString : nil)}
    private func saveTheme(_ value:SavedWorkspaceTheme,expected:SavedWorkspaceTheme?) {do {try saveThemeOrThrow(value,expected:expected,selectCurrent:true)} catch {themeError=error.localizedDescription}}
    private func binding(_ role: WorkspaceColorRole) -> Binding<Color> {
        Binding(get:{ palette[role] },set:{ color in var value = overrides; value.set(role,mode:mode,color:color); raw = value.encoded })
    }
    private var preview: some View {
        HStack(spacing:10) {
            VStack(alignment:.leading,spacing:8) { Text("Dashboard").font(.caption.weight(.semibold)); Label("Today",systemImage:"square.grid.2x2").foregroundStyle(palette[.accent]); Spacer() }.padding(10).frame(width:105).background(palette[.sidebar],in:RoundedRectangle(cornerRadius:8))
            VStack(alignment:.leading,spacing:7) {
                Text("Your PA").font(.headline)
                Text("A little clarity for your day.").font(.caption).foregroundStyle(palette[.text].opacity(0.65))
                Text("Good morning.").padding(6).background(palette[.assistantBubble],in:RoundedRectangle(cornerRadius:6))
                HStack { Spacer(); Text("What's on today?").padding(6).background(palette[.userBubble],in:RoundedRectangle(cornerRadius:6)) }
                HStack { Text("Message your PA").foregroundStyle(palette[.text].opacity(0.65)); Spacer(); Image(systemName:"paperplane").foregroundStyle(palette[.accent]) }.font(.caption).padding(6).background(palette[.input],in:RoundedRectangle(cornerRadius:5))
            }.font(.caption).padding(10).background(palette[.widget],in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(palette[.border]))
        }.foregroundStyle(palette[.text]).padding(10).frame(height:180).background(palette[.canvas],in:RoundedRectangle(cornerRadius:12))
    }
}

#if DEBUG
/// Uses a fresh defaults suite and the existing source-free review preview startup.
struct WorkspaceThemePreview:View {
    @State private var suite="threepo-theme-preview-"+UUID().uuidString
    @State private var showing=false
    var body:some View {
        VStack(spacing:16) {
            Text("Fictional colour themes · isolated preferences · no source startup").font(.caption)
            Button("Open colour editor") {showing=true}
        }.padding(24).frame(width:640,height:740)
            .defaultAppStorage(UserDefaults(suiteName:suite)!)
            .sheet(isPresented:$showing) {WorkspaceColorEditor().defaultAppStorage(UserDefaults(suiteName:suite)!)}
            .onDisappear {UserDefaults.standard.removePersistentDomain(forName:suite)}
    }
}
#endif

private struct WorkspaceThemeNameDraft:Identifiable {
    var id=UUID()
    var value:SavedWorkspaceTheme
    var expected:SavedWorkspaceTheme? = nil
}
private struct WorkspaceThemeNameEditor:View {
    let draft:WorkspaceThemeNameDraft
    var save:(SavedWorkspaceTheme)throws->Void
    @Environment(\.dismiss) private var dismiss
    @State private var name:String
    @State private var error:String?
    init(draft:WorkspaceThemeNameDraft,save:@escaping(SavedWorkspaceTheme)throws->Void) {self.draft=draft;self.save=save;_name=State(initialValue:draft.value.name)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text(draft.expected == nil ? "Save colour theme" : "Rename theme").font(.title2.weight(.semibold))
            Text("Includes your light and dark colours. Individual widget colours keep their own overrides.").font(.callout).foregroundStyle(.secondary)
            TextField("Theme name",text:$name).textFieldStyle(.roundedBorder).accessibilityLabel("Theme name")
            if let error {Text(error).font(.caption).foregroundStyle(.orange)}
            HStack {Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction);Spacer();Button("Save") {do {var value=draft.value;value.name=name;try save(value);dismiss()} catch {self.error=error.localizedDescription}}.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count > 60)}
        }.padding(24).frame(width:440)
    }
}

private struct WorkspaceHexField: View {
    let value: String
    let title: String
    var save: (String) -> Void
    @State private var draft = ""
    @State private var invalid = false
    var body: some View {
        TextField("Theme",text:$draft)
            .font(.system(.caption,design:.monospaced)).textFieldStyle(.roundedBorder).frame(width:80)
            .accessibilityLabel(title + " hex colour")
            .help(invalid ? "Enter six hexadecimal digits, for example #345678" : "Enter a hex colour, for example #345678, then press Return")
            .overlay(RoundedRectangle(cornerRadius:4).stroke(invalid ? Color.red : Color.clear))
            .onAppear { draft = value }
            .onChange(of:value) { _,newValue in draft = newValue; invalid = false }
            .onSubmit {
                let hex = draft.trimmingCharacters(in:.whitespacesAndNewlines)
                guard WorkspaceColorOverrides.components(hex) != nil else { invalid = true; return }
                let canonical = "#" + (hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).uppercased()
                invalid = false; draft = canonical; save(canonical)
            }
    }
}

extension WorkspacePalette {
    func applying(_ profiles: [String:[String:String]]?, mode: String) -> Self {
        var result = self
        for role in WorkspaceColorRole.allCases {
            guard let hex = profiles?[mode]?[role.rawValue], let (r,g,b) = WorkspaceColorOverrides.components(hex) else { continue }
            result.colors[role] = Color(.sRGB,red:r,green:g,blue:b,opacity:1)
        }
        return result
    }
}
struct WidgetColourEditor: View {
    @Binding var configuration: WidgetConfiguration
    let title: String
    @AppStorage("workspaceColorOverrides") private var raw = "{}"
    @AppStorage("workspaceTheme") private var theme = "warm"
    @AppStorage("workspaceAccent") private var accent = "sage"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "light"
    private let roles: [WorkspaceColorRole] = [.widget,.text,.accent,.border,.assistantBubble,.userBubble,.input]
    private var palette: WorkspacePalette { WorkspacePalette.resolved(raw:raw,mode:mode,theme:theme,accent:accent).applying(configuration.colourProfiles,mode:mode) }
    private func set(_ role: WorkspaceColorRole, hex: String?) {
        var profiles = configuration.colourProfiles ?? [:]
        profiles[mode,default:[:]][role.rawValue] = hex
        configuration.colourProfiles = profiles
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text(title + " colours").font(.title2.weight(.semibold)); Spacer(); Picker("Palette",selection:$mode) { Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented).labelsHidden().frame(width:150) }
            Text("Only this widget changes. Colours without an override follow your dashboard theme.").font(.callout).foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:10) {
                Text(title).font(.headline)
                Text("A little clarity for your day.")
                HStack { Text("Theme accent").foregroundStyle(palette[.accent]); Spacer(); Text("A message").padding(6).background(palette[.userBubble],in:RoundedRectangle(cornerRadius:6)) }
            }.foregroundStyle(palette[.text]).padding(16).frame(maxWidth:.infinity).background(palette[.widget],in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(palette[.border]))
            ScrollView {
                VStack(spacing:12) {
                    ForEach(roles) { role in
                        HStack {
                            Text(role.title).frame(maxWidth:.infinity,alignment:.leading)
                            ColorPicker(role.title,selection:Binding(get:{ palette[role] },set:{ colour in
                                var value = WorkspaceColorOverrides(); value.set(role,mode:mode,color:colour); set(role,hex:value.profiles[mode]?[role.rawValue])
                            }),supportsOpacity:false).labelsHidden()
                            WorkspaceHexField(value:configuration.colourProfiles?[mode]?[role.rawValue] ?? "",title:role.title) { set(role,hex:$0) }.id(mode + role.rawValue)
                            Button("Use theme") { set(role,hex:nil) }.buttonStyle(.borderless).disabled(configuration.colourProfiles?[mode]?[role.rawValue] == nil)
                        }
                    }
                }.padding(4)
            }
            HStack { Button("Use theme for this widget") { configuration.colourProfiles = nil }; Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width:560,height:520).onAppear { mode = scheme == .dark ? "dark" : "light" }
    }
}

// AppKit's fullscreen titlebar can ignore SwiftUI's toolbar background.
// Make its underlying window transparent to the same canvas colour.
struct WorkspaceWindowColour: NSViewRepresentable {
    let colour: NSColor
    func makeNSView(context: Context) -> ColourView { ColourView() }
    func updateNSView(_ view: ColourView, context: Context) { view.colour = colour; view.apply() }
    final class ColourView: NSView {
        var colour: NSColor = .windowBackgroundColor
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            guard let window else { return }
            for name in [NSWindow.didEnterFullScreenNotification,NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main) { [weak self] _ in self?.apply() })
            }
            apply()
        }
        func apply() { window?.titlebarAppearsTransparent = true; window?.backgroundColor = colour }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
