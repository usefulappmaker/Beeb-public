// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// What the Top Shelf shows when Beeb is in the top row of the Home Screen.
enum TopShelfSource: String, CaseIterable {
    case live = "Live TV", continueWatching = "Continue Watching", saved = "Saved", mix = "Mix"
    static let fallback = TopShelfSource.live
}

struct TopShelfEntry: Codable, Hashable {
    let id: String
    let title: String
    var subtitle: String?
    var image: URL?
    let displayURL: URL
    let playURL: URL
    var progress: Double?
}

struct TopShelfSnapshot: Codable, Equatable {
    var continueWatching: [TopShelfEntry] = []
    var saved: [TopShelfEntry] = []
}

/// The app writes a small snapshot of Saved and Continue Watching into the shared
/// App Group so the Top Shelf extension can show them without loading the app.
enum TopShelfShared {
    static let sourceKey = "topShelfSource"
    private static let snapshotKey = "topShelfSnapshot-v1"
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "BeebAppGroup") as? String }
    static var defaults: UserDefaults? { groupID.flatMap { UserDefaults(suiteName: $0) } }
    static var source: TopShelfSource {
        defaults?.string(forKey: sourceKey).flatMap(TopShelfSource.init(rawValue:)) ?? .fallback
    }
    static func snapshot() -> TopShelfSnapshot {
        defaults?.data(forKey: snapshotKey).flatMap { try? JSONDecoder().decode(TopShelfSnapshot.self, from: $0) } ?? TopShelfSnapshot()
    }
    /// Returns true when the stored snapshot changed, so callers only reload the shelf when needed.
    @discardableResult static func write(_ value: TopShelfSnapshot) -> Bool {
        guard let defaults, value != snapshot(), let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }
}

/// beeb://show/<id> opens a programme page; beeb://resume/<id> resumes a Continue Watching entry.
enum BeebLink: Equatable {
    case show(String), resume(String)
    private static func validID(_ id: String) -> Bool { id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil }
    static func showURL(_ id: String) -> URL? { validID(id) ? URL(string: "beeb://show/\(id)") : nil }
    static func resumeURL(_ id: String) -> URL? { validID(id) ? URL(string: "beeb://resume/\(id)") : nil }
    static func parse(_ url: URL) -> BeebLink? {
        guard url.scheme?.lowercased() == "beeb", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 1, validID(path[0]) else { return nil }
        switch url.host {
        case "show": return .show(path[0])
        case "resume": return .resume(path[0])
        default: return nil
        }
    }
}
