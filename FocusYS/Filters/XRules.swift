//
//  XRules.swift
//  FocusYS
//
//  Blocks:  /<user>/status/<id>/video/<n>   (full-screen media viewer for a
//                                            video, which on the mobile web
//                                            is the swipe-to-next immersive
//                                            player)
//  Keeps:   /home, /search, /<user>, /messages, /<user>/status/<id>
//           (videos keep playing inline inside posts), /…/photo/<n>
//

import Foundation

struct XRules: PlatformRules {
    let siteDomains = Platform.x.siteDomains

    func blockReason(for url: URL) -> BlockReason? {
        guard url.hostMatchesAny(siteDomains) else { return nil }
        let s = url.pathSegments
        // <user>/status/<id>/video/<n>
        if s.count >= 4, s[1] == "status", s[3] == "video" {
            return BlockReason(message: "Immersive video blocked")
        }
        // i/web/status/<id>/video/<n>
        if s.count >= 5, s[0] == "i", s[2] == "status", s[4] == "video" {
            return BlockReason(message: "Immersive video blocked")
        }
        return nil
    }
}
