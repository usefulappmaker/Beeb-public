// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The single-period HEVC/AAC live DASH subset used by BBC event feeds.
/// Media stays encoded; AVPlayer receives rolling HLS playlists on loopback.
struct LiveDASHSnapshot {
    let playlists: [String: Data]
    let media: [String: URL]
    let videoInitialization: URL
    let latestVideo: URL
    let latestAudio: URL
    let identity: String
    let refreshInterval: Double
}
struct LiveDASHManifest {
    let root: DASHNode
    let url: URL
    init(_ data: Data, url: URL) throws {
        let delegate = DASHXML(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard data.count <= 2_000_000, parser.parse(), let root = delegate.root,
              root.name == "MPD", root.attributes["type"] == "dynamic" else {
            throw BBCError.message("BBC has not returned a supported live UHD presentation.")
        }
        func protected(_ node: DASHNode) -> Bool { node.name == "ContentProtection" || node.children.contains(where: protected) }
        guard !protected(root) else { throw BBCError.message("This live UHD stream requires a separately supported content licence.") }
        self.root = root; self.url = url
    }
    static func seconds(_ raw: String?) -> Double? {
        guard let raw, let re = try? NSRegularExpression(pattern: "^P(?:(\\d+(?:\\.\\d+)?)D)?(?:T(?:(\\d+(?:\\.\\d+)?)H)?(?:(\\d+(?:\\.\\d+)?)M)?(?:(\\d+(?:\\.\\d+)?)S)?)?$"),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) else { return nil }
        var value = 0.0
        for (i, factor) in [(1,86400.0),(2,3600.0),(3,60.0),(4,1.0)] {
            if let r = Range(m.range(at:i), in:raw) { value += (Double(raw[r]) ?? 0) * factor }
        }
        return value.isFinite ? value : nil
    }
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        return f.date(from:raw) ?? ISO8601DateFormatter().date(from:raw)
    }
    func snapshot(now: Date = Date(), videoRange: String = "HLG") throws -> LiveDASHSnapshot {
        let periods = root.children.filter { $0.name == "Period" }
        guard periods.count == 1, let period = periods.first,
              let epoch = Self.date(root.attributes["availabilityStartTime"]) else {
            throw BBCError.message("This live UHD event uses an unsupported timing layout.")
        }
        let periodStart = Self.seconds(period.attributes["start"]) ?? 0
        let age = now.timeIntervalSince(epoch) - periodStart
        let end = Self.seconds(period.attributes["duration"]) ?? Self.seconds(root.attributes["mediaPresentationDuration"]).map { $0 - periodStart }
        guard age >= 0, end.map({ age <= $0 + 90 }) ?? true else {
            throw BBCError.message("Red Button UHD is currently off air. Try again during a BBC UHD event.")
        }
        let delay = max(4, min(30, Self.seconds(root.attributes["minBufferTime"]) ?? 10))
        let edge = min(age - delay, end ?? age)
        let depth = min(300, Self.seconds(root.attributes["timeShiftBufferDepth"]) ?? 300)
        guard edge > 0, depth > delay else { throw BBCError.message("The UHD event has not started streaming yet.") }
        let retainFrom = max(0, age - depth)
        let displayFrom = max(retainFrom, edge - 180)
        func base(_ node: DASHNode, parent: URL) throws -> URL {
            let reference = node.child("BaseURL")?.text.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
            if reference.isEmpty { return parent }
            guard let u = BBCService.resolve(reference, base:parent) else { throw BBCError.message("Invalid live media URL.") }
            return u
        }
        let periodURL = try base(period, parent:base(root,parent:url))
        struct Candidate { let adaptation: DASHNode; let representation: DASHNode; let url: URL }
        var videos = [Candidate](), audios = [Candidate]()
        for a in period.children where a.name == "AdaptationSet" {
            let aURL = try base(a,parent:periodURL)
            let type = a.attributes["contentType"] ?? a.attributes["mimeType"] ?? ""
            for r in a.children where r.name == "Representation" {
                let c = Candidate(adaptation:a,representation:r,url:try base(r,parent:aURL))
                let codec = r.attributes["codecs"] ?? a.attributes["codecs"] ?? ""
                if type.contains("video"), (Int(r.attributes["height"] ?? "0") ?? 0) >= 2160,
                   codec.hasPrefix("hev1.") || codec.hasPrefix("hvc1.") { videos.append(c) }
                let mainAudio = !a.children.contains { $0.name == "Role" && ["description","alternate","commentary"].contains($0.attributes["value"] ?? "") }
                if type.contains("audio"), codec.hasPrefix("mp4a."), [nil,"en","eng","en-GB"].contains(a.attributes["lang"]), mainAudio { audios.append(c) }
            }
        }
        func bandwidth(_ c: Candidate) -> Int { Int(c.representation.attributes["bandwidth"] ?? "0") ?? 0 }
        guard let v = videos.max(by:{ bandwidth($0) < bandwidth($1) }), let a = audios.max(by:{ bandwidth($0) < bandwidth($1) }) else {
            throw BBCError.message("This event has no compatible 4K video and English audio.")
        }
        var resources = [String:URL]()
        struct Track { let playlist: String; let initialization: URL; let latest: URL; let codec: String; let id: String }
        func track(_ c: Candidate, name: String) throws -> Track {
            let r = c.representation
            guard let id = r.attributes["id"], id.range(of:"^[A-Za-z0-9_.-]{1,80}$",options:.regularExpression) != nil else { throw BBCError.message("Invalid live representation.") }
            let templates = [root.child("SegmentTemplate"),period.child("SegmentTemplate"),c.adaptation.child("SegmentTemplate"),r.child("SegmentTemplate")].compactMap { $0 }
            var attrs = [String:String]()
            for t in templates { attrs.merge(t.attributes) { _,new in new } }
            guard let media = attrs["media"], let initialization = attrs["initialization"],
                  let scale = Double(attrs["timescale"] ?? "1"), scale > 0, scale <= 1_000_000_000,
                  let start = Int64(attrs["startNumber"] ?? "1"), start >= 0, start < Int64.max - 10_000_001,
                  let offset = Double(attrs["presentationTimeOffset"] ?? "0"), offset.isFinite, offset >= 0, offset < Double(Int64.max)-4096 else { throw BBCError.message("Unsupported live segment addressing.") }
            func expand(_ template: String, number: Int64, time: Double) throws -> URL {
                guard time.isFinite, time >= 0, time < Double(Int64.max)-4096 else { throw BBCError.message("Invalid live segment time.") }
                var value = template.replacingOccurrences(of:"$RepresentationID$",with:id).replacingOccurrences(of:"$Bandwidth$",with:String(bandwidth(c)))
                let re = try NSRegularExpression(pattern:"\\$(Number|Time)(?:%0(\\d+)d)?\\$")
                for match in re.matches(in:value,range:NSRange(value.startIndex...,in:value)).reversed() {
                    guard let range = Range(match.range,in:value), let token = Range(match.range(at:1),in:value) else { continue }
                    let n = value[token] == "Number" ? number : Int64(time.rounded())
                    let width = Range(match.range(at:2),in:value).flatMap { Int(value[$0]) } ?? 0
                    guard width <= 20 else { throw BBCError.message("Invalid live segment format.") }
                    let digits = String(n)
                    value.replaceSubrange(range,with:String(repeating:"0",count:max(0,width-digits.count))+digits)
                }
                guard !value.contains("$"), !value.contains("\n"), !value.contains("\r"), !value.contains("\""),
                      let result = BBCService.resolve(value,base:c.url) else { throw BBCError.message("Invalid live segment URL.") }
                return result
            }
            // Calculate the available interval without enumerating the event's entire history.
            var points = [(number:Int64,time:Double,start:Double,duration:Double)]()
            func appendRun(time:Double, ticks:Double, count:Int, ordinal:Int64) throws {
                guard time.isFinite, time >= 0, time < Double(Int64.max)-4096, ticks > 0, ticks.isFinite, count > 0, count <= 10_000_000 else { throw BBCError.message("Invalid live segment timeline.") }
                let step = ticks/scale, firstStart = (time-offset)/scale
                guard step >= 0.1, step <= 60 else { throw BBCError.message("Unsupported live segment duration.") }
                let lower = max(0,floor((retainFrom-firstStart)/step))
                let upper = min(Double(count-1),floor((edge-firstStart)/step)-1)
                if upper < lower { return }
                guard lower.isFinite, upper.isFinite, lower >= 0, upper < Double(count) else { throw BBCError.message("Invalid live window.") }
                let lo = Int(lower), hi = Int(upper)
                guard hi-lo < 3100 else { throw BBCError.message("Live window is too large.") }
                for i in lo...hi {
                    let number = start + ordinal + Int64(i)
                    guard number >= start else { throw BBCError.message("Live sequence overflow.") }
                    points.append((number,time+Double(i)*ticks,firstStart+Double(i)*step,step))
                }
            }
            if let timeline = templates.reversed().compactMap({ $0.child("SegmentTimeline") }).first {
                var time = 0.0, ordinal:Int64 = 0
                let entries = timeline.children.filter { $0.name == "S" }
                guard entries.count <= 10000 else { throw BBCError.message("Live timeline is too large.") }
                for (i,s) in entries.enumerated() {
                    time = s.attributes["t"].flatMap(Double.init) ?? time
                    guard let ticks = s.attributes["d"].flatMap(Double.init), ticks > 0, ticks.isFinite,
                          let repeats = Int(s.attributes["r"] ?? "0"), repeats >= -1, repeats < 10_000_000 else { throw BBCError.message("Invalid live timeline repeat.") }
                    let next = i+1 < entries.count ? entries[i+1].attributes["t"].flatMap(Double.init) : nil
                    let limit = next ?? (offset + min(edge,end ?? edge)*scale)
                    let total = repeats >= 0 ? Double(repeats)+1 : max(1,ceil((limit-time)/ticks))
                    guard total.isFinite, total > 0, total <= 10_000_000 else { throw BBCError.message("Live repeat is too large.") }
                    let count = Int(total)
                    try appendRun(time:time,ticks:ticks,count:count,ordinal:ordinal)
                    ordinal += Int64(count);time += Double(count)*ticks
                }
            } else {
                guard let ticks = attrs["duration"].flatMap(Double.init), ticks > 0, ticks.isFinite else { throw BBCError.message("Missing live segment duration.") }
                let total = ceil(max(0,edge)*scale/ticks)+1
                guard total.isFinite, total > 0, total <= 10_000_000 else { throw BBCError.message("Live timeline is too large.") }
                let count = Int(total)
                try appendRun(time:offset,ticks:ticks,count:count,ordinal:0)
            }
            let shown = points.filter { $0.start + $0.duration > displayFrom }
            guard shown.count >= 3, let first = shown.first, let last = shown.last else { throw BBCError.message("Red Button UHD is off air or still starting. Please try again later.") }
            let initURL = try expand(initialization,number:start,time:offset)
            let initPath = "\(name)/\(id)-init.mp4"
            resources["/"+initPath] = initURL
            for s in points { resources["/\(name)/\(s.number).m4s"] = try expand(media,number:s.number,time:s.time) }
            let target = max(1,Int(ceil(shown.map(\.duration).max() ?? 4)))
            var list = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:\(target)\n#EXT-X-MEDIA-SEQUENCE:\(first.number)\n#EXT-X-MAP:URI=\"\(initPath)\"\n"
            let date = ISO8601DateFormatter();date.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
            for s in shown {
                list += "#EXT-X-PROGRAM-DATE-TIME:\(date.string(from:epoch.addingTimeInterval(periodStart+s.start)))\n"
                list += String(format:"#EXTINF:%.6f,\n",locale:Locale(identifier:"en_US_POSIX"),s.duration)+"\(name)/\(s.number).m4s\n"
            }
            return Track(playlist:list,initialization:initURL,latest:try expand(media,number:last.number,time:last.time),codec:r.attributes["codecs"] ?? c.adaptation.attributes["codecs"] ?? "",id:id)
        }
        let video = try track(v,name:"video"), audio = try track(a,name:"audio")
        let frame = (v.representation.attributes["frameRate"] ?? v.adaptation.attributes["frameRate"] ?? "50").split(separator:"/").compactMap { Double($0) }
        let rate = frame.count == 2 && frame[1] > 0 ? frame[0]/frame[1] : frame.first ?? 50
        guard rate.isFinite, rate > 0, rate <= 120 else { throw BBCError.message("Invalid live frame rate.") }
        let width = Int(v.representation.attributes["width"] ?? "3840") ?? 3840, height = Int(v.representation.attributes["height"] ?? "2160") ?? 2160
        let master = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"English\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"en\",URI=\"audio.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=\(bandwidth(v)+bandwidth(a)),RESOLUTION=\(width)x\(height),FRAME-RATE=\(rate),CODECS=\"\(video.codec),\(audio.codec)\",VIDEO-RANGE=\(videoRange),AUDIO=\"audio\"\nvideo.m3u8\n"
        return LiveDASHSnapshot(playlists:["/master.m3u8":Data(master.utf8),"/video.m3u8":Data(video.playlist.utf8),"/audio.m3u8":Data(audio.playlist.utf8)],media:resources,videoInitialization:video.initialization,latestVideo:video.latest,latestAudio:audio.latest,identity:"\(root.attributes["availabilityStartTime"] ?? "")|\(period.attributes["id"] ?? "")|\(video.id)|\(audio.id)",refreshInterval:max(2,min(30,Self.seconds(root.attributes["minimumUpdatePeriod"]) ?? 10)))
    }
}

@MainActor final class LiveUHDPlaybackAccess {
    private var server: LocalHLSServer?
    private var refresh: Task<Void,Never>?
    private let fetch: (URL) async throws -> Data
    init(fetch: @escaping (URL) async throws -> Data = { try await BBCService().fetch($0) }) { self.fetch = fetch }
    func source(manifestURL: URL = AdditionalLiveStream.uhdManifest) async throws -> PlaybackSource {
        stop()
        var manifest = try LiveDASHManifest(await fetch(manifestURL),url:manifestURL)
        let initial = try manifest.snapshot()
        let initData = try await fetch(initial.videoInitialization)
        // Do not advertise HLG unless the encoded media actually signals it.
        guard initData.count <= 4_000_000, DASHManifest.signalsHLG(initData) else { throw BBCError.message("This live UHD event does not provide a supported HLG stream.") }
        let video = try await fetch(initial.latestVideo), audio = try await fetch(initial.latestAudio)
        guard video.count <= 64_000_000, audio.count <= 8_000_000 else { throw BBCError.message("Unsupported live media size.") }
        try await Task.detached(priority:.userInitiated) {
            _ = try FMP4Normalizer.normalize(video);_ = try FMP4Normalizer.normalize(audio)
        }.value
        try Task.checkCancellation()
        let bridge = LocalHLSServer();server = bridge
        let url = try await bridge.start(playlists:initial.playlists,media:initial.media)
        var checked = Date()
        refresh = Task { [fetch] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds:2_000_000_000)
                    if Date().timeIntervalSince(checked) >= initial.refreshInterval {
                        let replacement = try LiveDASHManifest(await fetch(manifestURL),url:manifestURL)
                        guard try replacement.snapshot().identity == initial.identity else { throw BBCError.message("The live event changed. Select Red Button UHD again.") }
                        manifest = replacement;checked = Date()
                    }
                    let current = try manifest.snapshot()
                    bridge.update(playlists:current.playlists,media:current.media)
                }
            } catch { if !Task.isCancelled { bridge.stop() } }
        }
        return PlaybackSource(url:url,requested1080:true,requestedHeight:2160,videoRange:"HLG")
    }
    func stop() { refresh?.cancel();refresh = nil;server?.stop();server = nil }
    deinit { refresh?.cancel();server?.stop() }
}
