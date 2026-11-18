// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// A programme page: summary, series picker and episodes. Clicking an episode plays it.
struct MacShowView: View {
    let show: CatalogueShow
    var preferUHDSeries = false
    @EnvironmentObject private var catalogue: CatalogueStore
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var history: WatchHistory
    @EnvironmentObject private var player: MacPlayerController
    @State private var loaded: CatalogueShow?
    @State private var seriesID = ""
    @State private var error: String?
    @State private var retry = 0
    @State private var uhdConfigured = true
    private var current: CatalogueShow { loaded ?? show }
    private var orderedSeries: [CatalogueSeries] { EpisodeSequence.orderedSeries(current.series) }
    /// Open on a numbered series where there is one, not the loose group of recaps and extras.
    private var defaultSeries: CatalogueSeries? {
        orderedSeries.first { $0.title != "Episodes" && !$0.id.hasSuffix("extras") } ?? orderedSeries.first
    }
    private var selectedSeriesID: String { orderedSeries.contains { $0.id == seriesID } ? seriesID : defaultSeries?.id ?? "" }
    private var episodes: [CatalogueEpisode] {
        EpisodeSequence.ordered(orderedSeries.first { $0.id == selectedSeriesID }?.episodes ?? [])
    }
    private var record: WatchRecord? { history.records.first { $0.id == current.id } }
    /// The episode the main Play button starts: the one in progress, else the first listed.
    private var primary: CatalogueEpisode? {
        if let record, !record.completed, let match = current.episodes.first(where: { $0.id == record.episode.id }) { return match }
        if let record, record.completed, let next = EpisodeSequence.next(after: record.episode, in: current) { return next }
        return EpisodeSequence.ordered(defaultSeries?.episodes ?? []).first
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 22) {
                    MacThumbnail(url: current.image, uhd: current.uhdListed == true).frame(width: 340)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(current.title).font(.largeTitle.bold())
                        Text(current.summary).font(.title3).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack(spacing: 12) {
                            if let primary {
                                Button { player.play(primary.programme, show: current, history: history) } label: {
                                    Label(history.resumePosition(for: primary.id) > 0 ? "Resume" : "Play", systemImage: "play.fill").padding(.horizontal, 6)
                                }.buttonStyle(.borderedProminent).controlSize(.large).tint(.pink).keyboardShortcut(.defaultAction)
                            }
                            Button { library.toggle(current) } label: {
                                Label(library.contains(current) ? "Saved" : "Save", systemImage: library.contains(current) ? "bookmark.fill" : "bookmark")
                            }.controlSize(.large).accessibilityLabel(library.contains(current) ? "Remove saved programme" : "Save programme")
                        }
                        if let primary, current.episodes.count > 1 {
                            Text(primary.subtitle).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                if current.uhdListed == true && !uhdConfigured {
                    Text("Choose Enable BBC UHD in Settings to set up 4K playback. Until then, episodes play in HD.").font(.callout).foregroundStyle(.secondary)
                }
                if loaded == nil && error == nil { ProgressView("Getting series and episodes…") }
                if let error {
                    MacWarning(error)
                    Button("Retry") { retry += 1 }
                }
                if orderedSeries.count > 1 {
                    Picker("Series", selection: Binding(get: { selectedSeriesID }, set: { seriesID = $0 })) {
                        ForEach(orderedSeries) { Text($0.title).tag($0.id) }
                    }.pickerStyle(.menu).fixedSize()
                }
                LazyVGrid(columns: MacTheme.grid, spacing: 14) {
                    ForEach(episodes) { episode in MacEpisodeCard(episode: episode, show: current) }
                }
                if loaded != nil && episodes.isEmpty { Text("No episodes are currently available.").foregroundStyle(.secondary) }
            }.padding(MacTheme.pagePadding).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MacTheme.background)
        .navigationTitle(current.title)
        .task(id: retry) {
            error = nil
            uhdConfigured = UHDIdentityVault.isConfigured
            do {
                loaded = try await catalogue.open(show)
                if preferUHDSeries && seriesID.isEmpty {
                    seriesID = orderedSeries.first { $0.episodes.contains { $0.programme.uhdListed == true } }?.id ?? ""
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct MacEpisodeCard: View {
    let episode: CatalogueEpisode
    let show: CatalogueShow
    @EnvironmentObject private var history: WatchHistory
    @EnvironmentObject private var player: MacPlayerController
    private var progress: Double? {
        guard let record = history.records.first(where: { $0.episode.id == episode.id }), !record.completed else { return nil }
        return record.fraction
    }
    var body: some View {
        Button { player.play(episode.programme, show: show, history: history) } label: {
            VStack(alignment: .leading, spacing: 6) {
                MacThumbnail(url: episode.programme.image, uhd: episode.programme.uhdListed == true, progress: progress)
                Text(episode.subtitle).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                if !episode.programme.summary.isEmpty {
                    Text(episode.programme.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    if !episode.duration.isEmpty { Text(episode.duration) }
                    if let date = episode.programme.firstBroadcast, !date.isEmpty { Text(date) }
                }.font(.caption).foregroundStyle(.tertiary)
                if let guidance = episode.programme.guidance, !guidance.isEmpty {
                    Text(guidance).font(.caption).foregroundStyle(.orange).lineLimit(2).multilineTextAlignment(.leading)
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .buttonStyle(MacCardStyle())
        .contextMenu {
            Button("Play") { player.play(episode.programme, show: show, history: history) }
            if progress != nil { Button("Play from the beginning") { player.play(episode.programme, show: show, history: history, restart: true) } }
        }
    }
}
