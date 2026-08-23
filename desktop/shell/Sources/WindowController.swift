// WindowController — one WKWebView window hosting the DSH Web GUI, plus
// placeholder and error pages for the server startup lifecycle.
//
// Patterns adopted from the reference products:
//   - persisted window frame across launches (bb's window-state.json, done
//     here with AppKit's native setFrameAutosaveName)
//   - browser-like zoom controls wired into the View menu
//   - navigation policy: loopback origins load inside the window; anything
//     else opens in the default browser

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
        window.titlebarAppearsTransparent = false
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

    /// True while the window shows a starting/error page rather than the app
    /// UI; such windows follow server lifecycle transitions.
    private(set) var showingLifecyclePage = true

    // MARK: - Navigation actions (menu targets)

    func reloadPage() {
        guard let url = webView.url else { return }
        webView.load(URLRequest(url: url))
    }

    func zoomIn() { webView.pageZoom = min(webView.pageZoom + 0.1, 3.0) }
    func zoomOut() { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    func resetZoom() { webView.pageZoom = 1.0 }

    // MARK: - Lifecycle pages

    func loadApp(_ url: URL) {
        showingLifecyclePage = false
        webView.load(URLRequest(url: url))
    }

    func showStartingPage() {
        showingLifecyclePage = true
        loadHTML(page(title: "Starting DeepSeek Harness…",
                      body: """
                      <div class="spinner"></div>
                      <p>Booting the local agent server.</p>
                      <p class="dim">First launch after a build can take a little while.</p>
                      """))
    }

    func showErrorPage(reason: String, logTail: [String]) {
        showingLifecyclePage = true
        let escapedLog = logTail.suffix(60)
            .map { $0.replacingOccurrences(of: "<", with: "&lt;") }
            .joined(separator: "\n")
        loadHTML(page(title: "DeepSeek Harness could not start",
                      body: """
                      <p class="error">✕</p>
                      <p><strong>\(reason)</strong></p>
                      <pre>\(escapedLog)</pre>
                      <p class="dim">Quit and reopen the app to retry. The full server log lives in
                      ~/Library/Application Support/DeepSeek Harness/server.log</p>
                      """))
    }

    private func loadHTML(_ html: String) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func page(title: String, body: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8"><title>\(title)</title><style>
          body { margin: 0; height: 100vh; display: flex; align-items: center; justify-content: center;
                 background: #0b1220; color: #e6edf3; font-family: -apple-system, sans-serif; }
          main { text-align: center; max-width: 640px; padding: 32px; }
          h1 { font-size: 20px; font-weight: 600; }
          p  { color: #9fb1c1; line-height: 1.5; }
          p.dim { font-size: 13px; color: #5c6f82; }
          p.error { color: #ff7b72; font-size: 28px; margin: 0; }
          pre { text-align: left; background: #0d1524; border: 1px solid #1d2b3f; border-radius: 8px;
                padding: 14px; max-height: 220px; overflow: auto; font-size: 11px; color: #8ba3b8;
                white-space: pre-wrap; }
          .spinner { width: 34px; height: 34px; margin: 0 auto 18px; border-radius: 50%;
                     border: 3px solid #22304a; border-top-color: #37b6f5;
                     animation: spin 0.9s linear infinite; }
          @keyframes spin { to { transform: rotate(360deg); } }
        </style></head><body><main><h1>\(title)</h1>\(body)</main></body></html>
        """
    }

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
