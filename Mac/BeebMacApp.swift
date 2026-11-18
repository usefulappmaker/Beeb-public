// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AVFoundation

@main struct BeebMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var delegate
    var body: some Scene {
        Window("Beeb", id: "main") {
            MacRootView().preferredColorScheme(.dark).frame(minWidth: 940, minHeight: 600)
        }
        .defaultSize(width: 1320, height: 840)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum MacSection: String, CaseIterable, Identifiable {
    case home = "Home", search = "Search", browse = "Browse", live = "Live", uhd = "4K UHD", saved = "Saved", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .browse: "square.grid.2x2"
        case .live: "dot.radiowaves.left.and.right"
        case .uhd: "4k.tv"
        case .saved: "bookmark"
        case .settings: "gearshape"
        }
    }
}

struct MacRootView: View {
    @StateObject private var catalogue = CatalogueStore()
    @StateObject private var index = CatalogueIndexStore()
    @StateObject private var library = Library()
    @StateObject private var history = WatchHistory()
    @StateObject private var player = MacPlayerController()
    @AppStorage("display4KUHDCategory") private var display4KUHDCategory = true
    @State private var section: MacSection? = .home
    @State private var path = NavigationPath()
    @Environment(\.scenePhase) private var phase
    private var sections: [MacSection] { MacSection.allCases.filter { display4KUHDCategory || $0 != .uhd } }
    var body: some View {
        ZStack {
            NavigationSplitView {
                List(selection: $section) {
                    ForEach(sections.filter { $0 != .settings }) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    Section { Label(MacSection.settings.rawValue, systemImage: MacSection.settings.icon).tag(MacSection.settings) }
                }
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
                .safeAreaInset(edge: .top) {
                    HStack(spacing: 8) {
                        Image("BeebMark").resizable().scaledToFit().frame(width: 22, height: 26)
                        Text("Beeb").font(.title2.bold())
                        Spacer()
                    }.padding(.horizontal, 16).padding(.vertical, 6)
                }
            } detail: {
                NavigationStack(path: $path) {
                    Group {
                        switch section ?? .home {
                        case .home: MacHomeView()
                        case .search: MacSearchView()
                        case .browse: MacBrowseView()
                        case .live: MacLiveView()
                        case .uhd: MacUHDView()
                        case .saved: MacSavedView()
                        case .settings: MacSettingsView()
                        }
                    }
                    .navigationTitle((section ?? .home).rawValue)
                    .navigationDestination(for: MacRoute.self) { route in
                        switch route {
                        case .show(let show, let preferUHD): MacShowView(show: show, preferUHDSeries: preferUHD)
                        case .category(let genre): MacProgrammePage(title: genre.title, category: genre.id, letter: nil)
                        case .letter(let letter): MacProgrammePage(title: letter.uppercased(), category: nil, letter: letter)
                        case .uhd: MacUHDView()
                        }
                    }
                }.background(MacTheme.background)
            }
            .toolbar(player.presented ? .hidden : .automatic, for: .windowToolbar)
            // Keep the browser's scroll position and navigation stack beneath the player.
            if player.presented {
                MacPlayerScreen(model: player.model, close: player.close).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: player.presented)
        .tint(.pink)
        .environmentObject(catalogue).environmentObject(index).environmentObject(library)
        .environmentObject(history).environmentObject(player)
        .onChange(of: section) { _, _ in path = NavigationPath() }
        .onChange(of: display4KUHDCategory) { _, visible in if !visible && section == .uhd { section = .home } }
        .task {
            catalogue.programmeOpened = { show, sourceID in Task { await index.record(show, replacingID: sourceID) } }
            await index.prepare(); await catalogue.boot()
        }
        .task(id: "\(phase)-\(index.refreshRevision)") { if phase == .active { await index.maintain() } }
        .onChange(of: phase) { _, value in
            if value == .active { Task { await catalogue.refreshHome() } } else { player.model.checkpoint() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in player.model.checkpoint() }
        #if DEBUG
        .task { await MacValidation.run(player: player, history: history, select: { section = $0 }, open: { path.append($0) }) }
        #endif
    }
}

#if DEBUG
/// Developer checks driven by environment variables, in the style of the tvOS harnesses.
///   BEEB_MAC_SECTION=<name>   open a sidebar section at launch
///   BEEB_MAC_SHOW=<pid>       open this programme's page at launch
///   BEEB_MAC_PID=<pid|url>    play this episode at launch
///   BEEB_MAC_LIVE=<channel>   play this live channel at launch, e.g. bbc_one_london
///   BEEB_MAC_VALIDATE=<file>  play muted, record what arrived as JSON, then quit
///   BEEB_MAC_SNAPSHOT=<file>  after BEEB_MAC_SNAPSHOT_DELAY seconds, save the window as PNG and quit
///   BEEB_MAC_KEYCHAIN_TEST=<p12> with _PASS and _RESULT=<file>: store, read back and remove a
///                             throwaway identity to check Keychain behaviour. Never runs over a real setup.
@MainActor enum MacValidation {
    static func run(player: MacPlayerController, history: WatchHistory, select: (MacSection) -> Void, open: (MacRoute) -> Void) async {
        let environment = ProcessInfo.processInfo.environment
        // Checks must not add to, or resume from, the real Continue Watching list.
        let history = environment["BEEB_MAC_VALIDATE"] == nil ? history : WatchHistory(defaults: UserDefaults(suiteName: "BeebMacValidation") ?? .standard)
        if let raw = environment["BEEB_MAC_SECTION"], let match = MacSection.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) { select(match) }
        if let id = environment["BEEB_MAC_SHOW"], let show = try? await DiscoveryAPI().show(id) {
            try? await Task.sleep(nanoseconds: 300_000_000) // after the section change has reset the stack
            open(.show(show, preferUHD: false))
        }
        if let path = environment["BEEB_MAC_KEYCHAIN_TEST"], let output = environment["BEEB_MAC_KEYCHAIN_RESULT"] {
            keychainRoundTrip(p12: path, password: environment["BEEB_MAC_KEYCHAIN_PASS"] ?? "", output: output)
            NSApplication.shared.terminate(nil)
        }
        var lookupError = ""
        if let pid = environment["BEEB_MAC_PID"] {
            if environment["BEEB_MAC_VALIDATE"] != nil { player.model.player.isMuted = true }
            do { player.play(try await BBCService().programme(pid), show: nil, history: history) }
            catch { lookupError = error.localizedDescription }
        }
        if let id = environment["BEEB_MAC_LIVE"] {
            if environment["BEEB_MAC_VALIDATE"] != nil { player.model.player.isMuted = true }
            player.playLive(LiveChannel(id: id, title: id))
        }
        if let path = environment["BEEB_MAC_VALIDATE"] {
            let model = player.model
            for tick in 1...60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let size = model.player.currentItem?.presentationSize ?? .zero
                let time = model.player.currentTime().seconds
                let failure = lookupError.isEmpty ? model.error ?? "" : lookupError
                let range = await MacVideoRange.received(model.player.currentItem) ?? ""
                let values: [String: Any] = ["tick": tick, "status": model.status, "error": failure, "quality": model.qualityBadge ?? "",
                                             "title": model.displayTitle, "width": Int(size.width), "height": Int(size.height), "time": time.isFinite ? time : 0,
                                             "host": (model.player.currentItem?.asset as? AVURLAsset)?.url.host ?? "", "range": range]
                if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
                if (size.height > 0 && time > 5) || !failure.isEmpty { break }
            }
            if environment["BEEB_MAC_SNAPSHOT"] == nil { NSApplication.shared.terminate(nil) }
        }
        if let path = environment["BEEB_MAC_SNAPSHOT"] {
            let delay = Double(environment["BEEB_MAC_SNAPSHOT_DELAY"] ?? "") ?? 6
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if let view = NSApp.windows.first(where: { $0.isVisible })?.contentView?.superview ?? NSApp.windows.first?.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                // Scroll offsets beside the picture: a cached drawing does not prove where a scroll view sits.
                var scrolls = [[String: Any]]()
                func visit(_ node: NSView) {
                    if let scroll = node as? NSScrollView, let document = scroll.documentView {
                        scrolls.append(["x": Int(scroll.documentVisibleRect.minX), "y": Int(scroll.documentVisibleRect.minY),
                                        "visibleWidth": Int(scroll.documentVisibleRect.width), "contentWidth": Int(document.frame.width), "contentHeight": Int(document.frame.height)])
                    }
                    node.subviews.forEach(visit)
                }
                visit(view)
                if let data = try? JSONSerialization.data(withJSONObject: scrolls, options: [.sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path + ".scroll.json"), options: .atomic) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            NSApplication.shared.terminate(nil)
        }
    }
    private static func keychainRoundTrip(p12: String, password: String, output: String) {
        var values = [String: Any]()
        defer { if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) { try? data.write(to: URL(fileURLWithPath: output), options: .atomic) } }
        guard !UHDIdentityVault.isConfigured, UHDIdentityVault.userAgent.isEmpty else { values["skipped"] = "A UHD setup already exists; not touching it."; return }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: p12)) else { values["error"] = "Could not read the test package."; return }
        do {
            try UHDIdentityVault.install(UHDBootstrap(p12: data.base64EncodedString(), password: password, userAgent: "BeebMacKeychainTest/1"))
            values["installed"] = true
            values["configured"] = UHDIdentityVault.isConfigured
            values["agent"] = UHDIdentityVault.userAgent
            values["sessionReady"] = (try? BBCSecureSession.configured()) != nil
        } catch { values["error"] = error.localizedDescription }
        UHDIdentityVault.remove()
        values["configuredAfterRemove"] = UHDIdentityVault.isConfigured
    }
}
#endif
