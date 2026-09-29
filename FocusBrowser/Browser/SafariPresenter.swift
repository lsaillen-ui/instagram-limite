import SafariServices
import UIKit

/// Presents `SFSafariViewController` with UIKit, from the top-most view controller.
/// Apple requires it to be presented modally, not embedded in a SwiftUI container.
@MainActor
enum SafariPresenter {
    private static weak var current: SFSafariViewController?

    static func present(_ url: URL) {
        guard url.scheme == "http" || url.scheme == "https" else { return }  // SFSafariViewController throws otherwise.
        // One at a time: a redirect chain or double tap must not stack presentations.
        if let current, current.presentingViewController != nil || current.isBeingPresented { return }
        guard let top = topViewController(), !top.isBeingPresented, !top.isBeingDismissed else { return }

        let controller = SFSafariViewController(url: url)
        current = controller
        top.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
