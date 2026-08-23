// SingleInstanceGuard — the bb pattern: launching a second copy brings the
// running instance forward instead of spawning a second server. Checked
// before NSApplication starts, so the duplicate process exits silently.

import AppKit

enum SingleInstanceGuard {

    /// Activate an already-running instance (if any) and exit; otherwise return
    /// and let bootstrap continue. A bare binary has no bundle identifier, so
    /// dev runs never match and always proceed.
    static func activateExistingAndExit(
        bundleIdentifier: String,
        current: NSRunningApplication = .current
    ) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0 != current }
        guard let existing = others.first else { return }
        existing.activate(options: [.activateAllWindows])
        exit(0)
    }
}
