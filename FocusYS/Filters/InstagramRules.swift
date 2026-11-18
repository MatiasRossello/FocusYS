//
//  InstagramRules.swift
//  FocusYS
//
//  Blocks:  /reels/…              (Reels tab / feed)
//           /reel/<code>/         (Reel player, direct links)
//           /<user>/reels/        (profile Reels tab)
//           /<user>/reel/<code>/  (profile-scoped Reel link)
//  Keeps:   /, /direct/…, /<user>/, /p/<code>/, /explore/, /stories/…
//

import Foundation

struct InstagramRules: PlatformRules {
    let siteDomains = Platform.instagram.siteDomains

    private static let reelSegments: Set<String> = ["reel", "reels"]
    /// First segments that are app sections, never usernames.
    private static let reservedFirstSegments: Set<String> = [
        "accounts", "challenge", "direct", "explore", "p", "stories",
        "about", "legal", "privacy", "help", "web", "api", "graphql", "oauth", "two_factor",
    ]

    func blockReason(for url: URL) -> BlockReason? {
        guard url.hostMatchesAny(siteDomains) else { return nil }
        let segments = url.pathSegments
        guard let first = segments.first else { return nil }

        if Self.reelSegments.contains(first) {
            return BlockReason(message: "Reel blocked")
        }
        if segments.count >= 2,
           !Self.reservedFirstSegments.contains(first),
           Self.reelSegments.contains(segments[1]) {
            return BlockReason(message: "Reel blocked")
        }
        return nil
    }
}
