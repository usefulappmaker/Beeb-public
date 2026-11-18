// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct CatalogueEpisode: Codable, Identifiable, Hashable {
    let programme: Programme
    let subtitle: String
    let duration: String
    let sliceID: String
    let seriesTitle: String
    var parentPosition: Int? = nil
    var broadcastDate: String? = nil
    var id: String { programme.id }
}
struct CatalogueSeries: Identifiable {
    let id: String
    let title: String
    let episodes: [CatalogueEpisode]
}
struct CatalogueShow: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var summary: String
    var image: URL?
    var letter: String
    var channel: String
    var categories: [String]
    var expectedEpisodes: Int
    var singleEpisode: Bool
    var episodes: [CatalogueEpisode]
    var indexedAt: Date?
    var uhdListed: Bool? = nil
    var hdrListed: Bool? = nil
    var uhdEpisodeCount: Int? = nil
    var discoveryEpisodeID: String? = nil
    var portraitImage: URL? = nil
    var series: [CatalogueSeries] {
        var order = [String](), groups = [String: [CatalogueEpisode]]()
        for e in episodes {
            if groups[e.sliceID] == nil { order.append(e.sliceID) }
            groups[e.sliceID, default: []].append(e)
        }
        return order.map { CatalogueSeries(id: $0, title: groups[$0]?.first?.seriesTitle ?? "Episodes", episodes: groups[$0] ?? []) }
    }
}
struct CataloguePage {
    let shows: [CatalogueShow]
    let total: Int
    let page: Int
    let perPage: Int
}
struct EpisodePage {
    let episodes: [CatalogueEpisode]
    let total: Int
    let page: Int
    let perPage: Int
}
struct CatalogueAPI {
    static let letters = ["0-9"] + (97...122).compactMap { UnicodeScalar($0).map(String.init) }
    let fetch: (URL) async throws -> Data
    init(fetch: @escaping (URL) async throws -> Data = { try await BBCService().fetch($0) }) { self.fetch = fetch }
    static func image(_ raw: Any?) -> URL? {
        guard let s = raw as? String else { return nil }
        return URL(string: s.replacingOccurrences(of: "{recipe}", with: "640x360"))
    }
    static func programmeImage(_ raw: Any?) -> URL? {
        let images = raw as? [String: Any] ?? [:]
        return ["promotional_with_logo", "standard", "promotional"].compactMap { key -> URL? in
            guard let value = images[key] as? String, !value.isEmpty else { return nil }
            return image(value)
        }.first
    }
    static func portraitImage(_ raw: Any?) -> URL? {
        let images = raw as? [String: Any] ?? [:]
        guard let value = images["portrait"] as? String, !value.isEmpty else { return nil }
        return URL(string: value.replacingOccurrences(of: "{recipe}", with: "640x960"))
    }
    static func episodeImage(_ raw: Any?) -> URL? {
        let images = raw as? [String: Any] ?? [:]
        // Standard is the episode still; promotional artwork is often shared by the whole show.
        return ["standard", "promotional", "promotional_with_logo"].compactMap { key -> URL? in
            guard let value = images[key] as? String, !value.isEmpty else { return nil }
            return image(value)
        }.first
    }
    static func episode(_ value: [String: Any]) throws -> CatalogueEpisode {
        guard let id = value["id"] as? String, id.range(of: "^[a-z0-9]{8}$", options: .regularExpression) != nil, let title = value["title"] as? String else {
            throw BBCError.message("BBC's episode catalogue format has changed.")
        }
        let versions = value["versions"] as? [[String: Any]] ?? []
        let eligible = versions.filter { eligibleVersion($0) }
        let version = eligible.first(where: { $0["uhd"] as? Bool == true })
            ?? eligible.first(where: { $0["kind"] as? String == "original" }) ?? eligible.first ?? versions.first ?? [:]
        let subtitle = value["subtitle"] as? String ?? ""
        let slice = value["slice_id"] as? String ?? "episodes"
        let seriesTitle: String
        if slice != "episodes", let separator = subtitle.range(of: ": ") {
            seriesTitle = String(subtitle[..<separator.lowerBound])
        } else { seriesTitle = "Episodes" }
        let guidance = ((version["guidance"] as? [String: Any])?["text"] as? [String: Any])?["large"] as? String
        var p = Programme(id: id, title: subtitle.isEmpty ? title : "\(title) — \(subtitle)",
                          summary: ["medium", "large", "small"].compactMap { (value["synopses"] as? [String: Any])?[$0] as? String }.first { !$0.isEmpty } ?? "",  // medium first, then the full synopsis
                          image: episodeImage(value["images"]),
                          version: version["id"] as? String ?? "", guidance: guidance)
        p.uhdListed = !["available", ""].contains(value["status"] as? String ?? "") ? false : eligible.contains { $0["uhd"] as? Bool == true }
        p.hdrListed = version["hdr"] as? Bool
        p.durationText = (version["duration"] as? [String: Any])?["text"] as? String
        p.firstBroadcast = version["first_broadcast"] as? String
        p.firstBroadcastDateTime = version["first_broadcast_date_time"] as? String
        p.showID = value["tleo_id"] as? String
        p.showTitle = title
        p.episodeSubtitle = subtitle.isEmpty ? nil : subtitle
        return CatalogueEpisode(programme: p, subtitle: subtitle.isEmpty ? title : subtitle,
                                duration: (version["duration"] as? [String: Any])?["text"] as? String ?? "",
                                sliceID: slice, seriesTitle: seriesTitle, parentPosition: value["parent_position"] as? Int, broadcastDate: value["release_date_time"] as? String)
    }
    /// UHD can belong to a replacement edit, and the catalogue HDR flag is not an HLG test.
    static func eligibleVersion(_ version: [String: Any], now: Date = Date()) -> Bool {
        guard !["audio-described", "signed"].contains(version["kind"] as? String ?? "") else { return false }
        let availability = version["availability"] as? [String: Any] ?? [:]
        func date(_ key: String) -> Date? {
            guard let raw = availability[key] as? String else { return nil }
            let parser = ISO8601DateFormatter()
            if let date = parser.date(from: raw) { return date }
            parser.formatOptions.insert(.withFractionalSeconds)
            return parser.date(from: raw)
        }
        if let start = date("start"), start > now { return false }
        if let end = date("end"), end <= now { return false }
        return true
    }
    static func container(_ data: Data, key: String) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = root[key] as? [String: Any], body["elements"] is [[String: Any]],
              body["count"] is Int, body["page"] is Int, let perPage = body["per_page"] as? Int, perPage > 0 else {
            throw BBCError.message("BBC's catalogue is unavailable or its format has changed. Your saved catalogue is retained.")
        }
        return body
    }
    static func show(_ value: [String: Any], letter: String = "") throws -> CatalogueShow {
        guard let id = value["id"] as? String, id.range(of: "^[a-z0-9]{8}$", options: .regularExpression) != nil, let title = value["title"] as? String else {
            throw BBCError.message("A catalogue listing is missing its title or identifier.")
        }
        let children = try (value["initial_children"] as? [[String: Any]] ?? []).map(episode)
        let count = value["count"] as? Int ?? children.count
        let single = value["tleo_type"] as? String == "episode"
        var show = CatalogueShow(id: id, title: title,
            summary: (value["synopses"] as? [String: Any])?["medium"] as? String ?? "",
            image: programmeImage(value["images"]), letter: letter,
            channel: ((value["master_brand"] as? [String: Any])?["titles"] as? [String: Any])?["small"] as? String ?? "BBC",
            categories: value["categories"] as? [String] ?? [], expectedEpisodes: count, singleEpisode: single,
            episodes: children, indexedAt: single && children.count >= count ? Date() : nil)
        show.portraitImage = portraitImage(value["images"])
        show.uhdListed = children.contains { $0.programme.uhdListed == true } ? true : nil
        show.hdrListed = children.contains { $0.programme.uhdListed == true && $0.programme.hdrListed == true }
        return show
    }
    static func parseShows(_ data: Data, letter: String) throws -> CataloguePage {
        let body = try container(data, key: "atoz_programmes")
        let shows = try (body["elements"] as! [[String: Any]]).map { try Self.show($0, letter: letter) }
        return CataloguePage(shows: shows, total: body["count"] as! Int, page: body["page"] as! Int, perPage: body["per_page"] as! Int)
    }
    static func parseEpisodes(_ data: Data) throws -> EpisodePage {
        let body = try container(data, key: "programme_episodes")
        return EpisodePage(episodes: try (body["elements"] as! [[String: Any]]).map(episode),
                           total: body["count"] as! Int, page: body["page"] as! Int, perPage: body["per_page"] as! Int)
    }
    func details(_ show: CatalogueShow) async throws -> CatalogueShow {
        if show.singleEpisode && show.indexedAt != nil { return show }
        var result = show, page = 1, all = [CatalogueEpisode](), seen = Set<String>()
        while true {
            try Task.checkCancellation()
            let url = URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/programmes/\(show.id)/episodes?page=\(page)&per_page=200")!
            let response = try Self.parseEpisodes(await fetch(url))
            guard response.page == page else { throw BBCError.message("BBC returned the wrong episode page.") }
            let additions = response.episodes.filter { seen.insert($0.id).inserted }
            all += additions
            if page * response.perPage >= response.total {
                guard all.count == response.total else { throw BBCError.message("BBC's episode list changed during paging. The previous list is retained.") }
                result.expectedEpisodes = response.total
                break
            }
            guard !additions.isEmpty else { throw BBCError.message("BBC's episode pagination stopped early.") }
            page += 1
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        result.episodes = all; result.indexedAt = Date()
        result.uhdListed = all.contains { $0.programme.uhdListed == true }
        result.hdrListed = all.contains { $0.programme.uhdListed == true && $0.programme.hdrListed == true }
        result.uhdEpisodeCount = all.filter { $0.programme.uhdListed == true }.count
        return result
    }
}

