import SwiftUI
import UIKit

struct PaperCanvasView: View {
    let paperSize: PrintSize
    let image: UIImage?
    let fitMode: ImageFitMode
    @Binding var placement: PrintPlacement
    @State private var dragStart: PrintPlacement?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / paperSize.widthPoints,
                geometry.size.height / paperSize.heightPoints
            )
            let canvasSize = CGSize(
                width: paperSize.widthPoints * scale,
                height: paperSize.heightPoints * scale
            )

            ZStack {
                Color.clear
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.white)
                    GridOverlay()
                    if let image {
                        imageLayer(image, scale: scale)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 34, weight: .regular))
                                .foregroundStyle(.secondary)
                            Text("Choose an image")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(paperSize.widthPoints / paperSize.heightPoints, contentMode: .fit)
    }

    private func imageLayer(_ image: UIImage, scale: Double) -> some View {
        let drawRect = PrintSizing.imageDrawRect(
            imageSize: PrintSize(widthPoints: image.size.width, heightPoints: image.size.height),
            in: placement,
            mode: fitMode
        )

        return ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .frame(width: drawRect.widthPoints * scale, height: drawRect.heightPoints * scale)
                .position(
                    x: (drawRect.xPoints - placement.xPoints + drawRect.widthPoints / 2) * scale,
                    y: (drawRect.yPoints - placement.yPoints + drawRect.heightPoints / 2) * scale
                )

            Rectangle()
                .stroke(.blue, lineWidth: 2)
                .frame(width: placement.widthPoints * scale, height: placement.heightPoints * scale)
                .position(
                    x: placement.widthPoints * scale / 2,
                    y: placement.heightPoints * scale / 2
                )
        }
        .frame(width: placement.widthPoints * scale, height: placement.heightPoints * scale)
        .position(
            x: (placement.xPoints + placement.widthPoints / 2) * scale,
            y: (placement.yPoints + placement.heightPoints / 2) * scale
        )
        .clipped()
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = placement
                    }
                    let origin = dragStart ?? placement
                    let updated = PrintPlacement(
                        xPoints: origin.xPoints + value.translation.width / scale,
                        yPoints: origin.yPoints + value.translation.height / scale,
                        widthPoints: origin.widthPoints,
                        heightPoints: origin.heightPoints,
                        rotationDegrees: origin.rotationDegrees
                    )
                    placement = PrintSizing.clamped(updated, to: paperSize)
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
    }
}

private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let step: CGFloat = 24
                var x: CGFloat = step
                while x < geometry.size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    x += step
                }
                var y: CGFloat = step
                while y < geometry.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    y += step
                }
            }
            .stroke(.gray.opacity(0.18), lineWidth: 0.5)
        }
    }
}
