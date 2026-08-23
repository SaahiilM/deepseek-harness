// TailscaleStatus — detects the machine's Tailscale client state.
//
// The mobile-pairing flow treats Tailscale as the preferred transport: it
// authenticates the network itself, works away from home, and MagicDNS names
// stay stable across address changes. This module locates the CLI, reads
// `status --json`, and reduces it to what the setup flow branches on. The
// JSON parse is lenient: any structural surprise degrades to .unknown rather
// than misreporting readiness.

import Foundation

struct TailscaleStatus: Equatable {
    /// Lifecycle states the setup flow distinguishes.
    enum Phase: Equatable {
        case notInstalled
        case installed          // binary exists, backend stopped or absent
        case needsLogin         // backend up, account not authenticated
        case running            // connected to a tailnet
    }

    let phase: Phase
    /// Tailnet IPv4 (100.x.y.z) when running.
    let ipv4: String?
    /// MagicDNS name without trailing dot (e.g. mac.tail1234.ts.net).
    let dnsName: String?

    var isRunning: Bool { phase == .running }
    /// Preferred pairing host: MagicDNS name beats the raw IP.
    var pairingHost: String? { isRunning ? (dnsName ?? ipv4) : nil }
}

enum TailscaleLocator {

    /// Filesystem locations of the CLI, most standard first. The App Store
    /// and standalone builds both ship the binary inside the app bundle;
    /// brew installs symlink it into a bin directory.
    static let candidatePaths = [
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "\(NSHomeDirectory())/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

    static func locateBinary(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        candidatePaths.first(where: fileExists)
    }
}

enum TailscaleProbe {

    static let statusTimeout: TimeInterval = 5

    /// Synchronous probe; safe on a background queue only.
    static func check(binaryPath: String? = TailscaleLocator.locateBinary(),
                      runProcess: (String, [String]) -> (Int32, Data)? = Self.runProcess) -> TailscaleStatus {
        guard let binaryPath else { return TailscaleStatus(phase: .notInstalled, ipv4: nil, dnsName: nil) }
        guard let (exitCode, output) = runProcess(binaryPath, ["status", "--json"]) else {
            return TailscaleStatus(phase: .installed, ipv4: nil, dnsName: nil)
        }
        // `tailscale status` exits nonzero when logged out; the JSON body
        // still names the backend state, so parse before judging the code.
        return parse(exitCode: exitCode, data: output)
    }

    /// Reduce `status --json` output to a TailscaleStatus. Pure; unit-tested
    /// against captured shapes.
    static func parse(exitCode: Int32, data: Data) -> TailscaleStatus {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return TailscaleStatus(phase: exitCode == 0 ? .installed : .needsLogin, ipv4: nil, dnsName: nil)
        }
        let backend = (json["BackendState"] as? String) ?? ""
        let selfDict = json["Self"] as? [String: Any]
        let ips = (selfDict?["TailscaleIPs"] as? [Any])?.compactMap { $0 as? String } ?? []
        let rawName = selfDict?["DNSName"] as? String

        switch backend {
        case "Running":
            return TailscaleStatus(phase: .running,
                                   ipv4: ips.first,
                                   dnsName: rawName.flatMap { $0.hasSuffix(".") ? String($0.dropLast()) : $0 })
        case "NeedsLogin":
            return TailscaleStatus(phase: .needsLogin, ipv4: nil, dnsName: nil)
        default:
            return TailscaleStatus(phase: .installed, ipv4: nil, dnsName: nil)
        }
    }

    private static func runProcess(_ path: String, _ arguments: [String]) -> (Int32, Data)? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return (proc.terminationStatus, data)
    }
}
