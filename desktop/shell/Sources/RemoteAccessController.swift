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

    /// Where the gate listens and what the pairing URL advertises.
    enum Transport: Equatable {
        /// All interfaces; pairing URL uses the primary LAN address (plain
        /// HTTP — browsers there lack secure-context APIs).
        case lan
        /// Gate bound to loopback only; `tailscale serve` fronts it with a
        /// real TLS certificate on the MagicDNS name (secure context).
        case tailnetServe(dnsName: String)
    }

    /// Filesystem name of the tailscale CLI used for `serve` management.
    private var tailscaleBinaryPath: String?

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
    static func pairingCodeURL(scheme: String = "http", lanAddress: String, gatePort: Int, code: String) -> URL? {
        if gatePort == 443 {
            return URL(string: "\(scheme)://\(lanAddress)/pair/\(code)")
        }
        return URL(string: "\(scheme)://\(lanAddress):\(gatePort)/pair/\(code)")
    }

    // MARK: - Lifecycle

    /// Start (or restart against a new upstream) the gate. `repoRoot` supplies
    /// node and the gate script path; `upstreamPort` is the harness server's.
    func enable(repoRoot: String, upstreamPort: Int, transport: Transport = .lan) {
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

            // Tailnet mode: the gate listens on loopback only and
            // `tailscale serve` fronts it with real TLS on the MagicDNS
            // name — a secure context, which phone browsers require for
            // APIs like crypto.randomUUID.
            var bindAddress = "0.0.0.0"
            var advertisedHost: String?
            var pairingScheme = "http"
            if case .tailnetServe(let dnsName) = transport {
                guard let tsBinary = TailscaleLocator.locateBinary() else {
                    NSLog("dsh-desktop remote-access: tailscale binary vanished; falling back to LAN bind")
                    return self.finishEnableLan(node: node, repoRoot: repoRoot, upstreamPort: upstreamPort)
                }
                tailscaleBinaryPath = tsBinary
                bindAddress = "127.0.0.1"
                advertisedHost = dnsName
                pairingScheme = "https"
                _ = node // gate spawn below shares this binary choice
            }
            if advertisedHost == nil {
                advertisedHost = LanAddress.primaryAddress()
            }
            guard let advertisedHost else {
                NSLog("dsh-desktop remote-access: no reachable address found for pairing")
                return
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: node)
            proc.arguments = [repoRoot + "/desktop/gate/gate.mjs"]
            proc.environment = [
                "GATE_PORT": String(gatePort),
                "GATE_BIND": bindAddress,
                "UPSTREAM_PORT": String(upstreamPort),
                "PAIR_SECRET": secret,
                "PAIR_CODE": code,
            ]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            // Drain both channels into the system log: the gate is where
            // phone-visible failures surface first (401s, upstream errors),
            // and an undrained pipe would silently truncate at 64 KiB.
            [pipe.fileHandleForReading].forEach { handle in
                handle.readabilityHandler = { fileHandle in
                    let data = fileHandle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    for line in text.split(separator: "\n") where !line.isEmpty {
                        NSLog("dsh-desktop gate: %@", String(line))
                    }
                }
            }

            do {
                try proc.run()
            } catch {
                NSLog("dsh-desktop remote-access: gate failed to start: %@", error.localizedDescription)
                return
            }
            self.process = proc

            if case .tailnetServe = transport {
                if self.configureTailscaleServe(gatePort: gatePort) {
                    NSLog("dsh-desktop remote-access: tailscale serve active on 443")
                } else {
                    // Serve unavailable (HTTPS certs disabled on the tailnet,
                    // CLI trouble…): tear the loopback gate down and use the
                    // plain-LAN transport instead. The injected randomUUID
                    // polyfill keeps the UI functional over plain http.
                    NSLog("dsh-desktop remote-access: tailscale serve unavailable; falling back to LAN")
                    self.stopSync()
                    self.enable(repoRoot: repoRoot, upstreamPort: upstreamPort, transport: .lan)
                    return
                }
            }

            if let url = Self.pairingCodeURL(scheme: pairingScheme, lanAddress: advertisedHost,
                                             gatePort: pairingScheme == "https" ? 443 : gatePort,
                                             code: code) {
                DispatchQueue.main.async {
                    self.pairingURL = url
                    self.isEnabled = true
                    self.onPairingURLChange?(url)
                }
                NSLog("dsh-desktop remote-access: gate on %@:%d (pairing available)", bindAddress, gatePort)
            } else {
                NSLog("dsh-desktop remote-access: could not build pairing URL")
            }
        }
    }

    /// LAN fallback used when tailnet mode cannot find its prerequisites.
    private func finishEnableLan(node: String, repoRoot: String, upstreamPort: Int) {
        enable(repoRoot: repoRoot, upstreamPort: upstreamPort, transport: .lan)
    }

    /// Point `tailscale serve` at the gate so https://<magicdns>/ routes to
    /// it on the tailnet with a valid certificate. Reset first so stale
    /// entries from earlier runs can never answer on 443. Returns false when
    /// the tailnet lacks HTTPS certificates or the CLI misbehaves — the
    /// caller falls back to the LAN transport.
    private func configureTailscaleServe(gatePort: Int) -> Bool {
        guard let tsBinary = tailscaleBinaryPath else { return false }
        runTailscale([tsBinary, "serve", "reset"], timeout: 5)
        guard let output = runTailscale([tsBinary, "serve", "--bg", "http://127.0.0.1:\(gatePort)"], timeout: 8),
              let text = String(data: output, encoding: .utf8)?.lowercased() else {
            NSLog("dsh-desktop remote-access: tailscale serve did not complete")
            return false
        }
        if text.contains("not enabled") || text.contains("https") == false && text.contains("serve") && text.contains("enable") {
            NSLog("dsh-desktop remote-access: tailnet HTTPS certificates are not enabled")
            return false
        }
        return true
    }

    /// Run a tailscale CLI command, killing it if it hangs (a foreground
    /// `serve` or an unparseable flag must never wedge this queue).
    @discardableResult
    private func runTailscale(_ arguments: [String], timeout: TimeInterval = 8) -> Data? {
        guard let first = arguments.first else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: first)
        proc.arguments = Array(arguments.dropFirst())
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = Pipe()
        do { try proc.run() } catch {
            NSLog("dsh-desktop remote-access: tailscale command failed: %@", arguments.joined(separator: " "))
            return nil
        }
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            NSLog("dsh-desktop remote-access: tailscale timed out: %@", arguments[1...].joined(separator: " "))
            proc.terminate()
        }
        proc.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus != 0, let text = String(data: data, encoding: .utf8), !text.isEmpty {
            NSLog("dsh-desktop remote-access: tailscale %@ said: %@", arguments[1...].joined(separator: " "), text)
        }
        return data
    }

    /// Clear the serve entry when the user explicitly disables remote
    /// access; app quit leaves it (next launch re-points it).
    func resetTailscaleServe() {
        queue.async { [weak self] in
            if let path = self?.tailscaleBinaryPath {
                self?.runTailscale([path, "serve", "reset"], timeout: 5)
            }
        }
    }

    func disable() {
        queue.async { [weak self] in self?.stopSync() }
    }

    /// Synchronous teardown for applicationWillTerminate: an async dispatch
    /// there races process exit and leaks the gate process.
    func disableNow() {
        queue.sync { stopSync() }
        if let tsBinary = tailscaleBinaryPath {
            runTailscale([tsBinary, "serve", "reset"])
        }
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
