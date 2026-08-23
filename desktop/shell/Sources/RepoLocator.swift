// RepoLocator — resolves the DeepSeek Harness checkout backing this app.
//
// Resolution order (first valid wins):
//   1. `DSH_DESKTOP_REPO` environment variable
//   2. `DSHDesktopRepoPath` user default
//   3. walking up from the executable until the CLI marker file appears
//   4. the embedded snapshot in Contents/Resources/runtime (see EmbeddedRuntime)
//
// A directory qualifies only when it contains the marker path, so a stale
// stored location fails loudly through the normal startup-failure page rather
// than spawning node in an unusable working directory.

import Foundation

/// The slice of UserDefaults the locator reads; injectable so tests can pass
/// an in-memory implementation.
protocol DefaultsReading {
    func string(forKey key: String) -> String?
}

extension UserDefaults: DefaultsReading {}

enum RepoLocator {

    /// Repository-relative file whose presence identifies the checkout root.
    static let markerPath = "apps/cli/src/bin.ts"

    /// UserDefaults key holding an explicit checkout path.
    static let userDefaultsKey = "DSHDesktopRepoPath"

    /// Environment variable holding an explicit checkout path.
    static let environmentKey = "DSH_DESKTOP_REPO"

    /// Resolve the repository root, or nil when none qualifies.
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: DefaultsReading = UserDefaults.standard,
        executablePath: String = CommandLine.arguments.first ?? "",
        embeddedPath: String? = EmbeddedRuntime.locate(),
        isValidRepo: (String) -> Bool = { RepoLocator.isValidRepo($0) }
    ) -> String? {
        if let pinned = environment[environmentKey], isValidRepo(pinned) {
            return pinned
        }
        if let stored = defaults.string(forKey: userDefaultsKey), isValidRepo(stored) {
            return stored
        }
        // Walk-up's per-directory probe is exactly "is this dir a valid repo".
        if let walked = locateByWalkingUp(fromPath: executablePath,
                                          isRepo: isValidRepo) {
            return walked
        }
        if let embedded = embeddedPath, isValidRepo(embedded) {
            return embedded
        }
        return nil
    }

    /// True when `path` contains the marker file.
    static func isValidRepo(_ path: String, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        fileExists(path + "/" + markerPath)
    }

    /// Walk up from `fromPath` (typically argv[0]) looking for a valid repo
    /// root, bounded at ten levels so a misplaced binary fails fast.
    static func locateByWalkingUp(
        fromPath: String,
        isRepo: (String) -> Bool = { RepoLocator.isValidRepo($0) }
    ) -> String? {
        var url = URL(fileURLWithPath: fromPath).deletingLastPathComponent()
        for _ in 0..<10 {
            if isRepo(url.path) { return url.path }
            if url.path == "/" { return nil }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
