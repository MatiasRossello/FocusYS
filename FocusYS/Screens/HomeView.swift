//
//  HomeView.swift
//  FocusYS
//
//  Native home screen: the app name, "Choose a platform" and one large
//  row per platform, placed toward the bottom so they are reachable with
//  one hand. Rows show block state; long-press a row for quick blocks, or
//  use the hourglass button to manage blocks.
//

import SwiftUI

struct HomeView: View {
    let blocks: BlockStore
    let now: Date
    let onSelect: (Platform) -> Void
    /// Opens the Blocks sheet, optionally preset to a platform / custom range.
    let onShowBlocks: (Platform?, BlockPreset?) -> Void

    @State private var pendingRule: BlockRule?
    @State private var blockedNotice: (platform: Platform, until: Date)?

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
                            row(for: platform)
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
        .confirmationDialog(
            pendingRule.map { "Block \($0.platform.displayName) now?" } ?? "",
            isPresented: Binding(get: { pendingRule != nil }, set: { if !$0 { pendingRule = nil } }),
            titleVisibility: .visible,
            presenting: pendingRule
        ) { rule in
            Button("Block until \(rule.end.blockDescription(relativeTo: now))", role: .destructive) {
                blocks.add(rule)
                pendingRule = nil
            }
            Button("Cancel", role: .cancel) { pendingRule = nil }
        } message: { _ in
            Text("It starts right away and can't be turned off until it ends.")
        }
        .alert(
            blockedNotice.map { "\($0.platform.displayName) is blocked" } ?? "",
            isPresented: Binding(get: { blockedNotice != nil }, set: { if !$0 { blockedNotice = nil } }),
            presenting: blockedNotice
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text("You blocked it until \(notice.until.blockDescription(relativeTo: now)).")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Focus\(Text("YS").foregroundStyle(Color.accentColor))")
                .font(.largeTitle.weight(.bold))
                .accessibilityLabel("FocusYS")
                .accessibilityAddTraits(.isHeader)

                Text("Focus Your Self")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            blocksButton
        }
    }

    private var hasBlocks: Bool {
        !blocks.active(at: now).isEmpty || !blocks.upcoming(at: now).isEmpty
    }

    private var blocksButton: some View {
        Button { onShowBlocks(nil, nil) } label: {
            Image(systemName: hasBlocks ? "hourglass.circle.fill" : "hourglass.circle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(hasBlocks ? Color.accentColor : .secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Blocks")
        .accessibilityHint("Block a platform for a while or see your blocks")
    }

    @ViewBuilder
    private func row(for platform: Platform) -> some View {
        let until = blocks.blockedUntil(platform, at: now)
        let upcoming = until == nil ? blocks.nextUpcoming(for: platform, at: now) : nil
        PlatformRow(platform: platform, blockedUntil: until, upcomingStart: upcoming?.start, now: now) {
            if let until {
                blockedNotice = (platform, until)
            } else {
                onSelect(platform)
            }
        }
        .contextMenu {
            if until == nil {
                Section("Block \(platform.displayName)") {
                    ForEach([BlockPreset.oneHour, .restOfToday, .tomorrow]) { preset in
                        Button { quickBlock(platform, preset) } label: {
                            Label(preset.title, systemImage: preset == .tomorrow ? "calendar" : "hourglass")
                        }
                    }
                    Button { onShowBlocks(platform, .custom) } label: {
                        Label("Custom…", systemImage: "slider.horizontal.3")
                    }
                }
            } else {
                Button { onShowBlocks(platform, nil) } label: {
                    Label("See blocks", systemImage: "lock")
                }
            }
        }
    }

    private func quickBlock(_ platform: Platform, _ preset: BlockPreset) {
        guard let interval = preset.interval(from: .now),
              let rule = try? blocks.validate(platform: platform, start: interval.start, end: interval.end) else { return }
        if rule.isActive(at: .now) {
            pendingRule = rule
        } else {
            blocks.add(rule)
        }
    }
}

// MARK: - Row

private struct PlatformRow: View {
    let platform: Platform
    let blockedUntil: Date?
    let upcomingStart: Date?
    let now: Date
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
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(blockedUntil != nil ? Color.accentColor : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !typeSize.isAccessibilitySize {
                    Image(systemName: blockedUntil != nil ? "lock.fill" : "chevron.forward")
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
            .opacity(blockedUntil != nil ? 0.55 : 1)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(platform.displayName)
        .accessibilityValue(subtitle)
        .accessibilityHint(blockedUntil != nil
                           ? "Blocked. Long press for options."
                           : "Opens \(platform.displayName) inside FocusYS. Long press to block it.")
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        if let blockedUntil {
            return "Blocked until \(blockedUntil.blockDescription(relativeTo: now))"
        }
        if let upcomingStart {
            return "\(platform.filterSummary) · Block from \(upcomingStart.blockDescription(relativeTo: now))"
        }
        return platform.filterSummary
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
    HomeView(blocks: BlockStore(), now: .now, onSelect: { _ in }, onShowBlocks: { _, _ in })
}
