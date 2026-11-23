import Foundation

@main struct WatchHistoryTests {
    @MainActor static func main() throws {
        func episode(_ id: String, season: Int = 1, number: Int, date: String? = nil) -> CatalogueEpisode {
            var programme = Programme(id: id, title: "Example", summary: "", image: nil, version: "v0000001", guidance: nil)
            programme.showID = "b0000001"; programme.showTitle = "Example"; programme.episodeSubtitle = "Series \(season): \(number). Episode title"
            return CatalogueEpisode(programme: programme, subtitle: programme.episodeSubtitle!, duration: "1 hour", sliceID: "s\(season)", seriesTitle: "Series \(season)", parentPosition: number, broadcastDate: date)
        }
        let one = episode("b0000002", number: 1), two = episode("b0000003", number: 2), three = episode("b0000004", number: 3), nextSeries = episode("b0000005", season: 2, number: 1)
        var show = CatalogueShow(id: "b0000001", title: "Example", summary: "", image: nil, letter: "e", channel: "BBC", categories: [], expectedEpisodes: 4, singleEpisode: false, episodes: [nextSeries, three, two, one], indexedAt: Date())
        precondition(EpisodeSequence.ordered(show.episodes).map(\.id) == [one.id, two.id, three.id, nextSeries.id], "Programme page starts at Episode 1, in series order")
        precondition(EpisodeSequence.orderedSeries(show.series).map(\.title) == ["Series 1", "Series 2"], "Series 1 is initially selected even when BBC returns the newest series first")
        precondition(EpisodeSequence.next(after: one, in: show)?.id == two.id, "API newest-first must not reverse watch order")
        precondition(EpisodeSequence.next(after: three, in: show)?.id == nextSeries.id, "Advance to the first episode of the next series")
        precondition(EpisodeSequence.next(after: nextSeries, in: show) == nil, "Final episode has no invented successor")
        show.episodes.removeAll { $0.id == one.id }
        precondition(EpisodeSequence.next(after: one, in: show)?.id == two.id, "Completed episode can expire without losing next-episode ordering")
        var dated = CatalogueEpisode(programme: one.programme, subtitle: "Monday", duration: "", sliceID: "days", seriesTitle: "Episodes", broadcastDate: "2026-10-12T20:00:00.000Z")
        var datedNext = CatalogueEpisode(programme: two.programme, subtitle: "Tuesday", duration: "", sliceID: "days", seriesTitle: "Episodes", broadcastDate: "2026-10-13T20:00:00.000Z")
        show.episodes = [datedNext, dated]
        precondition(EpisodeSequence.next(after: dated, in: show)?.id == datedNext.id, "Unnumbered episodes use broadcast dates")
        dated.broadcastDate = nil; datedNext.broadcastDate = nil; show.episodes = [datedNext, dated]
        precondition(EpisodeSequence.next(after: dated, in: show) == nil, "Do not guess order without metadata")
        show.episodes = [three, two, one]; show.expectedEpisodes = 3
        let suite = "BeebHistoryTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WatchHistory(defaults: defaults)
        history.update(episode: one, show: show, next: two, position: 120, duration: 3600)
        precondition(history.records.count == 1 && history.resumePosition(for: one.id) == 120, "Save resume position")
        precondition(history.records[0].show?.episodes.isEmpty == true, "History never embeds a full show catalogue")
        let reopened = WatchHistory(defaults: defaults)
        precondition(reopened.resumePosition(for: one.id) == 120 && reopened.records[0].nextEpisode?.id == two.id, "Progress and next episode persist across launches")
        let time = history.records[0].updatedAt
        history.update(episode: one, show: show, next: two, position: 120, duration: 3600)
        precondition(history.records[0].updatedAt == time, "Paused clock does not rewrite history or recency")
        history.update(episode: one, show: show, next: two, position: 3480, duration: 3600)
        precondition(history.records[0].completed && history.records[0].target?.id == two.id && history.resumePosition(for: one.id) == 0, "Finished episode offers the next episode")
        history.update(episode: two, show: show, next: three, position: 50, duration: 3600)
        precondition(history.records.count == 1 && history.records[0].episode.id == two.id && !history.records[0].completed, "Only one entry per programme, following the episode now watched")
        history.update(episode: two, show: show, next: nil, position: 55, duration: 3600)
        precondition(history.records[0].nextEpisode?.id == three.id, "Keep a known successor when a compact show is used")
        history.update(episode: two, show: show, next: three, position: 5, duration: 3600)
        precondition(history.resumePosition(for: two.id) == 5, "Start over replaces the bookmark after playback actually advances")
        history.update(episode: two, show: show, next: three, position: .nan, duration: 3600)
        history.update(episode: two, show: show, next: three, position: 100, duration: .infinity)
        precondition(history.resumePosition(for: two.id) == 5, "Unknown/invalid media times do not corrupt saved progress")
        history.update(episode: two, show: show, next: three, position: 3600, duration: 3600, ended: true)
        precondition(history.records[0].completed, "Actual end notification marks completion")
        precondition(!WatchHistory.isComplete(position: 3420, duration: 3600), "95 percent alone does not skip more than two minutes")
        precondition(WatchHistory.isComplete(position: 95, duration: 100), "Completion scales to short programmes")
        history.remove(show.id)
        precondition(WatchHistory(defaults: defaults).records.isEmpty, "Removing a programme persists")
        defaults.set(Data("bad JSON".utf8), forKey: "continueWatching-v1-" + ProfileStore.currentID)   // per-profile key since 0.11.0
        let corrupt = WatchHistory(defaults: defaults)
        precondition(corrupt.records.isEmpty && corrupt.warning != nil, "Corrupt history does not prevent launch")
        corrupt.update(episode: one, show: show, next: two, position: 15, duration: 3600)
        precondition(corrupt.warning == nil && WatchHistory(defaults: defaults).records.count == 1, "New progress recovers from corrupt storage")
        // Per-episode progress: watched and part-watched marks survive moving on to later episodes.
        let episodeSuite = "BeebEpisodeTests-" + UUID().uuidString
        let episodeDefaults = UserDefaults(suiteName: episodeSuite)!
        defer { episodeDefaults.removePersistentDomain(forName: episodeSuite) }
        let marks = WatchHistory(defaults: episodeDefaults)
        marks.update(episode: one, show: show, next: two, position: 3590, duration: 3600, ended: true)
        marks.update(episode: two, show: show, next: three, position: 900, duration: 3600)
        precondition(marks.progress(for: one.id)?.completed == true, "A finished episode stays watched after moving on")
        precondition(marks.progress(for: two.id).map { !$0.completed && abs($0.fraction - 0.25) < 0.01 } == true, "A part-watched episode keeps its progress")
        marks.update(episode: one, show: show, next: two, position: 60, duration: 3600)
        precondition(marks.progress(for: one.id)?.completed == true, "Rewatching the start doesn't un-mark a finished episode")
        marks.setWatched(three.id, true)
        precondition(marks.progress(for: three.id)?.completed == true, "Mark watched")
        marks.setWatched(one.id, false)
        precondition(marks.progress(for: one.id) == nil, "Mark unwatched forgets the episode's progress")
        let now = Date().timeIntervalSinceReferenceDate
        marks.adoptEpisodes(["records": [["id": "b0000099", "position": 10.0, "duration": 100.0, "completed": false, "updatedAt": now + 10]],
                             "removed": [two.id: now + 100]])
        precondition(marks.progress(for: "b0000099")?.position == 10, "Progress from another Apple TV is adopted")
        precondition(marks.progress(for: two.id) == nil, "A newer Mark unwatched from another Apple TV removes local progress")
        marks.adoptEpisodes(["records": [["id": three.id, "position": 1.0, "duration": 100.0, "completed": false, "updatedAt": now - 1000]], "removed": [:]])
        precondition(marks.progress(for: three.id)?.completed == true, "Older remote progress doesn't overwrite a newer local mark")
        // Completion is sticky between Apple TVs, whichever change is newer, until the episode is marked unwatched.
        func remote(_ id: String, _ completed: Bool, _ at: Double, reset: Double? = nil) -> [String: Any] {
            var record: [String: Any] = ["id": id, "position": completed ? 100.0 : 10.0, "duration": 100.0, "completed": completed, "updatedAt": at]
            if let reset { record["resetAt"] = reset }
            return record
        }
        func adopt(_ records: [[String: Any]], removed: [String: Double] = [:]) { marks.adoptEpisodes(["records": records, "removed": removed]) }
        adopt([remote(three.id, false, now + 200)])
        precondition(marks.progress(for: three.id).map { $0.completed && $0.position == 10 } == true, "Newer part-watched progress from another Apple TV keeps the watched mark")
        precondition(marks.progress(for: three.id)!.updatedAt.timeIntervalSinceReferenceDate > now + 200, "The kept mark is newer, so it reaches the server and the other Apple TV")
        let settled = marks.progress(for: three.id)!
        adopt([remote(three.id, true, settled.updatedAt.timeIntervalSinceReferenceDate)])
        precondition(marks.progress(for: three.id)!.updatedAt == settled.updatedAt, "An echoed record doesn't keep changing")
        adopt([remote("b0000098", false, now + 20)]); adopt([remote("b0000098", true, now + 10)])
        precondition(marks.progress(for: "b0000098").map { $0.completed && $0.position == 10 } == true, "An older completion arriving late marks the episode watched")
        adopt([], removed: [three.id: now + 300])
        precondition(marks.progress(for: three.id) == nil, "Mark unwatched on another Apple TV clears the mark")
        adopt([remote("b0000097", true, now + 10)]); adopt([remote("b0000097", false, now + 40, reset: now + 30)])
        precondition(marks.progress(for: "b0000097")?.completed == false, "Marked unwatched then part-watched elsewhere clears an earlier completion")
        adopt([remote("b0000096", true, now + 10)]); adopt([remote("b0000096", false, now + 40)], removed: ["b0000096": now + 30])
        precondition(marks.progress(for: "b0000096")?.completed == false, "A removal between a completion and newer progress clears the completion")
        adopt([remote("b0000097", true, now + 50, reset: now + 30)])
        precondition(marks.progress(for: "b0000097")?.completed == true, "Finishing it again after Mark unwatched counts")
        marks.setWatched(nextSeries.id, true); marks.setWatched(nextSeries.id, false)
        marks.update(episode: nextSeries, show: show, next: nil, position: 60, duration: 3600, now: Date().addingTimeInterval(1))
        precondition(marks.progress(for: nextSeries.id)?.resetAt != nil, "Playing again after Mark unwatched remembers it for the other Apple TVs")
        adopt([remote(nextSeries.id, true, now - 500)])
        precondition(marks.progress(for: nextSeries.id)?.completed == false, "A completion from before Mark unwatched doesn't return")
        // Progress saved before resetAt existed still loads.
        let legacy = try! JSONDecoder().decode(EpisodeProgress.self, from: Data(#"{"position":1,"duration":2,"completed":true,"updatedAt":0}"#.utf8))
        precondition(legacy.completed && legacy.resetAt == nil, "Earlier saved progress decodes")
        // Removing a profile leaves none of its data, and nobody else's is touched.
        for id in ["gone", "kept"] { for key in ["continueWatching-v1-", "continueWatching-removed-v1-", "savedShows-v3-", "savedShows-meta-v1-", "favouriteChannels-v1-", "episodeProgress-v1-", "episodeProgress-removed-v1-"] { episodeDefaults.set(Data([1]), forKey: key + id) } }
        ProfileStore.removeLocalData(for: "gone", in: episodeDefaults)
        let left = episodeDefaults.dictionaryRepresentation().keys
        precondition(!left.contains { $0.hasSuffix("-gone") } && left.filter { $0.hasSuffix("-kept") }.count == 7, "Removing a profile clears only its own stores")
        marks.setWatched(three.id, true)
        let reloaded = WatchHistory(defaults: episodeDefaults)
        precondition(reloaded.progress(for: three.id)?.completed == true && reloaded.progress(for: one.id) == nil, "Episode marks are kept")
        print("PASS: resume persistence, compact programme history, completion/up-next, reverse series order, broadcast dates, restart, removal, invalid-time and corruption recovery, per-episode watched marks and their sync")
    }
}
