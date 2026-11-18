//
//  PlatformRules.swift
//  FocusYS
//
//  Native (URL-level) filter layer. Each platform decides whether a
//  main-frame URL is a blocked experience by comparing hosts and whole
//  path segments, never substrings.
//

import Foundation

struct BlockReason: Equatable {
    /// Short message shown in the toast, e.g. "Reel blocked".
    let message: String
}

protocol PlatformRules {
    /// Hosts on which the rules (and the JS filter) apply.
    var siteDomains: [String] { get }
    /// Returns a reason if the URL leads to a blocked experience.
    func blockReason(for url: URL) -> BlockReason?
}

extension PlatformRules {
    func isBlocked(_ url: URL) -> Bool { blockReason(for: url) != nil }
}
