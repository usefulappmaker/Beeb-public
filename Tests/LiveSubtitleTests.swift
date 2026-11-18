import Foundation
@main struct LiveSubtitleTests {
    static func main() async throws {
        let base = URL(string: "https://example.org/live/video.m3u8")!
        let media = """
        #EXTM3U
        #EXT-X-TARGETDURATION:4
        #EXT-X-MEDIA-SEQUENCE:21
        #EXT-X-DISCONTINUITY-SEQUENCE:8
        #EXT-X-PROGRAM-DATE-TIME:2026-10-22T00:00:00.000Z
        #EXTINF:3.84,
        466830001.ts
        #EXTINF:3.84,
        466830002.ts
        #EXT-X-DISCONTINUITY
        #EXTINF:3.84,
        466830003.ts
        """
        let timeline = try LiveSubtitles.timeline(media, base: base)
        precondition(timeline.segments.map(\.sequence) == [21,22,23])
        precondition(timeline.segments.map(\.discontinuity) == [8,8,9])
        precondition(abs(timeline.segments[1].date - timeline.segments[0].date - 3.84) < 0.00001)
        let playlist = String(decoding: timeline.playlist, as: UTF8.self)
        precondition(playlist.contains("#EXT-X-MEDIA-SEQUENCE:21") && !playlist.contains("ENDLIST") && playlist.contains("9/23.vtt"))
        let first = timeline.segments[0], next = timeline.segments[1]
        let cues = [SubtitleCue(start: next.date + 0.5, end: next.date + 1.5, text: "Real & timed")]
        let vtt = String(decoding: LiveSubtitles.webVTT(cues: cues, segment: next, anchorDate: first.date, anchorPTS: 900000), as: UTF8.self)
        precondition(vtt.contains("MPEGTS:1245600") && vtt.contains("00:00:00.500 --> 00:00:01.500") && vtt.contains("Real &amp; timed"))
        let wrapped = String(decoding: LiveSubtitles.webVTT(cues: [], segment: next, anchorDate: first.date, anchorPTS: (1 << 33)-100), as: UTF8.self)
        precondition(wrapped.contains("MPEGTS:345500"), "PES timestamps wrap at 33 bits")
        do { _ = try LiveSubtitles.timeline(media + "\n#EXT-X-ENDLIST", base: base); preconditionFailure("Reject VOD") } catch {}
        do { _ = try LiveSubtitles.cues(Data([0,0,0,1])); preconditionFailure("Reject corrupt fragment") } catch {}
        let xml = Data("<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"1s\" end=\"2s\">Caption</p></div></body></tt>".utf8)
        let size = UInt32(xml.count + 8)
        var fragment = Data([UInt8(size >> 24), UInt8((size >> 16)&255), UInt8((size >> 8)&255), UInt8(size&255)])
        fragment.append(Data("mdat".utf8)); fragment.append(xml)
        let parsed = try LiveSubtitles.cues(fragment)
        precondition(parsed == [SubtitleCue(start: 1, end: 2, text: "Caption")])
        let selector = MediaSelector(), parser = XMLParser(data: Data("<mediaSelection><media kind=\"captions\" type=\"application/ttml+xml;codecs=etd2\"><connection transferFormat=\"dash\" href=\"https://example.org/$Number$.m4s\"/></media><media kind=\"video\"><connection transferFormat=\"hls\" href=\"https://example.org/master.m3u8\"/></media></mediaSelection>".utf8))
        parser.delegate = selector
        precondition(parser.parse() && selector.urls.count == 1 && selector.liveCaptionTemplates.count == 1)
        precondition(selector.liveCaptionTemplates[0].absoluteString.contains("$Number$"))
        // Exercise the actual dynamic HTTP bridge, including a rewind and a clock discontinuity.
        let timedXML = Data("<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"\(first.date+0.5)s\" end=\"\(first.date+1.5)s\">Bridge caption</p></div></body></tt>".utf8)
        let timedSize = UInt32(timedXML.count + 8)
        var timedFragment = Data([UInt8(timedSize >> 24), UInt8((timedSize >> 16)&255), UInt8((timedSize >> 8)&255), UInt8(timedSize&255)])
        timedFragment.append(Data("mdat".utf8)); timedFragment.append(timedXML)
        let captionData = timedFragment, playlistData = Data(media.utf8)
        let pts: UInt64 = 900000
        var packet = [UInt8](repeating: 0xff, count: 188)
        packet.replaceSubrange(0..<4, with: [0x47,0x41,0,0x10])
        packet.replaceSubrange(4..<13, with: [0,0,1,0xe0,0,0,0x80,0x80,5])
        packet.replaceSubrange(13..<18, with: [UInt8(0x21 | ((pts >> 30) & 7) << 1), UInt8((pts >> 22) & 255), UInt8(((pts >> 15) & 127) << 1 | 1), UInt8((pts >> 7) & 255), UInt8((pts & 127) << 1 | 1)])
        let videoData = Data(packet)
        let resources = LiveSubtitleResources(media: base, templates: selector.liveCaptionTemplates, fetch: { url in
            if url.path.hasSuffix(".m3u8") { return playlistData }
            if url.path.hasSuffix(".ts") { return videoData }
            return captionData
        })
        _ = try await resources.playlist()
        let server = LocalHLSServer()
        let local = try await server.start(playlists: ["/master.m3u8": Data("#EXTM3U".utf8)], resourceHandler: { try await resources.resource($0) })
        defer { server.stop() }
        let data = try await BBCService().fetch(URL(string: "live-captions/english.m3u8", relativeTo: local)!.absoluteURL)
        precondition(String(decoding: data, as: UTF8.self).contains("8/21.vtt"))
        for path in [first.path, timeline.segments[2].path, first.path] {
            let result = try await BBCService().fetch(URL(string: String(path.dropFirst()), relativeTo: local)!.absoluteURL)
            let text = String(decoding: result, as: UTF8.self)
            precondition(text.hasPrefix("WEBVTT") && text.contains("MPEGTS:900000"))
            if path == first.path { precondition(text.contains("Bridge caption"), "Timed text survives on-demand fetching and rewind") }
        }
        print("PASS: dynamic local HTTP captions, native WebVTT responses, discontinuity and rewind requests")
        if CommandLine.arguments.count > 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[1])
            let real = try LiveSubtitles.timeline(String(contentsOf: folder.appendingPathComponent("media.m3u8"), encoding: .utf8), base: base)
            let captions = try LiveSubtitles.cues(Data(contentsOf: folder.appendingPathComponent("caption.m4s")))
            let first = real.segments[0]
            let pts = HLSSubtitles.firstVideoPTS(try Data(contentsOf: folder.appendingPathComponent("segment.bin")))!
            precondition(!captions.isEmpty && captions.allSatisfy { $0.start >= first.date-0.01 && $0.end <= first.date+first.duration+0.01 }, "Real BBC TTML and HLS clocks align")
            let vtt = String(decoding: LiveSubtitles.webVTT(cues: captions, segment: first, anchorDate: first.date, anchorPTS: pts), as: UTF8.self)
            precondition(vtt.contains("MPEGTS:\(pts)") && vtt.contains("-->"))
            print("PASS: actual BBC live TTML fragment aligns with its HLS programme date/time and MPEG-TS PTS")
        }
        print("PASS: live subtitle discovery, rolling playlist, discontinuity, TTML extraction, native timestamp mapping and 33-bit wrap")
    }
}
