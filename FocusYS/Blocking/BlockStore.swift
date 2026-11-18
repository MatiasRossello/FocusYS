//
//  BlockStore.swift
//  FocusYS
//
//  Time-based blocks for platforms inside FocusYS ("no X tomorrow").
//  Blocks are a commitment: once one has started it cannot be removed
//  until it ends. Blocks that haven't started yet can be deleted.
//  Stored locally in UserDefaults; nothing leaves the device.
//

import Foundation
import Observation

struct BlockRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var platform: Platform
    var start: Date
    var end: Date

    func isActive(at now: Date) -> Bool { start <= now && now < end }
    func isUpcoming(at now: Date) -> Bool { now < start }
}

/// Quick choices offered in the UI.
enum BlockPreset: String, CaseIterable, Identifiable {
    case oneHour, restOfToday, tomorrow, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour: "1 hour"
        case .restOfToday: "Rest of today"
        case .tomorrow: "Tomorrow"
        case .custom: "Custom"
        }
    }

    /// The period for this preset, or nil for `.custom`.
    func interval(from now: Date, calendar: Calendar = .current) -> DateInterval? {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        switch self {
        case .oneHour:
            return DateInterval(start: now, end: now.addingTimeInterval(3600))
        case .restOfToday:
            return DateInterval(start: now, end: startOfTomorrow)
        case .tomorrow:
            let dayAfter = calendar.date(byAdding: .day, value: 1, to: startOfTomorrow)!
            return DateInterval(start: startOfTomorrow, end: dayAfter)
        case .custom:
            return nil
        }
    }
}

@Observable
final class BlockStore {
    enum ValidationError: LocalizedError {
        case endBeforeStart, alreadyOver, tooLong

        var errorDescription: String? {
            switch self {
            case .endBeforeStart: "The end must be after the start."
            case .alreadyOver: "That period is already over."
            case .tooLong: "A block can last up to \(BlockStore.maxDays) days."
            }
        }
    }

    static let maxDays = 30
    private static let storageKey = "focusys.blocks.v1"

    private(set) var rules: [BlockRule] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([BlockRule].self, from: data) {
            rules = saved
        }
        pruneExpired()
    }

    // MARK: Queries

    /// When the platform's current block ends (chaining overlapping or
    /// back-to-back blocks), or nil if it isn't blocked right now.
    func blockedUntil(_ platform: Platform, at now: Date = .now) -> Date? {
        let mine = rules.filter { $0.platform == platform }
        guard var end = mine.filter({ $0.isActive(at: now) }).map(\.end).max() else { return nil }
        var extended = true
        while extended {
            extended = false
            for rule in mine where rule.start <= end && rule.end > end {
                end = rule.end
                extended = true
            }
        }
        return end
    }

    func isBlocked(_ platform: Platform, at now: Date = .now) -> Bool {
        blockedUntil(platform, at: now) != nil
    }

    /// The next block that hasn't started yet for this platform.
    func nextUpcoming(for platform: Platform, at now: Date = .now) -> BlockRule? {
        rules.filter { $0.platform == platform && $0.isUpcoming(at: now) }
            .min { $0.start < $1.start }
    }

    func active(at now: Date = .now) -> [BlockRule] {
        rules.filter { $0.isActive(at: now) }.sorted { $0.end < $1.end }
    }

    func upcoming(at now: Date = .now) -> [BlockRule] {
        rules.filter { $0.isUpcoming(at: now) }.sorted { $0.start < $1.start }
    }

    /// The next moment any block starts or ends, to refresh the UI and
    /// enforce blocks exactly on time.
    func nextTransition(after now: Date = .now) -> Date? {
        rules.flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
    }

    // MARK: Changes

    func validate(platform: Platform, start: Date, end: Date, now: Date = .now) throws -> BlockRule {
        let start = max(start, now)
        guard end > start else { throw end <= now ? ValidationError.alreadyOver : ValidationError.endBeforeStart }
        guard end.timeIntervalSince(start) <= Double(Self.maxDays) * 86_400 + 60 else { throw ValidationError.tooLong }
        return BlockRule(platform: platform, start: start, end: end)
    }

    func add(_ rule: BlockRule) {
        rules.append(rule)
        save()
    }

    /// Removes a block that hasn't started. Active blocks are kept: that is
    /// the point of blocking. Returns false if the block couldn't be removed.
    @discardableResult
    func remove(_ rule: BlockRule, now: Date = .now) -> Bool {
        guard rule.isUpcoming(at: now) else { return false }
        rules.removeAll { $0.id == rule.id }
        save()
        return true
    }

    func pruneExpired(now: Date = .now) {
        let kept = rules.filter { $0.end > now }
        if kept.count != rules.count {
            rules = kept
            save()
        }
    }

    #if DEBUG
    /// Test hook: clears every block (Debug builds only).
    func debugRemoveAll() {
        rules.removeAll()
        save()
    }
    #endif

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Formatting

extension Date {
    /// "21:30" today, "tomorrow 00:00", otherwise "Wed 18 Nov 00:00".
    func blockDescription(relativeTo now: Date = .now, calendar: Calendar = .current) -> String {
        let time = formatted(.dateTime.hour().minute())
        if calendar.isDate(self, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(self, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
