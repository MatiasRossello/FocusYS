//
//  BlocksView.swift
//  FocusYS
//
//  Sheet to block a platform for a while: a preset (1 hour, rest of today,
//  tomorrow) or a custom range, plus the list of active and scheduled
//  blocks. Active blocks can't be removed; scheduled ones can.
//

import SwiftUI

struct BlocksView: View {
    let store: BlockStore
    let now: Date

    @State private var platform: Platform
    @State private var preset: BlockPreset
    @State private var customStart: Date
    @State private var customEnd: Date
    @State private var pendingRule: BlockRule?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(store: BlockStore, now: Date, platform: Platform = .x, preset: BlockPreset = .tomorrow) {
        self.store = store
        self.now = now
        _platform = State(initialValue: platform)
        _preset = State(initialValue: preset)
        let tomorrow = BlockPreset.tomorrow.interval(from: now)!
        _customStart = State(initialValue: tomorrow.start)
        _customEnd = State(initialValue: tomorrow.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                newBlockSection
                activeSection
                upcomingSection
            }
            .navigationTitle("Blocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingRule.map { "Block \($0.platform.displayName) now?" } ?? "",
                isPresented: Binding(get: { pendingRule != nil }, set: { if !$0 { pendingRule = nil } }),
                titleVisibility: .visible,
                presenting: pendingRule
            ) { rule in
                Button("Block until \(rule.end.blockDescription(relativeTo: now))", role: .destructive) {
                    store.add(rule)
                    pendingRule = nil
                }
                Button("Cancel", role: .cancel) { pendingRule = nil }
            } message: { _ in
                Text("It starts right away and can't be turned off until it ends.")
            }
            .alert("Can't add this block",
                   isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: New block

    private var newBlockSection: some View {
        Section {
            Picker("Platform", selection: $platform) {
                ForEach(Platform.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            Picker("When", selection: $preset) {
                ForEach(BlockPreset.allCases) { Text($0.title).tag($0) }
            }

            if preset == .custom {
                DatePicker("From", selection: $customStart, in: now..., displayedComponents: [.date, .hourAndMinute])
                DatePicker("Until", selection: $customEnd, in: customStart..., displayedComponents: [.date, .hourAndMinute])
            }

            Button(action: addBlock) {
                Label("Block \(platform.displayName)", systemImage: "hourglass")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("New block")
        } footer: {
            Text(summary + "\nOnce a block starts, it can't be turned off until it ends.")
        }
    }

    private var selectedInterval: (start: Date, end: Date) {
        if let interval = preset.interval(from: now) { return (interval.start, interval.end) }
        return (customStart, customEnd)
    }

    private var summary: String {
        let (start, end) = selectedInterval
        let from = start <= now ? "now" : start.blockDescription(relativeTo: now)
        return "\(platform.displayName) will be blocked from \(from) until \(end.blockDescription(relativeTo: now))."
    }

    private func addBlock() {
        let (start, end) = selectedInterval
        do {
            let rule = try store.validate(platform: platform, start: start, end: end, now: now)
            if rule.isActive(at: now) {
                pendingRule = rule          // starts now → ask first
            } else {
                store.add(rule)             // scheduled → can still be deleted
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Lists

    @ViewBuilder
    private var activeSection: some View {
        let active = store.active(at: now)
        if !active.isEmpty {
            Section("Active") {
                ForEach(active) { rule in
                    BlockRow(rule: rule, now: now, isActive: true)
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let upcoming = store.upcoming(at: now)
        if !upcoming.isEmpty {
            Section {
                ForEach(upcoming) { rule in
                    BlockRow(rule: rule, now: now, isActive: false)
                        .swipeActions {
                            Button("Delete", role: .destructive) { store.remove(rule, now: .now) }
                        }
                        .accessibilityAction(named: "Delete") { store.remove(rule, now: .now) }
                }
            } header: {
                Text("Scheduled")
            } footer: {
                Text("Swipe left to delete a scheduled block before it starts.")
            }
        }
    }
}

private struct BlockRow: View {
    let rule: BlockRule
    let now: Date
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "lock.fill" : "calendar")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.platform.displayName)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if isActive {
            return "Until \(rule.end.blockDescription(relativeTo: now))"
        }
        return "\(rule.start.blockDescription(relativeTo: now)) – \(rule.end.blockDescription(relativeTo: now))"
    }
}
