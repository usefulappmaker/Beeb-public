// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import TVServices

/// Copies Saved and Continue Watching into the App Group for the Top Shelf extension.
enum TopShelfPublisher {
    @MainActor static func publish(saved: [CatalogueShow], records: [WatchRecord]) {
        // Round progress so normal playback updates do not reload the shelf every few seconds.
        func rounded(_ value: Double) -> Double { max(0.02, (value * 20).rounded() / 20) }
        let continueEntries = records.prefix(12).compactMap { record -> TopShelfEntry? in
            guard let resume = BeebLink.resumeURL(record.id) else { return nil }
            let episode = record.completed ? record.nextEpisode ?? record.episode : record.episode
            return TopShelfEntry(id: record.id, title: record.show?.title ?? episode.programme.showTitle ?? episode.programme.title,
                                 subtitle: record.completed ? "Up next" : episode.subtitle,
                                 image: episode.programme.image ?? record.show?.image,
                                 displayURL: resume, playURL: resume, progress: record.completed ? nil : rounded(record.fraction))
        }
        let savedEntries = saved.prefix(12).compactMap { show -> TopShelfEntry? in
            guard let url = BeebLink.showURL(show.id) else { return nil }
            return TopShelfEntry(id: show.id, title: show.title, image: show.image, displayURL: url, playURL: url)
        }
        if TopShelfShared.write(TopShelfSnapshot(continueWatching: continueEntries, saved: savedEntries)) {
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }
}

struct TopShelfLinkRequest: Equatable {
    let id = UUID()
    let link: BeebLink
}

@MainActor private final class TopShelfLinkState: ObservableObject {
    @Published var show: CatalogueShow?
    @Published var playing = false
    @Published var preparing = false
}

/// Opens a programme page or resumes an episode when a Top Shelf item is chosen.
struct TopShelfLinkHost: View {
    let request: TopShelfLinkRequest?
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @EnvironmentObject private var history: WatchHistory
    @StateObject private var state = TopShelfLinkState()
    @StateObject private var playback = PlaybackModel()
    var body: some View {
        ZStack {
            if state.preparing || playback.loading { ProgressView("Getting your episode…").padding(40).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24)) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
        .task(id: request?.id) {
            guard let request else { return }
            // Let any existing player or sheet dismiss first, as Live links do.
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            await handle(request.link)
        }
        .sheet(item: $state.show) { CatalogueShowView(show: $0, catalogue: catalogue, library: library).environmentObject(history) }
        .fullScreenCover(isPresented: $state.playing, onDismiss: { playback.stop() }) { PlaybackScreen(model: playback) }
    }
    private func handle(_ link: BeebLink) async {
        switch link {
        case .show(let id):
            if let known = library.saved.first(where: { $0.id == id }) ?? history.records.compactMap(\.show).first(where: { $0.id == id }) {
                state.show = known
            } else {
                state.preparing = true; defer { state.preparing = false }
                state.show = try? await DiscoveryAPI().show(id)
            }
        case .resume(let id):
            guard let record = history.records.first(where: { $0.id == id }) else { return }
            state.preparing = true; defer { state.preparing = false }
            do {
                let (episode, show) = try await ContinueResolver.resolve(record, catalogue: catalogue)
                guard let episode else { state.show = show ?? record.show; return }
                playback.start(episode.programme, history: history, show: show) { state.playing = true }
            } catch { if !Task.isCancelled { state.show = record.show } }
        }
    }
}
