import AppKit

/// Holds the runtime state for one workspace.
class Workspace {
    let config: WorkspaceConfig
    let socketServer: SocketServer
    let splitTree: SplitTreeController
    var fileWatcher: FileWatcher?
    /// Status color for the workspace tab. nil = default, green = done, etc.
    var statusColor: NSColor?
    /// Resolved GitHub PR info. nil = no PR found or not yet fetched.
    var prInfo: GitHubPRInfo?
    var onStatusChanged: (() -> Void)?

    init(config: WorkspaceConfig) {
        self.socketServer = SocketServer()
        self.splitTree = SplitTreeController(
            layout: config.layout,
            repoPath: config.repoPath,
            socketServer: socketServer
        )
        self.config = config

        socketServer.start()
        splitTree.loadViewIfNeeded()

        if config.autoReloadOnFileChange {
            let watcher = FileWatcher(repoPath: config.repoPath)
            watcher.onChange = { [weak self] in
                self?.reloadAllBrowserTabs()
            }
            watcher.start()
            fileWatcher = watcher
        }
    }

    func setupSocketHandler(handler: @escaping (SocketCommand) -> Data?) {
        socketServer.onCommand = handler
    }

    func reloadAllBrowserTabs() {
        for pane in splitTree.paneControllers.values {
            for browser in pane.allBrowserTabs() {
                if browser.hasCompletedInitialLoad {
                    browser.forceReload()
                }
            }
        }
    }

    func refreshPRStatus() {
        GitHubPRResolver.resolve(worktreePath: config.repoPath) { [weak self] info in
            guard let self = self else { return }
            self.prInfo = info
            self.onStatusChanged?()
        }
    }

    func stop() {
        fileWatcher?.stop()
        socketServer.stop()
    }
}

// MARK: - Workspace Tab Bar

class WorkspaceTabBar: NSView {
    var onSelectWorkspace: ((Int) -> Void)?
    var onCloseWorkspace: ((Int) -> Void)?
    var onNewWorkspace: (() -> Void)?
    private var tabViews: [NSView] = []
    private let plusButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        plusButton.title = "+"
        plusButton.toolTip = "New Workspace"
        plusButton.bezelStyle = .recessed
        plusButton.font = .systemFont(ofSize: 14, weight: .medium)
        plusButton.target = self
        plusButton.action = #selector(plusClicked)
        plusButton.frame = NSRect(x: 0, y: 18, width: 28, height: 24)
        addSubview(plusButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(workspaces: [(repoName: String, workspaceName: String, isActive: Bool, statusColor: NSColor?, prInfo: GitHubPRInfo?)]) {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        plusButton.removeFromSuperview()

        var x: CGFloat = 4
        for (i, ws) in workspaces.enumerated() {
            let tab = WorkspaceTab(
                index: i, repoName: ws.repoName, workspaceName: ws.workspaceName, isActive: ws.isActive,
                statusColor: ws.statusColor, prInfo: ws.prInfo,
                onSelect: { [weak self] idx in self?.onSelectWorkspace?(idx) },
                onClose: { [weak self] idx in self?.onCloseWorkspace?(idx) }
            )
            tab.frame.origin = CGPoint(x: x, y: 2)
            addSubview(tab)
            tabViews.append(tab)
            x += tab.frame.width + 4
        }

        plusButton.frame.origin.x = x
        plusButton.frame.origin.y = 18
        addSubview(plusButton)
    }

    @objc private func plusClicked() {
        onNewWorkspace?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

private class WorkspaceTab: NSView {
    let index: Int
    private let onSelect: (Int) -> Void
    private let onClose: (Int) -> Void
    private let closeBtn: NSButton
    private var trackingArea: NSTrackingArea?
    private var prURL: URL?
    private var prBtnFrame: NSRect = .zero

    init(index: Int, repoName: String, workspaceName: String, isActive: Bool,
         statusColor: NSColor?, prInfo: GitHubPRInfo?,
         onSelect: @escaping (Int) -> Void, onClose: @escaping (Int) -> Void) {
        self.index = index
        self.onSelect = onSelect
        self.onClose = onClose
        self.closeBtn = NSButton(frame: NSRect(x: 0, y: 10, width: 18, height: 18))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        if let color = statusColor {
            layer?.backgroundColor = color.withAlphaComponent(0.45).cgColor
        } else if isActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        let hasPR = prInfo != nil

        // -- Line 1: Repo name (top, small, secondary) --
        let repoLabel = NSTextField(labelWithString: repoName)
        repoLabel.font = .systemFont(ofSize: 10)
        repoLabel.textColor = .secondaryLabelColor
        repoLabel.lineBreakMode = .byTruncatingTail
        repoLabel.frame = NSRect(x: 8, y: hasPR ? 38 : 30, width: 140, height: 14)
        addSubview(repoLabel)

        // -- Line 2: Workspace name (middle, larger) --
        let wsLabel = NSTextField(labelWithString: workspaceName)
        wsLabel.font = .systemFont(ofSize: 14, weight: isActive ? .semibold : .regular)
        wsLabel.lineBreakMode = .byTruncatingTail
        wsLabel.frame = NSRect(x: 8, y: hasPR ? 22 : 12, width: 140, height: 17)
        addSubview(wsLabel)

        // -- Line 3: PR badge pill (bottom, clickable) --
        var prPillWidth: CGFloat = 0
        if let pr = prInfo {
            self.prURL = URL(string: pr.url)
            let prColor = Self.color(for: pr.state)
            let stateText = Self.stateLabel(for: pr.state)

            let prAttr = NSMutableAttributedString()
            prAttr.append(NSAttributedString(string: " \u{25CF} ", attributes: [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: prColor,
                .baselineOffset: 1.5,
            ]))
            prAttr.append(NSAttributedString(string: "\(stateText) #\(pr.number) \u{2197} ", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: prColor,
            ]))

            let prBtn = NSButton(frame: .zero)
            prBtn.wantsLayer = true
            prBtn.layer?.cornerRadius = 4
            prBtn.layer?.backgroundColor = prColor.withAlphaComponent(0.10).cgColor
            prBtn.isBordered = false
            prBtn.attributedTitle = prAttr
            prBtn.target = self
            prBtn.action = #selector(openPR)
            prBtn.toolTip = Self.tooltip(for: pr)
            prBtn.sizeToFit()
            prBtn.frame = NSRect(
                x: 6, y: 4,
                width: prBtn.intrinsicContentSize.width,
                height: 15
            )
            addSubview(prBtn)
            prBtnFrame = prBtn.frame
            prPillWidth = prBtn.frame.width + 4
        }

        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close workspace")
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.isHidden = true
        closeBtn.frame = NSRect(x: 0, y: hasPR ? 26 : 16, width: 18, height: 18)
        addSubview(closeBtn)

        let textWidth = max(
            repoLabel.intrinsicContentSize.width,
            wsLabel.intrinsicContentSize.width,
            prPillWidth
        )
        let width = min(textWidth + 38, 240)
        frame.size = NSSize(width: width, height: hasPR ? 56 : 52)
        repoLabel.frame.size.width = width - 34
        wsLabel.frame.size.width = width - 34
        closeBtn.frame.origin.x = width - 22
    }

    @objc private func openPR() {
        if let url = prURL {
            NSWorkspace.shared.open(url)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if prURL != nil && !prBtnFrame.isEmpty {
            addCursorRect(prBtnFrame, cursor: .pointingHand)
        }
    }

    private static func color(for state: PRState) -> NSColor {
        switch state {
        case .open:   return .systemGreen
        case .draft:  return .systemGray
        case .merged: return .systemPurple
        case .closed: return .systemRed
        }
    }

    private static func stateLabel(for state: PRState) -> String {
        switch state {
        case .open:   return "Open"
        case .draft:  return "Draft"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }

    private static func tooltip(for pr: GitHubPRInfo) -> String {
        return "#\(pr.number) \(pr.title)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { closeBtn.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeBtn.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x < frame.width - 22 {
            onSelect(index)
        }
    }

    @objc private func closeClicked() { onClose(index) }
}

// MARK: - Window Controller

class WorkspaceWindowController: NSWindowController {
    private var workspaces: [Workspace] = []
    private var activeIndex: Int = -1
    private let workspaceTabBar = WorkspaceTabBar(frame: .zero)
    private let contentArea = NSView()
    private var prRefreshTimer: Timer?
    var onNewWorkspace: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly"
        window.center()
        window.setFrameAutosaveName("WorkspaceWindow")
        super.init(window: window)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        guard let contentView = window?.contentView else { return }

        workspaceTabBar.translatesAutoresizingMaskIntoConstraints = false
        workspaceTabBar.onSelectWorkspace = { [weak self] i in self?.selectWorkspace(at: i) }
        workspaceTabBar.onCloseWorkspace = { [weak self] i in self?.closeWorkspace(at: i) }
        workspaceTabBar.onNewWorkspace = { [weak self] in self?.onNewWorkspace?() }
        contentView.addSubview(workspaceTabBar)

        contentArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentArea)

        NSLayoutConstraint.activate([
            workspaceTabBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            workspaceTabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            workspaceTabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            workspaceTabBar.heightAnchor.constraint(equalToConstant: 60),

            contentArea.topAnchor.constraint(equalTo: workspaceTabBar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func addWorkspace(config: WorkspaceConfig) {
        let ws = Workspace(config: config)
        ws.onStatusChanged = { [weak self] in
            self?.refreshTabBar()
        }
        ws.setupSocketHandler { [weak self, weak ws] command in
            guard let ws = ws else { return nil }
            return self?.handleSocketCommand(command, workspace: ws)
        }
        workspaces.append(ws)
        selectWorkspace(at: workspaces.count - 1)

        // Fetch PR status immediately
        ws.refreshPRStatus()

        // Start periodic PR refresh if not already running
        if prRefreshTimer == nil {
            prRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.refreshAllPRStatuses()
            }
        }
    }

    private func refreshAllPRStatuses() {
        for ws in workspaces {
            ws.refreshPRStatus()
        }
    }

    private func selectWorkspace(at index: Int) {
        guard index >= 0 && index < workspaces.count else { return }

        // Remove current content
        if activeIndex >= 0 && activeIndex < workspaces.count {
            workspaces[activeIndex].splitTree.view.removeFromSuperview()
        }

        activeIndex = index
        let ws = workspaces[index]
        ws.statusColor = nil
        ws.splitTree.view.frame = contentArea.bounds
        ws.splitTree.view.autoresizingMask = [.width, .height]
        contentArea.addSubview(ws.splitTree.view)

        window?.title = "neetly -\(ws.config.workspaceName)"
        refreshTabBar()
    }

    private func closeWorkspace(at index: Int) {
        guard index >= 0 && index < workspaces.count else { return }

        if index == activeIndex {
            workspaces[index].splitTree.view.removeFromSuperview()
        }

        workspaces[index].stop()
        workspaces.remove(at: index)

        if workspaces.isEmpty {
            activeIndex = -1
            window?.title = "neetly"
            prRefreshTimer?.invalidate()
            prRefreshTimer = nil
            onNewWorkspace?()
        } else {
            activeIndex = min(activeIndex, workspaces.count - 1)
            selectWorkspace(at: activeIndex)
        }
    }

    private func refreshTabBar() {
        let tabs = workspaces.enumerated().map { (i, ws) in
            (repoName: ws.config.repoName, workspaceName: ws.config.workspaceName, isActive: i == activeIndex, statusColor: ws.statusColor, prInfo: ws.prInfo)
        }
        workspaceTabBar.update(workspaces: tabs)
    }

    /// Get the active workspace's split tree for menu actions.
    func getSplitTree() -> SplitTreeController? {
        guard activeIndex >= 0 && activeIndex < workspaces.count else { return nil }
        return workspaces[activeIndex].splitTree
    }

    // MARK: - Socket Command Handling

    private func handleSocketCommand(_ command: SocketCommand, workspace ws: Workspace) -> Data? {
        switch command.action {
        case "browser.open":
            guard let url = command.url else { return nil }
            let bg = command.background ?? false
            let pane = resolvePane(command, in: ws)
            pane?.addBrowserTab(url: url, background: bg)
            return nil

        case "terminal.run":
            guard let cmd = command.command else { return nil }
            let pane = resolvePane(command, in: ws)
            pane?.addTerminalTab(command: cmd)
            return nil

        case "tabs.list":
            var allTabs: [TabListEntry] = []
            for pane in ws.splitTree.paneControllers.values {
                allTabs.append(contentsOf: pane.listTabs())
            }
            return try? JSONEncoder().encode(allTabs)

        case "tab.send":
            guard let tabId = command.tabId, let text = command.text else {
                return jsonResponse(["ok": false, "error": "missing tabId or text"])
            }
            for pane in ws.splitTree.paneControllers.values {
                if pane.sendTextToTab(tabId: tabId, text: text) {
                    return jsonResponse(["ok": true])
                }
            }
            return jsonResponse(["ok": false, "error": "tab not found: \(tabId)"])

        case "workspace.notify":
            let colorName = command.command ?? "green"
            let color: NSColor
            switch colorName {
            case "green": color = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
            case "red": color = .systemRed
            case "yellow": color = .systemYellow
            case "blue": color = .systemBlue
            case "orange": color = .systemOrange
            case "clear", "none", "reset": ws.statusColor = nil; ws.onStatusChanged?(); return nil
            default: color = .systemGreen
            }
            ws.statusColor = color
            ws.onStatusChanged?()
            return nil

        default:
            return nil
        }
    }

    private func resolvePane(_ command: SocketCommand, in ws: Workspace) -> PaneViewController? {
        if let seq = command.paneSeq {
            if let pane = ws.splitTree.paneControllers.values.first(where: { $0.seqId == seq }) {
                return pane
            }
        }
        if let paneId = command.paneId, !paneId.isEmpty {
            if let pane = ws.splitTree.pane(for: paneId) {
                return pane
            }
        }
        return ws.splitTree.paneControllers.values.first
    }

    private func jsonResponse(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}
