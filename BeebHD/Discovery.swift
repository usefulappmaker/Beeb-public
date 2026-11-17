// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct Genre: Codable, Identifiable, Hashable { let id: String; let title: String }
struct HomeFeature: Codable, Identifiable {
    let show: CatalogueShow
    let headline: String
    let synopsis: String
    let image: URL?
    var id: String { show.id }
}
struct HomeRow: Codable, Identifiable {
    let id: String; let title: String; let shows: [CatalogueShow]
    var usesPosters: Bool { title.localizedCaseInsensitiveCompare("Stream Every Episode") == .orderedSame }
}
struct HomeFeed: Codable { let features: [HomeFeature]; let rows: [HomeRow] }
struct LiveProgramme: Codable, Hashable {
    let title: String
    let subtitle: String
    let image: URL?
    let end: Date
    var start: Date? = nil   // LIVE-LOGOS: for the progress bar
}
struct LiveChannel: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    var current: LiveProgramme? = nil
}
struct DiscoveryAPI {
    let fetch: (URL) async throws -> Data
    init(fetch: @escaping (URL) async throws -> Data = { try await BBCService().fetch($0) }) { self.fetch = fetch }
    static func state(from html: String) throws -> [String: Any] {
        guard let marker = html.range(of: "window.__IPLAYER_REDUX_STATE__"),
              let begin = html[marker.upperBound...].firstIndex(of: "{") else { throw BBCError.message("BBC homepage data could not be found.") }
        var depth = 0, quoted = false, escaped = false
        for i in html[begin...].indices {
            let ch = html[i]
            if quoted {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { quoted = false }
            } else if ch == "\"" { quoted = true }
            else if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    guard let object = try JSONSerialization.jsonObject(with: Data(html[begin...i].utf8)) as? [String: Any] else { break }
                    return object
                }
            }
        }
        throw BBCError.message("BBC homepage data is incomplete.")
    }
    static func home(_ data: Data) throws -> HomeFeed {
        let root = try state(from: String(decoding: data, as: UTF8.self))
        guard let bundles = root["bundles"] as? [[String: Any]] else { throw BBCError.message("BBC's homepage layout has changed.") }
        var rows = [HomeRow](), hero = [HomeFeature](), latest = [HomeFeature]()
        func text(_ object: Any?, _ keys: [String]) -> String {
            let fields = object as? [String: Any] ?? [:]
            return keys.compactMap { fields[$0] as? String }.first { !$0.isEmpty } ?? ""
        }
        for bundle in bundles {
            guard let bid = bundle["id"] as? String, let entities = bundle["entities"] as? [[String: Any]] else { continue }
            var shows = [CatalogueShow](), features = [HomeFeature](), seen = Set<String>()
            for entity in entities {
                guard let e = entity["episode"] as? [String: Any], e["live"] as? Bool != true,
                      let episodeID = e["id"] as? String else { continue }
                let showID = (e["tleo"] as? [String: Any])?["id"] as? String ?? episodeID
                guard showID.range(of: "^[a-z0-9]{8}$", options: .regularExpression) != nil, seen.insert(showID).inserted else { continue }
                let title = text(e["title"], ["default", "editorial"])
                let summary = text(e["synopsis"], ["programmeSmall", "small", "editorial"])
                let image = CatalogueAPI.image(text(e["image"], ["promotionalWithLogo", "default", "promotional"]))
                var show = CatalogueShow(id: showID, title: title, summary: summary, image: image, letter: "", channel: "BBC",
                    categories: [], expectedEpisodes: showID == episodeID ? 1 : 0, singleEpisode: showID == episodeID, episodes: [], indexedAt: nil)
                show.portraitImage = CatalogueAPI.portraitImage(e["image"])
                shows.append(show)
                let plainArtwork = text(e["image"], ["promotional", "default"])
                let large = plainArtwork.replacingOccurrences(of: "{recipe}", with: "1920x1080")
                features.append(HomeFeature(show: show, headline: text(e["title"], ["editorial", "default"]),
                    synopsis: text(e["synopsis"], ["editorial", "small"]), image: large.isEmpty ? nil : URL(string: large)))
            }
            if bid == "hero" { hero = features }
            if bid == "editorial" { latest = features }
            if !shows.isEmpty { rows.append(HomeRow(id: bid, title: text(bundle["title"], ["default", "small"]), shows: shows)) }
        }
        // Use BBC's actual popularity ordering, ahead of other discovery rows.
        rows = rows.filter { $0.id == "popular" } + rows.filter { $0.id != "popular" && $0.id != "hero" }
        guard !rows.isEmpty else { throw BBCError.message("BBC returned no homepage programmes.") }
        return HomeFeed(features: Array((latest.isEmpty ? hero : latest).prefix(8)), rows: Array(rows.prefix(10)))
    }
    func homepage() async throws -> HomeFeed {
        try Self.home(await fetch(URL(string: "https://www.bbc.co.uk/iplayer")!))
    }
    func genres() async throws -> [Genre] {
        let data = try await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/categories")!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let values = root["categories"] as? [[String: Any]] else { throw BBCError.message("BBC's categories are unavailable.") }
        return values.compactMap { v in
            guard let id = v["id"] as? String, let title = v["title"] as? String, v["kind"] as? String == "genre" else { return nil }
            return Genre(id: id, title: title)
        }
    }
    func page(category: String? = nil, letter: String? = nil, page: Int) async throws -> CataloguePage {
        let path: String, key: String
        if let category {
            guard category.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { throw BBCError.message("Unknown category.") }
            path = "categories/\(category)/programmes"; key = "category_programmes"
        } else if let letter, CatalogueAPI.letters.contains(letter) {
            path = "atoz/\(letter)/programmes"; key = "atoz_programmes"
        } else { throw BBCError.message("Choose a category or letter.") }
        let data = try await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/\(path)?page=\(page)&per_page=30")!)
        let body = try CatalogueAPI.container(data, key: key)
        guard body["page"] as? Int == page, let perPage = body["per_page"] as? Int, perPage <= 30,
              (body["elements"] as? [[String: Any]])?.count ?? 0 <= 30 else {
            throw BBCError.message("BBC returned an unexpected catalogue page.")
        }
        return CataloguePage(shows: try (body["elements"] as! [[String: Any]]).map { try CatalogueAPI.show($0, letter: letter ?? "") },
                             total: body["count"] as! Int, page: body["page"] as! Int, perPage: body["per_page"] as! Int)
    }
    func show(_ id: String) async throws -> CatalogueShow {
        let pid = try BBCService.pid(id)
        let data = try await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/programmes/\(pid)")!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let first = (root["programmes"] as? [[String: Any]])?.first else { throw BBCError.message("This programme is no longer listed.") }
        return try CatalogueAPI.show(first)
    }
    func parent(of episode: Programme) async throws -> CatalogueShow {
        if let id = episode.showID { return try await show(id) }
        let data = try await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/episodes/\(try BBCService.pid(episode.id))")!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (root["episodes"] as? [[String: Any]])?.first else { throw BBCError.message("Could not find this episode's programme.") }
        return try await show(first["tleo_id"] as? String ?? episode.id)
    }
    func channels() async throws -> [LiveChannel] {
        let data = try await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/channels")!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let values = root["channels"] as? [[String: Any]] else { throw BBCError.message("Live channels could not be loaded.") }
        return values.compactMap { v in
            guard v["has_schedule"] as? Bool == true, let id = v["id"] as? String, let title = v["title"] as? String else { return nil }
            return RegionalChannels.resolve(LiveChannel(id: id, title: title))
        }
    }
    static func currentBroadcast(_ data: Data, now: Date = Date()) throws -> LiveProgramme? {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let values = (root?["broadcasts"] as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        let dates = ISO8601DateFormatter(); dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ raw: Any?) -> Date? { (raw as? String).flatMap { dates.date(from: $0) ?? plain.date(from: $0) } }
        for broadcast in values {
            guard let start = date(broadcast["scheduled_start"]), let end = date(broadcast["scheduled_end"]),
                  start <= now, now < end, broadcast["blanked"] as? Bool != true,
                  let episode = broadcast["episode"] as? [String: Any], let title = episode["title"] as? String else { continue }
            return LiveProgramme(title: title, subtitle: episode["subtitle"] as? String ?? "",
                image: CatalogueAPI.programmeImage(episode["images"]), end: end, start: start)
        }
        return nil
    }
    func nowPlaying(_ channels: [LiveChannel]) async -> [LiveChannel] {
        // Independent channel schedules; one unavailable feed must not hide other channels.
        await withTaskGroup(of: (Int, LiveChannel).self) { group in
            for (index, channel) in channels.enumerated() {
                group.addTask {
                    var result = channel
                    if let data = try? await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/channels/\(channel.id)/broadcasts?per_page=20")!) {
                        result.current = try? Self.currentBroadcast(data)
                    } else if let current = result.current, current.end <= Date() { result.current = nil }
                    return (index, result)
                }
            }
            var results = [(Int, LiveChannel)]()
            for await value in group { results.append(value) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
    func liveSource(_ channel: LiveChannel) async throws -> PlaybackSource {
        guard channel.id.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil else { throw BBCError.message("Invalid channel.") }
        var last: Error?
        for set in ["iptv-all", "pc"] {
            do {
                let data = try await fetch(URL(string: "https://open.live.bbc.co.uk/mediaselector/6/select/version/2.0/mediaset/\(set)/vpid/\(channel.id)/format/xml")!)
                let selector = MediaSelector(); let parser = XMLParser(data: data); parser.delegate = selector
                guard parser.parse() else { continue }
                for url in selector.urls {
                    let manifest = String(decoding: try await fetch(url), as: UTF8.self)
                    if manifest.hasPrefix("#EXTM3U"), !BBCService.variants(manifest, base: url).isEmpty {
                        return PlaybackSource(url: url, requested1080: false, liveCaptionTemplates: selector.liveCaptionTemplates)
                    }
                }
                if let message = selector.error { throw BBCError.message(message) }
            } catch { if Task.isCancelled { throw CancellationError() }; last = error }
        }
        throw BBCError.message("This channel is unavailable or off air. \(last?.localizedDescription ?? "No compatible live HLS stream was returned.")")
    }
}
actor DiscoveryCache {
    let folder: URL
    init(folder: URL? = nil) { self.folder = folder ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BeebHDDiscovery-v5") }
    func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(key + ".json")) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func write<T: Encodable>(_ value: T, key: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: folder.appendingPathComponent(key + ".json"), options: .atomic)
    }
}

extension RegionalChannels {
    static func resolve(_ channel: LiveChannel, defaults: UserDefaults = .standard) -> LiveChannel {
        let id = selectedID(for: channel.id, defaults: defaults)
        guard id != channel.id else { return channel }
        let choice = (bbcOne + bbcTwo).first { $0.id == id }
        let name = id.hasPrefix("bbc_one") ? "BBC One" : "BBC Two"
        return LiveChannel(id: id, title: "\(name) \(choice?.title ?? "")")
    }
}
