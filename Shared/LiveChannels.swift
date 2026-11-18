// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct LiveShelfChannel: Codable, Hashable {
    let id: String
    let title: String
    var image: URL? = nil
    static let defaults = [
        LiveShelfChannel(id: "bbc_one_london", title: "BBC One"), LiveShelfChannel(id: "bbc_two_england", title: "BBC Two"),
        LiveShelfChannel(id: "bbc_three", title: "BBC Three"), LiveShelfChannel(id: "bbc_four", title: "BBC Four"),
        LiveShelfChannel(id: "cbbc", title: "CBBC"), LiveShelfChannel(id: "cbeebies", title: "CBeebies"),
        LiveShelfChannel(id: "bbc_scotland", title: "BBC Scotland"), LiveShelfChannel(id: "bbc_news24", title: "BBC News"),
        LiveShelfChannel(id: "bbc_parliament", title: "BBC Parliament"), LiveShelfChannel(id: "bbc_alba", title: "BBC ALBA"),
        LiveShelfChannel(id: "s4cpbs", title: "S4C")
    ]
}
enum LiveChannelLink {
    static func validID(_ id: String) -> Bool { id.range(of: "^[a-z0-9_]{2,64}$", options: .regularExpression) != nil }
    static func url(for id: String) -> URL? { validID(id) ? URL(string: "beeb://live/\(id)") : nil }
    static func channelID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "beeb", url.host == "live", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 1, validID(path[0]) else { return nil }
        return path[0]
    }
}
struct LiveLaunch: Equatable {
    let id = UUID()
    let channelID: String
}
enum LiveShelfArtwork {
    static func current(_ data: Data, now: Date = Date()) -> URL? {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let entries = (root?["broadcasts"] as? [String: Any])?["elements"] as? [[String: Any]] ?? []
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? { (value as? String).flatMap { fractional.date(from: $0) ?? plain.date(from: $0) } }
        for entry in entries {
            guard let start = date(entry["scheduled_start"]), let end = date(entry["scheduled_end"]), start <= now, now < end,
                  entry["blanked"] as? Bool != true, let episode = entry["episode"] as? [String: Any],
                  let images = episode["images"] as? [String: Any], let value = images["standard"] as? String,
                  let url = URL(string: value.replacingOccurrences(of: "{recipe}", with: "1280x720")),
                  url.scheme == "https", url.host == "ichef.bbci.co.uk" else { continue }
            return url
        }
        return nil
    }
}

extension Notification.Name { static let beebLaunchLive = Notification.Name("BeebLaunchLive") }

struct RegionalChannelChoice: Identifiable { let id: String; let title: String }
enum RegionalChannels {
    static let bbcOne: [RegionalChannelChoice] = [
        .init(id: "bbc_one_channel_islands", title: "Channel Islands"),
        .init(id: "bbc_one_east", title: "East"),
        .init(id: "bbc_one_east_midlands", title: "East Midlands"),
        .init(id: "bbc_one_east_yorkshire", title: "East Yorks & Lincs"),
        .init(id: "bbc_one_london", title: "London"),
        .init(id: "bbc_one_north_east", title: "North East & Cumbria"),
        .init(id: "bbc_one_north_west", title: "North West"),
        .init(id: "bbc_one_northern_ireland", title: "Northern Ireland"),
        .init(id: "bbc_one_scotland", title: "Scotland"),
        .init(id: "bbc_one_south", title: "South"),
        .init(id: "bbc_one_south_east", title: "South East"),
        .init(id: "bbc_one_south_west", title: "South West"),
        .init(id: "bbc_one_wales", title: "Wales"),
        .init(id: "bbc_one_west", title: "West"),
        .init(id: "bbc_one_west_midlands", title: "West Midlands"),
        .init(id: "bbc_one_yorks", title: "Yorkshire"),
    ]
    static let bbcTwo: [RegionalChannelChoice] = [
        .init(id: "bbc_two_england", title: "England / Scotland"),
        .init(id: "bbc_two_northern_ireland_digital", title: "Northern Ireland"),
        .init(id: "bbc_two_wales_digital", title: "Wales")
    ]
    static func selectedID(for id: String, defaults: UserDefaults = .standard) -> String {
        let choices: [RegionalChannelChoice], key: String
        switch id {
        case "bbc_one_london": choices = bbcOne; key = "bbcOneRegion"
        case "bbc_two_england": choices = bbcTwo; key = "bbcTwoRegion"
        default: return id
        }
        guard let selected = defaults.string(forKey: key), choices.contains(where: { $0.id == selected }) else { return id }
        return selected
    }
}

/// Curated event services; do not enumerate unadvertised stream numbers.
struct AdditionalLiveStream: Identifiable {
    let id: String
    let title: String
    static let all = [
        AdditionalLiveStream(id: "red_button_one", title: "Red Button"),
        AdditionalLiveStream(id: "uk_bbc_stream_041", title: "Red Button UHD")
    ]
    static let uhdManifest = URL(string: "https://ve-uhd-push-uk-live.akamaized.net/x=4/i=urn:bbc:pips:service:uk_bbc_stream_041/iptv_uhd_v1.mpd")!
}
