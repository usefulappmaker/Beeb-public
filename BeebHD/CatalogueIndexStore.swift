// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@MainActor enum PlaybackActivity { static var active = false }

@MainActor final class CatalogueIndexStore: ObservableObject {
    @Published private(set) var snapshot = CatalogueIndexSnapshot() { didSet { searchRevision += 1 } }
    @Published private(set) var searchRevision = 0
    private let searchWorker = CatalogueSearchWorker()
    func search(_ query: String) async throws -> [CatalogueShow] {
        try await searchWorker.search(query, snapshot: snapshot, revision: searchRevision)
    }
    @Published private(set) var loading = false
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    @Published private(set) var refreshRevision = 0
    private let api: CatalogueIndexAPI
    private let cache: DiscoveryCache
    private var preparation: Task<Void, Never>?
    private var servicedRefresh = 0
    init(api: CatalogueIndexAPI = CatalogueIndexAPI(), cache: DiscoveryCache = DiscoveryCache()) {
        self.api = api; self.cache = cache
    }
    var uhd: [CatalogueShow] { CatalogueIndexSnapshot.sorted(snapshot.uhd) }
    func prepare() async {
        if let preparation { await preparation.value; return }
        let task = Task { [self] in
            var seedAliases = [String: String]()
            if let url = Bundle.main.url(forResource: "CatalogueSeed", withExtension: "plist"),
               let data = try? Data(contentsOf: url), let seed = try? PropertyListDecoder().decode(CatalogueIndexSnapshot.self, from: data), seed.schemaVersion == 1 { snapshot = seed; seedAliases = seed.episodeParents ?? [:] }
            if let saved = await cache.read(CatalogueIndexSnapshot.self, key: "catalogue-index-v1"), saved.schemaVersion == 1, !saved.catalogue.isEmpty { snapshot = saved }
            snapshot.episodeParents = seedAliases.merging(snapshot.episodeParents ?? [:], uniquingKeysWith: { _, saved in saved })
        }
        preparation = task
        await task.value
    }
    private func save() async {
        do { try await cache.write(snapshot, key: "catalogue-index-v1") }
        catch { self.error = "Catalogue updates could not be saved. The current results remain available until the app closes." }
    }
    /// Lightweight daily metadata refreshes; playback gets network priority.
    func requestRefresh() { refreshRevision += 1 }
    func maintain() async {
        await prepare()
        #if DEBUG
        if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] != nil { return }
        #endif
        while loading {
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
        }
        guard !Task.isCancelled else { return }
        let force = refreshRevision != servicedRefresh
        servicedRefresh = refreshRevision
        await refresh(force: force)
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 900_000_000_000) } catch { return }
            await refresh()
        }
    }
    func refresh(force: Bool = false) async {
        await prepare()
        guard !loading else { return }
        let now = Date()
        let pageDue = force || ((snapshot.uhdPageUpdatedAt.map { now.timeIntervalSince($0) >= 86_400 } ?? true) && (snapshot.uhdRetryAfter.map { $0 <= now } ?? true))
        let catalogueDue = (snapshot.catalogueUpdatedAt.map { now.timeIntervalSince($0) >= 86_400 } ?? true) && (snapshot.catalogueRetryAfter.map { $0 <= now } ?? true)
        guard pageDue || catalogueDue else { return }
        loading = true; error = nil
        defer { loading = false; status = "" }
        if pageDue {
            do {
                try await waitForPlayback()
                status = "Updating BBC UHD list…"
                let entries = try await api.uhdPage()
                try Task.checkCancellation()
                include(entries)
                snapshot.uhdPageUpdatedAt = Date(); snapshot.uhdRetryAfter = nil
                await save()
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                self.error = "Could not update BBC's UHD list. Saved programmes remain available."
                snapshot.uhdRetryAfter = Date().addingTimeInterval(3600)
                await save()
            }
        }
        if catalogueDue {
            do {
                try await waitForPlayback()
                let shows = try await api.allShows { [weak self] text in self?.status = text }
                try Task.checkCancellation()
                snapshot.catalogue = shows; snapshot.catalogueUpdatedAt = Date(); snapshot.catalogueRetryAfter = nil
                await save()
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                self.error = "Could not update programme search. Saved results remain available."
                snapshot.catalogueRetryAfter = Date().addingTimeInterval(3600)
                await save()
            }
        }
    }
    private func waitForPlayback() async throws {
        try Task.checkCancellation()
        while PlaybackActivity.active { try await Task.sleep(nanoseconds: 2_000_000_000) }
    }
    private func include(_ entries: [UHDPageEntry]) {
        let known = Dictionary((snapshot.catalogue + snapshot.uhd).map { ($0.id, $0) }, uniquingKeysWith: { _, recent in recent })
        var uhd = Dictionary(snapshot.uhd.map { ($0.id, $0) }, uniquingKeysWith: { _, recent in recent })
        for entry in entries {
            let id = snapshot.episodeParents?[entry.id] ?? entry.id
            var show = known[id] ?? CatalogueShow(id: id, title: entry.title, summary: "", image: nil, letter: "", channel: "BBC", categories: [], expectedEpisodes: 0, singleEpisode: entry.singleEpisode, episodes: [], indexedAt: nil)
            if known[id] == nil && entry.singleEpisode { show.discoveryEpisodeID = entry.id }
            show.uhdListed = true
            // The editorial page lists titles, not current per-episode counts.
            show.uhdEpisodeCount = nil
            uhd[id] = CatalogueIndexSnapshot.compact(show)
        }
        snapshot.uhd = CatalogueIndexSnapshot.sorted(Array(uhd.values))
    }
    /// Called after the user opens one programme; no extra availability requests.
    func record(_ show: CatalogueShow, replacingID: String) async {
        await prepare()
        guard show.indexedAt != nil else { return }
        if replacingID != show.id {
            var aliases = snapshot.episodeParents ?? [:]; aliases[replacingID] = show.id; snapshot.episodeParents = aliases
        }
        snapshot.uhd.removeAll { $0.id == show.id || $0.id == replacingID }
        let count = show.episodes.filter { $0.programme.uhdListed == true }.count
        if count > 0 {
            var compact = CatalogueIndexSnapshot.compact(show)
            compact.uhdListed = true; compact.uhdEpisodeCount = count
            snapshot.uhd.append(compact)
        }
        await save()
    }
}
