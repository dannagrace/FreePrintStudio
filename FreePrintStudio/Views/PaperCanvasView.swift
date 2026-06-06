import SwiftUI
import UIKit

struct PaperCanvasView: View {
    let paperSize: PrintSize
    let image: UIImage?
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
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: placement.widthPoints * scale, height: placement.heightPoints * scale)
                            .clipped()
                            .overlay(
                                Rectangle()
                                    .stroke(.blue, lineWidth: 2)
                            )
                            .position(
                                x: (placement.xPoints + placement.widthPoints / 2) * scale,
                                y: (placement.yPoints + placement.heightPoints / 2) * scale
                            )
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
