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

let a4 = PaperPreset.a4.size
check(abs(a4.width(in: .millimeter) - 210) < 0.0001, "A4 width should be 210 mm")
check(abs(a4.height(in: .millimeter) - 297) < 0.0001, "A4 height should be 297 mm")

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

print("FreePrintStudioCoreChecks passed")
