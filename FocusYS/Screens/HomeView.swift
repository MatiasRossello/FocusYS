//
//  HomeView.swift
//  FocusYS
//
//  Native home screen: the app name, "Choose a platform" and one large
//  row per platform, placed toward the bottom so they are reachable with
//  one hand.
//

import SwiftUI

struct HomeView: View {
    let onSelect: (Platform) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 40)
                    Text("Choose a platform")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 14)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 12) {
                        ForEach(Platform.allCases) { platform in
                            PlatformRow(platform: platform) { onSelect(platform) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus\(Text("YS").foregroundStyle(Color.accentColor))")
            .font(.largeTitle.weight(.bold))
            .accessibilityLabel("FocusYS")
            .accessibilityAddTraits(.isHeader)

            Text("Focus Your Self")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Row

private struct PlatformRow: View {
    let platform: Platform
    let action: () -> Void

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 46
    @Environment(\.dynamicTypeSize) private var typeSize

    private var tileSize: CGFloat { min(iconSize, 64) }

    /// Side by side normally; stacked at accessibility text sizes so the
    /// names never break mid-word.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    var body: some View {
        Button(action: action) {
            layout {
                PlatformGlyph(platform: platform, size: tileSize)
                    .frame(width: tileSize, height: tileSize)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(platform.filterSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.forward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.displayName)
        .accessibilityValue(platform.filterSummary)
        .accessibilityHint("Opens \(platform.displayName) inside FocusYS")
        .accessibilityAddTraits(.isButton)
    }
}

/// Recognizable monochrome symbol for each platform (SF Symbols / Unicode,
/// no third-party logo assets).
private struct PlatformGlyph: View {
    let platform: Platform
    /// Side of the tile; the glyph scales with it, never past it.
    let size: CGFloat

    var body: some View {
        Group {
            switch platform {
            case .instagram:
                Image(systemName: "camera")
                    .font(.system(size: size * 0.46, weight: .medium))
            case .youtube:
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: size * 0.46))
            case .x:
                Text(verbatim: "𝕏")
                    .font(.system(size: size * 0.6, weight: .bold))
            }
        }
        .foregroundStyle(.primary)
        .accessibilityHidden(true)
    }
}

// MARK: - Press feedback

/// Slight, immediate scale-down while the finger is down. With Reduce Motion
/// the row dims instead of scaling.
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

#Preview {
    HomeView { _ in }
}
