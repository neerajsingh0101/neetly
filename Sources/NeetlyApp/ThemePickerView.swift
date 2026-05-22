import AppKit
import GhosttyTheme
import SwiftUI

/// A searchable popover list of terminal themes. Selecting one applies it to
/// every open terminal instantly and persists it — there is no save button.
struct ThemePickerView: View {
    @State private var searchText = ""
    @State private var currentTheme: String? = TerminalConfig.load().theme

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
            }
            .padding(10)

            Divider()

            List(results) { theme in
                Button {
                    apply(theme)
                } label: {
                    ThemeRow(theme: theme, isSelected: theme.name == currentTheme)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
        .frame(width: 320, height: 460)
    }

    private func apply(_ theme: GhosttyThemeDefinition) {
        var config = TerminalConfig.load()
        config.theme = theme.name
        config.save()
        currentTheme = theme.name
        if TerminalEngine.current == .ghostty {
            GhosttyTerminalTabViewController.reloadConfiguration()
        }
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
