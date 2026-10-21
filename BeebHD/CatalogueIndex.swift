// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct CatalogueIndexSnapshot: Codable {
    var schemaVersion = 1
    var catalogue: [CatalogueShow] = []
    var uhd: [CatalogueShow] = []
    var catalogueUpdatedAt: Date?
    var uhdPageUpdatedAt: Date?
    var uhdRetryAfter: Date?
    var catalogueRetryAfter: Date?
    var episodeParents: [String: String]?

    static func compact(_ show: CatalogueShow) -> CatalogueShow {
        var copy = show
        // Retain standalone-episode metadata while keeping the title index compact.
        if !copy.singleEpisode { copy.episodes = []; copy.indexedAt = nil }
        return copy
    }
    static func sorted(_ shows: [CatalogueShow]) -> [CatalogueShow] {
        shows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func search(_ query: String) -> [CatalogueShow] {
        func normal(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
        let needle = normal(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        let tokens = needle.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let knownUHD = Dictionary(uhd.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return catalogue.map { show in
            var result = show
            if let known = knownUHD[show.id] { result.uhdListed = true; result.uhdEpisodeCount = known.uhdEpisodeCount }
            return result
        }.filter { show in
            let text = normal(show.title + " " + show.summary)
            return tokens.allSatisfy { text.contains($0) }
        }.sorted { a, b in
            func rank(_ show: CatalogueShow) -> Int {
                let title = normal(show.title)
                if title == needle { return 0 }
                if title.hasPrefix(needle) { return 1 }
                return title.contains(needle) ? 2 : 3
            }
            let ar = rank(a), br = rank(b)
            return ar == br ? a.title.localizedStandardCompare(b.title) == .orderedAscending : ar < br
        }
    }
}

struct CatalogueIndexAPI {
    let fetch: (URL) async throws -> Data
    init(fetch: @escaping (URL) async throws -> Data = { try await BBCService().fetch($0) }) { self.fetch = fetch }
    func allShows(progress: (String) async -> Void = { _ in }) async throws -> [CatalogueShow] {
        var shows = [String: CatalogueShow]()
        for letter in CatalogueAPI.letters {
            var page = 1, seen = Set<String>(), expected: Int?
            repeat {
                try Task.checkCancellation()
                await progress("Updating catalogue · \(letter.uppercased())")
                let url = URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/atoz/\(letter)/programmes?page=\(page)&per_page=200")!
                let result = try CatalogueAPI.parseShows(await fetch(url), letter: letter)
                guard result.page == page, result.perPage <= 200, result.shows.count <= result.perPage,
                      expected == nil || expected == result.total else {
                    throw BBCError.message("BBC's catalogue changed while updating. The saved catalogue is retained.")
                }
                expected = result.total
                let fresh = result.shows.filter { seen.insert($0.id).inserted }
                for show in fresh { shows[show.id] = CatalogueIndexSnapshot.compact(show) }
                if page * result.perPage >= result.total {
                    guard seen.count == result.total else { throw BBCError.message("BBC's catalogue update was incomplete. Please retry later.") }
                    break
                }
                guard !fresh.isEmpty else { throw BBCError.message("BBC's catalogue pagination stopped early.") }
                page += 1
                try await Task.sleep(nanoseconds: 200_000_000)
            } while true
        }
        guard !shows.isEmpty else { throw BBCError.message("BBC returned an empty catalogue. The saved catalogue is retained.") }
        return CatalogueIndexSnapshot.sorted(Array(shows.values))
    }
    static let uhdPageURL = URL(string: "https://www.bbc.co.uk/iplayer/help/questions/programme-availability/uhd-content")!
    func uhdPage() async throws -> [UHDPageEntry] {
        try Self.parseUHDPage(await fetch(Self.uhdPageURL))
    }
    static func parseUHDPage(_ data: Data) throws -> [UHDPageEntry] {
        let html = String(decoding: data, as: UTF8.self)
        // Restrict extraction to the article, avoiding navigation/related programme links.
        guard let start = html.range(of: "<article", options: .caseInsensitive),
              let end = html.range(of: "</article>", options: .caseInsensitive, range: start.lowerBound..<html.endIndex) else {
            throw BBCError.message("BBC's UHD programme list could not be read.")
        }
        let article = String(html[start.lowerBound..<end.upperBound])
        let anchors = try NSRegularExpression(pattern: #"(?is)<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#)
        let path = try NSRegularExpression(pattern: #"^/iplayer/(episodes?)/([a-z0-9]{8})(?:/|$)"#)
        let ns = article as NSString
        var entries = [UHDPageEntry](), seen = Set<String>()
        for match in anchors.matches(in: article, range: NSRange(location: 0, length: ns.length)) {
            let href = Self.plainHTML(ns.substring(with: match.range(at: 1)))
            guard let url = URL(string: href, relativeTo: uhdPageURL)?.absoluteURL,
                  ["https", "http"].contains(url.scheme ?? ""),
                  ["bbc.co.uk", "www.bbc.co.uk", "bbc.com", "www.bbc.com"].contains(url.host?.lowercased() ?? ""),
                  let pid = path.firstMatch(in: url.path, range: NSRange(location: 0, length: (url.path as NSString).length)) else { continue }
            let urlPath = url.path as NSString
            let id = urlPath.substring(with: pid.range(at: 2))
            let title = Self.plainHTML(ns.substring(with: match.range(at: 2)))
            guard !title.isEmpty, seen.insert(id).inserted else { continue }
            entries.append(UHDPageEntry(id: id, title: title, singleEpisode: urlPath.substring(with: pid.range(at: 1)) == "episode"))
        }
        guard !entries.isEmpty else { throw BBCError.message("BBC's UHD programme list is empty or has changed format.") }
        return entries
    }
    private static func plainHTML(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let numbers = try! NSRegularExpression(pattern: #"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        for match in numbers.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let token = (text as NSString).substring(with: match.range(at: 1))
            let number = token.hasPrefix("x") ? UInt32(token.dropFirst(), radix: 16) : UInt32(token)
            if let number, let scalar = UnicodeScalar(number), let range = Range(match.range, in: text) { text.replaceSubrange(range, with: String(scalar)) }
        }
        for (entity, replacement) in [("&nbsp;", " "), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&ndash;", "–"), ("&rsquo;", "’")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

struct UHDPageEntry: Equatable {
    let id: String
    let title: String
    let singleEpisode: Bool
}

/// Immutable normalized catalogue, prepared once per snapshot off the UI thread.
struct PreparedCatalogueSearch {
    private struct Entry {
        let show: CatalogueShow
        let title: String
        let text: String
    }
    private let entries: [Entry]
    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    init(_ snapshot: CatalogueIndexSnapshot) {
        let known = Dictionary(snapshot.uhd.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entries = CatalogueIndexSnapshot.sorted(snapshot.catalogue).map { show in
            var show = show
            if let uhd = known[show.id] { show.uhdListed = true; show.uhdEpisodeCount = uhd.uhdEpisodeCount }
            let title = Self.normalize(show.title)
            return Entry(show: show, title: title, text: title + " " + Self.normalize(show.summary))
        }
    }
    func search(_ query: String) -> [CatalogueShow] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty else { return [] }
        let tokens = needle.split(separator: " ")
        var ranked = [[CatalogueShow]](repeating: [], count: 4)
        for entry in entries where tokens.allSatisfy({ entry.text.contains($0) }) {
            let rank = entry.title == needle ? 0 : entry.title.hasPrefix(needle) ? 1 : entry.title.contains(needle) ? 2 : 3
            ranked[rank].append(entry.show)
        }
        return ranked.flatMap { $0 }
    }
}

actor CatalogueSearchWorker {
    private var revision: Int?
    private var prepared: PreparedCatalogueSearch?
    private var cache: [String: [CatalogueShow]] = [:]
    func search(_ query: String, snapshot: CatalogueIndexSnapshot, revision: Int) throws -> [CatalogueShow] {
        try Task.checkCancellation()
        if self.revision != revision {
            prepared = PreparedCatalogueSearch(snapshot); self.revision = revision; cache = [:]
        }
        try Task.checkCancellation()
        let key = PreparedCatalogueSearch.normalize(query)
        if let result = cache[key] { return result }
        let result = prepared?.search(query) ?? []
        try Task.checkCancellation()
        if cache.count >= 32 { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        return result
    }
}
