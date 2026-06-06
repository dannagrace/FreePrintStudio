import UIKit

enum SharePresenter {
    @MainActor
    static func present(items: [Any]) {
        guard let presenter = UIApplication.shared.topMostViewController else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY,
                width: 1,
                height: 1
            )
        }

        presenter.present(controller, animated: true)
    }
}

private extension UIApplication {
    @MainActor
    var topMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMost
    }
}

private extension UIViewController {
    @MainActor
    var topMost: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMost
        }
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMost ?? navigationController
        }
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMost ?? tabBarController
        }
        return self
    }
}
