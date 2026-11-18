//
//  Platform.swift
//  FocusYS
//
//  Static description of each supported platform: names, symbols,
//  start page, which hosts belong to it and which filter rules apply.
//

import Foundation

enum Platform: String, CaseIterable, Identifiable, Codable {
    case instagram
    case youtube
    case x

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .x: "X"
        }
    }

    /// Short line under the name on the home screen.
    var filterSummary: String {
        switch self {
        case .instagram: "Reels blocked"
        case .youtube: "Shorts blocked"
        case .x: "Immersive video blocked"
        }
    }

    var homeURL: URL {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com/")!
        case .youtube: URL(string: "https://m.youtube.com/")!
        case .x: URL(string: "https://x.com/home")!
        }
    }

    /// Hosts that are the platform itself. Filtering applies here and the
    /// JavaScript filter only acts on these hosts.
    var siteDomains: [String] {
        switch self {
        case .instagram: ["instagram.com"]
        case .youtube: ["youtube.com", "youtu.be"]
        case .x: ["x.com", "twitter.com"]
        }
    }

    /// Official hosts that the sign-in / verification flow may need to show
    /// in the main frame. They are never filtered.
    var authDomains: [String] {
        switch self {
        case .instagram: ["facebook.com", "fb.com", "meta.com", "accountscenter.meta.com"]
        case .youtube: ["google.com", "accounts.google.com", "gstatic.com", "googleusercontent.com", "youtube-nocookie.com"]
        case .x: ["api.x.com", "api.twitter.com", "appleid.apple.com", "accounts.google.com", "google.com"]
        }
    }

    var rules: PlatformRules {
        switch self {
        case .instagram: InstagramRules()
        case .youtube: YouTubeRules()
        case .x: XRules()
        }
    }

    /// Name (without extension) of the bundled JavaScript filter.
    var scriptName: String {
        switch self {
        case .instagram: "instagram-filter"
        case .youtube: "youtube-filter"
        case .x: "x-filter"
        }
    }

    /// Stable identifier for this platform's persistent WebKit data store,
    /// so each platform keeps its own cookies / session between launches.
    var dataStoreID: UUID {
        switch self {
        case .instagram: UUID(uuidString: "6A3F1C2E-1B7A-4C1E-9D40-0F1A11A00001")!
        case .youtube: UUID(uuidString: "6A3F1C2E-1B7A-4C1E-9D40-0F1A11A00002")!
        case .x: UUID(uuidString: "6A3F1C2E-1B7A-4C1E-9D40-0F1A11A00003")!
        }
    }
}

extension URL {
    /// True if `host` equals `domain` or is a subdomain of it.
    /// Compares whole labels so `notinstagram.com` never matches `instagram.com`.
    func hostMatches(_ domain: String) -> Bool {
        guard let host = host()?.lowercased() else { return false }
        let domain = domain.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }

    func hostMatchesAny(_ domains: [String]) -> Bool {
        domains.contains(where: hostMatches)
    }

    /// Non-empty path segments, lowercased.
    var pathSegments: [String] {
        path(percentEncoded: false)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.lowercased() }
    }
}
