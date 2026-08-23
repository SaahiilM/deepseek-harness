// AppDelegate — composition root and server-state router.
//
// Wires the collaborators together and routes each ServerState to the parts
// that care: WindowManager (lifecycle pages), SessionMonitor (presence),
// and user attention. All real behavior lives in the collaborating modules.
// Entry point: AppMain.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, MenuActions {

    static let bundleIdentifier = "ai.deepseek.harness.desktop"

    private let windows = WindowManager()
    private lazy var sessionMonitor = SessionMonitor(
        presence: SystemPresenceReporter(),
        isFrontmost: { NSApp.isActive })
    private let server = ServerController()

    /// Set once the server reports a ready URL; drives New Window and
    /// Open-in-Browser.
    private var appURL: URL?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        AppMenuBuilder.install(into: self)

        makeWindow().showWindow(nil)

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
            if windows.isEmpty {
                makeWindow().showWindow(nil)
            } else {
                windows.keyOrFirst?.showWindow(nil)
            }
        }
        // false: we fully handled the reopen.
        return true
    }

    // MARK: - Server-state routing

    private func handle(_ state: ServerState) {
        switch state {
        case .idle:
            break
        case .starting:
            windows.lifecycleFollowers.forEach { $0.showStartingPage() }
        case .running(let url):
            appURL = url
            sessionMonitor.start(baseURL: url)
            windows.lifecycleFollowers.forEach { $0.loadApp(url) }
        case .failed(let reason, let logTail):
            sessionMonitor.stop()
            NSApp.requestUserAttention(.criticalRequest)
            windows.lifecycleFollowers.forEach { $0.showErrorPage(reason: reason, logTail: logTail) }
        case .exited(let status, let logTail):
            sessionMonitor.stop()
            appURL = nil
            windows.lifecycleFollowers.forEach { $0.showErrorPage(
                reason: "The harness server exited (status \(status)).",
                logTail: logTail) }
        }
    }

    // MARK: - Window management

    private func makeWindow() -> WindowController {
        windows.makeWindow(appURL: appURL)
    }

    // MARK: - Menu actions (selectors declared in MenuActions)

    @objc func newWindow(_ sender: Any?) {
        makeWindow().showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func reloadPage(_ sender: Any?) {
        windows.keyOrFirst?.reloadPage()
    }

    @objc func zoomIn(_ sender: Any?) { windows.keyOrFirst?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { windows.keyOrFirst?.zoomOut() }
    @objc func resetZoom(_ sender: Any?) { windows.keyOrFirst?.resetZoom() }

    @objc func openInBrowser(_ sender: Any?) {
        guard let url = appURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func revealServerLog(_ sender: Any?) {
        let path = server.logFilePath
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        NSWorkspace.shared.selectFile(path,
                                      inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }

    @objc func copyServerURL(_ sender: Any?) {
        guard let url = appURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc func restartServer(_ sender: Any?) {
        appURL = nil
        windows.forEach { $0.showStartingPage() }
        server.start()
    }
}
