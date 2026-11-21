// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Combine

struct WatchRecord: Codable, Identifiable {
    let id: String
    var episode: CatalogueEpisode
    var show: CatalogueShow?
    var nextEpisode: CatalogueEpisode?
    var position: Double
    var duration: Double
    var completed: Bool
    var updatedAt: Date
    var target: Programme? { completed ? nextEpisode?.programme : episode.programme }
    var fraction: Double { min(1, max(0, position / max(1, duration))) }
    var remainingMinutes: Int { max(1, Int(ceil((duration - position) / 60))) }
}

/// How far one episode has been watched, so programme pages can mark watched and part-watched episodes.
/// Completion is sticky: rewatching the start of a finished episode doesn't un-mark it (Mark unwatched does).
struct EpisodeProgress: Codable, Equatable {
    var position: Double
    var duration: Double
    var completed: Bool
    var updatedAt: Date
    var fraction: Double { min(1, max(0, position / max(1, duration))) }
}

enum EpisodeSequence {
    private static func number(_ text: String, pattern: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
    private static func season(_ episode: CatalogueEpisode) -> Int? {
        number(episode.seriesTitle + " " + episode.subtitle, pattern: "\\b(?:series|season)\\s+(\\d+)\\b")
    }
    private static func position(_ episode: CatalogueEpisode) -> Int? {
        if let value = episode.parentPosition, value > 0 { return value }
        let subtitle = episode.subtitle.components(separatedBy: ": ").last ?? episode.subtitle
        return number(subtitle, pattern: "^\\s*(?:episode\\s+)?(\\d+)(?:[.:]\\s*|\\s+|$)")
    }
    private static func date(_ episode: CatalogueEpisode) -> Date? {
        guard let value = episode.broadcastDate else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    /// BBC pages may arrive newest-first. Use explicit episode positions, then dates,
    /// and preserve source order when no comparable ordering metadata is supplied.
    static func ordered(_ episodes: [CatalogueEpisode]) -> [CatalogueEpisode] {
        episodes.enumerated().sorted { left, right in
            let a = left.element, b = right.element
            let sa = season(a) ?? Int.max, sb = season(b) ?? Int.max
            if sa != sb { return sa < sb }
            let pa = position(a) ?? Int.max, pb = position(b) ?? Int.max
            if pa != pb { return pa < pb }
            let da = date(a) ?? .distantFuture, db = date(b) ?? .distantFuture
            if da != db { return da < db }
            return left.offset < right.offset
        }.map(\.element)
    }
    static func orderedSeries(_ series: [CatalogueSeries]) -> [CatalogueSeries] {
        series.enumerated().sorted { left, right in
            if let a = left.element.episodes.first.flatMap(season), let b = right.element.episodes.first.flatMap(season), a != b { return a < b }
            return left.offset < right.offset
        }.map(\.element)
    }
    static func next(after current: CatalogueEpisode, in show: CatalogueShow) -> CatalogueEpisode? {
        let candidates = show.episodes.filter { $0.id != current.id }
        if let order = position(current) {
            if let series = season(current) {
                // Sort by BBC episode position and explicit series number, rather
                // than assuming the API is oldest-first (some shows are reversed).
                let numbered = candidates.compactMap { episode -> (CatalogueEpisode, Int, Int)? in
                    guard let s = season(episode), let p = position(episode), s > series || (s == series && p > order) else { return nil }
                    return (episode, s, p)
                }
                if let next = numbered.min(by: { ($0.1, $0.2) < ($1.1, $1.2) }) { return next.0 }
            } else {
                let sameSeries = candidates.filter { $0.sliceID == current.sliceID && position($0).map { $0 > order } == true }
                if let next = sameSeries.min(by: { position($0)! < position($1)! }) { return next }
            }
        }
        if let released = date(current) {
            return candidates.filter { date($0).map { $0 > released } == true }
                .min { date($0)! < date($1)! }
        }
        // Without ordering metadata, leave the programme available to browse
        // rather than guessing that a reversed API list is chronological.
        return nil
    }
}

@MainActor final class WatchHistory: ObservableObject {
    @Published private(set) var records: [WatchRecord] = []
    @Published private(set) var warning: String?
    private let defaults: UserDefaults
    // Household sync: per-profile storage + sync state
    private static var key: String { "continueWatching-v1-" + ProfileStore.currentID }
    private static var removedKey: String { "continueWatching-removed-v1-" + ProfileStore.currentID }
    private var removed: [String: Date] = [:]
    /// Per-episode progress (Continue Watching keeps one record per programme, so earlier episodes would be forgotten).
    @Published private(set) var episodes: [String: EpisodeProgress] = [:]
    private var episodesRemoved: [String: Date] = [:]
    private static var episodesKey: String { "episodeProgress-v1-" + ProfileStore.currentID }
    private static var episodesRemovedKey: String { "episodeProgress-removed-v1-" + ProfileStore.currentID }
    static let episodeLimit = 600
    private var syncTask: Task<Void, Never>?
    private var lastSync = Date.distantPast
    private var observers: [NSObjectProtocol] = []
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ProfileStore.migrateLegacy(defaults)   // Household sync
        loadLocal()
        startHASync()
    }
    private func loadLocal() {
        records = []; removed = [:]
        if let data = defaults.data(forKey: Self.key) {
            do {
                records = try JSONDecoder().decode([WatchRecord].self, from: data)
                    .filter { $0.position.isFinite && $0.duration.isFinite && $0.position >= 0 && $0.duration > 0 }
                    .sorted { $0.updatedAt > $1.updatedAt }
            } catch { warning = "Viewing history could not be read. New progress can still be saved." }
        }
        if let data = defaults.data(forKey: Self.removedKey),
           let saved = try? JSONDecoder().decode([String: Date].self, from: data) { removed = saved }
        episodes = [:]; episodesRemoved = [:]
        if let data = defaults.data(forKey: Self.episodesKey),
           let saved = try? JSONDecoder().decode([String: EpisodeProgress].self, from: data) { episodes = saved.filter { $0.value.duration > 0 } }
        if let data = defaults.data(forKey: Self.episodesRemovedKey),
           let saved = try? JSONDecoder().decode([String: Date].self, from: data) { episodesRemoved = saved }
    }
    func progress(for episodeID: String) -> EpisodeProgress? { episodes[episodeID] }
    /// Mark watched / Mark unwatched on the episode screen. Unwatched forgets the episode's progress.
    func setWatched(_ episodeID: String, _ watched: Bool, now: Date = Date()) {
        if watched {
            var value = episodes[episodeID] ?? EpisodeProgress(position: 1, duration: 1, completed: true, updatedAt: now)
            value.completed = true; value.position = value.duration; value.updatedAt = now
            episodes[episodeID] = value; episodesRemoved[episodeID] = nil
        } else {
            episodes[episodeID] = nil; episodesRemoved[episodeID] = now
        }
        persistEpisodes()
    }
    private func recordEpisode(_ id: String, position: Double, duration: Double, completed: Bool, now: Date) {
        var value = episodes[id] ?? EpisodeProgress(position: 0, duration: duration, completed: false, updatedAt: now)
        if abs(value.position - position) < 0.5, value.duration == duration, value.completed || !completed { return }
        value.position = min(position, duration); value.duration = duration
        value.completed = value.completed || completed; value.updatedAt = now
        episodes[id] = value; episodesRemoved[id] = nil
        if episodes.count > Self.episodeLimit {
            for key in episodes.sorted(by: { $0.value.updatedAt < $1.value.updatedAt }).prefix(episodes.count - Self.episodeLimit).map(\.key) { episodes[key] = nil }
        }
        persistEpisodes()
    }
    private func persistEpisodes() {
        if let data = try? JSONEncoder().encode(episodes) { defaults.set(data, forKey: Self.episodesKey) }
        if let data = try? JSONEncoder().encode(episodesRemoved) { defaults.set(data, forKey: Self.episodesRemovedKey) }
        scheduleHASync()
    }
    static func isComplete(position: Double, duration: Double, ended: Bool = false) -> Bool {
        guard position.isFinite, duration.isFinite, duration > 0 else { return false }
        return ended || (position / duration >= 0.95 && duration - position <= 120)
    }
    func resumePosition(for episodeID: String) -> Double {
        guard let record = records.first(where: { $0.episode.id == episodeID }), !record.completed else { return 0 }
        return record.position
    }
    func update(episode: CatalogueEpisode, show: CatalogueShow?, next: CatalogueEpisode?, position: Double, duration: Double, ended: Bool = false, now: Date = Date()) {
        guard position.isFinite, duration.isFinite, duration > 0, position >= 0, position >= 5 || ended else { return }
        let id = show?.id ?? episode.programme.showID ?? episode.id
        let completed = Self.isComplete(position: position, duration: duration, ended: ended)
        recordEpisode(episode.id, position: position, duration: duration, completed: completed, now: now)
        if let old = records.first(where: { $0.id == id }), old.episode.id == episode.id,
           abs(old.position - position) < 0.5, old.completed == completed { return }
        var compact = show
        compact?.episodes = []; compact?.indexedAt = nil
        let oldNext = records.first { $0.id == id && $0.episode.id == episode.id }?.nextEpisode
        let record = WatchRecord(id: id, episode: episode, show: compact, nextEpisode: next ?? oldNext,
                                 position: min(position, duration), duration: duration, completed: completed, updatedAt: now)
        records.removeAll { $0.id == id }; records.insert(record, at: 0)
        records = Array(records.prefix(40)); persist()
    }
    func remove(_ id: String) {
        records.removeAll { $0.id == id }
        removed[id] = Date(); saveRemoved()   // Household sync
        persist()
    }
    private func persist() {
        do { defaults.set(try JSONEncoder().encode(records), forKey: Self.key); warning = nil }
        catch { warning = "Viewing progress could not be saved." }
        scheduleHASync()   // Household sync
    }

    // MARK: - Household sync (optional household sync)
    private func saveRemoved() {
        if let data = try? JSONEncoder().encode(removed) { defaults.set(data, forKey: Self.removedKey) }
    }
    private func startHASync() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AppLifecycle.willEnterForeground, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleHASync(now: true) } })
        observers.append(nc.addObserver(forName: AppLifecycle.didEnterBackground, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleHASync(now: true) } })
        observers.append(nc.addObserver(forName: ProfileStore.changed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.loadLocal(); self?.scheduleHASync(now: true) } })
        scheduleHASync(now: true)
        // Pick up the other Apple TV's progress while Beeb sits open: check once a minute while on screen.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self else { return }
                if AppLifecycle.isActive, Date().timeIntervalSince(self.lastSync) > 55 {
                    self.scheduleHASync(now: true)
                }
            }
        }
    }
    /// Debounced: 3 s after the last change, but at least every 30 s while changes keep coming (playback).
    private func scheduleHASync(now: Bool = false) {
        let overdue = Date().timeIntervalSince(lastSync) > 30
        if overdue, syncTask != nil, !now { return }
        syncTask?.cancel()
        let delay: UInt64 = (now || overdue) ? 0 : 3_000_000_000
        syncTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            guard !Task.isCancelled else { return }
            await self?.haSync()
            self?.syncTask = nil
        }
    }
    private func haSync() async {
        lastSync = Date()
        let profile = ProfileStore.currentID
        guard let recordsJSON = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(records)),
              let reply = await BeebSyncClient.exchange(kind: "history", profile: profile, records: recordsJSON,
                                                        removed: removed.mapValues { $0.timeIntervalSinceReferenceDate }),
              profile == ProfileStore.currentID else { return }   // ignore a reply for a profile we've switched away from
        adopt(reply)
        let episodeRecords: [[String: Any]] = episodes.map { id, value in
            ["id": id, "position": value.position, "duration": value.duration, "completed": value.completed,
             "updatedAt": value.updatedAt.timeIntervalSinceReferenceDate]
        }
        guard let episodeReply = await BeebSyncClient.exchange(kind: "episodes", profile: profile, records: episodeRecords,
                                                               removed: episodesRemoved.mapValues { $0.timeIntervalSinceReferenceDate }),
              profile == ProfileStore.currentID else { return }
        adoptEpisodes(episodeReply)
    }
    /// Per episode the newest change wins; Mark unwatched (a removal) wins over progress that isn't newer.
    func adoptEpisodes(_ reply: [String: Any]) {
        var merged = episodes
        for item in reply["records"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String, let duration = item["duration"] as? Double, duration > 0, duration.isFinite,
                  let position = item["position"] as? Double, position.isFinite else { continue }
            let value = EpisodeProgress(position: max(0, min(position, duration)), duration: duration,
                                        completed: item["completed"] as? Bool ?? false,
                                        updatedAt: Date(timeIntervalSinceReferenceDate: item["updatedAt"] as? Double ?? 0))
            if merged[id].map({ value.updatedAt > $0.updatedAt }) ?? true { merged[id] = value }
        }
        var gone = episodesRemoved
        for (id, t) in reply["removed"] as? [String: Double] ?? [:] {
            let date = Date(timeIntervalSinceReferenceDate: t)
            if gone[id].map({ date > $0 }) ?? true { gone[id] = date }
        }
        for (id, t) in gone {
            if let value = merged[id] { if value.updatedAt > t { gone[id] = nil } else { merged[id] = nil } }
        }
        if merged.count > Self.episodeLimit {
            for key in merged.sorted(by: { $0.value.updatedAt < $1.value.updatedAt }).prefix(merged.count - Self.episodeLimit).map(\.key) { merged[key] = nil }
        }
        if merged != episodes || gone != episodesRemoved {
            episodes = merged; episodesRemoved = gone
            if let data = try? JSONEncoder().encode(episodes) { defaults.set(data, forKey: Self.episodesKey) }
            if let data = try? JSONEncoder().encode(episodesRemoved) { defaults.set(data, forKey: Self.episodesRemovedKey) }
        }
    }
    /// Merge the server's state with whatever changed locally while the request was in flight.
    private func adopt(_ reply: [String: Any]) {
        let decoder = JSONDecoder()
        let incoming: [WatchRecord] = (reply["records"] as? [Any] ?? []).compactMap { item in
            guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? decoder.decode(WatchRecord.self, from: data)
        }.filter { $0.position.isFinite && $0.duration.isFinite && $0.position >= 0 && $0.duration > 0 }
        var gone = removed
        for (id, t) in reply["removed"] as? [String: Double] ?? [:] {
            let date = Date(timeIntervalSinceReferenceDate: t)
            if gone[id].map({ date > $0 }) ?? true { gone[id] = date }
        }
        var byID: [String: WatchRecord] = [:]
        for record in records + incoming where byID[record.id].map({ record.updatedAt > $0.updatedAt }) ?? true {
            byID[record.id] = record
        }
        for (id, t) in gone {
            if let record = byID[id] { if record.updatedAt > t { gone[id] = nil } else { byID[id] = nil } }
        }
        let merged = Array(byID.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(40))
        let encoder = JSONEncoder()
        if (try? encoder.encode(merged)) != (try? encoder.encode(records)) {
            records = merged
            if let data = try? encoder.encode(records) { defaults.set(data, forKey: Self.key) }
        }
        if gone != removed { removed = gone; saveRemoved() }
    }
}
