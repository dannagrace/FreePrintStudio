import UIKit

enum PrintService {
    @MainActor private static var activePaperDelegate: PreferredPaperDelegate?

    @MainActor
    @discardableResult
    static func printPDF(
        _ url: URL,
        paperSize: PrintSize,
        completion: @escaping (Result<Void, Error>) -> Void
    ) -> Bool {
        guard UIPrintInteractionController.canPrint(url) else {
            completion(.failure(PrintServiceError.unsupportedPDF))
            return false
        }

        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "FreePrint Studio"
        info.orientation = paperSize.widthPoints > paperSize.heightPoints ? .landscape : .portrait
        controller.printInfo = info
        let paperDelegate = PreferredPaperDelegate(pageSize: CGSize(
            width: paperSize.widthPoints,
            height: paperSize.heightPoints
        ))
        activePaperDelegate = paperDelegate
        controller.delegate = paperDelegate
        controller.showsPaperSelectionForLoadedPapers = true
        controller.printingItem = url
        let didPresent = controller.present(animated: true) { _, _, error in
            controller.delegate = nil
            activePaperDelegate = nil
            if let error {
                completion(.failure(error))
            }
        }
        if !didPresent {
            controller.delegate = nil
            activePaperDelegate = nil
            completion(.failure(PrintServiceError.presentationFailed))
        }
        return didPresent
    }
}

@MainActor
private final class PreferredPaperDelegate: NSObject, UIPrintInteractionControllerDelegate {
    private let pageSize: CGSize

    init(pageSize: CGSize) {
        self.pageSize = pageSize
    }

    func printInteractionController(
        _ printInteractionController: UIPrintInteractionController,
        choosePaper paperList: [UIPrintPaper]
    ) -> UIPrintPaper {
        UIPrintPaper.bestPaper(forPageSize: pageSize, withPapersFrom: paperList)
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
