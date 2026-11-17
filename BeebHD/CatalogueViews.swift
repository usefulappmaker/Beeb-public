// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import TVServices

private enum BeebTab: String, CaseIterable { case home = "Home", search = "Search", browse = "Browse", live = "Live", uhd = "4K UHD", saved = "Saved", settings = "Settings"
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
    } }
struct HomeView: View {
    @StateObject private var catalogue = CatalogueStore()
    @StateObject private var index = CatalogueIndexStore()
    @StateObject private var library = Library()
    @StateObject private var history = WatchHistory()
    @AppStorage("homescreenLayout") private var homescreenLayout = "Modern"
    @AppStorage("modernNavigation") private var modernNavigation = "Sidebar"
    @AppStorage("display4KUHDCategory") private var display4KUHDCategory = true
    private var visibleTabs: [BeebTab] {
        BeebTab.allCases.filter { (display4KUHDCategory || $0 != .uhd) && (!ProfileStore.shared.kidsMode || [.home, .live, .saved].contains($0)) }
    }
    private var modern: Bool { homescreenLayout == "Modern" }
    private var usesSidebar: Bool { modern && modernNavigation == "Sidebar" }
    @State private var tab = BeebTab.home
    @StateObject private var homeState = HomeState()
    @StateObject private var navigationMemory = NavigationFocusMemory()
    @State private var liveLaunch: LiveLaunch?
    @FocusState private var focusedTab: BeebTab?
    @FocusState private var menuIconFocused: Bool
    @State private var sidebarOpen = false
    @State private var iconFocusRequest = 0
    @ObservedObject private var profiles = ProfileStore.shared
    @State private var showProfilePicker = ProfileStore.shared.pickerRequired
    /// Last item in the top menu bar: the current person; opens the Who's watching picker.
    @ViewBuilder private var profileTab: some View {
        if profiles.profiles.count > 1 {
            Button { profiles.pickerRequired = false; showProfilePicker = true } label: {
                HStack(spacing: 8) { Image(systemName: "person.crop.circle.fill"); Text(profiles.currentProfile.name) }
            }.buttonStyle(ProfilePillStyle()).accessibilityLabel("Profile \(profiles.currentProfile.name). Select to switch profile.")
        }
    }
    @Environment(\.scenePhase) private var phase
    private var navigationButton: some View {
        Button {
            if sidebarOpen { closeSidebar() } else { openSidebar() }
        } label: {
            HStack(spacing: 14) {
                Image("BeebMark").resizable().scaledToFit().frame(width: 48, height: 48)
                    .shadow(color: .pink.opacity(menuIconFocused ? 0.85 : 0), radius: 20)
                    .shadow(color: .pink.opacity(menuIconFocused ? 0.45 : 0), radius: 8)
                Text("Beeb").font(.system(size: 36, weight: .bold)).foregroundStyle(.white)
            }.padding(.vertical, 16)
                .scaleEffect(menuIconFocused ? 1.035 : 1)

        }.buttonStyle(BeebTabStyle()).focused($menuIconFocused).focusEffectDisabled()
            .accessibilityLabel("Navigation").accessibilityValue(sidebarOpen ? "Expanded" : "Collapsed")
    }
    private var sidebarHeader: some View {
        HStack {
            if sidebarOpen || tab == .home {
                navigationButton.onMoveCommand { direction in
                    if sidebarOpen {
                        if direction == .down { focusedTab = tab }
                        if direction == .right { closeSidebar() }
                    } else if direction == .down || direction == .right {
                        homeState.heroFocusRequest += 1
                    }
                }
            } else { navigationButton }
            Spacer(minLength: 0)
        }.padding(.horizontal, 64).padding(.top, 48).padding(.bottom, 16)
    }
    private var navigationIcon: some View {
        Group {
            if usesSidebar { sidebarHeader }
            else { horizontalHeader.focusSection().defaultFocus($focusedTab, tab) }
        }.onChange(of: profiles.current) { _, _ in if !visibleTabs.contains(tab) { tab = .home } }
        .onChange(of: profiles.kidsMode) { _, _ in if !visibleTabs.contains(tab) { tab = .home } }
        .fullScreenCover(isPresented: $showProfilePicker) {
            WhoIsWatchingView(required: profiles.pickerRequired, dismiss: { showProfilePicker = false }) { id in
                profiles.select(id)
                profiles.pickerRequired = false
                showProfilePicker = false
            }
        }
    }
    private var horizontalHeader: some View {
        HStack(spacing: modern ? 32 : 30) {
            HStack(spacing: 12) {
                Image("BeebMark").resizable().scaledToFit().frame(width: modern ? 48 : 64, height: modern ? 48 : 64)
                if modern { Text("Beeb").font(.system(size: 34, weight: .bold)) }
            }.accessibilityElement(children: .combine).accessibilityLabel("Beeb")
            if modern { Spacer(minLength: 12) }
            HStack(spacing: modern ? 4 : 14) {
                ForEach(visibleTabs, id: \.self) { value in
                    Button { tab = value } label: {
                        HStack(spacing: 8) {
                            if modern { Image(systemName: value.icon) }
                            Text(value.rawValue)
                        }.font(modern ? .system(size: 22, weight: .semibold) : .headline)
                            .padding(.horizontal, modern ? 20 : 24).padding(.vertical, 16)
                            .foregroundStyle(modern && focusedTab == value ? Color.black : .white.opacity(focusedTab == value || tab == value ? 1 : 0.7))
                            .background {
                                if modern {
                                    Capsule().fill(focusedTab == value ? Color.white : tab == value ? .white.opacity(0.13) : .clear)
                                        .shadow(color: .pink.opacity(focusedTab == value ? 0.55 : 0), radius: 20)
                                } else {
                                    RoundedRectangle(cornerRadius: 12).fill(.white.opacity(focusedTab == value ? 0.2 : tab == value ? 0.12 : 0))
                                }
                            }
                    }.buttonStyle(BeebTabStyle()).focused($focusedTab, equals: value).focusEffectDisabled()
                        .accessibilityAddTraits(tab == value ? .isSelected : [])
                        .accessibilityIdentifier("BeebTopbar" + value.rawValue)
                }
                profileTab
            }.padding(modern ? 8 : 0)
                .background {
                    if modern { Capsule().fill(.ultraThinMaterial).overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }.shadow(color: .black.opacity(0.3), radius: 20, y: 8) }
                }
            Spacer(minLength: 0)
        }.padding(.horizontal, 64).padding(.top, modern ? (tab == .home ? 64 : 24) : 18).padding(.bottom, 18)
    }
    private func menuItem(_ value: BeebTab) -> some View {
        BeebTabButton(tab: value, selected: tab, focus: $focusedTab) {
            let changed = tab != value
            tab = value
            closeSidebar(restore: !changed)
        }.onMoveCommand { direction in
            let values = visibleTabs
            let position = values.firstIndex(of: value) ?? 0
            switch direction {
            case .up:
                if position == 0 { focusedTab = nil; menuIconFocused = true }
                else { focusedTab = values[position - 1] }
            case .down: focusedTab = values[min(values.count - 1, position + 1)]
            case .right: closeSidebar()
            default: break
            }
        }
    }
    private var sidebar: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                ForEach(visibleTabs.filter { $0 != .settings }, id: \.self) { menuItem($0) }
                Spacer(minLength: 24)
                Divider().overlay(.white.opacity(0.12))
                menuItem(.settings)
            }.padding(18).frame(width: 296, height: max(600, geometry.size.height - 196))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
                .padding(.leading, 48).padding(.top, 148)
                .onAppear { focusedTab = tab }
                .onExitCommand { closeSidebar() }
        }.ignoresSafeArea()
    }
    private func focusNavigation() {
        // Cancel a pending Down-to-hero request before moving focus back to the menu.
        homeState.heroFocusRequest = 0
        homeState.scrollTopRequest += 1
        if usesSidebar { menuIconFocused = true } else { focusedTab = tab }
    }
    private func openSidebar() {
        guard usesSidebar, !sidebarOpen else { return }
        homeState.heroFocusRequest = 0
        iconFocusRequest = 0
        navigationMemory.capture()
        withAnimation(.easeOut(duration: 0.2)) { sidebarOpen = true }
    }
    private func closeSidebar(restore: Bool = true) {
        guard sidebarOpen else { return }
        focusedTab = nil
        menuIconFocused = false
        withAnimation(.easeOut(duration: 0.2), completionCriteria: .removed) {
            sidebarOpen = false
        } completion: {
            guard !sidebarOpen else { return }
            if restore, navigationMemory.restore() { return }
            navigationMemory.discard()
            if tab == .home { homeState.heroFocusRequest += 1 }
            else { iconFocusRequest += 1 }
        }
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.015, blue: 0.055).ignoresSafeArea()
                if tab == .home && modern && !profiles.kidsMode {
                    DiscoveryHome(catalogue: catalogue, library: library, state: homeState,
                                  header: navigationIcon, menuOpen: sidebarOpen,
                                  focusHeader: focusNavigation)
                } else {
                    VStack(spacing: 0) {
                        navigationIcon
                        Group {
                            switch tab {
                            case .home:
                                if profiles.kidsMode { KidsHomeView(catalogue: catalogue, library: library) }
                                else { ClassicDiscoveryHome(catalogue: catalogue, library: library, state: homeState) }
                            case .uhd: UHDCategoryView(index: index, catalogue: catalogue, library: library)
                            case .browse: BrowseView(catalogue: catalogue, library: library, index: index)
                            case .search: CatalogueSearchView(index: index, catalogue: catalogue, library: library)
                            case .live: LiveView(launch: liveLaunch, library: library)
                            case .saved: SavedProgrammes(catalogue: catalogue, library: library)
                            case .settings: SettingsView(catalogue: catalogue)
                            }
                        }.id(tab).disabled(sidebarOpen)
                    }
                }
            }.background {
                NavigationEdgeObserver(enabled: !sidebarOpen && focusedTab == nil && !menuIconFocused,
                                       onLeft: usesSidebar ? openSidebar : nil,
                                       onUp: modern && !usesSidebar ? focusNavigation : nil)
            }.environment(\.beebFocusMemory, navigationMemory)
            .environment(\.beebOpenSidebar, usesSidebar ? openSidebar : nil)
            .environment(\.beebFocusNavigation, modern && !usesSidebar ? focusNavigation : nil)
            .modifier(RootBackAction(active: tab != .home) {
                sidebarOpen = false; tab = .home; homeState.heroFocusRequest += 1
            }).overlay(alignment: .topLeading) {
                if usesSidebar && sidebarOpen { sidebar.transition(.move(edge: .leading).combined(with: .opacity)) }
            }
        }.id(liveLaunch?.id).environmentObject(history).tint(.pink)
        .task(id: iconFocusRequest) {
            guard iconFocusRequest > 0 else { return }
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            if !sidebarOpen && tab != .home { menuIconFocused = true }
        }
        .onChange(of: menuIconFocused) { _, focused in
            if focused && !sidebarOpen {
                let target = $menuIconFocused
                navigationMemory.remember { target.wrappedValue = true }
            }
        }
        .onChange(of: focusedTab) { _, focused in
            if focused != nil { homeState.heroFocusRequest = 0 }
        }
        .onChange(of: homescreenLayout) { _, _ in sidebarOpen = false; focusedTab = nil; menuIconFocused = false }
        .onChange(of: display4KUHDCategory) { _, visible in
            guard !visible else { return }
            if tab == .uhd { tab = .home; homeState.heroFocusRequest += 1 }
            if focusedTab == .uhd { focusedTab = .home }
        }
        .onChange(of: modernNavigation) { _, _ in sidebarOpen = false; focusedTab = nil; menuIconFocused = false }
        .onOpenURL { url in
            sidebarOpen = false
            guard let id = LiveChannelLink.channelID(from: url) else { return }
            if tab != .live { NotificationCenter.default.post(name: .beebLaunchLive, object: nil) }
            liveLaunch = LiveLaunch(channelID: id)
            tab = .live
        }
        .task {
            TVTopShelfContentProvider.topShelfContentDidChange()
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEEB_LIVE_ROUTE_VALIDATE"] == "1" { return }
            #endif
            catalogue.programmeOpened = { show, sourceID in Task { await index.record(show, replacingID: sourceID) } }
            await index.prepare(); await catalogue.boot()
        }
        .task(id: "\(phase)-\(index.refreshRevision)") {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEEB_LIVE_ROUTE_VALIDATE"] == "1" || ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "review" { return }
            #endif
            if phase == .active { await index.maintain() }
        }
        #if DEBUG
        .onAppear { if let value = ProcessInfo.processInfo.environment["BEEB_UI_TAB"], let selected = visibleTabs.first(where: { $0.rawValue.lowercased() == value }) { tab = selected } }
        #endif
        .onChange(of: phase) { _, value in if value == .active { Task { await catalogue.refreshHome() } } }
    }
}
private struct BeebTabButton: View {
    let tab: BeebTab
    let selected: BeebTab
    let focus: FocusState<BeebTab?>.Binding
    let action: () -> Void
    private var focused: Bool { focus.wrappedValue == tab }
    var body: some View {
        Button(action: action) {
            Label(tab.rawValue, systemImage: tab.icon).font(.system(size: 25, weight: .semibold))
                .labelStyle(.titleAndIcon).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).frame(height: 68)
                .foregroundStyle(focused ? Color.black : .white.opacity(selected == tab ? 1 : 0.75))
                .background(focused ? Color.white : selected == tab ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .pink.opacity(focused ? 0.55 : 0), radius: 16)
        }.buttonStyle(BeebTabStyle()).focused(focus, equals: tab).focusEffectDisabled()
            .accessibilityAddTraits(selected == tab ? .isSelected : [])
    }
}
private struct BeebTabStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.opacity(configuration.isPressed ? 0.7 : 1) }
}
private struct CinematicBackdrop: View {
    let url: URL?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.035, green: 0.015, blue: 0.055)
                if let url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22), .init(color: .black, location: 1)], startPoint: .leading, endPoint: .trailing))
                    } placeholder: { Color.clear }
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                    LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0), .init(color: .black.opacity(0.5), location: 0.38), .init(color: .clear, location: 0.78)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(stops: [.init(color: .black.opacity(0.18), location: 0), .init(color: .clear, location: 0.3), .init(color: Color(red: 0.035, green: 0.015, blue: 0.055).opacity(0.9), location: 0.72), .init(color: Color(red: 0.035, green: 0.015, blue: 0.055), location: 1)], startPoint: .top, endPoint: .bottom)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct CinematicActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CinematicActionSurface(content: configuration.label, pressed: configuration.isPressed)
    }
}
private struct CinematicActionSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content.font(.system(size: 26, weight: .semibold)).padding(.horizontal, 34).padding(.vertical, 22)
            .foregroundStyle(focused ? Color.black : Color.white)
            .background(focused ? Color.white : Color.white.opacity(0.12), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(focused ? 0.9 : 0.22), lineWidth: 1) }
            .shadow(color: Color(red: 1, green: 0.04, blue: 0.43).opacity(focused ? 0.65 : 0), radius: 26, y: 4)
            .scaleEffect(pressed ? 0.98 : focused ? 1.035 : 1)
            .animation(.easeOut(duration: 0.18), value: focused).focusEffectDisabled()
    }
}
private struct BannerRotationKey: Hashable { let index: Int; let count: Int; let paused: Bool }
@MainActor final class HomeState: ObservableObject { @Published var banner = 0; @Published var heroFocusRequest = 0; @Published var scrollTopRequest = 0 }
struct DiscoveryHome<Header: View>: View {
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @ObservedObject var state: HomeState
    let header: Header
    let menuOpen: Bool
    let focusHeader: () -> Void
    @Environment(\.beebFocusMemory) private var focusMemory
    @Environment(\.scenePhase) private var phase
    @Environment(\.beebOpenSidebar) private var openSidebar
    @FocusState private var bannerFocused: Bool
    @FocusState private var focusedCard: String?
    @State private var visible = false
    private var rotationKey: BannerRotationKey {
        BannerRotationKey(index: state.banner, count: catalogue.home?.features.count ?? 0, paused: !visible || bannerFocused || menuOpen || phase != .active)
    }
    private var feature: HomeFeature? {
        guard let features = catalogue.home?.features, !features.isEmpty else { return nil }
        return features[min(state.banner, features.count - 1)]
    }
    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    header
                    if let feature {
                        VStack(alignment: .leading, spacing: 22) {
                            Spacer(minLength: 0)
                            Text("FEATURED").font(.system(size: 22, weight: .semibold)).tracking(5).foregroundStyle(.pink)
                            Text(feature.headline).font(.system(size: 64, weight: .bold)).lineLimit(2)
                                .frame(maxWidth: 1000, alignment: .leading)
                            Text(feature.synopsis).font(.system(size: 27)).lineLimit(2)
                                .foregroundStyle(.white.opacity(0.85)).frame(maxWidth: 950, alignment: .leading)
                            if feature.show.uhdListed == true { UHDListedBadge(hdr: false) }
                            HStack {
                                NavigationLink {
                                    CatalogueShowView(show: feature.show, catalogue: catalogue, library: library)
                                } label: {
                                    Label("Watch now", systemImage: "play.fill")
                                }.buttonStyle(CinematicActionStyle()).focused($bannerFocused).disabled(menuOpen).padding(.top, 8)
                                    .onMoveCommand { direction in
                                        guard bannerFocused else { return }
                                        if direction == .left {
                                            if let openSidebar { openSidebar() } else { advanceBanner(by: -1) }
                                        }
                                        if direction == .right { advanceBanner(by: 1) }
                                        if direction == .up { bannerFocused = false; focusHeader() }
                                    }
                                    .accessibilityAdjustableAction { direction in
                                        switch direction {
                                        case .increment: advanceBanner(by: 1)
                                        case .decrement: advanceBanner(by: -1)
                                        @unknown default: break
                                        }
                                    }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, alignment: .leading).focusSection()
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, minHeight: 440, maxHeight: 440, alignment: .leading)
                             .padding(.leading, menuOpen ? 368 : 64).padding(.trailing, 64).padding(.top, 26).padding(.bottom, 50)
                            .animation(.easeOut(duration: 0.2), value: menuOpen)
                    }
                }.background { CinematicBackdrop(url: feature?.image) }.clipped().id("home-header")
                VStack(alignment: .leading, spacing: 34) {
                    if let error = catalogue.error { Text(error).foregroundStyle(.orange).font(.callout) }
                    if let feed = catalogue.home {
                    ContinueWatchingRow(catalogue: catalogue, library: library)
                    ForEach(feed.rows) { row in
                        VStack(alignment: .leading, spacing: 18) {
                            Text(row.title).font(.title2).bold()
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 28) {
                                    ForEach(row.shows) { show in
                                        NavigationLink { CatalogueShowView(show: show, catalogue: catalogue, library: library) } label: { HomeProgrammeCard(show: show, poster: row.usesPosters).frame(width: row.usesPosters ? 260 : 360) }.buttonStyle(ProgrammeCardStyle()).accessibilityLabel(show.title).focused($focusedCard, equals: "\(row.id):\(show.id)")
                                    }
                                }.padding(.vertical, 30).padding(.horizontal, 24)
                            }.scrollClipDisabled().padding(.horizontal, -24)
                        }
                    }
                } else if catalogue.loading { ProgressView("Getting the latest programmes…") }
                else { Button("Retry homepage") { Task { await catalogue.refreshHome() } } }
                }.disabled(menuOpen).padding(.leading, menuOpen ? 368 : 64).padding(.trailing, 64)
                    .padding(.top, 34).padding(.bottom, 60)
                    .animation(.easeOut(duration: 0.2), value: menuOpen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.035, green: 0.015, blue: 0.055))
            }
        }.ignoresSafeArea().scrollClipDisabled()
        .task(id: state.scrollTopRequest) {
            guard state.scrollTopRequest > 0 else { return }
            scroll.scrollTo("home-header", anchor: .top)
        }
        .onChange(of: bannerFocused) { _, focused in
            if focused {
                let target = $bannerFocused
                focusMemory?.remember { target.wrappedValue = true }
                scroll.scrollTo("home-header", anchor: .top)
            }
        }
        .onChange(of: focusedCard) { _, card in
            if let card {
                let target = $focusedCard
                focusMemory?.remember { target.wrappedValue = card }
            }
        }
        .task(id: state.heroFocusRequest) {
            guard state.heroFocusRequest > 0, feature != nil, !menuOpen else { return }
            scroll.scrollTo("home-header", anchor: .top)
            let request = state.heroFocusRequest
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard state.heroFocusRequest == request, !menuOpen else { return }
            bannerFocused = true
            scroll.scrollTo("home-header", anchor: .top)
        }
        .onAppear { visible = true }
        .task(id: phase) {
            #if DEBUG
            guard phase == .active else { return }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "cards" { focusedCard = "preview:preview-0" }
            if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "banner-focused" || ProcessInfo.processInfo.environment["BEEB_HOME_HERO_FOCUS"] == "1" { bannerFocused = true }
            #endif
        }
        .onDisappear { visible = false }
        .onChange(of: rotationKey) { _, _ in recordBannerValidation() }
        .task(id: rotationKey) {
            guard !rotationKey.paused, rotationKey.count > 1 else { return }
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard !Task.isCancelled, visible, !bannerFocused, !menuOpen, phase == .active else { return }
            withAnimation(.easeInOut(duration: 0.4)) { state.banner = (state.banner + 1) % rotationKey.count }
        }
    }
    }
    private func advanceBanner(by offset: Int) {
        let count = catalogue.home?.features.count ?? 0
        guard count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            state.banner = (min(state.banner, count - 1) + offset + count) % count
        }
    }
    private func recordBannerValidation() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] != nil else { return }
        let values: [String: Any] = ["index": state.banner, "count": rotationKey.count, "focused": bannerFocused, "visible": visible, "active": phase == .active, "timestamp": Date().timeIntervalSince1970]
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("UI-validation.json")
        if let data = try? JSONSerialization.data(withJSONObject: values) { try? data.write(to: output, options: .atomic) }
        #endif
    }

}
private struct ClassicDiscoveryHome: View {
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @ObservedObject var state: HomeState
    @Environment(\.scenePhase) private var phase
    @FocusState private var bannerFocused: Bool
    @FocusState private var focusedCard: String?
    @State private var visible = false
    private var rotationKey: BannerRotationKey {
        BannerRotationKey(index: state.banner, count: catalogue.home?.features.count ?? 0, paused: !visible || bannerFocused || phase != .active)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                if let error = catalogue.error { Text(error).foregroundStyle(.orange).font(.callout) }
                if catalogue.home == nil { ContinueWatchingRow(catalogue: catalogue, library: library) }
                if let feed = catalogue.home {
                    if !feed.features.isEmpty {
                        let index = min(state.banner, feed.features.count - 1)
                        let feature = feed.features[index]
                        NavigationLink { CatalogueShowView(show: feature.show, catalogue: catalogue, library: library) } label: {
                            ZStack(alignment: .bottomLeading) {
                                Color.clear.overlay {
                                    GeometryReader { geometry in
                                        AsyncImage(url: feature.image) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.gray.opacity(0.15)) }
                                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                    }
                                }
                                LinearGradient(colors: [.clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("NEW & TRENDING").font(.caption).tracking(4).foregroundStyle(.pink)
                                    Text(feature.headline).font(.system(size: 48, weight: .bold)).lineLimit(2)
                                    Text(feature.synopsis).font(.title3).lineLimit(2).frame(maxWidth: 1000, alignment: .leading)
                                }.padding(38)
                            }.aspectRatio(2.35, contentMode: .fit).cornerRadius(18)
                        }.buttonStyle(ProgrammeCardStyle()).focused($bannerFocused)
                        .onMoveCommand { direction in
                            guard bannerFocused else { return }
                            switch direction {
                            case .left: advanceBanner(by: -1)
                            case .right: advanceBanner(by: 1)
                            default: break
                            }
                        }
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: advanceBanner(by: 1)
                            case .decrement: advanceBanner(by: -1)
                            @unknown default: break
                            }
                        }
                        // Match the 30-point bottom focus space beneath programme rows.
                        .padding(.bottom, 30)
                    }
                    ContinueWatchingRow(catalogue: catalogue, library: library)
                    ForEach(feed.rows) { row in
                        VStack(alignment: .leading, spacing: 18) {
                            Text(row.title).font(.title2).bold()
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 28) {
                                    ForEach(row.shows) { show in
                                        NavigationLink { CatalogueShowView(show: show, catalogue: catalogue, library: library) } label: { HomeProgrammeCard(show: show, poster: row.usesPosters).frame(width: row.usesPosters ? 260 : 360) }.buttonStyle(ProgrammeCardStyle()).accessibilityLabel(show.title).focused($focusedCard, equals: "\(row.id):\(show.id)")
                                    }
                                }.padding(.vertical, 30).padding(.horizontal, 24)
                            }.scrollClipDisabled().padding(.horizontal, -24)
                        }
                    }
                } else if catalogue.loading { ProgressView("Getting the latest programmes…") }
                else { Button("Retry homepage") { Task { await catalogue.refreshHome() } } }
            }.padding(.horizontal, 64).padding(.vertical, 26)
        }.scrollClipDisabled()
        .onAppear { visible = true }
        .task(id: phase) {
            #if DEBUG
            guard phase == .active else { return }
            do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "cards" { focusedCard = "preview:preview-0" }
            if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "banner-focused" || ProcessInfo.processInfo.environment["BEEB_HOME_HERO_FOCUS"] == "1" { bannerFocused = true }
            #endif
        }
        .task(id: state.heroFocusRequest) {
            guard state.heroFocusRequest > 0 else { return }; bannerFocused = true
        }
        .onDisappear { visible = false }
        .onChange(of: rotationKey) { _, _ in recordBannerValidation() }
        .task(id: rotationKey) {
            guard !rotationKey.paused, rotationKey.count > 1 else { return }
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard !Task.isCancelled, visible, !bannerFocused, phase == .active else { return }
            withAnimation(.easeInOut(duration: 0.4)) { state.banner = (state.banner + 1) % rotationKey.count }
        }
    }
    private func advanceBanner(by offset: Int) {
        let count = catalogue.home?.features.count ?? 0
        guard count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            state.banner = (min(state.banner, count - 1) + offset + count) % count
        }
    }
    private func recordBannerValidation() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] != nil else { return }
        let values: [String: Any] = ["index": state.banner, "count": rotationKey.count, "focused": bannerFocused, "visible": visible, "active": phase == .active, "timestamp": Date().timeIntervalSince1970]
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("UI-validation.json")
        if let data = try? JSONSerialization.data(withJSONObject: values) { try? data.write(to: output, options: .atomic) }
        #endif
    }

}
@MainActor final class BrowseState: ObservableObject { @Published var mode = "Categories" }
struct BrowseView: View {
    @Environment(\.beebFocusMemory) private var focusMemory
    @Environment(\.beebOpenSidebar) private var openSidebar
    @Environment(\.beebFocusNavigation) private var focusNavigation
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @ObservedObject var index: CatalogueIndexStore
    @AppStorage("display4KUHDCategory") private var display4KUHDCategory = true
    @StateObject private var state = BrowseState()
    @FocusState private var categoryFocus: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Browse").font(.system(size: 48, weight: .bold))
                BeebNavigationSegments(title: "Browse by", options: ["Categories", "A–Z"], selection: $state.mode)
                    .frame(width: 520)
                if state.mode == "Categories" {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 3), spacing: 24) {
                        if display4KUHDCategory {
                            NavigationLink { UHDCategoryView(index: index, catalogue: catalogue, library: library) } label: {
                                CategoryTile(title: "4K UHD", icon: "4k.tv")
                            }.buttonStyle(ProgrammeCardStyle()).rememberSidebarFocus()
                        }
                        ForEach(catalogue.genres) { genre in
                            NavigationLink { ProgrammePage(title: genre.title, category: genre.id, letter: nil, catalogue: catalogue, library: library) } label: {
                                CategoryTile(title: genre.title, icon: CategoryTile.icon(genre.id))
                            }.buttonStyle(ProgrammeCardStyle()).focused($categoryFocus, equals: genre.id)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 24) {
                        ForEach(CatalogueAPI.letters, id: \.self) { letter in
                            NavigationLink { ProgrammePage(title: letter.uppercased(), category: nil, letter: letter, catalogue: catalogue, library: library) } label: {
                                Text(letter.uppercased()).font(.title2).frame(maxWidth: .infinity, minHeight: 75)
                            }.rememberSidebarFocus()
                        }
                    }
                }
            }.padding(.horizontal, 60).padding(.top, 24).padding(.bottom, 60)
        }.onChange(of: categoryFocus) { _, category in
            if let category {
                let target = $categoryFocus
                focusMemory?.remember { target.wrappedValue = category }
            }
        }
    }
}
private struct CategoryTile: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: icon).font(.system(size: 34, weight: .medium)).foregroundStyle(.pink).frame(width: 52)
            Text(title).font(.system(size: 29, weight: .semibold)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
        }.padding(.horizontal, 26).frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
    }
    static func icon(_ id: String) -> String {
        switch id {
        case "drama-and-soaps": "theatermasks"
        case "films": "film"
        case "comedy": "face.smiling"
        case "documentaries": "doc.text.image"
        case "sport": "sportscourt"
        case "news": "newspaper"
        case "entertainment": "sparkles.tv"
        case "music": "music.note"
        case "food": "fork.knife"
        case "lifestyle": "house"
        case "history": "clock.arrow.circlepath"
        case "science-and-nature": "leaf"
        case "arts": "paintpalette"
        case "archive": "archivebox"
        default: "play.rectangle"
        }
    }
}
struct ProgrammePage: View {
    let title: String
    let category: String?
    let letter: String?
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @StateObject private var page = ContinuousCatalogueStore()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 48, weight: .bold))
                    Spacer()
                    if page.count > 0 {Text("\(page.count) programmes").font(.callout).foregroundStyle(.secondary)}
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 28)], spacing: 30) {
                    ForEach(Array(page.shows.enumerated()), id: \.element.id) { position, show in
                        NavigationLink { CatalogueShowView(show: show, catalogue: catalogue, library: library) } label: { ShowCard(show: show) }.buttonStyle(ProgrammeCardStyle()).rememberSidebarFocus()
                            .task {if position >= page.shows.count-6 {await page.next(category:category,letter:letter)}}
                    }
                }
                if page.loading {ProgressView()}
                if let error = page.error {
                    Text(error).font(.callout).foregroundStyle(.orange)
                    Button("Retry") {Task {await page.next(category:category,letter:letter)}}
                }
            }.padding(60)
        }.background(Color(red: 0.035, green: 0.015, blue: 0.055).ignoresSafeArea())
        .task {await page.next(category:category,letter:letter)}
        .onExitCommand { dismiss() }
    }
}
/// Give the image a finite proposal before scaledToFill; intrinsic artwork sizes
/// must never determine a row's card width or its focus outline.
struct ProgrammeThumbnail: View {
    let url: URL?
    let uhd: Bool
    var hdr = false
    var body: some View {
        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                        Rectangle().fill(.gray.opacity(0.15)).overlay(Image(systemName: "play.tv").font(.largeTitle))
                    }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) { if uhd { UHDListedBadge(hdr: hdr).padding(10) } }
    }
}
struct ProgrammeCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { ProgrammeCardSurface(content: configuration.label, pressed: configuration.isPressed) }
}
// no slab/outline; focused card lifts, others dim slightly.
private struct ProgrammeCardSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content
            .background(Color.white.opacity(focused ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(focused ? 1 : 0.82)
            .scaleEffect(pressed ? 0.98 : focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 26, y: 14)
            .animation(.easeOut(duration: 0.18), value: focused)
            .focusEffectDisabled().zIndex(focused ? 1 : 0)
    }
}
private struct HomeProgrammeCard: View {
    let show: CatalogueShow
    let poster: Bool
    var body: some View {
        if poster {
            AsyncImage(url: show.portraitImage) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { ZStack { Color(white: 0.12); Text(show.title).font(.title3).multilineTextAlignment(.center).padding(24) } }
            }.frame(width: 260, height: 390).clipped().cornerRadius(12)
                .accessibilityLabel(show.title)
        } else { ShowCard(show: show) }
    }
}
struct ShowCard: View {
    let show: CatalogueShow
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgrammeThumbnail(url: show.image, uhd: show.uhdListed == true, hdr: show.hdrListed == true)
            Text(show.title).font(.system(size: 26, weight: .semibold)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .topLeading)

        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }
}
@MainActor final class ShowState: ObservableObject {
    @Published var show: CatalogueShow?
    @Published var seriesID = ""
    @Published var selection: Programme?
    @Published var error: String?
    @Published var retry = 0
    @Published var episodePage = 1
}
struct CatalogueShowView: View {
    let show: CatalogueShow
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    var preferUHDSeries = false
    @StateObject private var state = ShowState()
    @StateObject private var bookmarkFocus = BookmarkFocusDestination()
    @State private var episodeColumns = 5
    @FocusState private var focusedEpisode: String?
    @EnvironmentObject private var history: WatchHistory
    /// What the big button should open: resume the part-watched episode, the next one after a finished one,
    /// or the first episode of the oldest series.
    private var watchTarget: (label: String, programme: Programme, subtitle: String)? {
        if let record = history.records.first(where: { $0.id == current.id }) {
            if !record.completed { return ("Resume", record.episode.programme, record.episode.subtitle) }
            if let next = record.nextEpisode { return ("Next episode", next.programme, next.subtitle) }
        }
        guard let series = orderedSeries.first, let first = EpisodeSequence.ordered(series.episodes).first else { return nil }
        return ("Start watching", first.programme, first.subtitle)
    }
    var current: CatalogueShow { state.show ?? show }
    var orderedSeries: [CatalogueSeries] { EpisodeSequence.orderedSeries(current.series) }
    var selectedEpisodes: [CatalogueEpisode] {
        let group = orderedSeries.first { $0.id == state.seriesID } ?? orderedSeries.last   // newest series by default
        let episodes = EpisodeSequence.ordered(group?.episodes ?? [])
        return ProfileStore.shared.kidsMode ? episodes.filter { ($0.programme.guidance ?? "").isEmpty } : episodes
    }
    var visibleEpisodes: [CatalogueEpisode] { Array(selectedEpisodes.dropFirst((state.episodePage - 1) * 30).prefix(30)) }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text(current.title).font(.largeTitle).bold(); Spacer()
                    ProgrammeBookmarkButton(show: current, library: library)
                        .background(BookmarkFocusAnchor(destination: bookmarkFocus))
                }.focusSection()
                Text(current.summary).font(.system(size: 28)).foregroundStyle(.secondary).lineLimit(5)
                if let target = watchTarget {   // Start watching / Resume
                    HStack(spacing: 28) {
                        Button { state.selection = target.programme } label: {
                            HStack(spacing: 14) { Image(systemName: "play.fill"); Text(target.label) }
                        }.buttonStyle(PrimaryPlayButtonStyle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(target.label == "Resume" ? "Continue" : target.label).font(.system(size: 22)).foregroundStyle(.secondary)
                            Text(target.subtitle).font(.system(size: 30, weight: .semibold)).lineLimit(1)
                        }
                    }.padding(.vertical, 8).focusSection()
                }
                if state.show == nil && state.error == nil { ProgressView("Getting series and episodes…") }
                if let error = state.error { Text(error).foregroundStyle(.orange); Button("Retry") { state.retry += 1 } }
                if orderedSeries.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            ForEach(orderedSeries) { series in
                                Button(series.title) { state.seriesID = series.id; state.episodePage = 1 }
                                    .buttonStyle(SeriesTabStyle(selected: (state.seriesID.isEmpty ? orderedSeries.last?.id : state.seriesID) == series.id))
                            }
                        }.padding(.vertical, 30).padding(.horizontal, 24)
                    }.scrollClipDisabled().padding(.horizontal, -24).focusSection()   // Up from any episode lands here
                }
                if selectedEpisodes.count > 30 {
                    HStack(spacing: 24) {
                        Button("Previous episodes") { state.episodePage -= 1 }.disabled(state.episodePage <= 1)
                        Text("Episodes \((state.episodePage - 1) * 30 + 1)–\(min(state.episodePage * 30, selectedEpisodes.count))")
                        Button("More episodes") { state.episodePage += 1 }.disabled(state.episodePage * 30 >= selectedEpisodes.count)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 36)], spacing: 30) {  // 4 columns (3 in sidebar layout)
                    ForEach(visibleEpisodes) { episode in
                        Button { state.selection = episode.programme } label: { ProgrammeCard(programme: episode.programme) }.buttonStyle(ProgrammeCardStyle()).focused($focusedEpisode, equals: episode.id)
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { episodeColumns = max(1, Int((geometry.size.width + 36) / 416)) }
                            .onChange(of: geometry.size.width) { _, width in episodeColumns = max(1, Int((width + 36) / 416)) }
                    }
                }
                .background(alignment: .top) {
                    WideBookmarkFocusGuide(destination: bookmarkFocus, enabled: orderedSeries.count <= 1 && visibleEpisodes.prefix(episodeColumns).contains { $0.id == focusedEpisode })
                        .frame(height: 24).offset(y: -26)
                }
                if state.show != nil && selectedEpisodes.isEmpty { Text("No episodes are currently available.").foregroundStyle(.secondary) }
                if selectedEpisodes.count > 30 {   // pager at the bottom too
                    HStack(spacing: 24) {
                        Button("Previous episodes") { state.episodePage -= 1 }.disabled(state.episodePage <= 1)
                        Text("Episodes \((state.episodePage - 1) * 30 + 1)–\(min(state.episodePage * 30, selectedEpisodes.count))")
                        Button("More episodes") { state.episodePage += 1 }.disabled(state.episodePage * 30 >= selectedEpisodes.count)
                    }.padding(.top, 20)
                }
            }.padding(60)
        }.task(id: state.retry) {
            state.error = nil
            do {
                state.show = try await catalogue.open(show)
                if preferUHDSeries && state.seriesID.isEmpty {
                    state.seriesID = orderedSeries.last(where: { $0.episodes.contains { $0.programme.uhdListed == true } })?.id ?? ""
                }
            } catch { if !Task.isCancelled { state.error = error.localizedDescription } }
        }.defaultFocus($focusedEpisode, visibleEpisodes.first?.id)
        .task(id: visibleEpisodes.first?.id) {
            guard let first = visibleEpisodes.first?.id else { return }
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            focusedEpisode = first
        }.sheet(item: $state.selection) { DetailView(programme: $0, show: current, library: library) }
        .onExitCommand { dismiss() }
    }
}
struct SavedProgrammes: View {
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label("Saved programmes", systemImage: "bookmark.fill").font(.largeTitle).bold()
                if let warning = library.migrationWarning { Text(warning).foregroundStyle(.orange).font(.callout) }
                if library.saved.isEmpty { Text("Save a programme to follow all of its series and episodes here.").foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330))], spacing: 30) {
                    ForEach(library.saved) { show in
                        NavigationLink { CatalogueShowView(show: show, catalogue: catalogue, library: library) } label: { ShowCard(show: show) }.buttonStyle(ProgrammeCardStyle()).rememberSidebarFocus()
                    }
                }
            }.padding(60)
        }.task { await library.migrate(); await library.refreshArtwork() }
    }
}
@MainActor final class LiveState: ObservableObject {
    @Published var channels: [LiveChannel] = []
    @Published var error: String?
    @Published var retry = 0
    @Published var playing = false
}
struct LiveView: View {
    var launch: LiveLaunch? = nil
    var library: Library? = nil
    @State private var selectedChannel: String?
    @State private var guides: [String: ChannelGuide] = [:]
    @State private var detail: Programme?
    @FocusState private var stripFocus: String?
    @AppStorage("offerLiveFromStart") private var offerFromStart = false
    @State private var askFromStart: LiveChannel?
    /// Ask "from the start or live?" when that's enabled and the programme has been on for over a minute.
    private func play(_ channel: LiveChannel, fromStart: Bool? = nil) {
        if fromStart == nil, offerFromStart, let start = channel.current?.start, Date().timeIntervalSince(start) > 60 {
            askFromStart = channel; return
        }
        playback.startLive(channel, fromStart: fromStart ?? false) { state.playing = true }
    }
    private var currentChannelID: String? { selectedChannel ?? state.channels.filter { !profileStore.kidsMode || Self.kidsChannels.contains($0.id) }.first?.id }
    @ObservedObject private var profileStore = ProfileStore.shared
    private static let kidsChannels: Set<String> = ["cbbc", "cbeebies"]
    @Environment(\.scenePhase) private var phase
    @StateObject private var state = LiveState()
    @StateObject private var playback = PlaybackModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if state.channels.isEmpty && state.error == nil { ProgressView("Getting channels…") }
                if let error = state.error { Text(error).foregroundStyle(.orange); Button("Retry channels") { state.retry += 1 } }
                if let error = playback.error { Text(error).foregroundStyle(.orange) }
                if playback.loading { HStack { ProgressView("Connecting to live channel…"); Button("Cancel") { playback.stop() } } }
                // channel strip
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(state.channels.filter { !profileStore.kidsMode || Self.kidsChannels.contains($0.id) }) { channel in
                            Button { play(channel) } label: {
                                Text(ChannelWordmark.style(id: channel.id, title: channel.title).label)
                            }.buttonStyle(ChannelStripStyle(id: channel.id, title: channel.title, selected: currentChannelID == channel.id))
                                .focused($stripFocus, equals: channel.id).disabled(playback.loading)
                        }
                    }.padding(.vertical, 20).padding(.horizontal, 8)
                }.scrollClipDisabled().focusSection()
                if let channel = state.channels.filter { !profileStore.kidsMode || Self.kidsChannels.contains($0.id) }.first(where: { $0.id == currentChannelID }) {
                    let guide = guides[channel.id]
                    let hide = profileStore.kidsMode
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 40) {
                            Button { play(channel) } label: { OnNowCard(channel: channel) }
                                .buttonStyle(ProgrammeCardStyle()).disabled(playback.loading)
                            ForEach((guide?.featured ?? []).filter { !hide || ($0.programme.guidance ?? "").isEmpty }) { episode in
                                Button { detail = episode.programme } label: { GuideCard(programme: episode.programme, width: 560) }
                                    .buttonStyle(ProgrammeCardStyle())
                            }
                        }.padding(.vertical, 24).padding(.horizontal, 8)
                    }.scrollClipDisabled().focusSection()
                    if guide == nil { ProgressView("Getting \(channel.title) programmes…") }
                    ForEach(guide?.rows ?? []) { row in
                        let episodes = row.episodes.filter { !hide || ($0.programme.guidance ?? "").isEmpty }
                        if !episodes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(row.title).font(.system(size: 34, weight: .bold))
                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 36) {
                                        ForEach(episodes) { episode in
                                            Button { detail = episode.programme } label: { GuideCard(programme: episode.programme, width: 440) }
                                                .buttonStyle(ProgrammeCardStyle())
                                        }
                                    }.padding(.vertical, 20).padding(.horizontal, 8)
                                }.scrollClipDisabled()
                            }.focusSection()
                        }
                    }
                }
            }.padding(.horizontal, 60).padding(.vertical, 30)
        }.onChange(of: stripFocus) { _, id in if let id { selectedChannel = id } }
        .task(id: currentChannelID) {
            guard let id = currentChannelID, guides[id] == nil else { return }
            guides[id] = await ChannelGuideAPI.load(id)
        }
        .sheet(item: $detail) { programme in if let library { DetailView(programme: programme, library: library) } }
        .confirmationDialog(askFromStart.map { $0.current?.title ?? $0.title } ?? "",
                            isPresented: Binding(get: { askFromStart != nil }, set: { if !$0 { askFromStart = nil } }), titleVisibility: .visible) {
            if let channel = askFromStart {
                Button("Watch from the start" + (channel.current?.start.map { " (" + $0.formatted(date: .omitted, time: .shortened) + ")" } ?? "")) { play(channel, fromStart: true) }
                Button("Watch live") { play(channel, fromStart: false) }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task(id: "\(state.retry)-\(phase)-\(state.playing)") {
            guard phase == .active, !state.playing else { return }
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEEB_LIVE_ROUTE_VALIDATE"] == "1" || ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "review" { return }
            #endif
            state.error = nil
            do {
                let api = DiscoveryAPI()
                if state.channels.isEmpty { state.channels = try await api.channels() }
                while !Task.isCancelled {
                    let channels = await api.nowPlaying(state.channels)
                    try Task.checkCancellation(); state.channels = channels
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                }
            } catch { if !Task.isCancelled { state.error = error.localizedDescription } }
        }.task(id: launch?.id) {
            guard let launch else { return }
            if profileStore.kidsMode && !Self.kidsChannels.contains(launch.channelID) { state.error = "This channel isn't available on a kids profile."; return }
            // Allow an existing episode cover to dismiss before the Live page presents.
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
                var channel = state.channels.first { $0.id == launch.channelID }
                if channel == nil, let known = LiveShelfChannel.defaults.first(where: { $0.id == launch.channelID }) {
                    channel = LiveChannel(id: known.id, title: known.title)
                }
                if channel == nil { channel = try await DiscoveryAPI().channels().first { $0.id == launch.channelID } }
                try Task.checkCancellation()
                guard let channel else { state.error = "This channel is not currently available."; return }
                play(channel)
            } catch { if !Task.isCancelled { state.error = error.localizedDescription } }
        }.fullScreenCover(isPresented: $state.playing, onDismiss: { playback.stop() }) { PlaybackScreen(model: playback) }
        .onDisappear { if !state.playing { playback.stop() } }
    }
}
struct SettingsView: View {
    @Environment(\.beebOpenSidebar) private var openSidebar
    @Environment(\.beebFocusNavigation) private var focusNavigation
    @ObservedObject var catalogue: CatalogueStore
    @AppStorage("display4KUHDCategory") private var display4KUHDCategory = true
    @AppStorage("offerLiveFromStart") private var offerLiveFromStart = false
    @AppStorage("homescreenLayout") private var homescreenLayout = "Modern"
    @AppStorage("modernNavigation") private var modernNavigation = "Sidebar"
    @AppStorage("bbcOneRegion") private var bbcOne = "bbc_one_london"
    @AppStorage("bbcTwoRegion") private var bbcTwo = "bbc_two_england"
    @ObservedObject private var profileStore = ProfileStore.shared
    @AppStorage(BeebSyncSettings.urlKey) private var syncURL = ""
    @AppStorage(BeebSyncSettings.secretKey) private var syncSecret = ""
    @State private var syncStatus = ""
    @State private var editingProfile: String?        // nil = add a new profile
    @State private var showProfileEditor = false
    @State private var settingPIN = false
    private var startupChoices: [String] { ["last"] + profileStore.profiles.map(\.id) + ["ask"] }
    private func startupLabel(_ value: String) -> String {
        value == "last" ? "Last used" : value == "ask" ? "Ask" : profileStore.name(value)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Settings").font(.system(size: 56, weight: .bold))
                VStack(alignment: .leading, spacing: 16) {
                    Text("Profiles").font(.system(size: 32, weight: .bold))
                    Text("Each person has their own Continue Watching and Saved list.").font(.system(size: 22)).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 28) {
                            ForEach(profileStore.profiles) { profile in
                                Button { editingProfile = profile.id; showProfileEditor = true } label: {
                                    ProfileAvatar(name: profile.name, current: profile.id == profileStore.current, size: 130)
                                }.buttonStyle(ProgrammeCardStyle())
                            }
                            Button { editingProfile = nil; showProfileEditor = true } label: {
                                VStack(spacing: 12) {
                                    Image(systemName: "plus").font(.system(size: 50, weight: .semibold))
                                        .frame(width: 130, height: 130).background(Circle().fill(.white.opacity(0.12)))
                                    Text("Add").font(.system(size: 24, weight: .semibold))
                                }.padding(16)
                            }.buttonStyle(ProgrammeCardStyle())
                        }.padding(.vertical, 16).padding(.horizontal, 8)
                    }.scrollClipDisabled()
                    Text("Select a profile to rename it, switch to it, make it a kids profile or remove it.").font(.system(size: 22)).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        Button(profileStore.kidsPIN.isEmpty ? "Set kids PIN" : "Change kids PIN") { settingPIN = true }
                        if !profileStore.kidsPIN.isEmpty { Button("Remove kids PIN") { profileStore.kidsPIN = "" } }
                        Text(profileStore.kidsPIN.isEmpty ? "No PIN: anyone can switch away from a kids profile."
                                                          : "The PIN is needed to leave a kids profile. With household sync it applies on every Apple TV.")
                            .font(.system(size: 22)).foregroundStyle(.secondary)
                    }
                    Text("On launch").font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
                    ScrollView(.horizontal) {
                        BeebNavigationSegments(title: "Profile on launch", options: startupChoices.map(startupLabel), selection: Binding(
                            get: { startupLabel(profileStore.startup) },
                            set: { label in if let value = startupChoices.first(where: { startupLabel($0) == label }) { profileStore.startup = value } }))
                            .frame(width: CGFloat(startupChoices.count) * 220)
                            .padding(.vertical, 12).padding(.horizontal, 4)
                    }.scrollClipDisabled()
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
                    .focusSection()   // Down from the menu bar lands in this section even though its first control is at the far left
                    .fullScreenCover(isPresented: $settingPIN) {
                        PINPadView(title: "Choose a 4-digit kids PIN", validate: nil) { pin in
                            if let pin { profileStore.kidsPIN = pin }
                            settingPIN = false
                        }
                    }
                    .fullScreenCover(isPresented: $showProfileEditor) {
                        ProfileEditView(profileID: editingProfile) { showProfileEditor = false }
                    }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Household sync").font(.system(size: 32, weight: .bold))
                    Text("Optional. Shares profiles, Continue Watching and Saved between your Apple TVs through a sync server you run, for example the Home Assistant AppDaemon app. Leave the URL empty to keep everything on this Apple TV.")
                        .font(.system(size: 22)).foregroundStyle(.secondary)
                    TextField("Server URL, e.g. http://homeassistant.local:5050/api/appdaemon/beeb_history", text: $syncURL).frame(width: 1200)
                    SecureField("Key", text: $syncSecret).frame(width: 1200)
                    HStack(spacing: 24) {
                        Button("Test connection") { Task { syncStatus = await BeebSyncClient.test() } }
                        Text(syncStatus).font(.system(size: 22)).foregroundStyle(.secondary)
                    }
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
                    .focusSection()
                    .onChange(of: syncURL) { _, _ in profileStore.scheduleSync(); NotificationCenter.default.post(name: ProfileStore.changed, object: nil) }
                    .onChange(of: syncSecret) { _, _ in profileStore.scheduleSync(); NotificationCenter.default.post(name: ProfileStore.changed, object: nil) }
                VStack(alignment: .leading, spacing: 24) {
                    Text("Homescreen Layout").font(.system(size: 32, weight: .bold))
                    BeebNavigationSegments(title: "Homescreen Layout", options: ["Modern", "Classic"], selection: $homescreenLayout)
                        .frame(width: 520).accessibilityIdentifier("HomescreenLayoutPicker")
                    if homescreenLayout == "Modern" {
                        Text("Navigation").font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary)
                        BeebNavigationSegments(title: "Modern Navigation", options: ["Topbar", "Sidebar"], selection: $modernNavigation)
                            .frame(width: 520).accessibilityIdentifier("ModernNavigationPicker")
                    }
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
                Toggle("Offer watch from start for live TV", isOn: $offerLiveFromStart)
                Text("When on, opening a channel part-way through a programme asks whether to watch from the start or live. When off, live TV always starts live. You can also jump back with Watch from start in the player.")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                Toggle("Display 4K UHD category", isOn: $display4KUHDCategory)
                    .accessibilityIdentifier("Display4KUHDCategoryToggle").rememberSidebarFocus()
                Text("Playback automatically selects the best available quality, including 4K HDR when available. Live channel quality adapts to the stream BBC supplies.").foregroundStyle(.secondary)
                NavigationLink {
                    RegionSelectionView(title: "BBC One region", choices: RegionalChannels.bbcOne, selection: $bbcOne)
                } label: { RegionSettingLabel(title: "BBC One region", value: RegionalChannels.bbcOne.first { $0.id == bbcOne }?.title ?? "London") }.rememberSidebarFocus()
                NavigationLink {
                    RegionSelectionView(title: "BBC Two version", choices: RegionalChannels.bbcTwo, selection: $bbcTwo)
                } label: { RegionSettingLabel(title: "BBC Two version", value: RegionalChannels.bbcTwo.first { $0.id == bbcTwo }?.title ?? "England / Scotland") }.rememberSidebarFocus()
                Button("Refresh homepage") { Task { await catalogue.refreshHome() } }.disabled(catalogue.loading).rememberSidebarFocus()
                Text("Programme listings load only when you select a category or letter. Series and episodes load when you open a programme. Saved programmes include all their series.")
                if let warning = catalogue.storageWarning { Text(warning).foregroundStyle(.orange) }
                UHDSetupView()
                Text("Beeb \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") • Independent BBC player").font(.caption).foregroundStyle(.secondary)
            }.font(.system(size: 26)).padding(60)
        }
    }
}

private struct RegionSettingLabel: View {
    let title: String
    let value: String
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary); Image(systemName: "chevron.right") }
            .frame(maxWidth: .infinity).padding(.vertical, 0)
    }
}
private struct RegionSelectionView: View {
    let title: String
    let choices: [RegionalChannelChoice]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.system(size: 52, weight: .bold))
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 36), GridItem(.flexible())], spacing: 22) {
                    ForEach(choices) { choice in
                        Button {
                            selection = choice.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(choice.title); Spacer()
                                Image(systemName: selection == choice.id ? "checkmark.circle.fill" : "circle").opacity(selection == choice.id ? 1 : 0.3).symbolRenderingMode(.palette).foregroundStyle(selection == choice.id ? Color.pink : Color.secondary)
                            }.frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 14)
                        }.buttonStyle(OutlinedActionButtonStyle())
                    }
                }.padding(.horizontal, 36).padding(.vertical, 20)
            }.scrollClipDisabled()
        }.padding(60)
        .onExitCommand { dismiss() }
    }
}

private struct RootBackAction: ViewModifier {
    let active: Bool
    let action: () -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if active { content.onExitCommand(perform: action) } else { content }
    }
}

struct ProfilePillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { ProfilePillSurface(content: configuration.label, pressed: configuration.isPressed) }
}
private struct ProfilePillSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content.font(.system(size: 22, weight: .semibold))
            .foregroundStyle(focused ? Color.black : Color.white.opacity(0.9))
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background { Capsule().fill(focused ? Color.white : Color.white.opacity(0.08)) }
            .shadow(color: .pink.opacity(focused ? 0.55 : 0), radius: 20)
            .scaleEffect(pressed ? 0.96 : focused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
            .focusEffectDisabled()
    }
}
/// "Who's watching?" grid for any number of profiles. Back keeps the current profile unless a choice is required.
struct WhoIsWatchingView: View {
    @ObservedObject private var store = ProfileStore.shared
    let required: Bool
    let dismiss: () -> Void
    let choose: (String) -> Void
    @FocusState private var focused: String?
    @State private var pending: String?
    var body: some View {
        VStack(spacing: 60) {
            Text("Who's watching?").font(.system(size: 56, weight: .bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 40)], spacing: 40) {
                ForEach(store.profiles) { profile in
                    Button { if store.needsPIN(toSelect: profile.id) { pending = profile.id } else { choose(profile.id) } } label: {
                        ProfileAvatar(name: profile.name, current: profile.id == store.current)
                    }.buttonStyle(ProgrammeCardStyle()).focused($focused, equals: profile.id)
                }
            }.frame(maxWidth: 1400)
            if !required { Text("Press Back to keep \(store.currentProfile.name)").font(.system(size: 22)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55).ignoresSafeArea())
        .background(.ultraThickMaterial)
        .defaultFocus($focused, store.current)
        .onExitCommand { if !required { dismiss() } }
        .interactiveDismissDisabled(required)
        .fullScreenCover(item: Binding(get: { pending.map { PendingProfile(id: $0) } }, set: { pending = $0?.id })) { item in
            PINPadView(title: "Enter the kids PIN to switch to \(store.name(item.id))", validate: { $0 == store.kidsPIN }) { pin in
                let id = item.id
                pending = nil
                if pin != nil { choose(id) }
            }
        }
    }
}

/// Round initial avatar used in the picker and Settings.
struct ProfileAvatar: View {
    let name: String
    let current: Bool
    var size: CGFloat = 200
    var body: some View {
        VStack(spacing: size * 0.09) {
            Text(String(name.prefix(1)).uppercased()).font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size).background(Circle().fill(Color.pink.opacity(0.85)))
                .overlay { if current { Circle().strokeBorder(.white, lineWidth: max(4, size * 0.03)) } }
            Text(name.isEmpty ? " " : name).font(.system(size: max(22, size * 0.16), weight: .semibold)).lineLimit(1)
        }.padding(size * 0.12)
    }
}
/// Add or edit a profile: a real text field (opens the Apple TV keyboard), Save / Switch to / Remove / Cancel.
struct ProfileEditView: View {
    @ObservedObject private var store = ProfileStore.shared
    let profileID: String?
    let done: () -> Void
    @State private var name = ""
    @State private var confirmRemove = false
    @State private var kids = false
    @FocusState private var nameFocused: Bool
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 44) {
            Text(profileID == nil ? "Add profile" : "Edit profile").font(.system(size: 56, weight: .bold))
            HStack(spacing: 48) {
                ProfileAvatar(name: trimmed.isEmpty ? "?" : trimmed, current: profileID == store.current, size: 180)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Name").font(.system(size: 24, weight: .semibold)).foregroundStyle(.secondary)
                    TextField("Name", text: $name).font(.system(size: 32)).frame(width: 760).focused($nameFocused)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                    Toggle("Kids profile", isOn: $kids).frame(width: 760).padding(.top, 12)
                    Text("CBeebies and CBBC only, no programmes with BBC guidance warnings, and no Settings.")
                        .font(.system(size: 20)).foregroundStyle(.secondary).frame(width: 760, alignment: .leading)
                }
            }
            HStack(spacing: 24) {
                Button(profileID == nil ? "Add profile" : "Save") {
                    if let id = profileID { store.rename(id, to: trimmed); store.setKids(id, kids) }
                    else if let added = store.add(trimmed) { store.setKids(added.id, kids) }
                    done()
                }.buttonStyle(PrimaryPlayButtonStyle()).disabled(trimmed.isEmpty)
                if let id = profileID, id != store.current {
                    Button("Switch to") { store.rename(id, to: trimmed); store.select(id); done() }
                }
                if let id = profileID, store.profiles.count > 1, store.profiles.contains(where: { $0.id == id }) {
                    Button("Remove") { confirmRemove = true }
                }
                Button("Cancel") { done() }
            }.buttonStyle(OutlinedActionButtonStyle())
        }.padding(90).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.55).ignoresSafeArea())
        .background(.ultraThickMaterial)
        .onAppear {
            if let id = profileID { name = store.name(id); kids = store.profiles.first { $0.id == id }?.kids ?? false } else { nameFocused = true }
        }
        .onExitCommand { done() }
        .alert("Remove \(store.name(profileID ?? ""))?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { if let id = profileID { store.remove(id) }; done() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Their Continue Watching and Saved list will be deleted on every Apple TV.") }
    }
}

// typographic channel wordmark, in the style of the official app's channel strip.
struct ChannelWordmark: View {
    let id: String
    let title: String
    private var style: (label: String, colour: Color) { Self.style(id: id, title: title) }
    static func style(id: String, title: String) -> (label: String, colour: Color) {
        switch true {
        case id.hasPrefix("bbc_one"): return ("ONE", Color(red: 0.89, green: 0.28, blue: 0.27))
        case id.hasPrefix("bbc_two"): return ("TWO", Color(red: 0.42, green: 0.23, blue: 0.62))
        case id.hasPrefix("bbc_three"): return ("THREE", Color(red: 0.55, green: 0.75, blue: 0.13))
        case id.hasPrefix("bbc_four"): return ("FOUR", Color(red: 0.12, green: 0.36, blue: 0.62))
        case id == "cbbc": return ("CBBC", Color(red: 0.36, green: 0.73, blue: 0.24))
        case id == "cbeebies": return ("CBeebies", Color(red: 0.98, green: 0.76, blue: 0.10))
        case id.hasPrefix("bbc_news"): return ("NEWS", Color(red: 0.73, green: 0.10, blue: 0.10))
        case id.hasPrefix("bbc_parliament"): return ("PARLIAMENT", Color(red: 0.15, green: 0.42, blue: 0.33))
        case id.hasPrefix("bbc_scotland"): return ("SCOTLAND", Color(red: 0.10, green: 0.30, blue: 0.62))
        case id.hasPrefix("bbc_alba"): return ("ALBA", Color(red: 0.05, green: 0.55, blue: 0.62))
        case id.hasPrefix("s4c"): return ("S4C", Color(red: 0.95, green: 0.55, blue: 0.10))
        default: return (title.replacingOccurrences(of: "BBC ", with: "").uppercased(), Color(white: 0.2))
        }
    }
    var body: some View {
        Text(style.label).font(.system(size: 24, weight: .heavy)).tracking(0.5)
            .foregroundStyle(id == "cbeebies" ? Color.black : Color.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(style.colour, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .accessibilityLabel(title)
    }
}
/// Thin line along the bottom of a live tile: how far through the current programme we are.
struct LiveProgressLine: View {
    let programme: LiveProgramme?
    var body: some View {
        if let p = programme, let start = p.start, p.end > start {
            let fraction = min(1, max(0, Date().timeIntervalSince(start) / p.end.timeIntervalSince(start)))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.45))
                    Rectangle().fill(Color.pink).frame(width: g.size.width * fraction)
                }
            }.frame(height: 6).clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
        }
    }
}

private struct PendingProfile: Identifiable { let id: String }

/// Remote-friendly 4-digit PIN pad. validate == nil: choose a new PIN; otherwise check it. Back cancels.
struct PINPadView: View {
    let title: String
    let validate: ((String) -> Bool)?
    let done: (String?) -> Void
    @State private var digits = ""
    @State private var message = ""
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "Delete", "0", "Cancel"]
    var body: some View {
        VStack(spacing: 36) {
            Text(title).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center)
            HStack(spacing: 24) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i < digits.count ? Color.white : Color.white.opacity(0.2)).frame(width: 30, height: 30)
                }
            }
            Text(message.isEmpty ? " " : message).font(.system(size: 24)).foregroundStyle(.orange)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(180), spacing: 24), count: 3), spacing: 24) {
                ForEach(keys, id: \.self) { key in
                    Button(key) { press(key) }.buttonStyle(OutlinedActionButtonStyle()).frame(width: 180)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55).ignoresSafeArea())
        .background(.ultraThickMaterial)
        .onExitCommand { done(nil) }
    }
    private func press(_ key: String) {
        switch key {
        case "Cancel": done(nil)
        case "Delete": if !digits.isEmpty { digits.removeLast() }
        default:
            guard digits.count < 4 else { return }
            digits += key; message = ""
            if digits.count == 4 {
                if let validate, !validate(digits) { message = "That PIN isn't right."; digits = "" }
                else { done(digits) }
            }
        }
    }
}

/// Home for a kids profile: their Continue Watching plus CBeebies and CBBC programmes.
struct KidsHomeView: View {
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    private struct Row: Identifiable { let id: String; let title: String; let shows: [CatalogueShow] }
    @State private var rows: [Row] = []
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                ContinueWatchingRow(catalogue: catalogue, library: library)
                if rows.isEmpty && error == nil { ProgressView("Getting CBeebies and CBBC…") }
                if let error { Text(error).foregroundStyle(.orange) }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(row.title).font(.system(size: 36, weight: .bold))
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 36) {
                                ForEach(row.shows) { show in
                                    NavigationLink { CatalogueShowView(show: show, catalogue: catalogue, library: library) } label: {
                                        ShowCard(show: show).frame(width: 400)
                                    }.buttonStyle(ProgrammeCardStyle())
                                }
                            }.padding(.vertical, 24).padding(.horizontal, 8)
                        }.scrollClipDisabled()
                    }.focusSection()
                }
            }.padding(60)
        }.task {
            var loaded: [Row] = []
            for (id, title) in [("cbeebies", "CBeebies"), ("cbbc", "CBBC")] {
                if let page = try? await DiscoveryAPI().page(category: id, page: 1), !page.shows.isEmpty {
                    loaded.append(Row(id: id, title: title, shows: page.shows))
                }
            }
            rows = loaded
            if loaded.isEmpty { error = "CBeebies and CBBC programmes couldn't be loaded. Try again later." }
        }
    }
}

// data + views
struct ChannelGuide {
    struct Row: Identifiable { let id: String; let title: String; let episodes: [CatalogueEpisode] }
    var featured: [CatalogueEpisode] = []
    var rows: [Row] = []
}
enum ChannelGuideAPI {
    static func load(_ channelID: String) async -> ChannelGuide {
        guard channelID.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil else { return ChannelGuide() }
        let api = DiscoveryAPI()
        func json(_ path: String) async -> [String: Any]? {
            guard let url = URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/" + path), let data = try? await api.fetch(url) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        var guide = ChannelGuide()
        guard let elements = ((await json("channels/\(channelID)/highlights"))?["channel_highlights"] as? [String: Any])?["elements"] as? [[String: Any]] else { return guide }
        var groups: [(String, String)] = []
        for element in elements {
            let type = element["type"] as? String ?? ""
            if type == "episode", let episode = try? CatalogueAPI.episode(element) { guide.featured.append(episode) }
            else if type.hasPrefix("group"), let id = element["id"] as? String, let title = element["title"] as? String,
                    id.range(of: "^[a-z0-9]+$", options: .regularExpression) != nil { groups.append((id, title)) }
        }
        for (id, title) in groups.prefix(8) {
            let items = ((await json("groups/\(id)/episodes?per_page=24"))?["group_episodes"] as? [String: Any])?["elements"] as? [[String: Any]] ?? []
            let episodes = items.compactMap { try? CatalogueAPI.episode($0) }
            if !episodes.isEmpty { guide.rows.append(.init(id: id, title: title, episodes: episodes)) }
        }
        return guide
    }
}
/// Big wordmark in the channel strip: brand colour when focused, underline when it's the channel shown below.
struct ChannelStripStyle: ButtonStyle {
    let id: String
    let title: String
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        ChannelStripSurface(content: configuration.label, colour: ChannelWordmark.style(id: id, title: title).colour,
                            selected: selected, pressed: configuration.isPressed)
    }
}
private struct ChannelStripSurface<Content: View>: View {
    let content: Content
    let colour: Color
    let selected: Bool
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content.font(.system(size: 30, weight: .heavy)).lineLimit(1).fixedSize()
            .foregroundStyle(Color.white.opacity(focused || selected ? 1 : 0.7))
            .padding(.horizontal, 22).frame(minWidth: 110, minHeight: 70)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(focused ? colour : Color.clear))
            .overlay(alignment: .bottom) { if selected && !focused { Capsule().fill(colour).frame(height: 5).padding(.horizontal, 18).offset(y: -4) } }
            .scaleEffect(pressed ? 0.96 : focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 10, y: 4)
            .animation(.easeOut(duration: 0.15), value: focused)
            .focusEffectDisabled()
    }
}
/// First card in the row: what's on now, with an ON NOW badge and progress line.
struct OnNowCard: View {
    let channel: LiveChannel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgrammeThumbnail(url: channel.current?.image, uhd: false)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("ON NOW")
                    }.font(.system(size: 22, weight: .heavy)).foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.75))
                        .padding(.horizontal, 12).padding(.vertical, 6).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                        .padding(12)
                }
                .overlay(alignment: .bottom) { LiveProgressLine(programme: channel.current) }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            Text(channel.current?.title ?? channel.title).font(.system(size: 28, weight: .semibold)).lineLimit(1).padding(.top, 8)
            Text(channel.current.map { "Live until " + $0.end.formatted(date: .omitted, time: .shortened) } ?? "Watch live")
                .font(.system(size: 21)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(14).frame(width: 640, alignment: .leading)
    }
}
/// Programme card in the guide rows: the programme's name (as the official app does), subtitle underneath.
struct GuideCard: View {
    let programme: Programme
    let width: CGFloat
    @Environment(\.isFocused) private var focused
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgrammeThumbnail(url: programme.image, uhd: programme.uhdListed == true, hdr: programme.hdrListed == true)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            Text(programme.showTitle ?? programme.title).font(.system(size: 26, weight: .semibold)).lineLimit(1)
                .foregroundStyle(focused ? Color.white : Color.white.opacity(0.8)).padding(.top, 8)
            Text(programme.episodeSubtitle ?? " ").font(.system(size: 21)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(14).frame(width: width, alignment: .leading)
    }
}
