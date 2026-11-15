// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct MacHomeView: View {
    @EnvironmentObject private var catalogue: CatalogueStore
    @Environment(\.scenePhase) private var phase
    @State private var banner = 0
    @State private var bannerHovered = false
    private var features: [HomeFeature] { catalogue.home?.features ?? [] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !features.isEmpty {
                    MacFeatureBanner(features: features, index: $banner).onHover { bannerHovered = $0 }
                }
                VStack(alignment: .leading, spacing: 26) {
                    if let error = catalogue.error { MacWarning(error) }
                    MacContinueWatchingRow()
                    if let feed = catalogue.home {
                        ForEach(feed.rows) { MacHomeRow(row: $0) }
                    } else if catalogue.loading {
                        ProgressView("Getting the latest programmes…")
                    } else {
                        Button("Retry homepage") { Task { await catalogue.refreshHome() } }
                    }
                }.padding(.horizontal, MacTheme.pagePadding).padding(.bottom, MacTheme.pagePadding)
                    .padding(.top, features.isEmpty ? MacTheme.pagePadding : 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MacTheme.background)
        .task(id: "\(banner)-\(features.count)-\(bannerHovered)-\(phase)") {
            guard features.count > 1, !bannerHovered, phase == .active else { return }
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            withAnimation(.easeInOut(duration: 0.4)) { banner = (banner + 1) % features.count }
        }
    }
}

private struct MacFeatureBanner: View {
    let features: [HomeFeature]
    @Binding var index: Int
    private var feature: HomeFeature { features[min(index, features.count - 1)] }
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MacTheme.background
            GeometryReader { geometry in
                AsyncImage(url: feature.image) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
            LinearGradient(stops: [.init(color: .black.opacity(0.88), location: 0), .init(color: .black.opacity(0.45), location: 0.45), .init(color: .clear, location: 0.85)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.55), .init(color: MacTheme.background, location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED").font(.caption.weight(.semibold)).tracking(4).foregroundStyle(.pink)
                Text(feature.headline).font(.system(size: 38, weight: .bold)).lineLimit(2)
                Text(feature.synopsis).font(.title3).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                HStack(spacing: 12) {
                    NavigationLink(value: MacRoute.show(feature.show, preferUHD: false)) { Label("Watch now", systemImage: "play.fill").padding(.horizontal, 6) }
                        .buttonStyle(.borderedProminent).controlSize(.large).tint(.pink)
                    if feature.show.uhdListed == true { MacUHDBadge() }
                    if features.count > 1 {
                        Spacer()
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous featured programme")
                        Text("\(min(index, features.count - 1) + 1) / \(features.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        Button { step(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next featured programme")
                    }
                }.padding(.top, 6)
            }.frame(maxWidth: 720, alignment: .leading).padding(MacTheme.pagePadding).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 380).clipped()
    }
    private func step(_ offset: Int) {
        withAnimation(.easeInOut(duration: 0.25)) { index = (min(index, features.count - 1) + offset + features.count) % features.count }
    }
}

private struct MacHomeRow: View {
    let row: HomeRow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(row.title).font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(row.shows) { show in
                        if row.usesPosters {
                            NavigationLink(value: MacRoute.show(show, preferUHD: false)) {
                                AsyncImage(url: show.portraitImage) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { ZStack { Color(white: 0.12); Text(show.title).font(.headline).multilineTextAlignment(.center).padding(12) } }
                                }.frame(width: 170, height: 255).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(MacCardStyle()).accessibilityLabel(show.title)
                        } else {
                            MacShowLink(show: show).frame(width: 250)
                        }
                    }
                }.padding(.horizontal, MacTheme.pagePadding)
            }.padding(.horizontal, -MacTheme.pagePadding)
        }
    }
}

/// Resume an unfinished episode, or move on to the next one after a finished episode.
struct MacContinueWatchingRow: View {
    @EnvironmentObject private var history: WatchHistory
    @EnvironmentObject private var catalogue: CatalogueStore
    @EnvironmentObject private var player: MacPlayerController
    @State private var preparing = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    var body: some View {
        if !history.records.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Continue Watching").font(.title2.bold())
                    if preparing { ProgressView().controlSize(.small) }
                }
                if let error { MacWarning(error) }
                if let warning = history.warning { MacWarning(warning) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(history.records) { record in
                            Button { open(record) } label: { MacContinueCard(record: record).frame(width: 270) }
                                .buttonStyle(MacCardStyle()).disabled(preparing)
                                .contextMenu {
                                    if let show = record.show { NavigationLink("Go to programme", value: MacRoute.show(show, preferUHD: false)) }
                                    Button("Remove from Continue Watching") { history.remove(record.id) }
                                }
                        }
                    }.padding(.horizontal, MacTheme.pagePadding)
                }.padding(.horizontal, -MacTheme.pagePadding)
            }.onDisappear { operation?.cancel() }
        }
    }
    private func open(_ record: WatchRecord) {
        operation?.cancel(); preparing = true; error = nil
        operation = Task { @MainActor in
            defer { preparing = false }
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
                    } else { episode = record.nextEpisode }
                } else { episode = show?.episodes.first { $0.id == record.episode.id } ?? record.episode }
                guard let episode else { error = "No next episode is currently available."; return }
                player.play(episode.programme, show: show, history: history)
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct MacContinueCard: View {
    let record: WatchRecord
    private var episode: CatalogueEpisode { record.completed ? record.nextEpisode ?? record.episode : record.episode }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MacThumbnail(url: episode.programme.image ?? record.show?.image, uhd: episode.programme.uhdListed == true,
                         progress: record.completed ? nil : record.fraction)
            Text(record.show?.title ?? episode.programme.showTitle ?? episode.programme.title).font(.headline).lineLimit(1)
            Text(episode.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            Text(record.completed ? (record.nextEpisode == nil ? "Check for next episode" : "Up next") : "Resume · \(record.remainingMinutes) min left")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
