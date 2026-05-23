import AppKit

struct TerminalConfig: Codable {
    var fontFamily: String?
    var fontSize: CGFloat?
    var backgroundColor: String?
    var foregroundColor: String?
    var selectionColor: String?
    var linkColor: String?
    var scrollback: Int?
    var theme: String?

    /// The built-in terminal theme derived from the app's design tokens (see
    /// `NeetlyTerminalTheme`) — what the terminal uses out of the box so it
    /// matches the chrome. Resolved specially in `makeConfiguration`.
    static let neetlyThemeName = "Neetly Default"
    /// Sentinel meaning "use the explicit color fields below" — the user's
    /// editable custom palette, listed in the picker beside the catalog themes.
    static let customThemeName = "Custom"
    /// The theme every install gets until the user picks another one.
    static let defaultThemeName = neetlyThemeName

    static let `default` = TerminalConfig(
        fontFamily: nil,
        fontSize: 17,
        backgroundColor: NeetlyTerminalTheme.background,
        foregroundColor: NeetlyTerminalTheme.foreground,
        selectionColor: NeetlyTerminalTheme.selection,
        linkColor: NeetlyTerminalTheme.cursor,
        scrollback: 10000,
        theme: defaultThemeName
    )

    static func load() -> TerminalConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configFile = home.appendingPathComponent(".config/neetly/terminal.json")
        guard let data = try? Data(contentsOf: configFile),
              var config = try? JSONDecoder().decode(TerminalConfig.self, from: data) else {
            return .default
        }
        // Installs that predate theming have no theme set — give them the
        // default too, until they pick their own.
        if config.theme == nil { config.theme = defaultThemeName }
        return config
    }

    /// Writes this config to ~/.config/neetly/terminal.json.
    func save() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/neetly")
        let configFile = dir.appendingPathComponent("terminal.json")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: configFile, options: .atomic)
        } catch {
            NSLog("TerminalConfig: failed to save: \(error)")
        }
    }

    var font: NSFont {
        let size = fontSize ?? 17
        let candidates = [
            fontFamily,
            "JetBrains Mono",
            "Symbols Nerd Font Mono",
            "Noto Color Emoji",
        ].compactMap { $0 }

        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var bgColor: NSColor? {
        backgroundColor.flatMap { NSColor.fromHex($0) }
    }

    var fgColor: NSColor? {
        foregroundColor.flatMap { NSColor.fromHex($0) }
    }

    var selColor: NSColor? {
        selectionColor.flatMap { NSColor.fromHex($0) }
    }

    /// Returns the link color as an OSC 4 escape sequence that overrides ANSI
    /// palette colors 4 (blue) and 12 (bright blue), where most terminals render
    /// URLs.
    var oscLinkColorSequence: String? {
        guard let hex = linkColor?.trimmingCharacters(in: .whitespaces) else { return nil }
        var str = hex
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6 else { return nil }
        let r = String(str.prefix(2))
        let g = String(str.dropFirst(2).prefix(2))
        let b = String(str.dropFirst(4).prefix(2))
        // OSC 4 ; index ; rgb:RR/GG/BB ST  — set palette color
        // ESC ] 4 ; i ; rgb:... BEL
        let blue = "\u{1B}]4;4;rgb:\(r)/\(g)/\(b)\u{07}"
        let brightBlue = "\u{1B}]4;12;rgb:\(r)/\(g)/\(b)\u{07}"
        return blue + brightBlue
    }
}

/// The built-in "Neetly Default" terminal theme: the app's design tokens
/// (`Theme.swift`) expressed as a ghostty palette, so terminal content matches
/// the chrome out of the box. The status hues (red/green/yellow/blue/magenta)
/// are the exact Theme tokens; the greys/whites come from the Theme fg/bg ramp,
/// and the cyan + bright slots (absent from the chrome palette) are tuned to sit
/// with them.
enum NeetlyTerminalTheme {
    static let background = "#0D0F10"   // Theme.bg0
    static let foreground = "#E9EBEE"   // Theme.fg1
    static let cursor     = "#5B89FF"   // Theme.accent
    static let selection  = "#232629"   // Theme.bg3

    /// ANSI palette indices 0–15.
    static let palette: [Int: String] = [
        0:  "#1A1C1E",  // black          (Theme.bg2)
        1:  "#F84B4B",  // red            (Theme.red)
        2:  "#51C672",  // green          (Theme.green)
        3:  "#F0B135",  // yellow         (Theme.amber)
        4:  "#5B89FF",  // blue           (Theme.accent)
        5:  "#A787F6",  // magenta        (Theme.violet)
        6:  "#5BC6D6",  // cyan           (tuned)
        7:  "#B4B8BB",  // white          (Theme.fg2)
        8:  "#5A5E62",  // bright black   (Theme.fg4)
        9:  "#FF6F6F",  // bright red
        10: "#6FD98C",  // bright green
        11: "#FFC95C",  // bright yellow
        12: "#7BA0FF",  // bright blue
        13: "#BBA0FF",  // bright magenta
        14: "#7FD8E4",  // bright cyan
        15: "#E9EBEE",  // bright white   (Theme.fg1)
    ]
}

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        var str = hex.trimmingCharacters(in: .whitespaces)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6, let val = UInt64(str, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// `#RRGGBB` in sRGB — the inverse of `fromHex`, for persisting colors
    /// chosen via SwiftUI's ColorPicker back into `terminal.json`.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        func channel(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        return String(format: "#%02X%02X%02X",
                      channel(c.redComponent), channel(c.greenComponent), channel(c.blueComponent))
    }
}
