import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedPaper: PaperPreset = .letter
    @State private var selectedUnit: MeasurementUnit = .inch
    @State private var widthText = "4"
    @State private var heightText = "6"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var placement = PrintPlacement(xPoints: 162, yPoints: 180, widthPoints: 288, heightPoints: 432)
    @State private var exportedPDF: URL?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        controls
                        PaperCanvasView(
                            paperSize: selectedPaper.size,
                            image: selectedImage,
                            placement: $placement
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 18)
                }

                actionBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FreePrint Studio")
            .navigationBarTitleDisplayMode(.inline)
            .alert("FreePrint Studio", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadPhoto(newValue) }
            }
            .onChange(of: selectedPaper) { _, _ in
                recenterImage()
            }
            .onChange(of: selectedUnit) { _, _ in
                recenterImage()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(selectedImage == nil ? "Choose Image" : "Change Image", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    recenterImage()
                } label: {
                    Label("Center", systemImage: "scope")
                }
                .buttonStyle(.bordered)
            }

            Picker("Paper", selection: $selectedPaper) {
                ForEach(PaperPreset.allCases) { paper in
                    Text(paper.displayName).tag(paper)
                }
            }
            .pickerStyle(.segmented)

            Picker("Unit", selection: $selectedUnit) {
                ForEach(MeasurementUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                MeasurementField(title: "Width", text: $widthText, unit: selectedUnit.displayName)
                MeasurementField(title: "Height", text: $heightText, unit: selectedUnit.displayName)
            }
            .onChange(of: widthText) { _, _ in recenterImage() }
            .onChange(of: heightText) { _, _ in recenterImage() }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                exportPDF()
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                printPDF()
            } label: {
                Label("Print", systemImage: "printer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                alertMessage = "The selected image could not be loaded."
                return
            }
            selectedImage = image
            recenterImage()
        } catch {
            alertMessage = "Image loading failed: \(error.localizedDescription)"
        }
    }

    private func recenterImage() {
        guard let target = targetSize else { return }
        placement = PrintSizing.centeredPlacement(targetSize: target, on: selectedPaper.size)
        exportedPDF = nil
    }

    private var targetSize: PrintSize? {
        guard let width = Double(widthText), let height = Double(heightText), width > 0, height > 0 else {
            return nil
        }
        return PrintSizing.targetSize(width: width, height: height, unit: selectedUnit)
    }

    private func renderPDF() throws -> URL {
        guard let image = selectedImage else {
            throw FreePrintStudioError.missingImage
        }
        let clampedPlacement = PrintSizing.clamped(placement, to: selectedPaper.size)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePrintStudio-\(UUID().uuidString).pdf")
        try PDFRenderer.render(
            image: image,
            paperSize: selectedPaper.size,
            placement: clampedPlacement,
            to: url
        )
        exportedPDF = url
        return url
    }

    private func exportPDF() {
        do {
            let url = try renderPDF()
            SharePresenter.present(items: [url])
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func printPDF() {
        do {
            let url = try renderPDF()
            PrintService.printPDF(url)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct MeasurementField: View {
    let title: String
    @Binding var text: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(title, text: $text)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private enum FreePrintStudioError: LocalizedError {
    case missingImage

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "Choose an image before exporting or printing."
        }
    }
}
