import Foundation

@main struct ResolverTests {
    static func main() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        let parsedPID = try BBCService.pid("https://www.bbc.co.uk/iplayer/episode/m0032x5w/example")
        check(parsedPID == "m0032x5w", "Episode URL parsing")
        do { _ = try BBCService.pid("https://evil.example/iplayer/episode/m0032x5w"); fatalError("Accepted other host") } catch {}
        do { _ = try BBCService.pid("../../file"); fatalError("Accepted invalid PID") } catch {}
        let base = URL(string: "https://cdn.example/path/master.m3u8?token=abc")!
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS="avc1.640020,mp4a.40.2",RESOLUTION=704x396
        low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5500000,RESOLUTION=1280x720
        video=5070000.m3u8?foo=bar
        """
        let variants = BBCService.variants(manifest, base: base)
        check(variants.count == 2 && variants[0].height == 720 && variants[0].bandwidth == 5500000, "Variant parsing and ranking")
        check(variants[0].url.absoluteString == "https://cdn.example/path/video=5070000.m3u8?token=abc&foo=bar", "Relative URL and auth preservation")
        check(BBCService.resolve("https://other.example/video.m3u8", base: base)?.query == nil, "Cross-host credential leak")
        check(BBCService.fullHDURL(variants[0].url)?.absoluteString == "https://cdn.example/path/video=12000000.m3u8?token=abc&foo=bar", "Full HD candidate")
        check(!BBCService.validMediaPlaylist("<html>error</html>"), "HTML rejected")
        check(!BBCService.validMediaPlaylist("#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://x\"\n#EXTINF:8,\na.ts"), "Unsupported DRM rejected")
        let delegate = MediaSelector()
        let xml = """
        <mediaSelection><media kind="thumbnails"><connection transferFormat="hls" href="https://cdn.example/no"/></media><media kind="video"><connection transferFormat="dash" href="https://cdn.example/no"/><connection transferFormat="hls" href="http://cdn.example/no"/><connection transferFormat="hls" href="https://cdn.example/yes"/></media></mediaSelection>
        """
        let parser = XMLParser(data: Data(xml.utf8)); parser.delegate = delegate
        check(parser.parse() && delegate.urls.map(\.absoluteString) == ["https://cdn.example/yes"], "Selector filtering")
        let metadata = Data("""
        {"episodes":[{"id":"p09pm8b0","title":"Vigil","synopses":{"large":"Episode description"},"versions":[
        {"id":"p09tjhvs","kind":"audio-described"},
        {"id":"m002hzwl","kind":"signed"},
        {"id":"m000z8m3","kind":"technical-replacement","uhd":true,"availability":{"start":"2022-01-01T00:00:00Z","end":"2099-01-01T00:00:00Z"}},
        {"id":"m0032x5w","kind":"original","availability":{"end":"2000-01-01T00:00:00Z"}}]}]}
        """.utf8)
        let programme = try BBCService.programme(metadata, id:"p09pm8b0")
        check(programme.version == "m000z8m3" && programme.summary == "Episode description", "Current episode API supplies playable version")
        let parsedEpisode = try BBCService.episodeMetadata(metadata,id:"p09pm8b0")
        check(BBCService.playbackVersions(parsedEpisode) == ["m000z8m3"], "Excluded expired, signed and described versions")
        do { _ = try BBCService.programme(Data("<html>Service Temporarily Unavailable</html>".utf8), id:"p09pm8b0");fatalError("Accepted HTML as JSON") }
        catch { check(error.localizedDescription.contains("episode service"), "Readable service-format error") }
        do { _ = try BBCService.programme(metadata,id:"m0032x5w");fatalError("Played wrong episode") } catch {}
        print("PASS: resolver parsing, validation, URL handling, quality selection and selector filtering")
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--episode-response" {
            let metadata = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            let episode = try BBCService.programme(metadata, id:"p09pm8b0")
            check(episode.version == "m000z8m3", "Current BBC response resolves the available Vigil version")
            print("PASS: current BBC episode response resolves Vigil metadata and playback version")
            return
        }
        if CommandLine.arguments.count > 1 {
            let service = BBCService()
            let p = try await service.programme(CommandLine.arguments[1])
            let source = try await service.source(for: p, require1080: true)
            print("LIVE PASS: \(p.title); 1080p candidate found: \(source.requested1080)")
            if CommandLine.arguments.count > 2 {
                try source.url.absoluteString.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
            }
        }
    }
}
