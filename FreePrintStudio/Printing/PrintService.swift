import UIKit

enum PrintService {
    @MainActor
    @discardableResult
    static func printPDF(_ url: URL, completion: @escaping (Result<Void, Error>) -> Void) -> Bool {
        guard UIPrintInteractionController.canPrint(url) else {
            completion(.failure(PrintServiceError.unsupportedPDF))
            return false
        }

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo
        info.jobName = "FreePrint Studio"
        controller.printInfo = info
        controller.printingItem = url
        let didPresent = controller.present(animated: true) { _, _, error in
            if let error {
                completion(.failure(error))
            }
        }
        if !didPresent {
            completion(.failure(PrintServiceError.presentationFailed))
        }
        return didPresent
    }
}

private enum PrintServiceError: LocalizedError {
    case unsupportedPDF
    case presentationFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedPDF:
            return "This PDF cannot be printed from this device."
        case .presentationFailed:
            return "The system print sheet could not be opened."
        }
    }
}
