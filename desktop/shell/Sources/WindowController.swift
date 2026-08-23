// WindowController — one WKWebView window hosting the DSH Web GUI.
//
// Owns only this window's concerns: webview navigation policy (loopback in,
// external links out), lifecycle page display, zoom, and frame persistence.
// Window collection management lives in WindowManager; server state routing
// in AppDelegate.

import AppKit
import WebKit

final class WindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {

    private var webView: WKWebView!
    /// Invoked when the user closes this window so the owner can forget it.
    var onClose: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "DeepSeek Harness"
        window.minSize = NSSize(width: 720, height: 480)
        window.tabbingMode = .disallowed

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let web = WKWebView(frame: .zero, configuration: config)
        web.autoresizingMask = [.width, .height]
        window.contentView = web

        self.init(window: window)
        webView = web
        webView.navigationDelegate = self
        window.delegate = self
        // Restore last session's frame (bb pattern, AppKit-native form).
        window.setFrameAutosaveName("MainWindow")
        window.center()
    }

    deinit {
        window?.delegate = nil
    }

    /// True while the window shows a starting/error page rather than the app
    /// UI; such windows follow server lifecycle transitions.
    private(set) var showingLifecyclePage = true

    // MARK: - Display

    func loadApp(_ url: URL) {
        showingLifecyclePage = false
        webView.load(URLRequest(url: url))
    }

    func showStartingPage() {
        showingLifecyclePage = true
        webView.loadHTMLString(LifecyclePages.starting(), baseURL: nil)
    }

    func showErrorPage(reason: String, logTail: [String]) {
        showingLifecyclePage = true
        webView.loadHTMLString(LifecyclePages.error(reason: reason, logTail: logTail),
                               baseURL: nil)
    }

    // MARK: - Navigation actions (menu targets)

    func reloadPage() {
        guard let url = webView.url else { return }
        webView.load(URLRequest(url: url))
    }

    func zoomIn() { webView.pageZoom = min(webView.pageZoom + 0.1, 3.0) }
    func zoomOut() { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    func resetZoom() { webView.pageZoom = 1.0 }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let host = url.host?.lowercased(),
              host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]" else {
            // Non-loopback target: hand it to the default browser instead of
            // loading it inside the app shell.
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        // A failed app-page load usually means the server just died.
        let message = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? "load failed"
        showErrorPage(reason: "The UI failed to load: \(message)", logTail: [])
    }
}
