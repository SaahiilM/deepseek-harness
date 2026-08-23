// AppDelegate — wires windows to the server lifecycle, owns the menus, and
// provides the native affordances the reference products (OpenAI Codex
// desktop, get-bb/bb, pingdotgg/t3code) all share:
//
//   - single instance: a second launch activates the running app (bb main.ts)
//   - multiple windows onto the same local server (bb File ▸ New Window)
//   - full Edit-menu roles so text fields work natively in the webview
//   - browser zoom controls in View (bb View menu)
//   - dock badge + finish notifications driven by live session state

import AppKit
import UserNotifications

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    static let bundleIdentifier = "ai.deepseek.harness.desktop"

    private let server = ServerController()
    private let sessionMonitor = SessionMonitor()
    private var windowControllers: [WindowController] = []
    /// Set once the server reports a ready URL; drives Reload/Open-in-Browser.
    private var appURL: URL?

    /// Explicit bootstrap: `@main` alone does not install the delegate when the
    /// binary runs without a nib or principal-class wiring, so this installs
    /// the app, delegate, and run loop by hand.
    static func main() {
        activateExistingInstanceIfAny()
        let application = NSApplication.shared
        let delegate = Self()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    /// bb's single-instance pattern: launching while an instance runs brings
    /// the existing one forward instead of spawning a second server.
    private static func activateExistingInstanceIfAny() {
        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0 != current }
        guard let other = others.first else { return }
        other.activate(options: [.activateAllWindows])
        exit(0)
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        buildMenus()

        let controller = makeWindowController()
        controller.showWindow(nil)

        server.onStateChange = { [weak self] state in
            self?.handle(state)
        }
        server.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionMonitor.stop()
        server.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let first = windowControllers.first {
                first.showWindow(nil)
            } else {
                let controller = makeWindowController()
                controller.showWindow(nil)
                if let url = appURL { controller.loadApp(url) }
            }
        }
        // false: we fully handled the reopen.
        return true
    }

    // MARK: - Windows

    private func makeWindowController() -> WindowController {
        let controller = WindowController()
        controller.showStartingPage()
        if let url = appURL {
            controller.loadApp(url)
        }
        controller.onClose = { [weak self, weak controller] in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(controller)
        return controller
    }

    // MARK: - Server state

    private func handle(_ state: ServerState) {
        switch state {
        case .idle:
            break
        case .starting:
            for controller in windowControllers where controller.showingLifecyclePage {
                controller.showStartingPage()
            }
        case .running(let url):
            appURL = url
            sessionMonitor.start(baseURL: url)
            for controller in windowControllers where controller.showingLifecyclePage {
                controller.loadApp(url)
            }
        case .failed(let reason, let logTail):
            sessionMonitor.stop()
            NSApp.requestUserAttention(.criticalRequest)
            for controller in windowControllers where controller.showingLifecyclePage {
                controller.showErrorPage(reason: reason, logTail: logTail)
            }
        case .exited(let status, let logTail):
            sessionMonitor.stop()
            appURL = nil
            for controller in windowControllers where controller.showingLifecyclePage {
                controller.showErrorPage(
                    reason: "The harness server exited (status \(status)).",
                    logTail: logTail)
            }
        }
    }

    // MARK: - Actions

    @objc private func newWindow(_ sender: Any?) {
        let controller = makeWindowController()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reloadPage(_ sender: Any?) {
        keyWindowController()?.reloadPage()
    }

    @objc private func zoomIn(_ sender: Any?) { keyWindowController()?.zoomIn() }
    @objc private func zoomOut(_ sender: Any?) { keyWindowController()?.zoomOut() }
    @objc private func resetZoom(_ sender: Any?) { keyWindowController()?.resetZoom() }

    @objc private func openInBrowser(_ sender: Any?) {
        guard let url = appURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealServerLog(_ sender: Any?) {
        let path = server.logFilePath
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }

    @objc private func copyServerURL(_ sender: Any?) {
        guard let url = appURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func restartServer(_ sender: Any?) {
        appURL = nil
        for controller in windowControllers {
            controller.showStartingPage()
        }
        server.start()
    }

    private func keyWindowController() -> WindowController? {
        windowControllers.first { $0.window?.isKeyWindow == true } ?? windowControllers.first
    }

    // MARK: - Menus

    private func buildMenus() {
        let mainMenu = NSMenu()

        // App menu.
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About DeepSeek Harness",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DeepSeek Harness",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DeepSeek Harness",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu — New Window / Close Window (bb pattern).
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)),
                         keyEquivalent: "n")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")

        // Edit menu — without these roles, undo/copy/paste do not work in a
        // WKWebView (every reference product ships them).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu — reload + zoom (bb pattern).
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(reloadPage(_:)),
                         keyEquivalent: "r")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)),
                         keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)),
                         keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(resetZoom(_:)),
                         keyEquivalent: "0")

        // Server menu — lifecycle affordances for the local agent process.
        let serverItem = NSMenuItem()
        mainMenu.addItem(serverItem)
        let serverMenu = NSMenu(title: "Server")
        serverItem.submenu = serverMenu
        serverMenu.addItem(withTitle: "Restart Server", action: #selector(restartServer(_:)),
                           keyEquivalent: "r").keyEquivalentModifierMask = [.command, .shift]
        serverMenu.addItem(withTitle: "Open in Browser", action: #selector(openInBrowser(_:)),
                           keyEquivalent: "b").keyEquivalentModifierMask = [.command, .control]
        serverMenu.addItem(withTitle: "Copy Server URL", action: #selector(copyServerURL(_:)),
                           keyEquivalent: "u").keyEquivalentModifierMask = [.command, .control]
        serverMenu.addItem(.separator())
        serverMenu.addItem(withTitle: "Reveal Server Log", action: #selector(revealServerLog(_:)),
                           keyEquivalent: "")

        // Window menu.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }
}
