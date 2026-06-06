import AppKit

let size = NSSize(width: 1024, height: 1024)
let outputDirectory = "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset"

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

let iconPixels: [(String, Int)] = [
    ("Icon-20@1x.png", 20),
    ("Icon-20@2x.png", 40),
    ("Icon-20@3x.png", 60),
    ("Icon-29@1x.png", 29),
    ("Icon-29@2x.png", 58),
    ("Icon-29@3x.png", 87),
    ("Icon-40@1x.png", 40),
    ("Icon-40@2x.png", 80),
    ("Icon-40@3x.png", 120),
    ("Icon-60@2x.png", 120),
    ("Icon-60@3x.png", 180),
    ("Icon-76@2x.png", 152),
    ("Icon-83.5@2x.png", 167),
    ("AppIcon.png", 1024),
]

func drawIcon(into bitmap: NSBitmapImageRep) {
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let bounds = NSRect(origin: .zero, size: size)
    let background = NSGradient(colors: [
        color(15, 118, 110),
        color(20, 184, 166),
        color(59, 130, 246),
    ])!
    background.draw(in: bounds, angle: 45)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -18)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    let paperRect = NSRect(x: 268, y: 188, width: 488, height: 648)
    let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: 42, yRadius: 42)
    color(252, 253, 255).setFill()
    paperPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: 650, y: 836))
    foldPath.line(to: NSPoint(x: 756, y: 730))
    foldPath.line(to: NSPoint(x: 650, y: 730))
    foldPath.close()
    color(216, 232, 255).setFill()
    foldPath.fill()

    color(37, 99, 235).setStroke()
    let rulerPath = NSBezierPath()
    rulerPath.lineWidth = 26
    rulerPath.lineCapStyle = .round
    rulerPath.move(to: NSPoint(x: 230, y: 246))
    rulerPath.line(to: NSPoint(x: 230, y: 778))
    rulerPath.move(to: NSPoint(x: 230, y: 246))
    rulerPath.line(to: NSPoint(x: 794, y: 246))
    rulerPath.stroke()

    for index in 0...7 {
        let y = CGFloat(306 + index * 58)
        let length: CGFloat = index % 2 == 0 ? 76 : 46
        let tick = NSBezierPath()
        tick.lineWidth = 16
        tick.lineCapStyle = .round
        tick.move(to: NSPoint(x: 230, y: y))
        tick.line(to: NSPoint(x: 230 + length, y: y))
        tick.stroke()
    }

    for index in 0...8 {
        let x = CGFloat(292 + index * 58)
        let length: CGFloat = index % 2 == 0 ? 76 : 46
        let tick = NSBezierPath()
        tick.lineWidth = 16
        tick.lineCapStyle = .round
        tick.move(to: NSPoint(x: x, y: 246))
        tick.line(to: NSPoint(x: x, y: 246 + length))
        tick.stroke()
    }

    let imageFrame = NSRect(x: 354, y: 344, width: 316, height: 316)
    let framePath = NSBezierPath(roundedRect: imageFrame, xRadius: 34, yRadius: 34)
    color(235, 248, 255).setFill()
    framePath.fill()
    color(14, 116, 144).setStroke()
    framePath.lineWidth = 18
    framePath.stroke()

    let sunPath = NSBezierPath(ovalIn: NSRect(x: 574, y: 570, width: 56, height: 56))
    color(250, 204, 21).setFill()
    sunPath.fill()

    let mountainPath = NSBezierPath()
    mountainPath.move(to: NSPoint(x: 382, y: 382))
    mountainPath.line(to: NSPoint(x: 482, y: 512))
    mountainPath.line(to: NSPoint(x: 548, y: 448))
    mountainPath.line(to: NSPoint(x: 642, y: 560))
    mountainPath.line(to: NSPoint(x: 642, y: 382))
    mountainPath.close()
    color(34, 197, 94).setFill()
    mountainPath.fill()

    NSGraphicsContext.restoreGraphicsState()
}

for (filename, pixels) in iconPixels {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 3,
        hasAlpha: false,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap context for \(filename)")
    }

    drawIcon(into: bitmap)

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(filename)")
    }

    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
    try pngData.write(to: url)
    print("Wrote \(url.path)")
}
