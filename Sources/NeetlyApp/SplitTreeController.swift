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
        pane.onSplit = { [weak self, weak pane] direction in
            guard let self, let pane else { return }
            self.splitPane(pane, direction: direction)
        }
        pane.onEmpty = { [weak self, weak pane] in
            guard let self, let pane else { return }
            self.collapsePane(pane)
        }
        return pane
    }

    /// Split an existing pane into two. The original stays on one side,
    /// a new empty terminal pane appears on the other.
    func splitPane(_ pane: PaneViewController, direction: SplitDirection) {
        let oldView = pane.view
        guard let parent = oldView.superview else { return }

        // Create new pane
        let newPane = makePaneController()
        newPane.addTerminalTab(command: "")

        // Create split view
        let splitView = NSSplitView()
        splitView.isVertical = (direction == .columns)
        splitView.dividerStyle = .thin
        splitView.frame = oldView.frame
        splitView.autoresizingMask = oldView.autoresizingMask

        // Replace old view with split view
        parent.replaceSubview(oldView, with: splitView)

        // Add both panes to the split
        oldView.autoresizingMask = [.width, .height]
        newPane.view.autoresizingMask = [.width, .height]
        splitView.addArrangedSubview(oldView)
        splitView.addArrangedSubview(newPane.view)

        // Equal split
        DispatchQueue.main.async {
            let half = splitView.isVertical
                ? splitView.bounds.width / 2
                : splitView.bounds.height / 2
            splitView.setPosition(half, ofDividerAt: 0)
        }

        // Trigger viewDidAppear for the new pane's terminal
        newPane.view.window?.makeFirstResponder(newPane.view)
    }

    /// When the last tab of a pane is closed, collapse it:
    /// remove the empty pane and promote the sibling to take the parent split's place.
    func collapsePane(_ pane: PaneViewController) {
        let emptyView = pane.view
        guard let splitView = emptyView.superview as? NSSplitView else {
            // Not inside a split — it's the root pane, nothing to collapse
            return
        }

        // Find the sibling view (the other child of the split)
        let siblings = splitView.arrangedSubviews
        guard let sibling = siblings.first(where: { $0 !== emptyView }) else { return }

        // Remove the empty pane
        paneControllers.removeValue(forKey: pane.paneId)
        pane.removeFromParent()

        // Replace the NSSplitView with the sibling in the parent
        guard let parent = splitView.superview else { return }
        sibling.removeFromSuperview()
        sibling.frame = splitView.frame
        sibling.autoresizingMask = splitView.autoresizingMask
        parent.replaceSubview(splitView, with: sibling)

        // Focus the sibling
        sibling.window?.makeFirstResponder(sibling)
    }

    /// Find a pane controller by its UUID string.
    func pane(for id: String) -> PaneViewController? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return paneControllers[uuid]
    }
}
