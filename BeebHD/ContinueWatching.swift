// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@MainActor private final class ContinueState: ObservableObject {
    @Published var preparing = false
    @Published var playing = false
    @Published var error: String?
    @Published var browse: CatalogueShow?
    var operation: Task<Void, Never>?
}
struct ContinueWatchingRow: View {
    @EnvironmentObject private var history: WatchHistory
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @StateObject private var state = ContinueState()
    @StateObject private var playback = PlaybackModel()
    var body: some View {
        if !history.records.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text("Continue Watching").font(.title2).bold()
                if state.preparing || playback.loading { ProgressView("Getting your episode…") }
                if let error = state.error ?? playback.error { Text(error).font(.callout).foregroundStyle(.orange) }
                if let warning = history.warning { Text(warning).font(.callout).foregroundStyle(.orange) }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 28) {
                        ForEach(history.records) { record in
                            Button { open(record) } label: { ContinueCard(record: record).frame(width: 390) }
                                .buttonStyle(ProgrammeCardStyle()).disabled(state.preparing || playback.loading).rememberSidebarFocus()
                                .contextMenu { Button("Remove from Continue Watching") { history.remove(record.id) } }
                        }
                    }.padding(.vertical, 30).padding(.horizontal, 24)
                }.scrollClipDisabled().padding(.horizontal, -24)
            }
            .fullScreenCover(isPresented: $state.playing, onDismiss: { playback.stop() }) { PlaybackScreen(model: playback) }
            .sheet(item: $state.browse) { CatalogueShowView(show: $0, catalogue: catalogue, library: library) }
            .onDisappear {
                if !state.playing { state.operation?.cancel(); playback.stop() }
            }
        }
    }
    private func open(_ record: WatchRecord) {
        state.operation?.cancel(); state.preparing = true; state.error = nil
        state.operation = Task { @MainActor in
            defer { state.preparing = false }
            do {
                var show = record.show
                if let saved = show {
                    do { show = try await catalogue.open(saved) }
                    catch { if Task.isCancelled { throw CancellationError() }; if record.target == nil { throw error } }
                }
                try Task.checkCancellation()
                let episode: CatalogueEpisode?
                if record.completed {
                    if let show {
                        let availableKnownNext = show.indexedAt == nil ? record.nextEpisode : record.nextEpisode.flatMap { next in show.episodes.first { $0.id == next.id } }
                        episode = EpisodeSequence.next(after: record.episode, in: show) ?? availableKnownNext
                    }
                    else { episode = record.nextEpisode }
                } else { episode = show?.episodes.first { $0.id == record.episode.id } ?? record.episode }
                guard let episode else {
                    state.error = "No next episode is currently available."
                    state.browse = show
                    return
                }
                playback.start(episode.programme, history: history, show: show) { state.playing = true }
            } catch { if !Task.isCancelled { state.error = error.localizedDescription } }
        }
    }
}
// progress line on the picture, label above the title (official-app style).
struct ContinueCard: View {
    let record: WatchRecord
    @Environment(\.isFocused) private var focused
    private var episode: CatalogueEpisode { record.completed ? record.nextEpisode ?? record.episode : record.episode }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgrammeThumbnail(url: episode.programme.image ?? record.show?.image, uhd: episode.programme.uhdListed == true, hdr: episode.programme.hdrListed == true)
                .overlay(alignment: .bottom) {
                    if !record.completed {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.45))
                                Rectangle().fill(Color.pink).frame(width: g.size.width * record.fraction)
                            }
                        }.frame(height: 6).clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            Text(record.completed ? (record.nextEpisode == nil ? "Check for next episode" : "Up next") : "Resume · \(record.remainingMinutes) min left")
                .font(.system(size: 21)).foregroundStyle(.secondary).lineLimit(1).padding(.top, 10)
            Text(record.show?.title ?? episode.programme.showTitle ?? episode.programme.title)
                .font(.system(size: 28, weight: .semibold)).lineLimit(1)
                .foregroundStyle(focused ? Color.white : Color.white.opacity(0.8))
            Text(episode.subtitle).font(.system(size: 22)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}
