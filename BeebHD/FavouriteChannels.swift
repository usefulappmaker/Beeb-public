// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Combine
#if os(tvOS)
import TVServices
#endif

/// Each profile's favourite live channels, in the order they chose. Favourites lead the channel strip, the guide
/// and the Top Shelf's live row. Synced like Saved (kind "channels"): per channel the newest change wins, and
/// a reorder stamps every position so the whole order travels together.
@MainActor final class FavouriteChannels: ObservableObject {
    static let shared = FavouriteChannels()
    @Published private(set) var ids: [String] = []
    private let defaults: UserDefaults
    private var changedAt: [String: Date] = [:]
    private var removedAt: [String: Date] = [:]
    private var syncTask: Task<Void, Never>?
    private var lastSync = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    private struct Stored: Codable { var ids: [String]; var changed: [String: Date]; var removed: [String: Date] }
    private static var key: String { "favouriteChannels-v1-" + ProfileStore.currentID }
    static let limit = 60

    init(defaults: UserDefaults = .standard, sync: Bool = true) {
        self.defaults = defaults
        loadLocal()
        if sync { startSync() }
    }
    func contains(_ id: String) -> Bool { ids.contains(Self.canonical(id)) }
    func toggle(_ id: String) { contains(id) ? remove(id) : add(id) }
    func add(_ id: String) {
        let id = Self.canonical(id)
        guard !ids.contains(id), ids.count < Self.limit else { return }
        ids.append(id); changedAt[id] = Date(); removedAt[id] = nil
        persist()
    }
    func remove(_ id: String) {
        let id = Self.canonical(id)
        guard ids.contains(id) else { return }
        ids.removeAll { $0 == id }; changedAt[id] = nil; removedAt[id] = Date()
        persist()
    }
    /// Moves a favourite one place up (-1) or down (+1).
    func move(_ id: String, by step: Int) {
        let id = Self.canonical(id)
        guard let from = ids.firstIndex(of: id) else { return }
        let to = max(0, min(ids.count - 1, from + step))
        guard to != from else { return }
        ids.remove(at: from); ids.insert(id, at: to)
        let now = Date()
        for id in ids { changedAt[id] = now }   // the whole order wins together
        persist()
    }
    /// Channels in favourite order first, then the rest as given.
    func ordered<T>(_ items: [T], id: (T) -> String) -> [T] {
        let rank = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        return items.enumerated().sorted { a, b in
            let ra = rank[Self.canonical(id(a.element))] ?? Int.max, rb = rank[Self.canonical(id(b.element))] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
    /// Regional BBC One/Two variants count as the same channel.
    static func canonical(_ id: String) -> String {
        if id.hasPrefix("bbc_one_") { return "bbc_one_london" }
        if id.hasPrefix("bbc_two_") { return "bbc_two_england" }
        return id
    }

    // MARK: Storage and sync
    private func loadLocal() {
        ids = []; changedAt = [:]; removedAt = [:]
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            ids = stored.ids; changedAt = stored.changed; removedAt = stored.removed
        }
        publishToTopShelf()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(Stored(ids: ids, changed: changedAt, removed: removedAt)) { defaults.set(data, forKey: Self.key) }
        publishToTopShelf()
        scheduleSync()
    }
    private func publishToTopShelf() {
        var snapshot = TopShelfShared.snapshot()
        guard snapshot.favouriteChannels ?? [] != ids else { return }
        snapshot.favouriteChannels = ids
        #if os(tvOS)
        if TopShelfShared.write(snapshot) { TVTopShelfContentProvider.topShelfContentDidChange() }
        #else
        TopShelfShared.write(snapshot)
        #endif
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
                if AppLifecycle.isActive, Date().timeIntervalSince(self.lastSync) > 55 { self.scheduleSync(now: true) }
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
        let records: [[String: Any]] = ids.enumerated().map { index, id in
            ["id": id, "position": index, "updatedAt": (changedAt[id] ?? Date(timeIntervalSinceReferenceDate: 0)).timeIntervalSinceReferenceDate]
        }
        guard let reply = await BeebSyncClient.exchange(kind: "channels", profile: profile, records: records,
                                                        removed: removedAt.mapValues { $0.timeIntervalSinceReferenceDate }),
              profile == ProfileStore.currentID else { return }
        adopt(reply)
    }
    /// Merge the server's favourites with local changes made while the request was in flight.
    func adopt(_ reply: [String: Any]) {
        var entries: [String: (position: Int, at: Date)] = [:]
        for (index, id) in ids.enumerated() { entries[id] = (index, changedAt[id] ?? Date(timeIntervalSinceReferenceDate: 0)) }
        for item in reply["records"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String, !id.isEmpty else { continue }
            let at = Date(timeIntervalSinceReferenceDate: item["updatedAt"] as? Double ?? 0)
            if entries[id].map({ at > $0.at }) ?? true { entries[id] = (item["position"] as? Int ?? Int.max, at) }
        }
        var gone = removedAt
        for (id, t) in reply["removed"] as? [String: Double] ?? [:] {
            let date = Date(timeIntervalSinceReferenceDate: t)
            if gone[id].map({ date > $0 }) ?? true { gone[id] = date }
        }
        for (id, t) in gone {
            if let entry = entries[id] { if entry.at > t { gone[id] = nil } else { entries[id] = nil } }
        }
        let merged = entries.sorted { ($0.value.position, $0.value.at, $0.key) < ($1.value.position, $1.value.at, $1.key) }
        let newIDs = Array(merged.map(\.key).prefix(Self.limit))
        let newAt = Dictionary(uniqueKeysWithValues: merged.map { ($0.key, $0.value.at) })
        if newIDs != ids || newAt != changedAt || gone != removedAt {
            ids = newIDs; changedAt = newAt; removedAt = gone
            if let data = try? JSONEncoder().encode(Stored(ids: ids, changed: changedAt, removed: removedAt)) { defaults.set(data, forKey: Self.key) }
            publishToTopShelf()
        }
    }
}
