import Foundation

public enum MeasurementUnit: String, CaseIterable, Identifiable, Sendable {
    case inch
    case centimeter
    case millimeter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inch:
            return "in"
        case .centimeter:
            return "cm"
        case .millimeter:
            return "mm"
        }
    }

    public func points(from value: Double) -> Double {
        switch self {
        case .inch:
            return value * PrintSizing.pointsPerInch
        case .centimeter:
            return value / 2.54 * PrintSizing.pointsPerInch
        case .millimeter:
            return value / 25.4 * PrintSizing.pointsPerInch
        }
    }

    public func value(fromPoints points: Double) -> Double {
        switch self {
        case .inch:
            return points / PrintSizing.pointsPerInch
        case .centimeter:
            return points / PrintSizing.pointsPerInch * 2.54
        case .millimeter:
            return points / PrintSizing.pointsPerInch * 25.4
        }
    }
}

public enum PaperPreset: String, CaseIterable, Identifiable, Sendable {
    case letter
    case a4
    case fourBySix
    case fiveBySeven

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .letter:
            return "Letter"
        case .a4:
            return "A4"
        case .fourBySix:
            return "4 x 6"
        case .fiveBySeven:
            return "5 x 7"
        }
    }

    public var size: PrintSize {
        switch self {
        case .letter:
            return PrintSize(widthPoints: 8.5 * PrintSizing.pointsPerInch, heightPoints: 11 * PrintSizing.pointsPerInch)
        case .a4:
            return PrintSize(widthPoints: MeasurementUnit.millimeter.points(from: 210), heightPoints: MeasurementUnit.millimeter.points(from: 297))
        case .fourBySix:
            return PrintSize(widthPoints: 4 * PrintSizing.pointsPerInch, heightPoints: 6 * PrintSizing.pointsPerInch)
        case .fiveBySeven:
            return PrintSize(widthPoints: 5 * PrintSizing.pointsPerInch, heightPoints: 7 * PrintSizing.pointsPerInch)
        }
    }

    public func size(orientation: PaperOrientation) -> PrintSize {
        size.oriented(orientation)
    }
}

public enum PaperOrientation: String, CaseIterable, Identifiable, Sendable {
    case portrait
    case landscape

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .portrait:
            return "Portrait"
        case .landscape:
            return "Landscape"
        }
    }
}

public enum ImageFitMode: String, CaseIterable, Identifiable, Sendable {
    case fit
    case fill
    case stretch

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fit:
            return "Fit"
        case .fill:
            return "Fill"
        case .stretch:
            return "Stretch"
        }
    }
}

public struct PrintSize: Equatable, Sendable {
    public var widthPoints: Double
    public var heightPoints: Double

    public init(widthPoints: Double, heightPoints: Double) {
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
    }

    public func width(in unit: MeasurementUnit) -> Double {
        unit.value(fromPoints: widthPoints)
    }

    public func height(in unit: MeasurementUnit) -> Double {
        unit.value(fromPoints: heightPoints)
    }

    public func oriented(_ orientation: PaperOrientation) -> PrintSize {
        switch orientation {
        case .portrait:
            return self
        case .landscape:
            return PrintSize(widthPoints: heightPoints, heightPoints: widthPoints)
        }
    }
}

public struct PrintRect: Equatable, Sendable {
    public var xPoints: Double
    public var yPoints: Double
    public var widthPoints: Double
    public var heightPoints: Double

    public init(xPoints: Double, yPoints: Double, widthPoints: Double, heightPoints: Double) {
        self.xPoints = xPoints
        self.yPoints = yPoints
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
    }
}

public struct PrintPlacement: Equatable, Sendable {
    public var xPoints: Double
    public var yPoints: Double
    public var widthPoints: Double
    public var heightPoints: Double
    public var rotationDegrees: Double

    public init(xPoints: Double, yPoints: Double, widthPoints: Double, heightPoints: Double, rotationDegrees: Double = 0) {
        self.xPoints = xPoints
        self.yPoints = yPoints
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.rotationDegrees = rotationDegrees
    }
}

public struct CanvasPreviewSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum TargetSizeValidation: Equatable, Sendable {
    case valid
    case invalidDimension
    case exceedsPaper(maxWidth: Double, maxHeight: Double)
}

public enum PrintSizing {
    public static let pointsPerInch: Double = 72

    public static func parseMeasurement(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let commaCount = trimmed.filter { $0 == "," }.count
        let dotCount = trimmed.filter { $0 == "." }.count
        guard commaCount <= 1, dotCount <= 1, !(commaCount == 1 && dotCount == 1) else {
            return nil
        }

        let normalized = commaCount == 1 ? trimmed.replacingOccurrences(of: ",", with: ".") : trimmed
        return Double(normalized)
    }

    public static func targetSize(width: Double, height: Double, unit: MeasurementUnit) -> PrintSize {
        PrintSize(widthPoints: unit.points(from: width), heightPoints: unit.points(from: height))
    }

    public static func targetSizeValidation(
        width: Double?,
        height: Double?,
        unit: MeasurementUnit,
        paperSize: PrintSize
    ) -> TargetSizeValidation {
        guard let width,
              let height,
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return .invalidDimension
        }

        let widthPoints = unit.points(from: width)
        let heightPoints = unit.points(from: height)
        let tolerance = 0.0001

        if widthPoints - paperSize.widthPoints > tolerance ||
            heightPoints - paperSize.heightPoints > tolerance {
            return .exceedsPaper(
                maxWidth: paperSize.width(in: unit),
                maxHeight: paperSize.height(in: unit)
            )
        }

        return .valid
    }

    public static func convertMeasurement(_ value: Double, from sourceUnit: MeasurementUnit, to targetUnit: MeasurementUnit) -> Double {
        targetUnit.value(fromPoints: sourceUnit.points(from: value))
    }

    public static func previewSize(paperSize: PrintSize, maxWidth: Double, maxHeight: Double) -> CanvasPreviewSize {
        guard paperSize.widthPoints > 0,
              paperSize.heightPoints > 0,
              maxWidth > 0,
              maxHeight > 0 else {
            return CanvasPreviewSize(width: 0, height: 0)
        }

        let ratio = paperSize.widthPoints / paperSize.heightPoints
        var width = maxWidth
        var height = width / ratio

        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }

        return CanvasPreviewSize(width: width, height: height)
    }

    public static func imageDrawRect(imageSize: PrintSize, in placement: PrintPlacement, mode: ImageFitMode) -> PrintRect {
        let placementRect = PrintRect(
            xPoints: placement.xPoints,
            yPoints: placement.yPoints,
            widthPoints: placement.widthPoints,
            heightPoints: placement.heightPoints
        )

        guard imageSize.widthPoints > 0,
              imageSize.heightPoints > 0,
              placement.widthPoints > 0,
              placement.heightPoints > 0 else {
            return placementRect
        }

        switch mode {
        case .stretch:
            return placementRect
        case .fit, .fill:
            let widthScale = placement.widthPoints / imageSize.widthPoints
            let heightScale = placement.heightPoints / imageSize.heightPoints
            let scale = mode == .fit ? min(widthScale, heightScale) : max(widthScale, heightScale)
            let drawWidth = imageSize.widthPoints * scale
            let drawHeight = imageSize.heightPoints * scale

            return PrintRect(
                xPoints: placement.xPoints + (placement.widthPoints - drawWidth) / 2,
                yPoints: placement.yPoints + (placement.heightPoints - drawHeight) / 2,
                widthPoints: drawWidth,
                heightPoints: drawHeight
            )
        }
    }

    public static func centeredPlacement(targetSize: PrintSize, on paperSize: PrintSize) -> PrintPlacement {
        PrintPlacement(
            xPoints: (paperSize.widthPoints - targetSize.widthPoints) / 2,
            yPoints: (paperSize.heightPoints - targetSize.heightPoints) / 2,
            widthPoints: targetSize.widthPoints,
            heightPoints: targetSize.heightPoints
        )
    }

    public static func clamped(_ placement: PrintPlacement, to paperSize: PrintSize) -> PrintPlacement {
        let x = min(max(placement.xPoints, 0), max(0, paperSize.widthPoints - placement.widthPoints))
        let y = min(max(placement.yPoints, 0), max(0, paperSize.heightPoints - placement.heightPoints))
        return PrintPlacement(
            xPoints: x,
            yPoints: y,
            widthPoints: placement.widthPoints,
            heightPoints: placement.heightPoints,
            rotationDegrees: placement.rotationDegrees
        )
    }
}
