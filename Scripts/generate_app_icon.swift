import AppKit
import CoreGraphics
import Foundation

let outputDirectory = "FreePrintStudio/Resources/Assets.xcassets/AppIcon.appiconset"
let designSize: CGFloat = 1024

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

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func strokeLine(_ context: CGContext, from start: CGPoint, to end: CGPoint, width: CGFloat, color strokeColor: CGColor) {
    context.setStrokeColor(strokeColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
}

func fillPath(_ context: CGContext, points: [CGPoint], color fillColor: CGColor) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() {
        context.addLine(to: point)
    }
    context.closePath()
    context.setFillColor(fillColor)
    context.fillPath()
}

func makeIcon(pixels: Int) -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("Unable to create bitmap context")
    }

    let scale = CGFloat(pixels) / designSize
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(10, 93, 111),
            color(20, 184, 166),
            color(37, 99, 235),
            color(124, 58, 237),
        ] as CFArray,
        locations: [0, 0.42, 0.78, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 120, y: 980),
        end: CGPoint(x: 920, y: 60),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    context.setFillColor(color(255, 255, 255, 0.16))
    context.fillEllipse(in: CGRect(x: 644, y: 680, width: 300, height: 300))
    context.setFillColor(color(255, 255, 255, 0.10))
    context.fillEllipse(in: CGRect(x: 80, y: 82, width: 292, height: 292))

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 40, color: color(0, 0, 0, 0.28))
    let paperRect = CGRect(x: 278, y: 188, width: 468, height: 648)
    context.addPath(roundedRect(paperRect, radius: 42))
    context.setFillColor(color(252, 253, 255))
    context.fillPath()
    context.restoreGState()

    fillPath(
        context,
        points: [
            CGPoint(x: 638, y: 836),
            CGPoint(x: 746, y: 728),
            CGPoint(x: 638, y: 728),
        ],
        color: color(213, 228, 255)
    )

    let rulerColor = color(29, 78, 216)
    strokeLine(context, from: CGPoint(x: 226, y: 248), to: CGPoint(x: 226, y: 774), width: 26, color: rulerColor)
    strokeLine(context, from: CGPoint(x: 226, y: 248), to: CGPoint(x: 800, y: 248), width: 26, color: rulerColor)

    for index in 0...7 {
        let y = CGFloat(306 + index * 58)
        let length: CGFloat = index.isMultiple(of: 2) ? 78 : 48
        strokeLine(
            context,
            from: CGPoint(x: 226, y: y),
            to: CGPoint(x: 226 + length, y: y),
            width: 16,
            color: rulerColor
        )
    }

    for index in 0...8 {
        let x = CGFloat(292 + index * 58)
        let length: CGFloat = index.isMultiple(of: 2) ? 78 : 48
        strokeLine(
            context,
            from: CGPoint(x: x, y: 248),
            to: CGPoint(x: x, y: 248 + length),
            width: 16,
            color: rulerColor
        )
    }

    let imageFrame = CGRect(x: 350, y: 340, width: 324, height: 324)
    context.addPath(roundedRect(imageFrame, radius: 36))
    context.setFillColor(color(236, 253, 245))
    context.fillPath()

    context.addPath(roundedRect(imageFrame, radius: 36))
    context.setStrokeColor(color(14, 116, 144))
    context.setLineWidth(18)
    context.strokePath()

    context.setFillColor(color(250, 204, 21))
    context.fillEllipse(in: CGRect(x: 574, y: 568, width: 58, height: 58))

    fillPath(
        context,
        points: [
            CGPoint(x: 382, y: 382),
            CGPoint(x: 480, y: 512),
            CGPoint(x: 548, y: 448),
            CGPoint(x: 642, y: 560),
            CGPoint(x: 642, y: 382),
        ],
        color: color(34, 197, 94)
    )

    context.setStrokeColor(color(15, 23, 42, 0.28))
    context.setLineWidth(10)
    strokeLine(context, from: CGPoint(x: 386, y: 716), to: CGPoint(x: 568, y: 716), width: 18, color: color(15, 23, 42, 0.24))
    strokeLine(context, from: CGPoint(x: 386, y: 676), to: CGPoint(x: 614, y: 676), width: 14, color: color(15, 23, 42, 0.18))

    guard let image = context.makeImage() else {
        fatalError("Unable to produce app icon image")
    }
    return image
}

for (filename, pixels) in iconPixels {
    let cgImage = makeIcon(pixels: pixels)
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    bitmap.size = NSSize(width: pixels, height: pixels)

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(filename)")
    }

    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename)
    try pngData.write(to: url)
    print("Wrote \(url.path)")
}
