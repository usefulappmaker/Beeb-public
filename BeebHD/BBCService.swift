// SPDX-License-Identifier: GPL-3.0-or-later
// Stream discovery adapted from get_iplayer 3.36; see NOTICE.md.
import Foundation

struct Programme: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let summary: String
    let image: URL?
    let version: String
    let guidance: String?
    var showID: String? = nil
    var showTitle: String? = nil
    var episodeSubtitle: String? = nil
    var uhdListed: Bool? = nil
    var hdrListed: Bool? = nil
    var durationText: String? = nil
    var firstBroadcast: String? = nil
    var firstBroadcastDateTime: String? = nil
}
struct PlaybackSource {
    let url: URL
    let requested1080: Bool
    var requestedHeight: Int? = nil
    var videoRange: String? = nil
    var versionID: String? = nil
    var liveCaptionTemplates: [URL] = []
}
enum BBCError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
struct Variant {
    let url: URL
    let height: Int
    let bandwidth: Int
    var codecs: String? = nil
    var videoRange: String? = nil
}
struct BBCService {
    static func pid(_ input: String) throws -> String {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.range(of: "^[b-df-hj-np-tv-z0-9]{8}$", options: .regularExpression) != nil { return s }
        if let u = URL(string: s), let host = u.host,
           host == "bbc.co.uk" || host.hasSuffix(".bbc.co.uk") {
            let parts = u.pathComponents
            for marker in ["episode", "episodes", "programmes"] {
                if let i = parts.firstIndex(of: marker), i + 1 < parts.count {
                    return try pid(parts[i + 1])
                }
            }
        }
        throw BBCError.message("Enter a BBC episode URL or its eight-character programme ID.")
    }
    func fetch(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BBCError.message("No response from BBC.") }
        guard (200..<300).contains(http.statusCode) else {
            throw BBCError.message("The service returned HTTP \(http.statusCode). The programme may be unavailable or access may be restricted.")
        }
        return data
    }
    static func episodeMetadata(_ data: Data, id: String) throws -> [String: Any] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let episode = (root["episodes"] as? [[String: Any]])?.first(where: { $0["id"] as? String == id }) else {
            throw BBCError.message("BBC's episode service returned unreadable details. Please try again later.")
        }
        return episode
    }
    static func playbackVersions(_ episode: [String: Any], now: Date = Date()) -> [String] {
        let formatter = ISO8601DateFormatter()
        func date(_ raw: Any?) -> Date? {
            guard let raw = raw as? String else { return nil }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        }
        let versions = (episode["versions"] as? [[String: Any]] ?? []).filter { version in
            let kind = (version["kind"] as? String ?? "original").lowercased()
            guard !kind.contains("signed"), !kind.contains("describ"), let id = version["id"] as? String,
                  (try? pid(id)) != nil else { return false }
            let availability = version["availability"] as? [String: Any] ?? [:]
            if let start = date(availability["start"]), start > now { return false }
            if let end = date(availability["end"]), end <= now { return false }
            return true
        }
        let ordered = versions.filter { $0["uhd"] as? Bool == true } + versions.filter { $0["uhd"] as? Bool != true }
        var seen = Set<String>()
        return ordered.compactMap { $0["id"] as? String }.filter { seen.insert($0).inserted }
    }
    static func programme(_ data: Data, id: String) throws -> Programme {
        let episode = try episodeMetadata(data, id: id)
        guard let versionID = playbackVersions(episode).first else {
            throw BBCError.message("No standard version of this episode is currently available.")
        }
        let version = (episode["versions"] as? [[String: Any]])?.first { $0["id"] as? String == versionID } ?? [:]
        let synopses = episode["synopses"] as? [String: Any] ?? [:]
        let images = episode["images"] as? [String: Any] ?? [:]
        let artwork = (images["standard"] as? String ?? "").replacingOccurrences(of: "{recipe}", with: "640x360")
        let guidance = ((version["guidance"] as? [String: Any])?["text"] as? [String: Any])?["large"] as? String
        return Programme(id: id, title: episode["title"] as? String ?? id,
                         summary: ["large", "medium", "small"].compactMap { synopses[$0] as? String }.first ?? "",
                         image: URL(string: artwork), version: versionID, guidance: guidance)
    }
    func programme(_ id: String) async throws -> Programme {
        let id = try Self.pid(id)
        return try Self.programme(await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/episodes/\(id)")!), id: id)
    }
    static func resolve(_ reference: String, base: URL) -> URL? {
        guard let url = URL(string: reference, relativeTo: base)?.absoluteURL,
              url.scheme == "https" else { return nil }
        // Match get_iplayer's same-host authentication query propagation.
        guard url.host == base.host, var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let parent = URLComponents(url: base, resolvingAgainstBaseURL: true)?.percentEncodedQuery else { return url }
        if let own = parts.percentEncodedQuery, !own.isEmpty { parts.percentEncodedQuery = parent + "&" + own }
        else { parts.percentEncodedQuery = parent }
        return parts.url
    }
    static func variants(_ text: String, base: URL) -> [Variant] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var attrs: String?
        var result = [Variant]()
        func capture(_ pattern: String, _ s: String) -> Int {
            guard let r = try? NSRegularExpression(pattern: pattern),
                  let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let range = Range(m.range(at: 1), in: s) else { return 0 }
            return Int(s[range]) ?? 0
        }
        func attribute(_ key: String, _ attributes: String) -> String? {
            let pattern = "(?:^|[:,])" + key + "=(?:\"([^\"]*)\"|([^,]+))"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)) else { return nil }
            for index in [1, 2] {
                if let range = Range(match.range(at: index), in: attributes) { return String(attributes[range]) }
            }
            return nil
        }
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") { attrs = line }
            else if !line.isEmpty && !line.hasPrefix("#"), let a = attrs {
                if let url = resolve(line, base: base) {
                    result.append(Variant(url: url, height: capture("RESOLUTION=[0-9]+x([0-9]+)", a),
                                          bandwidth: capture("(?:[:,])BANDWIDTH=([0-9]+)", a),
                                          codecs: attribute("CODECS", a), videoRange: attribute("VIDEO-RANGE", a)))
                }
                attrs = nil
            }
        }
        return result.sorted { $0.height == $1.height ? $0.bandwidth > $1.bandwidth : $0.height > $1.height }
    }
    static func fullHDURL(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path.range(of: "video=[0-9]+", options: .regularExpression) != nil else { return nil }
        parts.path = parts.path.replacingOccurrences(of: "video=[0-9]+", with: "video=12000000", options: .regularExpression)
        return parts.url
    }
    static func validMediaPlaylist(_ text: String) -> Bool {
        text.hasPrefix("#EXTM3U") && text.contains("#EXTINF:") &&
        !text.contains("METHOD=SAMPLE-AES") && !text.contains("skd://")
    }
    func source(for programme: Programme, require1080: Bool) async throws -> PlaybackSource {
        // Refresh metadata and signed links for each play; do not persist expiring CDN URLs.
        let fresh = try await self.programme(programme.id)
        var lastError: Error?
        for version in [6, 5] {
            for set in ["iptv-all", "pc"] {
                do {
                    let data = try await fetch(URL(string: "https://open.live.bbc.co.uk/mediaselector/\(version)/select/version/2.0/mediaset/\(set)/vpid/\(fresh.version)/format/xml")!)
                    let selector = MediaSelector()
                    let parser = XMLParser(data: data); parser.delegate = selector
                    guard parser.parse() else { throw BBCError.message("BBC returned an unreadable stream listing.") }
                    if let error = selector.error {
                        throw BBCError.message("BBC playback service: \(error).")
                    }
                    var fallback: URL?
                    for master in selector.urls {
                        try Task.checkCancellation()
                        do {
                            let text = String(decoding: try await fetch(master), as: UTF8.self)
                            guard text.hasPrefix("#EXTM3U") else { continue }
                            let variants = Self.variants(text, base: master)
                            for variant in variants where variant.height >= 1080 && variant.height < 2160 {
                                let media = String(decoding: try await fetch(variant.url), as: UTF8.self)
                                if Self.validMediaPlaylist(media) { return PlaybackSource(url: variant.url, requested1080: true, versionID: fresh.version) }
                            }
                            if let hd = variants.first(where: { $0.height >= 720 && $0.height < 2160 }), let url = Self.fullHDURL(hd.url) {
                                if let data = try? await fetch(url) {
                                    let media = String(decoding: data, as: UTF8.self)
                                    if Self.validMediaPlaylist(media) && media.contains("video=12000000") {
                                        return PlaybackSource(url: url, requested1080: true, versionID: fresh.version)
                                    }
                                }
                            }
                            if fallback == nil { fallback = variants.first(where: { $0.height < 2160 })?.url }
                        } catch is CancellationError { throw CancellationError() }
                        catch { lastError = error }
                    }
                    if !require1080, let fallback { return PlaybackSource(url: fallback, requested1080: false, versionID: fresh.version) }
                } catch is CancellationError { throw CancellationError() }
                catch { lastError = error }
            }
        }
        throw BBCError.message("No \(require1080 ? "1080p HLS" : "compatible HLS") stream was found. \(lastError?.localizedDescription ?? "This episode may not have a compatible stream.")")
    }
}
final class MediaSelector: NSObject, XMLParserDelegate {
    var urls = [URL]()
    var error: String?
    var liveCaptionTemplates = [URL]()
    private var captions = false
    private var video = false
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "media" {
            video = attributes["kind"] == "video"
            captions = attributes["kind"] == "captions" && (attributes["type"] ?? "").hasPrefix("application/ttml+xml")
        }
        if element == "connection", captions, attributes["transferFormat"] == "dash",
           let href = attributes["href"], href.contains("$Number$"), let url = URL(string: href), url.scheme == "https",
           !liveCaptionTemplates.contains(url) { liveCaptionTemplates.append(url) }
        if element == "error" { error = attributes["id"] ?? "Unavailable" }
        if element == "connection", video, attributes["transferFormat"] == "hls",
           let s = attributes["href"], let url = URL(string: s), url.scheme == "https", !urls.contains(url) { urls.append(url) }
    }
    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if element == "media" { video = false; captions = false }
    }
}
