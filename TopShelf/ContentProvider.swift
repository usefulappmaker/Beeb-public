// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import TVServices
import UIKit

final class ContentProvider: TVTopShelfContentProvider {
    private struct Snapshot: Codable { let date: Date; let channels: [LiveShelfChannel] }
    private var cacheURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("live-shelf.json") }
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task { @MainActor in
            let source = TopShelfShared.source
            let snapshot = TopShelfShared.snapshot()
            var sections = [TVTopShelfItemCollection<TVTopShelfSectionedItem>]()
            if source == .continueWatching || source == .mix, let section = section("Continue Watching", snapshot.continueWatching) { sections.append(section) }
            if source == .saved || source == .mix, let section = section("Saved", snapshot.saved) { sections.append(section) }
            // Live TV is the shelf for its own setting, part of Mix, and the fallback when a chosen list is empty.
            if source == .live || source == .mix || sections.isEmpty { sections.append(liveSection(await liveChannels())) }
            completionHandler(TVTopShelfSectionedContent(sections: sections))
        }
    }
    @MainActor private func section(_ title: String, _ entries: [TopShelfEntry]) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        let items = entries.map { entry -> TVTopShelfSectionedItem in
            let item = TVTopShelfSectionedItem(identifier: title + "-" + entry.id)
            item.title = entry.subtitle.map { "\(entry.title) · \($0)" } ?? entry.title
            item.imageShape = .hdtv
            item.displayAction = TVTopShelfAction(url: entry.displayURL); item.playAction = TVTopShelfAction(url: entry.playURL)
            if let progress = entry.progress { item.playbackProgress = progress }
            if let image = entry.image { item.setImageURL(image, for: .screenScale1x); item.setImageURL(image, for: .screenScale2x) }
            return item
        }
        guard !items.isEmpty else { return nil }
        let section = TVTopShelfItemCollection(items: items); section.title = title
        return section
    }
    @MainActor private func liveChannels() async -> [LiveShelfChannel] {
        do {
            let saved = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
            if let saved, !saved.channels.isEmpty, Date().timeIntervalSince(saved.date) < 600 {
                return saved.channels
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 2; configuration.timeoutIntervalForResource = 4
            configuration.httpMaximumConnectionsPerHost = 8
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            var channels = saved?.channels ?? LiveShelfChannel.defaults
            var refreshed = false
            if let (data, response) = try? await session.data(from: URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/channels")!),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let values = root["channels"] as? [[String: Any]] {
                let available = values.compactMap { value -> LiveShelfChannel? in
                    guard value["has_schedule"] as? Bool == true, let id = value["id"] as? String,
                          LiveChannelLink.validID(id), let title = value["title"] as? String else { return nil }
                    return LiveShelfChannel(id: id, title: title)
                }
                if !available.isEmpty { channels = available; refreshed = true }
            }
            channels = await withTaskGroup(of: (Int, LiveShelfChannel).self) { group in
                for (index, entry) in channels.enumerated() {
                    group.addTask {
                        var entry = entry
                        let url = URL(string: "https://ibl.api.bbc.co.uk/ibl/v1/channels/\(entry.id)/broadcasts?per_page=20")!
                        if let (data, _) = try? await session.data(from: url), let image = LiveShelfArtwork.current(data) { entry.image = image }
                        return (index, entry)
                    }
                }
                var entries = [(Int, LiveShelfChannel)]()
                for await entry in group { entries.append(entry) }
                return entries.sorted { $0.0 < $1.0 }.map(\.1)
            }
            if refreshed || saved == nil {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(Snapshot(date: Date(), channels: channels)) { try? data.write(to: cacheURL, options: .atomic) }
            }
            return channels
        }
    }
    @MainActor private func liveSection(_ channels: [LiveShelfChannel]) -> TVTopShelfItemCollection<TVTopShelfSectionedItem> {
        let items = channels.compactMap { channel -> TVTopShelfSectionedItem? in
            guard let url = LiveChannelLink.url(for: channel.id) else { return nil }
            let item = TVTopShelfSectionedItem(identifier: channel.id)
            item.title = channel.title; item.imageShape = .hdtv
            item.displayAction = TVTopShelfAction(url: url); item.playAction = TVTopShelfAction(url: url)
            let image = channel.image ?? fallbackImage(channel)
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
            return item
        }
        let section = TVTopShelfItemCollection(items: items); section.title = "Live TV"
        return section
    }
    @MainActor private func fallbackImage(_ channel: LiveShelfChannel) -> URL? {
        let url = cacheURL.deletingLastPathComponent().appendingPathComponent("\(channel.id).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360)).image { context in
            UIColor(white: 0.08, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 44, weight: .bold), .foregroundColor: UIColor.white]
            (channel.title as NSString).draw(in: CGRect(x: 40, y: 140, width: 560, height: 120), withAttributes: attributes)
        }
        guard let data = image.pngData() else { return nil }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        return url
    }
}
