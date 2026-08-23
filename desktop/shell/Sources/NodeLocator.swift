// NodeLocator — finds a Node binary able to run the harness source launch.
//
// The harness engines range is ^22.19 || >=24. A binary merely present on
// disk proves nothing (machines routinely carry stale `/usr/local/bin/node`
// installs), so every candidate is validated either by parsing its version
// directory name (nvm) or by executing `--version`.
//
// Order: DSH_DESKTOP_NODE, newest qualifying nvm install, common locations,
// then the user's login-shell PATH.

import Foundation

enum NodeLocator {

    /// Environment variable pinning an exact node binary.
    static let environmentKey = "DSH_DESKTOP_NODE"

    /// Locate a usable node binary, or nil when none qualifies.
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        repoRoot: String? = nil
    ) -> String? {
        let fm = FileManager.default
        if let pinned = environment[environmentKey],
           fm.isExecutableFile(atPath: pinned), isSupportedNode(at: pinned) {
            return pinned
        }
        // A node shipped with the resolved checkout (the standalone bundle's
        // .node-bin/node) outranks whatever the machine happens to have — the
        // snapshot was validated against that exact binary.
        if let repoRoot,
           let bundled = repoLocalNodePath(repoRoot: repoRoot, isExecutableFile: { fm.isExecutableFile(atPath: $0) }),
           isSupportedNode(at: bundled) {
            return bundled
        }

        var candidates = nvmCandidates(homeDirectory: homeDirectory)
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/node",
            "/opt/homebrew/opt/node/bin/node",
            "/usr/local/opt/node/bin/node",
            "/usr/local/bin/node",
            homeDirectory + "/.volta/bin/node",
        ])
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) && isSupportedNode(at: $0) }) {
            return found
        }

        guard let path = loginShellPath() else { return nil }
        for dir in path.split(separator: ":").map(String.init) {
            let candidate = dir + "/node"
            if fm.isExecutableFile(atPath: candidate), isSupportedNode(at: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// nvm keeps one directory per version; return the supported ones newest
    /// first as full binary paths.
    /// Path of a repo-local node binary, or nil when absent. Pure so tests
    /// can inject the file-existence check.
    static func repoLocalNodePath(
        repoRoot: String,
        isExecutableFile: (String) -> Bool = { _ in false }
    ) -> String? {
        let path = repoRoot + "/" + EmbeddedRuntime.nodePathInRepo
        return isExecutableFile(path) ? path : nil
    }

    static func nvmCandidates(homeDirectory: String) -> [String] {
        let versionsRoot = homeDirectory + "/.nvm/versions/node"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: versionsRoot) else {
            return []
        }
        return entries
            .compactMap(parseVersionDirectoryName)
            .filter { Self.isSupported(major: $0.major, minor: $0.minor) }
            .sorted { ($0.major, $0.minor, $0.patch) > ($1.major, $1.minor, $1.patch) }
            .map { "\(versionsRoot)/v\($0.major).\($0.minor).\($0.patch)/bin/node" }
    }

    /// "v22.19.0" -> (22, 19, 0); nil when the entry is not a version directory.
    static func parseVersionDirectoryName(_ entry: String) -> (major: Int, minor: Int, patch: Int)? {
        let parts = entry.dropFirst().split(separator: ".")
        guard entry.hasPrefix("v"), parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else { return nil }
        return (major, minor, patch)
    }

    /// Harness engines range: ^22.19 || >=24.
    static func isSupported(major: Int, minor: Int) -> Bool {
        (major == 22 && minor >= 19) || major >= 24
    }

    /// Parse a `vMAJOR.MINOR.PATCH` version string against the engines range.
    static func isSupportedVersionString(_ version: String) -> Bool {
        let parts = version.dropFirst().split(separator: ".").compactMap { Int($0) }
        guard version.hasPrefix("v"), parts.count >= 2 else { return false }
        return isSupported(major: parts[0], minor: parts[1])
    }

    /// Run `node --version` at `path` and validate the reported version.
    static func isSupportedNode(at path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]
        let stdout = Pipe()
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return false }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let version = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return false }
        return isSupportedVersionString(version)
    }

    /// PATH as the user's login shell computes it (GUI apps get launchd's
    /// minimal one).
    static func loginShellPath(shell: String = "/bin/zsh") -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", "printf '%s' \"$PATH\""]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8), !path.isEmpty else { return nil }
        return path
    }
}
