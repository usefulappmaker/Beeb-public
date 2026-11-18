// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Combine

@MainActor final class Library: ObservableObject {
    @Published var saved: [CatalogueShow] = []
    @Published var migrationWarning: String?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ProfileStore.migrateLegacy(defaults)   // Household sync: per-profile Saved + sync
        loadLocal()
        startSync()
    }
    private static var savedKey: String { "savedShows-v3-" + ProfileStore.currentID }
    private static var metaKey: String { "savedShows-meta-v1-" + ProfileStore.currentID }
    private var savedAt: [String: Date] = [:]
    private var removedAt: [String: Date] = [:]
    private var syncTask: Task<Void, Never>?
    private var lastSync = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private func loadLocal() {
        saved = []; savedAt = [:]; removedAt = [:]
        if let data = defaults.data(forKey: Self.savedKey), let shows = try? JSONDecoder().decode([CatalogueShow].self, from: data) { saved = shows }
        if let data = defaults.data(forKey: Self.metaKey),
           let meta = try? JSONDecoder().decode([String: [String: Date]].self, from: data) {
            savedAt = meta["added"] ?? [:]; removedAt = meta["removed"] ?? [:]
        }
    }
    private func saveMeta() {
        if let data = try? JSONEncoder().encode(["added": savedAt, "removed": removedAt]) { defaults.set(data, forKey: Self.metaKey) }
    }
    private func startSync() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AppLifecycle.willEnterForeground, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync(now: true) } })
        observers.append(nc.addObserver(forName: ProfileStore.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.loadLocal(); self?.scheduleSync(now: true) } })
        scheduleSync(now: true)
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self else { return }
                if AppLifecycle.isActive, Date().timeIntervalSince(self.lastSync) > 55 {
                    self.scheduleSync(now: true)
                }
            }
        }
    }
    private func scheduleSync(now: Bool = false) {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            if !now { try? await Task.sleep(nanoseconds: 2_000_000_000) }
            guard !Task.isCancelled else { return }
            await self?.sync()
            self?.syncTask = nil
        }
    }
    private func sync() async {
        lastSync = Date()
        let profile = ProfileStore.currentID
        let encoder = JSONEncoder()
        let records: [[String: Any]] = saved.compactMap { show in
            guard let data = try? encoder.encode(show), let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return ["id": show.id, "updatedAt": (savedAt[show.id] ?? Date(timeIntervalSinceReferenceDate: 0)).timeIntervalSinceReferenceDate, "show": json]
        }
        guard let reply = await BeebSyncClient.exchange(kind: "saved", profile: profile, records: records,
                                                        removed: removedAt.mapValues { $0.timeIntervalSinceReferenceDate }),
              profile == ProfileStore.currentID else { return }
        adopt(reply)
    }
    /// Merge the server's Saved list with local changes made while the request was in flight.
    private func adopt(_ reply: [String: Any]) {
        let decoder = JSONDecoder()
        var shows: [String: (CatalogueShow, Date)] = [:]
        for show in saved { shows[show.id] = (show, savedAt[show.id] ?? Date(timeIntervalSinceReferenceDate: 0)) }
        for item in reply["records"] as? [[String: Any]] ?? [] {
            guard let json = item["show"], let data = try? JSONSerialization.data(withJSONObject: json),
                  let show = try? decoder.decode(CatalogueShow.self, from: data) else { continue }
            let t = Date(timeIntervalSinceReferenceDate: item["updatedAt"] as? Double ?? 0)
            if shows[show.id].map({ t > $0.1 }) ?? true { shows[show.id] = (show, t) }
        }
        var gone = removedAt
        for (id, t) in reply["removed"] as? [String: Double] ?? [:] {
            let date = Date(timeIntervalSinceReferenceDate: t)
            if gone[id].map({ date > $0 }) ?? true { gone[id] = date }
        }
        for (id, t) in gone {
            if let entry = shows[id] { if entry.1 > t { gone[id] = nil } else { shows[id] = nil } }
        }
        let merged = shows.values.sorted { $0.1 > $1.1 }
        let newSaved = merged.map { $0.0 }
        let newAt = Dictionary(uniqueKeysWithValues: merged.map { ($0.0.id, $0.1) })
        if newSaved.map(\.id) != saved.map(\.id) || newAt != savedAt || gone != removedAt {
            saved = newSaved; savedAt = newAt; removedAt = gone
            defaults.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
            saveMeta()
        }
    }
    func contains(_ show: CatalogueShow) -> Bool { saved.contains { $0.id == show.id } }
    func save(_ show: CatalogueShow) {
        var compact = show; compact.episodes = []; compact.indexedAt = nil
        saved.removeAll { $0.id == show.id }; saved.insert(compact, at: 0)
        savedAt[show.id] = Date(); removedAt[show.id] = nil; saveMeta()   // Household sync
        persist()
    }
    func remove(_ show: CatalogueShow) {
        saved.removeAll { $0.id == show.id }
        removedAt[show.id] = Date(); savedAt[show.id] = nil; saveMeta()   // Household sync
        persist()
    }
    func toggle(_ show: CatalogueShow) { if contains(show) { remove(show) } else { save(show) } }
    func refreshArtwork() async {
        // Refresh only saved programmes when Saved is opened; no episode/catalogue crawl.
        for id in saved.map(\.id) {
            guard !Task.isCancelled else { return }
            if let fresh = try? await DiscoveryAPI().show(id), !Task.isCancelled,
               let index = saved.firstIndex(where: { $0.id == id }) {
                saved[index].image = fresh.image; persist()
            }
        }
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey); scheduleSync() }   // Household sync
    func migrate(resolve: (Programme) async throws -> CatalogueShow = { try await DiscoveryAPI().parent(of: $0) }) async {
        guard let data = defaults.data(forKey: "saved"), let episodes = try? JSONDecoder().decode([Programme].self, from: data) else { return }
        var unresolved = [Programme]()
        for episode in episodes {
            do { let parent = try await resolve(episode); if !contains(parent) { save(parent) } }
            catch { unresolved.append(episode) }
        }
        if unresolved.isEmpty { defaults.removeObject(forKey: "saved"); migrationWarning = nil }
        else { defaults.set(try? JSONEncoder().encode(unresolved), forKey: "saved"); migrationWarning = "\(unresolved.count) older saved episodes could not yet be converted to programmes. They will be retried next time." }
    }
}
