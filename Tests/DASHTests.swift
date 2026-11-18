import Foundation
@main struct DASHTests {
    static func main() async throws {
        let xml = """
        <MPD type="static" mediaPresentationDuration="PT10S"><Period>
        <AdaptationSet contentType="video" frameRate="25"><SegmentTemplate timescale="1000" duration="4000" startNumber="1" initialization="$RepresentationID$/IS.mp4" media="$RepresentationID$/$Number%06d$.m4s"/>
        <Representation id="video-low" width="1920" height="1080" codecs="hev1.2.4.L150.B0" bandwidth="8000000"/>
        <Representation id="video-high" width="3840" height="2160" codecs="hev1.2.4.L153.B0" bandwidth="24000000"/>
        </AdaptationSet>
        <AdaptationSet contentType="audio" codecs="mp4a.40.2" lang="eng"><SegmentTemplate timescale="1000" duration="4000" initialization="$RepresentationID$/IS.mp4" media="$RepresentationID$/$Number%06d$.m4s"/><Representation id="audio" bandwidth="192000"/></AdaptationSet>
        </Period></MPD>
        """
        let base = URL(string:"https://cdn.example/programme/master.mpd?token=example")!
        let parsed = try DASHManifest.parse(Data(xml.utf8),url:base)
        precondition(parsed.video.height==2160 && parsed.video.width==3840 && parsed.audio.codec=="mp4a.40.2","Select 4K video with separate compatible audio")
        precondition(parsed.video.segments.count==3 && parsed.video.segments.last?.duration==2,"VOD segmentation and final duration")
        precondition(parsed.video.segments[0].url.path=="/programme/video-high/000001.m4s" && parsed.video.segments[0].url.query=="token=example","DASH template formatting and signed query propagation")
        precondition(parsed.video.playlist.contains("#EXT-X-MAP:") && parsed.video.playlist.contains("#EXT-X-ENDLIST"),"fMP4 initialization and VOD playlist")
        precondition(String(decoding:parsed.playlists["/master.m3u8"]!,as:UTF8.self).contains("VIDEO-RANGE=HLG"),"HLG master signalling")
        let timelineXML=xml.replacingOccurrences(of:"duration=\"4000\"",with:"presentationTimeOffset=\"10000\"").replacingOccurrences(of:"media=\"$RepresentationID$/$Number%06d$.m4s\"/>",with:"media=\"$RepresentationID$/$Time$.m4s\"><SegmentTimeline><S t=\"10000\" d=\"4000\" r=\"-1\"/></SegmentTimeline></SegmentTemplate>")
        let timeline=try DASHManifest.parse(Data(timelineXML.utf8),url:base)
        precondition(timeline.video.segments.count==3 && timeline.video.segments[0].url.path.hasSuffix("/10000.m4s"),"Timeline repeats, presentation offset and time template")
        var initialization=Data([0,0,0,19]);initialization.append(Data("colrnclx".utf8));initialization.append(contentsOf:[0,9,0,18,0,9,0])
        precondition(DASHManifest.signalsHLG(initialization),"HLG transfer 18 with BT.2020 primaries")
        var sdr=initialization;sdr[15]=14
        precondition(!DASHManifest.signalsHLG(sdr),"Do not label BT.2020 SDR as HLG")
        let protected=xml.replacingOccurrences(of:"<Period>",with:"<Period><ContentProtection schemeIdUri=\"urn:example\"/>")
        do {_ = try DASHManifest.parse(Data(protected.utf8),url:base);fatalError("Protected presentation accepted")}catch{}
        do {_ = try DASHManifest.parse(Data(xml.replacingOccurrences(of:"type=\"static\"",with:"type=\"dynamic\"").utf8),url:base);fatalError("Dynamic presentation accepted")}catch{}
        let server=LocalHLSServer();let url=try await server.start(playlists:parsed.playlists)
        let (data,response)=try await URLSession.shared.data(from:url)
        precondition((response as? HTTPURLResponse)?.statusCode==200 && String(decoding:data,as:UTF8.self).contains("RESOLUTION=3840x2160"),"Loopback playlist delivery")
        let (_,missing)=try await URLSession.shared.data(from:url.deletingLastPathComponent().appendingPathComponent("private-key.pem"))
        precondition((missing as? HTTPURLResponse)?.statusCode==404,"Loopback server never serves arbitrary files")
        var request = URLRequest(url: url); request.httpMethod = "HEAD"
        let (head, headResponse) = try await URLSession.shared.data(for: request)
        precondition(head.isEmpty && (headResponse as? HTTPURLResponse)?.statusCode == 200, "HEAD does not send a response body")
        request.httpMethod = "GET"; request.setValue("bytes=0-6", forHTTPHeaderField: "Range")
        let (partial, partialResponse) = try await URLSession.shared.data(for: request)
        precondition(partial == Data("#EXTM3U".utf8) && (partialResponse as? HTTPURLResponse)?.statusCode == 206, "HTTP byte-range delivery")
        precondition(LocalHLSServer.byteRange("bytes=-3", count: 10) == 7..<10 && LocalHLSServer.byteRange("bytes=4-", count: 10) == 4..<10, "Suffix and open-ended ranges")
        precondition(LocalHLSServer.byteRange("bytes=10-", count: 10) == nil && LocalHLSServer.byteRange("bytes=0-1,4-5", count: 10) == nil, "Invalid ranges rejected")
        let videoPlaylist = String(decoding: parsed.playlists["/video.m3u8"]!, as: UTF8.self)
        precondition(videoPlaylist.contains("video/init.mp4") && videoPlaylist.contains("video/0.m4s") && !videoPlaylist.contains("https://"), "Every fragment goes through the normalization bridge")
        precondition(parsed.mediaResources["/video/0.m4s"] == parsed.video.segments[0].url, "Bridge allowlist preserves signed CDN URLs")
        server.stop()
        try await fragmentRegressionTests()
        hlgSignallingTests()
        print("PASS: DASH templates/timelines, audio selection, HLG detection, protection checks, loopback HLS/ranges, padded-fragment regression and HLG parameter-set signalling")
    }
}

// Small synthetic boxes exercise the precise failure without bundling BBC media.
private func be(_ value: Int, _ count: Int = 4) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ((count - 1 - $0) * 8)) })
}
private func box(_ type: String, _ payload: Data) -> Data { be(payload.count + 8) + Data(type.utf8) + payload }
private func fragment(padding: Int, extended: Bool = false, toEnd: Bool = false, sample: Data = Data([0x21,0x1a,0x94,0x6d])) -> Data {
    let tfhd = box("tfhd", be(0x020000) + be(1))
    func moof(_ offset: Int) -> Data {
        box("moof", box("mfhd", be(0) + be(18)) + box("traf", tfhd + box("tfdt", be(0x01000000) + be(65280, 8)) + box("trun", be(0x00000201) + be(1) + be(offset) + be(sample.count))))
    }
    let header = extended ? 16 : 8
    let m = moof(moof(0).count + header + padding)
    let payload = Data(repeating: 0xbc, count: padding) + sample
    let media = extended ? be(1) + Data("mdat".utf8) + be(payload.count + 16, 8) + payload : be(toEnd ? 0 : payload.count + 8) + Data("mdat".utf8) + payload
    return m + media
}
private final class FragmentProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "cdn.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // One remote fragment carries a real parameter set; the rest carry opaque sample bytes.
        let data = request.url?.lastPathComponent == "19.m4s" ? fragment(padding: 2, sample: units(bytes(compatibleParameterSet))) : fragment(padding: 2)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private func fragmentRegressionTests() async throws {
    for padding in [0, 2, 16] {
        for extended in [false, true] {
            let corrected = try FMP4Normalizer.normalize(fragment(padding: padding, extended: extended))
            precondition(corrected == fragment(padding: 0, extended: extended), "Remove padding, fix mdat size and trun offset, preserve encoded samples")
            let again = try FMP4Normalizer.normalize(corrected)
            precondition(again == corrected, "Normalization is idempotent")
        }
    }
    let sizeToEnd = try FMP4Normalizer.normalize(fragment(padding: 2, toEnd: true))
    precondition(sizeToEnd == fragment(padding: 0, toEnd: true), "Size-to-end mdat")
    for invalid in [Data([0, 1, 2]), fragment(padding: 4097), Data(fragment(padding: 2).dropLast())] {
        do { _ = try FMP4Normalizer.normalize(invalid); fatalError("Malformed fragment accepted") } catch {}
    }
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FragmentProtocol.self]
    let server = LocalHLSServer(configuration: configuration)
    let master = try await server.start(playlists: [:], media: ["/video/18.m4s": URL(string: "https://cdn.example/video/18.m4s?token=test")!,
                                                                "/video/19.m4s": URL(string: "https://cdn.example/video/19.m4s?token=test")!,
                                                                "/audio/19.m4s": URL(string: "https://cdn.example/audio/19.m4s?token=test")!])
    let url = master.deletingLastPathComponent().appendingPathComponent("video/18.m4s")
    let (normalized, response) = try await URLSession.shared.data(from: url)
    precondition((response as? HTTPURLResponse)?.statusCode == 200 && normalized == fragment(padding: 0), "Real bridge normalizes remote fragments")
    var request = URLRequest(url: url); request.setValue("bytes=0-15", forHTTPHeaderField: "Range")
    let (partial, partialResponse) = try await URLSession.shared.data(for: request)
    precondition((partialResponse as? HTTPURLResponse)?.statusCode == 206 && partial == normalized.prefix(16), "Ranges apply after normalization")
    let promotedSet = bytes(compatibleParameterSet.replacingOccurrences(of: "848704", with: "848904"))
    let (video, _) = try await URLSession.shared.data(from: master.deletingLastPathComponent().appendingPathComponent("video/19.m4s"))
    precondition(video == fragment(padding: 0, sample: units(promotedSet)), "Real bridge declares HLG in served video fragments, after normalization")
    let (audio, _) = try await URLSession.shared.data(from: master.deletingLastPathComponent().appendingPathComponent("audio/19.m4s"))
    precondition(audio == fragment(padding: 0, sample: units(bytes(compatibleParameterSet))), "Only video fragments are rewritten")
    server.stop()
}
/// Length-prefixed units as they sit in a fragment: access unit delimiter, parameter set, then a slice.
private func units(_ parameterSet: [UInt8]) -> Data {
    func unit(_ payload: [UInt8]) -> Data { be(payload.count) + Data(payload) }
    return unit([0x46, 0x01, 0x50]) + unit(parameterSet) + unit([0x26, 0x01, 0xaf, 0x09, 0x40, 0x87, 0x04, 0xdb])
}

/// A BBC UHD sequence parameter set: 3840 x 2160, 10-bit, BT.2020 primaries with the
/// SDR-compatible transfer function (14). It holds stream configuration only, no picture data.
private let compatibleParameterSet = "420101022000000300900000030000030099a001e020021c4d966626491b4bc050848704db0800001f4000030d4040"
private func bytes(_ hex: String) -> [UInt8] { stride(from: 0, to: hex.count, by: 2).map { UInt8(hex.dropFirst($0).prefix(2), radix: 16)! } }
private func hlgSignallingTests() {
    let original = bytes(compatibleParameterSet)
    // transfer_characteristics starts one bit into the 0x87: 14 becomes 18 by changing that byte alone.
    let expected = bytes(compatibleParameterSet.replacingOccurrences(of: "848704", with: "848904"))
    guard let promoted = HLGSignalling.promote(sequenceParameterSet: original) else { fatalError("Compatible HLG parameter set was not promoted") }
    precondition(promoted == expected, "Only the transfer function changes, in place, keeping emulation prevention bytes")
    precondition(HLGSignalling.promote(sequenceParameterSet: promoted) == nil, "A parameter set already declaring HLG is left alone")
    for unreadable in [[UInt8](), Array(original.prefix(20)), Array(original.dropLast(12)), [UInt8](repeating: 0, count: 47), [UInt8](repeating: 0xff, count: 47)] {
        precondition(HLGSignalling.promote(sequenceParameterSet: unreadable) == nil, "Truncated or unreadable parameter sets are left alone")
    }
    var otherPrimaries = original; otherPrimaries[33] ^= 0x02 // colour_primaries 9 becomes 13
    precondition(HLGSignalling.promote(sequenceParameterSet: otherPrimaries) == nil, "Only BT.2020 video is promoted")

    // A fragment is a run of length-prefixed units: access unit delimiter, parameter set, then a slice.
    func unit(_ payload: [UInt8]) -> Data { be(payload.count) + Data(payload) }
    let delimiter: [UInt8] = [0x46, 0x01, 0x50], slice: [UInt8] = [0x26, 0x01, 0xaf, 0x09, 0x40, 0x87, 0x04, 0xdb]
    func video(_ parameterSet: [UInt8], trailing: Data = Data()) -> Data {
        box("moof", box("mfhd", be(0) + be(1))) + box("mdat", unit(delimiter) + unit(parameterSet) + unit(slice) + trailing)
    }
    precondition(HLGSignalling.promote(video(original)) == video(expected), "Every parameter set in a fragment is promoted; other units are untouched")
    precondition(HLGSignalling.promote(video(expected)) == video(expected), "Promotion is idempotent")
    // BBC's packager leaves six unreferenced bytes after the last sample of some fragments.
    for tail in [Data("BBC RD".utf8), Data([0, 0, 0]), Data([0, 0, 0, 1, 0x42, 0x01, 0x01])] {
        precondition(HLGSignalling.promote(video(original, trailing: tail)) == video(expected, trailing: tail), "An unreferenced tail does not stop the rewrite, and is preserved")
    }
    let leading = box("moof", box("mfhd", be(0) + be(1))) + box("mdat", Data("BBC RD".utf8) + unit(original))
    precondition(HLGSignalling.promote(leading) == leading, "Bytes that are not units are never searched for parameter sets")
    precondition(HLGSignalling.promote(fragment(padding: 0)) == fragment(padding: 0), "Fragments without parameter sets are unchanged")
    let truncated = Data(video(original).dropLast())
    precondition(HLGSignalling.promote(truncated) == truncated, "Malformed fragments are returned unchanged")
}
