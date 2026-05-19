import AppKit
import SwiftTerm

/// Terminal view that suppresses macOS's text-input interventions.
///
/// SwiftTerm's `keyDown` routes printable keystrokes through `interpretKeyEvents`,
/// which is the AppKit hook the OS uses to apply Text Replacements
/// ("asx" → "Apple Store"), autocorrect, smart quotes/dashes, and inline
/// predictions. In a terminal we want literally what the user typed.
///
/// Two layers do the suppression:
///
/// 1. An `NSEvent` local key-down monitor short-circuits ordinary typing while
///    this view is first responder, sending characters straight to the PTY
///    and returning nil so the event never reaches `interpretKeyEvents`.
///    (SwiftTerm's `keyDown` is `public` not `open`, so a subclass override
///    isn't possible — the local monitor is the supported alternative.)
///
/// 2. `insertText` still gets called for the cases the monitor lets through —
///    IME commits, paste, system-delivered text. There we honor
///    `replacementRange.length` (which SwiftTerm's default ignores) so any
///    replacement that does sneak through edits the shell's line buffer
///    correctly via DEL instead of concatenating to it.
///
/// Events the monitor hands back to SwiftTerm (so super.keyDown handles them
/// the normal way):
/// - any modifier other than Shift/CapsLock (Cmd/Ctrl/Option/Fn) — preserves
///   Ctrl-letter, Option-as-meta, dead keys, app shortcuts
/// - kitty keyboard protocol active — the foreground program needs encoded events
/// - control / function-key characters — go through `doCommand` paths
/// - empty `event.characters` — dead-key first stroke or IME composition
class NeetlyTerminalView: LocalProcessTerminalView {
    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installKeyMonitor()
        } else {
            removeKeyMonitor()
        }
    }

    deinit {
        removeKeyMonitor()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard let window = self.window, event.window === window else { return event }
            guard window.firstResponder === self else { return event }

            if !self.getTerminal().keyboardEnhancementFlags.isEmpty {
                return event
            }

            let needsSystem: NSEvent.ModifierFlags = [.command, .control, .function, .option]
            if !event.modifierFlags.intersection(needsSystem).isEmpty {
                return event
            }

            guard let chars = event.characters, !chars.isEmpty, Self.isOrdinaryText(chars) else {
                return event
            }

            self.send(txt: chars)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private static func isOrdinaryText(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v < 0x20 || v == 0x7f { return false }       // C0 controls + DEL
            if v >= 0xF700 && v <= 0xF8FF { return false }  // NSFunctionKey range (arrows, F1-F12, etc.)
        }
        return true
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if replacementRange.length > 0 {
            let count = min(replacementRange.length, 4096)
            let dels = [UInt8](repeating: 0x7f, count: count)
            send(data: dels[...])
        }
        super.insertText(string, replacementRange: replacementRange)
    }
}
