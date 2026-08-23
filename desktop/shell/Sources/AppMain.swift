// AppMain — entry point.
//
// `@main` alone does not install the delegate when the binary runs without a
// nib or principal-class wiring, so bootstrap installs the app, delegate, and
// run loop explicitly.

import AppKit

@main
enum AppMain {

    static func main() {
        SingleInstanceGuard.activateExistingAndExit(bundleIdentifier: AppDelegate.bundleIdentifier)

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
