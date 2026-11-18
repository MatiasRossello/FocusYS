//
//  PlatformScreen.swift
//  FocusYS
//
//  A platform shown full screen, like its own app: no browser chrome. The
//  status-bar area takes the site's own header color, a small floating Home
//  button (draggable, with a loading ring) returns to FocusYS, and a swipe
//  from the left edge goes back — or Home once there is no history left.
//  Also hosts the error state with retry and the "… blocked" toast.
//

import SwiftUI

struct PlatformScreen: View {
    let session: WebSession
    let onHome: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                WebViewContainer(webView: session.webView, onEdgeSwipeHome: onHome)
                    .opacity(isFailed ? 0 : 1)
                    .accessibilityHidden(isFailed)

                if !session.hasContent && !isFailed {
                    ProgressView()
                        .controlSize(.regular)
                        .accessibilityLabel("Loading \(session.platform.displayName)")
                }
                if case .failed(let message) = session.loadState {
                    ErrorStateView(message: message, retry: session.retry)
                }

                FloatingHomeButton(
                    platformName: session.platform.displayName,
                    isLoading: session.loadState == .loading,
                    progress: session.progress,
                    canGoBack: session.canGoBack,
                    container: proxy.size,
                    onHome: onHome,
                    onBack: session.goBack
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { toast }
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.22), value: session.toast)
        }
        // The web view runs edge to edge at the bottom (WebKit paints the
        // page's own background under the home indicator); the status-bar
        // area takes the site's header color so it reads as one surface.
        .ignoresSafeArea(.container, edges: .bottom)
        .background(session.statusBarColor.ignoresSafeArea())
    }

    private var isFailed: Bool {
        if case .failed = session.loadState { return true }
        return false
    }

    // MARK: Toast

    @ViewBuilder
    private var toast: some View {
        if let toast = session.toast {
            Label(toast.message, systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(.systemBackground))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color(.label).opacity(0.88)))
                .padding(.top, 12)
                .padding(.horizontal, 24)
                .id(toast.id)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -12)))
                .onTapGesture(perform: session.dismissToast)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

// MARK: - Floating Home button

/// Small glass button that returns to the FocusYS home screen. It can be
/// dragged anywhere and snaps to the nearest side, so it never has to cover
/// a control of the site; its position is remembered. While a page loads a
/// thin ring around it shows progress.
private struct FloatingHomeButton: View {
    let platformName: String
    let isLoading: Bool
    let progress: Double
    let canGoBack: Bool
    let container: CGSize
    let onHome: () -> Void
    let onBack: () -> Void

    @AppStorage("floatingHome.trailing") private var onTrailingSide = true
    @AppStorage("floatingHome.y") private var yFraction = 0.80
    @State private var dragOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let diameter: CGFloat = 44
    private let margin: CGFloat = 10

    var body: some View {
        Button(action: onHome) {
            Image(systemName: "house.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay { loadingRing }
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .position(x: restingX + dragOffset.width, y: restingY + dragOffset.height)
        .highPriorityGesture(dragGesture)
        .animation(.easeOut(duration: 0.2), value: isLoading)
        .accessibilityLabel("Home")
        .accessibilityValue(isLoading ? "Loading" : "")
        .accessibilityHint("Returns to the FocusYS home screen")
        .accessibilityAction(named: "Go back in \(platformName)") {
            if canGoBack { onBack() }
        }
    }

    // MARK: Position

    private var minY: CGFloat { diameter / 2 + 8 }
    private var maxY: CGFloat { max(minY, container.height - diameter / 2 - 8) }

    private var restingX: CGFloat {
        onTrailingSide ? container.width - margin - diameter / 2 : margin + diameter / 2
    }

    private var restingY: CGFloat {
        min(max(yFraction * container.height, minY), maxY)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let finalX = restingX + value.translation.width
                let finalY = min(max(restingY + value.translation.height, minY), maxY)
                let snap = {
                    onTrailingSide = finalX > container.width / 2
                    yFraction = container.height > 0 ? finalY / container.height : 0.8
                    dragOffset = .zero
                }
                if reduceMotion { snap() } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8), snap)
                }
            }
    }

    // MARK: Loading ring

    @ViewBuilder
    private var loadingRing: some View {
        if isLoading {
            Circle()
                .trim(from: 0, to: min(max(progress, 0.08), 1))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(-3)
                .animation(.easeOut(duration: 0.25), value: progress)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Error state

private struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: retry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding(32)
        .frame(maxWidth: 360)
    }
}
