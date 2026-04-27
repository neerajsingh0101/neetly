import Foundation

struct SavedSession: Codable, Equatable {
    let repoPath: String
    let repoName: String
    /// Free-form display label.
    let sessionName: String
    /// Sanitized identity / on-disk directory name. Unique within a repo.
    let worktreeName: String
    let layoutText: String
    let autoReloadOnFileChange: Bool
    var prInfo: GitHubPRInfo? = nil
    /// True if currently attached. Drives auto-restore on app launch.
    /// Detached sessions stay in the store so they remain in the list.
    var isOpen: Bool = true
}

class SessionStore {
    static let shared = SessionStore()

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/neetly")
    }()

    private var configFile: URL {
        configDir.appendingPathComponent("sessions.json")
    }

    func load() -> [SavedSession] {
        guard let data = try? Data(contentsOf: configFile),
              let sessions = try? JSONDecoder().decode([SavedSession].self, from: data) else {
            return []
        }
        return sessions
    }

    func save(_ sessions: [SavedSession]) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: configFile, options: .atomic)
        } catch {
            NSLog("SessionStore: failed to save: \(error)")
        }
    }

    func add(_ ws: SavedSession) {
        var all = load()
        all.removeAll { $0.repoPath == ws.repoPath && $0.worktreeName == ws.worktreeName }
        all.append(ws)
        save(all)
    }

    func remove(repoPath: String, worktreeName: String) {
        var all = load()
        all.removeAll { $0.repoPath == repoPath && $0.worktreeName == worktreeName }
        save(all)
    }

    /// Mark a session as detached so it doesn't auto-restore next launch,
    /// but keep its entry so it stays visible in the session list.
    func markClosed(repoPath: String, worktreeName: String) {
        var all = load()
        guard let idx = all.firstIndex(where: {
            $0.repoPath == repoPath && $0.worktreeName == worktreeName
        }) else { return }
        all[idx].isOpen = false
        save(all)
    }

    func updatePRInfo(repoPath: String, worktreeName: String, prInfo: GitHubPRInfo?) {
        var all = load()
        guard let idx = all.firstIndex(where: {
            $0.repoPath == repoPath && $0.worktreeName == worktreeName
        }) else { return }
        all[idx].prInfo = prInfo
        save(all)
    }
}
