import AppKit
import SwiftUI

/// Central color + type palette for neetly's native chrome.
///
/// Derived from the Neetly design system (Claude Design handoff): a clean,
/// minimal, dark-mode-first editor look. The design specifies colors in OKLCH
/// (hue ~250 — a near-neutral blue-grey — with a blue accent and green/amber/red
/// status colors). AppKit has no OKLCH initializer, so the tokens below are the
/// exact sRGB equivalents of those OKLCH values.
///
/// Theming: the canvas/line/type/accent tokens **follow the picked terminal
/// theme** via `ChromeTheme` — when a theme is active they're derived from it,
/// otherwise (Neetly Default) they use the fixed design values below. The
/// semantic status colors (green/amber/red/violet) are always fixed.
enum Theme {
    private static func srgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    // MARK: Design defaults (used when no terminal theme is active)
    private static let _bg0 = srgb(13, 15, 16)
    private static let _bg1 = srgb(19, 21, 24)
    private static let _bg2 = srgb(26, 28, 30)
    private static let _bg3 = srgb(35, 38, 41)
    private static let _divider = srgb(5, 6, 7)
    private static let _line1 = srgb(44, 46, 49)
    private static let _line2 = srgb(58, 61, 65)
    private static let _fg1 = srgb(233, 235, 238)
    private static let _fg2 = srgb(180, 184, 187)
    private static let _fg3 = srgb(131, 135, 139)
    private static let _fg4 = srgb(90, 94, 98)
    private static let _accent = srgb(91, 137, 255)

    // MARK: Canvas — follow the picked terminal theme, else the design palette.
    /// App / chrome background — the deepest surface.
    static var bg0: NSColor { ChromeTheme.current?.bg0 ?? _bg0 }
    /// Pane background.
    static var bg1: NSColor { ChromeTheme.current?.bg1 ?? _bg1 }
    /// Header / raised surface — active tab, detail strip.
    static var bg2: NSColor { ChromeTheme.current?.bg2 ?? _bg2 }
    /// Hover / active surface.
    static var bg3: NSColor { ChromeTheme.current?.bg3 ?? _bg3 }
    /// Thin seam between panes — reads as a dark hairline.
    static var divider: NSColor { ChromeTheme.current?.divider ?? _divider }

    // MARK: Lines
    /// Hairline border.
    static var line1: NSColor { ChromeTheme.current?.line1 ?? _line1 }
    /// Stronger border.
    static var line2: NSColor { ChromeTheme.current?.line2 ?? _line2 }

    // MARK: Type
    /// Primary text.
    static var fg1: NSColor { ChromeTheme.current?.fg1 ?? _fg1 }
    /// Secondary text.
    static var fg2: NSColor { ChromeTheme.current?.fg2 ?? _fg2 }
    /// Muted text.
    static var fg3: NSColor { ChromeTheme.current?.fg3 ?? _fg3 }
    /// Hint text.
    static var fg4: NSColor { ChromeTheme.current?.fg4 ?? _fg4 }

    // MARK: Accent + status
    /// Neeto-leaning indigo/blue accent (#5B89FF) — follows the theme's accent.
    static var accent: NSColor { ChromeTheme.current?.accent ?? _accent }
    /// Done — Claude finished, awaiting review. Fixed (semantic).
    static let green = srgb(81, 198, 114)
    /// Working / in progress. Fixed (semantic).
    static let amber = srgb(240, 177, 53)
    /// Needs attention / error. Fixed (semantic).
    static let red = srgb(248, 75, 75)
    /// Merged PR / accent-violet. Fixed (semantic).
    static let violet = srgb(167, 135, 246)

    // MARK: Fonts
    /// Monospaced font for terminal-app chrome (pane titles, URLs, SHAs, stats).
    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Icons
    /// An SF Symbol rendered at a consistent, light point size so all chrome
    /// icons share one fine-line, minimal weight. Stays a template image, so
    /// `contentTintColor` still controls its color.
    static func symbol(_ name: String, size: CGFloat = 12.5, weight: NSFont.Weight = .regular) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: name)?
            .withSymbolConfiguration(config)
    }
}

// MARK: - SwiftUI mirrors

/// `Color` versions of the palette for the SwiftUI setup screens. The chrome
/// tokens are computed so those screens pick up the active theme when (re)built;
/// the status colors are fixed.
extension Theme {
    static var bg0C: Color { Color(nsColor: bg0) }
    static var bg1C: Color { Color(nsColor: bg1) }
    static var bg2C: Color { Color(nsColor: bg2) }
    static var bg3C: Color { Color(nsColor: bg3) }
    static var line1C: Color { Color(nsColor: line1) }
    static var line2C: Color { Color(nsColor: line2) }
    static var fg1C: Color { Color(nsColor: fg1) }
    static var fg2C: Color { Color(nsColor: fg2) }
    static var fg3C: Color { Color(nsColor: fg3) }
    static var fg4C: Color { Color(nsColor: fg4) }
    static var accentC: Color { Color(nsColor: accent) }
    static let greenC = Color(nsColor: green)
    static let amberC = Color(nsColor: amber)
    static let redC = Color(nsColor: red)
    static let violetC = Color(nsColor: violet)
}
