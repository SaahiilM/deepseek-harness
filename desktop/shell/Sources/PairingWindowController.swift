// PairingWindowController — shows the QR a phone scans to pair.
//
// The QR encodes `http://<lan-ip>:<gatePort>/pair/<one-time-code>`; opening
// it in the phone's browser exchanges the code for the pairing cookie and
// lands on the harness web UI. Also shows the URL as text with a copy
// button, because typing a URL beats scanning when the phone is the one
// holding the camera.

import AppKit
import CoreImage

final class PairingWindowController: NSWindowController, NSWindowDelegate {

    private let pairingURL: URL

    init(pairingURL: URL) {
        self.pairingURL = pairingURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Pair Mobile Device"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window, pairingURL: pairingURL)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("pairing window is built in code") }

    private func buildContent(in window: NSWindow, pairingURL: URL) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let qrImageView = NSImageView(image: Self.qrImage(for: pairingURL) ?? NSImage())
        qrImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            qrImageView.widthAnchor.constraint(equalToConstant: 280),
            qrImageView.heightAnchor.constraint(equalToConstant: 280),
        ])

        let caption = NSTextField(labelWithString: "Scan with your phone's camera.\nMust be on the same Wi-Fi network.")
        caption.alignment = .center
        caption.font = .systemFont(ofSize: 13)

        let urlField = NSTextField(labelWithString: pairingURL.absoluteString)
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let copyButton = NSButton(title: "Copy link", target: self, action: #selector(copyLink(_:)))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = .command

        stack.addArrangedSubview(qrImageView)
        stack.addArrangedSubview(caption)
        stack.addArrangedSubview(urlField)
        stack.addArrangedSubview(copyButton)
        window.contentView?.addSubview(stack)

        guard let contentView = window.contentView else { return }
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @objc private func copyLink(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingURL.absoluteString, forType: .string)
    }

    // MARK: - QR rendering

    /// Render a URL as a black-on-white QR image via CoreImage.
    static func qrImage(for url: URL) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        let scale: CGFloat = 10
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
