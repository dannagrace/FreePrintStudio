import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedPaper: PaperPreset = .letter
    @State private var selectedOrientation: PaperOrientation = .portrait
    @State private var selectedUnit: MeasurementUnit = .inch
    @State private var selectedFitMode: ImageFitMode = .fill
    @State private var widthText = "4"
    @State private var heightText = "6"
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var placement = PrintPlacement(xPoints: 162, yPoints: 180, widthPoints: 288, heightPoints: 432)
    @State private var exportedPDF: URL?
    @State private var alertMessage: String?
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 18) {
                            controls
                            paperPreview(availableSize: geometry.size)
                        }
                        .padding(.vertical, 18)
                    }

                    actionBar
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FreePrint Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("About FreePrint Studio")
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
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
            .onChange(of: selectedOrientation) { _, _ in
                recenterImage()
            }
            .onChange(of: selectedUnit) { oldUnit, newUnit in
                convertMeasurementFields(from: oldUnit, to: newUnit)
            }
            #if DEBUG
            .onAppear {
                loadDebugImageIfRequested()
            }
            #endif
        }
    }

    private func paperPreview(availableSize: CGSize) -> some View {
        let maxPreviewWidth = max(240, Double(availableSize.width - 32))
        let maxPreviewHeight = max(260, min(520, Double(availableSize.height) - 520))
        let previewSize = PrintSizing.previewSize(
            paperSize: paperSize,
            maxWidth: maxPreviewWidth,
            maxHeight: maxPreviewHeight
        )

        return PaperCanvasView(
            paperSize: paperSize,
            image: selectedImage,
            fitMode: selectedFitMode,
            placement: $placement
        )
        .frame(width: previewSize.width, height: previewSize.height)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
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

            Picker("Orientation", selection: $selectedOrientation) {
                ForEach(PaperOrientation.allCases) { orientation in
                    Text(orientation.displayName).tag(orientation)
                }
            }
            .pickerStyle(.segmented)

            Picker("Unit", selection: $selectedUnit) {
                ForEach(MeasurementUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            Picker("Fit Mode", selection: $selectedFitMode) {
                ForEach(ImageFitMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
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
        placement = PrintSizing.centeredPlacement(targetSize: target, on: paperSize)
        exportedPDF = nil
    }

    private var paperSize: PrintSize {
        selectedPaper.size(orientation: selectedOrientation)
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
        let clampedPlacement = PrintSizing.clamped(placement, to: paperSize)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreePrintStudio-\(UUID().uuidString).pdf")
        try PDFRenderer.render(
            image: image,
            paperSize: paperSize,
            placement: clampedPlacement,
            fitMode: selectedFitMode,
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
            PrintService.printPDF(url) { result in
                if case .failure(let error) = result {
                    alertMessage = error.localizedDescription
                }
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func convertMeasurementFields(from oldUnit: MeasurementUnit, to newUnit: MeasurementUnit) {
        guard oldUnit != newUnit else { return }
        if let width = Double(widthText), width > 0 {
            widthText = formatMeasurement(PrintSizing.convertMeasurement(width, from: oldUnit, to: newUnit))
        }
        if let height = Double(heightText), height > 0 {
            heightText = formatMeasurement(PrintSizing.convertMeasurement(height, from: oldUnit, to: newUnit))
        }
        recenterImage()
    }

    private func formatMeasurement(_ value: Double) -> String {
        let rounded = (value * 1_000).rounded() / 1_000
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }

        var text = String(format: "%.3f", rounded)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    #if DEBUG
    private func loadDebugImageIfRequested() {
        guard selectedImage == nil else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let imagePathIndex = arguments.firstIndex(of: "-FreePrintStudioTestImagePath"),
              arguments.indices.contains(imagePathIndex + 1) else {
            return
        }

        let imagePath = arguments[imagePathIndex + 1]
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: imagePath)),
              let image = UIImage(data: data) else {
            alertMessage = "The test image could not be loaded."
            return
        }

        if let modeIndex = arguments.firstIndex(of: "-FreePrintStudioFitMode"),
           arguments.indices.contains(modeIndex + 1),
           let mode = ImageFitMode(rawValue: arguments[modeIndex + 1]) {
            selectedFitMode = mode
        }

        if let paperIndex = arguments.firstIndex(of: "-FreePrintStudioPaper"),
           arguments.indices.contains(paperIndex + 1),
           let paper = PaperPreset(rawValue: arguments[paperIndex + 1]) {
            selectedPaper = paper
        }

        selectedImage = image
        recenterImage()
    }
    #endif
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

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    private let privacyPolicyURL = URL(string: "https://dannagrace.github.io/FreePrintStudio/privacy-policy.html")!
    private let supportURL = URL(string: "https://dannagrace.github.io/FreePrintStudio/support.html")!

    var body: some View {
        NavigationStack {
            List {
                Section("About FreePrint Studio") {
                    Text("FreePrint Studio prepares selected images for exact-size PDF export and AirPrint. Images stay on this device during the print workflow.")
                }

                Section("Privacy Policy") {
                    Text("FreePrint Studio does not collect, transmit, sell, or share personal data. Selected images are processed locally for preview, export, and printing. The app does not use accounts, analytics, advertising SDKs, or tracking.")
                    Text("If you contact the developer outside the app, information you choose to provide is used only to respond to your request.")
                    Link(destination: privacyPolicyURL) {
                        Label("Open Privacy Policy", systemImage: "safari")
                    }
                }

                Section("Support") {
                    Link(destination: supportURL) {
                        Label("Open Support", systemImage: "questionmark.circle")
                    }
                }

                Section("Version") {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
