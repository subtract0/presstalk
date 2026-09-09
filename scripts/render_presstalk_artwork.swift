import AppKit
import Foundation

// Build the app icon from the site's existing fn key mark and palette.
// No downloaded artwork or additional fonts are required.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func render(width: Int, height: Int, name: String, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current!.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
func centered(_ text: String, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink]
    let string = text as NSString
    string.draw(at: NSPoint(x: (width - string.size(withAttributes: attributes).width) / 2, y: y), withAttributes: attributes)
}
let iconset = output.appendingPathComponent("PressTalk.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = "PressTalk.iconset/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(width: pixels, height: pixels, name: name) {
            let context = NSGraphicsContext.current!.cgContext
            context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 25; shadow.shadowOffset = NSSize(width: 0, height: -12)
            NSGraphicsContext.saveGraphicsState(); shadow.set()
            color(0x1b1e19).setFill()
            NSBezierPath(roundedRect: NSRect(x: 74, y: 64, width: 876, height: 886), xRadius: 192, yRadius: 192).fill()
            NSGraphicsContext.restoreGraphicsState()
            let face = NSBezierPath(roundedRect: NSRect(x: 82, y: 90, width: 860, height: 860), xRadius: 184, yRadius: 184)
            NSGradient(starting: color(0x34382f), ending: color(0x252722))!.draw(in: face, angle: -90)
            color(0x4b5044).setStroke(); face.lineWidth = 3; face.stroke()
            centered("fn", y: 226, width: 1024, size: 464, weight: .semibold, ink: color(0xf8f7f4))
            color(0xc36142).setFill()
            NSBezierPath(roundedRect: NSRect(x: 448, y: 766, width: 128, height: 18), xRadius: 9, yRadius: 9).fill()
        }
    }
}
try render(width: 640, height: 400, name: "installer-background.png") {
    color(0xf8f7f4).setFill(); NSRect(x: 0, y: 0, width: 640, height: 400).fill()
    centered("Install PressTalk", y: 333, width: 640, size: 25, weight: .semibold, ink: color(0x252722))
    color(0xb94829).setStroke()
    let arrow = NSBezierPath(); arrow.lineWidth = 4; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 281, y: 220)); arrow.line(to: NSPoint(x: 351, y: 220))
    arrow.move(to: NSPoint(x: 337, y: 234)); arrow.line(to: NSPoint(x: 351, y: 220)); arrow.line(to: NSPoint(x: 337, y: 206)); arrow.stroke()
    centered("Drag PressTalk to Applications", y: 70, width: 640, size: 19, weight: .medium, ink: color(0x252722))
    centered("PressTalk in Programme ziehen", y: 42, width: 640, size: 14, weight: .regular, ink: color(0x696c63))
}
