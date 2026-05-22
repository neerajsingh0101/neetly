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
    func terminateProcess()
}

/// Which terminal engine new tabs use. Resolved once per launch.
enum TerminalEngine {
    case swiftTerm
    case ghostty

    /// Resolution order: the `NEETLY_TERMINAL` env var (dev / dogfooding)
    /// wins; then the bundled `NeetlyTerminalEngine` Info.plist key — how the
    /// beta build opts in; else SwiftTerm, so the public build is unchanged.
    static let current: TerminalEngine = {
        switch ProcessInfo.processInfo.environment["NEETLY_TERMINAL"]?.lowercased() {
        case "ghostty": return .ghostty
        case "swiftterm": return .swiftTerm
        default: break
        }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "NeetlyTerminalEngine") as? String,
           bundled.lowercased() == "ghostty" {
            return .ghostty
        }
        return .swiftTerm
    }()
}
