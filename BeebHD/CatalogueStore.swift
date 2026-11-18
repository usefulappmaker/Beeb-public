// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@MainActor final class CatalogueStore: ObservableObject {
    @Published var home: HomeFeed?
    @Published var genres: [Genre] = []
    @Published var loading = false
    @Published var error: String?
    @Published var storageWarning: String?
    var programmeOpened: ((CatalogueShow, String) -> Void)?
    private let discovery: DiscoveryAPI
    private let catalogue: CatalogueAPI
    private let cache: DiscoveryCache
    private var started = false
    private var details: [String: CatalogueShow] = [:]
    private var recent = [String]()
    init(discovery: DiscoveryAPI = DiscoveryAPI(), catalogue: CatalogueAPI = CatalogueAPI(), cache: DiscoveryCache = DiscoveryCache()) {
        self.discovery = discovery; self.catalogue = catalogue; self.cache = cache
    }
    func boot() async {
        guard !started else { return }; started = true
        #if DEBUG
        if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] != nil { loadUIFixture(); return }
        #endif
        home = await cache.read(HomeFeed.self, key: "homepage")
        genres = await cache.read([Genre].self, key: "genres") ?? []
        await refreshHome()
    }
    func refreshHome() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] != nil { loadUIFixture(); return }
        #endif
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        details.removeAll(); recent.removeAll()
        do {
            async let feed = discovery.homepage()
            async let categories = discovery.genres()
            home = try await feed
            do { try await cache.write(home!, key: "homepage") } catch { storageWarning = "Homepage could not be saved for offline browsing." }
            genres = try await categories
            try? await cache.write(genres, key: "genres")
        } catch { if !Task.isCancelled { self.error = "Could not refresh discovery. \(error.localizedDescription)" } }
    }
    #if DEBUG
    /// Offline fixtures exercise layout/focus without depending on BBC availability.
    private func loadUIFixture() {
        if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "review" {
            let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("review-homepage.html")
            if let data = try? Data(contentsOf: path), let feed = try? DiscoveryAPI.home(data) { home = feed; return }
        }
        let titles = ["The Reluctant Vampire", "Blue Lights", "The Americas", "Asia", "A much longer programme title on two lines", "Wild Isles", "Doctor Who", "The Capture"]
        let shows = titles.enumerated().map { index, title in
            CatalogueShow(id: "preview-\(index)", title: title, summary: "Discover the latest programmes on Beeb.", image: URL(string: "http://127.0.0.1:18745/\(index % 2 == 0 ? "wide.png" : "portrait.png")"), letter: "a", channel: "BBC", categories: [], expectedEpisodes: index % 2 == 0 ? 8 : 0, singleEpisode: false, episodes: [], indexedAt: nil, uhdListed: index % 2 == 0)
        }
        let features = shows.map { HomeFeature(show: $0, headline: $0.title, synopsis: $0.summary, image: $0.image) }
        home = HomeFeed(features: ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "cards" ? [] : features, rows: [HomeRow(id: "preview", title: "New & Trending", shows: shows)])
    }
    #endif

    func open(_ show: CatalogueShow) async throws -> CatalogueShow {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "programme" { return show }
        #endif
        if let loaded = details[show.id] { programmeOpened?(loaded, show.id); return loaded }
        let old = await cache.read(CatalogueShow.self, key: "show-" + show.id)
        do {
            let metadata: CatalogueShow
            if let episodeID = show.discoveryEpisodeID {
                metadata = try await discovery.parent(of: Programme(id: episodeID, title: show.title, summary: "", image: nil, version: "", guidance: nil))
            } else { metadata = try await discovery.show(show.id) }
            let updated = try await catalogue.details(metadata)
            details[show.id] = updated; recent.removeAll { $0 == show.id }; recent.append(show.id)
            while recent.count > 12 { details.removeValue(forKey: recent.removeFirst()) }
            try? await cache.write(updated, key: "show-" + show.id)
            programmeOpened?(updated, show.id)
            return updated
        } catch { if !Task.isCancelled, let old { return old }; throw error }
    }
}
struct PageSnapshot: Codable { let shows: [CatalogueShow]; let page: Int; let totalPages: Int; let count: Int }
@MainActor final class PageStore: ObservableObject {
    @Published var shows: [CatalogueShow] = []
    @Published var page = 1
    @Published var totalPages = 1
    @Published var count = 0
    @Published var loading = false
    @Published var error: String?
    private var requestID = UUID()
    let api: DiscoveryAPI
    let cache: DiscoveryCache
    init(api: DiscoveryAPI = DiscoveryAPI(), cache: DiscoveryCache = DiscoveryCache()) { self.api = api; self.cache = cache }
    func load(category: String? = nil, letter: String? = nil, page: Int) async {
        let id = UUID(); requestID = id; loading = true; error = nil; shows = []
        defer { if requestID == id { loading = false } }
        let key = "page-\(category ?? letter ?? "none")-\(page)"
        let cached = await cache.read(PageSnapshot.self, key: key)
        if let cached, requestID == id {
            shows = cached.shows; self.page = cached.page; totalPages = cached.totalPages; count = cached.count
        }
        do {
            let result = try await api.page(category: category, letter: letter, page: page)
            try Task.checkCancellation(); guard requestID == id else { return }
            self.page = result.page; count = result.total; totalPages = max(1, Int(ceil(Double(result.total) / Double(result.perPage))))
            shows = result.shows
            try? await cache.write(PageSnapshot(shows: shows, page: self.page, totalPages: totalPages, count: count), key: key)
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            if let cached { shows = cached.shows }
            self.error = error.localizedDescription
        }
    }
}

@MainActor final class ContinuousCatalogueStore: ObservableObject {
    @Published var shows: [CatalogueShow] = []
    @Published var count = 0
    @Published var loading = false
    @Published var error: String?
    private let api: DiscoveryAPI
    init(api: DiscoveryAPI = DiscoveryAPI()) { self.api = api }
    private var page = 0
    var hasMore: Bool { page == 0 || shows.count < count }
    func next(category: String?, letter: String?) async {
        guard !loading, hasMore else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await api.page(category: category, letter: letter, page: page + 1)
            try Task.checkCancellation()
            guard result.page == page+1 else {throw BBCError.message("The catalogue could not continue. Please retry.")}
            let existing = Set(shows.map(\.id));let added = result.shows.filter {!existing.contains($0.id)}
            guard !added.isEmpty || result.total == 0 else {throw BBCError.message("No further programmes were returned. Please retry.")}
            shows += added; count = result.total; page = result.page
        } catch {if !Task.isCancelled {self.error = error.localizedDescription}}
    }
}
