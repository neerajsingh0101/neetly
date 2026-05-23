import AppKit
import GhosttyTheme

/// Chrome colors derived from the user's picked terminal theme, so the app
/// chrome (window, bars, browser toolbar, split seams) matches the terminal.
/// The token names mirror `Theme`; `Theme` reads these and falls back to its
/// fixed design palette when `current` is nil.
///
/// `current` is nil for the built-in "Neetly Default" (and when unset), so the
/// chrome keeps its minimalist design palette in that case. The result is
/// cached — `refresh()` recomputes it (call at launch and on every theme
/// change) so reading a `Theme` color never hits disk.
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
        let cfg = TerminalConfig.load()
        // Neetly Default (or unset) keeps the minimalist design palette.
        guard let name = cfg.theme, name != TerminalConfig.neetlyThemeName else { return nil }

        let bg: NSColor, fg: NSColor, accent: NSColor, dark: Bool
        if name == TerminalConfig.customThemeName {
            // The user's editable palette → derive chrome from its explicit colors.
            guard let b = cfg.bgColor, let f = cfg.fgColor else { return nil }
            bg = b
            fg = f
            accent = cfg.linkColor.flatMap { NSColor.fromHex($0) } ?? f
            dark = luminance(b) < 0.5
        } else {
            // A GhosttyTheme catalog theme.
            guard let theme = GhosttyThemeCatalog.theme(named: name),
                  let b = NSColor.fromHex(theme.background),
                  let f = NSColor.fromHex(theme.foreground) else { return nil }
            bg = b
            fg = f
            accent = theme.palette[4].flatMap { NSColor.fromHex($0) } ?? f
            dark = theme.isDark
        }
        return derive(bg: bg, fg: fg, accent: accent, isDark: dark)
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

    private static func luminance(_ c: NSColor) -> CGFloat {
        let rgb = c.usingColorSpace(.sRGB) ?? c
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
    }
}

extension Notification.Name {
    /// Posted (no object) after `ChromeTheme.refresh()` when the user picks a
    /// terminal theme, so chrome views can restyle themselves.
    static let neetlyThemeChanged = Notification.Name("neetlyThemeChanged")
}
