// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@MainActor enum TwinVineUHDProbe {
    /// A bounded check of the editorial UHD list, never a full-catalogue scan.
    static func verify(probe: (Programme) async throws -> Void,
                       fetch: @escaping (URL) async throws -> Data = { try await BBCService().fetch($0) }) async throws -> String {
        var entries = (try? await CatalogueIndexAPI(fetch: fetch).uhdPage()) ?? []
        try Task.checkCancellation()
        if entries.isEmpty, let url = Bundle.main.url(forResource: "CatalogueSeed", withExtension: "plist"),
           let data = try? Data(contentsOf: url), let seed = try? PropertyListDecoder().decode(CatalogueIndexSnapshot.self, from: data) {
            entries = seed.uhd.prefix(3).map { UHDPageEntry(id: $0.discoveryEpisodeID ?? $0.id, title: $0.title, singleEpisode: $0.singleEpisode) }
        }
        for entry in entries.prefix(3) {
            try Task.checkCancellation()
            do {
                let pid = try BBCService.pid(entry.id)
                let programmes: [Programme]
                if entry.singleEpisode {
                    let data = try await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/episodes/\(pid)")!)
                    programmes = [try BBCService.programme(data, id: pid)]
                } else {
                    let data = try await fetch(URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/programmes/\(pid)/episodes?page=1&per_page=24")!)
                    programmes = try CatalogueAPI.parseEpisodes(data).episodes.filter { $0.programme.uhdListed == true }.prefix(2).map(\.programme)
                }
                for programme in programmes {
                    do { try await probe(programme); return entry.title }
                    catch { if Task.isCancelled || error is CancellationError { throw CancellationError() } }
                }
            } catch { if Task.isCancelled || error is CancellationError { throw CancellationError() } }
        }
        throw BBCError.message("Could not verify a playable 4K HLG stream from BBC's current UHD list. Your existing UHD setup has been kept. Try again later.")
    }
}
