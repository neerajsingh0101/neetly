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
/// Scope note: this palette styles the *chrome only* (session tab bar, pane tab
/// bars, browser toolbar, split seams). Terminal content is rendered by
/// libghostty and is user-configurable via `terminal.json`; website content is
/// the page's own. Neither is touched here.
enum Theme {
    private static func srgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }

    // MARK: Canvas
    /// App / chrome background — the deepest surface (oklch 0.165).
    static let bg0 = srgb(13, 15, 16)
    /// Pane background (oklch 0.195).
    static let bg1 = srgb(19, 21, 24)
    /// Header / raised surface — active tab, detail strip (oklch 0.225).
    static let bg2 = srgb(26, 28, 30)
    /// Hover / active surface (oklch 0.265).
    static let bg3 = srgb(35, 38, 41)
    /// Thin seam between panes (oklch 0.12) — reads as a dark hairline.
    static let divider = srgb(5, 6, 7)

    // MARK: Lines
    /// Hairline border (oklch 0.30).
    static let line1 = srgb(44, 46, 49)
    /// Stronger border (oklch 0.36).
    static let line2 = srgb(58, 61, 65)

    // MARK: Type
    /// Primary text (oklch 0.94).
    static let fg1 = srgb(233, 235, 238)
    /// Secondary text (oklch 0.78).
    static let fg2 = srgb(180, 184, 187)
    /// Muted text (oklch 0.62).
    static let fg3 = srgb(131, 135, 139)
    /// Hint text (oklch 0.48).
    static let fg4 = srgb(90, 94, 98)

    // MARK: Accent + status
    /// Neeto-leaning indigo/blue accent (#5B89FF).
    static let accent = srgb(91, 137, 255)
    /// Done — Claude finished, awaiting review (oklch 0.74 0.16 150).
    static let green = srgb(81, 198, 114)
    /// Working / in progress (oklch 0.80 0.15 80).
    static let amber = srgb(240, 177, 53)
    /// Needs attention / error (oklch 0.66 0.21 25).
    static let red = srgb(248, 75, 75)
    /// Merged PR / accent-violet (oklch 0.70 0.16 295).
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

/// `Color` versions of the palette for the SwiftUI setup screens, so the launch
/// / new-session / settings UI shares one source of truth with the AppKit chrome.
extension Theme {
    static let bg0C = Color(nsColor: bg0)
    static let bg1C = Color(nsColor: bg1)
    static let bg2C = Color(nsColor: bg2)
    static let bg3C = Color(nsColor: bg3)
    static let line1C = Color(nsColor: line1)
    static let line2C = Color(nsColor: line2)
    static let fg1C = Color(nsColor: fg1)
    static let fg2C = Color(nsColor: fg2)
    static let fg3C = Color(nsColor: fg3)
    static let fg4C = Color(nsColor: fg4)
    static let accentC = Color(nsColor: accent)
    static let greenC = Color(nsColor: green)
    static let amberC = Color(nsColor: amber)
    static let redC = Color(nsColor: red)
    static let violetC = Color(nsColor: violet)
}
