// Renders the app icon and packs it into Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / canvas
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // macOS icon grid: 824pt rounded square centered on a 1024pt canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.27, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.42, green: 0.20, blue: 0.85, alpha: 1),
    ])!.draw(in: tilePath, angle: -60)

    // Three panes in a BSP split: one tall pane on the left, two stacked on the right.
    let inset: CGFloat = 96
    let gap: CGFloat = 36
    let area = tile.insetBy(dx: inset, dy: inset)
    let leftWidth = (area.width - gap) * 0.5
    let rightHeight = (area.height - gap) / 2
    let panes = [
        NSRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height),
        NSRect(x: area.minX + leftWidth + gap, y: area.minY + rightHeight + gap, width: area.width - leftWidth - gap, height: rightHeight),
        NSRect(x: area.minX + leftWidth + gap, y: area.minY, width: area.width - leftWidth - gap, height: rightHeight),
    ]
    let opacities: [CGFloat] = [0.96, 0.78, 0.62]
    for (pane, opacity) in zip(panes, opacities) {
        let path = NSBezierPath(roundedRect: pane, xRadius: 44, yRadius: 44)
        NSColor.white.withAlphaComponent(opacity).setFill()
        path.fill()
        // Title bar strip with traffic-light dots, so the panes read as windows.
        let bar = NSRect(x: pane.minX, y: pane.maxY - 70, width: pane.width, height: 70)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor(srgbRed: 0.16, green: 0.18, blue: 0.45, alpha: 0.18).setFill()
        bar.fill()
        NSGraphicsContext.restoreGraphicsState()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: pane.minX + 34 + CGFloat(i) * 40, y: bar.midY - 13, width: 26, height: 26)).fill()
        }
    }

    // Subtle top highlight for depth.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: CGFloat(points)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: CGFloat(points * 2)).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
