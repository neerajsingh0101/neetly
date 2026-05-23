import AppKit

/// The session-workspace chrome, in the Neetly design language:
///   ─ a horizontal session strip across the top (flat, sharp tabs)
///   ─ a slim bottom status footer (branch · diff · commit · PR)
///
/// Sharp and minimal: no rounded pills — flat tabs with an accent underline for
/// the active session and hairline seams. The strip sits in the (transparent)
/// title-bar region, so the native traffic lights show through on the left.
/// All data shown is real session state — nothing fabricated.

// MARK: - Launch-screen session state

/// The live Claude state of a session as surfaced on the launch screen. Only
/// *open* sessions have a real state; everything listed but not open is `idle`.
enum LaunchSessionState {
    case done, awaiting, working, active, idle
}

// MARK: - Row model

struct SessionRowModel {
    let index: Int
    let repoName: String
    let sessionName: String
    let worktreeName: String
    let repoPath: String
    let commitSha: String?
    let commitURL: String?
    let isActive: Bool
    let statusColor: NSColor?
    let prInfos: [GitHubPRInfo]
    let diffStats: (added: Int, deleted: Int)?
}

enum PRStyle {
    static func color(for state: PRState) -> NSColor {
        switch state {
        case .open:   return Theme.green
        case .draft:  return Theme.fg3
        case .merged: return Theme.violet
        case .closed: return Theme.red
        }
    }
    static func label(for state: PRState) -> String {
        switch state {
        case .open:   return "Open"
        case .draft:  return "Draft"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }
}

// MARK: - Session strip (horizontal)

final class SessionStrip: NSView {
    static let barHeight: CGFloat = 46

    var onSelectSession: ((Int) -> Void)?
    var onCloseSession: ((Int) -> Void)?
    var onNewSession: (() -> Void)?

    /// Left inset so the first tab clears the native window buttons.
    private let leftInset: CGFloat = 78
    private var tabViews: [SessionTabView] = []
    private let plusButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.bg0.cgColor

        plusButton.image = Theme.symbol("plus", size: 12.5)
        plusButton.imagePosition = .imageOnly
        plusButton.isBordered = false
        plusButton.contentTintColor = Theme.fg3
        plusButton.toolTip = "New Session"
        plusButton.target = self
        plusButton.action = #selector(plusClicked)
        addSubview(plusButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(rows: [SessionRowModel]) {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        var x = leftInset
        for model in rows {
            let tab = SessionTabView(
                model: model,
                height: Self.barHeight,
                onSelect: { [weak self] i in self?.onSelectSession?(i) },
                onClose: { [weak self] i in self?.onCloseSession?(i) }
            )
            tab.frame.origin = CGPoint(x: x, y: 0)
            addSubview(tab)
            tabViews.append(tab)
            x += tab.frame.width
        }

        plusButton.frame = NSRect(x: x + 4, y: (Self.barHeight - 22) / 2, width: 26, height: 22)
    }

    @objc private func plusClicked() { onNewSession?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Theme.line1.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

// MARK: - Session tab

private final class SessionTabView: NSView {
    private let index: Int
    private let isActive: Bool
    private let statusColor: NSColor?
    private let onSelect: (Int) -> Void
    private let onClose: (Int) -> Void
    private let closeBtn = NSButton()
    private var trackingArea: NSTrackingArea?

    init(model: SessionRowModel, height: CGFloat,
         onSelect: @escaping (Int) -> Void, onClose: @escaping (Int) -> Void) {
        self.index = model.index
        self.isActive = model.isActive
        self.statusColor = model.statusColor
        self.onSelect = onSelect
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        applyBackground(hover: false)

        let hasStatus = statusColor != nil
        let textX: CGFloat = 14
        let nameX: CGFloat = hasStatus ? textX + 12 : textX

        // State dot, aligned with the session name (lower line).
        if let color = statusColor {
            let dot = NSView(frame: NSRect(x: textX, y: 13, width: 6, height: 6))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            dot.layer?.backgroundColor = color.cgColor
            addSubview(dot)
        }

        // Repo (small, muted) over session name.
        let repoLabel = NSTextField(labelWithString: model.repoName.uppercased())
        repoLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        repoLabel.textColor = Theme.fg4
        repoLabel.lineBreakMode = .byTruncatingTail
        repoLabel.frame = NSRect(x: textX, y: 26, width: 160, height: 13)
        addSubview(repoLabel)

        let nameLabel = NSTextField(labelWithString: model.sessionName)
        nameLabel.font = .systemFont(ofSize: 13, weight: isActive ? .semibold : .medium)
        nameLabel.textColor = (isActive || hasStatus) ? Theme.fg1 : Theme.fg2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: nameX, y: 7, width: 160, height: 17)
        addSubview(nameLabel)

        // Detach (hover only).
        closeBtn.image = Theme.symbol("xmark", size: 9.5)
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.contentTintColor = Theme.fg3
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.isHidden = true
        closeBtn.toolTip = "Detach Session"
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        addSubview(closeBtn)

        // Size to content.
        let textWidth = max(repoLabel.intrinsicContentSize.width + (nameX - textX),
                            nameLabel.intrinsicContentSize.width + (nameX - textX))
        let width = min(max(textWidth + textX + 30, 140), 240)
        frame = NSRect(x: 0, y: 0, width: width, height: height)
        repoLabel.frame.size.width = width - textX - 26
        nameLabel.frame.size.width = width - nameX - 26
        closeBtn.frame = NSRect(x: width - 24, y: (height - 16) / 2, width: 16, height: 16)

        // Active underline (sits just above the strip's bottom hairline).
        if isActive {
            let underline = NSView(frame: NSRect(x: 0, y: 1, width: width, height: 2))
            underline.autoresizingMask = [.width]
            underline.wantsLayer = true
            underline.layer?.backgroundColor = Theme.accent.cgColor
            addSubview(underline)
        }

        // Right hairline seam between tabs.
        let seam = NSView(frame: NSRect(x: width - 1, y: 8, width: 1, height: height - 16))
        seam.wantsLayer = true
        seam.layer?.backgroundColor = Theme.line1.withAlphaComponent(0.7).cgColor
        addSubview(seam)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyBackground(hover: Bool) {
        if isActive {
            layer?.backgroundColor = Theme.bg2.cgColor
        } else if let color = statusColor {
            layer?.backgroundColor = color.withAlphaComponent(hover ? 0.18 : 0.12).cgColor
        } else {
            layer?.backgroundColor = (hover ? Theme.bg2 : NSColor.clear).cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
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
        if !closeBtn.frame.contains(loc) { onSelect(index) }
    }
    @objc private func closeClicked() { onClose(index) }
}

// MARK: - Status footer

final class NeetlyStatusBar: NSView {
    var onOpenCommit: (() -> Void)?
    var onOpenPR: ((URL) -> Void)?

    private let cluster = NSStackView()
    private var prURLs: [NSButton: URL] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.bg0.cgColor

        cluster.orientation = .horizontal
        cluster.spacing = 10
        cluster.alignment = .centerY
        cluster.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cluster)
        NSLayoutConstraint.activate([
            cluster.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            cluster.centerYAnchor.constraint(equalTo: centerYAnchor),
            cluster.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(active: SessionRowModel?) {
        cluster.arrangedSubviews.forEach { $0.removeFromSuperview() }
        prURLs.removeAll()
        guard let a = active else { return }

        func text(_ str: String, _ color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
            let l = NSTextField(labelWithString: str)
            l.font = Theme.mono(11.5, weight: weight)
            l.textColor = color
            return l
        }

        cluster.addArrangedSubview(text(a.worktreeName, Theme.fg2))

        if let stats = a.diffStats, stats.added > 0 || stats.deleted > 0 {
            if stats.added > 0 { cluster.addArrangedSubview(text("+\(stats.added)", Theme.green, weight: .medium)) }
            if stats.deleted > 0 { cluster.addArrangedSubview(text("\u{2212}\(stats.deleted)", Theme.red, weight: .medium)) }
            cluster.addArrangedSubview(text("●", Theme.amber))  // uncommitted marker
        }

        cluster.addArrangedSubview(text("·", Theme.fg4))

        if let sha = a.commitSha {
            if a.commitURL != nil {
                let btn = NSButton()
                btn.isBordered = false
                btn.attributedTitle = NSAttributedString(string: sha, attributes: [
                    .font: Theme.mono(11.5), .foregroundColor: Theme.fg3,
                ])
                btn.toolTip = "Open commit on GitHub"
                btn.target = self
                btn.action = #selector(commitClicked)
                cluster.addArrangedSubview(btn)
            } else {
                cluster.addArrangedSubview(text(sha, Theme.fg3))
            }
        }

        for pr in a.prInfos {
            let color = PRStyle.color(for: pr.state)
            let btn = NSButton()
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 4
            btn.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
            btn.isBordered = false
            btn.attributedTitle = NSAttributedString(string: " PR #\(pr.number) \(PRStyle.label(for: pr.state)) \u{2197} ", attributes: [
                .font: Theme.mono(11.5, weight: .medium), .foregroundColor: color,
            ])
            btn.toolTip = "#\(pr.number) \(pr.title)"
            btn.target = self
            btn.action = #selector(prClicked(_:))
            if let url = URL(string: pr.url) { prURLs[btn] = url }
            cluster.addArrangedSubview(btn)
        }
    }

    @objc private func commitClicked() { onOpenCommit?() }
    @objc private func prClicked(_ sender: NSButton) {
        if let url = prURLs[sender] { onOpenPR?(url) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Theme.line1.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}
