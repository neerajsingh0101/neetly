import Foundation

struct Activity: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: Kind
    let repoName: String
    let detail: String

    enum Kind: String, Codable {
        case workspaceCreated
        case workspaceDeleted
        case prOpened
    }

    var description: String {
        switch kind {
        case .workspaceCreated:
            return "Created workspace \(detail) for repo \(repoName)"
        case .workspaceDeleted:
            return "Deleted workspace \(detail) from repo \(repoName)"
        case .prOpened:
            return "Opened PR #\(detail) for repo \(repoName)"
        }
    }
}

class ActivityStore {
    static let shared = ActivityStore()

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/neetly")
    }()

    private var configFile: URL {
        configDir.appendingPathComponent("activities.json")
    }

    func load() -> [Activity] {
        guard let data = try? Data(contentsOf: configFile),
              let activities = try? JSONDecoder().decode([Activity].self, from: data) else {
            return []
        }
        return activities.sorted { $0.timestamp > $1.timestamp }
    }

    private func save(_ activities: [Activity]) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(activities)
            try data.write(to: configFile, options: .atomic)
        } catch {
            NSLog("ActivityStore: failed to save: \(error)")
        }
    }

    func log(_ kind: Activity.Kind, repoName: String, detail: String) {
        var all = load()
        let activity = Activity(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            repoName: repoName,
            detail: detail
        )
        all.insert(activity, at: 0)
        // Keep last 200 activities
        if all.count > 200 { all = Array(all.prefix(200)) }
        save(all)
    }
}
