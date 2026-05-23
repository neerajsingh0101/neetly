import AppKit
import GhosttyTheme
import SwiftUI

/// A searchable popover list of terminal themes. Selecting one applies it
/// to every open terminal instantly and persists it — no save button.
///
/// Keyboard: the search field captures focus on open, and ↑/↓ arrow keys
/// move the selection while auto-applying the highlighted theme — VS-Code
/// style live preview. Stop = that's your theme.
struct ThemePickerView: View {
    @State private var searchText = ""
    @State private var currentTheme: String? = TerminalConfig.load().theme
    @State private var highlightedID: String?
    @FocusState private var searchFocused: Bool

    private var results: [GhosttyThemeDefinition] {
        // GhosttyThemeCatalog.search("") returns nothing — its name filter
        // rejects an empty query — so list the full catalog directly when
        // there is no search text.
        searchText.isEmpty
            ? GhosttyThemeCatalog.allThemes
            : GhosttyThemeCatalog.search(searchText)
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
                    ForEach(results) { theme in
                        ThemeRow(theme: theme, isSelected: theme.name == currentTheme)
                            .tag(theme.id)
                            .contentShape(Rectangle())
                            .onTapGesture { highlightedID = theme.id }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .onChange(of: highlightedID) { _, newID in
                    guard let id = newID,
                          let theme = results.first(where: { $0.id == id })
                    else { return }
                    apply(theme)
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
            if let id = highlightedID, results.contains(where: { $0.id == id }) { return }
            highlightedID = results.first?.id
        }
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let currentIdx = highlightedID.flatMap { id in
            results.firstIndex(where: { $0.id == id })
        } ?? -1
        let nextIdx = currentIdx < 0
            ? 0
            : max(0, min(results.count - 1, currentIdx + delta))
        highlightedID = results[nextIdx].id
        // .onChange(of: highlightedID) does the apply + scroll.
    }

    private func apply(_ theme: GhosttyThemeDefinition) {
        var config = TerminalConfig.load()
        config.theme = theme.name
        config.save()
        currentTheme = theme.name
        if TerminalEngine.current == .ghostty {
            GhosttyTerminalTabViewController.reloadConfiguration()
        }
        NotificationCenter.default.post(name: .neetlyThemeChanged, object: nil)
    }
}

private struct ThemeRow: View {
    let theme: GhosttyThemeDefinition
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(theme.name)
                        .font(.system(size: 13, weight: .medium))
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                ThemeSwatch(theme: theme)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct ThemeSwatch: View {
    let theme: GhosttyThemeDefinition

    var body: some View {
        HStack(spacing: 0) {
            Text("Ab")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(color(theme.foreground))
                .frame(width: 30, height: 18)
                .background(color(theme.background))
            ForEach(0 ..< 16, id: \.self) { index in
                color(theme.palette[index])
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
