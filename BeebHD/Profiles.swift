// SPDX-License-Identifier: GPL-3.0-or-later
// Profiles and optional household sync.
//
// Profiles: each person gets their own Continue Watching and Saved list. Profiles are stored on the Apple TV and,
// when household sync is configured, shared between every Apple TV that uses the same sync server.
// Household sync: off until a server URL is entered in Settings. See docs/SYNC.md for the protocol and the
// reference servers (a Home Assistant AppDaemon app and a standalone Python server).
import Foundation
import UIKit
import Combine

struct BeebProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Kids mode: CBeebies/CBBC only, no programmes with BBC guidance warnings, Settings hidden.
    var kids: Bool = false
    var updatedAt: Date
}

/// Server address + key for household sync. Empty URL = sync off.
enum BeebSyncSettings {
    static let urlKey = "beebSyncURL"
    static let secretKey = "beebSyncKey"
    static var url: URL? {
        let raw = (UserDefaults.standard.string(forKey: urlKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    static var secret: String { UserDefaults.standard.string(forKey: secretKey) ?? "" }
    static var enabled: Bool { url != nil }
}

enum BeebSyncClient {
    /// POST one store (kind) for one profile and return the server's merged state, or nil if sync is off/failed.
    static func exchange(kind: String, profile: String, records: Any, removed: [String: Double], purge: Bool = false) async -> [String: Any]? {
        guard let url = BeebSyncSettings.url else { return nil }
        var payload: [String: Any] = ["kind": kind, "profile": profile, "records": records, "removed": removed]
        if purge { payload["purge"] = true }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BeebSyncSettings.secret, forHTTPHeaderField: "X-Beeb-Key")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return reply
    }
    /// For Settings › Test connection.
    static func test() async -> String {
        guard BeebSyncSettings.url != nil else { return "Enter a server URL first." }
        let reply = await exchange(kind: "profiles", profile: ProfileStore.householdID, records: [], removed: [:])
        guard let reply else { return "Couldn't reach the server, or the key was refused." }
        let count = (reply["records"] as? [Any])?.count ?? 0
        return "Connected. The server knows \(count) profile\(count == 1 ? "" : "s")."
    }
}

@MainActor final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    nonisolated static let changed = Notification.Name("beebProfileChanged")
    nonisolated static let householdID = "household"
    nonisolated static let defaultID = "main"
    nonisolated static let currentKey = "beebProfile"
    nonisolated static let startupKey = "beebProfileStartup"   // "last", "ask" or a profile id
    private static let listKey = "beebProfiles-v1"
    private static let removedKey = "beebProfilesRemoved-v1"

    @Published private(set) var profiles: [BeebProfile] = []
    @Published private(set) var current: String = defaultID
    @Published var startup: String { didSet { UserDefaults.standard.set(startup, forKey: Self.startupKey) } }
    @Published var pickerRequired = false
    /// Optional 4-digit PIN needed to switch from a kids profile to another profile (stored on this Apple TV).
    @Published var kidsPIN: String {
        didSet {
            UserDefaults.standard.set(kidsPIN, forKey: "beebKidsPIN")
            guard !adoptingPIN else { return }
            pinUpdatedAt = Date(); UserDefaults.standard.set(pinUpdatedAt, forKey: "beebKidsPINUpdated")
            scheduleSync()
        }
    }
    /// The PIN is shared by the household when sync is on (newest change wins).
    private var pinUpdatedAt: Date
    private var adoptingPIN = false
    private var removed: [String: Date] = [:]
    private var syncTask: Task<Void, Never>?

    /// The current profile id, for storage keys (safe to read from anywhere).
    nonisolated static var currentID: String { UserDefaults.standard.string(forKey: currentKey) ?? defaultID }

    private init() {
        let d = UserDefaults.standard
        startup = d.string(forKey: Self.startupKey) ?? "last"
        kidsPIN = d.string(forKey: "beebKidsPIN") ?? ""
        pinUpdatedAt = d.object(forKey: "beebKidsPINUpdated") as? Date ?? Date(timeIntervalSinceReferenceDate: 0)
        if let data = d.data(forKey: Self.listKey), let list = try? JSONDecoder().decode([BeebProfile].self, from: data) { profiles = list }
        if let data = d.data(forKey: Self.removedKey), let map = try? JSONDecoder().decode([String: Date].self, from: data) { removed = map }
        if profiles.isEmpty { profiles = [BeebProfile(id: Self.defaultID, name: "Me", updatedAt: Date(timeIntervalSinceReferenceDate: 0))]; saveList() }
        var id = d.string(forKey: Self.currentKey) ?? Self.defaultID
        if profiles.contains(where: { $0.id == startup }) { id = startup }   // "Always <name>" on launch
        if !profiles.contains(where: { $0.id == id }) { id = profiles[0].id }
        current = id; d.set(id, forKey: Self.currentKey)
        pickerRequired = startup == "ask" && profiles.count > 1
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() } }
        scheduleSync()
    }

    var currentProfile: BeebProfile { profiles.first { $0.id == current } ?? profiles[0] }
    var kidsMode: Bool { currentProfile.kids }
    /// True when switching to `id` must be confirmed with the kids PIN.
    func needsPIN(toSelect id: String) -> Bool {
        guard !kidsPIN.isEmpty, let target = profiles.first(where: { $0.id == id }), !target.kids else { return false }
        return kidsMode || pickerRequired
    }
    func setKids(_ id: String, _ kids: Bool) {
        guard let i = profiles.firstIndex(where: { $0.id == id }), profiles[i].kids != kids else { return }
        profiles[i].kids = kids; profiles[i].updatedAt = Date()
        saveList(); scheduleSync()
        if id == current { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }
    func name(_ id: String) -> String { profiles.first { $0.id == id }?.name ?? id }

    // MARK: switching and editing
    func select(_ id: String) {
        guard profiles.contains(where: { $0.id == id }), id != current else { return }
        current = id
        UserDefaults.standard.set(id, forKey: Self.currentKey)
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
    @discardableResult func add(_ name: String) -> BeebProfile? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let profile = BeebProfile(id: "p" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased(),
                                  name: String(clean.prefix(30)), updatedAt: Date())
        profiles.append(profile); saveList(); scheduleSync()
        return profile
    }
    func rename(_ id: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[i].name = String(clean.prefix(30)); profiles[i].updatedAt = Date()
        saveList(); scheduleSync()
    }
    /// Removes the profile, its local data and (with sync) its data on the server. The last profile can't be removed.
    func remove(_ id: String) {
        guard profiles.count > 1, profiles.contains(where: { $0.id == id }) else { return }
        profiles.removeAll { $0.id == id }
        removed[id] = Date()
        let d = UserDefaults.standard
        for key in ["continueWatching-v1-", "continueWatching-removed-v1-", "savedShows-v3-", "savedShows-meta-v1-"] { d.removeObject(forKey: key + id) }
        if startup == id { startup = "last" }
        if current == id { select(profiles[0].id) }
        saveList(); scheduleSync()
        Task { _ = await BeebSyncClient.exchange(kind: "history", profile: id, records: [], removed: [:], purge: true) }
    }

    // MARK: persistence + household sync of the profile list
    private func saveList() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(profiles), forKey: Self.listKey)
        d.set(try? JSONEncoder().encode(removed), forKey: Self.removedKey)
    }
    func scheduleSync() {
        guard BeebSyncSettings.enabled else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }
    private func sync() async {
        let encoder = JSONEncoder()
        guard let json = try? JSONSerialization.jsonObject(with: encoder.encode(profiles)),
              let reply = await BeebSyncClient.exchange(kind: "profiles", profile: Self.householdID, records: json,
                                                        removed: removed.mapValues { $0.timeIntervalSinceReferenceDate }) else { return }
        let decoder = JSONDecoder()
        var byID: [String: BeebProfile] = [:]
        for p in profiles { byID[p.id] = p }
        for item in reply["records"] as? [Any] ?? [] {
            guard let data = try? JSONSerialization.data(withJSONObject: item), let p = try? decoder.decode(BeebProfile.self, from: data) else { continue }
            if byID[p.id].map({ p.updatedAt > $0.updatedAt }) ?? true { byID[p.id] = p }
        }
        var gone = removed
        for (id, t) in reply["removed"] as? [String: Double] ?? [:] {
            let date = Date(timeIntervalSinceReferenceDate: t)
            if gone[id].map({ date > $0 }) ?? true { gone[id] = date }
        }
        for (id, t) in gone { if let p = byID[id] { if p.updatedAt > t { gone[id] = nil } else { byID[id] = nil } } }
        var merged = byID.values.sorted { ($0.id == Self.defaultID ? 0 : 1, $0.name) < ($1.id == Self.defaultID ? 0 : 1, $1.name) }
        if merged.isEmpty { merged = [BeebProfile(id: Self.defaultID, name: "Me", updatedAt: Date(timeIntervalSinceReferenceDate: 0))] }
        if merged != profiles || gone != removed {
            profiles = merged; removed = gone; saveList()
            if !profiles.contains(where: { $0.id == current }) { select(profiles[0].id) }
        }
        await syncSettings()
    }
    /// Household settings shared through the server (currently the kids PIN).
    private func syncSettings() async {
        let record: [String: Any] = ["id": "kidsPIN", "updatedAt": pinUpdatedAt.timeIntervalSinceReferenceDate, "value": kidsPIN]
        guard let reply = await BeebSyncClient.exchange(kind: "settings", profile: Self.householdID, records: [record], removed: [:]),
              let remote = (reply["records"] as? [[String: Any]])?.first(where: { $0["id"] as? String == "kidsPIN" }),
              let t = remote["updatedAt"] as? Double, t > pinUpdatedAt.timeIntervalSinceReferenceDate else { return }
        adoptingPIN = true
        kidsPIN = remote["value"] as? String ?? ""
        adoptingPIN = false
        pinUpdatedAt = Date(timeIntervalSinceReferenceDate: t)
        UserDefaults.standard.set(pinUpdatedAt, forKey: "beebKidsPINUpdated")
    }

    /// One-off: data saved before profiles existed belongs to the default profile.
    nonisolated static func migrateLegacy(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: "beebProfilesMigrated") else { return }
        for (old, new) in [("continueWatching-v1", "continueWatching-v1-" + defaultID),
                           ("continueWatching-removed-v1", "continueWatching-removed-v1-" + defaultID),
                           ("savedShows-v3", "savedShows-v3-" + defaultID)] {
            if defaults.data(forKey: new) == nil, let data = defaults.data(forKey: old) { defaults.set(data, forKey: new) }
        }
        defaults.set(true, forKey: "beebProfilesMigrated")
    }
}
