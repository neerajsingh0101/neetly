import AppKit
import WebKit

class BrowserTabViewController: NSViewController, WKNavigationDelegate {
    let tabId = UUID()
    let initialURL: String
    private var webView: WKWebView!
    private var urlBar: NSTextField!
    private(set) var currentTitle: String = "Browser"

    init(url: String) {
        self.initialURL = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        // URL bar
        urlBar = NSTextField()
        urlBar.stringValue = initialURL
        urlBar.font = .systemFont(ofSize: 13)
        urlBar.placeholderString = "Enter URL..."
        urlBar.target = self
        urlBar.action = #selector(urlBarAction)
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(urlBar)

        // Navigation buttons
        let backButton = NSButton(title: "<", target: self, action: #selector(goBack))
        backButton.bezelStyle = .recessed
        backButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backButton)

        let forwardButton = NSButton(title: ">", target: self, action: #selector(goForward))
        forwardButton.bezelStyle = .recessed
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(forwardButton)

        let reloadButton = NSButton(title: "R", target: self, action: #selector(reload))
        reloadButton.bezelStyle = .recessed
        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(reloadButton)

        // Web view
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            backButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 24),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            forwardButton.widthAnchor.constraint(equalToConstant: 28),
            forwardButton.heightAnchor.constraint(equalToConstant: 24),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 2),
            reloadButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            reloadButton.widthAnchor.constraint(equalToConstant: 28),
            reloadButton.heightAnchor.constraint(equalToConstant: 24),

            urlBar.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 4),
            urlBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            urlBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            urlBar.heightAnchor.constraint(equalToConstant: 24),

            webView.topAnchor.constraint(equalTo: urlBar.bottomAnchor, constant: 4),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if initialURL.isEmpty {
            // Focus the URL bar so user can type
            DispatchQueue.main.async { [weak self] in
                self?.view.window?.makeFirstResponder(self?.urlBar)
            }
        } else {
            navigate(to: initialURL)
        }
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
        webView.reload()
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString {
            urlBar.stringValue = url
        }
        currentTitle = webView.title ?? webView.url?.host ?? "Browser"
    }
}
