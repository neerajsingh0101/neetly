import AppKit

/// The interface `PaneViewController` and `AppDelegate` use to drive a terminal
/// tab — implemented by both the SwiftTerm-backed `TerminalTabViewController`
/// and the libghostty-backed `GhosttyTerminalTabViewController`, so the rest of
/// the app is engine-agnostic.
protocol TerminalTab: NSViewController {
    var tabId: UUID { get }
    var seqId: Int { get }
    var command: String { get }
    var onProcessExited: (() -> Void)? { get set }
    func focusTerminal()
    func sendText(_ text: String)
    /// Clear the terminal — visible screen and scrollback history (⌘K).
    func clearTerminal()
    func terminateProcess()
}

/// Which terminal engine new tabs use. Resolved once per launch.
enum TerminalEngine {
    case swiftTerm
    case ghostty

    /// libghostty is the engine for all builds. `NEETLY_TERMINAL=swiftterm`
    /// is an escape hatch back to the legacy SwiftTerm renderer, kept in case
    /// a ghostty problem turns up in the field.
    static let current: TerminalEngine = {
        if ProcessInfo.processInfo.environment["NEETLY_TERMINAL"]?.lowercased() == "swiftterm" {
            return .swiftTerm
        }
        return .ghostty
    }()
}
