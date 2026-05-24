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

    /// The theme every install gets until the user picks another one. A real
    /// catalog theme name — no built-in sentinels.
    static let defaultThemeName = "Catppuccin Mocha"

    static let `default` = TerminalConfig(
        fontFamily: nil,
        fontSize: 17,
        backgroundColor: "#1e1e2e",
        foregroundColor: "#cdd6f4",
        selectionColor: "#585b70",
        linkColor: "#89b4fa",
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
        // Installs that predate theming have no theme set, and installs from
        // the brief "Neetly Default" / "Custom" era have stale built-in
        // sentinels — give them the catalog default until they pick their own.
        if config.theme == nil
            || config.theme == "Neetly Default"
            || config.theme == "Custom"
        {
            config.theme = defaultThemeName
        }
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
