import AppKit
import GhosttyTheme
import SwiftUI

/// One selectable entry in the terminal-theme picker: the built-in Neetly
/// theme (the app's design tokens), the user's editable custom palette, or any
/// theme from the GhosttyTheme catalog.
enum TerminalThemeChoice: Identifiable {
    case neetly
    case custom
    case catalog(GhosttyThemeDefinition)

    /// Stable id == the name persisted in `TerminalConfig.theme`, so selection
    /// and scroll-to-current key off the same string.
    var id: String { name }

    var name: String {
        switch self {
        case .neetly:         return TerminalConfig.neetlyThemeName
        case .custom:         return TerminalConfig.customThemeName
        case .catalog(let t): return t.name
        }
    }
}

/// A searchable popover list of terminal themes. Selecting one applies it to
/// every open terminal instantly and persists it — no save button. The two
/// built-in entries (Neetly Default, Custom) are pinned above the catalog.
///
/// Keyboard: the search field captures focus on open, and ↑/↓ arrow keys move
/// the selection while auto-applying the highlighted theme — VS-Code style live
/// preview. Stop = that's your theme.
struct ThemePickerView: View {
    @State private var searchText = ""
    @State private var currentTheme: String? = TerminalConfig.load().theme
    @State private var highlightedID: String?
    @FocusState private var searchFocused: Bool

    /// The Neetly + Custom built-ins, then the (optionally filtered) catalog.
    private var choices: [TerminalThemeChoice] {
        let catalog = searchText.isEmpty
            ? GhosttyThemeCatalog.allThemes
            : GhosttyThemeCatalog.search(searchText)
        let builtins: [TerminalThemeChoice] = [.neetly, .custom].filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
        return builtins + catalog.map { .catalog($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search themes", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onKeyPress(.upArrow) {
                        moveSelection(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveSelection(by: 1)
                        return .handled
                    }
            }
            .padding(10)

            Divider()

            ScrollViewReader { proxy in
                List(selection: $highlightedID) {
                    ForEach(choices) { choice in
                        ThemeRow(choice: choice, isSelected: choice.name == currentTheme)
                            .tag(choice.id)
                            .contentShape(Rectangle())
                            .onTapGesture { highlightedID = choice.id }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    // Center the current theme when the picker opens. The
                    // first onChange below fires before the List has
                    // computed row positions, so we defer one tick to catch
                    // the actual first laid-out frame.
                    guard let id = currentTheme else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: highlightedID) { _, newID in
                    guard let id = newID,
                          let choice = choices.first(where: { $0.id == id })
                    else { return }
                    // Skip the no-op case — initial open assigns
                    // highlightedID = currentTheme, and the .onAppear above
                    // already handles centering for that.
                    guard id != currentTheme else { return }
                    apply(choice)
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 320, height: 460)
        .onAppear {
            highlightedID = currentTheme
            // Defer focus a tick so the popover's window has become key.
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: searchText) { _, _ in
            // After a filter change, keep the current highlight visible —
            // else jump to the first result so ↑/↓ has somewhere to start.
            if let id = highlightedID, choices.contains(where: { $0.id == id }) { return }
            highlightedID = choices.first?.id
        }
    }

    private func moveSelection(by delta: Int) {
        let list = choices
        guard !list.isEmpty else { return }
        let currentIdx = highlightedID.flatMap { id in
            list.firstIndex(where: { $0.id == id })
        } ?? -1
        let nextIdx = currentIdx < 0
            ? 0
            : max(0, min(list.count - 1, currentIdx + delta))
        highlightedID = list[nextIdx].id
        // .onChange(of: highlightedID) does the apply + scroll.
    }

    private func apply(_ choice: TerminalThemeChoice) {
        var config = TerminalConfig.load()
        switch choice {
        case .neetly:
            config.theme = TerminalConfig.neetlyThemeName
        case .custom:
            config.theme = TerminalConfig.customThemeName
            // Seed the editable colors from the Neetly look the first time, so
            // the Settings color wells start from the brand palette, not black.
            if config.backgroundColor == nil { config.backgroundColor = NeetlyTerminalTheme.background }
            if config.foregroundColor == nil { config.foregroundColor = NeetlyTerminalTheme.foreground }
            if config.selectionColor == nil { config.selectionColor = NeetlyTerminalTheme.selection }
            if config.linkColor == nil { config.linkColor = NeetlyTerminalTheme.cursor }
        case .catalog(let theme):
            config.theme = theme.name
        }
        config.save()
        currentTheme = config.theme
        if TerminalEngine.current == .ghostty {
            GhosttyTerminalTabViewController.reloadConfiguration()
        }
        // Re-resolve chrome colors and tell the chrome to restyle.
        ChromeTheme.refresh()
        NotificationCenter.default.post(name: .neetlyThemeChanged, object: nil)
    }
}

private struct ThemeRow: View {
    let choice: TerminalThemeChoice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(choice.name)
                        .font(.system(size: 13, weight: .medium))
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                swatch
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// Built-ins preview from their own colors; catalog themes from theirs.
    @ViewBuilder private var swatch: some View {
        switch choice {
        case .neetly:
            ThemeSwatch(
                background: NeetlyTerminalTheme.background,
                foreground: NeetlyTerminalTheme.foreground,
                blocks: (0 ..< 16).map { NeetlyTerminalTheme.palette[$0] }
            )
        case .custom:
            // The custom palette defines only the four key colors.
            let cfg = TerminalConfig.load()
            ThemeSwatch(
                background: cfg.backgroundColor ?? NeetlyTerminalTheme.background,
                foreground: cfg.foregroundColor ?? NeetlyTerminalTheme.foreground,
                blocks: [cfg.linkColor, cfg.foregroundColor, cfg.selectionColor, cfg.backgroundColor]
            )
        case .catalog(let theme):
            ThemeSwatch(
                background: theme.background,
                foreground: theme.foreground,
                blocks: (0 ..< 16).map { theme.palette[$0] }
            )
        }
    }
}

private struct ThemeSwatch: View {
    let background: String?
    let foreground: String?
    let blocks: [String?]

    var body: some View {
        HStack(spacing: 0) {
            Text("Ab")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(color(foreground))
                .frame(width: 30, height: 18)
                .background(color(background))
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, hex in
                color(hex)
                    .frame(width: 13, height: 18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func color(_ hex: String?) -> Color {
        guard let hex, let nsColor = NSColor.fromHex(hex) else { return Color.secondary }
        return Color(nsColor: nsColor)
    }
}
