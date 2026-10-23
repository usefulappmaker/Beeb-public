// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct UHDCategoryView: View {
    @ObservedObject var index: CatalogueIndexStore
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @Environment(\.scenePhase) private var phase
    private var shows: [CatalogueShow] { index.uhd }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("4K UHD").font(.largeTitle).bold()
                if let error = index.error { Text(error).font(.callout).foregroundStyle(.orange) }
                HStack {
                    Text("\(shows.count) programmes").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { index.requestRefresh() } label: {
                        Label("Check for updates", systemImage:"arrow.clockwise")
                    }.disabled(index.loading)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 28)], spacing: 30) {
                    ForEach(shows) { show in
                        NavigationLink { CatalogueShowView(show: show, catalogue: catalogue, library: library, preferUHDSeries: true) } label: {
                            ShowCard(show: show)
                        }.buttonStyle(ProgrammeCardStyle())
                    }
                }
                if shows.isEmpty && !index.loading { Text("No UHD listings are currently saved. Check for updates to retry.") }
            }.padding(60)
        }
    }
}

private struct SearchRequest: Hashable { let query: String; let revision: Int }

struct CatalogueSearchView: View {
    @ObservedObject var index: CatalogueIndexStore
    @ObservedObject var catalogue: CatalogueStore
    @ObservedObject var library: Library
    @Environment(\.scenePhase) private var phase
    @State private var query = ""
    @State private var page = 1
    @State private var results: [CatalogueShow] = []
    @State private var searching = false
    private var pages: Int { max(1, (results.count + 29) / 30) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 24) {
                        Text("\(results.count) \(results.count == 1 ? "result" : "results")").font(.title3)
                        Spacer()
                        if pages > 1 {
                            Button("Previous") { page -= 1 }.disabled(page <= 1)
                            Text("\(min(page, pages)) / \(pages)")
                            Button("Next") { page += 1 }.disabled(page >= pages)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 28)], spacing: 30) {
                        ForEach(Array(results.dropFirst((min(page, pages) - 1) * 30).prefix(30))) { show in
                            NavigationLink { CatalogueShowView(show: show, catalogue: catalogue, library: library) } label: { ShowCard(show: show) }.buttonStyle(ProgrammeCardStyle())
                        }
                    }
                    if searching { ProgressView("Searching…") }
                    else if results.isEmpty { Text("No results.") }
                }
            }.padding(60)
        }
        .searchable(text: $query, prompt: "Search")
        .task(id: SearchRequest(query: query, revision: index.searchRevision)) {
            page = 1
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results = []; searching = false; return
            }
            searching = true
            do {
                // Coalesce partial dictated words without delaying the text field.
                try await Task.sleep(for: .milliseconds(120))
                let matches = try await index.search(query)
                try Task.checkCancellation()
                results = matches; searching = false
            } catch { if !Task.isCancelled { searching = false } }
        }
        #if DEBUG
        .onAppear { if let preview = ProcessInfo.processInfo.environment["BEEB_SEARCH_QUERY"] { query = preview } }
        #endif
    }
}
#if DEBUG
/// Render the real cached UHD screen without a live catalogue refresh during UI validation.
struct UHDLayoutValidationView: View {
    @StateObject private var index = CatalogueIndexStore()
    @StateObject private var catalogue = CatalogueStore()
    @StateObject private var library = Library()
    @StateObject private var history = WatchHistory()
    var body: some View {
        NavigationStack { UHDCategoryView(index: index, catalogue: catalogue, library: library) }
            .environmentObject(history).task { await index.prepare() }
    }
}
#endif
