// TailnetSetupWindowController — guides the user to a working Tailscale
// transport for mobile access.
//
// One window, three states, driven by a poll of `tailscale status`:
//   notInstalled → "Open Download Page" + step-by-step copy
//   needsLogin   → "Open Tailscale & Sign In" (launches the client)
//   running      → "Enable Mobile Access over Tailscale" (finishes setup)
// The footer always offers "Use plain Wi-Fi instead", which enables the LAN
// transport so nobody is stuck if they decline Tailscale.

import AppKit

final class TailnetSetupWindowController: NSWindowController, NSWindowDelegate {

    /// Called on the main queue once Tailscale is running and the user
    /// accepted enabling mobile access over it.
    var onTailnetReady: ((TailscaleStatus) -> Void)?
    /// Called when the user chooses plain Wi-Fi instead.
    var onUseLanInstead: (() -> Void)?

    private let probeQueue = DispatchQueue(label: "dsh-desktop.tailnet-probe")
    private var pollTimer: Timer?
    private var lastPhase: TailscaleStatus.Phase?

    private let stack = NSStackView()
    private let spinner = NSProgressIndicator()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Mobile Access Setup"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("setup window is built in code") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        stopPolling()
    }

    // MARK: - UI construction

    private func buildContent(in window: NSWindow) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)

        spinner.isIndeterminate = true
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let intro = NSTextField(labelWithString:
            "Tailscale gives your phone a secure, private connection to this Mac —")
        intro.font = .systemFont(ofSize: 13)
        let intro2 = NSTextField(labelWithString:
            "at home or away. It is free for personal use.")
        intro2.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(intro)
        stack.addArrangedSubview(intro2)
        stack.addArrangedSubview(spinner)

        guard let contentView = window.contentView else { return }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    // MARK: - State polling

    private func startPolling() {
        stopPolling()
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refresh() {
        probeQueue.async { [weak self] in
            let status = TailscaleProbe.check()
            DispatchQueue.main.async { [weak self] in
                self?.apply(status)
            }
        }
    }

    // MARK: - State application (main queue)

    private func apply(_ status: TailscaleStatus) {
        guard status.phase != lastPhase else { return }
        lastPhase = status.phase

        // Drop everything after the intro + spinner.
        while stack.arrangedSubviews.count > 3 {
            stack.arrangedSubviews.last?.removeFromSuperview()
        }

        switch status.phase {
        case .notInstalled:
            addHeading("Step 1 · Install Tailscale")
            addBody("1. Click “Download” below and install the app.\n" +
                    "2. Open Tailscale from your Applications folder.\n" +
                    "3. Sign in (a free personal account is enough).\n" +
                    "This window continues automatically once you are connected.")
            addButton("Open Download Page") { NSWorkspace.shared.open(URL(string: "https://tailscale.com/download/mac")!) }

        case .installed:
            addHeading("Step 1 · Start Tailscale")
            addBody("Tailscale is installed but not connected.\nOpen the app and sign in — this window\ncontinues automatically.")
            addButton("Open Tailscale") {
                if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "io.tailscale.ipn.macos") {
                    NSWorkspace.shared.open(appUrl)
                } else if let binary = TailscaleLocator.locateBinary() {
                    NSWorkspace.shared.open(URL(fileURLWithPath: (binary as NSString).deletingLastPathComponent))
                }
            }

        case .needsLogin:
            addHeading("Step 1 · Sign in to Tailscale")
            addBody("A browser window should open asking you to sign in.\nComplete it and this window continues automatically.")

        case .running:
            spinner.stopAnimation(nil)
            addHeading("✓ Tailscale is ready")
            addBody("This Mac is reachable as:\n" +
                    (status.dnsName ?? status.ipv4 ?? "?"))
            addButton("Enable Mobile Access over Tailscale", primary: true) { [weak self] in
                self?.stopPolling()
                if let self { self.onTailnetReady?(status) }
            }
        }

        // Escape hatch, always last.
        addButton("Use plain Wi-Fi instead (this network only)", small: true) { [weak self] in
            self?.stopPolling()
            self?.onUseLanInstead?()
        }
    }

    // MARK: - Small builders

    private func addHeading(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        stack.addArrangedSubview(label)
    }

    private func addBody(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.preferredMaxLayoutWidth = 400
        stack.addArrangedSubview(label)
    }

    private func addButton(_ title: String, primary: Bool = false, small: Bool = false,
                           action closure: @escaping () -> Void) {
        let button = NSButton(title: title, target: self, action: #selector(buttonFired(_:)))
        button.bezelStyle = primary ? .rounded : .rounded
        button.controlSize = small ? .small : .regular
        button.font = .systemFont(ofSize: small ? 11 : 13)
        button.tag = actions.count
        actions.append(closure)
        stack.addArrangedSubview(button)
    }

    private var actions: [() -> Void] = []

    @objc private func buttonFired(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}
