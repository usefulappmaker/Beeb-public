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
    private var visibleTabs: [BeebTab] { BeebTab.allCases.filter { display4KUHDCategory || $0 != .uhd } }
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
    @ViewBuilder private var navigationIcon: some View {
        if usesSidebar { sidebarHeader }
        else { horizontalHeader.focusSection().defaultFocus($focusedTab, tab) }
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
                if tab == .home && modern {
                    DiscoveryHome(catalogue: catalogue, library: library, state: homeState,
                                  header: navigationIcon, menuOpen: sidebarOpen,
                                  focusHeader: focusNavigation)
                } else {
                    VStack(spacing: 0) {
                        navigationIcon
                        Group {
                            switch tab {
                            case .home: ClassicDiscoveryHome(catalogue: catalogue, library: library, state: homeState)
                            case .uhd: UHDCategoryView(index: index, catalogue: catalogue, library: library)
                            case .browse: BrowseView(catalogue: catalogue, library: library, index: index)
                            case .search: CatalogueSearchView(index: index, catalogue: catalogue, library: library)
                            case .live: LiveView(launch: liveLaunch)
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
private struct ProgrammeCardSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content
            .background(focused ? Color.white.opacity(0.16) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(focused ? .white : .clear, lineWidth: 3) }
            .scaleEffect(pressed ? 0.99 : focused ? 1.045 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
            .animation(.easeOut(duration: 0.15), value: focused)
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
            Text(show.title).font(.headline).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .topLeading)

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
    var current: CatalogueShow { state.show ?? show }
    var orderedSeries: [CatalogueSeries] { EpisodeSequence.orderedSeries(current.series) }
    var selectedEpisodes: [CatalogueEpisode] {
        let group = orderedSeries.first { $0.id == state.seriesID } ?? orderedSeries.first
        return EpisodeSequence.ordered(group?.episodes ?? [])
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
                Text(current.summary).font(.title3).foregroundStyle(.secondary)
                if state.show == nil && state.error == nil { ProgressView("Getting series and episodes…") }
                if let error = state.error { Text(error).foregroundStyle(.orange); Button("Retry") { state.retry += 1 } }
                if orderedSeries.count > 1 {
                    ScrollView(.horizontal) {
                        HStack(spacing: 20) {
                            ForEach(orderedSeries) { series in
                                Button(series.title) { state.seriesID = series.id; state.episodePage = 1 }
                                    .tint((state.seriesID.isEmpty ? orderedSeries.first?.id : state.seriesID) == series.id ? .pink : .gray)
                            }
                        }.padding(.vertical, 30).padding(.horizontal, 24)
                    }.scrollClipDisabled().padding(.horizontal, -24)
                }
                if selectedEpisodes.count > 30 {
                    HStack(spacing: 24) {
                        Button("Previous episodes") { state.episodePage -= 1 }.disabled(state.episodePage <= 1)
                        Text("Episodes \((state.episodePage - 1) * 30 + 1)–\(min(state.episodePage * 30, selectedEpisodes.count))")
                        Button("More episodes") { state.episodePage += 1 }.disabled(state.episodePage * 30 >= selectedEpisodes.count)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 30)], spacing: 30) {
                    ForEach(visibleEpisodes) { episode in
                        Button { state.selection = episode.programme } label: { ProgrammeCard(programme: episode.programme) }.buttonStyle(ProgrammeCardStyle()).focused($focusedEpisode, equals: episode.id)
                    }
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.onAppear { episodeColumns = max(1, Int((geometry.size.width + 30) / 360)) }
                            .onChange(of: geometry.size.width) { _, width in episodeColumns = max(1, Int((width + 30) / 360)) }
                    }
                }
                .background(alignment: .top) {
                    WideBookmarkFocusGuide(destination: bookmarkFocus, enabled: visibleEpisodes.prefix(episodeColumns).contains { $0.id == focusedEpisode })
                        .frame(height: 24).offset(y: -26)
                }
                if state.show != nil && selectedEpisodes.isEmpty { Text("No episodes are currently available.").foregroundStyle(.secondary) }
            }.padding(60)
        }.task(id: state.retry) {
            state.error = nil
            do {
                state.show = try await catalogue.open(show)
                if preferUHDSeries && state.seriesID.isEmpty {
                    state.seriesID = orderedSeries.first(where: { $0.episodes.contains { $0.programme.uhdListed == true } })?.id ?? ""
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
    @Environment(\.scenePhase) private var phase
    @StateObject private var state = LiveState()
    @StateObject private var playback = PlaybackModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Live channels").font(.largeTitle).bold()
                if state.channels.isEmpty && state.error == nil { ProgressView("Getting channels…") }
                if let error = state.error { Text(error).foregroundStyle(.orange); Button("Retry channels") { state.retry += 1 } }
                if let error = playback.error { Text(error).foregroundStyle(.orange) }
                if playback.loading { HStack { ProgressView("Connecting to live channel…"); Button("Cancel") { playback.stop() } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 370))], spacing: 30) {
                    ForEach(state.channels) { channel in
                        Button { playback.startLive(channel) { state.playing = true } } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                ProgrammeThumbnail(url: channel.current?.image, uhd: false)
                                Text(channel.current?.title ?? channel.title).font(.headline).lineLimit(2)
                                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .topLeading)
                                Text(channel.title).font(.callout).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(ProgrammeCardStyle()).disabled(playback.loading).rememberSidebarFocus()
                    }
                }
            }.padding(60)
        }.task(id: "\(state.retry)-\(phase)-\(state.playing)") {
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
                playback.startLive(channel) { state.playing = true }
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
    @AppStorage("homescreenLayout") private var homescreenLayout = "Modern"
    @AppStorage("modernNavigation") private var modernNavigation = "Sidebar"
    @AppStorage("bbcOneRegion") private var bbcOne = "bbc_one_london"
    @AppStorage("bbcTwoRegion") private var bbcTwo = "bbc_two_england"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Text("Settings").font(.largeTitle).bold()
                VStack(alignment: .leading, spacing: 24) {
                    Text("Homescreen Layout").font(.title2).bold()
                    BeebNavigationSegments(title: "Homescreen Layout", options: ["Modern", "Classic"], selection: $homescreenLayout)
                        .frame(width: 700).accessibilityIdentifier("HomescreenLayoutPicker")
                    if homescreenLayout == "Modern" {
                        Text("Navigation").font(.headline).foregroundStyle(.secondary)
                        BeebNavigationSegments(title: "Modern Navigation", options: ["Topbar", "Sidebar"], selection: $modernNavigation)
                            .frame(width: 700).accessibilityIdentifier("ModernNavigationPicker")
                    }
                }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 24))
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
            }.padding(60)
        }
    }
}

private struct RegionSettingLabel: View {
    let title: String
    let value: String
    var body: some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary); Image(systemName: "chevron.right") }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}
private struct RegionSelectionView: View {
    let title: String
    let choices: [RegionalChannelChoice]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title).font(.largeTitle).bold()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                    ForEach(choices) { choice in
                        Button {
                            selection = choice.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(choice.title); Spacer()
                                Image(systemName: selection == choice.id ? "checkmark.circle.fill" : "circle").opacity(selection == choice.id ? 1 : 0.3)
                            }.frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 14)
                        }.buttonStyle(OutlinedActionButtonStyle())
                    }
                }.padding(12)
            }
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
