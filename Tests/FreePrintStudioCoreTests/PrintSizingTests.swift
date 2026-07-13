import XCTest
@testable import FreePrintStudioCore

final class PrintSizingTests: XCTestCase {
    func testMeasurementUnitsUsePrinterPoints() {
        XCTAssertEqual(MeasurementUnit.inch.points(from: 1), 72, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.centimeter.points(from: 2.54), 72, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.millimeter.points(from: 25.4), 72, accuracy: 0.0001)
    }

    func testPaperPresetsAndOrientation() {
        let letter = PaperPreset.letter.size
        XCTAssertEqual(letter.widthPoints, 612, accuracy: 0.0001)
        XCTAssertEqual(letter.heightPoints, 792, accuracy: 0.0001)

        let landscapeLetter = PaperPreset.letter.size(orientation: .landscape)
        XCTAssertEqual(landscapeLetter.widthPoints, 792, accuracy: 0.0001)
        XCTAssertEqual(landscapeLetter.heightPoints, 612, accuracy: 0.0001)

        let a4 = PaperPreset.a4.size
        XCTAssertEqual(a4.width(in: .millimeter), 210, accuracy: 0.0001)
        XCTAssertEqual(a4.height(in: .millimeter), 297, accuracy: 0.0001)
    }

    func testMeasurementParsingAndConversion() {
        XCTAssertEqual(PrintSizing.parseMeasurement("4.5"), 4.5)
        XCTAssertEqual(PrintSizing.parseMeasurement(" 6,25 "), 6.25)
        XCTAssertNil(PrintSizing.parseMeasurement(""))
        XCTAssertNil(PrintSizing.parseMeasurement("4,5.6"))

        XCTAssertEqual(
            PrintSizing.convertMeasurement(4, from: .inch, to: .centimeter),
            10.16,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            PrintSizing.convertMeasurement(6, from: .inch, to: .millimeter),
            152.4,
            accuracy: 0.0001
        )
    }

    func testTargetSizeValidationAndCalibrationGuide() {
        let letter = PaperPreset.letter.size

        XCTAssertEqual(PrintSizing.calibrationGuideWidthInches, 6)
        XCTAssertEqual(PrintSizing.calibrationGuideHeightInches, 1)
        XCTAssertEqual(PrintSizing.calibrationGuideTargetSize.widthPoints, 432, accuracy: 0.0001)
        XCTAssertEqual(PrintSizing.calibrationGuideTargetSize.heightPoints, 72, accuracy: 0.0001)

        XCTAssertEqual(
            PrintSizing.targetSizeValidation(width: 4, height: 6, unit: .inch, paperSize: letter),
            .valid
        )
        XCTAssertEqual(
            PrintSizing.targetSizeValidation(width: 0, height: 6, unit: .inch, paperSize: letter),
            .invalidDimension
        )
        XCTAssertEqual(
            PrintSizing.targetSizeValidation(width: 12, height: 9, unit: .inch, paperSize: letter),
            .exceedsPaper(maxWidth: 8.5, maxHeight: 11)
        )
    }

    func testPlacementClampingAndImageFitModes() {
        let letter = PaperPreset.letter.size
        let target = PrintSizing.targetSize(width: 4, height: 6, unit: .inch)
        let placement = PrintSizing.centeredPlacement(targetSize: target, on: letter)
        XCTAssertEqual(placement.xPoints, 162, accuracy: 0.0001)
        XCTAssertEqual(placement.yPoints, 180, accuracy: 0.0001)
        XCTAssertEqual(placement.widthPoints, 288, accuracy: 0.0001)
        XCTAssertEqual(placement.heightPoints, 432, accuracy: 0.0001)

        let outOfBounds = PrintPlacement(xPoints: -50, yPoints: 900, widthPoints: 288, heightPoints: 432)
        let clamped = PrintSizing.clamped(outOfBounds, to: letter)
        XCTAssertEqual(clamped.xPoints, 0, accuracy: 0.0001)
        XCTAssertEqual(clamped.yPoints, 360, accuracy: 0.0001)

        let imageSize = PrintSize(widthPoints: 400, heightPoints: 200)
        let targetRect = PrintPlacement(xPoints: 10, yPoints: 20, widthPoints: 100, heightPoints: 100)

        let fitRect = PrintSizing.imageDrawRect(imageSize: imageSize, in: targetRect, mode: .fit)
        XCTAssertEqual(fitRect, PrintRect(xPoints: 10, yPoints: 45, widthPoints: 100, heightPoints: 50))

        let fillRect = PrintSizing.imageDrawRect(imageSize: imageSize, in: targetRect, mode: .fill)
        XCTAssertEqual(fillRect, PrintRect(xPoints: -40, yPoints: 20, widthPoints: 200, heightPoints: 100))

        let stretchRect = PrintSizing.imageDrawRect(imageSize: imageSize, in: targetRect, mode: .stretch)
        XCTAssertEqual(stretchRect, PrintRect(xPoints: 10, yPoints: 20, widthPoints: 100, heightPoints: 100))
    }

    func testPreviewSizePreservesPaperRatio() {
        let portraitPreview = PrintSizing.previewSize(
            paperSize: PrintSize(widthPoints: 288, heightPoints: 432),
            maxWidth: 440,
            maxHeight: 420
        )
        XCTAssertEqual(portraitPreview.width, 280, accuracy: 0.0001)
        XCTAssertEqual(portraitPreview.height, 420, accuracy: 0.0001)

        let landscapePreview = PrintSizing.previewSize(
            paperSize: PrintSize(widthPoints: 432, heightPoints: 288),
            maxWidth: 440,
            maxHeight: 420
        )
        XCTAssertEqual(landscapePreview.width, 440, accuracy: 0.0001)
        XCTAssertEqual(landscapePreview.height, 293.3333333333, accuracy: 0.0001)
    }
}
