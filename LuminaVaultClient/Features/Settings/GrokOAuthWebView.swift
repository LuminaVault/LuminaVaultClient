// LuminaVaultClient/LuminaVaultClient/Features/Settings/GrokOAuthWebView.swift
//
// HER-240b — in-app WKWebView that hosts the xAI Grok OAuth flow and
// intercepts the loopback callback xAI requires.
//
// Why WKWebView instead of ASWebAuthenticationSession:
//   * xAI requires `redirect_uri = http://127.0.0.1:56121/callback` and
//     validates it against an allowlist. We can't swap in a custom scheme.
//   * `ASWebAuthenticationSession` only catches callbacks matching its
//     `callbackURLScheme` (a custom scheme). It can't intercept an `http://`
//     loopback URL.
//   * `WKWebView.decidePolicyFor navigationAction` runs on EVERY navigation
//     (including `http://127.0.0.1:56121/callback`) and lets us cancel
//     before the browser tries to load it (which would fail since the
//     loopback target lives inside the Hermes container on the server).
//
// The trade-off vs ASWebAuthenticationSession is that we don't share Safari
// cookies and the user re-enters their X credentials inside our sheet. Same
// trade-off Google Sign-In and other in-app flows accept.

import SwiftUI
import WebKit

struct GrokOAuthWebView: UIViewControllerRepresentable {
    let authorizeURL: URL
    /// Invoked with the full loopback callback URL (e.g.
    /// `http://127.0.0.1:56121/callback?code=…&state=…`) once the
    /// `WKNavigationDelegate` cancels the navigation. Always called on the
    /// main actor.
    let onCallback: (URL) -> Void
    /// Invoked when the underlying WebKit navigation fails so the parent
    /// sheet can surface the failure.
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> WebViewController {
        let controller = WebViewController(authorizeURL: authorizeURL)
        controller.onCallback = onCallback
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_: WebViewController, context _: Context) {}
}

final class WebViewController: UIViewController, WKNavigationDelegate {
    private let authorizeURL: URL
    private let webView = WKWebView()
    var onCallback: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    init(authorizeURL: URL) {
        self.authorizeURL = authorizeURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        webView.navigationDelegate = self
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: authorizeURL))
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void,
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if Self.isLoopbackCallback(url) {
            decisionHandler(.cancel)
            onCallback?(url)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        onError?(error)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        onError?(error)
    }

    // MARK: - Helpers

    /// Matches Hermes' fixed loopback redirect contract:
    /// `http://127.0.0.1:56121/callback`. Port is read at runtime in case
    /// upstream changes the default later; for now we accept any port to
    /// avoid hardcoding.
    static func isLoopbackCallback(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let isLoopback = host == "127.0.0.1" || host == "localhost"
        return isLoopback && url.path == "/callback"
    }
}
