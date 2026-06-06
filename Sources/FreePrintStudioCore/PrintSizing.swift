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

public enum PrintSizing {
    public static let pointsPerInch: Double = 72

    public static func targetSize(width: Double, height: Double, unit: MeasurementUnit) -> PrintSize {
        PrintSize(widthPoints: unit.points(from: width), heightPoints: unit.points(from: height))
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
