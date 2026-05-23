import AppKit

/// Holds the runtime state for one session.
class Session {
    let config: SessionConfig
    let socketServer: SocketServer
    let splitTree: SplitTreeController
    var fileWatcher: FileWatcher?
    /// Status color for the session tab. nil = default, green = done, etc.
    var statusColor: NSColor?
    /// All GitHub PRs observed during this session's lifetime. The resolver only
    /// surfaces the PR for the currently-checked-out branch; this list accumulates
    /// every distinct PR (by number) seen across branch switches so users can
    /// still navigate to PRs opened earlier in the session.
    var prInfos: [GitHubPRInfo] = []
    /// Short commit SHA of the worktree's current HEAD.
    var commitSha: String?
    /// GitHub commit URL for the worktree's current HEAD, if the remote is GitHub.
    var commitURL: String?
    /// Uncommitted diff stats (lines added/deleted vs HEAD).
    var diffStats: (added: Int, deleted: Int)?
    var onStatusChanged: (() -> Void)?

    init(config: SessionConfig) {
        // If a previous Claude Code session exists for this worktree, append
        // --continue to any `claude` run command so re-attaching resumes the
        // session instead of starting a fresh one.
        let layout = GitWorktree.hasClaudeSession(forWorktreePath: config.repoPath)
            ? Self.appendingClaudeContinue(to: config.layout)
            : config.layout

        self.socketServer = SocketServer()
        self.splitTree = SplitTreeController(
            layout: layout,
            repoPath: config.repoPath,
            socketServer: socketServer
        )
        self.config = config
        self.commitSha = GitWorktree.headShortSha(worktreePath: config.repoPath)
        self.commitURL = GitWorktree.headCommitURL(worktreePath: config.repoPath)

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
            guard let info = info else {
                // Resolver found nothing for the current branch — don't clear the
                // session's PR history; previously-opened PRs stay listed.
                self.onStatusChanged?()
                return
            }

            let existingIdx = self.prInfos.firstIndex { $0.number == info.number }
            let previousState = existingIdx.map { self.prInfos[$0].state }

            if let idx = existingIdx {
                self.prInfos[idx] = info
            } else {
                self.prInfos.append(info)
            }

            // Setup screen still shows a single per-session PR — keep writing the
            // latest detected one.
            SessionStore.shared.updatePRInfo(
                repoPath: self.config.repoPath,
                worktreeName: self.config.worktreeName,
                prInfo: info
            )

            let stateLabel: String
            switch info.state {
            case .open:   stateLabel = "Open"
            case .draft:  stateLabel = "Draft"
            case .merged: stateLabel = "Merged"
            case .closed: stateLabel = "Closed"
            }

            let isNew = existingIdx == nil
            if isNew {
                ActivityStore.shared.log(
                    .prOpened,
                    repoName: self.config.repoName,
                    detail: "\(info.number)",
                    prURL: info.url
                )
            }

            if isNew || previousState != info.state {
                ActivityStore.shared.updatePRState(
                    repoName: self.config.repoName,
                    prNumber: "\(info.number)",
                    state: stateLabel,
                    url: info.url
                )
            }

            self.onStatusChanged?()
        }
    }

    /// Walk the layout and append `--continue` to any `.run` command whose
    /// first token is exactly `claude`. Skips commands that already include
    /// `--continue` or `--resume` to stay idempotent.
    private static func appendingClaudeContinue(to node: LayoutNode) -> LayoutNode {
        switch node {
        case .run(let command):
            return .run(command: appendContinueIfClaude(command))
        case .visit:
            return node
        case .split(let direction, let first, let second, let firstSize, let secondSize):
            return .split(
                direction: direction,
                first: appendingClaudeContinue(to: first),
                second: appendingClaudeContinue(to: second),
                firstSize: firstSize,
                secondSize: secondSize
            )
        case .tabs(let children):
            return .tabs(children.map(appendingClaudeContinue))
        }
    }

    private static func appendContinueIfClaude(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) == "claude" else {
            return command
        }
        if command.contains("--continue") || command.contains("--resume") {
            return command
        }
        return command + " --continue"
    }

    func stop() {
        // SIGTERM foreground jobs and tear down shells so child processes
        // (servers, Ruby scripts, etc.) release ports before detach.
        for pane in splitTree.paneControllers.values {
            pane.terminateAllTerminals()
        }
        fileWatcher?.stop()
        socketServer.stop()
    }
}

// MARK: - Window Controller

class SessionWindowController: NSWindowController {
    private var sessions: [Session] = []
    private var activeIndex: Int = -1
    private let sessionStrip = SessionStrip(frame: .zero)
    private let statusBar = NeetlyStatusBar(frame: .zero)
    private let contentArea = NSView()
    private var activeCommitURL: URL?
    private var prRefreshTimer: Timer?
    private var diffStatsTimer: Timer?
    var onNewSession: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly"
        window.center()
        window.setFrameAutosaveName("SessionWindow")
        // The design is dark-mode-first with its own breadcrumb title bar. Pin
        // the window to dark and make the native title bar transparent so our
        // custom top bar fills it (the native traffic lights stay on top-left).
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg0
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        super.init(window: window)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        guard let contentView = window?.contentView else { return }

        // Session strip (top) — horizontal session tabs; sits in the transparent
        // title-bar region so the native traffic lights show through on the left.
        sessionStrip.translatesAutoresizingMaskIntoConstraints = false
        sessionStrip.onSelectSession = { [weak self] i in self?.selectSession(at: i) }
        sessionStrip.onCloseSession = { [weak self] i in self?.closeSession(at: i) }
        sessionStrip.onNewSession = { [weak self] in self?.onNewSession?() }
        contentView.addSubview(sessionStrip)

        // Workspace — holds the active session's split tree.
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        contentArea.wantsLayer = true
        contentArea.layer?.backgroundColor = Theme.bg0.cgColor
        contentView.addSubview(contentArea)

        // Status footer (bottom) — branch / diff / commit / PR.
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.onOpenCommit = { [weak self] in
            if let url = self?.activeCommitURL { NSWorkspace.shared.open(url) }
        }
        statusBar.onOpenPR = { url in NSWorkspace.shared.open(url) }
        contentView.addSubview(statusBar)

        NSLayoutConstraint.activate([
            sessionStrip.topAnchor.constraint(equalTo: contentView.topAnchor),
            sessionStrip.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sessionStrip.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sessionStrip.heightAnchor.constraint(equalToConstant: SessionStrip.barHeight),

            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24),

            contentArea.topAnchor.constraint(equalTo: sessionStrip.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ])
    }

    func addSession(config: SessionConfig) {
        // If this session is already open, just switch to it
        if let existing = sessions.firstIndex(where: { $0.config.repoPath == config.repoPath }) {
            selectSession(at: existing)
            return
        }

        let ws = Session(config: config)
        ws.onStatusChanged = { [weak self] in
            self?.refreshTabBar()
        }
        ws.setupSocketHandler { [weak self, weak ws] command in
            guard let ws = ws else { return nil }
            return self?.handleSocketCommand(command, session: ws)
        }
        sessions.append(ws)
        selectSession(at: sessions.count - 1)

        // Persist to session store
        SessionStore.shared.add(SavedSession(
            repoPath: config.repoPath,
            repoName: config.repoName,
            sessionName: config.sessionName,
            worktreeName: config.worktreeName,
            layoutText: config.layoutText,
            autoReloadOnFileChange: config.autoReloadOnFileChange
        ))

        // Fetch PR status immediately
        ws.refreshPRStatus()

        // Start periodic PR refresh if not already running
        if prRefreshTimer == nil {
            prRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.refreshAllPRStatuses()
            }
        }

        // Start diff stats polling for active session
        if diffStatsTimer == nil {
            diffStatsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.refreshActiveDiffStats()
            }
        }
    }

    private func refreshActiveDiffStats() {
        guard activeIndex >= 0 && activeIndex < sessions.count else { return }
        let ws = sessions[activeIndex]
        DispatchQueue.global(qos: .utility).async {
            let stats = GitWorktree.diffStats(worktreePath: ws.config.repoPath)
            let sha = GitWorktree.headShortSha(worktreePath: ws.config.repoPath)
            let url = GitWorktree.headCommitURL(worktreePath: ws.config.repoPath)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let statsChanged = ws.diffStats?.added != stats?.added || ws.diffStats?.deleted != stats?.deleted
                let shaChanged = ws.commitSha != sha
                ws.diffStats = stats
                ws.commitSha = sha
                ws.commitURL = url
                if statsChanged || shaChanged { self.refreshTabBar() }
            }
        }
    }

    private func refreshAllPRStatuses() {
        for ws in sessions {
            ws.refreshPRStatus()
        }
    }

    func selectSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }

        // Detach every session's splitTree view from contentArea before adding
        // the new one. removeFromSuperview is a no-op when the view isn't
        // attached, so this is cheap — and it guarantees no stale view is left
        // behind if activeIndex ever got out of sync with what's in the hierarchy.
        for ws in sessions {
            ws.splitTree.view.removeFromSuperview()
        }

        activeIndex = index
        let ws = sessions[index]
        ws.statusColor = nil
        ws.splitTree.view.frame = contentArea.bounds
        ws.splitTree.view.autoresizingMask = [.width, .height]
        contentArea.addSubview(ws.splitTree.view)

        window?.title = "neetly - \(ws.config.repoName) - \(ws.config.sessionName)"
        refreshTabBar()
    }

    /// Close any session whose repoPath (worktree path) matches.
    /// Called when a worktree is deleted from the setup screen.
    func closeSessionByPath(_ path: String) {
        if let index = sessions.firstIndex(where: { $0.config.repoPath == path }) {
            closeSession(at: index)
        }
    }

    func closeSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }

        // Mark as detached (keep in store so it stays in the session list,
        // but won't auto-reopen on next app launch).
        let cfg = sessions[index].config
        SessionStore.shared.markClosed(repoPath: cfg.repoPath, worktreeName: cfg.worktreeName)

        // Detach the currently-active view from contentArea before we mutate
        // the array. Otherwise, if `index < activeIndex`, the removal shifts
        // activeIndex onto a different session and the previously-active
        // view stays stuck in contentArea.
        if activeIndex >= 0 && activeIndex < sessions.count {
            sessions[activeIndex].splitTree.view.removeFromSuperview()
        }

        sessions[index].stop()
        sessions.remove(at: index)

        // If a session before the active one was closed, the active one shifted down.
        if index < activeIndex {
            activeIndex -= 1
        }

        if sessions.isEmpty {
            activeIndex = -1
            window?.title = "neetly"
            prRefreshTimer?.invalidate()
            prRefreshTimer = nil
            diffStatsTimer?.invalidate()
            diffStatsTimer = nil
            refreshTabBar()
        } else {
            activeIndex = min(max(0, activeIndex), sessions.count - 1)
            selectSession(at: activeIndex)
        }
    }

    private func refreshTabBar() {
        let rows = sessions.enumerated().map { (i, ws) in
            SessionRowModel(
                index: i,
                repoName: ws.config.repoName,
                sessionName: ws.config.sessionName,
                worktreeName: ws.config.worktreeName,
                repoPath: ws.config.repoPath,
                commitSha: ws.commitSha,
                commitURL: ws.commitURL,
                isActive: i == activeIndex,
                statusColor: ws.statusColor,
                prInfos: ws.prInfos,
                diffStats: ws.diffStats
            )
        }
        sessionStrip.update(rows: rows)

        let active = rows.first { $0.isActive }
        activeCommitURL = active?.commitURL.flatMap { URL(string: $0) }
        statusBar.update(active: active)
    }

    /// Get the active session's split tree for menu actions.
    func getSplitTree() -> SplitTreeController? {
        guard activeIndex >= 0 && activeIndex < sessions.count else { return nil }
        return sessions[activeIndex].splitTree
    }

    /// Open session count and active index, for keyboard session navigation.
    func sessionCount() -> Int { sessions.count }
    func activeSessionIndex() -> Int { activeIndex }

    /// Launch-screen helper: the live Claude state of the session whose worktree
    /// is `repoPath`. Returns `.idle` when that session isn't currently open, so
    /// the launch screen never shows a fabricated state.
    func launchState(repoPath: String) -> LaunchSessionState {
        guard let ws = sessions.first(where: { $0.config.repoPath == repoPath }) else { return .idle }
        guard let color = ws.statusColor else { return .active }
        if color == Theme.green { return .done }
        if color == Theme.red { return .awaiting }
        if color == Theme.amber { return .working }
        return .active
    }

    // MARK: - Socket Command Handling

    private func handleSocketCommand(_ command: SocketCommand, session ws: Session) -> Data? {
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

        case "session.notify":
            let colorName = command.command ?? "green"

            // "work done" on the active session is just noise — the user is
            // already looking at it. Drop the green tint so the active tab
            // doesn't suddenly change color on completion.
            let isActive = activeIndex >= 0 && activeIndex < sessions.count && sessions[activeIndex] === ws
            if isActive && colorName == "green" {
                return nil
            }

            let color: NSColor
            switch colorName {
            // Design palette: done = green, needs-input = red, working = amber.
            case "green": color = Theme.green
            case "red": color = Theme.red
            case "yellow": color = Theme.amber
            case "blue": color = Theme.accent
            case "orange": color = Theme.amber
            case "clear", "none", "reset": ws.statusColor = nil; ws.onStatusChanged?(); return nil
            default: color = Theme.green
            }
            ws.statusColor = color
            ws.onStatusChanged?()
            return nil

        default:
            return nil
        }
    }

    private func resolvePane(_ command: SocketCommand, in ws: Session) -> PaneViewController? {
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
