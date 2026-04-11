import SwiftUI

struct SetupView: View {
    @State private var repoPath: String = ""
    @State private var projectName: String = ""
    @State private var layoutConfig: String = """
        split: columns
        left:
          run: claude
        right:
          run: bin/launch
        """
    @State private var errorMessage: String?

    var onLaunch: (WorkspaceConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("neetly1")
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            // Repo path
            HStack {
                Text("Repository")
                    .frame(width: 80, alignment: .trailing)
                TextField("/path/to/repo", text: $repoPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") { pickRepo() }
            }

            // Project name
            HStack {
                Text("Project")
                    .frame(width: 80, alignment: .trailing)
                TextField("project-name", text: $projectName)
                    .textFieldStyle(.roundedBorder)
            }

            // Layout config
            VStack(alignment: .leading, spacing: 4) {
                Text("Layout")
                    .font(.headline)
                TextEditor(text: $layoutConfig)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 160)
                    .border(Color.gray.opacity(0.3))
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Launch") { launch() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 550, height: 450)
    }

    private func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a repository directory"
        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
            if projectName.isEmpty {
                projectName = url.lastPathComponent
            }
        }
    }

    private func launch() {
        errorMessage = nil

        guard !repoPath.isEmpty else {
            errorMessage = "Please select a repository."
            return
        }

        let parser = LayoutParser()
        // Dedent the config (strip common leading whitespace)
        let dedented = dedent(layoutConfig)
        guard let layout = parser.parse(dedented) else {
            errorMessage = "Could not parse layout config. Check the format."
            return
        }

        let name = projectName.isEmpty ? URL(fileURLWithPath: repoPath).lastPathComponent : projectName
        let config = WorkspaceConfig(repoPath: repoPath, projectName: name, layout: layout)
        onLaunch(config)
    }

    private func dedent(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let minIndent = nonEmptyLines.map { line in
            line.prefix(while: { $0 == " " || $0 == "\t" }).count
        }.min() ?? 0
        return lines.map { line in
            if line.count >= minIndent {
                return String(line.dropFirst(minIndent))
            }
            return line
        }.joined(separator: "\n")
    }
}
