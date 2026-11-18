// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct MacBrowseView: View {
    @EnvironmentObject private var catalogue: CatalogueStore
    @AppStorage("display4KUHDCategory") private var display4KUHDCategory = true
    @AppStorage("macBrowseMode") private var mode = "Categories"
    var body: some View {
        MacPage(title: "Browse") {
            Picker("Browse by", selection: $mode) {
                Text("Categories").tag("Categories")
                Text("A–Z").tag("A–Z")
            }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
            if mode == "Categories" {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    if display4KUHDCategory {
                        NavigationLink(value: MacRoute.uhd) { MacCategoryTile(title: "4K UHD", icon: "4k.tv") }.buttonStyle(MacCardStyle())
                    }
                    ForEach(catalogue.genres) { genre in
                        NavigationLink(value: MacRoute.category(genre)) { MacCategoryTile(title: genre.title, icon: MacCategoryTile.icon(genre.id)) }
                            .buttonStyle(MacCardStyle())
                    }
                }
                if catalogue.genres.isEmpty && catalogue.loading { ProgressView("Getting categories…") }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach(CatalogueAPI.letters, id: \.self) { letter in
                        NavigationLink(value: MacRoute.letter(letter)) {
                            Text(letter.uppercased()).font(.title2.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(MacCardStyle())
                    }
                }
            }
        }
    }
}

private struct MacCategoryTile: View {
    let title: String
    let icon: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.pink).frame(width: 34)
            Text(title).font(.title3.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }
    static func icon(_ id: String) -> String {
        switch id {
        case "drama-and-soaps": "theatermasks"
        case "films": "film"
        case "comedy": "face.smiling"
        case "documentaries": "doc.text.image"
        case "sport": "sportscourt"
        case "news": "newspaper"
        case "entertainment": "sparkles.tv"
        case "music": "music.note"
        case "food": "fork.knife"
        case "lifestyle": "house"
        case "history": "clock.arrow.circlepath"
        case "science-and-nature": "leaf"
        case "arts": "paintpalette"
        case "archive": "archivebox"
        default: "play.rectangle"
        }
    }
}

/// One category or A–Z letter; further pages load as the grid nears its end.
struct MacProgrammePage: View {
    let title: String
    let category: String?
    let letter: String?
    @StateObject private var page = ContinuousCatalogueStore()
    var body: some View {
        MacPage(title: title) {
            if page.count > 0 { Text("\(page.count) programmes").font(.callout).foregroundStyle(.secondary) }
            LazyVGrid(columns: MacTheme.grid, spacing: 14) {
                ForEach(Array(page.shows.enumerated()), id: \.element.id) { position, show in
                    MacShowLink(show: show)
                        .task { if position >= page.shows.count - 6 { await page.next(category: category, letter: letter) } }
                }
            }
            if page.loading { ProgressView() }
            if let error = page.error {
                MacWarning(error)
                Button("Retry") { Task { await page.next(category: category, letter: letter) } }
            }
        }
        .navigationTitle(title)
        .task { await page.next(category: category, letter: letter) }
    }
}

struct MacUHDView: View {
    @EnvironmentObject private var index: CatalogueIndexStore
    var body: some View {
        MacPage(title: "4K UHD") {
            if let error = index.error { MacWarning(error) }
            HStack {
                Text("\(index.uhd.count) programmes").font(.callout).foregroundStyle(.secondary)
                if index.loading { ProgressView().controlSize(.small) }
                if !index.status.isEmpty { Text(index.status).font(.callout).foregroundStyle(.tertiary).lineLimit(1) }
                Spacer()
                Button { index.requestRefresh() } label: { Label("Check for updates", systemImage: "arrow.clockwise") }.disabled(index.loading)
            }
            MacShowGrid(shows: index.uhd, preferUHD: true)
            if index.uhd.isEmpty && !index.loading { Text("No UHD listings are currently saved. Check for updates to retry.").foregroundStyle(.secondary) }
        }.navigationTitle("4K UHD")
    }
}

struct MacSearchView: View {
    @EnvironmentObject private var index: CatalogueIndexStore
    @State private var query = ""
    @State private var results = [CatalogueShow]()
    @FocusState private var fieldFocused: Bool
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        MacPage(title: "Search") {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Programme title or description", text: $query).textFieldStyle(.plain).font(.title3).focused($fieldFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }.padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: 520)
            if !trimmed.isEmpty {
                Text("\(results.count) \(results.count == 1 ? "result" : "results")").font(.callout).foregroundStyle(.secondary)
                MacShowGrid(shows: results)
            } else if index.loading {
                HStack { ProgressView().controlSize(.small); Text(index.status.isEmpty ? "Updating the programme catalogue…" : index.status).foregroundStyle(.secondary) }
            } else {
                Text("Search covers the full A–Z programme catalogue by title and description.").foregroundStyle(.secondary)
            }
        }
        .onAppear {
            fieldFocused = true
            #if DEBUG
            if let preview = ProcessInfo.processInfo.environment["BEEB_SEARCH_QUERY"] { query = preview }
            #endif
        }
        // Search off the keystroke path: a short pause, then one pass over the cached index.
        .task(id: "\(trimmed)-\(index.snapshot.catalogue.count)") {
            guard !trimmed.isEmpty else { results = []; return }
            do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            results = index.snapshot.search(trimmed)
        }
    }
}

struct MacSavedView: View {
    @EnvironmentObject private var library: Library
    var body: some View {
        MacPage(title: "Saved") {
            if let warning = library.migrationWarning { MacWarning(warning) }
            if library.saved.isEmpty { Text("Save a programme to follow all of its series and episodes here.").foregroundStyle(.secondary) }
            MacShowGrid(shows: library.saved)
        }.task { await library.migrate(); await library.refreshArtwork() }
    }
}

struct MacLiveView: View {
    @EnvironmentObject private var player: MacPlayerController
    @Environment(\.scenePhase) private var phase
    @State private var channels = [LiveChannel]()
    @State private var error: String?
    @State private var retry = 0
    @AppStorage("macLiveMode") private var mode = "Channels"
    var body: some View {
        MacPage(title: "Live") {
            Picker("Show", selection: $mode) {
                Text("Channels").tag("Channels")
                Text("Guide").tag("Guide")
            }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
            if channels.isEmpty && error == nil { ProgressView("Getting channels…") }
            if let error {
                MacWarning(error)
                Button("Retry channels") { retry += 1 }
            }
            if mode == "Guide" { MacGuideView(channels: channels) }
            else { channelGrid }
        }
        // Schedules refresh each minute while this page is in front and nothing is playing.
        .task(id: "\(retry)-\(phase)-\(player.presented)") {
            guard phase == .active, !player.presented else { return }
            error = nil
            do {
                let api = DiscoveryAPI()
                if channels.isEmpty { channels = try await api.channels() }
                while !Task.isCancelled {
                    let updated = await api.nowPlaying(channels)
                    try Task.checkCancellation(); channels = updated
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private var channelGrid: some View {
            LazyVGrid(columns: MacTheme.grid, spacing: 14) {
                ForEach(channels) { channel in
                    Button { player.playLive(channel) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            MacThumbnail(url: channel.current?.image)
                            Text(channel.current?.title ?? channel.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                            Text(channel.title).font(.callout).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(MacCardStyle())
                }
            }
    }
}
