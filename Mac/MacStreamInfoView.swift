// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AVFoundation

/// What is actually being received and shown, sampled once a second: the catalogue and the
/// playlist only say what was offered. Nothing here includes a stream URL, so it is safe to copy.
@MainActor final class MacStreamInfo: ObservableObject {
    struct Row: Identifiable { let label: String; let value: String; var id: String { label } }
    struct Group: Identifiable { let title: String; let rows: [Row]; var id: String { title } }
    @Published private(set) var groups = [Group]()
    /// Reading the Keychain every second would be wasteful; setup rarely changes while this is open.
    private var uhdConfigured: Bool?
    var text: String {
        groups.map { group in ([group.title] + group.rows.map { "  \($0.label): \($0.value)" }).joined(separator: "\n") }.joined(separator: "\n\n")
    }
    func refresh(_ model: PlaybackModel) async {
        let player = model.player, item = player.currentItem
        var result = [Group(title: "Playback", rows: playback(model, item: item))]
        var videoIsHDR = false
        if let item {
            var variants = [AVAssetVariant]()
            if let asset = item.asset as? AVURLAsset, let loaded = try? await asset.load(.variants) { variants = loaded }
            var video = [Row](), audio = [Row]()
            let size = item.presentationSize
            if size.height > 0 { video.append(Row(label: "Resolution", value: "\(Int(size.width)) × \(Int(size.height))")) }
            // The rendition being presented, for what the playlist claims about it.
            let playing = variants.filter { $0.videoAttributes?.presentationSize.height == size.height && size.height > 0 }
            var described = false
            for track in item.tracks where track.isEnabled {
                guard let asset = track.assetTrack, let description = try? await asset.load(.formatDescriptions).first else { continue }
                let extensions = (CMFormatDescriptionGetExtensions(description) as? [String: Any]) ?? [:]
                if asset.mediaType == .video {
                    described = true
                    let depth = (extensions["BitsPerComponent"] as? NSNumber).map { ", \($0.intValue)-bit" } ?? ""
                    video.append(Row(label: "Codec", value: Self.codec(CMFormatDescriptionGetMediaSubType(description)) + depth))
                    if track.currentVideoFrameRate > 0 { video.append(Row(label: "Frame rate", value: String(format: "%.1f fps", track.currentVideoFrameRate))) }
                    let transfer = extensions[kCVImageBufferTransferFunctionKey as String] as? String
                    let alternative = extensions["AlternativeTransferCharacteristics"] as? String
                    videoIsHDR = asset.hasMediaCharacteristic(.containsHDRVideo)
                    let range: String
                    if transfer == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { range = "HDR (HLG)" }
                    else if transfer == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String { range = "HDR (PQ)" }
                    else if videoIsHDR { range = "HDR" }
                    // Backwards-compatible HLG that the system is treating as standard range.
                    else if alternative != nil { range = "SDR (stream also flags \(Self.colour(alternative)))" }
                    else { range = "SDR" }
                    video.append(Row(label: "Dynamic range", value: range))
                    if let transfer { video.append(Row(label: "Transfer function", value: Self.colour(transfer))) }
                    if let primaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String { video.append(Row(label: "Colour primaries", value: Self.colour(primaries))) }
                    if let matrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String { video.append(Row(label: "Colour matrix", value: Self.colour(matrix))) }
                    if let full = extensions["FullRangeVideo"] as? NSNumber { video.append(Row(label: "Levels", value: full.boolValue ? "Full range" : "Video range")) }
                } else if asset.mediaType == .audio, let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
                    audio.append(Row(label: "Codec", value: Self.codec(format.mFormatID)))
                    audio.append(Row(label: "Channels", value: format.mChannelsPerFrame == 2 ? "Stereo" : "\(format.mChannelsPerFrame)"))
                    if format.mSampleRate > 0 { audio.append(Row(label: "Sample rate", value: String(format: "%.1f kHz", format.mSampleRate / 1000))) }
                }
            }
            // Streamed tracks may not describe themselves: fall back to the playlist's account.
            if !described, let attributes = playing.first?.videoAttributes {
                if let codec = attributes.codecTypes.first { video.append(Row(label: "Codec", value: Self.codec(codec))) }
                if let rate = attributes.nominalFrameRate, rate > 0 { video.append(Row(label: "Frame rate", value: String(format: "%.1f fps", rate))) }
                videoIsHDR = attributes.videoRange == .hlg || attributes.videoRange == .pq
                video.append(Row(label: "Dynamic range", value: Self.range(attributes.videoRange) + " (per playlist)"))
            }
            if !video.isEmpty { result.append(Group(title: "Video", rows: video)) }
            // Beside the video it describes: whether that dynamic range is reaching the screen.
            result.append(Group(title: "Display", rows: display(videoIsHDR: videoIsHDR)))
            if !audio.isEmpty { result.append(Group(title: "Audio", rows: audio)) }
            result.append(Group(title: "Stream", rows: stream(item, variants: variants, playing: playing, time: player.currentTime().seconds)))
        } else { result.append(Group(title: "Display", rows: display(videoIsHDR: nil))) }
        groups = result
    }
    private func playback(_ model: PlaybackModel, item: AVPlayerItem?) -> [Row] {
        guard item != nil || model.loading || model.error != nil else { return [Row(label: "State", value: "Nothing is playing")] }
        var rows = [Row]()
        if !model.displayTitle.isEmpty { rows.append(Row(label: "Title", value: model.displayTitle)) }
        if !model.displaySubtitle.isEmpty { rows.append(Row(label: model.isLive ? "Channel" : "Episode", value: model.displaySubtitle)) }
        rows.append(Row(label: "Type", value: model.isLive ? "Live" : "On demand"))
        let player = model.player
        let state: String
        if let error = model.error { state = "Error: \(error)" }
        else if model.loading { state = model.status }
        else {
            switch player.timeControlStatus {
            case .paused: state = "Paused"
            case .playing: state = player.rate == 1 ? "Playing" : String(format: "Playing at %.2g×", player.rate)
            case .waitingToPlayAtSpecifiedRate: state = "Buffering"
            @unknown default: state = model.status
            }
        }
        rows.append(Row(label: "State", value: state))
        if let badge = model.qualityBadge { rows.append(Row(label: "Quality", value: badge)) }
        if let item, !model.isLive {
            rows.append(Row(label: "Position", value: "\(Self.clock(player.currentTime().seconds)) / \(Self.clock(item.duration.seconds))"))
        }
        return rows
    }
    private func stream(_ item: AVPlayerItem, variants: [AVAssetVariant], playing: [AVAssetVariant], time: Double) -> [Row] {
        var rows = [Row]()
        if let host = (item.asset as? AVURLAsset)?.url.host {
            rows.append(Row(label: "Playlist from", value: host == "127.0.0.1" ? "Beeb's bridge on this Mac" : host))
        }
        let offered = Set(variants.compactMap { variant -> String? in
            guard let attributes = variant.videoAttributes, attributes.presentationSize.height > 0 else { return nil }
            return "\(Int(attributes.presentationSize.height))p \(Self.range(attributes.videoRange))"
        }).sorted { (Int($0.prefix { $0.isNumber }) ?? 0) > (Int($1.prefix { $0.isNumber }) ?? 0) }
        if !offered.isEmpty { rows.append(Row(label: "Offered", value: offered.joined(separator: ", "))) }
        if let range = playing.first?.videoAttributes?.videoRange { rows.append(Row(label: "Playlist range", value: Self.range(range))) }
        if let event = item.accessLog()?.events.last {
            if let host = event.uri.flatMap({ URL(string: $0)?.host }), host != "127.0.0.1" { rows.append(Row(label: "Media from", value: host)) }
            if event.indicatedBitrate > 0 { rows.append(Row(label: "Stream bitrate", value: Self.megabits(event.indicatedBitrate))) }
            if event.observedBitrate > 0 { rows.append(Row(label: "Download speed", value: Self.megabits(event.observedBitrate))) }
            if event.numberOfBytesTransferred > 0 { rows.append(Row(label: "Downloaded", value: String(format: "%.1f MB", Double(event.numberOfBytesTransferred) / 1_000_000))) }
            if event.startupTime > 0 { rows.append(Row(label: "Start-up time", value: String(format: "%.1f s", event.startupTime))) }
            rows.append(Row(label: "Stalls", value: "\(max(0, event.numberOfStalls))"))
            rows.append(Row(label: "Dropped frames", value: "\(max(0, event.numberOfDroppedVideoFrames))"))
        }
        if time.isFinite, let ahead = item.loadedTimeRanges.map(\.timeRangeValue).first(where: { $0.containsTime(CMTime(seconds: time, preferredTimescale: 600)) }) {
            rows.append(Row(label: "Buffered ahead", value: String(format: "%.0f s", max(0, ahead.end.seconds - time))))
        }
        // The comment may quote a URL; the code and domain are enough to recognise the failure.
        if let error = item.errorLog()?.events.last { rows.append(Row(label: "Last stream error", value: "\(error.errorDomain) \(error.errorStatusCode)")) }
        if uhdConfigured == nil { uhdConfigured = UHDIdentityVault.isConfigured }
        rows.append(Row(label: "BBC UHD setup", value: uhdConfigured == true ? "Enabled" : "Not set up"))
        return rows
    }
    /// Extended range is granted by the system only while something visible asks for it, so the
    /// screen's headroom is the evidence that HDR is reaching the display.
    private func display(videoIsHDR: Bool?) -> [Row] {
        let window = NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true } ?? NSApp.mainWindow
        guard let screen = window?.screen ?? NSScreen.main else { return [Row(label: "Screen", value: "Unknown")] }
        let now = screen.maximumExtendedDynamicRangeColorComponentValue, potential = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
        let visible = window?.occlusionState.contains(.visible) == true
        var rows = [Row(label: "Screen", value: screen.localizedName),
                    Row(label: "HDR capable", value: potential > 1 ? String(format: "Yes, up to %.1f× SDR white", potential) : "No"),
                    Row(label: "Headroom now", value: String(format: "%.2f×", now))]
        if let videoIsHDR {
            rows.append(Row(label: "Player window", value: visible ? "Visible" : "Hidden or covered"))
            let verdict: String
            if potential <= 1 { verdict = "No: this display has no HDR" }
            else if !videoIsHDR { verdict = "No: the video is SDR" }
            else if !visible { verdict = "No: the player window is not visible" }
            else if now >= 2 { verdict = "Yes" }
            else if now <= 1.25 { verdict = "No: the display is giving no extra headroom" }
            else { verdict = "Marginal: little headroom at this brightness" }
            rows.append(Row(label: "HDR on screen", value: verdict))
        }
        if !AVPlayer.eligibleForHDRPlayback { rows.append(Row(label: "HDR playback", value: "Not available on this Mac")) }
        return rows
    }
    private static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
    }
    private static func megabits(_ bits: Double) -> String { String(format: "%.1f Mb/s", bits / 1_000_000) }
    private static func codec(_ code: FourCharCode) -> String {
        let tag = String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
        switch tag {
        case "hvc1", "hev1": return "HEVC (\(tag))"
        case "avc1", "avc3": return "H.264 (\(tag))"
        case "mp4a", "aac": return "AAC"
        case "ac-3": return "Dolby Digital"
        case "ec-3": return "Dolby Digital Plus"
        default: return tag
        }
    }
    private static func range(_ range: AVVideoRange) -> String {
        switch range {
        case .hlg: "HLG"
        case .pq: "PQ"
        case .sdr: "SDR"
        default: range.rawValue
        }
    }
    /// Core Video's names for colour tags, in the terms the standards use.
    private static func colour(_ tag: String?) -> String {
        switch tag {
        case "ITU_R_2100_HLG": "HLG (BT.2100)"
        case "SMPTE_ST_2084_PQ": "PQ (ST 2084)"
        case "ITU_R_709_2": "BT.709"
        case "ITU_R_2020": "BT.2020"
        case "P3_D65": "Display P3"
        case "SMPTE_C": "SMPTE C"
        case "ITU_R_601_4": "BT.601"
        case .some(let other): other.replacingOccurrences(of: "_", with: " ")
        case nil: "Unknown"
        }
    }
}

/// A separate window, so the figures can sit beside the picture they describe.
struct MacStreamInfoView: View {
    static let windowID = "stream-info"
    @ObservedObject var model: PlaybackModel
    @StateObject private var info = MacStreamInfo()
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(info.groups) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title).font(.headline)
                        ForEach(group.rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                                // Monospaced, so figures that change every second do not shift the text.
                                Text(row.value).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("Updates every second").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info.text, forType: .string)
                    copied = true
                }.help("Copy these figures as text. Stream URLs are never included.")
            }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
        }
        .background(MacTheme.background)
        .frame(minWidth: 420, minHeight: 360)
        .task {
            while !Task.isCancelled {
                await info.refresh(model)
                copied = false
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
