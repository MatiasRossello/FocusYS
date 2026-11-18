//
//  RootView.swift
//  FocusYS
//
//  Switches between Home and a platform screen with native SwiftUI
//  transitions: a short fade + subtle rise to open, the reverse to close.
//  With Reduce Motion it is a plain, quicker cross-fade.
//
//  Also enforces blocks: a blocked platform can't be opened, and if a block
//  starts while it is on screen FocusYS pauses it and returns Home.
//

import SwiftUI

struct RootView: View {
    @State private var store = WebSessionStore()
    @State private var blocks = BlockStore()
    /// Current time for block state; refreshed exactly when a block starts
    /// or ends, at least every minute, and when the app becomes active.
    @State private var now = Date.now
    @State private var blocksSheet: BlocksSheetRequest?
    @State private var kickedOut: (platform: Platform, until: Date)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    struct BlocksSheetRequest: Identifiable {
        let id = UUID()
        var platform: Platform?
        var preset: BlockPreset?
    }

    var body: some View {
        ZStack {
            HomeView(blocks: blocks, now: now, onSelect: open) { platform, preset in
                blocksSheet = BlocksSheetRequest(platform: platform, preset: preset)
            }
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
        .sheet(item: $blocksSheet) { request in
            BlocksView(store: blocks, now: now,
                       platform: request.platform ?? .x,
                       preset: request.preset ?? .tomorrow)
        }
        .alert(
            kickedOut.map { "\($0.platform.displayName) is now blocked" } ?? "",
            isPresented: Binding(get: { kickedOut != nil }, set: { if !$0 { kickedOut = nil } }),
            presenting: kickedOut
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text("Your block runs until \(notice.until.blockDescription(relativeTo: now)).")
        }
        // Re-arm the timer whenever the set of blocks changes.
        .task(id: blocks.rules) { await enforceBlocksLoop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { enforceBlocks() }
        }
        #if DEBUG
        .task {
            print("[FocusYS] debug: reduceMotion=\(reduceMotion)")
            seedDebugBlock()
            await runDebugLaunchArguments()
        }
        #endif
    }

    // MARK: - Blocks

    private func enforceBlocksLoop() async {
        while !Task.isCancelled {
            enforceBlocks()
            let next = blocks.nextTransition(after: .now) ?? .distantFuture
            let wait = min(max(next.timeIntervalSinceNow + 0.5, 1), 60)
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    private func enforceBlocks() {
        now = .now
        blocks.pruneExpired(now: now)
        if let platform = store.active, let until = blocks.blockedUntil(platform, at: now) {
            #if DEBUG
            print("[FocusYS] debug: block started, leaving \(platform.rawValue)")
            #endif
            goHome()
            kickedOut = (platform, until)
        }
    }

    // MARK: - Navigation

    private var platformTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 16))
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.28)
    }

    private func open(_ platform: Platform) {
        // Blocked platforms never load (Home also shows why).
        guard !blocks.isBlocked(platform) else { return }
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

    // MARK: - Debug hooks

    #if DEBUG
    /// -FocusYSResetBlocks 1 clears all blocks first, then
    /// -FocusYSDebugBlock "x:<startSeconds>:<durationSeconds>" adds a block
    /// relative to launch (Debug builds only), e.g. "x:8:60".
    private func seedDebugBlock() {
        if UserDefaults.standard.bool(forKey: "FocusYSResetBlocks") {
            blocks.debugRemoveAll()
            print("[FocusYS] debug: blocks reset")
        }
        guard let spec = UserDefaults.standard.string(forKey: "FocusYSDebugBlock") else { return }
        let parts = spec.split(separator: ":")
        guard parts.count == 3, let platform = Platform(rawValue: String(parts[0])),
              let start = Double(parts[1]), let duration = Double(parts[2]) else { return }
        let begin = Date.now.addingTimeInterval(start)
        blocks.add(BlockRule(platform: platform, start: begin, end: begin.addingTimeInterval(duration)))
        print("[FocusYS] debug: block \(platform.rawValue) from +\(start)s for \(duration)s")
    }

    /// Test hook for the simulator, Debug builds only:
    ///   -FocusYSOpen instagram|youtube|x   open a platform at launch
    ///   -FocusYSURL <url>                  then load this URL (goes through the filter)
    ///   -FocusYSURLDelay <seconds>         wait before loading it (0 = before the start page commits)
    ///   -FocusYSHomeAfter <seconds>        then return to Home
    ///   -FocusYSReopenAfter <seconds>      then open the same platform again
    ///   -FocusYSShowBlocks 1               open the Blocks sheet at launch
    private func runDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "FocusYSShowBlocks") {
            try? await Task.sleep(for: .milliseconds(600))
            blocksSheet = BlocksSheetRequest(platform: .x, preset: .tomorrow)
        }
        guard let raw = defaults.string(forKey: "FocusYSOpen"), let platform = Platform(rawValue: raw) else { return }
        try? await Task.sleep(for: .milliseconds(600))
        open(platform)
        print("[FocusYS] debug: open \(platform.rawValue) active=\(store.active?.rawValue ?? "none")")
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
}

#Preview {
    RootView()
}
