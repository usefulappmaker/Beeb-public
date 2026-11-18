// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// BBC live caption fragments share the numbered 3.84-second IPTV timeline.
/// Programme date/time ties TTML's absolute clock to the video's 33-bit PES clock.
enum LiveSubtitles {
    struct Segment {
        let sequence: Int
        let discontinuity: Int
        let date: Double
        let duration: Double
        let video: URL
        let captionNumber: Int
        var path: String { "/live-captions/\(discontinuity)/\(sequence).vtt" }
    }
    struct Timeline {
        let segments: [Segment]
        let target: Int
        var playlist: Data {
            guard let first = segments.first else { return Data() }
            var text = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:\(target)\n#EXT-X-MEDIA-SEQUENCE:\(first.sequence)\n#EXT-X-DISCONTINUITY-SEQUENCE:\(first.discontinuity)\n"
            var previous = first.discontinuity
            let clock = ISO8601DateFormatter(); clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for segment in segments {
                if segment.discontinuity != previous { text += "#EXT-X-DISCONTINUITY\n"; previous = segment.discontinuity }
                // Same wall-clock times as the video segments: lets the player show and seek by time of day.
                text += "#EXT-X-PROGRAM-DATE-TIME:" + clock.string(from: Date(timeIntervalSince1970: segment.date)) + "\n"
                text += String(format: "#EXTINF:%.6f,\n", locale: Locale(identifier: "en_US_POSIX"), segment.duration)
                text += "\(segment.discontinuity)/\(segment.sequence).vtt\n"
            }
            // No ENDLIST: AVPlayer reloads this alongside the remote video playlist.
            return Data(text.utf8)
        }
    }
    static func timeline(_ text: String, base: URL) throws -> Timeline {
        guard text.hasPrefix("#EXTM3U"), !text.contains("#EXT-X-MAP:"), !text.contains("#EXT-X-ENDLIST") else {
            throw BBCError.message("This live stream has no supported caption clock.")
        }
        let normal = ISO8601DateFormatter(), fractional = ISO8601DateFormatter()
        fractional.formatOptions.insert(.withFractionalSeconds)
        var sequence = 0, discontinuity = 0, target = 4
        var date: Double?, duration: Double?, result = [Segment]()
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") { sequence = Int(line.dropFirst(22)) ?? 0 }
            else if line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE:") { discontinuity = Int(line.dropFirst(30)) ?? 0 }
            else if line == "#EXT-X-DISCONTINUITY" { discontinuity += 1 }
            else if line.hasPrefix("#EXT-X-TARGETDURATION:") { target = Int(line.dropFirst(22)) ?? 4 }
            else if line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") {
                let value = String(line.dropFirst(25))
                date = (fractional.date(from: value) ?? normal.date(from: value))?.timeIntervalSince1970
            } else if line.hasPrefix("#EXTINF:") { duration = Double(line.dropFirst(8).split(separator: ",")[0]) }
            else if !line.isEmpty, !line.hasPrefix("#") {
                guard let start = date, let length = duration, abs(length - 3.84) < 0.01,
                      let url = HLSSubtitles.resolve(line, base: base),
                      let number = Int(url.deletingPathExtension().lastPathComponent), sequence >= 0 else {
                    throw BBCError.message("The live caption timeline is unavailable.")
                }
                result.append(Segment(sequence: sequence, discontinuity: discontinuity, date: start, duration: length, video: url, captionNumber: number))
                sequence += 1; date = start + length; duration = nil
            }
        }
        guard !result.isEmpty, result.count <= 4096, target > 0 else { throw BBCError.message("Invalid live caption playlist.") }
        return Timeline(segments: result, target: target)
    }
    static func cues(_ fragment: Data) throws -> [SubtitleCue] {
        guard fragment.count <= 8_000_000 else { throw BBCError.message("Live caption fragment is too large.") }
        var offset = 0
        func number(_ at: Int, _ count: Int) -> UInt64 {
            fragment[at..<at+count].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        while offset + 8 <= fragment.count {
            let size = number(offset, 4), type = String(decoding: fragment[offset+4..<offset+8], as: UTF8.self)
            let header = size == 1 ? 16 : 8
            guard offset + header <= fragment.count else { break }
            let length = size == 0 ? UInt64(fragment.count - offset) : size == 1 ? number(offset+8, 8) : size
            guard length >= header, length <= fragment.count - offset else { break }
            if type == "mdat" {
                return try TTMLSubtitles.parse(fragment.subdata(in: offset+header..<offset+Int(length)))
            }
            offset += Int(length)
        }
        throw BBCError.message("No timed text in the live caption fragment.")
    }
    static func webVTT(cues: [SubtitleCue], segment: Segment, anchorDate: Double, anchorPTS: UInt64) -> Data {
        let wrap = Int64(1) << 33
        let raw = Int64(anchorPTS) + Int64(((segment.date - anchorDate) * 90000).rounded())
        let pts = ((raw % wrap) + wrap) % wrap
        var text = "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:\(pts)\n\n"
        for cue in cues where cue.end > segment.date && cue.start < segment.date + segment.duration {
            let value = cue.text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            text += "\(HLSSubtitles.timestamp(max(0, cue.start - segment.date))) --> \(HLSSubtitles.timestamp(min(segment.duration, cue.end - segment.date)))\n\(value)\n\n"
        }
        return Data(text.utf8)
    }
}

#if canImport(Network)
/// Fetch captions only as AVPlayer requests them, including after a rewind.
/// Video and alternate audio remain direct BBC URLs; no video proxy or transcoding.
actor LiveSubtitleResources {
    private let media: URL
    private let templates: [URL]
    private let fetch: @Sendable (URL) async throws -> Data
    private var segments = [String: LiveSubtitles.Segment]()
    private var anchors = [Int: (date: Double, pts: UInt64)]()
    private var cached: (Date, Data)?
    init(media: URL, templates: [URL], fetch: @escaping @Sendable (URL) async throws -> Data = { try await BBCService().fetch($0) }) {
        self.media = media; self.templates = templates; self.fetch = fetch
    }
    func playlist() async throws -> Data {
        if let cached, Date().timeIntervalSince(cached.0) < 1 { return cached.1 }
        let text = String(decoding: try await fetch(media), as: UTF8.self)
        let timeline = try LiveSubtitles.timeline(text, base: media)
        try Task.checkCancellation()
        let current = Dictionary(uniqueKeysWithValues: timeline.segments.map { ($0.path, $0) })
        // Keep a short tail for requests racing a playlist update, with bounded memory.
        let tail = segments.values.sorted { $0.sequence > $1.sequence }.prefix(128)
        segments = Dictionary(tail.map { ($0.path, $0) }, uniquingKeysWith: { _, new in new })
        segments.merge(current, uniquingKeysWith: { _, new in new })
        let groups = Set(segments.values.map(\.discontinuity)); anchors = anchors.filter { groups.contains($0.key) }
        let data = timeline.playlist; cached = (Date(), data)
        return data
    }
    func resource(_ path: String) async throws -> Data? {
        if path == "/live-captions/english.m3u8" { return try await playlist() }
        guard let segment = segments[path] else { return nil }
        let anchor: (date: Double, pts: UInt64)
        if let existing = anchors[segment.discontinuity] { anchor = existing }
        else {
            let data = try await fetch(segment.video)
            guard let pts = HLSSubtitles.firstVideoPTS(data) else { throw BBCError.message("Live video clock unavailable.") }
            anchor = (segment.date, pts); anchors[segment.discontinuity] = anchor
        }
        for template in templates {
            try Task.checkCancellation()
            guard let url = URL(string: template.absoluteString.replacingOccurrences(of: "$Number$", with: String(segment.captionNumber))) else { continue }
            do {
                let cues = try LiveSubtitles.cues(await fetch(url))
                return LiveSubtitles.webVTT(cues: cues, segment: segment, anchorDate: anchor.date, anchorPTS: anchor.pts)
            } catch { if Task.isCancelled { throw CancellationError() } }
        }
        // A temporarily missing caption segment must not end an otherwise working live stream.
        return LiveSubtitles.webVTT(cues: [], segment: segment, anchorDate: anchor.date, anchorPTS: anchor.pts)
    }
}

@MainActor final class LiveSubtitlePlaybackAccess {
    private let server = LocalHLSServer()
    func start(_ source: PlaybackSource) async throws -> URL {
        let master = String(decoding: try await BBCService().fetch(source.url), as: UTF8.self)
        guard master.hasPrefix("#EXTM3U"), !master.contains("TYPE=SUBTITLES"),
              let variant = BBCService.variants(master, base: source.url).first else { return source.url }
        let resources = LiveSubtitleResources(media: variant.url, templates: source.liveCaptionTemplates)
        _ = try await resources.playlist()
        var generated = try HLSSubtitles.assets(cues: [], duration: 1, master: master, base: source.url)["/master.m3u8"]!
        generated = Data(String(decoding: generated, as: UTF8.self).replacingOccurrences(of: "subtitles/english.m3u8", with: "live-captions/english.m3u8").utf8)
        try Task.checkCancellation()
        return try await server.start(playlists: ["/master.m3u8": generated], resourceHandler: { try await resources.resource($0) })
    }
    func stop() { server.stop() }
    deinit { server.stop() }
}
#endif
