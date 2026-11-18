//
//  PlatformScreen.swift
//  FocusYS
//
//  A platform's web view with a compact top bar (Back · name · Home),
//  a discreet progress line, an error state with retry and the
//  "… blocked" toast. Home stays usable while the page loads.
//

import SwiftUI

struct PlatformScreen: View {
    let session: WebSession
    let onHome: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                WebViewContainer(webView: session.webView)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { toast }
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.22), value: session.toast)
        }
        .background(Color(.systemBackground))
    }

    private var isFailed: Bool {
        if case .failed = session.loadState { return true }
        return false
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 4) {
            BarButton(title: "Back", systemImage: "chevron.backward", action: session.goBack)
                .disabled(!session.canGoBack)
                .accessibilityHint("Goes to the previous page in \(session.platform.displayName)")

            Spacer(minLength: 8)

            Text(session.platform.displayName)
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            BarButton(title: "Home", systemImage: "house", action: onHome)
                .accessibilityHint("Returns to the FocusYS home screen")
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
        .background(.bar)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .leading) {
                Divider()
                if session.loadState == .loading {
                    LoadingLine(progress: session.progress)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.loadState == .loading)
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

// MARK: - Pieces

private struct BarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.body.weight(.medium))
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.6))
    }
}

/// Thin determinate line under the top bar.
private struct LoadingLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: max(24, proxy.size.width * min(max(progress, 0.08), 1)), height: 2)
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}

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
