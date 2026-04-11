import AppKit

/// Chrome-style horizontal tab bar at the top of each pane.
class TabBarView: NSView {
    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTerminal: (() -> Void)?
    var onNewBrowser: (() -> Void)?
    private var buttons: [NSButton] = []
    private let newTerminalButton = NSButton()
    private let newBrowserButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // "+Terminal" button — right-aligned
        newTerminalButton.title = ">_"
        newTerminalButton.toolTip = "New Terminal"
        newTerminalButton.bezelStyle = .recessed
        newTerminalButton.font = .systemFont(ofSize: 11, weight: .medium)
        newTerminalButton.target = self
        newTerminalButton.action = #selector(newTerminalClicked)
        newTerminalButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newTerminalButton)

        // "+Browser" button — right of terminal button
        newBrowserButton.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "New Browser")
        newBrowserButton.toolTip = "New Browser"
        newBrowserButton.bezelStyle = .recessed
        newBrowserButton.imagePosition = .imageOnly
        newBrowserButton.target = self
        newBrowserButton.action = #selector(newBrowserClicked)
        newBrowserButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newBrowserButton)

        NSLayoutConstraint.activate([
            newBrowserButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            newBrowserButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newBrowserButton.widthAnchor.constraint(equalToConstant: 28),
            newBrowserButton.heightAnchor.constraint(equalToConstant: 22),

            newTerminalButton.trailingAnchor.constraint(equalTo: newBrowserButton.leadingAnchor, constant: -2),
            newTerminalButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTerminalButton.widthAnchor.constraint(equalToConstant: 32),
            newTerminalButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(tabs: [(title: String, isActive: Bool)]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        var x: CGFloat = 2
        for (i, tab) in tabs.enumerated() {
            let button = TabButton(index: i, title: tab.title, isActive: tab.isActive)
            button.target = self
            button.action = #selector(tabClicked(_:))
            button.frame.origin = CGPoint(x: x, y: 2)
            addSubview(button)
            buttons.append(button)
            x += button.frame.width + 2
        }
    }

    @objc private func tabClicked(_ sender: TabButton) {
        onSelectTab?(sender.tabIndex)
    }

    @objc private func newTerminalClicked() {
        onNewTerminal?()
    }

    @objc private func newBrowserClicked() {
        onNewBrowser?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Bottom border
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

private class TabButton: NSButton {
    let tabIndex: Int

    init(index: Int, title: String, isActive: Bool) {
        self.tabIndex = index
        super.init(frame: .zero)

        self.title = title
        bezelStyle = .recessed
        setButtonType(.onOff)
        state = isActive ? .on : .off
        font = .systemFont(ofSize: 12)
        isBordered = true
        sizeToFit()

        // Ensure minimum width
        let minWidth: CGFloat = 80
        if frame.width < minWidth {
            frame.size.width = minWidth
        }
        frame.size.height = 26
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
