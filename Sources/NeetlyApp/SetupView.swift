import AppKit
import SwiftUI

// MARK: - Screen Navigation

enum SetupScreen {
    case repoList
    case addRepo
    case editLayout(RepoConfig)
    case sessionList(RepoConfig)
    case sessionName(RepoConfig)
    case settings
    case activities
}

// MARK: - Root Setup View

struct SetupView: View {
    @State private var screen: SetupScreen
    @State private var repos: [RepoConfig] = []
    var onLaunch: (SessionConfig) -> Void

    init(initialScreen: SetupScreen = .repoList, onLaunch: @escaping (SessionConfig) -> Void) {
        _screen = State(initialValue: initialScreen)
        self.onLaunch = onLaunch
    }

    var body: some View {
        screenContent
            .background(Theme.bg0C)
            .tint(Theme.accentC)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var screenContent: some View {
        switch screen {
        case .repoList:
            RepoListScreen(
                repos: $repos,
                onAddRepo: { screen = .addRepo },
                onEditLayout: { repo in screen = .editLayout(repo) },
                onSettings: { screen = .settings },
                onActivities: { screen = .activities },
                onNewSession: { repo in screen = .sessionName(repo) },
                onLaunchSession: { repo, sessionName, worktreeName in
                    let parser = LayoutParser()
                    let dedented = dedent(repo.layoutText)
                    guard let layout = parser.parse(dedented) else { return }
                    let worktreePath = GitWorktree.worktreePath(repoName: repo.name, worktreeName: worktreeName)
                    let config = SessionConfig(
                        repoPath: worktreePath,
                        repoName: repo.name,
                        sessionName: sessionName,
                        worktreeName: worktreeName,
                        layout: layout,
                        layoutText: repo.layoutText,
                        autoReloadOnFileChange: true
                    )
                    onLaunch(config)
                }
            )
            .onAppear { repos = RepoStore.shared.load() }

        case .addRepo:
            AddRepoScreen(
                onAdd: { repo in
                    RepoStore.shared.add(repo)
                    repos = RepoStore.shared.load()
                    screen = .sessionName(repo)
                },
                onCancel: { screen = .repoList }
            )

        case .editLayout(let repo):
            EditLayoutScreen(
                repo: repo,
                onSave: { updated in
                    RepoStore.shared.update(updated)
                    repos = RepoStore.shared.load()
                    screen = .repoList
                },
                onCancel: { screen = .repoList }
            )

        case .sessionList(let repo):
            SessionListScreen(
                repo: repo,
                onSelectSession: { sessionName, worktreeName in
                    let parser = LayoutParser()
                    let dedented = dedent(repo.layoutText)
                    guard let layout = parser.parse(dedented) else { return }
                    let worktreePath = GitWorktree.worktreePath(repoName: repo.name, worktreeName: worktreeName)
                    let config = SessionConfig(
                        repoPath: worktreePath,
                        repoName: repo.name,
                        sessionName: sessionName,
                        worktreeName: worktreeName,
                        layout: layout,
                        layoutText: repo.layoutText,
                        autoReloadOnFileChange: true
                    )
                    onLaunch(config)
                },
                onAddSession: { screen = .sessionName(repo) },
                onBack: { screen = .repoList }
            )

        case .sessionName(let repo):
            SessionNameScreen(
                repo: repo,
                onStart: { sessionName, worktreeName, layoutText, autoReload, worktreePath in
                    let parser = LayoutParser()
                    let dedented = dedent(layoutText)
                    guard let layout = parser.parse(dedented) else { return }

                    NSLog("Session: using repoPath = \(worktreePath)")
                    let config = SessionConfig(
                        repoPath: worktreePath,
                        repoName: repo.name,
                        sessionName: sessionName,
                        worktreeName: worktreeName,
                        layout: layout,
                        layoutText: layoutText,
                        autoReloadOnFileChange: autoReload
                    )
                    ActivityStore.shared.log(.sessionCreated, repoName: repo.name, detail: sessionName)
                    onLaunch(config)
                },
                onBack: { screen = .repoList }
            )

        case .settings:
            SettingsScreen(onBack: { screen = .repoList })

        case .activities:
            ActivityScreen(onBack: { screen = .repoList })
        }
    }

    private func dedent(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let minIndent = nonEmpty.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        return lines.map { $0.count >= minIndent ? String($0.dropFirst(minIndent)) : $0 }
            .joined(separator: "\n")
    }
}

// MARK: - Window Sizer

/// Grows the hosting window downward to fit a target content height,
/// clamped to the screen's visible area (minus a bottom margin). Only
/// grows — never shrinks — so user manual resizes aren't fought.
private struct WindowHeightSizer: NSViewRepresentable {
    let targetHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let target = targetHeight
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }

            let bottomMargin: CGFloat = 80
            let baseHeight: CGFloat = 600
            let maxHeight = max(baseHeight, screen.visibleFrame.height - bottomMargin)
            let clamped = min(max(target, baseHeight), maxHeight)

            let current = window.frame
            guard clamped > current.height + 1 else { return }

            // Keep the title bar fixed; extend downward. If that would push
            // the bottom off-screen, pin to the visible frame's minY.
            let topY = current.maxY
            let newY = max(topY - clamped, screen.visibleFrame.minY)
            let newFrame = NSRect(x: current.minX, y: newY, width: current.width, height: clamped)
            window.setFrame(newFrame, display: true, animate: true)
        }
    }
}

// MARK: - Screen 1: Repo List

struct RepoListScreen: View {
    @Binding var repos: [RepoConfig]
    var onAddRepo: () -> Void
    var onEditLayout: (RepoConfig) -> Void
    var onSettings: () -> Void
    var onActivities: () -> Void
    var onNewSession: (RepoConfig) -> Void
    /// (repo, sessionName, worktreeName)
    var onLaunchSession: (RepoConfig, String, String) -> Void

    @State private var expanded: Set<UUID> = []
    @State private var sessionsExpanded: Set<UUID> = []
    @State private var sessionsByRepo: [String: [SessionListEntry]] = [:]
    @State private var pendingDelete: PendingSessionDelete?
    @State private var pendingRepoDelete: RepoConfig?

    private var sortedRepos: [RepoConfig] {
        repos.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private var totalSessions: Int { sessionsByRepo.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(sortedRepos) { repo in
                        RepoGroupRow(
                            repo: repo,
                            sessions: sessionsByRepo[repo.name] ?? [],
                            isExpanded: expanded.contains(repo.id),
                            showSessions: sessionsExpanded.contains(repo.id),
                            onToggle: { toggle(repo) },
                            onShowSessions: { sessionsExpanded.insert(repo.id) },
                            onLaunch: { entry in onLaunchSession(repo, entry.sessionName, entry.worktreeName) },
                            onNewSession: { onNewSession(repo) },
                            onEditLayout: { onEditLayout(repo) },
                            onDeleteRepo: { pendingRepoDelete = repo },
                            onDeleteSession: { entry in pendingDelete = PendingSessionDelete(repo: repo, entry: entry) }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 720, minHeight: 600)
        .background(Theme.bg0C)
        .background(WindowHeightSizer(targetHeight: targetHeight))
        .onAppear { reload() }
        .alert(
            "Delete session?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { p in
            Button("Delete", role: .destructive) { performDelete(p) }
            Button("Cancel", role: .cancel) { }
        } message: { p in
            Text("“\(p.entry.sessionName)” and its associated worktree will be permanently deleted.")
        }
        .alert(
            "Delete repo?",
            isPresented: Binding(
                get: { pendingRepoDelete != nil },
                set: { if !$0 { pendingRepoDelete = nil } }
            ),
            presenting: pendingRepoDelete
        ) { repo in
            Button("Delete", role: .destructive) { performRepoDelete(repo) }
            Button("Cancel", role: .cancel) { }
        } message: { repo in
            Text("“\(repo.name)” will be removed from Neetly and all worktrees associated with the repo will be permanently deleted.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                HStack(spacing: 0) {
                    Text("Neetly")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.fg1C)
                    BlinkingCaret()
                }
                Spacer()
                Button(action: onAddRepo) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").foregroundColor(Theme.accentC)
                        Text("Add Repo").foregroundColor(Theme.fg1C)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg2C))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line2C, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 18) {
                textButton("list.bullet.clipboard", "Activities", action: onActivities)
                textButton("gearshape", "Settings", action: onSettings)
                Spacer()
                summary
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private func textButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 13))
            .foregroundColor(Theme.fg3C)
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        HStack(spacing: 0) {
            Text("\(repos.count) repos · \(totalSessions) sessions")
                .foregroundColor(Theme.fg3C)
        }
        .font(.system(size: 13, design: .monospaced))
    }

    // MARK: State

    private var targetHeight: CGFloat {
        var h: CGFloat = 130  // header
        for repo in sortedRepos {
            h += 52
            if expanded.contains(repo.id) {
                let sessionCount = (sessionsByRepo[repo.name] ?? []).count
                if sessionCount == 0 {
                    h += 38                                          // just "+ new session"
                } else if sessionsExpanded.contains(repo.id) {
                    h += CGFloat(sessionCount) * 40 + 38             // full list + "+ new session"
                } else {
                    h += 40 + 38                                     // "expand existing…" link + "+ new session"
                }
            }
        }
        return h + 32
    }

    private func toggle(_ repo: RepoConfig) {
        if expanded.contains(repo.id) {
            expanded.remove(repo.id)
            // Tuck the sessions list back away so the next expand starts
            // with only the "+ new session" + "expand existing…" link.
            sessionsExpanded.remove(repo.id)
        } else {
            expanded.insert(repo.id)
        }
    }

    private func reload() {
        var map: [String: [SessionListEntry]] = [:]
        for s in SessionStore.shared.load() {
            map[s.repoName, default: []].append(
                SessionListEntry(sessionName: s.sessionName, worktreeName: s.worktreeName, prInfo: s.prInfo)
            )
        }
        sessionsByRepo = map
        // Expand repos that have sessions by default.
        expanded = Set(repos.filter { !(map[$0.name] ?? []).isEmpty }.map { $0.id })
    }

    private func performDelete(_ p: PendingSessionDelete) {
        let worktreeName = p.entry.worktreeName
        ActivityStore.shared.log(.sessionDeleted, repoName: p.repo.name, detail: p.entry.sessionName)
        pendingDelete = nil

        let worktreePath = GitWorktree.worktreePath(repoName: p.repo.name, worktreeName: worktreeName)
        SessionStore.shared.remove(repoPath: worktreePath, worktreeName: worktreeName)
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.sessionWindowController?.closeSessionByPath(worktreePath)
        }
        let repoPath = p.repo.path
        let repoName = p.repo.name
        DispatchQueue.global(qos: .userInitiated).async {
            _ = GitWorktree.deleteWorktree(parentRepoPath: repoPath, repoName: repoName, worktreeName: worktreeName)
        }
        reload()
    }

    /// Remove a repo from neetly and delete every worktree it created. The
    /// original repo checkout (`repo.path`) is never touched.
    private func performRepoDelete(_ repo: RepoConfig) {
        let worktrees = GitWorktree.listWorktrees(for: repo.name)
        for wt in worktrees {
            let path = GitWorktree.worktreePath(repoName: repo.name, worktreeName: wt)
            SessionStore.shared.remove(repoPath: path, worktreeName: wt)
            (NSApp.delegate as? AppDelegate)?.sessionWindowController?.closeSessionByPath(path)
            ActivityStore.shared.log(.sessionDeleted, repoName: repo.name, detail: wt)
        }
        RepoStore.shared.remove(id: repo.id)
        pendingRepoDelete = nil

        let repoPath = repo.path
        let repoName = repo.name
        DispatchQueue.global(qos: .userInitiated).async {
            for wt in worktrees {
                _ = GitWorktree.deleteWorktree(parentRepoPath: repoPath, repoName: repoName, worktreeName: wt)
            }
            // Remove the now-empty per-repo worktrees folder so nothing is orphaned.
            let parent = "\(NeetlySettings.shared.worktreeBaseDir)/\(repoName)"
            try? FileManager.default.removeItem(atPath: parent)
        }
        repos = RepoStore.shared.load()
        reload()
    }

}

private struct PendingSessionDelete: Identifiable {
    let repo: RepoConfig
    let entry: SessionListEntry
    var id: String { entry.worktreeName }
}

// MARK: - Repo group (expandable)

private struct RepoGroupRow: View {
    let repo: RepoConfig
    let sessions: [SessionListEntry]
    let isExpanded: Bool
    let showSessions: Bool
    var onToggle: () -> Void
    var onShowSessions: () -> Void
    var onLaunch: (SessionListEntry) -> Void
    var onNewSession: () -> Void
    var onEditLayout: () -> Void
    var onDeleteRepo: () -> Void
    var onDeleteSession: (SessionListEntry) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onToggle) {
                    HStack(spacing: 10) {
                        Text(repo.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.fg1C)
                        Text(repo.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(Theme.fg4C)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Edit Layout", action: onEditLayout)
                    Divider()
                    Button("Delete Repo", role: .destructive, action: onDeleteRepo)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.fg4C)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.fg4C)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 10).fill(isExpanded ? Theme.bg2C : Color.clear))

            if isExpanded {
                if showSessions {
                    ForEach(sessions) { entry in
                        LaunchSessionRow(
                            repoName: repo.name,
                            entry: entry,
                            onLaunch: { onLaunch(entry) },
                            onDelete: { onDeleteSession(entry) }
                        )
                    }
                } else if !sessions.isEmpty {
                    // Existing sessions stay tucked away behind a link by
                    // default — click to reveal, then the link disappears.
                    Button(action: onShowSessions) {
                        HStack(spacing: 7) {
                            Image(systemName: "chevron.right")
                            Text("expand existing sessions list")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(Theme.fg4C)
                        .padding(.leading, 42)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onNewSession) {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                        Text("new session")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Theme.fg4C)
                    .padding(.leading, 42)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LaunchSessionRow: View {
    let repoName: String
    let entry: SessionListEntry
    var onLaunch: () -> Void
    var onDelete: () -> Void
    @State private var hovering = false

    private var state: LaunchSessionState {
        liveLaunchState(repoName: repoName, worktreeName: entry.worktreeName)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onLaunch) {
                HStack(spacing: 12) {
                    Circle().fill(launchStateColor(state)).frame(width: 7, height: 7)
                        .padding(.leading, 28)
                    Text(entry.sessionName)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.fg2C)
                    Spacer(minLength: 16)
                    Text(launchStateLabel(state))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(launchStateColor(state))
                        .frame(width: 72, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.fg4C)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete Session")
        }
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(hovering ? Theme.bg1C : Color.clear)
        .onHover { hovering = $0 }
    }
}

// MARK: - Launch-state styling + lookup

private func launchStateColor(_ s: LaunchSessionState) -> Color {
    switch s {
    case .done:     return Theme.greenC
    case .awaiting: return Theme.redC
    case .active:   return Theme.accentC
    case .detached: return Theme.fg4C
    }
}

private func launchStateLabel(_ s: LaunchSessionState) -> String {
    switch s {
    case .done:     return "done"
    case .awaiting: return "awaiting"
    case .active:   return "active"
    case .detached: return "detached"
    }
}

/// The live Claude state of a listed session, via the open session window.
/// Returns `.detached` when the session isn't currently open.
private func liveLaunchState(repoName: String, worktreeName: String) -> LaunchSessionState {
    let path = GitWorktree.worktreePath(repoName: repoName, worktreeName: worktreeName)
    return (NSApp.delegate as? AppDelegate)?.sessionWindowController?.launchState(repoPath: path) ?? .detached
}

// MARK: - Blinking caret

private struct BlinkingCaret: View {
    @State private var on = true
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Theme.accentC)
            .frame(width: 4, height: 32)
            .padding(.leading, 5)
            .opacity(on ? 1 : 0)
            .onReceive(Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()) { _ in
                on.toggle()
            }
    }
}

// MARK: - Screen 2: Add Repo

struct AddRepoScreen: View {
    @State private var repoPath: String = ""
    @State private var layoutConfig: String = """
        split: columns
        left:
          size: 40%
          run: claude --dangerously-skip-permissions
        right:
          run: bin/setup && bin/launch --neetly
        """
    @State private var pullMain: Bool = true
    @State private var errorMessage: String?
    var onAdd: (RepoConfig) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onCancel) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Add Repo").font(.headline)
                Spacer()
            }

            HStack {
                TextField("/path/to/repo", text: $repoPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") { pickRepo() }
            }

            Toggle(isOn: $pullMain) {
                Text("Always start work from the main branch and always do a git pull on main branch before starting the work.")
                    .font(.system(size: 13))
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Layout")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $layoutConfig)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 150)
                    .border(Theme.line1C)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Button("Add Repo") { addRepo() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }

    private func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a repository directory"
        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
        }
    }

    private func addRepo() {
        errorMessage = nil
        guard !repoPath.isEmpty else {
            errorMessage = "Please select a repository."
            return
        }
        let repo = RepoConfig(path: repoPath, layoutText: layoutConfig, pullMainBeforeWork: pullMain)
        onAdd(repo)
    }
}

// MARK: - Screen 3: Session Name

struct SessionNameScreen: View {
    let repo: RepoConfig
    @State private var sessionName: String = ""
    @State private var layoutText: String = ""
    @State private var autoReload: Bool = true
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool
    /// (sessionName, worktreeName, layoutText, autoReload, worktreePath)
    var onStart: (String, String, String, Bool, String) -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Spacer()
            }

            Text(repo.name)
                .font(.system(size: 29, weight: .bold, design: .monospaced))

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("New Session Name")
                    .font(.system(size: 22, weight: .semibold))
                TextField("", text: $sessionName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 19))
                    .focused($isNameFocused)
                    .onSubmit { startSession() }
                    .disabled(isLoading)
                    .onChange(of: sessionName) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if trimmed.count > 60 {
                            errorMessage = "Session name must be 60 characters or fewer (current: \(trimmed.count))."
                        } else {
                            errorMessage = nil
                        }
                    }
                Text("A session name could be the feature name or the GitHub issue number you are working on.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $autoReload) {
                    Text("Auto-reload browser on file changes")
                        .font(.system(size: 17))
                }
                Text("WKWebView doesn't support HMR. When enabled, browser tabs reload automatically when JavaScript files change in the repo.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Layout")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.top, 8)
                TextEditor(text: $layoutText)
                    .font(.system(size: 15, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(Theme.line1C)
            }

            Spacer()

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 20))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.green)
                    Text("Creating session...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Button("Start") { startSession() }
                        .keyboardShortcut(.return)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            isNameFocused = true
            layoutText = repo.layoutText
        }
    }

    private func startSession() {
        guard !isLoading else { return }
        errorMessage = nil

        let name = sessionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "Please provide a session name."
            return
        }
        guard name.count <= 60 else {
            errorMessage = "Session name must be 60 characters or fewer (current: \(name.count))."
            return
        }

        let worktreeName = GitWorktree.uniqueWorktreeName(for: repo.name, baseName: name)
        guard !worktreeName.isEmpty else {
            errorMessage = "Session name produces an empty worktree slug — try different characters."
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Create git worktree (runs git checkout, pull, worktree add)
            let git = GitWorktree(repoPath: repo.path)
            let result = git.createWorktree(worktreeName: worktreeName, pullMain: repo.pullMainBeforeWork)

            DispatchQueue.main.async {
                switch result {
                case .success(let path):
                    onStart(name, worktreeName, layoutText, autoReload, path)
                case .failure(let message):
                    errorMessage = message
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Screen 4: Edit Layout

struct EditLayoutScreen: View {
    let repo: RepoConfig
    @State private var layoutText: String = ""
    @State private var pullMain: Bool = true
    var onSave: (RepoConfig) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onCancel) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Text(repo.name)
                .font(.system(size: 29, weight: .bold, design: .monospaced))

            Toggle(isOn: $pullMain) {
                Text("Always start work from the main branch and always do a git pull on main branch before starting the work.")
                    .font(.system(size: 13))
            }
            .padding(.top, 8)

            Text("Default Layout")
                .font(.system(size: 18, weight: .semibold))

            TextEditor(text: $layoutText)
                .font(.system(size: 15, design: .monospaced))
                .border(Theme.line1C)

            HStack {
                Spacer()
                Button("Save") {
                    let updated = RepoConfig(id: repo.id, path: repo.path, name: repo.name, layoutText: layoutText, pullMainBeforeWork: pullMain)
                    onSave(updated)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            layoutText = repo.layoutText
            pullMain = repo.pullMainBeforeWork
        }
    }
}

// MARK: - Screen 5: Session List (existing sessions for a repo)

struct SessionListEntry: Identifiable {
    let sessionName: String
    let worktreeName: String
    var prInfo: GitHubPRInfo?
    var id: String { worktreeName }
}

struct SessionListScreen: View {
    let repo: RepoConfig
    @State private var sessions: [SessionListEntry] = []
    @State private var sessionToDelete: SessionListEntry?
    /// Called with (sessionName, worktreeName).
    var onSelectSession: (String, String) -> Void
    var onAddSession: () -> Void
    var onBack: () -> Void

    private func loadSessions() -> [SessionListEntry] {
        return SessionStore.shared.load()
            .filter { $0.repoName == repo.name }
            .map { SessionListEntry(sessionName: $0.sessionName, worktreeName: $0.worktreeName, prInfo: $0.prInfo) }
    }

    private func fetchMissingPRInfo() {
        let repoName = repo.name
        for entry in sessions where entry.prInfo == nil {
            let worktreePath = GitWorktree.worktreePath(repoName: repoName, worktreeName: entry.worktreeName)
            let worktreeName = entry.worktreeName
            GitHubPRResolver.resolve(worktreePath: worktreePath) { info in
                guard let info = info else { return }
                if let idx = sessions.firstIndex(where: { $0.worktreeName == worktreeName }) {
                    sessions[idx].prInfo = info
                }
                SessionStore.shared.updatePRInfo(
                    repoPath: worktreePath,
                    worktreeName: worktreeName,
                    prInfo: info
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onAddSession) {
                    Label("Add Session", systemImage: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)

            HStack {
                Text(repo.name)
                    .font(.system(size: 29, weight: .bold, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if sessions.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("No sessions yet")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Click \"Add Session\" to create one")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(sessions) { entry in
                        Button(action: { onSelectSession(entry.sessionName, entry.worktreeName) }) {
                            HStack {
                                HStack(spacing: 10) {
                                    Text(entry.sessionName)
                                        .font(.system(size: 22, weight: .semibold))
                                    if let pr = entry.prInfo {
                                        PRBadge(prInfo: pr)
                                    }
                                    Menu {
                                        Button(role: .destructive, action: {
                                            sessionToDelete = entry
                                        }) {
                                            Label("Delete Session", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.primary.opacity(0.6))
                                            .frame(width: 26, height: 26)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(HoverButtonStyle())
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            sessions = loadSessions()
            fetchMissingPRInfo()
        }
        .alert(
            "Delete session?",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            presenting: sessionToDelete
        ) { target in
            Button("Delete", role: .destructive) {
                let sessionLabel = target.sessionName
                let worktreeName = target.worktreeName
                ActivityStore.shared.log(.sessionDeleted, repoName: repo.name, detail: sessionLabel)
                sessions.removeAll { $0.worktreeName == worktreeName }

                // Close the session if currently open (must be on main thread)
                let worktreePath = GitWorktree.worktreePath(repoName: repo.name, worktreeName: worktreeName)
                SessionStore.shared.remove(repoPath: worktreePath, worktreeName: worktreeName)
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.sessionWindowController?.closeSessionByPath(worktreePath)
                }

                // Run the actual deletion in the background
                let repoPath = repo.path
                let repoName = repo.name
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = GitWorktree.deleteWorktree(
                        parentRepoPath: repoPath,
                        repoName: repoName,
                        worktreeName: worktreeName
                    )
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: { target in
            Text("“\(target.sessionName)” and its associated worktree will be permanently deleted.")
        }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @State private var worktreeDir: String = NeetlySettings.shared.worktreeBaseDir
    @State private var diffCommand: String = NeetlySettings.shared.diffCommand
    @State private var postCreateCommand: String = NeetlySettings.shared.postWorktreeCreateCommand
    @State private var fontSize: Int = Int(TerminalConfig.load().fontSize ?? 17)
    @State private var themeName: String = TerminalConfig.load().theme ?? TerminalConfig.defaultThemeName
    @State private var showingThemePicker = false
    @State private var worktreeError: String?
    @FocusState private var focusedField: Field?
    var onBack: () -> Void

    private enum Field { case worktreeDir, postCreate, diffCommand }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(20)

            Text("Neetly")
                .font(.system(size: 29, weight: .bold, design: .monospaced))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.top, 20)

                    // Worktree directory
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Worktree Directory")
                            .font(.system(size: 16, weight: .medium))
                        Text("The directory where Neetly creates git worktrees for your sessions.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("", text: $worktreeDir)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 15, design: .monospaced))
                                .focused($focusedField, equals: .worktreeDir)
                                .onSubmit { commitWorktreeDir() }
                            Button("Browse...") { pickDirectory() }
                        }
                        if let worktreeError {
                            Text(worktreeError)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                    }

                    // Post-create command
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Post-Create Command")
                            .font(.system(size: 16, weight: .medium))
                        Text("Runs after a new worktree is created. Use $WORKTREE_DIRECTORY for the worktree's absolute path. Leave blank to skip. A common use case is running mise trust $WORKTREE_DIRECTORY for the folks who use mise to manage their Ruby versions.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TextField("e.g. mise trust $WORKTREE_DIRECTORY", text: $postCreateCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, design: .monospaced))
                            .focused($focusedField, equals: .postCreate)
                            .onSubmit { commitPostCreate() }
                    }

                    Divider()

                    // Cmd+G: Open Diff
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Open Diff")
                                .font(.system(size: 16, weight: .medium))
                            Text("Cmd+G")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.bg3C)
                                .cornerRadius(4)
                        }
                        Text("Opens a terminal in the last pane with this command and maximizes it.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TextField("", text: $diffCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, design: .monospaced))
                            .focused($focusedField, equals: .diffCommand)
                            .onSubmit { commitDiffCommand() }
                    }

                    // Cmd+Shift+G: Close Diff (read-only)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Close Diff")
                                .font(.system(size: 16, weight: .medium))
                            Text("Cmd+Shift+G")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.bg3C)
                                .cornerRadius(4)
                        }
                        Text("Unmaximizes the pane and closes the active tab. This is not configurable.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Terminal font size
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terminal Font Size")
                            .font(.system(size: 16, weight: .medium))
                        Text("Point size for text in terminal tabs. Changes apply to open terminals immediately.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Stepper(value: $fontSize, in: 8 ... 32) {
                            Text("\(fontSize) pt")
                                .font(.system(size: 15, design: .monospaced))
                        }
                        .frame(width: 130, alignment: .leading)
                    }

                    Divider()

                    // Terminal theme — pick any of the catalog themes.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Terminal Theme")
                            .font(.system(size: 16, weight: .medium))
                        Text("Colors for terminal tabs. Pick any catalog theme; changes apply to open terminals immediately.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        HStack(spacing: 10) {
                            Text(themeName)
                                .font(.system(size: 15, design: .monospaced))
                                .foregroundColor(.secondary)
                            Button("Choose…") { showingThemePicker = true }
                                .popover(isPresented: $showingThemePicker, arrowEdge: .bottom) {
                                    ThemePickerView()
                                }
                        }
                    }

                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onChange(of: fontSize) { _, _ in commitFontSize() }
        .onChange(of: showingThemePicker) { _, isShowing in
            // Reflect the picked theme (and whether to show the custom wells)
            // when the popover closes.
            if !isShowing {
                themeName = TerminalConfig.load().theme ?? TerminalConfig.defaultThemeName
            }
        }
        .onChange(of: focusedField) { previous, _ in
            // Commit a field's value as soon as focus leaves it.
            switch previous {
            case .worktreeDir: commitWorktreeDir()
            case .postCreate: commitPostCreate()
            case .diffCommand: commitDiffCommand()
            case .none: break
            }
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the directory for worktrees"
        if panel.runModal() == .OK, let url = panel.url {
            worktreeDir = url.path
            commitWorktreeDir()
        }
    }

    // Each setting commits the moment the user finishes editing it — on Return
    // or when focus leaves the field — so there is no Save button.

    private func commitWorktreeDir() {
        let path = worktreeDir.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            worktreeError = "Please provide a directory path."
            return
        }
        let expanded = NSString(string: path).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir),
              isDir.boolValue
        else {
            worktreeError = "Directory does not exist: \(expanded)"
            return
        }
        worktreeError = nil
        worktreeDir = expanded
        NeetlySettings.shared.setWorktreeBaseDir(expanded)
    }

    private func commitDiffCommand() {
        let cmd = diffCommand.trimmingCharacters(in: .whitespaces)
        NeetlySettings.shared.setDiffCommand(cmd.isEmpty ? NeetlySettings.defaultDiffCommand : cmd)
    }

    private func commitPostCreate() {
        NeetlySettings.shared.setPostWorktreeCreateCommand(
            postCreateCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func commitFontSize() {
        var config = TerminalConfig.load()
        config.fontSize = CGFloat(fontSize)
        config.save()
        if TerminalEngine.current == .ghostty {
            GhosttyTerminalTabViewController.reloadConfiguration()
        }
    }

}

// MARK: - Activities

struct ActivityScreen: View {
    @State private var activities: [Activity] = []
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(20)

            HStack {
                Text("Activities")
                    .font(.system(size: 29, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if activities.isEmpty {
                Spacer()
                Text("No activities yet")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(activities) { activity in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: activityIcon(activity.kind))
                                .font(.system(size: 14))
                                .foregroundColor(activityColor(activity.kind))
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 4) {
                                activityText(activity)
                                    .font(.system(size: 15))
                                Text(formatDate(activity.timestamp))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            activities = ActivityStore.shared.load()
        }
    }

    @ViewBuilder
    private func activityText(_ activity: Activity) -> some View {
        if activity.kind == .prOpened, let urlStr = activity.prURL, let url = URL(string: urlStr) {
            let state = activity.prState.map { " (\($0))" } ?? ""
            HStack(spacing: 0) {
                Text("Opened PR ")
                Text(verbatim: "#\(activity.detail)\(state)")
                    .foregroundColor(Theme.accentC)
                    .underline()
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                Text(" for repo \(activity.repoName).")
            }
        } else {
            Text(activity.description)
        }
    }

    private func activityIcon(_ kind: Activity.Kind) -> String {
        switch kind {
        case .sessionCreated: return "plus.circle.fill"
        case .sessionDeleted: return "trash.circle.fill"
        case .prOpened:         return "arrow.triangle.pull"
        }
    }

    private func activityColor(_ kind: Activity.Kind) -> Color {
        switch kind {
        case .sessionCreated: return Theme.greenC
        case .sessionDeleted: return Theme.redC
        case .prOpened:         return Theme.violetC
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - PR Badge

struct PRBadge: View {
    let prInfo: GitHubPRInfo

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "PR #\(prInfo.number) (\(stateLabel))")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .help("#\(prInfo.number) \(prInfo.title)")
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            if let url = URL(string: prInfo.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var color: Color {
        switch prInfo.state {
        case .open:   return Theme.greenC
        case .draft:  return Theme.fg3C
        case .merged: return Theme.violetC
        case .closed: return Theme.redC
        }
    }

    private var stateLabel: String {
        switch prInfo.state {
        case .open:   return "Open"
        case .draft:  return "Draft"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }
}

// MARK: - Hover Button Style

struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
