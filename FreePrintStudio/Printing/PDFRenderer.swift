import UIKit

enum PDFRenderer {
    static func render(image: UIImage, paperSize: PrintSize, placement: PrintPlacement, to url: URL) throws {
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
            drawAspectFill(image, in: imageRect)
            context.cgContext.restoreGState()
        }
    }

    private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }
}
