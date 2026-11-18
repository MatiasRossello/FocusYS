//
//  RootView.swift
//  FocusYS
//
//  Switches between Home and a platform screen with native SwiftUI
//  transitions: a short fade + subtle rise to open, the reverse to close.
//  With Reduce Motion it is a plain, quicker cross-fade.
//

import SwiftUI

struct RootView: View {
    @State private var store = WebSessionStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HomeView(onSelect: open)
                .opacity(store.active == nil ? 1 : 0)
                .offset(y: store.active == nil || reduceMotion ? 0 : -8)
                .accessibilityHidden(store.active != nil)
                .allowsHitTesting(store.active == nil)

            if let platform = store.active, let session = store.sessions[platform] {
                PlatformScreen(session: session, onHome: goHome)
                    .id(platform)
                    .transition(platformTransition)
                    .zIndex(1)
            }
        }
        #if DEBUG
        .task {
            print("[FocusYS] debug: reduceMotion=\(reduceMotion)")
            await runDebugLaunchArguments()
        }
        #endif
    }

    #if DEBUG
    /// Test hook for the simulator, Debug builds only:
    ///   -FocusYSOpen instagram|youtube|x   open a platform at launch
    ///   -FocusYSURL <url>                  then load this URL (goes through the filter)
    ///   -FocusYSURLDelay <seconds>         wait before loading it (0 = before the start page commits)
    ///   -FocusYSHomeAfter <seconds>        then return to Home
    ///   -FocusYSReopenAfter <seconds>      then open the same platform again
    private func runDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "FocusYSOpen"), let platform = Platform(rawValue: raw) else { return }
        try? await Task.sleep(for: .milliseconds(600))
        open(platform)
        if let urlString = defaults.string(forKey: "FocusYSURL"), let url = URL(string: urlString) {
            let delay = defaults.object(forKey: "FocusYSURLDelay") == nil ? 4 : defaults.double(forKey: "FocusYSURLDelay")
            try? await Task.sleep(for: .seconds(delay))
            store.sessions[platform]?.debugLoad(url)
        }
        let homeAfter = defaults.double(forKey: "FocusYSHomeAfter")
        if homeAfter > 0 {
            try? await Task.sleep(for: .seconds(homeAfter))
            print("[FocusYS] debug: Home")
            goHome()
            let reopenAfter = defaults.double(forKey: "FocusYSReopenAfter")
            if reopenAfter > 0 {
                try? await Task.sleep(for: .seconds(reopenAfter))
                print("[FocusYS] debug: reopen \(platform.rawValue)")
                open(platform)
            }
        }
    }
    #endif

    private var platformTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 16))
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.28)
    }

    private func open(_ platform: Platform) {
        // Create (or reuse) the session first so the web view starts loading
        // while the screen is already animating in.
        let session = store.session(for: platform)
        session.setMediaSuspended(false)
        withAnimation(animation) { store.active = platform }
    }

    private func goHome() {
        if let platform = store.active {
            store.sessions[platform]?.setMediaSuspended(true)
        }
        withAnimation(animation) { store.active = nil }
    }
}

#Preview {
    RootView()
}
