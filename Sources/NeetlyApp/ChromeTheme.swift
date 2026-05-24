import AppKit
import GhosttyTheme

/// Chrome colors derived from the user's picked terminal theme, so the app
/// chrome (window, bars, browser toolbar, split seams) matches the terminal.
/// The token names mirror `Theme`; `Theme` reads these and falls back to its
/// fixed design palette when `current` is nil.
///
/// `current` is nil when no theme is set or the catalog lookup fails —
/// chrome then keeps its design palette. The result is cached — `refresh()`
/// recomputes it (call at launch and on every theme change) so reading a
/// `Theme` color never hits disk.
struct ChromeTheme {
    let isDark: Bool
    let bg0, bg1, bg2, bg3: NSColor
    let divider, line1, line2: NSColor
    let fg1, fg2, fg3, fg4: NSColor
    let accent: NSColor

    private static var resolved: ChromeTheme?
    private static var didResolve = false

    /// The chrome theme derived from the current terminal theme, or nil to use
    /// the fixed design palette.
    static var current: ChromeTheme? {
        if !didResolve { refresh() }
        return resolved
    }

    /// Recompute and cache. Call at launch and whenever the theme changes.
    static func refresh() {
        resolved = resolve()
        didResolve = true
    }

    private static func resolve() -> ChromeTheme? {
        guard let name = TerminalConfig.load().theme,
              let theme = GhosttyThemeCatalog.theme(named: name),
              let bg = NSColor.fromHex(theme.background),
              let fg = NSColor.fromHex(theme.foreground)
        else { return nil }
        let accent = theme.palette[4].flatMap { NSColor.fromHex($0) } ?? fg
        return derive(bg: bg, fg: fg, accent: accent, isDark: theme.isDark)
    }

    /// Build the full chrome ramp from a theme's base background/foreground:
    /// the bg surfaces lift toward the tint, borders blend bg→fg, and the text
    /// ramp fades fg→bg — preserving the design's relative steps in any theme.
    private static func derive(bg: NSColor, fg: NSColor, accent: NSColor, isDark: Bool) -> ChromeTheme {
        let tint: NSColor = isDark ? .white : .black
        let shade: NSColor = isDark ? .black : .white
        func lift(_ f: CGFloat) -> NSColor { bg.blended(withFraction: f, of: tint) ?? bg }
        func mix(_ f: CGFloat) -> NSColor { bg.blended(withFraction: f, of: fg) ?? bg }
        func fade(_ f: CGFloat) -> NSColor { fg.blended(withFraction: f, of: bg) ?? fg }
        return ChromeTheme(
            isDark: isDark,
            bg0: bg,
            bg1: lift(0.03),
            bg2: lift(0.08),
            bg3: lift(0.13),
            divider: bg.blended(withFraction: 0.25, of: shade) ?? bg,
            line1: mix(0.16),
            line2: mix(0.26),
            fg1: fg,
            fg2: fade(0.18),
            fg3: fade(0.40),
            fg4: fade(0.58),
            accent: accent
        )
    }

}

extension Notification.Name {
    /// Posted (no object) after `ChromeTheme.refresh()` when the user picks a
    /// terminal theme, so chrome views can restyle themselves.
    static let neetlyThemeChanged = Notification.Name("neetlyThemeChanged")
}
