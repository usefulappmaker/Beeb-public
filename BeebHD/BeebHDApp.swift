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
// title always; synopsis only on the focused card (like the official app).
struct ProgrammeCard: View {
    let programme: Programme
    @Environment(\.isFocused) private var focused
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgrammeThumbnail(url: programme.image, uhd: programme.uhdListed == true, hdr: programme.hdrListed == true)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            Text(programme.episodeSubtitle ?? programme.title).font(.system(size: 28, weight: .semibold)).lineLimit(1)
                .foregroundStyle(focused ? Color.white : Color.white.opacity(0.75)).padding(.top, 8)
            Text(programme.summary).font(.system(size: 22)).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56, alignment: .topLeading)
                .opacity(focused ? 1 : 0)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
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
    @FocusState private var playFocused: Bool
    @State private var expanded = false
    private func clock(_ seconds: Double) -> String {
        let t = max(0, Int(seconds))
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
    var body: some View {
        let resume = history.resumePosition(for: programme.id)
        HStack(alignment: .top, spacing: 64) {
            VStack(alignment: .leading, spacing: 16) {
                Text(programme.showTitle ?? programme.title).font(.system(size: 50, weight: .bold)).lineLimit(2)
                if let subtitle = programme.episodeSubtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 32, weight: .medium)).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    if details.uhdListed == true { UHDListedBadge(hdr: details.hdrListed == true) }
                    if let duration = details.durationText, !duration.isEmpty {
                        Label(duration, systemImage: "clock").font(.callout).foregroundStyle(.secondary)
                    }
                }
                // medium synopsis, inline More/Less for the long one fetched on open.
                let shortText = programme.summary
                let longText = details.summary.count > shortText.count ? details.summary : shortText
                Text(expanded ? longText : shortText).font(.system(size: 28)).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(expanded ? 16 : 4).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: 0.2), value: expanded)
                if longText.count > shortText.count + 30 {
                    Button(expanded ? "Less" : "More") { expanded.toggle() }.buttonStyle(TextLinkButtonStyle())
                }
                if details.uhdListed == true && !UHDIdentityVault.isConfigured {
                    Text("Choose Enable BBC UHD in Settings to set up 4K playback. Until then, this episode will play in HD.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let guidance = programme.guidance, !guidance.isEmpty {
                    Label(guidance, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
                if let error = playback.error { Text(error).foregroundStyle(.orange).font(.callout) }
                else if playback.loading || playback.status != "Ready to play." {
                    Text(playback.status).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    Button {
                        playback.start(programme, history: history, show: show) { state.playing = true }
                    } label: {
                        HStack(spacing: 16) {
                            if playback.loading { ProgressView() } else { Image(systemName: "play.fill") }
                            Text(playback.loading ? "Finding stream…" : resume > 0 ? "Resume \(clock(resume))" : "Play")
                        }
                    }.buttonStyle(PrimaryPlayButtonStyle()).focused($playFocused).disabled(playback.loading)
                        .accessibilityLabel(playback.loading ? "Finding the best stream" : "Play at the best available quality")
                    if !playback.loading, resume > 0 {
                        Button("Start over") { playback.start(programme, history: history, show: show, restart: true) { state.playing = true } }
                    }
                    if playback.loading { Button("Cancel") { playback.stop() } }
                    if let show { ProgrammeBookmarkButton(show: show, library: library) }
                    Button("Close") { dismiss() }
                }.buttonStyle(OutlinedActionButtonStyle()).padding(.top, 12)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ProgrammeThumbnail(url: details.image ?? programme.image, uhd: false)
                .frame(width: 540).shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        }.padding(70)
        .frame(maxWidth: .infinity, maxHeight: .infinity)   // content fills the pop-up (glass background)
        .defaultFocus($playFocused, true)
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
// focused = solid white + dark text + lift; unfocused = faint fill.
private struct OutlinedActionSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    let square: Bool
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        content.font(.system(size: 34, weight: .medium)).foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, square ? 0 : 32).frame(width: square ? 84 : nil, height: 84)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(focused ? Color.white : Color.white.opacity(0.1)))
            .scaleEffect(pressed ? 0.97 : focused ? 1.06 : 1)
            .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 16, y: 8)
            .opacity(enabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: focused)
            .focusEffectDisabled()
    }
}
/// the main Play button.
struct PrimaryPlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryPlaySurface(content: configuration.label, pressed: configuration.isPressed)
    }
}
private struct PrimaryPlaySurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content.font(.system(size: 36, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 48).frame(minWidth: 260, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.pink.opacity(focused ? 1 : 0.5)))
            .scaleEffect(pressed ? 0.97 : focused ? 1.08 : 1)
            .shadow(color: .pink.opacity(focused ? 0.55 : 0), radius: 22, y: 6)
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

// small text link (More/Less).
struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TextLinkSurface(content: configuration.label) }
}
private struct TextLinkSurface<Content: View>: View {
    let content: Content
    @Environment(\.isFocused) private var focused
    var body: some View {
        content.font(.system(size: 24, weight: .semibold)).textCase(.uppercase)
            .foregroundStyle(focused ? Color.black : Color.pink)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Capsule().fill(focused ? Color.white : Color.clear))
            .scaleEffect(focused ? 1.06 : 1).animation(.easeOut(duration: 0.15), value: focused)
            .focusEffectDisabled()
    }
}
// series selector tile (pink bar under the selected series).
struct SeriesTabStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        SeriesTabSurface(content: configuration.label, selected: selected, pressed: configuration.isPressed)
    }
}
private struct SeriesTabSurface<Content: View>: View {
    let content: Content
    let selected: Bool
    let pressed: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content.font(.system(size: 30, weight: .semibold))
            .foregroundStyle(focused ? Color.black : Color.white.opacity(selected ? 1 : 0.7))
            .padding(.horizontal, 44).frame(minWidth: 240, minHeight: 88)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(focused ? Color.white : Color.black.opacity(0.5)))
            .overlay(alignment: .bottom) {
                if selected { Capsule().fill(Color.pink).frame(height: 6).padding(.horizontal, 4).offset(y: 3) }
            }
            .scaleEffect(pressed ? 0.97 : focused ? 1.05 : 1)
            .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.15), value: focused)
            .focusEffectDisabled()
    }
}
