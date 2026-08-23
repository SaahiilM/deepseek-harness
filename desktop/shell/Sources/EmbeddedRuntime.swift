// EmbeddedRuntime — a self-contained harness snapshot inside the app bundle.
//
// `make-standalone.sh` copies the repository sources and a matching node
// binary into Contents/Resources/runtime so the copied app can run on a
// machine without this checkout. Resolution treats the snapshot as the LAST
// resort: during development the walk-up still finds the live checkout (the
// bundle sits inside it), so edits apply without repackaging; an app moved
// elsewhere fails the walk-up and falls back to its own snapshot.

import Foundation

enum EmbeddedRuntime {

    /// Bundle-resources subdirectory holding the repository snapshot.
    static let bundleRelativePath = "runtime"

    /// Repository-relative location of the bundled node binary.
    static let nodePathInRepo = ".node-bin/node"

    /// The snapshot root inside `bundle`, or nil when absent/incomplete.
    static func locate(
        bundle: Bundle = .main,
        isValidRepo: (String) -> Bool = { RepoLocator.isValidRepo($0) }
    ) -> String? {
        guard let resources = bundle.resourceURL else { return nil }
        let root = resources.appendingPathComponent(bundleRelativePath, isDirectory: true)
        return isValidRepo(root.path) ? root.path : nil
    }
}
