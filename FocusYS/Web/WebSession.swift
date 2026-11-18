//
//  WebSession.swift
//  FocusYS
//
//  Owns one WKWebView per platform. It is created lazily the first time the
//  platform is opened and kept alive (with its page and history) while the
//  app keeps it in memory. Applies the native filter layer and installs the
//  platform's JavaScript filter.
//

import Foundation
import Observation
import UIKit
import WebKit

@Observable
final class WebSession: NSObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    let platform: Platform
    private let rules: PlatformRules

    private(set) var loadState: LoadState = .idle
    private(set) var progress: Double = 0
    private(set) var canGoBack = false
    /// True once the first page has painted something.
    private(set) var hasContent = false
    /// Current toast message (e.g. "Reel blocked"), cleared automatically.
    private(set) var toast: Toast?

    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let message: String
    }

    @ObservationIgnored private(set) var webView: WKWebView!
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var recentBlocks: [Date] = []

    static let messageHandlerName = "focusys"

    init(platform: Platform) {
        self.platform = platform
        self.rules = platform.rules
        super.init()
        self.webView = makeWebView()
        observe()
        load(platform.homeURL)
    }

    // MARK: - Setup

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Persistent, per-platform storage: keeps the platform's own login
        // between launches. FocusYS never reads cookies or credentials.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: platform.dataStoreID)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Safari-like UA suffix so the sites serve their normal mobile web
        // and sign-in pages instead of an "unsupported browser" screen.
        config.applicationNameForUserAgent = "Version/26.0 Mobile/15E148 Safari/604.1"
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        let controller = WKUserContentController()
        for script in Self.userScripts(for: platform) {
            controller.addUserScript(script)
        }
        controller.add(ScriptMessageProxy(owner: self), contentWorld: .defaultClient, name: Self.messageHandlerName)
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    /// The shared core plus the platform's own filter, injected only into the
    /// main frame and into an isolated JS world (the page cannot see or call
    /// them). The scripts also check the host themselves, so they stay inert
    /// on sign-in domains.
    private static func userScripts(for platform: Platform) -> [WKUserScript] {
        let config: [String: Any] = [
            "handler": messageHandlerName,
            "domains": platform.siteDomains,
        ]
        let configJSON = (try? JSONSerialization.data(withJSONObject: config))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let bootstrap = "window.__focusysConfig = \(configJSON);"

        var sources = [bootstrap]
        for name in ["focusys-core", platform.scriptName] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                assertionFailure("Missing bundled script \(name).js")
                continue
            }
            sources.append(source)
        }
        return [WKUserScript(source: sources.joined(separator: "\n;\n"),
                             injectionTime: .atDocumentStart,
                             forMainFrameOnly: true,
                             in: .defaultClient)]
    }

    private func observe() {
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.syncLoading(webView) }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            // Fires for same-document (pushState) changes too, which the
            // navigation delegate never sees. Native fallback for SPA routing.
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.urlDidChange(webView.url) }
            },
        ]
    }

    private func syncLoading(_ webView: WKWebView) {
        if webView.isLoading {
            if case .failed = loadState { return }
            loadState = .loading
        } else if loadState == .loading {
            loadState = .loaded
        }
    }

    // MARK: - Public actions

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func retry() {
        loadState = .loading
        if let url = webView.url, url.absoluteString != "about:blank" {
            webView.reload()
        } else {
            load(platform.homeURL)
        }
    }

    /// Pauses audio/video while the platform is off screen (Home visible).
    func setMediaSuspended(_ suspended: Bool) {
        if suspended {
            webView.pauseAllMediaPlayback()
        }
        webView.setAllMediaPlaybackSuspended(suspended)
    }

    #if DEBUG
    /// Loads a URL as a direct navigation (test hook; the filter still applies).
    func debugLoad(_ url: URL) { webView.load(URLRequest(url: url)) }
    #endif

    func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    // MARK: - Filtering

    private func load(_ url: URL) {
        loadState = .loading
        webView.load(URLRequest(url: url))
    }

    private func showBlocked(_ reason: BlockReason) {
        toastTask?.cancel()
        let toast = Toast(message: reason.message)
        self.toast = toast
        UIAccessibility.post(notification: .announcement, argument: reason.message)
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, self?.toast == toast else { return }
            self?.toast = nil
        }
    }

    /// Leaves a blocked page: back if there is allowed history, otherwise the
    /// platform's start page. Repeated hits in a short window always go to the
    /// start page, which is never blocked, so this cannot loop.
    private func leaveBlockedPage() {
        let now = Date()
        recentBlocks = recentBlocks.filter { now.timeIntervalSince($0) < 3 } + [now]
        if webView.canGoBack && recentBlocks.count <= 3 {
            webView.goBack()
        } else {
            recentBlocks.removeAll()
            load(platform.homeURL)
        }
    }

    private func urlDidChange(_ url: URL?) {
        #if DEBUG
        print("[FocusYS] url \(url?.absoluteString ?? "nil")")
        #endif
        guard let url, rules.isBlocked(url) else { return }
        // `url` also changes when a full load *starts*, before the navigation
        // delegate has decided. Re-check shortly after: if a provisional load
        // was cancelled by policy the URL has already reverted. What remains
        // is a same-document (pushState) route change into a blocked page.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, let current = self.webView.url,
                  let reason = self.rules.blockReason(for: current),
                  self.backForwardList(contains: current) else { return }
            await self.webView.pauseAllMediaPlayback()
            self.showBlocked(reason)
            self.leaveBlockedPage()
        }
    }

    /// True if `url` is the committed current history item (i.e. the page is
    /// really showing it, not just about to load it).
    private func backForwardList(contains url: URL) -> Bool {
        webView.backForwardList.currentItem?.url == url
    }

    fileprivate func handleScriptMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "blocked":
            let message = (dict["message"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(60)) }
            showBlocked(BlockReason(message: message ?? "Blocked"))
        default:
            break
        }
    }

    private func isInternal(_ url: URL) -> Bool {
        url.hostMatchesAny(platform.siteDomains) || url.hostMatchesAny(platform.authDomains)
    }

    private func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - WKNavigationDelegate

extension WebSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        #if DEBUG
        if isMainFrame { print("[FocusYS] nav \(platform.rawValue) \(url.absoluteString) blocked=\(rules.isBlocked(url))") }
        #endif

        // Sub-frames (captchas, embedded players, sign-in widgets) are left alone.
        guard isMainFrame else { return decisionHandler(.allow) }

        if let reason = rules.blockReason(for: url) {
            decisionHandler(.cancel)
            showBlocked(reason)
            // Opened directly with nothing allowed behind it → start page.
            let committed = webView.backForwardList.currentItem?.url
            if committed == nil || committed?.absoluteString == "about:blank" || rules.isBlocked(committed!) {
                load(platform.homeURL)
            }
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if !["http", "https", "about", "blob", "data"].contains(scheme) {
            // App deep links (instagram://, youtube://, twitter://, intent…)
            // would leave FocusYS for the unfiltered native app.
            return decisionHandler(.cancel)
        }

        // Links the user taps to other websites open in Safari; redirects to
        // other hosts are allowed so login / verification flows keep working.
        if navigationAction.navigationType == .linkActivated, ["http", "https"].contains(scheme), !isInternal(url) {
            openExternally(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadState = .loading
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        hasContent = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadState = .loaded
        hasContent = true
        #if DEBUG
        debugReportFilter(after: 6)
        #endif
    }

    #if DEBUG
    /// Logs what the JS filter hid / dimmed (Debug test hook).
    func debugReportFilter(after seconds: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self else { return }
            let js = """
            (function(){
              var d = function(sel){ return Array.from(document.querySelectorAll(sel)).map(function(e){
                var a = e.matches('a[href]') ? e : e.querySelector('a[href]');
                return e.tagName.toLowerCase() + (a ? ' ' + a.getAttribute('href') : '');
              }).slice(0, 12); };
              return JSON.stringify({ url: location.href, installed: !!window.FocusYS,
                hidden: d('[data-focusys-hidden]'), dimmed: d('[data-focusys-dim]'),
                shortsLinks: document.querySelectorAll('a[href*="/shorts"]').length });
            })()
            """
            let result = try? await self.webView.evaluateJavaScript(js, in: nil, contentWorld: .defaultClient)
            print("[FocusYS] filter \(self.platform.rawValue) \(result ?? "nil")")
        }
    }
    #endif

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func handle(_ error: Error) {
        let nsError = error as NSError
        // Cancelled navigations and ones we stopped by policy are not errors.
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return syncAfterCancel() }
        if nsError.domain == "WebKitErrorDomain" && (nsError.code == 102 || nsError.code == 204) { return syncAfterCancel() }

        let message: String
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            message = "You're offline. Check your connection and try again."
        case NSURLErrorTimedOut:
            message = "The page took too long to respond."
        default:
            message = "The page couldn't be loaded."
        }
        loadState = .failed(message)
    }

    private func syncAfterCancel() {
        if loadState == .loading && !webView.isLoading {
            loadState = hasContent ? .loaded : .idle
        }
    }
}

// MARK: - WKUIDelegate (new windows)

extension WebSession: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target="_blank" / window.open: apply the same rules, then keep the
        // platform in this web view and send other sites to Safari.
        guard let url = navigationAction.request.url else { return nil }
        if let reason = rules.blockReason(for: url) {
            showBlocked(reason)
        } else if isInternal(url) {
            webView.load(URLRequest(url: url))
        } else {
            openExternally(url)
        }
        return nil
    }
}

// MARK: - Script messages

/// Breaks the retain cycle WKUserContentController → handler → session.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: WebSession?
    init(owner: WebSession) { self.owner = owner }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only accept messages from the main frame of the platform's own site.
        guard message.frameInfo.isMainFrame,
              let owner,
              let url = message.frameInfo.request.url,
              url.hostMatchesAny(owner.platform.siteDomains) else { return }
        owner.handleScriptMessage(message.body)
    }
}
