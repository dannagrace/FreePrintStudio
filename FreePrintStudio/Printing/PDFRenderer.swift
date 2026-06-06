import UIKit

enum PDFRenderer {
    static func render(image: UIImage, paperSize: PrintSize, placement: PrintPlacement, fitMode: ImageFitMode, to url: URL) throws {
        let bounds = CGRect(x: 0, y: 0, width: paperSize.widthPoints, height: paperSize.heightPoints)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        try renderer.writePDF(to: url) { context in
            context.beginPage()
            UIColor.white.setFill()
            context.cgContext.fill(bounds)

            let imageRect = CGRect(
                x: placement.xPoints,
                y: placement.yPoints,
                width: placement.widthPoints,
                height: placement.heightPoints
            )

            context.cgContext.saveGState()
            context.cgContext.addRect(imageRect)
            context.cgContext.clip()
            let drawRect = PrintSizing.imageDrawRect(
                imageSize: PrintSize(widthPoints: image.size.width, heightPoints: image.size.height),
                in: placement,
                mode: fitMode
            )
            image.draw(in: CGRect(
                x: drawRect.xPoints,
                y: drawRect.yPoints,
                width: drawRect.widthPoints,
                height: drawRect.heightPoints
            ))
            context.cgContext.restoreGState()
        }
    }
}
