import Foundation

// MARK: - Layout Model

enum SplitDirection {
    case columns  // left | right
    case rows     // top / bottom
}

indirect enum LayoutNode {
    case run(command: String)
    case visit(url: String)
    case split(direction: SplitDirection, first: LayoutNode, second: LayoutNode)
}

// MARK: - Workspace Config

struct WorkspaceConfig {
    let repoPath: String
    let projectName: String
    let layout: LayoutNode
}

// MARK: - Socket Command

struct SocketCommand: Codable {
    let action: String
    let paneId: String
    let url: String?
    let command: String?
}

// MARK: - Pane Tab

enum PaneTabKind {
    case terminal
    case browser
}

struct PaneTabInfo {
    let id: UUID
    let kind: PaneTabKind
    var title: String
}
