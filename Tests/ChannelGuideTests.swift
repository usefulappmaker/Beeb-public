// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
@main struct ChannelGuideTests {
    static func main() async throws {
        func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
        func at(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }
        func entry(_ id: String, _ start: String, _ end: String) -> GuideEntry {
            GuideEntry(id: id, start: at(start), end: at(end), title: id, subtitle: "", synopsis: "", episodeID: nil, onDemand: false, isRepeat: false)
        }

        // The window opens half an hour before the current half-hour, in whole half-hours.
        let now = at("2026-10-19T12:40:00Z")
        check(ChannelGuide.origin(for: now) == at("2026-10-19T12:00:00Z"), "Guide opens half an hour before the current half-hour")
        check(ChannelGuide.origin(for: at("2026-10-19T12:30:00Z")) == at("2026-10-19T12:00:00Z"), "A half-hour boundary belongs to the slot it starts")
        check(ChannelGuide.origin(for: now, hoursBack: 8) == at("2026-10-19T04:00:00Z"), "Earlier programmes extend the window by whole hours")
        check(ChannelGuide.stamp(at("2026-10-19T04:00:00Z")) == "2026-10-19T04:00", "BBC from_date is minute precision in UTC without a zone suffix")

        let schedule = Data(#"""
        {"broadcasts":{"elements":[
        {"id":"b1","scheduled_start":"2026-10-19T12:00:00Z","scheduled_end":"2026-10-19T13:00:00Z","repeat":true,
         "episode":{"id":"p0000001","title":"Later","subtitle":"Series 1: Episode 1","status":"available","synopses":{"medium":"","small":"Short","large":"Long"}}},
        {"id":"b0","scheduled_start":"2026-10-19T11:00:00.000Z","scheduled_end":"2026-10-19T12:00:00.000Z",
         "episode":{"title":"Earlier","status":"unavailable","synopses":{"medium":"Medium"}}},
        {"id":"b1","scheduled_start":"2026-10-19T12:00:00Z","scheduled_end":"2026-10-19T13:00:00Z","episode":{"title":"Duplicate"}},
        {"id":"b2","scheduled_start":"2026-10-19T13:00:00Z","scheduled_end":"2026-10-19T14:00:00Z","blanked":true,"episode":{"title":"Blanked"}},
        {"id":"b3","scheduled_start":"2026-10-19T14:00:00Z","scheduled_end":"2026-10-19T14:00:00Z","episode":{"title":"No duration"}},
        {"id":"b4","scheduled_start":"2026-10-19T15:00:00Z","scheduled_end":"2026-10-19T16:00:00Z"}
        ]}}
        """#.utf8)
        let entries = ChannelGuide.entries(schedule)
        check(entries.map(\.id) == ["b0", "b1"], "Blanked, duplicate, empty and episode-less broadcasts are dropped; the rest sort by start")
        let earlier = entries[0], later = entries[1]
        check(earlier.start == at("2026-10-19T11:00:00Z") && earlier.synopsis == "Medium", "Fractional-second dates and the medium synopsis are read")
        check(!earlier.onDemand && earlier.episodeID == nil && !earlier.isRepeat, "Only episodes BBC lists as available are offered on demand")
        check(later.onDemand && later.episodeID == "p0000001" && later.isRepeat, "Available episodes keep their identifier and repeat flag")
        check(later.subtitle == "Series 1: Episode 1" && later.synopsis == "Short", "An empty synopsis falls back to the next length")
        check(earlier.isPast(at: now) && !earlier.isOnAir(at: now), "A finished programme is past")
        check(later.isOnAir(at: now) && !later.isPast(at: now), "The programme spanning now is on air")
        check(later.isPast(at: later.end) && !later.isOnAir(at: later.end), "A programme ends at its scheduled end")
        check(ChannelGuide.entries(Data("<html>Service Temporarily Unavailable</html>".utf8)).isEmpty, "A non-JSON response yields an empty schedule")

        // 12:00–12:30, a quarter-hour gap, 12:45–13:30, then a broadcast overlapping the previous one.
        let row = [entry("a", "2026-10-19T12:00:00Z", "2026-10-19T12:30:00Z"), entry("b", "2026-10-19T12:45:00Z", "2026-10-19T13:30:00Z"),
                   entry("hidden", "2026-10-19T13:00:00Z", "2026-10-19T13:20:00Z"), entry("c", "2026-10-19T13:15:00Z", "2026-10-19T14:00:00Z")]
        let segments = ChannelGuide.segments(row, from: at("2026-10-19T12:10:00Z"), to: at("2026-10-19T13:45:00Z"))
        check(segments.map { $0.entry?.id ?? "gap" } == ["a", "gap", "b", "c"], "Programmes and gaps alternate; a broadcast hidden by the previous one is skipped")
        check(segments.map(\.minutes) == [20, 15, 45, 15], "Segments are clipped to the window and an overlap starts where the previous programme ended")
        check(segments.map(\.minutes).reduce(0, +) == 95, "Segments fill the window exactly, so every row keeps the same width")
        let late = ChannelGuide.segments([row[1]], from: at("2026-10-19T12:00:00Z"), to: at("2026-10-19T13:00:00Z"))
        check(late.map { $0.entry?.id ?? "gap" } == ["gap", "b"] && late.map(\.minutes) == [45, 15], "A row starting late opens with a gap")
        check(ChannelGuide.segments(row, from: at("2026-10-19T15:00:00Z"), to: at("2026-10-19T16:00:00Z")).isEmpty, "Nothing scheduled in the window leaves the row empty")

        // Remote navigation: Up and Down land on the programme at the focus time; Left and Right page at the window's edges.
        func playable(_ id: String, _ start: String, _ end: String, onDemand: Bool = true) -> GuideEntry {
            GuideEntry(id: id, start: at(start), end: at(end), title: id, subtitle: "", synopsis: "", episodeID: nil, onDemand: onDemand, isRepeat: false)
        }
        let day = [playable("past", "2026-10-19T10:00:00Z", "2026-10-19T11:00:00Z", onDemand: false),
                   playable("morning", "2026-10-19T11:00:00Z", "2026-10-19T12:15:00Z"),
                   playable("noon", "2026-10-19T12:15:00Z", "2026-10-19T13:00:00Z"),
                   playable("film", "2026-10-19T13:00:00Z", "2026-10-19T15:30:00Z"),
                   playable("late", "2026-10-19T15:30:00Z", "2026-10-19T16:00:00Z")]
        let open = at("2026-10-19T12:00:00Z"), span: TimeInterval = 2.5 * 3600, first = at("2026-10-19T04:00:00Z"), last = at("2026-10-19T18:00:00Z")
        func land(_ time: String) -> String? { ChannelGuide.landing(in: day, at: at(time), from: open, to: open.addingTimeInterval(span), now: now)?.id }
        check(land("2026-10-19T12:40:00Z") == "noon", "Up and Down land on the programme showing at the focus time")
        check(land("2026-10-19T12:00:00Z") == "morning", "A programme that began before the window still counts at its left edge")
        check(ChannelGuide.landing(in: [day[0]], at: open, from: open.addingTimeInterval(-7200), to: open, now: now) == nil, "A row with nothing playable is skipped")
        check(ChannelGuide.landing(in: [day[0], day[4]], at: open, from: at("2026-10-19T10:00:00Z"), to: at("2026-10-19T16:00:00Z"), now: now)?.id == "late",
              "Without a playable programme at the focus time, the nearest playable one is chosen")
        func page(_ id: String, _ forward: Bool, from start: Date = open) -> (String, Date)? {
            ChannelGuide.page(day, from: day.first { $0.id == id }!, forward: forward, start: start, span: span, earliest: first, latest: last, now: now).map { ($0.entry.id, $0.start) }
        }
        check(page("noon", true) == nil && page("noon", false) == nil, "A neighbour already on screen is left to the focus engine")
        check(page("film", true).map { $0 == ("late", at("2026-10-19T15:30:00Z")) } == true, "Right at the edge opens the window at the next programme")
        check(page("morning", false, from: at("2026-10-19T11:00:00Z")) == nil, "Nothing earlier that can be watched: the window stays")
        check(page("film", false, from: at("2026-10-19T13:00:00Z")).map { $0 == ("noon", at("2026-10-19T10:30:00Z")) } == true,
              "Left at the edge brings the previous programme's end into view")
        let long = [playable("marathon", "2026-10-19T06:00:00Z", "2026-10-19T18:00:00Z")]
        let back = ChannelGuide.page(long, from: long[0], forward: false, start: open, span: span, earliest: first, latest: last, now: now)
        check(back?.entry.id == "marathon" && back!.start == at("2026-10-19T10:00:00Z"), "With nothing beyond a long programme, Left scrolls through it and keeps it focused")
        let ahead = ChannelGuide.page(long, from: long[0], forward: true, start: open, span: span, earliest: first, latest: last, now: now)
        check(ahead?.entry.id == "marathon" && ahead!.start == at("2026-10-19T14:00:00Z"), "Right scrolls through it too")
        check(ChannelGuide.page(long, from: long[0], forward: true, start: last.addingTimeInterval(-span), span: span, earliest: first, latest: last, now: now) == nil,
              "Scrolling stops at the end of the guide")

        let channels = [LiveChannel(id: "bbc_one_london", title: "BBC One"), LiveChannel(id: "bbc_two_england", title: "BBC Two"), LiveChannel(id: "bbc_four", title: "BBC Four")]
        let guide = await ChannelGuide.load(channels, from: at("2026-10-19T04:00:00Z"), perPage: 100) { url in
            guard url.absoluteString.hasSuffix("/broadcasts?per_page=100&from_date=2026-10-19T04:00") else { throw BBCError.message("Unexpected schedule request") }
            if url.path.contains("bbc_two_england") { throw BBCError.message("Schedule unavailable") }
            return schedule
        }
        check(guide.map(\.id) == channels.map(\.id), "Channels keep their order whichever schedule arrives first")
        check(guide[0].entries.count == 2 && guide[2].entries.count == 2 && guide[1].entries.isEmpty, "One unavailable schedule does not hide the others")
        print("PASS: guide window, schedule parsing, on-demand flags, timeline segments, remote navigation and independent channel loading")
    }
}
