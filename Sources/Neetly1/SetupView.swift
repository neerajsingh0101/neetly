import SwiftUI

// MARK: - Screen Navigation

enum SetupScreen {
    case repoList
    case addRepo
    case workspaceName(RepoConfig)
}

// MARK: - Root Setup View

struct SetupView: View {
    @State private var screen: SetupScreen = .repoList
    @State private var repos: [RepoConfig] = []
    var onLaunch: (WorkspaceConfig) -> Void

    var body: some View {
        switch screen {
        case .repoList:
            RepoListScreen(
                repos: $repos,
                onSelectRepo: { repo in screen = .workspaceName(repo) },
                onAddRepo: { screen = .addRepo }
            )
            .onAppear { repos = RepoStore.shared.load() }

        case .addRepo:
            AddRepoScreen(
                onAdd: { repo in
                    RepoStore.shared.add(repo)
                    repos = RepoStore.shared.load()
                    screen = .repoList
                },
                onCancel: { screen = .repoList }
            )

        case .workspaceName(let repo):
            WorkspaceNameScreen(
                repo: repo,
                onStart: { workspaceName in
                    let parser = LayoutParser()
                    let dedented = dedent(repo.layoutText)
                    guard let layout = parser.parse(dedented) else { return }
                    let config = WorkspaceConfig(
                        repoPath: repo.path,
                        workspaceName: workspaceName,
                        layout: layout
                    )
                    onLaunch(config)
                },
                onBack: { screen = .repoList }
            )
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

// MARK: - Screen 1: Repo List

struct RepoListScreen: View {
    @Binding var repos: [RepoConfig]
    var onSelectRepo: (RepoConfig) -> Void
    var onAddRepo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("neetly1").font(.system(size: 24, weight: .bold, design: .monospaced))
                Spacer()
                Button(action: onAddRepo) {
                    Label("Add Repo", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(20)

            Divider()

            if repos.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No repos added yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Click \"Add Repo\" to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(repos) { repo in
                        Button(action: { onSelectRepo(repo) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(repo.name)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(repo.path)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            RepoStore.shared.remove(id: repos[i].id)
                        }
                        repos = RepoStore.shared.load()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Screen 2: Add Repo

struct AddRepoScreen: View {
    @State private var repoPath: String = ""
    @State private var layoutConfig: String = """
        split: columns
        left:
          run: claude
        right:
          run: bin/launch
        """
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Layout")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $layoutConfig)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 150)
                    .border(Color.gray.opacity(0.3))
            }

            if let error = errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
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
        let repo = RepoConfig(path: repoPath, layoutText: layoutConfig)
        onAdd(repo)
    }
}

// MARK: - Screen 3: Workspace Name

struct WorkspaceNameScreen: View {
    let repo: RepoConfig
    @State private var workspaceName: String = ""
    @FocusState private var isNameFocused: Bool
    var onStart: (String) -> Void
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
                .font(.system(size: 20, weight: .bold, design: .monospaced))

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace Name")
                    .font(.title3.weight(.semibold))
                TextField("my-feature", text: $workspaceName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .focused($isNameFocused)
                    .onSubmit {
                        let name = workspaceName.isEmpty ? "default" : workspaceName
                        onStart(name)
                    }
                Text("A workspace name could be the feature name or the bug you are working on.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Start") {
                    let name = workspaceName.isEmpty ? "default" : workspaceName
                    onStart(name)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 500, height: 300)
        .onAppear { isNameFocused = true }
    }
}
