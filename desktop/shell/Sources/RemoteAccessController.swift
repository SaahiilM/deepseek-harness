// RemoteAccessController — runs the token-gated LAN front door.
//
// When enabled, spawns desktop/gate/gate.mjs with a freshly generated pair
// secret and one-time code, targeting whatever harness server the shell is
// currently attached to. The phone scans a QR of
// `http://<lan-ip>:<gatePort>/pair/<code>`; presenting the code once yields a
// year-long HttpOnly cookie. Disabling or quitting kills the gate; the LAN
// listener is strictly opt-in per app launch.

import Foundation

final class RemoteAccessController: NSObject, @unchecked Sendable {

    static let defaultGatePort = 52390

    private var process: Process?
    private let queue = DispatchQueue(label: "dsh-desktop.remote-access")

    private(set) var pairingURL: URL?
    private(set) var isEnabled = false

    /// Invoked on the main queue when the pairing URL appears or disappears.
    var onPairingURLChange: ((URL?) -> Void)?

    // MARK: - Secret material

    /// Random hex string of `byteCount` bytes. Pure enough to test for shape.
    static func randomHex(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The QR target for one-time pairing against this gate instance.
    static func pairingCodeURL(lanAddress: String, gatePort: Int, code: String) -> URL? {
        URL(string: "http://\(lanAddress):\(gatePort)/pair/\(code)")
    }

    // MARK: - Lifecycle

    /// Start (or restart against a new upstream) the gate. `repoRoot` supplies
    /// node and the gate script path; `upstreamPort` is the harness server's.
    func enable(repoRoot: String, upstreamPort: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopSync()
            guard let node = NodeLocator.locate(
                environment: ProcessInfo.processInfo.environment,
                repoRoot: repoRoot) else {
                NSLog("dsh-desktop remote-access: no node found, cannot start gate")
                return
            }

            let secret = Self.randomHex(byteCount: 24)
            let code = Self.randomHex(byteCount: 4)
            let gatePort = FreePortPicker.pickFreePort(defaultPort: Self.defaultGatePort)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: node)
            proc.arguments = [repoRoot + "/desktop/gate/gate.mjs"]
            proc.environment = [
                "GATE_PORT": String(gatePort),
                "GATE_BIND": "0.0.0.0",
                "UPSTREAM_PORT": String(upstreamPort),
                "PAIR_SECRET": secret,
                "PAIR_CODE": code,
            ]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            do {
                try proc.run()
            } catch {
                NSLog("dsh-desktop remote-access: gate failed to start: %@", error.localizedDescription)
                return
            }
            self.process = proc

            if let lan = LanAddress.primaryAddress(),
               let url = Self.pairingCodeURL(lanAddress: lan, gatePort: gatePort, code: code) {
                DispatchQueue.main.async {
                    self.pairingURL = url
                    self.isEnabled = true
                    self.onPairingURLChange?(url)
                }
                NSLog("dsh-desktop remote-access: gate on port %d (pairing available)", gatePort)
            } else {
                NSLog("dsh-desktop remote-access: no LAN address found; phone cannot reach this machine")
            }
        }
    }

    func disable() {
        queue.async { [weak self] in self?.stopSync() }
    }

    private func stopSync() {
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
        if isEnabled || pairingURL != nil {
            DispatchQueue.main.async {
                self.pairingURL = nil
                self.isEnabled = false
                self.onPairingURLChange?(nil)
            }
        }
    }
}
