// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@main struct BeebHDApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEEB_REVIEW_PLAYER"] == "1" { ReviewPlaybackView().preferredColorScheme(.dark) }
            else if ProcessInfo.processInfo.environment["BEEB_CONTINUE_INFO_TEST"] == "1" { ResumeInfoValidationView().preferredColorScheme(.dark) }
            else if ProcessInfo.processInfo.environment["BEEB_PLAYER_LAYOUT"] == "1" { PlayerLayoutValidationView().preferredColorScheme(.dark) }
            else if ProcessInfo.processInfo.environment["BEEB_UHD_LAYOUT"] == "1" { UHDLayoutValidationView().preferredColorScheme(.dark) }
            else if ProcessInfo.processInfo.environment["BEEB_IDENTITY_VALIDATE"] == "1" { IdentityValidationView().preferredColorScheme(.dark) }
            else if ProcessInfo.processInfo.environment["BEEB_EXTRAS_VALIDATE"] == "1" { ExtrasValidationView().preferredColorScheme(.dark) }
            else if ProcessInfo.processInfo.environment["BEEB_PROGRESS_VALIDATE"] == "1" { ProgressValidationView().preferredColorScheme(.dark) }
            else if ["detail", "history", "programme"].contains(ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] ?? "") { HistoryLayoutValidationView().preferredColorScheme(.dark) }
            else if ProcessInfo.processInfo.environment["BEEBHD_UHD_VALIDATE"] == "1" { UHDValidationView().preferredColorScheme(.dark) }
            else { HomeView().preferredColorScheme(.dark) }
            #else
            HomeView().preferredColorScheme(.dark)
            #endif
        }
    }
}
struct ProgrammeCard: View {
    let programme: Programme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgrammeThumbnail(url: programme.image, uhd: programme.uhdListed == true, hdr: programme.hdrListed == true)
            Text(programme.episodeSubtitle ?? programme.title).font(.headline).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .topLeading)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct DetailView: View {
    @StateObject private var state = DetailViewState()
    let programme: Programme
    var show: CatalogueShow? = nil
    @ObservedObject var library: Library
    @StateObject private var playback = PlaybackModel()
    @EnvironmentObject private var history: WatchHistory
    @Environment(\.dismiss) private var dismiss
    private var details: Programme { state.fresh ?? programme }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(programme.showTitle ?? programme.title).font(.largeTitle).bold()
            if let subtitle = programme.episodeSubtitle, !subtitle.isEmpty { Text(subtitle).font(.title2) }
            Text(programme.summary).font(.title3)
            HStack(spacing: 18) {
                if details.uhdListed == true { UHDListedBadge(hdr: details.hdrListed == true) }
                if let duration = details.durationText, !duration.isEmpty { Text(duration).font(.callout).foregroundStyle(.secondary) }
            }
            if details.uhdListed == true && !UHDIdentityVault.isConfigured {
                Text("Choose Enable BBC UHD in Settings to set up 4K playback. Until then, this episode will play in HD.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let guidance = programme.guidance, !guidance.isEmpty { Text(guidance).foregroundStyle(.orange) }
            if history.resumePosition(for: programme.id) > 0 {
                Text("Your saved position will resume automatically.").font(.callout).foregroundStyle(.secondary)
            }
            Text(playback.status).font(.callout).foregroundStyle(.secondary)
            if let error = playback.error { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack(spacing: 24) {
                Button {
                    playback.start(programme, history: history, show: show) { state.playing = true }
                } label: {
                    if playback.loading { ProgressView().frame(width: 40, height: 46) }
                    else { Image("BeebMark").resizable().scaledToFit().frame(width: 40, height: 46) }
                }.accessibilityLabel(playback.loading ? "Finding the best stream" : "Play at the best available quality")
                    .disabled(playback.loading).buttonStyle(OutlinedActionButtonStyle(square: true))
                if !playback.loading, history.resumePosition(for: programme.id) > 0 {
                    Button("Start over") { playback.start(programme, history: history, show: show, restart: true) { state.playing = true } }
                }
                if playback.loading { Button("Cancel") { playback.stop() } }
                if let show {
                    ProgrammeBookmarkButton(show: show, library: library)
                }
                Button("Close") { dismiss() }
            }.buttonStyle(OutlinedActionButtonStyle())
        }.padding(70)
        .onExitCommand { dismiss() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEEB_UI_PREVIEW"] == "detail" { return }
            #endif
            state.fresh = try? await PlaybackExtrasAPI().programme(programme.id)
        }
        .fullScreenCover(isPresented: $state.playing, onDismiss: { playback.stop() }) { PlaybackScreen(model: playback) }
        .onDisappear { if !state.playing { playback.stop() } }
    }
}
@MainActor final class DetailViewState: ObservableObject {
    @Published var playing = false
    @Published var fresh: Programme?
}
struct UHDListedBadge: View {
    var hdr = false
    var body: some View {
        Text("4K").font(.system(size: 19, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.85)).foregroundStyle(.white).cornerRadius(6)
            .accessibilityLabel("BBC lists a 4K version")
    }
}

/// Clear action buttons retain the pink mark's contrast; focus uses a stronger
/// white outline, keeping all buttons the same height even when focused.
struct OutlinedActionButtonStyle: ButtonStyle {
    var square = false
    func makeBody(configuration: Configuration) -> some View {
        OutlinedActionSurface(content: configuration.label, pressed: configuration.isPressed, square: square)
    }
}
private struct OutlinedActionSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    let square: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        content.font(.system(size: 34, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, square ? 0 : 32).frame(width: square ? 84 : nil, height: 84)
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(enabled ? 1 : 0.4), lineWidth: focused ? 3 : 1.5) }
            .opacity(enabled ? (pressed ? 0.7 : 1) : 0.5)
            .animation(.easeOut(duration: 0.15), value: focused)
            .focusEffectDisabled()
    }
}

struct ProgrammeBookmarkButton: View {
    let show: CatalogueShow
    @ObservedObject var library: Library
    var body: some View {
        Button { library.toggle(show) } label: {
            Image(systemName: library.contains(show) ? "bookmark.fill" : "bookmark")
                .font(.system(size: 32, weight: .medium))
        }.buttonStyle(OutlinedActionButtonStyle(square: true))
            .accessibilityLabel(library.contains(show) ? "Remove saved programme" : "Save programme")
    }
}
