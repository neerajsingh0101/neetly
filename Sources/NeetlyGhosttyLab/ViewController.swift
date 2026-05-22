import AppKit
import GhosttyTerminal

/// Hosts a single libghostty terminal surface running a real shell.
///
/// This mirrors libghostty-spm's own AppKit example, with one deliberate
/// change: the example uses the sandboxed `.inMemory` backend, while we
/// use `.exec` — which makes ghostty spawn a real PTY + login shell,
/// exactly what Neetly needs.
final class ViewController: NSViewController {
    /// `TerminalView` is libghostty-spm's typealias — `AppTerminalView` on macOS.
    private lazy var terminalView: TerminalView = .init(
        frame: NSRect(x: 0, y: 0, width: 820, height: 520)
    )

    /// Owns the ghostty app runtime, config resolution, and surface creation.
    private lazy var controller: TerminalController = .init()

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Order mirrors libghostty-spm's example: delegate, configuration,
        // then controller.
        terminalView.delegate = self
        terminalView.configuration = TerminalSurfaceOptions(
            backend: .exec, // real PTY + login shell
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        terminalView.controller = controller

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(terminalView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        terminalView.fitToSize()
    }
}

// MARK: - Terminal callbacks

extension ViewController:
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceResizeDelegate,
    TerminalSurfaceCloseDelegate
{
    func terminalDidChangeTitle(_ title: String) {
        view.window?.title = title.isEmpty ? "neetly-ghostty-lab" : title
    }

    func terminalDidResize(columns _: Int, rows _: Int) {}

    func terminalDidClose(processAlive _: Bool) {
        view.window?.close()
    }
}
