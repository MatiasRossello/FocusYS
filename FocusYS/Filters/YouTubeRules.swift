//
//  YouTubeRules.swift
//  FocusYS
//
//  Blocks:  /shorts, /shorts/<id>                  (Shorts tab and player)
//           /@handle/shorts, /channel/<id>/shorts,
//           /c/<name>/shorts, /user/<name>/shorts  (channel Shorts tab)
//           /hashtag/<tag>/shorts
//  Keeps:   /watch, /results, /@handle, /playlist, /feed/subscriptions, …
//

import Foundation

struct YouTubeRules: PlatformRules {
    let siteDomains = Platform.youtube.siteDomains

    private static let channelPrefixes: Set<String> = ["channel", "c", "user", "hashtag"]

    func blockReason(for url: URL) -> BlockReason? {
        guard url.hostMatchesAny(siteDomains) else { return nil }
        let segments = url.pathSegments
        guard let first = segments.first else { return nil }

        if first == "shorts" {
            return BlockReason(message: "Short blocked")
        }
        if first.hasPrefix("@"), segments.count >= 2, segments[1] == "shorts" {
            return BlockReason(message: "Short blocked")
        }
        if Self.channelPrefixes.contains(first), segments.count >= 3, segments[2] == "shorts" {
            return BlockReason(message: "Short blocked")
        }
        return nil
    }
}
