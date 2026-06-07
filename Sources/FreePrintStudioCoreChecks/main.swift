import FreePrintStudioCore

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

check(MeasurementUnit.inch.points(from: 1) == 72, "1 inch should equal 72 printer points")
check(abs(MeasurementUnit.centimeter.points(from: 2.54) - 72) < 0.0001, "2.54 cm should equal 72 printer points")
check(abs(MeasurementUnit.millimeter.points(from: 25.4) - 72) < 0.0001, "25.4 mm should equal 72 printer points")

let letter = PaperPreset.letter.size
check(letter.widthPoints == 612, "Letter width should be 612 points")
check(letter.heightPoints == 792, "Letter height should be 792 points")

let landscapeLetter = PaperPreset.letter.size(orientation: .landscape)
check(landscapeLetter.widthPoints == 792, "Landscape Letter width should be 792 points")
check(landscapeLetter.heightPoints == 612, "Landscape Letter height should be 612 points")

let a4 = PaperPreset.a4.size
check(abs(a4.width(in: .millimeter) - 210) < 0.0001, "A4 width should be 210 mm")
check(abs(a4.height(in: .millimeter) - 297) < 0.0001, "A4 height should be 297 mm")

let fourInchesAsCentimeters = PrintSizing.convertMeasurement(4, from: .inch, to: .centimeter)
check(abs(fourInchesAsCentimeters - 10.16) < 0.0001, "4 inches should be 10.16 cm")

let sixInchesAsMillimeters = PrintSizing.convertMeasurement(6, from: .inch, to: .millimeter)
check(abs(sixInchesAsMillimeters - 152.4) < 0.0001, "6 inches should be 152.4 mm")

check(PrintSizing.parseMeasurement("4.5") == 4.5, "Decimal point input should parse")
check(PrintSizing.parseMeasurement(" 6,25 ") == 6.25, "Decimal comma input should parse")
check(PrintSizing.parseMeasurement("4,5.6") == nil, "Mixed decimal separators should be rejected")

let validTargetValidation = PrintSizing.targetSizeValidation(width: 4, height: 6, unit: .inch, paperSize: letter)
check(validTargetValidation == .valid, "4 x 6 in should fit on portrait Letter paper")

let invalidTargetValidation = PrintSizing.targetSizeValidation(width: 0, height: 6, unit: .inch, paperSize: letter)
check(invalidTargetValidation == .invalidDimension, "Zero width should be rejected")

let oversizedTargetValidation = PrintSizing.targetSizeValidation(width: 12, height: 9, unit: .inch, paperSize: letter)
check(oversizedTargetValidation == .exceedsPaper(maxWidth: 8.5, maxHeight: 11), "12 x 9 in should be rejected for portrait Letter paper")

let target = PrintSizing.targetSize(width: 4, height: 6, unit: .inch)
let placement = PrintSizing.centeredPlacement(targetSize: target, on: letter)
check(placement.widthPoints == 288, "4 inch target width should be 288 points")
check(placement.heightPoints == 432, "6 inch target height should be 432 points")
check(placement.xPoints == 162, "Centered x should be 162 points")
check(placement.yPoints == 180, "Centered y should be 180 points")

let outOfBounds = PrintPlacement(xPoints: -50, yPoints: 900, widthPoints: 288, heightPoints: 432)
let clamped = PrintSizing.clamped(outOfBounds, to: letter)
check(clamped.xPoints == 0, "Clamped x should stay inside paper")
check(clamped.yPoints == 360, "Clamped y should stay inside paper")

let imageSize = PrintSize(widthPoints: 400, heightPoints: 200)
let targetRect = PrintPlacement(xPoints: 10, yPoints: 20, widthPoints: 100, heightPoints: 100)

let fitRect = PrintSizing.imageDrawRect(imageSize: imageSize, in: targetRect, mode: .fit)
check(fitRect.xPoints == 10, "Fit x should align with placement")
check(fitRect.yPoints == 45, "Fit y should vertically center the image")
check(fitRect.widthPoints == 100, "Fit width should use full placement width")
check(fitRect.heightPoints == 50, "Fit height should preserve image aspect ratio")

let fillRect = PrintSizing.imageDrawRect(imageSize: imageSize, in: targetRect, mode: .fill)
check(fillRect.xPoints == -40, "Fill x should center the cropped image")
check(fillRect.yPoints == 20, "Fill y should align with placement")
check(fillRect.widthPoints == 200, "Fill width should overflow for cropping")
check(fillRect.heightPoints == 100, "Fill height should use full placement height")

let stretchRect = PrintSizing.imageDrawRect(imageSize: imageSize, in: targetRect, mode: .stretch)
check(stretchRect == PrintRect(xPoints: 10, yPoints: 20, widthPoints: 100, heightPoints: 100), "Stretch should match placement exactly")

let portraitPreview = PrintSizing.previewSize(
    paperSize: PrintSize(widthPoints: 288, heightPoints: 432),
    maxWidth: 440,
    maxHeight: 420
)
check(abs(portraitPreview.width - 280) < 0.0001, "Portrait preview width should shrink to fit the max height")
check(abs(portraitPreview.height - 420) < 0.0001, "Portrait preview height should use the max height")

let landscapePreview = PrintSizing.previewSize(
    paperSize: PrintSize(widthPoints: 432, heightPoints: 288),
    maxWidth: 440,
    maxHeight: 420
)
check(abs(landscapePreview.width - 440) < 0.0001, "Landscape preview width should use the max width")
check(abs(landscapePreview.height - 293.3333333333) < 0.0001, "Landscape preview height should preserve the paper ratio")

print("FreePrintStudioCoreChecks passed")
