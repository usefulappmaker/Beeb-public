// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

final class DASHNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [DASHNode] = []
    init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
    func child(_ name: String) -> DASHNode? { children.first { $0.name == name } }
}
final class DASHXML: NSObject, XMLParserDelegate {
    var root: DASHNode?
    var stack: [DASHNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = DASHNode(elementName.components(separatedBy: ":").last!, attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
}
struct DASHSegment { let url: URL; let duration: Double }
struct DASHTrack {
    let initialization: URL
    let segments: [DASHSegment]
    let codec: String
    let bandwidth: Int
    let width: Int
    let height: Int
    let frameRate: Double
    var playlist: String { playlist(initializationURI: initialization.absoluteString, segmentURIs: segments.map { $0.url.absoluteString }) }
    func playlist(initializationURI: String, segmentURIs: [String]) -> String {
        let target = Int(ceil(segments.map(\.duration).max() ?? 4))
        var text = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:\(max(1, target))\n#EXT-X-MEDIA-SEQUENCE:1\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MAP:URI=\"\(initializationURI)\"\n"
        for (index, segment) in segments.enumerated() { text += String(format: "#EXTINF:%.6f,\n", locale: Locale(identifier: "en_US_POSIX"), segment.duration) + segmentURIs[index] + "\n" }
        return text + "#EXT-X-ENDLIST\n"
    }
}
struct DASHManifest {
    let video: DASHTrack
    let audio: DASHTrack
    var playlists: [String: Data] {
        let bandwidth = video.bandwidth + audio.bandwidth
        let master = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"English\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"en\",URI=\"audio.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth),RESOLUTION=\(video.width)x\(video.height),FRAME-RATE=\(video.frameRate),CODECS=\"\(video.codec),\(audio.codec)\",VIDEO-RANGE=HLG,AUDIO=\"audio\"\nvideo.m3u8\n"
        return ["/master.m3u8": Data(master.utf8), "/video.m3u8": Data(video.playlist(initializationURI: "video/init.mp4", segmentURIs: video.segments.indices.map { "video/\($0).m4s" }).utf8), "/audio.m3u8": Data(audio.playlist(initializationURI: "audio/init.mp4", segmentURIs: audio.segments.indices.map { "audio/\($0).m4s" }).utf8)]
    }
    var mediaResources: [String: URL] {
        var resources = [String: URL]()
        for (name, track) in [("video", video), ("audio", audio)] {
            resources["/\(name)/init.mp4"] = track.initialization
            for (index, segment) in track.segments.enumerated() { resources["/\(name)/\(index).m4s"] = segment.url }
        }
        return resources
    }
    static func signalsHLG(_ data: Data) -> Bool {
        let bytes = Array(data)
        guard bytes.count >= 18 else { return false }
        for i in 4..<(bytes.count - 13) where Array(bytes[i..<i+4]) == Array("colr".utf8) {
            let colourType = String(bytes: bytes[i+4..<i+8], encoding: .ascii)
            if colourType == "nclx" || colourType == "nclc" {
                let primaries = Int(bytes[i+8]) * 256 + Int(bytes[i+9])
                let transfer = Int(bytes[i+10]) * 256 + Int(bytes[i+11])
                if primaries == 9 && transfer == 18 { return true }
            }
        }
        return false
    }
    static func parse(_ data: Data, url: URL) throws -> DASHManifest {
        let delegate = DASHXML(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), let root = delegate.root, root.name == "MPD", root.attributes["type"] != "dynamic" else {
            throw BBCError.message("The UHD manifest is not a supported on-demand DASH presentation.")
        }
        func containsProtection(_ node: DASHNode) -> Bool { node.name == "ContentProtection" || node.children.contains(where: containsProtection) }
        guard !containsProtection(root) else { throw BBCError.message("This UHD stream requires a separately supported content licence.") }
        let periods = root.children.filter { $0.name == "Period" }
        guard periods.count == 1, let period = periods.first else { throw BBCError.message("Multi-period UHD presentations are not supported yet.") }
        func seconds(_ input: String) -> Double? {
            guard let regex = try? NSRegularExpression(pattern: "^PT(?:(\\d+(?:\\.\\d+)?)H)?(?:(\\d+(?:\\.\\d+)?)M)?(?:(\\d+(?:\\.\\d+)?)S)?$"), let m = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
            var value = 0.0
            for (i, factor) in [(1,3600.0),(2,60.0),(3,1.0)] { if let range = Range(m.range(at: i), in: input) { value += (Double(input[range]) ?? 0) * factor } }
            return value > 0 ? value : nil
        }
        guard let duration = seconds(period.attributes["duration"] ?? root.attributes["mediaPresentationDuration"] ?? ""), duration < 86400 else { throw BBCError.message("Missing UHD presentation duration.") }
        func base(_ node: DASHNode, parent: URL) throws -> URL {
            guard let reference = node.child("BaseURL")?.text.trimmingCharacters(in: .whitespacesAndNewlines), !reference.isEmpty else { return parent }
            guard let result = BBCService.resolve(reference, base: parent) else { throw BBCError.message("Invalid UHD media URL.") }; return result
        }
        let rootURL = try base(root, parent: url), periodURL = try base(period, parent: rootURL)
        struct Candidate { let adaptation: DASHNode; let representation: DASHNode; let base: URL }
        var videos = [Candidate](), audios = [Candidate]()
        for adaptation in period.children where adaptation.name == "AdaptationSet" {
            let adaptationURL = try base(adaptation, parent: periodURL)
            let type = adaptation.attributes["contentType"] ?? adaptation.attributes["mimeType"] ?? ""
            for representation in adaptation.children where representation.name == "Representation" {
                let candidate = Candidate(adaptation: adaptation, representation: representation, base: try base(representation, parent: adaptationURL))
                let codec = representation.attributes["codecs"] ?? adaptation.attributes["codecs"] ?? ""
                if type.contains("video"), Int(representation.attributes["height"] ?? adaptation.attributes["height"] ?? "0") ?? 0 >= 2160, codec.hasPrefix("hev1.") || codec.hasPrefix("hvc1.") { videos.append(candidate) }
                if type.contains("audio"), codec.hasPrefix("mp4a."), [nil,"en","eng"].contains(adaptation.attributes["lang"]) { audios.append(candidate) }
            }
        }
        func score(_ candidate: Candidate) -> Int { Int(candidate.representation.attributes["bandwidth"] ?? "0") ?? 0 }
        guard let video = videos.max(by: { score($0) < score($1) }), let audio = audios.max(by: { score($0) < score($1) }) else { throw BBCError.message("No 2160p HEVC video with compatible English audio was found.") }
        func track(_ candidate: Candidate) throws -> DASHTrack {
            let a = candidate.adaptation, r = candidate.representation
            let templates = [root.child("SegmentTemplate"), period.child("SegmentTemplate"), a.child("SegmentTemplate"), r.child("SegmentTemplate")].compactMap { $0 }
            var attributes = [String: String]()
            for template in templates { attributes.merge(template.attributes) { _, new in new } }
            guard let media = attributes["media"], let initialization = attributes["initialization"], let representationID = r.attributes["id"] else { throw BBCError.message("Unsupported UHD segment addressing.") }
            let timescale = Double(attributes["timescale"] ?? "1") ?? 1
            guard timescale > 0 else { throw BBCError.message("Invalid UHD timescale.") }
            let start = Int64(attributes["startNumber"] ?? "1") ?? 1
            let presentationOffset = Int64(attributes["presentationTimeOffset"] ?? "0") ?? 0
            let bandwidth = r.attributes["bandwidth"] ?? a.attributes["bandwidth"] ?? "0"
            func expand(_ template: String, number: Int64, time: Int64) throws -> URL {
                var value = template.replacingOccurrences(of: "$$", with: "__DOLLAR__").replacingOccurrences(of: "$RepresentationID$", with: representationID).replacingOccurrences(of: "$Bandwidth$", with: bandwidth)
                let regex = try NSRegularExpression(pattern: "\\$(Number|Time)(?:%0(\\d+)d)?\\$")
                for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                    guard let range = Range(match.range, in: value), let nameRange = Range(match.range(at: 1), in: value) else { continue }
                    let numeric = value[nameRange] == "Number" ? number : time
                    let width = Range(match.range(at: 2), in: value).flatMap { Int(value[$0]) } ?? 0
                    guard width <= 20 else { throw BBCError.message("Invalid UHD segment number format.") }
                    let numberText = String(numeric)
                    value.replaceSubrange(range, with: String(repeating: "0", count: max(0, width - numberText.count)) + numberText)
                }
                value = value.replacingOccurrences(of: "__DOLLAR__", with: "$")
                guard !value.contains("\""), !value.contains("\n"), let url = BBCService.resolve(value, base: candidate.base) else { throw BBCError.message("Invalid UHD segment URL.") }; return url
            }
            var intervals = [(Int64, Double)]()
            if let timeline = templates.reversed().compactMap({ $0.child("SegmentTimeline") }).first {
                var time: Int64 = 0
                let entries = timeline.children.filter { $0.name == "S" }
                for (index, entry) in entries.enumerated() {
                    if let explicit = entry.attributes["t"].flatMap(Int64.init) { time = explicit }
                    guard let step = entry.attributes["d"].flatMap(Int64.init), step > 0 else { throw BBCError.message("Invalid UHD segment timeline.") }
                    let repeats = Int(entry.attributes["r"] ?? "0") ?? 0
                    let limit = index + 1 < entries.count ? entries[index + 1].attributes["t"].flatMap(Int64.init) : nil
                    let count = repeats >= 0 ? repeats + 1 : Int(ceil(Double((limit ?? (Int64(duration * timescale) + presentationOffset)) - time) / Double(step)))
                    guard count > 0, count < 100000, intervals.count + count < 100000 else { throw BBCError.message("Unsupported UHD segment count.") }
                    for _ in 0..<count { intervals.append((time, Double(step) / timescale)); time += step }
                }
            } else {
                guard let ticks = Double(attributes["duration"] ?? ""), ticks > 0 else { throw BBCError.message("Missing UHD segment duration.") }
                let step = ticks / timescale, count = Int(ceil(duration / step))
                guard count > 0, count < 100000 else { throw BBCError.message("Unsupported UHD segment count.") }
                for i in 0..<count { intervals.append((Int64(Double(i) * ticks), min(step, duration - Double(i) * step))) }
            }
            let segments = try intervals.enumerated().map { DASHSegment(url: try expand(media, number: start + Int64($0.offset), time: $0.element.0), duration: $0.element.1) }
            guard !segments.isEmpty else { throw BBCError.message("Empty UHD presentation.") }
            let frameRateText = r.attributes["frameRate"] ?? a.attributes["frameRate"] ?? "25"
            let rate = frameRateText.split(separator: "/").compactMap { Double($0) }
            let frameRate = rate.count == 2 && rate[1] != 0 ? rate[0] / rate[1] : rate.first ?? 25
            return DASHTrack(initialization: try expand(initialization, number: start, time: 0), segments: segments,
                codec: r.attributes["codecs"] ?? a.attributes["codecs"] ?? "", bandwidth: Int(bandwidth) ?? 0,
                width: Int(r.attributes["width"] ?? a.attributes["width"] ?? "0") ?? 0, height: Int(r.attributes["height"] ?? a.attributes["height"] ?? "0") ?? 0, frameRate: frameRate)
        }
        return try DASHManifest(video: track(video), audio: track(audio))
    }
}
