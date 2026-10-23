import AppKit

// Original artwork, based on Agent Handler's existing robot. Run from the repo
// root with `swift scripts/generate-icon.swift` to regenerate committed assets.
let files = FileManager.default
let output = URL(fileURLWithPath: "assets", isDirectory: true)
let iconset = files.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("iconset")
try files.createDirectory(at: output, withIntermediateDirectories: true)
try files.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? files.removeItem(at: iconset) }

func png(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()

    let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.38, blue: 0.91, alpha: 1),
        ending: NSColor(srgbRed: 0.12, green: 0.60, blue: 1, alpha: 1))!.draw(in: background, angle: 90)
    NSColor.white.setStroke()
    NSColor.white.setFill()

    let head = NSBezierPath(roundedRect: NSRect(x: 236, y: 284, width: 552, height: 392), xRadius: 110, yRadius: 110)
    head.lineWidth = 40
    head.stroke()
    let antenna = NSBezierPath()
    antenna.lineWidth = 30
    antenna.lineCapStyle = .round
    antenna.move(to: NSPoint(x: 512, y: 696))
    antenna.line(to: NSPoint(x: 512, y: 788))
    antenna.stroke()
    NSBezierPath(ovalIn: NSRect(x: 490, y: 788, width: 44, height: 44)).fill()
    for x: CGFloat in [370, 606] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 480, width: 48, height: 80), xRadius: 24, yRadius: 24).fill()
    }
    let mouth = NSBezierPath()
    mouth.lineWidth = 28
    mouth.lineCapStyle = .round
    mouth.move(to: NSPoint(x: 408, y: 390))
    mouth.line(to: NSPoint(x: 616, y: 390))
    mouth.stroke()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return data
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let data = try png(size: points * scale)
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if points == 512 && scale == 2 { try data.write(to: output.appendingPathComponent("AppIcon.png")) }
    }
}
let conversion = Process()
conversion.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
conversion.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try conversion.run()
conversion.waitUntilExit()
guard conversion.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
print("Created assets/AppIcon.png and assets/AppIcon.icns")
