//
//  WebViewContainer.swift
//  FocusYS
//
//  Hosts a session's existing WKWebView inside SwiftUI. The web view is
//  never recreated: it is only re-parented, so leaving and returning to a
//  platform does not reload or flash the page.
//
//  Navigation gestures, like a native navigation stack:
//  - left-edge swipe with history → WebKit's own back gesture;
//  - left-edge swipe with no history left → back to the FocusYS home screen.
//

import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    let onEdgeSwipeHome: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        attach(to: container)

        let edgePan = UIScreenEdgePanGestureRecognizer(target: context.coordinator,
                                                       action: #selector(Coordinator.handleEdgePan(_:)))
        edgePan.edges = .left
        edgePan.delegate = context.coordinator
        container.addGestureRecognizer(edgePan)

        context.coordinator.webView = webView
        context.coordinator.onHome = onEdgeSwipeHome
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.onHome = onEdgeSwipeHome
        if webView.superview !== container {
            attach(to: container)
        }
    }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
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

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var webView: WKWebView?
        var onHome: (() -> Void)?

        @objc func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            let distance = gesture.translation(in: view).x
            let velocity = gesture.velocity(in: view).x
            if distance > view.bounds.width * 0.25 || velocity > 600 {
                onHome?()
            }
        }

        /// Only when the site has nothing to go back to; otherwise WebKit's
        /// own back-swipe handles the gesture.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !(webView?.canGoBack ?? false)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
