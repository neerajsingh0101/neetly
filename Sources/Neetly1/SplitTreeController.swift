import AppKit

/// Recursively builds NSSplitView hierarchy from a LayoutNode tree.
class SplitTreeController: NSViewController {
    let layout: LayoutNode
    let repoPath: String
    let socketServer: SocketServer
    /// All pane controllers keyed by pane UUID, for socket command routing.
    private(set) var paneControllers: [UUID: PaneViewController] = [:]

    init(layout: LayoutNode, repoPath: String, socketServer: SocketServer) {
        self.layout = layout
        self.repoPath = repoPath
        self.socketServer = socketServer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = buildView(from: layout)
    }

    private func buildView(from node: LayoutNode) -> NSView {
        switch node {
        case .run(let command):
            let pane = makePaneController()
            pane.addTerminalTab(command: command)
            return pane.view

        case .visit(let url):
            let pane = makePaneController()
            pane.addBrowserTab(url: url)
            return pane.view

        case .tabs(let children):
            let pane = makePaneController()
            for child in children {
                switch child {
                case .run(let command):
                    pane.addTerminalTab(command: command)
                case .visit(let url):
                    pane.addBrowserTab(url: url)
                default:
                    break
                }
            }
            // Select the first tab
            if !children.isEmpty { pane.selectTab(at: 0) }
            return pane.view

        case .split(let direction, let first, let second):
            let splitView = NSSplitView()
            splitView.isVertical = (direction == .columns)
            splitView.dividerStyle = .thin
            splitView.autoresizingMask = [.width, .height]

            let firstView = buildView(from: first)
            let secondView = buildView(from: second)

            splitView.addArrangedSubview(firstView)
            splitView.addArrangedSubview(secondView)

            // Equal split by default
            DispatchQueue.main.async {
                let half = splitView.isVertical
                    ? splitView.bounds.width / 2
                    : splitView.bounds.height / 2
                splitView.setPosition(half, ofDividerAt: 0)
            }

            return splitView
        }
    }

    private func makePaneController() -> PaneViewController {
        let pane = PaneViewController(repoPath: repoPath, socketServer: socketServer)
        addChild(pane)
        paneControllers[pane.paneId] = pane
        return pane
    }

    /// Find a pane controller by its UUID string.
    func pane(for id: String) -> PaneViewController? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return paneControllers[uuid]
    }
}
