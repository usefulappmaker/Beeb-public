// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
@main struct LiveDASHTests {
    static func main() async throws {
        let xml = """
        <MPD type="dynamic" availabilityStartTime="2026-10-21T12:00:00Z" minimumUpdatePeriod="PT8H" minBufferTime="PT10S" timeShiftBufferDepth="PT25H"><Period id="event" start="PT0S">
        <AdaptationSet contentType="video"><Representation id="v1" width="3840" height="2160" bandwidth="18000000" codecs="hev1.2.4.L153.B0" frameRate="50"><SegmentTemplate timescale="1000" duration="4000" startNumber="100" presentationTimeOffset="8000" initialization="$RepresentationID$/init.mp4" media="$RepresentationID$/$Number$.m4s"/></Representation></AdaptationSet>
        <AdaptationSet contentType="audio" codecs="mp4a.40.2" lang="en"><Representation id="a1" bandwidth="320000"><SegmentTemplate timescale="1000" duration="4000" startNumber="100" presentationTimeOffset="8000" initialization="$RepresentationID$/init.mp4" media="$RepresentationID$/$Number$.m4s"/></Representation></AdaptationSet>
        </Period></MPD>
        """
        let base = URL(string:"https://bbc.example/event/master.mpd?auth=fixture")!
        let now = LiveDASHManifest.date("2026-10-21T12:10:00Z")!
        let manifest = try LiveDASHManifest(Data(xml.utf8),url:base)
        let first = try manifest.snapshot(now:now), next = try manifest.snapshot(now:now.addingTimeInterval(8))
        let video = String(decoding:first.playlists["/video.m3u8"]!,as:UTF8.self)
        let second = String(decoding:next.playlists["/video.m3u8"]!,as:UTF8.self)
        precondition(video.contains("#EXT-X-MEDIA-SEQUENCE:202\n") && second.contains("#EXT-X-MEDIA-SEQUENCE:204\n"),"Stable live sequences advance with the clock")
        precondition(!video.contains("ENDLIST") && !video.contains("PLAYLIST-TYPE:VOD"),"Live playlists remain open")
        precondition(first.latestVideo.lastPathComponent == "246.m4s" && next.latestVideo.lastPathComponent == "248.m4s","Only fully available segments behind the live edge are referenced")
        precondition(first.media["/video/230.m4s"] == next.media["/video/230.m4s"],"Old playlist requests keep the same media identity after refresh")
        precondition(first.media.count < 160 && first.refreshInterval == 30,"Bounded retained window and refresh interval")
        precondition(first.latestVideo.query == "auth=fixture" && video.contains("#EXT-X-PROGRAM-DATE-TIME:"),"Authentication query and A/V wall-clock alignment retained")
        precondition(String(decoding:first.playlists["/master.m3u8"]!,as:UTF8.self).contains("RESOLUTION=3840x2160,FRAME-RATE=50.0"),"Native master advertises encoded 4K 50fps")
        let timeline = xml.replacingOccurrences(of:"duration=\"4000\" ",with:"").replacingOccurrences(of:"media=\"$RepresentationID$/$Number$.m4s\"/>",with:"media=\"$RepresentationID$/$Time$.m4s\"><SegmentTimeline><S t=\"8000\" d=\"4000\" r=\"-1\"/></SegmentTimeline></SegmentTemplate>")
        let timed = try LiveDASHManifest(Data(timeline.utf8),url:base).snapshot(now:now)
        precondition(timed.latestVideo.lastPathComponent == "592000.m4s","Timeline $Time$ includes presentation offset")
        let stale = xml.replacingOccurrences(of:"<MPD ",with:"<MPD mediaPresentationDuration=\"PT100S\" ")
        do { _ = try LiveDASHManifest(Data(stale.utf8),url:base).snapshot(now:now); fatalError("Ended event accepted as live") } catch {}
        let protected = xml.replacingOccurrences(of:"<Period ",with:"<ContentProtection/><Period ")
        do { _ = try LiveDASHManifest(Data(protected.utf8),url:base);fatalError("Protected media accepted") } catch {}
        do { _ = try manifest.snapshot(now:now.addingTimeInterval(-590));fatalError("Starting event lacks a safe buffer") } catch {}
        let multi = xml.replacingOccurrences(of:"</MPD>",with:"<Period id=\"second\"/></MPD>")
        do { _ = try LiveDASHManifest(Data(multi.utf8),url:base).snapshot(now:now);fatalError("Unimplemented period transition accepted") } catch {}
        let badSequence = xml.replacingOccurrences(of:"startNumber=\"100\"",with:"startNumber=\"9223372036854775807\"")
        do { _ = try LiveDASHManifest(Data(badSequence.utf8),url:base).snapshot(now:now);fatalError("Overflowing sequence accepted") } catch {}
        let badTime = timeline.replacingOccurrences(of:"t=\"8000\"",with:"t=\"1e300\"")
        do { _ = try LiveDASHManifest(Data(badTime.utf8),url:base).snapshot(now:now);fatalError("Overflowing timeline accepted") } catch {}
        let server = LocalHLSServer()
        let url = try await server.start(playlists:first.playlists,media:first.media)
        let playlistURL = url.deletingLastPathComponent().appendingPathComponent("video.m3u8")
        let (old,_) = try await URLSession.shared.data(from:playlistURL)
        precondition(old == first.playlists["/video.m3u8"],"Initial live playlist delivered")
        server.update(playlists:next.playlists,media:next.media)
        let (fresh,_) = try await URLSession.shared.data(from:playlistURL)
        precondition(fresh == next.playlists["/video.m3u8"],"Same loopback endpoint serves the refreshed rolling playlist")
        let (_,response) = try await URLSession.shared.data(from:url.deletingLastPathComponent().appendingPathComponent("unlisted.m4s"))
        precondition((response as? HTTPURLResponse)?.statusCode == 404,"Live bridge refuses unlisted paths")
        server.stop()
        let epochNow = ISO8601DateFormatter().string(from:Date().addingTimeInterval(-600))
        let fixture = xml.replacingOccurrences(of:"2026-10-21T12:00:00Z",with:epochNow)
        var initData=Data([0,0,0,19]);initData.append(Data("colrnclx".utf8));initData.append(contentsOf:[0,9,0,18,0,9,0])
        func word(_ n:Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded:n >> ((3-$0)*8)) }) }
        func box(_ name:String,_ body:Data) -> Data { word(body.count+8)+Data(name.utf8)+body }
        func moof(_ offset:Int) -> Data { box("moof",box("traf",box("tfhd",word(0x020000)+word(1))+box("trun",word(0x00000201)+word(1)+word(offset)+word(4)))) }
        let fragment = moof(moof(0).count+8)+box("mdat",Data([1,2,3,4]))
        let live = LiveUHDPlaybackAccess(fetch:{ url in
            if url.path.hasSuffix("master.mpd") { return Data(fixture.utf8) }
            if url.path.hasSuffix("init.mp4") { return initData }
            return fragment
        })
        let source = try await live.source(manifestURL:base)
        precondition(source.requestedHeight == 2160 && source.videoRange == "HLG","Live source checks init signalling before advertising UHD")
        let rollingURL = source.url.deletingLastPathComponent().appendingPathComponent("video.m3u8")
        let (before,_) = try await URLSession.shared.data(from:rollingURL)
        try await Task.sleep(nanoseconds:4_300_000_000)
        let (after,_) = try await URLSession.shared.data(from:rollingURL)
        precondition(before != after,"Running live bridge advances playlists without changing playback URL")
        live.stop()
        precondition(AdditionalLiveStream.all.map(\.id) == ["red_button_one","uk_bbc_stream_041"],"Menu uses the two curated services")
        print("PASS: live UHD timing, rolling sequence/resource identity, timeline addressing, off-air/protection rejection, bounded resources and loopback refresh")
    }
}
