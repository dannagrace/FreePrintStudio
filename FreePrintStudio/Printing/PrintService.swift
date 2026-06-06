import UIKit

enum PrintService {
    @MainActor
    static func printPDF(_ url: URL) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo
        info.jobName = "FreePrint Studio"
        controller.printInfo = info
        controller.printingItem = url
        controller.present(animated: true)
    }
}
