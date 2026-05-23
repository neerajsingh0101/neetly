import AppKit

/// Chrome-style horizontal tab bar at the top of each pane.
class TabBarView: NSView {
    static let barHeight: CGFloat = 30
    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTerminal: (() -> Void)?
    var onNewBrowser: (() -> Void)?
    var onSplitColumns: (() -> Void)?
    var onSplitRows: (() -> Void)?
    var onToggleMaximize: (() -> Void)?
    private var buttons: [NSView] = []
    private var tabInfos: [(title: String, icon: NSImage?, isActive: Bool)] = []
    private var laidOutWidth: CGFloat = -1
    private let newTerminalButton = NSButton()
    private let newBrowserButton = NSButton()
    private let splitColButton = NSButton()
    private let splitRowButton = NSButton()
    private let maximizeButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.bg0.cgColor

        // Borderless, muted icon buttons — the cmux-style pane action row.
        func styleIconButton(_ button: NSButton, symbol: String, tip: String, action: Selector) {
            button.image = Theme.symbol(symbol, size: 12.5)
            button.toolTip = tip
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.contentTintColor = Theme.fg3
            button.target = self
            button.action = action
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }

        styleIconButton(newTerminalButton, symbol: "terminal",
                        tip: "New Terminal", action: #selector(newTerminalClicked))
        styleIconButton(newBrowserButton, symbol: "globe",
                        tip: "New Browser", action: #selector(newBrowserClicked))
        styleIconButton(splitColButton, symbol: "rectangle.split.2x1",
                        tip: "Split into Columns", action: #selector(splitColClicked))
        styleIconButton(splitRowButton, symbol: "rectangle.split.1x2",
                        tip: "Split into Rows", action: #selector(splitRowClicked))
        styleIconButton(maximizeButton, symbol: "arrow.up.left.and.arrow.down.right",
                        tip: "Maximize (Cmd+Shift+M)", action: #selector(maximizeClicked))

        NSLayoutConstraint.activate([
            maximizeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            maximizeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            maximizeButton.widthAnchor.constraint(equalToConstant: 22),
            maximizeButton.heightAnchor.constraint(equalToConstant: 20),

            splitRowButton.trailingAnchor.constraint(equalTo: maximizeButton.leadingAnchor, constant: -1),
            splitRowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            splitRowButton.widthAnchor.constraint(equalToConstant: 22),
            splitRowButton.heightAnchor.constraint(equalToConstant: 20),

            splitColButton.trailingAnchor.constraint(equalTo: splitRowButton.leadingAnchor, constant: -1),
            splitColButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            splitColButton.widthAnchor.constraint(equalToConstant: 22),
            splitColButton.heightAnchor.constraint(equalToConstant: 20),

            newBrowserButton.trailingAnchor.constraint(equalTo: splitColButton.leadingAnchor, constant: -1),
            newBrowserButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newBrowserButton.widthAnchor.constraint(equalToConstant: 22),
            newBrowserButton.heightAnchor.constraint(equalToConstant: 20),

            newTerminalButton.trailingAnchor.constraint(equalTo: newBrowserButton.leadingAnchor, constant: -1),
            newTerminalButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTerminalButton.widthAnchor.constraint(equalToConstant: 26),
            newTerminalButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(tabs: [(title: String, icon: NSImage?, isActive: Bool)]) {
        tabInfos = tabs
        laidOutWidth = -1  // force a re-layout with the new tab set
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Re-flow tabs whenever the bar resizes or the tab set changes, so they
        // shrink to share the available width instead of overflowing past the
        // action buttons.
        guard bounds.width != laidOutWidth else { return }
        laidOutWidth = bounds.width
        relayoutTabs()
    }

    private func relayoutTabs() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        let count = tabInfos.count
        guard count > 0 else { return }

        // Tabs span from the left edge up to the right-aligned action buttons.
        let leftPad: CGFloat = 4
        let clusterLeft = newTerminalButton.frame.minX
        let rightEdge = (clusterLeft > leftPad ? clusterLeft : bounds.width - 130) - 6
        let available = max(0, rightEdge - leftPad)
        // Share the available width, shrinking (to a floor) when overflowing.
        let perTab = max(32, min(180, available / CGFloat(count)))

        var x = leftPad
        for (i, info) in tabInfos.enumerated() {
            let tabView = TabButton(
                index: i, title: info.title, icon: info.icon, isActive: info.isActive,
                width: perTab, height: Self.barHeight,
                onSelect: { [weak self] idx in self?.onSelectTab?(idx) },
                onClose: { [weak self] idx in self?.onCloseTab?(idx) }
            )
            tabView.frame.origin = CGPoint(x: x, y: 0)
            addSubview(tabView)
            buttons.append(tabView)
            x += perTab
        }
    }

    /// Re-apply themed colors after a theme change. Tab buttons are rebuilt by
    /// the owning pane's `refreshTabBar()`; this handles the bar's own chrome.
    func applyTheme() {
        layer?.backgroundColor = Theme.bg0.cgColor
        for btn in [newTerminalButton, newBrowserButton, splitColButton, splitRowButton, maximizeButton] {
            btn.contentTintColor = Theme.fg3
        }
        needsDisplay = true
    }

    @objc private func newTerminalClicked() {
        onNewTerminal?()
    }

    @objc private func newBrowserClicked() {
        onNewBrowser?()
    }

    @objc private func splitColClicked() {
        onSplitColumns?()
    }

    @objc private func splitRowClicked() {
        onSplitRows?()
    }

    @objc private func maximizeClicked() {
        onToggleMaximize?()
    }

    /// Update the maximize button icon and tooltip based on state.
    func setMaximized(_ isMaximized: Bool) {
        if isMaximized {
            maximizeButton.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "Restore")
            maximizeButton.toolTip = "Restore (Cmd+Shift+M)"
        } else {
            maximizeButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Maximize")
            maximizeButton.toolTip = "Maximize (Cmd+Shift+M)"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Bottom hairline
        Theme.line1.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

private class TabButton: NSView {
    let tabIndex: Int
    private let onSelect: (Int) -> Void
    private let onClose: (Int) -> Void
    private let isActive: Bool
    private let closeBtn: NSButton
    private var trackingArea: NSTrackingArea?

    init(index: Int, title: String, icon: NSImage?, isActive: Bool, width: CGFloat, height: CGFloat,
         onSelect: @escaping (Int) -> Void, onClose: @escaping (Int) -> Void) {
        self.tabIndex = index
        self.isActive = isActive
        self.onSelect = onSelect
        self.onClose = onClose
        self.closeBtn = NSButton(frame: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        applyBackground(hover: false)

        // Icon — tint template symbols (terminal/globe); leave real favicons in color.
        var x: CGFloat = 10
        if let icon = icon {
            let iconView = NSImageView(frame: NSRect(x: x, y: (height - 13) / 2, width: 13, height: 13))
            iconView.image = icon
            iconView.imageScaling = .scaleProportionallyUpOrDown
            if icon.isTemplate {
                iconView.contentTintColor = isActive ? Theme.fg1 : Theme.fg3
            }
            addSubview(iconView)
            x += 17
        }

        // Title — monospaced, matching the terminal-app pane header.
        let label = NSTextField(labelWithString: title)
        label.font = Theme.mono(11, weight: isActive ? .medium : .regular)
        label.textColor = isActive ? Theme.fg1 : Theme.fg3
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: x, y: (height - 16) / 2, width: 90, height: 16)
        addSubview(label)

        // Close button — hidden by default, shown on hover
        closeBtn.image = Theme.symbol("xmark", size: 9.5)
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.contentTintColor = Theme.fg3
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.isHidden = true
        closeBtn.toolTip = "Close Tab (Cmd+W)"
        addSubview(closeBtn)

        frame.size = NSSize(width: width, height: height)
        label.frame.size.width = max(0, width - x - 26)
        closeBtn.frame = NSRect(x: width - 24, y: (height - 16) / 2, width: 16, height: 16)

        // Active tab: a thin accent underline at the bottom — consistent with
        // the session strip — instead of a chunky filled pill.
        if isActive {
            let underline = NSView(frame: NSRect(x: 0, y: 1, width: width, height: 2))
            underline.autoresizingMask = [.width]
            underline.wantsLayer = true
            underline.layer?.backgroundColor = Theme.accent.cgColor
            addSubview(underline)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyBackground(hover: Bool) {
        if isActive {
            layer?.backgroundColor = Theme.bg2.cgColor
        } else {
            layer?.backgroundColor = (hover ? Theme.bg2 : NSColor.clear).cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        if !isActive { applyBackground(hover: true) }
        closeBtn.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        if !isActive { applyBackground(hover: false) }
        closeBtn.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x < frame.width - 24 {
            onSelect(tabIndex)
        }
    }

    @objc private func closeClicked() {
        onClose(tabIndex)
    }
}
