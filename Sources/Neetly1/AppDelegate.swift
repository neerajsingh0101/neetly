import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var setupWindowController: SetupWindowController?
    var workspaceWindowController: WorkspaceWindowController?
    var socketServer: SocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        showSetupWindow()
    }

    private func showSetupWindow() {
        setupWindowController = SetupWindowController()
        setupWindowController?.onLaunch = { [weak self] config in
            self?.launchWorkspace(config)
        }
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func launchWorkspace(_ config: WorkspaceConfig) {
        // Start socket server
        socketServer = SocketServer()
        socketServer?.start()

        // Close setup window, open workspace
        setupWindowController?.close()
        setupWindowController = nil

        workspaceWindowController = WorkspaceWindowController(
            config: config,
            socketServer: socketServer!
        )
        workspaceWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About neetly1", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit neetly1", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (needed for text input to work in text fields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Pane menu
        let paneMenuItem = NSMenuItem()
        let paneMenu = NSMenu(title: "Pane")
        paneMenu.addItem(withTitle: "New Terminal", action: #selector(newTerminalTab), keyEquivalent: "t")
        paneMenu.addItem(withTitle: "New Browser", action: #selector(newBrowserTab), keyEquivalent: "t")
        paneMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        paneMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        paneMenu.addItem(withTitle: "Reload Browser", action: #selector(reloadBrowser), keyEquivalent: "r")
        paneMenu.addItem(.separator())
        paneMenu.addItem(withTitle: "Next Tab", action: #selector(nextTab), keyEquivalent: "]")
        paneMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        paneMenu.addItem(withTitle: "Previous Tab", action: #selector(previousTab), keyEquivalent: "[")
        paneMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        paneMenuItem.submenu = paneMenu
        mainMenu.addItem(paneMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func reloadBrowser() {
        if let pane = findFocusedPane(), let browser = pane.activeBrowserTab() {
            browser.forceReload()
        }
    }

    @objc private func closeCurrentTab() {
        if let pane = findFocusedPane(), pane.tabCount() > 0 {
            pane.closeActiveTab()
        }
    }

    @objc private func newTerminalTab() {
        if let pane = findFocusedPane() {
            pane.addTerminalTab(command: "")
        }
    }

    @objc private func newBrowserTab() {
        if let pane = findFocusedPane() {
            pane.addBrowserTab(url: "")
        }
    }

    @objc private func nextTab() {
        // Find the focused pane and switch its tab
        if let pane = findFocusedPane() {
            pane.selectNextTab()
        }
    }

    @objc private func previousTab() {
        if let pane = findFocusedPane() {
            pane.selectPreviousTab()
        }
    }

    private func findFocusedPane() -> PaneViewController? {
        guard let window = NSApp.keyWindow else { return nil }
        guard let firstResponder = window.firstResponder as? NSView else { return nil }

        // Walk up the view hierarchy to find which pane contains the first responder
        var current: NSView? = firstResponder
        while let view = current {
            if let paneVC = workspaceWindowController?.getSplitTree()?
                .paneControllers.values.first(where: { $0.view == view || $0.view.isDescendant(of: view) || view.isDescendant(of: $0.view) }) {
                return paneVC
            }
            current = view.superview
        }

        // Fallback: return first pane
        return workspaceWindowController?.getSplitTree()?.paneControllers.values.first
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Expose split tree for menu actions
extension WorkspaceWindowController {
    func getSplitTree() -> SplitTreeController? {
        splitTree
    }
}
