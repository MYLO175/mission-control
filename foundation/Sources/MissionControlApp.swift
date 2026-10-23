import SwiftUI
import AppKit

@main struct MissionControlApp: App {
    @State private var model: FoundationModel
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let rendering = arguments.firstIndex(of: "--render-preview")
        let preview = arguments.contains("--preview") || rendering != nil
        let instance = FoundationModel(preview: preview)
        _model = State(initialValue: instance)
        if let index = rendering, arguments.indices.contains(index + 1) {
            _ = NSApplication.shared
            let content = WorkspaceView(model: instance).frame(width: 1320, height: 850).environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1.5
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                fputs("Could not render fictional preview\n", stderr); exit(1)
            }
            do { try png.write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic); exit(0) }
            catch { fputs("Could not save preview\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup(AppIdentity.name) {
            WorkspaceView(model: model).frame(minWidth: 1060, minHeight: 680)
        }.defaultSize(width: 1320, height: 850)
    }
}
