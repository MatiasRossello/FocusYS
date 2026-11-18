//
//  WebSessionStore.swift
//  FocusYS
//
//  Creates a platform's web session only when it is chosen, and keeps it in
//  memory so its last page survives going back to Home. Under memory
//  pressure, sessions that are not on screen are released (their login is
//  kept by the persistent data store).
//

import Observation
import UIKit

@Observable
final class WebSessionStore {
    private(set) var sessions: [Platform: WebSession] = [:]
    @ObservationIgnored private var memoryObserver: NSObjectProtocol?

    /// The platform currently on screen, if any.
    var active: Platform?

    init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseInactiveSessions() }
        }
    }

    func session(for platform: Platform) -> WebSession {
        if let existing = sessions[platform] { return existing }
        let session = WebSession(platform: platform)
        sessions[platform] = session
        return session
    }

    private func releaseInactiveSessions() {
        sessions = sessions.filter { $0.key == active }
    }
}
