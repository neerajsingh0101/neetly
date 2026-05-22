import AppKit
import GhosttyTheme

/// Colors for theming Neetly's chrome — window, tab bars, panes — to match
/// the picked terminal theme. `current` is nil when no theme is set, so the
/// chrome keeps its system appearance.
struct ChromeTheme {
    let background: NSColor
    let foreground: NSColor
    /// Dimmed foreground, for secondary text (repo names, SHAs).
    let mutedForeground: NSColor
    /// Background for the active tab — a subtle lift from `background`.
    let activeBackground: NSColor
    /// Hairline separator color.
    let border: NSColor
    /// Accent color for icons and highlights — the theme's palette[4]
    /// (the ANSI blue slot), the convention Muxy follows too.
    let accent: NSColor
    let isDark: Bool

    /// Resolved from the theme currently picked in `terminal.json`, or nil.
    static var current: ChromeTheme? {
        guard let name = TerminalConfig.load().theme,
              let theme = GhosttyThemeCatalog.theme(named: name),
              let background = NSColor.fromHex(theme.background),
              let foreground = NSColor.fromHex(theme.foreground)
        else { return nil }
        let tint: NSColor = theme.isDark ? .white : .black
        let accent = theme.palette[4].flatMap { NSColor.fromHex($0) } ?? foreground
        return ChromeTheme(
            background: background,
            foreground: foreground,
            mutedForeground: background.blended(withFraction: 0.6, of: foreground) ?? foreground,
            activeBackground: background.blended(withFraction: 0.12, of: tint) ?? background,
            border: background.blended(withFraction: 0.2, of: foreground) ?? background,
            accent: accent,
            isDark: theme.isDark
        )
    }
}

extension Notification.Name {
    /// Posted (no object) when the user picks a terminal theme, so chrome
    /// views can restyle themselves.
    static let neetlyThemeChanged = Notification.Name("neetlyThemeChanged")
}
