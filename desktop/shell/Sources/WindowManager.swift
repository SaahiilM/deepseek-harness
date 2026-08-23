// WindowManager — the collection of open windows and their shared lifecycle.
//
// Owns creation, close bookkeeping, and lifecycle-page fan-out. A window
// still on a starting/error page follows server transitions; a window
// already showing the app UI is never reloaded behind the user's back.

import AppKit

final class WindowManager {

    private(set) var windows: [WindowController] = []

    var keyOrFirst: WindowController? {
        windows.first { $0.window?.isKeyWindow == true } ?? windows.first
    }

    var isEmpty: Bool { windows.isEmpty }

    /// Create, register, and return a new window. It shows the starting page
    /// (or `appURL` when the server is already up) but does not make key.
    func makeWindow(appURL: URL?) -> WindowController {
        let controller = WindowController()
        if let appURL {
            controller.loadApp(appURL)
        } else {
            controller.showStartingPage()
        }
        let id = ObjectIdentifier(controller)
        controller.onClose = { [weak self] in
            self?.windows.removeAll { ObjectIdentifier($0) == id }
        }
        windows.append(controller)
        return controller
    }

    /// Windows still on a starting/error page, which should follow server
    /// lifecycle transitions.
    var lifecycleFollowers: [WindowController] {
        windows.filter(\.showingLifecyclePage)
    }

    func forEach(_ body: (WindowController) -> Void) {
        windows.forEach(body)
    }
}
