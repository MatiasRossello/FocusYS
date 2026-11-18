//
//  WebViewContainer.swift
//  FocusYS
//
//  Hosts a session's existing WKWebView inside SwiftUI. The web view is
//  never recreated: it is only re-parented, so leaving and returning to a
//  platform does not reload or flash the page.
//

import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if webView.superview !== container {
            attach(to: container)
        }
    }

    static func dismantleUIView(_ container: UIView, coordinator: ()) {
        // Only detach if another container hasn't already taken the web view.
        for case let webView as WKWebView in container.subviews {
            webView.removeFromSuperview()
        }
    }

    private func attach(to container: UIView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
