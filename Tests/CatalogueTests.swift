import Foundation
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(),message) }
actor RequestLog {
    var urls = [URL]()
    func record(_ url: URL) { urls.append(url) }
    func count() -> Int { urls.count }
}
@main struct CatalogueTests {
    static func episode(_ id: String, series: Int) -> [String: Any] {
        ["id":id,"title":"Example","tleo_id":"b0000001","subtitle":"Series \(series): Episode \(id)","slice_id":"s\(series)","versions":[["id":"v0000001","kind":"original"]]]
    }
    static func main() async throws {
        setbuf(stdout, nil)
        let raw: [String:Any] = ["id":"b0000001","title":"Example","count":3,"tleo_type":"brand","initial_children":[episode("p0000001",series:1)]]
        let show = try CatalogueAPI.show(raw)
        var first = episode("p0000001", series: 1)
        first["images"] = ["standard": "https://example.org/{recipe}/episode-one.jpg", "promotional": "https://example.org/show.jpg", "promotional_with_logo": "https://example.org/show-logo.jpg"]
        var second = episode("p0000002", series: 1)
        second["images"] = ["standard": "https://example.org/{recipe}/episode-two.jpg", "promotional_with_logo": "https://example.org/show-logo.jpg"]
        let artworkPage = try CatalogueAPI.parseEpisodes(JSONSerialization.data(withJSONObject: ["programme_episodes": ["page": 1, "per_page": 30, "count": 2, "elements": [first, second]]]))
        check(artworkPage.episodes.map { $0.programme.image?.lastPathComponent } == ["episode-one.jpg", "episode-two.jpg"], "Episode cards retain distinct episode stills instead of shared show artwork")
        check(artworkPage.episodes.first?.programme.image?.absoluteString.contains("640x360") == true, "Episode still uses thumbnail recipe")
        check(CatalogueAPI.episodeImage(["standard": "", "promotional": "https://example.org/plain.jpg", "promotional_with_logo": "https://example.org/logo.jpg"])?.lastPathComponent == "plain.jpg", "Missing episode still falls back to plain promotional artwork")
        check(CatalogueAPI.episodeImage(["promotional_with_logo": "https://example.org/logo.jpg"])?.lastPathComponent == "logo.jpg", "Episode artwork has a last-resort show fallback")
        check(CatalogueAPI.episodeImage(nil) == nil, "Missing artwork remains absent")
        let log = RequestLog()
        let api = CatalogueAPI(fetch: { url in
            await log.record(url)
            let page = Int(URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.first {$0.name=="page"}!.value!)!
            return try JSONSerialization.data(withJSONObject:["programme_episodes":["page":page,"per_page":1,"count":3,"elements":[episode("p000000\(page)",series:page==3 ? 2:1)]]])
        })
        let result = try await api.details(show)
        check(result.episodes.count==3 && result.series.count==2,"Selected show fetches every episode page and groups series")
        check(result.episodes[0].programme.showID==show.id && result.episodes[0].programme.episodeSubtitle?.contains("Series 1")==true,"Player metadata retains parent, series, episode and title")
        let calls = await log.count();check(calls==3,"Exactly selected-show pages requested")
        let discoveryLog = RequestLog()
        let discovery = DiscoveryAPI(fetch: { url in
            await discoveryLog.record(url)
            return try JSONSerialization.data(withJSONObject:["category_programmes":["page":2,"per_page":30,"count":90,"elements":[raw]]])
        })
        let page = try await discovery.page(category:"comedy",page:2)
        let pageCalls = await discoveryLog.count()
        check(page.page==2 && pageCalls==1,"Browsing fetches one page, never the entire category or catalogue")
        let fakeEpisode: [String:Any] = ["id":"p0000001","tleo":["id":"b0000001"],"title":["default":"Example"],"subtitle":["default":"Series 1: Episode 1"],"image":["default":"https://example.com/{recipe}/x.jpg", "promotional": "https://example.com/{recipe}/plain.jpg", "promotionalWithLogo": "https://example.com/{recipe}/logo.jpg", "portrait": "https://example.com/{recipe}/poster.jpg"],"synopsis":["small":"A story with } and \\\" braces"]]
        let bundle: (String,String)->[String:Any] = { ["id":$0,"title":["default":$1],"entities":[["episode":fakeEpisode]]] }
        let state = try JSONSerialization.data(withJSONObject:["bundles":[bundle("editorial","New & Trending"),bundle("popular","Most Popular Today")]])
        let html = Data(("<script>window.__IPLAYER_REDUX_STATE__ = "+String(decoding:state,as:UTF8.self)+";</script>").utf8)
        let home = try DiscoveryAPI.home(html)
        check(home.rows.first?.id=="popular" && home.features.count==1 && home.rows.first?.shows.first?.id=="b0000001","Homepage popularity ordering and parent show identity")
        check(home.features.first?.image?.absoluteString.contains("1920x1080")==true,"Banner uses widescreen high-resolution image recipe")
        check(home.features.first?.image?.lastPathComponent == "plain.jpg", "Homepage banner prefers artwork without a logo")
        check(home.rows.first?.shows.first?.image?.lastPathComponent == "logo.jpg", "Show cards retain programme logo artwork independently of banner")
        check(home.rows.first?.shows.first?.portraitImage?.absoluteString == "https://example.com/640x960/poster.jpg", "Homepage keeps true portrait artwork independently of landscape cards")
        check(HomeRow(id: "other", title: "Stream Every Episode", shows: []).usesPosters, "Poster row follows editorial title rather than an unstable BBC bundle ID")
        let legacy = try JSONDecoder().decode(CatalogueShow.self, from: JSONEncoder().encode(show))
        check(legacy.portraitImage == nil, "Older cached shows without portrait artwork remain readable")
        let fallbackCases: [([String: String], String?)] = [(["default": "https://example.org/{recipe}/still.jpg"], "still.jpg"), (["promotionalWithLogo": "https://example.org/logo.jpg"], nil)]
        for (images, expected) in fallbackCases {
            var entry = fakeEpisode; entry["image"] = images
            let fallbackState = try JSONSerialization.data(withJSONObject: ["bundles": [["id": "editorial", "entities": [["episode": entry]]]]])
            let fallback = try DiscoveryAPI.home(Data(("window.__IPLAYER_REDUX_STATE__ = " + String(decoding: fallbackState, as: UTF8.self)).utf8))
            check(fallback.features.first?.image?.lastPathComponent == expected, "Banner uses default plain still or no image, never logo-only fallback")
        }
        do { _ = try DiscoveryAPI.state(from:"window.__IPLAYER_REDUX_STATE__ = {\"broken\":");fatalError("Truncated homepage accepted") } catch {}
        // Long-running programmes without series slices: grouped by the series named in each subtitle, specials
        // joined to the series broadcast nearest them, the newest series last (the default tab).
        func hignfy(_ id: String, _ subtitle: String, _ date: String) -> CatalogueEpisode {
            var p = Programme(id: id, title: "HIGNFY", summary: "", image: nil, version: "v", guidance: nil)
            p.episodeSubtitle = subtitle
            return CatalogueEpisode(programme: p, subtitle: subtitle, duration: "30 mins", sliceID: "episodes", seriesTitle: "Episodes", broadcastDate: date)
        }
        let long = [hignfy("p0000001", "Series 72: Episode 7", "2026-11-14T21:00:00Z"), hignfy("p0000002", "Series 72: Episode 1", "2026-10-03T21:00:00Z"),
                    hignfy("p0000003", "Have I Got 2025 for You", "2025-12-19T21:00:00Z"), hignfy("p0000004", "Series 71: Episode 10", "2025-12-12T21:00:00Z"),
                    hignfy("p0000005", "Series 66: Episode 1", "2023-09-29T21:00:00Z"), hignfy("p0000006", "Have I Got 2019 for You", "2019-12-20T21:00:00Z")]
        let grouped = CatalogueShow(id: "b006mkw3", title: "HIGNFY", summary: "", image: nil, letter: "h", channel: "BBC", categories: [], expectedEpisodes: 6, singleEpisode: false, episodes: long, indexedAt: Date()).series
        check(grouped.map(\.title) == ["Specials", "Series 66", "Series 71", "Series 72"], "Series come from the subtitles; leftover specials first, newest series last")
        check(grouped.first { $0.title == "Series 71" }?.episodes.map(\.id).sorted() == ["p0000003", "p0000004"], "A special joins the series broadcast nearest to it")
        check(grouped.first { $0.title == "Specials" }?.episodes.map(\.id) == ["p0000006"], "A special far from any series stays in Specials")
        check(grouped.last?.title == "Series 72", "The newest series is last, so it opens by default")
        print("PASS: selected-show pagination, series metadata, one-page browsing, homepage ranking, banner parsing, series from subtitles and malformed-response handling")
        if CommandLine.arguments.contains("--live") {
            let live = DiscoveryAPI()
            print("Live: homepage")
            let homepage = try await live.homepage()
            check(homepage.rows.first?.id=="popular","BBC homepage has popularity section")
            print("Live: categories")
            let categories = try await live.genres()
            print("Live: comedy page")
            let comedy = try await live.page(category:"comedy",page:1)
            print("Live: A page")
            let a = try await live.page(letter:"a",page:1)
            check(comedy.shows.count<=30 && a.shows.count<=30,"Live pages bounded at 30")
            print("Live: channels")
            let channels = try await live.channels()
            print("Live: resolving first channel")
            let source = try await live.liveSource(channels.first!)
            let old = Programme(id:"m0032x5w",title:"Episode",summary:"",image:nil,version:"",guidance:nil)
            print("Live: legacy saved parent")
            let parent = try await live.parent(of:old)
            check(parent.id=="b006m86d","Legacy saved episode resolves to its parent programme")
            print("LIVE PASS: \(homepage.rows.count) homepage rows, \(homepage.features.count) banners, \(categories.count) categories, \(comedy.shows.count)/\(a.shows.count) shows per page, \(channels.count) TV channels, live HLS resolved: \(source.url.scheme == "https")")
        }
    }
}
