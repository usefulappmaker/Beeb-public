import Foundation
@main struct CatalogueLifecycleTests {
    @MainActor static func main() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:folder)}
        let cache=DiscoveryCache(folder:folder)
        let minimal=HomeFeed(features:[],rows:[HomeRow(id:"popular",title:"Popular",shows:[])])
        try await cache.write(minimal,key:"homepage")
        let log=RequestLogForLifecycle()
        let fail=DiscoveryAPI(fetch:{url in await log.record(url);throw BBCError.message("Offline")})
        let store=CatalogueStore(discovery:fail,cache:cache)
        await store.boot()
        precondition(store.home?.rows.first?.id=="popular" && store.error != nil,"Offline launch keeps lightweight homepage cache")
        let paths=await log.paths()
        precondition(paths.count==2 && !paths.contains(where:{$0.contains("atoz")||$0.contains("episodes")}),"Launch requests only homepage and categories; no catalogue crawl")
        let raw:[String:Any]=["id":"b0000001","title":"A show","count":1,"tleo_type":"brand"]
        let data=try JSONSerialization.data(withJSONObject:["atoz_programmes":["page":1,"per_page":30,"count":60,"elements":[raw]]])
        let pages=PageStore(api:DiscoveryAPI(fetch:{_ in data}),cache:cache)
        await pages.load(letter:"a",page:1)
        precondition(pages.shows.count==1 && pages.totalPages==2,"Page metadata retained")
        let offline=PageStore(api:fail,cache:cache)
        await offline.load(letter:"a",page:1)
        precondition(offline.shows.count==1 && offline.totalPages==2 && offline.error != nil,"Offline browsing restores cached page and pagination")
        var linked = try CatalogueAPI.show(["id": "p0000002", "title": "Linked episode", "count": 0, "tleo_type": "episode"])
        linked.discoveryEpisodeID = "p0000002"
        let discovery = DiscoveryAPI(fetch: { url in
            if url.path.contains("/episodes/") {
                return try JSONSerialization.data(withJSONObject: ["episodes": [["tleo_id": "b0000003"]]])
            }
            precondition(url.path.hasSuffix("/programmes/b0000003"), "Resolve episode to its actual parent")
            return try JSONSerialization.data(withJSONObject: ["programmes": [["id": "b0000003", "title": "Full programme", "count": 2, "tleo_type": "brand"]]])
        })
        let episodeAPI = CatalogueAPI(fetch: { url in
            precondition(url.path.contains("/programmes/b0000003/episodes"), "Only open the selected programme's episodes")
            let episodes: [[String: Any]] = [false, true].enumerated().map { offset, uhd in
                ["id": offset == 0 ? "p0000002" : "p0000003", "title": "Full programme", "subtitle": "Episode \(offset + 1)", "status": "available", "versions": [["id": "v0000001", "kind": "original", "uhd": uhd]]]
            }
            return try JSONSerialization.data(withJSONObject: ["programme_episodes": ["page": 1, "per_page": 200, "count": 2, "elements": episodes]])
        })
        let linkedStore = CatalogueStore(discovery: discovery, catalogue: episodeAPI, cache: cache)
        var observedParent = "", observedSource = ""
        linkedStore.programmeOpened = { show, source in observedParent = show.id; observedSource = source }
        let opened = try await linkedStore.open(linked)
        precondition(opened.id == "b0000003" && opened.episodes.count == 2 && opened.uhdEpisodeCount == 1, "Linked episode opens all episodes, including non-UHD")
        precondition(observedParent == opened.id && observedSource == linked.id, "Publish opened details for passive UHD discovery and alias learning")
        let continuousRequests = RequestLogForLifecycle()
        let continuous = ContinuousCatalogueStore(api: DiscoveryAPI(fetch: { url in
            await continuousRequests.record(url)
            let number = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "page" }!.value!)!
            let ids = number == 1 ? ["b0000001", "b0000002"] : ["b0000002", "b0000003"]
            return try JSONSerialization.data(withJSONObject: ["category_programmes": ["page": number, "per_page": 2, "count": 3, "elements": ids.map { ["id": $0, "title": $0, "count": 1, "tleo_type": "brand"] }]])
        }))
        await continuous.next(category: "drama-and-soaps", letter: nil)
        precondition(continuous.shows.count == 2 && continuous.hasMore, "First batch does not crawl the catalogue")
        await continuous.next(category: "drama-and-soaps", letter: nil)
        precondition(continuous.shows.count == 3 && !continuous.hasMore, "Append in order, deduplicate and stop at the total")
        await continuous.next(category: "drama-and-soaps", letter: nil)
        let fetched = await continuousRequests.paths()
        precondition(fetched.count == 2, "No extra request after reaching the end")
        print("PASS: lightweight offline launch, absence of full-catalogue requests, page cache and pagination restoration")
    }
}
actor RequestLogForLifecycle {
    var values=[String]()
    func record(_ url:URL){values.append(url.path)}
    func paths()->[String]{values}
}
