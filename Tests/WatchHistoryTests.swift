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
        print("PASS: resume persistence, compact programme history, completion/up-next, reverse series order, broadcast dates, restart, removal, invalid-time and corruption recovery")
    }
}
