import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var setupWindowController: SetupWindowController?
    var sessionWindowController: SessionWindowController?
    private var escapeMonitor: Any?
    private var shortcutMonitor: Any?
    private var paneMenu: NSMenu?
    private var sessionMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Shorten AppKit's default ~1.5s tooltip delay.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])

        // Resolve chrome colors from the saved terminal theme before any window
        // or menu reads a Theme color.
        ChromeTheme.refresh()

        setAppIcon()
        setupMainMenu()
        setupEscapeKeyMonitor()
        setupShortcutKeyMonitor()

        let toRestore = SessionStore.shared.load().filter { $0.isOpen }
        if toRestore.isEmpty {
            showSetupWindow()
        } else {
            restoreSessions(toRestore)
        }
    }

    private func restoreSessions(_ saved: [SavedSession]) {
        let parser = LayoutParser()
        for ws in saved {
            let dedented = dedent(ws.layoutText)
            guard let layout = parser.parse(dedented) else { continue }
            let config = SessionConfig(
                repoPath: ws.repoPath,
                repoName: ws.repoName,
                sessionName: ws.sessionName,
                worktreeName: ws.worktreeName,
                layout: layout,
                layoutText: ws.layoutText,
                autoReloadOnFileChange: ws.autoReloadOnFileChange
            )
            launchSession(config)
        }
    }

    private func dedent(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let minIndent = nonEmpty.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        return lines.map { $0.count >= minIndent ? String($0.dropFirst(minIndent)) : $0 }
            .joined(separator: "\n")
    }

    private func showSetupWindow(initialScreen: SetupScreen = .repoList) {
        setupWindowController = SetupWindowController(initialScreen: initialScreen)
        setupWindowController?.onLaunch = { [weak self] config in
            self?.launchSession(config)
        }
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        showSetupWindow(initialScreen: .settings)
    }

    private func launchSession(_ config: SessionConfig) {
        setupWindowController?.close()

        if sessionWindowController == nil {
            sessionWindowController = SessionWindowController()
            sessionWindowController?.onNewSession = { [weak self] in
                self?.showSetupWindow()
            }
            sessionWindowController?.showWindow(nil)
        }

        sessionWindowController?.addSession(config: config)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Install a local key-event monitor that catches Escape and exits
    /// maximize mode if a pane is currently maximized. Escape is ignored
    /// otherwise, so terminals still receive it for their own handling.
    private func setupEscapeKeyMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // 53 = Escape
            guard let splitTree = self?.sessionWindowController?.getSplitTree(),
                  splitTree.isMaximized else { return event }
            splitTree.toggleMaximizeForActivePane()
            return nil  // consume the event
        }
    }

    /// Route the app's Pane/Session menu shortcuts before libghostty can
    /// swallow them. A focused terminal surface otherwise consumes ⌘-combos
    /// (only ⌘Q/⌘, are released via ghostty `=unbind`), so menu key equivalents
    /// never fire over a terminal. This local monitor runs before the terminal
    /// sees the event: if a Pane/Session menu item claims it, perform it and
    /// consume the event. The Edit menu is intentionally NOT consulted, so
    /// terminal typing and ⌘C/⌘V copy-paste pass straight through.
    private func setupShortcutKeyMonitor() {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Only ⌘ combinations are app shortcuts; plain typing must pass through.
            guard event.modifierFlags.contains(.command) else { return event }
            if self.paneMenu?.performKeyEquivalent(with: event) == true { return nil }
            if self.sessionMenu?.performKeyEquivalent(with: event) == true { return nil }
            return event
        }
    }

    // Locate AppIcon.icns without going through Bundle.module — its auto-
    // generated accessor fatalErrors at launch if the SwiftPM resource bundle
    // directory isn't where it expects, which reportedly happens on some
    // machines when the .app is launched via Gatekeeper/quarantine copy paths.
    private static let appIconURL: URL? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            return url
        }
        // Dev fallback: `swift run` puts the SPM resource bundle next to the
        // executable at .build/<triple>/<config>/neetly_neetly-app.bundle/.
        let devCandidate = Bundle.main.bundleURL
            .appendingPathComponent("neetly_neetly-app.bundle/AppIcon.icns")
        return FileManager.default.fileExists(atPath: devCandidate.path) ? devCandidate : nil
    }()

    /// Set the Dock/Cmd+Tab icon from the bundled resource. Needed for
    /// dev runs (`swift run neetly-app`) where there's no .app bundle to
    /// pick up CFBundleIconFile.
    private func setAppIcon() {
        if let url = Self.appIconURL, let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About neetly", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        let checkItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(Updater.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkItem.target = Updater.shared
        appMenu.addItem(checkItem)
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit neetly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        let newBrowserItem = paneMenu.addItem(withTitle: "New Browser", action: #selector(newBrowserTab), keyEquivalent: "t")
        newBrowserItem.keyEquivalentModifierMask = [.command, .shift]
        paneMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        paneMenu.addItem(withTitle: "Reload Browser", action: #selector(reloadBrowser), keyEquivalent: "r")

        paneMenu.addItem(.separator())
        paneMenu.addItem(withTitle: "Split Right", action: #selector(splitRight), keyEquivalent: "d")
        let splitDownItem = paneMenu.addItem(withTitle: "Split Down", action: #selector(splitDown), keyEquivalent: "d")
        splitDownItem.keyEquivalentModifierMask = [.command, .shift]
        let closePaneItem = paneMenu.addItem(withTitle: "Close Pane", action: #selector(closeFocusedPane), keyEquivalent: "w")
        closePaneItem.keyEquivalentModifierMask = [.command, .shift]
        let maximizeItem = paneMenu.addItem(withTitle: "Maximize / Restore", action: #selector(toggleMaximize), keyEquivalent: "m")
        maximizeItem.keyEquivalentModifierMask = [.command, .shift]

        paneMenu.addItem(.separator())
        paneMenu.addItem(withTitle: "Focus Pane Left", action: #selector(focusPaneLeft), keyEquivalent: "h")
        paneMenu.addItem(withTitle: "Focus Pane Down", action: #selector(focusPaneDown), keyEquivalent: "j")
        paneMenu.addItem(withTitle: "Focus Pane Up", action: #selector(focusPaneUp), keyEquivalent: "k")
        paneMenu.addItem(withTitle: "Focus Pane Right", action: #selector(focusPaneRight), keyEquivalent: "l")

        let focusTabItem = NSMenuItem(title: "Focus Tab", action: nil, keyEquivalent: "")
        let focusTabMenu = NSMenu(title: "Focus Tab")
        for n in 1 ... 9 {
            let item = focusTabMenu.addItem(withTitle: "Tab \(n)", action: #selector(focusTab(_:)), keyEquivalent: "\(n)")
            item.tag = n
        }
        focusTabItem.submenu = focusTabMenu
        paneMenu.addItem(focusTabItem)

        paneMenu.addItem(.separator())
        let nextTabItem = paneMenu.addItem(withTitle: "Next Tab", action: #selector(nextTab), keyEquivalent: "]")
        nextTabItem.keyEquivalentModifierMask = [.command, .shift]
        let prevTabItem = paneMenu.addItem(withTitle: "Previous Tab", action: #selector(previousTab), keyEquivalent: "[")
        prevTabItem.keyEquivalentModifierMask = [.command, .shift]

        paneMenu.addItem(.separator())
        paneMenu.addItem(withTitle: "Open Diff", action: #selector(openDiff), keyEquivalent: "g")
        let closeDiffItem = paneMenu.addItem(withTitle: "Close Diff", action: #selector(closeDiff), keyEquivalent: "g")
        closeDiffItem.keyEquivalentModifierMask = [.command, .shift]

        paneMenuItem.submenu = paneMenu
        mainMenu.addItem(paneMenuItem)
        self.paneMenu = paneMenu

        // Session menu
        let sessionMenuItem = NSMenuItem()
        let sessionMenu = NSMenu(title: "Session")
        sessionMenu.addItem(withTitle: "New Session", action: #selector(newSession), keyEquivalent: "n")
        let closeSessionItem = sessionMenu.addItem(withTitle: "Close Session", action: #selector(closeCurrentSession), keyEquivalent: "n")
        closeSessionItem.keyEquivalentModifierMask = [.command, .shift]

        sessionMenu.addItem(.separator())
        let focusSessionItem = NSMenuItem(title: "Focus Session", action: nil, keyEquivalent: "")
        let focusSessionMenu = NSMenu(title: "Focus Session")
        for n in 1 ... 9 {
            let item = focusSessionMenu.addItem(withTitle: "Session \(n)", action: #selector(focusSession(_:)), keyEquivalent: "\(n)")
            item.keyEquivalentModifierMask = [.command, .option]
            item.tag = n
        }
        focusSessionItem.submenu = focusSessionMenu
        sessionMenu.addItem(focusSessionItem)

        let nextSessionItem = sessionMenu.addItem(withTitle: "Next Session", action: #selector(nextSession), keyEquivalent: "]")
        nextSessionItem.keyEquivalentModifierMask = [.command, .option]
        let prevSessionItem = sessionMenu.addItem(withTitle: "Previous Session", action: #selector(previousSession), keyEquivalent: "[")
        prevSessionItem.keyEquivalentModifierMask = [.command, .option]

        sessionMenuItem.submenu = sessionMenu
        mainMenu.addItem(sessionMenuItem)
        self.sessionMenu = sessionMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "neetly",
            .applicationVersion: version,
            .version: "",
            .credits: NSAttributedString(
                string: "Copyright \u{00A9} 2026 \u{2014} Neeto",
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 11),
                ]
            ),
        ]
        if let url = Self.appIconURL, let icon = NSImage(contentsOf: url) {
            options[.applicationIcon] = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func toggleMaximize() {
        guard let splitTree = sessionWindowController?.getSplitTree() else { return }
        if splitTree.isMaximized {
            splitTree.toggleMaximizeForActivePane()
        } else if let pane = findFocusedPane() {
            splitTree.toggleMaximize(pane)
        }
    }

    @objc private func openDiff() {
        guard let splitTree = sessionWindowController?.getSplitTree() else { return }

        // Find the last pane (rightmost/bottommost) by seqId
        guard let pane = splitTree.paneControllers.values.max(by: { $0.seqId < $1.seqId }) else { return }

        // Add a terminal tab with the configured diff command
        pane.addTerminalTab(command: NeetlySettings.shared.diffCommand)

        // Maximize the pane after a short delay to let the tab initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !splitTree.isMaximized {
                splitTree.toggleMaximize(pane)
            }
        }
    }

    @objc private func closeDiff() {
        guard let splitTree = sessionWindowController?.getSplitTree() else { return }

        // Unmaximize first if maximized
        if splitTree.isMaximized {
            splitTree.toggleMaximizeForActivePane()
        }

        // Close the active tab (kills the diff process cleanly)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let pane = self?.findFocusedPane() {
                pane.closeActiveTab()
            }
        }
    }

    @objc private func clearTerminal() {
        if let pane = findFocusedPane(), let terminal = pane.activeTerminalTab() {
            terminal.sendText("\u{0C}")
        }
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
        if let pane = findFocusedPane() {
            pane.selectNextTab()
        }
    }

    @objc private func previousTab() {
        if let pane = findFocusedPane() {
            pane.selectPreviousTab()
        }
    }

    // MARK: - Pane focus (vim hjkl) + splits

    @objc private func focusPaneLeft()  { focusPane(.left) }
    @objc private func focusPaneDown()  { focusPane(.down) }
    @objc private func focusPaneUp()    { focusPane(.up) }
    @objc private func focusPaneRight() { focusPane(.right) }

    private func focusPane(_ direction: PaneFocusDirection) {
        guard let splitTree = sessionWindowController?.getSplitTree(),
              let pane = findFocusedPane() else { return }
        splitTree.focusAdjacentPane(from: pane, direction)
    }

    @objc private func splitRight() {
        guard let splitTree = sessionWindowController?.getSplitTree(),
              let pane = findFocusedPane() else { return }
        splitTree.splitPane(pane, direction: .columns)
    }

    @objc private func splitDown() {
        guard let splitTree = sessionWindowController?.getSplitTree(),
              let pane = findFocusedPane() else { return }
        splitTree.splitPane(pane, direction: .rows)
    }

    @objc private func closeFocusedPane() {
        guard let splitTree = sessionWindowController?.getSplitTree(),
              let pane = findFocusedPane() else { return }
        splitTree.closePane(pane)
    }

    // MARK: - Focus tab by number (menu item tag = 1-based tab index)

    @objc private func focusTab(_ sender: NSMenuItem) {
        guard let pane = findFocusedPane() else { return }
        let index = sender.tag - 1
        if index >= 0 && index < pane.tabCount() {
            pane.selectTab(at: index)
        }
    }

    // MARK: - Sessions

    @objc private func focusSession(_ sender: NSMenuItem) {
        sessionWindowController?.selectSession(at: sender.tag - 1)
    }

    @objc private func nextSession() {
        guard let wc = sessionWindowController, wc.sessionCount() > 0 else { return }
        wc.selectSession(at: (wc.activeSessionIndex() + 1) % wc.sessionCount())
    }

    @objc private func previousSession() {
        guard let wc = sessionWindowController, wc.sessionCount() > 0 else { return }
        let count = wc.sessionCount()
        wc.selectSession(at: (wc.activeSessionIndex() - 1 + count) % count)
    }

    @objc private func newSession() {
        showSetupWindow()
    }

    @objc private func closeCurrentSession() {
        guard let wc = sessionWindowController else { return }
        let index = wc.activeSessionIndex()
        if index >= 0 { wc.closeSession(at: index) }
    }

    private func findFocusedPane() -> PaneViewController? {
        guard let window = NSApp.keyWindow else { return nil }
        guard let firstResponder = window.firstResponder as? NSView else { return nil }

        var current: NSView? = firstResponder
        while let view = current {
            if let paneVC = sessionWindowController?.getSplitTree()?
                .paneControllers.values.first(where: { $0.view == view || $0.view.isDescendant(of: view) || view.isDescendant(of: $0.view) }) {
                return paneVC
            }
            current = view.superview
        }

        return sessionWindowController?.getSplitTree()?.paneControllers.values.first
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
