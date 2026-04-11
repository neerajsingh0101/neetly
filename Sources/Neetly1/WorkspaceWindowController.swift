import AppKit

class WorkspaceWindowController: NSWindowController {
    let config: WorkspaceConfig
    let socketServer: SocketServer
    var splitTree: SplitTreeController!

    init(config: WorkspaceConfig, socketServer: SocketServer) {
        self.config = config
        self.socketServer = socketServer

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly1 - \(config.projectName)"
        window.center()
        window.setFrameAutosaveName("WorkspaceWindow")
        super.init(window: window)

        setupContent()
        setupSocketHandler()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        splitTree = SplitTreeController(
            layout: config.layout,
            repoPath: config.repoPath,
            socketServer: socketServer
        )

        // Load the split tree view
        splitTree.loadViewIfNeeded()
        splitTree.view.frame = window!.contentView!.bounds
        splitTree.view.autoresizingMask = [.width, .height]
        window!.contentView!.addSubview(splitTree.view)
    }

    private func setupSocketHandler() {
        socketServer.onCommand = { [weak self] command in
            self?.handleSocketCommand(command)
        }
    }

    private func handleSocketCommand(_ command: SocketCommand) {
        switch command.action {
        case "browser.open":
            guard let url = command.url else { return }
            if let pane = splitTree.pane(for: command.paneId) {
                pane.addBrowserTab(url: url)
            } else {
                // If pane not found, add to first available pane
                if let firstPane = splitTree.paneControllers.values.first {
                    firstPane.addBrowserTab(url: url)
                }
            }

        case "terminal.run":
            guard let cmd = command.command else { return }
            if let pane = splitTree.pane(for: command.paneId) {
                pane.addTerminalTab(command: cmd)
            }

        default:
            NSLog("Unknown socket command: \(command.action)")
        }
    }
}
