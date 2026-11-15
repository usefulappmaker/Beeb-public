// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// One scheduled broadcast on a live channel.
struct GuideEntry: Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let title: String
    let subtitle: String
    let synopsis: String
    let episodeID: String?
    /// BBC already lists this episode as available on demand.
    let onDemand: Bool
    let isRepeat: Bool
    func isOnAir(at date: Date) -> Bool { start <= date && date < end }
    func isPast(at date: Date) -> Bool { end <= date }
}

struct GuideChannel: Identifiable {
    let channel: LiveChannel
    let entries: [GuideEntry]
    var id: String { channel.id }
}

/// A stretch of one channel's row in the guide: a programme, or an unscheduled gap.
struct GuideSegment: Identifiable {
    let id: String
    let entry: GuideEntry?
    let start: Date
    let end: Date
    var minutes: Double { end.timeIntervalSince(start) / 60 }
}

enum ChannelGuide {
    /// The guide opens half an hour before the current half-hour, so the programme on air keeps a
    /// readable width. `hoursBack` extends the window to earlier programmes.
    static func origin(for now: Date, hoursBack: Int = 0) -> Date {
        Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 1800).rounded(.down) * 1800 - 1800 - Double(hoursBack) * 3600)
    }
    /// BBC's `from_date` accepts only minute precision in UTC, without a zone suffix.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.string(from: date)
    }
    static func clock(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    static func times(_ entry: GuideEntry) -> String { "\(clock(entry.start)) – \(clock(entry.end))" }
    /// BBC returns each channel's schedule from the programme on air at the requested time (default: now) onwards.
    static func entries(_ data: Data) -> [GuideEntry] {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let values = (root?["broadcasts"] as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ raw: Any?) -> Date? { (raw as? String).flatMap { fractional.date(from: $0) ?? plain.date(from: $0) } }
        var seen = Set<String>()
        return values.compactMap { broadcast -> GuideEntry? in
            guard let start = date(broadcast["scheduled_start"]), let end = date(broadcast["scheduled_end"]), end > start,
                  broadcast["blanked"] as? Bool != true,
                  let episode = broadcast["episode"] as? [String: Any], let title = episode["title"] as? String else { return nil }
            let id = broadcast["id"] as? String ?? "\(start.timeIntervalSince1970)"
            guard seen.insert(id).inserted else { return nil }
            let synopses = episode["synopses"] as? [String: Any] ?? [:]
            let episodeID = (episode["id"] as? String).flatMap { try? BBCService.pid($0) }
            return GuideEntry(id: id, start: start, end: end, title: title, subtitle: episode["subtitle"] as? String ?? "",
                              synopsis: ["medium", "small", "large"].compactMap { synopses[$0] as? String }.first { !$0.isEmpty } ?? "",
                              episodeID: episodeID, onDemand: episode["status"] as? String == "available",
                              isRepeat: broadcast["repeat"] as? Bool == true)
        }.sorted { $0.start < $1.start }
    }
    /// Independent channel schedules; one unavailable feed must not hide the others.
    static func load(_ channels: [LiveChannel], from origin: Date? = nil, perPage: Int = 50,
                     fetch: @escaping (URL) async throws -> Data = { try await BBCService().fetch($0) }) async -> [GuideChannel] {
        let since = origin.map { "&from_date=" + stamp($0) } ?? ""
        return await withTaskGroup(of: (Int, GuideChannel).self) { group in
            for (index, channel) in channels.enumerated() {
                group.addTask {
                    let url = URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/channels/\(channel.id)/broadcasts?per_page=\(perPage)\(since)")!
                    let data = try? await fetch(url)
                    return (index, GuideChannel(channel: channel, entries: data.map(entries) ?? []))
                }
            }
            var results = [(Int, GuideChannel)]()
            for await value in group { results.append(value) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
    /// Lay one channel out as contiguous programme and gap segments clipped to a time window.
    /// An overlapping broadcast starts where the previous one ended.
    static func segments(_ entries: [GuideEntry], from origin: Date, to end: Date) -> [GuideSegment] {
        var result = [GuideSegment](), cursor = origin
        for entry in entries where entry.end > origin && entry.start < end {
            let from = max(entry.start, cursor), to = min(entry.end, end)
            guard to > from else { continue }
            if from > cursor { result.append(GuideSegment(id: "gap-\(cursor.timeIntervalSinceReferenceDate)", entry: nil, start: cursor, end: from)) }
            result.append(GuideSegment(id: entry.id, entry: entry, start: from, end: to))
            cursor = to
        }
        return result
    }
}
