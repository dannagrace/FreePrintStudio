import UIKit

enum PrintService {
    @MainActor
    static func printPDF(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard UIPrintInteractionController.canPrint(url) else {
            completion(.failure(PrintServiceError.unsupportedPDF))
            return
        }

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo
        info.jobName = "FreePrint Studio"
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true) { _, _, error in
            if let error {
                completion(.failure(error))
            }
        }
    }
}

private enum PrintServiceError: LocalizedError {
    case unsupportedPDF

    var errorDescription: String? {
        switch self {
        case .unsupportedPDF:
            return "This PDF cannot be printed from this device."
        }
    }
}
