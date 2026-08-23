// LifecyclePages — HTML for the states before (or instead of) the app UI.
// Pure functions of their arguments: the same inputs always render the same
// page, which is what the tests assert.

import Foundation

enum LifecyclePages {

    static func starting() -> String {
        page(title: "Starting DeepSeek Harness…",
             body: """
             <div class="spinner"></div>
             <p>Booting the local agent server.</p>
             <p class="dim">First launch after a build can take a little while.</p>
             """)
    }

    static func error(reason: String, logTail: [String]) -> String {
        let escapedLog = logTail.suffix(60)
            .map(escapeHTML)
            .joined(separator: "\n")
        return page(title: "DeepSeek Harness could not start",
                    body: """
                    <p class="error">✕</p>
                    <p><strong>\(escapeHTML(reason))</strong></p>
                    <pre>\(escapedLog)</pre>
                    <p class="dim">Quit and reopen the app to retry. The full server log lives in
                    ~/Library/Application Support/DeepSeek Harness/server.log</p>
                    """)
    }

    private static func escapeHTML(_ text: String) -> String {
        // Ampersand first: escaping it after < would double-encode entities.
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func page(title: String, body: String) -> String {
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
}
