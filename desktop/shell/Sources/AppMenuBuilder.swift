// AppMenuBuilder — constructs the menu bar. Structure only: every action
// selector must exist on the target (AppDelegate implements MenuActions).
// Menu layout follows the reference products' native affordances — Edit roles
// so text editing works inside the webview, browser-style zoom, File ▸ New
// Window, and a Server menu for the local process lifecycle.

import AppKit

/// Selectors the menu builder wires up; implemented by AppDelegate.
@objc protocol MenuActions: NSObjectProtocol {
    func newWindow(_ sender: Any?)
    func reloadPage(_ sender: Any?)
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    func resetZoom(_ sender: Any?)
    func restartServer(_ sender: Any?)
    func openInBrowser(_ sender: Any?)
    func copyServerURL(_ sender: Any?)
    func revealServerLog(_ sender: Any?)
}

enum AppMenuBuilder {

    static func install(into target: MenuActions) {
        let mainMenu = NSMenu()

        // App menu.
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About DeepSeek Harness",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DeepSeek Harness",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DeepSeek Harness",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu — New Window / Close Window (bb pattern).
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New Window", action: #selector(MenuActions.newWindow(_:)),
                         keyEquivalent: "n")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)),
                         keyEquivalent: "w")

        // Edit menu — without these roles, undo/copy/paste do not work in a
        // WKWebView (every reference product ships them).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu — reload + zoom (bb pattern).
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(MenuActions.reloadPage(_:)),
                         keyEquivalent: "r")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(MenuActions.zoomIn(_:)),
                         keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(MenuActions.zoomOut(_:)),
                         keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(MenuActions.resetZoom(_:)),
                         keyEquivalent: "0")

        // Server menu — lifecycle affordances for the local agent process.
        let serverItem = NSMenuItem()
        mainMenu.addItem(serverItem)
        let serverMenu = NSMenu(title: "Server")
        serverItem.submenu = serverMenu
        serverMenu.addItem(withTitle: "Restart Server", action: #selector(MenuActions.restartServer(_:)),
                           keyEquivalent: "r").keyEquivalentModifierMask = [.command, .shift]
        serverMenu.addItem(withTitle: "Open in Browser", action: #selector(MenuActions.openInBrowser(_:)),
                           keyEquivalent: "b").keyEquivalentModifierMask = [.command, .control]
        serverMenu.addItem(withTitle: "Copy Server URL", action: #selector(MenuActions.copyServerURL(_:)),
                           keyEquivalent: "u").keyEquivalentModifierMask = [.command, .control]
        serverMenu.addItem(.separator())
        serverMenu.addItem(withTitle: "Reveal Server Log", action: #selector(MenuActions.revealServerLog(_:)),
                           keyEquivalent: "")

        // Window menu.
        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")

        NSApp.mainMenu = mainMenu
    }
}
