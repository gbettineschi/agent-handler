import AppKit

/// Original template artwork; macOS supplies the menu-bar tint in light/dark/selected states.
@MainActor enum AgentStatusIcon {
    static func image(mode: MenuBarState.Mode, frame: Int = 0) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            let rise: CGFloat = frame % 4 == 1 ? 0.5 : frame % 4 == 3 ? -0.5 : 0
            let head = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 3.5 + rise, width: 13, height: 10), xRadius: 3, yRadius: 3)
            head.lineWidth = 1.3; head.stroke()
            let antenna = NSBezierPath(); antenna.move(to: .init(x: 8, y: 14 + rise)); antenna.line(to: .init(x: 8, y: 16 + rise)); antenna.lineWidth = 1.1; antenna.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7, y: 15.5 + rise, width: 2, height: 2)).fill()
            for x: CGFloat in [5, 10] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 8 + rise, width: 1.5, height: frame % 4 == 2 ? 1 : 2.5), xRadius: 0.6, yRadius: 0.6).fill()
            }
            let mouth = NSBezierPath(); mouth.move(to: .init(x: 5.5, y: 6 + rise)); mouth.line(to: .init(x: 10, y: 6 + rise)); mouth.lineWidth = 1; mouth.stroke()
            // Small plain marks stay legible at menu-bar size; filled-circle
            // SF Symbols at 8 pt collapsed into indistinguishable dots.
            let mark = NSBezierPath(); mark.lineWidth = 1.4
            mark.lineCapStyle = .round; mark.lineJoinStyle = .round
            switch mode {
            case .attention:
                mark.move(to: .init(x: 18, y: 8)); mark.line(to: .init(x: 18, y: 4.5)); mark.stroke()
                NSBezierPath(ovalIn: NSRect(x: 17.3, y: 1.5, width: 1.5, height: 1.5)).fill()
            case .unavailable:
                NSAttributedString(string: "?", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.black])
                    .draw(at: NSPoint(x: 15.5, y: 0))
            case .failed:
                mark.move(to: .init(x: 16, y: 2)); mark.line(to: .init(x: 21, y: 7))
                mark.move(to: .init(x: 16, y: 7)); mark.line(to: .init(x: 21, y: 2)); mark.stroke()
            case .recent:
                mark.move(to: .init(x: 15.5, y: 4)); mark.line(to: .init(x: 17.5, y: 2)); mark.line(to: .init(x: 21, y: 7)); mark.stroke()
            case .paused:
                for x: CGFloat in [16, 20] { NSBezierPath(rect: NSRect(x: x, y: 2, width: 1.5, height: 6)).fill() }
            case .working, .idle: break
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Agent Handler"
        return image
    }
}
