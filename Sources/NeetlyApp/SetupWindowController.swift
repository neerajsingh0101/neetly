import AppKit
import SwiftUI

class SetupWindowController: NSWindowController {
    var onLaunch: ((SessionConfig) -> Void)?

    convenience init(initialScreen: SetupScreen = .repoList) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly"
        window.center()
        // Dark-mode-first, matching the session window and the rest of the app.
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.bg0
        self.init(window: window)

        let setupView = SetupView(initialScreen: initialScreen) { [weak self] config in
            self?.onLaunch?(config)
        }
        window.contentView = NSHostingView(rootView: setupView)
    }
}
