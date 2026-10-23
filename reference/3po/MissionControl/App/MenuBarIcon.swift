import AppKit

/// A small template rendition of the app artwork: CRT, globe arc and trajectory.
/// Template rendering lets macOS supply the correct colour on either menu bar.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let frame = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15), xRadius: 4, yRadius: 4)
            frame.lineWidth = 1.3
            frame.stroke()

            let globe = NSBezierPath()
            globe.move(to: NSPoint(x: 3, y: 5.1))
            globe.curve(to: NSPoint(x: 15, y: 4), controlPoint1: NSPoint(x: 7.1, y: 8), controlPoint2: NSPoint(x: 11.2, y: 7))
            globe.lineWidth = 0.85
            globe.stroke()

            let trajectory = NSBezierPath()
            trajectory.move(to: NSPoint(x: 4, y: 3.8))
            trajectory.curve(to: NSPoint(x: 13.2, y: 12.7), controlPoint1: NSPoint(x: 7, y: 9.1), controlPoint2: NSPoint(x: 10.4, y: 12))
            trajectory.lineWidth = 1.3
            trajectory.lineCapStyle = .round
            trajectory.stroke()
            NSBezierPath(ovalIn: NSRect(x: 11.8, y: 11.3, width: 2.8, height: 2.8)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "3PO"
        return image
    }()
}
