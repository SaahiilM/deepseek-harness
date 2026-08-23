// AppDelegate — wires the window to the server lifecycle and owns the menus.
//
// Entry point: `@main` synthesizes the AppKit bootstrap that installs this
// delegate and starts the run loop. All behavior lives here,
// WindowController, and ServerController.

import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Explicit bootstrap: `@main` alone does not install the delegate when the
    /// binary runs without a nib or principal-class wiring, so this installs
    /// the app, delegate, and run loop by hand.
    static func main() {
        let application = NSApplication.shared
        let delegate = Self()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    private let server = ServerController()
    private var windowController: WindowController?
    /// Set once the server reports a ready URL; drives Reload/Open-in-Browser.
    private var appURL: URL?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        buildMenus()

        let controller = WindowController()
        windowController = controller
        controller.showWindow(nil)
        controller.showStartingPage()

        server.onStateChange = { [weak self] state in
            self?.handle(state)
        }
        server.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.showWindow(nil) }
        return true
    }

    // MARK: - Server state

    private func handle(_ state: ServerState) {
        switch state {
        case .idle:
            break
        case .starting:
            windowController?.showStartingPage()
        case .running(let url):
            appURL = url
            NSApp.dockTile.badgeLabel = nil
            windowController?.loadApp(url)
        case .failed(let reason, let logTail):
            NSApp.requestUserAttention(.criticalRequest)
            windowController?.showErrorPage(reason: reason, logTail: logTail)
        case .exited(let status, let logTail):
            appURL = nil
            windowController?.showErrorPage(
                reason: "The harness server exited (status \(status)).",
                logTail: logTail)
        }
    }

    // MARK: - Actions

    @objc private func reload(_ sender: Any?) {
        windowController?.reload()
    }

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
        windowController?.showStartingPage()
        server.start()
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
        appMenu.addItem(withTitle: "Quit DeepSeek Harness",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

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

        // View menu — reload the webview like a browser would.
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(reload(_:)),
                         keyEquivalent: "r")

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
