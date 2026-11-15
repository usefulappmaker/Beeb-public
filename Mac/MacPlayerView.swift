// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AVKit

/// One player for the whole window. Starting playback presents the player
/// immediately, so stream discovery and any error are shown in place.
@MainActor final class MacPlayerController: ObservableObject {
    let model = PlaybackModel()
    @Published var presented = false
    func play(_ programme: Programme, show: CatalogueShow?, history: WatchHistory, restart: Bool = false) {
        presented = true
        model.start(programme, history: history, show: show, restart: restart) {}
    }
    func playLive(_ channel: LiveChannel) {
        presented = true
        model.startLive(channel) {}
    }
    func close() {
        model.stop()
        presented = false
    }
}

/// AppKit's player view: native transport bar, subtitle and audio menus, speeds and PiP.
struct MacPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        // The window's own full screen keeps Beeb's title bar and Skip button visible.
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = true
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

/// The dynamic range of the video actually being received, not what the catalogue lists.
@MainActor enum MacVideoRange {
    static func received(_ item: AVPlayerItem?) async -> String? {
        guard let item else { return nil }
        // The decoded track's own signalling is the best evidence.
        for track in item.tracks where track.isEnabled {
            guard let asset = track.assetTrack, asset.mediaType == .video,
                  let descriptions = try? await asset.load(.formatDescriptions) else { continue }
            for description in descriptions {
                guard let transfer = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String else { continue }
                if transfer == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String { return "HLG" }
                if transfer == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String { return "PQ" }
                return nil
            }
        }
        // Streamed tracks may not expose a format description: use the playlist's
        // VIDEO-RANGE for the rendition whose size is being presented.
        let height = item.presentationSize.height
        guard height > 0, let asset = item.asset as? AVURLAsset, let variants = try? await asset.load(.variants) else { return nil }
        let playing = variants.filter { $0.videoAttributes?.presentationSize.height == height }
        guard !playing.isEmpty else { return nil }
        if playing.allSatisfy({ $0.videoAttributes?.videoRange == .hlg }) { return "HLG" }
        if playing.allSatisfy({ $0.videoAttributes?.videoRange == .pq }) { return "PQ" }
        return nil
    }
}

struct MacPlayerScreen: View {
    @ObservedObject var model: PlaybackModel
    let close: () -> Void
    @State private var chromeVisible = true
    @State private var hideChrome: Task<Void, Never>?
    @State private var showInfo = false
    @State private var videoRange: String?
    private var paused: Bool { model.player.timeControlStatus == .paused }
    var body: some View {
        ZStack {
            Color.black
            MacPlayerView(player: model.player)
            if model.loading {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(model.status).foregroundStyle(.secondary)
                }
            }
            if let error = model.error {
                VStack(spacing: 16) {
                    Text(error).foregroundStyle(.orange).multilineTextAlignment(.center).frame(maxWidth: 520).textSelection(.enabled)
                    Button("Close player", action: close).keyboardShortcut(.defaultAction)
                }.padding(28).background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
            }
            VStack(spacing: 0) {
                titleBar.opacity(chromeVisible || model.loading || model.error != nil ? 1 : 0)
                Spacer()
                if let marker = model.activeSkip {
                    HStack {
                        Spacer()
                        Button(marker.title) { model.skip(marker) }
                            .buttonStyle(.borderedProminent).controlSize(.large).tint(.white.opacity(0.25))
                            .padding(.trailing, 32).padding(.bottom, 96)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onContinuousHover { phase in if case .active = phase { revealChrome() } }
        .onAppear { revealChrome() }
        .onDisappear { hideChrome?.cancel() }
        // Re-check whenever the received quality changes, including a switch of stream.
        .task(id: model.qualityBadge) { videoRange = model.qualityBadge == nil ? nil : await MacVideoRange.received(model.player.currentItem) }
        .alert("Additional stream unavailable", isPresented: Binding(get: { model.additionalStreamError != nil }, set: { if !$0 { model.additionalStreamError = nil } })) {
            Button("OK") { model.additionalStreamError = nil }
        } message: { Text(model.additionalStreamError ?? "") }
    }
    private var titleBar: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: close) { Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                .keyboardShortcut(.cancelAction).help("Close player (Esc)")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayTitle).font(.title3.bold()).lineLimit(1)
                HStack(spacing: 8) {
                    if model.isLive {
                        Text("LIVE").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: RoundedRectangle(cornerRadius: 3))
                    }
                    if !model.displaySubtitle.isEmpty { Text(model.displaySubtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                    if let badge = model.qualityBadge {
                        Text(badge).font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.8)) }
                            .accessibilityLabel("Playing in \(badge)")
                        if let videoRange {
                            Text("HDR").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.8)) }
                                .help("Receiving \(videoRange) high dynamic range video")
                                .accessibilityLabel("High dynamic range, \(videoRange)")
                        }
                    }
                }
            }
            Spacer()
            if model.isLive {
                Menu {
                    ForEach(AdditionalLiveStream.all) { stream in Button(stream.title) { model.switchAdditionalStream(stream) } }
                } label: { Label("Additional streams", systemImage: "dot.radiowaves.left.and.right") }
                    .menuStyle(.borderlessButton).fixedSize().disabled(model.switchingAdditionalStream)
            }
            if model.infoProgramme != nil {
                Button { showInfo.toggle() } label: { Label("Info", systemImage: "info.circle") }
                    .popover(isPresented: $showInfo, arrowEdge: .bottom) { MacPlayerInfo(model: model) }
            }
            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right").labelStyle(.iconOnly) }
                .help("Toggle full screen")
        }
        .buttonStyle(.bordered).foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.top, 34).padding(.bottom, 26)
        .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
        .animation(.easeOut(duration: 0.2), value: chromeVisible)
    }
    private func revealChrome() {
        chromeVisible = true
        hideChrome?.cancel()
        hideChrome = Task {
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEEB_MAC_CHROME"] == "1" { return }
            #endif
            if !showInfo && !paused { chromeVisible = false }
        }
    }
}

/// Programme details for the episode being played.
private struct MacPlayerInfo: View {
    @ObservedObject var model: PlaybackModel
    private var footer: String {
        let duration = model.player.currentItem?.duration.seconds ?? .nan
        let runtime = model.infoProgramme?.durationText ?? (duration.isFinite && duration > 0 ? "\(max(1, Int(ceil((duration - 0.5) / 60)))) min" : nil)
        return [model.infoProgramme?.firstBroadcast, runtime, model.qualityBadge].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  •  ")
    }
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let data = model.infoArtwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 200).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 8) {
                let title = model.infoProgramme?.showTitle ?? model.displayTitle
                Text(model.displaySubtitle.isEmpty || title.contains(model.displaySubtitle) ? title : "\(title) — \(model.displaySubtitle)").font(.headline)
                ScrollView { Text(PlaybackInfoMetadata.synopsis(model.infoProgramme)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxHeight: 180)
                if !footer.isEmpty { Text(footer).font(.callout) }
            }.frame(width: 380, alignment: .leading)
        }.padding(18)
    }
}
