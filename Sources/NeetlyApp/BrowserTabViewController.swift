import AppKit
import WebKit

class BrowserTabViewController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    let tabId = UUID()
    let seqId = SeqCounter.shared.nextId()
    let initialURL: String
    private(set) var webView: WKWebView!
    private var urlBar: NSTextField!
    // Toolbar pieces kept so they can be re-themed on a theme change.
    private var navButtons: [NSButton] = []
    private var urlPillView: NSView?
    private var lockIconView: NSImageView?
    private var toolbarSeparator: NSView?
    private(set) var currentTitle: String = "Browser"
    private(set) var favicon: NSImage?
    private(set) var hasCompletedInitialLoad = false
    private var retryTimer: DispatchSourceTimer?
    /// Used when WebKit asks to create a new webview (target=_blank links).
    /// The pane provides a preinstalled WKWebView from WebKit's configuration.
    private var preinstalledWebView: WKWebView?
    /// Callback when title or favicon changes, so the pane can refresh the tab bar.
    var onTitleChanged: (() -> Void)?
    /// Called when the page wants to open a link in a new tab (target=_blank).
    /// The pane creates a new BrowserTabViewController using the provided webView.
    var onRequestNewTab: ((WKWebView) -> Void)?

    init(url: String, preinstalledWebView: WKWebView? = nil) {
        self.initialURL = url
        self.preinstalledWebView = preinstalledWebView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Make the web view first responder so keyboard focus lands in this pane
    /// when its tab is selected — mirrors the terminal's `focusTerminal()`.
    /// Without this, switching to a browser tab leaves the firstResponder on
    /// the window, so pane-targeted shortcuts can't tell which pane is active.
    func focusContent() {
        view.window?.makeFirstResponder(webView)
    }

    /// Re-apply themed colors to the browser toolbar after a theme change.
    /// (Web page content is the site's own and isn't themed.)
    func applyTheme() {
        guard isViewLoaded else { return }
        view.layer?.backgroundColor = Theme.bg1.cgColor
        navButtons.forEach { $0.contentTintColor = Theme.fg3 }
        urlPillView?.layer?.backgroundColor = Theme.bg0.cgColor
        lockIconView?.contentTintColor = Theme.fg4
        urlBar?.textColor = Theme.fg2
        toolbarSeparator?.layer?.backgroundColor = Theme.line1.cgColor
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.bg1.cgColor

        // Borderless, muted nav buttons — matching the design's slim WebKit toolbar.
        func navButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
            let b = NSButton()
            b.image = Theme.symbol(symbol, size: 12.5)
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.contentTintColor = Theme.fg3
            b.toolTip = tip
            b.target = self
            b.action = action
            b.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(b)
            self.navButtons.append(b)
            return b
        }
        let backButton = navButton("chevron.left", tip: "Back", action: #selector(goBack))
        let forwardButton = navButton("chevron.right", tip: "Forward", action: #selector(goForward))
        let reloadButton = navButton("arrow.clockwise", tip: "Reload", action: #selector(reload))

        // URL bar — sits inside a rounded dark pill with a leading lock glyph.
        let urlPill = NSView()
        urlPill.wantsLayer = true
        urlPill.layer?.backgroundColor = Theme.bg0.cgColor
        urlPill.layer?.cornerRadius = 5
        urlPill.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(urlPill)
        urlPillView = urlPill

        let lockIcon = NSImageView()
        lockIcon.image = Theme.symbol("lock.fill", size: 9.5)
        lockIcon.contentTintColor = Theme.fg4
        lockIcon.imageScaling = .scaleProportionallyDown
        lockIcon.translatesAutoresizingMaskIntoConstraints = false
        urlPill.addSubview(lockIcon)
        lockIconView = lockIcon

        urlBar = NSTextField()
        urlBar.stringValue = initialURL
        urlBar.font = Theme.mono(11.5)
        urlBar.textColor = Theme.fg2
        urlBar.placeholderString = "Enter URL\u{2026}"
        urlBar.isBordered = false
        urlBar.drawsBackground = false
        urlBar.focusRingType = .none
        urlBar.target = self
        urlBar.action = #selector(urlBarAction)
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        urlPill.addSubview(urlBar)

        // Hairline under the toolbar.
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = Theme.line1.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)
        toolbarSeparator = separator

        // Web view — use preinstalled one (from a target=_blank link) or create fresh
        if let pre = preinstalledWebView {
            webView = pre
        } else {
            let config = WKWebViewConfiguration()
            webView = WKWebView(frame: .zero, configuration: config)
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.addObserver(self, forKeyPath: "URL", options: [.new], context: nil)

        // Expose to Safari's Web Inspector.
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        } else {
            webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }

        container.addSubview(webView)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            backButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            backButton.widthAnchor.constraint(equalToConstant: 24),
            backButton.heightAnchor.constraint(equalToConstant: 22),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.topAnchor.constraint(equalTo: backButton.topAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 24),
            forwardButton.heightAnchor.constraint(equalToConstant: 22),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 2),
            reloadButton.topAnchor.constraint(equalTo: backButton.topAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 24),
            reloadButton.heightAnchor.constraint(equalToConstant: 22),

            urlPill.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 8),
            urlPill.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            urlPill.topAnchor.constraint(equalTo: backButton.topAnchor),
            urlPill.heightAnchor.constraint(equalToConstant: 22),

            lockIcon.leadingAnchor.constraint(equalTo: urlPill.leadingAnchor, constant: 9),
            lockIcon.centerYAnchor.constraint(equalTo: urlPill.centerYAnchor),
            lockIcon.widthAnchor.constraint(equalToConstant: 10),
            lockIcon.heightAnchor.constraint(equalToConstant: 10),

            urlBar.leadingAnchor.constraint(equalTo: lockIcon.trailingAnchor, constant: 6),
            urlBar.trailingAnchor.constraint(equalTo: urlPill.trailingAnchor, constant: -8),
            urlBar.centerYAnchor.constraint(equalTo: urlPill.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 6),
            separator.heightAnchor.constraint(equalToConstant: 1),

            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if preinstalledWebView != nil {
            // WebKit will load the target URL into this webView itself — do nothing.
        } else if initialURL.isEmpty {
            // Focus the URL bar so user can type
            DispatchQueue.main.async { [weak self] in
                self?.view.window?.makeFirstResponder(self?.urlBar)
            }
        } else {
            navigate(to: initialURL)
            startInitialLoadRetry()
        }
    }

    /// Retry the initial load every 3 seconds until it succeeds. Useful when the
    /// dev server is still booting when the browser tab is opened via `neetly visit`.
    private func startInitialLoadRetry() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 3, repeating: 3.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.hasCompletedInitialLoad {
                self.retryTimer?.cancel()
                self.retryTimer = nil
                return
            }
            NSLog("BrowserTab: retrying initial load for \(self.initialURL)")
            self.navigate(to: self.initialURL)
        }
        timer.resume()
        retryTimer = timer
    }

    @objc private func urlBarAction() {
        navigate(to: urlBar.stringValue)
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func reload() {
        if webView.url != nil {
            webView.reloadFromOrigin()
        } else {
            // Initial load never succeeded — navigate fresh
            navigate(to: urlBar.stringValue.isEmpty ? initialURL : urlBar.stringValue)
        }
    }

    /// Force reload — same as clicking R. Skips if initial load hasn't completed.
    @objc func forceReload() {
        guard hasCompletedInitialLoad else { return }
        webView.reloadFromOrigin()
    }

    func navigate(to urlString: String) {
        var str = urlString.trimmingCharacters(in: .whitespaces)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "https://" + str
        }
        guard let url = URL(string: str) else { return }
        webView.load(URLRequest(url: url))
        urlBar.stringValue = str
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            // Reload was cancelled by a competing navigation — retry after a short delay
            NSLog("BrowserTab: reload cancelled, retrying in 1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.webView.reloadFromOrigin()
            }
            return
        }
        NSLog("BrowserTab: provisional navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }  // handled above
        NSLog("BrowserTab: navigation failed: \(error)")
    }

    /// Handle target="_blank" links: WebKit sometimes sends them here with
    /// targetFrame == nil without calling createWebViewWith. We spawn a new tab.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            // Open in a new tab via the pane
            let newWebView = WKWebView(frame: .zero, configuration: webView.configuration)
            onRequestNewTab?(newWebView)
            newWebView.load(URLRequest(url: url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasCompletedInitialLoad = true
        if let url = webView.url?.absoluteString {
            urlBar.stringValue = url
        }
        currentTitle = shortTitle(from: webView.title, url: webView.url)
        fetchFavicon(for: webView.url)
        onTitleChanged?()
    }

    // MARK: - WKUIDelegate

    /// Called when a page wants to open a link in a new tab (target="_blank" or
    /// window.open). We create a new webview with the same configuration, hand it
    /// to the pane to wrap in a new BrowserTabViewController, and return it so
    /// WebKit loads the target URL into it automatically.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let newWebView = WKWebView(frame: .zero, configuration: configuration)
        onRequestNewTab?(newWebView)
        return newWebView
    }

    /// Show an NSOpenPanel when the page triggers `<input type="file">`.
    /// WKWebView has no built-in file picker — without this delegate method,
    /// clicking a file input is silently a no-op.
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection

        let window = webView.window ?? view.window
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    /// Build a short tab title: first two words of the page title, or the hostname.
    private func shortTitle(from title: String?, url: URL?) -> String {
        if let title = title, !title.isEmpty {
            let words = title.split(separator: " ").prefix(2)
            return words.joined(separator: " ")
        }
        return url?.host ?? "Browser"
    }

    /// Fetch /favicon.ico from the site's origin.
    private func fetchFavicon(for url: URL?) {
        guard let url = url,
              let scheme = url.scheme,
              let host = url.host,
              let faviconURL = URL(string: "\(scheme)://\(host)/favicon.ico") else { return }

        URLSession.shared.dataTask(with: faviconURL) { [weak self] data, response, _ in
            guard let data = data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.favicon = image
                self?.onTitleChanged?()
            }
        }.resume()
    }

    // MARK: - KVO

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == "URL", let url = webView.url?.absoluteString {
            urlBar.stringValue = url
        }
    }

    deinit {
        webView?.removeObserver(self, forKeyPath: "URL")
        retryTimer?.cancel()
    }
}
