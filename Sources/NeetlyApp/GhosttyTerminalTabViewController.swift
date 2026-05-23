import AppKit
import GhosttyTerminal
import GhosttyTheme

/// libghostty-backed terminal tab — a drop-in alternative to the SwiftTerm
/// `TerminalTabViewController`, selected by `TerminalEngine.current`.
///
/// libghostty's `.exec` backend spawns a real login shell in `repoPath`, so
/// there is no `cd` to send. Per-pane environment and the optional startup
/// command are injected by typing into that shell via `sendText` — the same
/// approach the SwiftTerm path already uses.
final class GhosttyTerminalTabViewController: NSViewController, TerminalTab {
    let tabId = UUID()
    let seqId = SeqCounter.shared.nextId()
    let command: String
    let repoPath: String
    let environment: [String: String]
    var onProcessExited: (() -> Void)?

    private var terminalView: TerminalView!
    private var hasStarted = false

    /// One ghostty runtime (`ghostty_app`) shared by every terminal tab.
    static let sharedController = TerminalController(configuration: makeConfiguration())

    /// Every live terminal tab, weakly held — so `reloadConfiguration()` can
    /// force each surface to repaint after a config change.
    private static let liveInstances = NSHashTable<GhosttyTerminalTabViewController>.weakObjects()

    /// Builds the ghostty terminal configuration from Neetly's
    /// `~/.config/neetly/terminal.json`, so ghostty matches the app's look.
    static func makeConfiguration() -> TerminalConfiguration {
        let cfg = TerminalConfig.load()
        return TerminalConfiguration { builder in
            builder.withFontFamily(cfg.fontFamily ?? "JetBrains Mono")
            builder.withFontSize(Float(cfg.fontSize ?? 17))
            if cfg.theme == TerminalConfig.neetlyThemeName {
                // The built-in Neetly theme — the app's design tokens as a
                // ghostty palette, so terminal content matches the chrome.
                builder.withBackground(NeetlyTerminalTheme.background)
                builder.withForeground(NeetlyTerminalTheme.foreground)
                builder.withCursorColor(NeetlyTerminalTheme.cursor)
                builder.withSelectionBackground(NeetlyTerminalTheme.selection)
                for index in NeetlyTerminalTheme.palette.keys.sorted() {
                    if let color = NeetlyTerminalTheme.palette[index] {
                        builder.withPalette(index, color: color)
                    }
                }
            } else if let themeName = cfg.theme,
               let theme = GhosttyThemeCatalog.theme(named: themeName) {
                // A picked theme owns every color. Theme hex values are bare
                // ("1e1e2e"); ghostty config wants a leading "#".
                func hex(_ value: String) -> String {
                    value.hasPrefix("#") ? value : "#" + value
                }
                builder.withBackground(hex(theme.background))
                builder.withForeground(hex(theme.foreground))
                if let cursor = theme.cursorColor { builder.withCursorColor(hex(cursor)) }
                if let cursorText = theme.cursorText { builder.withCursorText(hex(cursorText)) }
                if let selBg = theme.selectionBackground { builder.withSelectionBackground(hex(selBg)) }
                if let selFg = theme.selectionForeground { builder.withSelectionForeground(hex(selFg)) }
                for index in theme.palette.keys.sorted() {
                    if let color = theme.palette[index] {
                        builder.withPalette(index, color: hex(color))
                    }
                }
            } else {
                // No theme picked — the explicit terminal.json colors.
                if let bg = cfg.backgroundColor { builder.withBackground(bg) }
                if let fg = cfg.foregroundColor { builder.withForeground(fg) }
                if let sel = cfg.selectionColor { builder.withSelectionBackground(sel) }
                // Tint links by overriding ANSI palette blue (4) and bright
                // blue (12) — the indices Neetly's OSC-4 trick used.
                if let link = cfg.linkColor {
                    builder.withPalette(4, color: link)
                    builder.withPalette(12, color: link)
                }
            }
            // Advertise the universally-installed `xterm-256color` terminfo
            // entry rather than ghostty's own `xterm-ghostty`, so
            // vim/htop/lazygit work on every machine.
            builder.withCustom("term", "xterm-256color")
            // Let Neetly's menu own these shortcuts — ghostty's defaults
            // would otherwise swallow them before AppKit could route to the
            // menu: super+, (open_config) and super+q (quit, which has no
            // host integration in libghostty so the app would never quit).
            builder.withCustom("keybind", "super+,=unbind")
            builder.withCustom("keybind", "super+q=unbind")
        }
    }

    /// Re-reads `terminal.json` and live-applies it to every open ghostty
    /// terminal (and tabs created afterward). Call after the user changes
    /// terminal appearance in Settings or picks a theme.
    ///
    /// Uses `updateConfigSource` rather than `setTerminalConfiguration`: the
    /// latter merges the config over a base config, yielding duplicate keys
    /// that ghostty's parser can reject. This pushes one clean config and
    /// updates every open surface directly.
    static func reloadConfiguration() {
        sharedController.updateConfigSource(.generated(makeConfiguration().rendered))
        if let issue = sharedController.lastConfigurationIssue {
            NSLog("[neetly] terminal config rejected: \(issue)")
        }
        // updateConfigSource updates each surface's config but does not
        // trigger a redraw — an idle terminal keeps its old colors until it
        // next renders. Nudge every open terminal to repaint now.
        for instance in liveInstances.allObjects {
            instance.terminalView?.fitToSize()
        }
    }

    init(command: String, repoPath: String, environment: [String: String]) {
        self.command = command
        self.repoPath = repoPath
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let tv = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        terminalView = tv
        view = tv
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        terminalView.delegate = self
        terminalView.configuration = TerminalSurfaceOptions(
            backend: .exec, // real PTY + login shell, started in repoPath
            workingDirectory: repoPath
        )
        terminalView.controller = Self.sharedController
        Self.liveInstances.add(self)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !hasStarted {
            hasStarted = true
            startCommand()
        }
        focusTerminal()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        terminalView.fitToSize()
    }

    /// Inject this pane's environment + the optional startup command by typing
    /// into the freshly spawned shell. The 0.5s delay mirrors the SwiftTerm
    /// path — it gives the shell time to render its first prompt.
    private func startCommand() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }

            // Prepend the neetly CLI's directory to PATH so the `neetly`
            // command works inside the terminal, then export the pane env.
            let execDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                .deletingLastPathComponent().path
            var exports = "export PATH='\(Self.shellEscape(execDir))':\"$PATH\""
            for (key, value) in self.environment {
                exports += " \(key)='\(Self.shellEscape(value))'"
            }
            self.runLine(exports)

            guard !self.command.isEmpty else { return }
            self.runLine(self.command)
        }
    }

    /// Type `line` into the shell and submit it.
    ///
    /// libghostty wraps `sendText` in bracketed-paste markers whenever the
    /// shell has bracketed-paste mode on — which interactive shells do — so a
    /// trailing "\n" is pasted as literal text, not run. We therefore send the
    /// line as text and submit it with a synthesized Return key event, which
    /// goes through ghostty's key path (encoded to CR) exactly as if the user
    /// had pressed Return.
    private func runLine(_ line: String) {
        terminalView.sendText(line)
        pressReturn()
    }

    private func pressReturn() {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: terminalView.window?.windowNumber ?? 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36 // kVK_Return
        ) else { return }
        terminalView.keyDown(with: event)
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    // MARK: - TerminalTab

    func focusTerminal() {
        view.window?.makeFirstResponder(terminalView)
    }

    func sendText(_ text: String) {
        terminalView.sendText(text)
    }

    func terminateProcess() {
        // Tearing down the view frees the ghostty surface, which closes the
        // PTY and sends SIGHUP to the foreground process group — enough to
        // release ports in the common case. Explicit SIGTERM parity with the
        // SwiftTerm path is a follow-up (libghostty-spm doesn't expose the
        // child fd).
    }
}

// MARK: - Surface callbacks

extension GhosttyTerminalTabViewController:
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceResizeDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceOpenURLDelegate
{
    func terminalDidChangeTitle(_: String) {}

    func terminalDidResize(columns _: Int, rows _: Int) {}

    func terminalDidClose(processAlive _: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onProcessExited?()
        }
    }

    /// Cmd-click on a hyperlink (OSC 8 or auto-detected URL) — hand it to
    /// the system to open in the default browser. Without this conformance,
    /// libghostty surfaces the action but nothing happens, which is why PR
    /// links Claude prints stopped working under libghostty.
    func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
        guard let nsURL = URL(string: url) else { return }
        NSWorkspace.shared.open(nsURL)
    }
}
