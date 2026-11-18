// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AVKit

@MainActor private struct PlaybackTracking {
    let history: WatchHistory
    let episode: CatalogueEpisode
    let show: CatalogueShow?
    let next: CatalogueEpisode?
    let resumePosition: Double
}

@MainActor final class PlaybackModel: ObservableObject {
    @Published var loading = false
    @Published var status = "Ready to play."
    @Published var error: String?
    @Published var qualityBadge: String?
    @Published var displayTitle = ""
    @Published var displaySubtitle = ""
    @Published private(set) var isLive = false
    /// Start of the programme on air when a live channel was opened (for From start).
    @Published private(set) var liveProgrammeStart: Date?
    @Published private(set) var infoProgramme: Programme?
    @Published private(set) var infoArtwork: Data?
    @Published var additionalStreamError: String?
    @Published private(set) var additionalStreamErrorID = UUID()
    @Published private(set) var switchingAdditionalStream = false
    private var additionalOperation: Task<Void,Never>?
    private var liveUHD: LiveUHDPlaybackAccess?
    @Published var activeSkip: SkipMarker?
    private var skipMarkers = [SkipMarker]()
    private var extrasTasks = [Task<Void, Never>]()
    private var liveSubtitles: LiveSubtitlePlaybackAccess?
    private var subtitleBridge: LocalHLSServer?
    private var clockObserver: Any?
    let player = AVPlayer()
    private var operation: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var generation = UUID()
    private var failedToEndObserver: NSObjectProtocol?
    private var endedObserver: NSObjectProtocol?
    private var tracking: PlaybackTracking?
    private let uhdAccess = UHDPlaybackAccess()
    private let extrasAPI: PlaybackExtrasAPI
    private let sourceResolver: ((Programme, PlaybackQuality) async throws -> PlaybackSource)?
    init(sourceResolver: ((Programme, PlaybackQuality) async throws -> PlaybackSource)? = nil, extrasAPI: PlaybackExtrasAPI = PlaybackExtrasAPI()) {
        #if DEBUG
        if sourceResolver == nil, ProcessInfo.processInfo.environment["BEEB_CONTINUE_INFO_TEST"] == "1",
           let raw = ProcessInfo.processInfo.environment["BEEB_PLAYER_URL"], let url = URL(string: raw) {
            self.sourceResolver = { _, _ in PlaybackSource(url: url, requested1080: false) }
        } else { self.sourceResolver = sourceResolver }
        #else
        self.sourceResolver = sourceResolver
        #endif
        self.extrasAPI = extrasAPI
    }
    func start(_ programme: Programme, require1080: Bool = false, quality: PlaybackQuality = .automatic, history: WatchHistory? = nil, show: CatalogueShow? = nil, restart: Bool = false, ready: @escaping () -> Void) {
        let episode = show?.episodes.first { $0.id == programme.id } ?? CatalogueEpisode(programme: programme, subtitle: programme.episodeSubtitle ?? programme.title, duration: "", sliceID: "episodes", seriesTitle: "Episodes")
        let next = show.flatMap { EpisodeSequence.next(after: episode, in: $0) }
        let context = history.map { PlaybackTracking(history: $0, episode: episode, show: show, next: next, resumePosition: restart ? 0 : $0.resumePosition(for: programme.id)) }
        begin(programme: programme, tracking: context, title: programme.showTitle ?? programme.title, subtitle: programme.episodeSubtitle ?? "", minimumHeight: quality == .uhd ? 2160 : (quality == .hd && require1080 ? 1080 : 0), ready: ready) {
            if let sourceResolver = self.sourceResolver { return try await sourceResolver(programme, quality) }
            if quality == .automatic {
                let canTryUHD = UHDIdentityVault.isConfigured || programme.uhdListed == true
                return try await PlaybackPolicy.bestSource(uhd: canTryUHD ? {
                    if UHDIdentityVault.isConfigured { return try await self.uhdAccess.source(for: programme) }
                    return try await UHDService().source(for: programme)
                } : nil, hd: { try await BBCService().source(for: programme, require1080: false) })
            }
            if quality == .uhd {
                if UHDIdentityVault.isConfigured { return try await self.uhdAccess.source(for: programme) }
                return try await UHDService().source(for: programme)
            }
            return try await BBCService().source(for: programme, require1080: require1080)
        }
    }
    func startLive(_ selected: LiveChannel, fromStart: Bool = false, ready: @escaping () -> Void) {
        let channel = RegionalChannels.resolve(selected)
        let programmeStart = selected.current?.start ?? channel.current?.start
        var startAtBeginning = fromStart
        #if DEBUG
        if ProcessInfo.processInfo.environment["BEEB_TEST_FROM_START"] == "1" { startAtBeginning = true }
        #endif
        let wantsStart = startAtBeginning
        begin(title: channel.current?.title ?? channel.title, subtitle: channel.title, minimumHeight: 0, isLive: true, ready: { [weak self] in
            ready()
            if wantsStart { Task { @MainActor [weak self] in await self?.watchFromStartWhenReady() } }
        }) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["BEEB_LIVE_ROUTE_VALIDATE"] == "1", let raw = ProcessInfo.processInfo.environment["BEEB_PLAYER_URL"], let url = URL(string: raw) { return PlaybackSource(url: url, requested1080: false) }
            #endif
            return try await DiscoveryAPI().liveSource(channel)
        }
        liveProgrammeStart = programmeStart
    }
    /// Live: jump back to the start of the programme on air (or the earliest point the stream keeps).
    func watchFromStart() {
        guard isLive, let item = player.currentItem else { return }
        guard let start = liveProgrammeStart else { seekToEarliest(); return }
        if item.currentDate() != nil {   // the stream carries clock times: seek straight to the start time
            item.seek(to: start) { [weak self] done in
                if !done { Task { @MainActor [weak self] in self?.seekBack(to: start) } }
            }
        } else { seekBack(to: start) }
    }
    /// Without clock times: the live edge is "now" minus the stream's delay, so step back by the programme's age.
    private func seekBack(to start: Date) {
        guard let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        let liveDelay = 20.0   // typical BBC live latency; landing a few seconds early beats missing the opening
        let back = max(0, Date().timeIntervalSince(start) - liveDelay)
        let target = max(range.start.seconds + 2, CMTimeRangeGetEnd(range).seconds - back)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }
    /// Live: jump back to the live edge.
    func goLive() {
        guard isLive, let range = player.currentItem?.seekableTimeRanges.last?.timeRangeValue else { return }
        player.seek(to: CMTimeRangeGetEnd(range))
    }
    private func seekToEarliest() {
        guard let range = player.currentItem?.seekableTimeRanges.first?.timeRangeValue else { return }
        player.seek(to: range.start + CMTime(seconds: 2, preferredTimescale: 600))
    }
    private func watchFromStartWhenReady() async {
        for _ in 0..<150 {   // up to 15 s for the stream to become ready
            if player.currentItem?.status == .readyToPlay { watchFromStart(); return }
            if player.currentItem?.status == .failed { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    /// Resolve first: an off-air event must not destroy the working channel.
    func switchAdditionalStream(_ stream: AdditionalLiveStream) {
        guard isLive, AdditionalLiveStream.all.contains(where: { $0.id == stream.id }) else { return }
        additionalOperation?.cancel(); additionalStreamError = nil; switchingAdditionalStream = true
        let id = generation
        additionalOperation = Task { [weak self] in
            let uhd = stream.id == "uk_bbc_stream_041" ? LiveUHDPlaybackAccess() : nil
            var adopted = false
            defer { if !adopted { uhd?.stop() } }
            do {
                let source: PlaybackSource
                #if DEBUG
                if ProcessInfo.processInfo.environment["BEEB_LIVE_ROUTE_VALIDATE"] == "1", let raw = ProcessInfo.processInfo.environment["BEEB_PLAYER_URL"], let url = URL(string:raw) {
                    if ProcessInfo.processInfo.environment["BEEB_ADDITIONAL_UNAVAILABLE"] == stream.id { throw BBCError.message("This event is currently off air.") }
                    source = PlaybackSource(url:url,requested1080:false)
                } else if let uhd { source = try await uhd.source() }
                else { source = try await DiscoveryAPI().liveSource(LiveChannel(id:stream.id,title:stream.title)) }
                #else
                if let uhd { source = try await uhd.source() }
                else { source = try await DiscoveryAPI().liveSource(LiveChannel(id:stream.id,title:stream.title)) }
                #endif
                try Task.checkCancellation()
                guard let self, self.generation == id, self.isLive else { return }
                // stop() inside begin must not cancel the operation adopting its result.
                self.additionalOperation = nil
                adopted = true
                self.begin(title:stream.title,subtitle:stream.title,minimumHeight:source.requestedHeight ?? 0,isLive:true,ready:{}) {
                    self.liveUHD = uhd
                    return source
                }
            } catch {
                guard let self, !Task.isCancelled, self.generation == id else { return }
                self.switchingAdditionalStream = false; self.additionalOperation = nil
                self.additionalStreamErrorID = UUID()
                self.additionalStreamError = error.localizedDescription
            }
        }
    }
    private func applyInfo(to item: AVPlayerItem) {
        // Keep AVKit's built-in expanding text renderer out of this path: device
        // crash reports show it looping while measuring even short synopses.
        // The same metadata is rendered by our bounded Info card.
        #if !os(macOS)
        if !item.externalMetadata.isEmpty { item.externalMetadata = [] }
        #endif
    }
    private func prepareInfo(programme: Programme, versionID: String?, item: AVPlayerItem, generation id: UUID) {
        extrasTasks.append(Task { [weak self] in
            // Fetch missing/full details only for the selected episode, not the catalogue.
            let raw = try? await self?.extrasAPI.episode(programme.id)
            let fresh = raw.flatMap { try? CatalogueAPI.episode($0).programme }
            guard let self, !Task.isCancelled, self.generation == id, self.player.currentItem === item else { return }
            if let versionID, let version = (raw?["versions"] as? [[String: Any]])?.first(where: { $0["id"] as? String == versionID }) {
                self.skipMarkers = SkipMarker.parse(version)
                self.updateTimedControls(at: self.player.currentTime().seconds)
            }
            var details = fresh ?? programme
            if details.summary.isEmpty { details = programme }
            details.durationText = details.durationText ?? programme.durationText
            details.firstBroadcast = details.firstBroadcast ?? programme.firstBroadcast
            details.firstBroadcastDateTime = details.firstBroadcastDateTime ?? programme.firstBroadcastDateTime
            self.infoProgramme = details
            self.applyInfo(to: item)
            guard let url = details.image ?? programme.image, url.scheme == "https" else { return }
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 12
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, self.generation == id, self.player.currentItem === item,
                      (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8_000_000 else { return }
                let jpeg = await Task.detached(priority: .utility) { PlaybackInfoArtwork.jpeg(from: data) }.value
                guard let jpeg, !Task.isCancelled, self.generation == id, self.player.currentItem === item else { return }
                self.infoArtwork = jpeg
                self.applyInfo(to: item)
            } catch { /* Artwork is optional and must never interrupt playback. */ }
        })
    }
    private func begin(programme: Programme? = nil, tracking context: PlaybackTracking? = nil, title: String, subtitle: String, minimumHeight: Int, isLive: Bool = false, ready: @escaping () -> Void, resolve: @escaping () async throws -> PlaybackSource) {
        stop(); PlaybackActivity.active = true
        self.isLive = isLive
        displayTitle = title; displaySubtitle = subtitle
        infoProgramme = programme; infoArtwork = nil
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["BEEB_PLAYER_ARTWORK"], let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            infoArtwork = PlaybackInfoArtwork.jpeg(from: data)
        }
        #endif
        error = nil; loading = true; status = "Finding the best available stream…"
        let id = generation
        operation = Task { [self] in
            defer { if generation == id { loading = false } }
            do {
                let source = try await resolve(); try Task.checkCancellation()
                guard id == generation else { return }
                let playbackURL = await nativeSubtitleURL(for: source)
                try Task.checkCancellation()
                guard id == generation else { return }
                let item = AVPlayerItem(url: playbackURL)
                applyInfo(to: item)
                failedToEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] notification in
                    let failure = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                    let message = failure?.localizedDescription ?? "The stream could not continue. Close and retry."
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id else { return }
                        self.checkpoint(); self.error = message; self.status = "Playback stopped."; self.player.pause()
                    }
                }
                player.replaceCurrentItem(with: item)
                if let programme { prepareInfo(programme: programme, versionID: source.versionID, item: item, generation: id) }
                clockObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id else { return }
                        self.updateTimedControls(at: time.seconds)
                    }
                }
                #if !os(macOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                if let context, context.resumePosition > 0 {
                    status = "Resuming episode…"
                    var waited = 0
                    while item.status != .readyToPlay {
                        if item.status == .failed { throw item.error ?? BBCError.message("Unable to resume this episode.") }
                        guard waited < 300 else { throw BBCError.message("Timed out preparing the saved position. Close and retry.") }
                        try await Task.sleep(nanoseconds: 100_000_000); waited += 1
                    }
                    let duration = item.duration.seconds
                    let position = duration.isFinite && duration > 0 ? min(context.resumePosition, max(0, duration - 2)) : context.resumePosition
                    let sought = await player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    try Task.checkCancellation()
                    guard generation == id else { return }
                    guard sought else { throw BBCError.message("Unable to seek to the saved position. Close and retry.") }
                }
                tracking = context
                endedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == id else { return }
                        self.checkpoint(ended: true)
                    }
                }
                status = "Starting playback…"
                let requiredHeight = max(minimumHeight, source.requestedHeight ?? 0)
                ready(); player.play()
                #if DEBUG
                if ProcessInfo.processInfo.environment["BEEB_LIVE_ROUTE_VALIDATE"] == "1" {
                    let values: [String: Any] = ["title": displayTitle, "channel": displaySubtitle, "isLive": isLive]
                    let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Live-launch-validation.json")
                    if let data = try? JSONSerialization.data(withJSONObject: values) { try? data.write(to: file, options: .atomic) }
                }
                #endif
                monitor = Task {
                    var seconds = 0
                    while !Task.isCancelled {
                        do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                        seconds += 1
                        if seconds % 5 == 0 { checkpoint() }
                        if item.status == .failed { error = item.error?.localizedDescription ?? "Playback failed. Close and retry."; player.pause(); return }
                        let size = item.presentationSize
                        if size.height > 0 {
                            let h = Int(size.height.rounded()), w = Int(size.width.rounded())
                            qualityBadge = PlaybackPolicy.badge(height: h, videoRange: source.videoRange)
                            status = player.timeControlStatus == .waitingToPlayAtSpecifiedRate ? "Buffering…" : "Playing"
                            if requiredHeight > 0 && h < requiredHeight { error = "This stream is \(w) × \(h), below your \(requiredHeight)p requirement."; player.pause(); return }
                        } else if seconds >= 40 { error = "No video arrived within 40 seconds. Close and retry."; player.pause(); return }
                    }
                }
            } catch { if !Task.isCancelled, generation == id { self.error = error.localizedDescription; status = "Unable to start playback." } }
        }
    }
    private func nativeSubtitleURL(for source: PlaybackSource) async -> URL {
        if !source.liveCaptionTemplates.isEmpty {
            let bridge = LiveSubtitlePlaybackAccess()
            liveSubtitles = bridge
            do { return try await bridge.start(source) }
            catch { bridge.stop(); return source.url }
        }
        guard let version = source.versionID else { return source.url }
        do {
            let cues = try await extrasAPI.subtitles(versionID: version)
            guard !cues.isEmpty else { return source.url }
            let raw = try await BBCService().fetch(source.url)
            let master = String(decoding: raw, as: UTF8.self)
            guard master.hasPrefix("#EXTM3U") else { return source.url }
            // Existing HLS subtitle renditions already work with the single native control.
            if master.contains("TYPE=SUBTITLES") { return source.url }
            var media = master, mediaBase = source.url
            if master.contains("#EXT-X-STREAM-INF:") {
                let lines = master.components(separatedBy: .newlines)
                guard let index = lines.firstIndex(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }), index + 1 < lines.count,
                      let url = HLSSubtitles.resolve(lines[index + 1], base: source.url) else { return source.url }
                mediaBase = url
                media = String(decoding: try await BBCService().fetch(url), as: UTF8.self)
            }
            var origin: UInt64 = 0
            if !media.contains("#EXT-X-MAP:") {
                guard let segment = media.components(separatedBy: .newlines).first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
                      let url = HLSSubtitles.resolve(segment, base: mediaBase),
                      let pts = HLSSubtitles.firstVideoPTS(try await BBCService().fetch(url)) else { return source.url }
                origin = pts
            }
            let assets = try HLSSubtitles.assets(cues: cues, duration: HLSSubtitles.duration(media), master: master, base: source.url, mpegTimestamp: origin)
            try Task.checkCancellation()
            let bridge = LocalHLSServer(); subtitleBridge = bridge
            return try await bridge.start(playlists: assets)
        } catch { return source.url } // Caption failure must never discard an already selected UHD stream.
    }
    func updateTimedControls(at time: Double) {
        let marker = skipMarkers.first { $0.contains(time) }
        if activeSkip != marker { activeSkip = marker }
    }
    func skip(_ marker: SkipMarker) {
        guard marker == activeSkip, marker.contains(player.currentTime().seconds) else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        guard !duration.isFinite || marker.end < duration else { return }
        player.seek(to: CMTime(seconds: marker.end, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        activeSkip = nil
    }
    func checkpoint(ended: Bool = false) {
        guard let tracking, let item = player.currentItem else { return }
        tracking.history.update(episode: tracking.episode, show: tracking.show, next: tracking.next,
                                position: player.currentTime().seconds, duration: item.duration.seconds, ended: ended)
    }
    func stop() {
        additionalOperation?.cancel(); additionalOperation = nil
        switchingAdditionalStream = false; additionalStreamError = nil
        liveUHD?.stop(); liveUHD = nil
        checkpoint(); tracking = nil
        extrasTasks.forEach { $0.cancel() }; extrasTasks = []
        if let clockObserver { player.removeTimeObserver(clockObserver) }; clockObserver = nil
        skipMarkers = []; activeSkip = nil
        if let endedObserver { NotificationCenter.default.removeObserver(endedObserver) }; endedObserver = nil
        if let failedToEndObserver { NotificationCenter.default.removeObserver(failedToEndObserver) }; failedToEndObserver = nil
        generation = UUID(); operation?.cancel(); monitor?.cancel(); operation = nil; monitor = nil
        liveSubtitles?.stop(); liveSubtitles = nil
        subtitleBridge?.stop(); subtitleBridge = nil
        uhdAccess.stop()
        PlaybackActivity.active = false
        isLive = false; infoProgramme = nil; infoArtwork = nil
        player.pause(); player.replaceCurrentItem(with: nil); loading = false; qualityBadge = nil
    }
    #if DEBUG
    func startLiveLayoutValidation(url: URL) {
        let liveCaptionCheck = ProcessInfo.processInfo.environment["BEEB_LIVE_SUBTITLE_VALIDATE"] == "1"
        begin(title: liveCaptionCheck ? "BBC One" : "Live playback layout check", subtitle: liveCaptionCheck ? "BBC One London" : "BBC Two", minimumHeight: 0, isLive: true, ready: {}) {
            if ProcessInfo.processInfo.environment["BEEB_LIVE_SUBTITLE_VALIDATE"] == "1" {
                return try await DiscoveryAPI().liveSource(LiveChannel(id: "bbc_one_london", title: "BBC One"))
            }
            return PlaybackSource(url: url, requested1080: false)
        }
    }
    #endif
}
#if !os(macOS) // tvOS player chrome; the Mac player lives in Mac/.
/// Native controls and Info with a year-free title/episode line above the scrubber.
struct NativePlayer: UIViewControllerRepresentable {
    @ObservedObject var model: PlaybackModel
    let closeScreen: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> PlayerContainerViewController {
        let container = PlayerContainerViewController(badge: context.coordinator.badge)
        let controller = container.playerController
        controller.player = model.player
        controller.delegate = context.coordinator
        context.coordinator.container = container
        context.coordinator.close = closeScreen
        container.exitPlayer = closeScreen
        controller.showsPlaybackControls = true
        // Preserve native audio/subtitle settings; our Info action owns the
        // description card and no description is supplied to AVKit.
        controller.playbackControlsIncludeInfoViews = true
        controller.transportBarIncludesTitleView = false
        controller.speeds = model.isLive ? [] : [0.5, 0.75, 1, 1.25, 1.5, 2].map { AVPlaybackSpeed(rate: Float($0), localizedName: "\($0)×") }
        container.configureMenus(isLive:model.isLive)
        container.loadViewIfNeeded()
        return container
    }
    func updateUIViewController(_ container: PlayerContainerViewController, context: Context) {
        let controller = container.playerController
        if model.isLive, !controller.speeds.isEmpty { controller.speeds = [] }
        container.configureMenus(isLive:model.isLive)
        container.chooseAdditional = { [weak model] stream in model?.switchAdditionalStream(stream) }
        container.fromStart = { [weak model] in model?.watchFromStart() }
        container.backToLive = { [weak model] in model?.goLive() }
        container.redAction.attributes = model.switchingAdditionalStream ? [.disabled] : []
        container.reportAdditionalError(model.additionalStreamError, id:model.additionalStreamErrorID)
        container.infoController.configure(model: model)
        let subtitle = model.displaySubtitle
        context.coordinator.badge.configure(quality: model.qualityBadge, title: model.displayTitle, subtitle: subtitle, isLive: model.isLive)
        context.coordinator.close = closeScreen
        container.exitPlayer = closeScreen
        if context.coordinator.marker != model.activeSkip {
            context.coordinator.marker = model.activeSkip
            controller.contextualActions = model.activeSkip.map { marker in
                [UIAction(title: marker.title) { [weak model] _ in Task { @MainActor in model?.skip(marker) } }]
            } ?? []
        }
    }
    @MainActor final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        let badge = PlayerQualityOverlay()
        weak var container: PlayerContainerViewController?
        @objc(playerViewController:willTransitionToVisibilityOfTransportBar:withAnimationCoordinator:)
        func playerViewController(_ playerViewController: AVPlayerViewController, willTransitionToVisibilityOfTransportBar visible: Bool, with coordinator: AVPlayerViewControllerAnimationCoordinator) {
            container?.controlsVisible = visible
            let showTitle = visible && container?.infoVisible != true
            self.badge.setControlsVisible(showTitle)
            coordinator.addCoordinatedAnimations({ self.badge.alpha = showTitle ? 1 : 0 }, completion: nil)
        }
        var marker: SkipMarker?
        var close: (() -> Void)?
        func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
            // AVKit consumes Back to close Info/controls first. It asks for dismissal
            // only once its own UI is closed; dismiss the enclosing SwiftUI cover then.
            close?()
            return false
        }
    }
}
/// Keep the year-free title and outlined quality mark above AVKit’s dimming layer.
final class PlayerContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    let playerController = AVPlayerViewController()
    let infoController = ProgrammeInfoViewController()
    private var backExitArmed = false
    private var backGesture: PlayerBackGesture?
    var exitPlayer: (() -> Void)?
    private let badge: PlayerQualityOverlay
    var controlsVisible = false
    private(set) var infoVisible = false
    var chooseAdditional: ((AdditionalLiveStream) -> Void)?
    var fromStart: (() -> Void)?
    var backToLive: (() -> Void)?
    lazy var fromStartAction = UIAction(title: "Watch from start", image: UIImage(systemName: "arrow.counterclockwise.circle")) { [weak self] _ in self?.fromStart?() }
    lazy var liveAction = UIAction(title: "Live", image: Self.textIcon("LIVE")) { [weak self] _ in self?.backToLive?() }
    private var liveMenus = false
    private var lastAdditionalError: UUID?
    lazy var redAction = UIAction(title:"Additional streams", image:Self.redIcon()) { [weak self] _ in self?.showAdditionalStreams() }
    lazy var infoAction = UIAction(title: "Info", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.showInfo() }
    static func textIcon(_ label: String) -> UIImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: UIColor.white]
        let text = label as NSString
        let measured = text.size(withAttributes: attributes)
        let size = CGSize(width: max(40, measured.width + 8), height: 34)
        return UIGraphicsImageRenderer(size: size).image { _ in
            text.draw(at: CGPoint(x: (size.width - measured.width) / 2, y: (size.height - measured.height) / 2), withAttributes: attributes)
        }.withRenderingMode(.alwaysTemplate)
    }
    static func redIcon() -> UIImage {
        let size = CGSize(width:40,height:34)
        return UIGraphicsImageRenderer(size:size).image { _ in
            let text = "RED" as NSString
            let attributes: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize:18,weight:.semibold),.foregroundColor:UIColor.white]
            let measured = text.size(withAttributes:attributes)
            text.draw(at:CGPoint(x:(size.width-measured.width)/2,y:(size.height-measured.height)/2),withAttributes:attributes)
        }.withRenderingMode(.alwaysTemplate)
    }
    func configureMenus(isLive: Bool) {
        guard liveMenus != isLive || playerController.transportBarCustomMenuItems.isEmpty else { return }
        liveMenus = isLive
        playerController.transportBarCustomMenuItems = isLive ? [fromStartAction, liveAction, redAction, infoAction] : [infoAction]
    }
    private func showAdditionalStreams() {
        guard liveMenus, presentedViewController == nil, !infoVisible else { return }
        backExitArmed = false
        let menu = UIAlertController(title:"Additional streams",message:nil,preferredStyle:.actionSheet)
        for stream in AdditionalLiveStream.all {
            menu.addAction(UIAlertAction(title:stream.title,style:.default) { [weak self, weak menu] _ in
                menu?.dismiss(animated:true) { self?.chooseAdditional?(stream) }
            })
        }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.backExitArmed = false
        })
        present(menu,animated:true)
    }
    func reportAdditionalError(_ message: String?, id:UUID) {
        guard let message else { lastAdditionalError = nil; return }
        guard id != lastAdditionalError, viewIfLoaded?.window != nil else { return }
        lastAdditionalError = id
        let alert = UIAlertController(title:"Additional stream unavailable",message:message,preferredStyle:.alert)
        alert.addAction(UIAlertAction(title:"OK",style:.default))
        if let presented = presentedViewController {
            presented.dismiss(animated:true) { [weak self] in self?.present(alert,animated:true) }
        } else { present(alert,animated:true) }
    }
    init(badge: PlayerQualityOverlay) {
        self.badge = badge
        super.init(nibName: nil, bundle: nil)

    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(playerController)
        let playerView = playerController.view!
        playerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerView)
        NSLayoutConstraint.activate([playerView.leadingAnchor.constraint(equalTo: view.leadingAnchor), playerView.trailingAnchor.constraint(equalTo: view.trailingAnchor), playerView.topAnchor.constraint(equalTo: view.topAnchor), playerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        playerController.didMove(toParent: self)
        badge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(badge)
        NSLayoutConstraint.activate([badge.leadingAnchor.constraint(equalTo: view.leadingAnchor), badge.trailingAnchor.constraint(equalTo: view.trailingAnchor), badge.topAnchor.constraint(equalTo: view.topAnchor), badge.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        badge.align(with: playerController.unobscuredContentGuide)
        addChild(infoController)
        view.addSubview(infoController.view)
        infoController.view.isHidden = true
        infoController.didMove(toParent: self)
        let input = UITapGestureRecognizer(target: self, action: #selector(nonBackInteraction))
        input.allowedPressTypes = [UIPress.PressType.upArrow, .downArrow, .leftArrow, .rightArrow, .select, .playPause].map { NSNumber(value: $0.rawValue) }
        input.cancelsTouchesInView = false; input.delaysTouchesBegan = false; input.delaysTouchesEnded = false
        input.delegate = self
        view.addGestureRecognizer(input)
        let back = PlayerBackGesture(target: self, action: #selector(backPressed(_:)))
        back.minimumPressDuration = 0
        back.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        back.cancelsTouchesInView = true; back.delaysTouchesBegan = false; back.delaysTouchesEnded = false
        back.delegate = self; backGesture = back
        // Register on the window while this player is visible, so AVKit’s
        // reparented Info/focus views cannot bypass the Back handler.
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let backGesture { view.window?.addGestureRecognizer(backGesture) }
    }
    override func viewDidDisappear(_ animated: Bool) {
        if let backGesture { backGesture.view?.removeGestureRecognizer(backGesture) }
        super.viewDidDisappear(animated)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer !== backGesture && otherGestureRecognizer !== backGesture
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === backGesture
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        infoController.view.frame = CGRect(x: 80, y: view.bounds.height - 340, width: max(1, view.bounds.width - 160), height: 300)
    }
    private func showInfo() {
        infoVisible = true; backExitArmed = false
        infoController.view.isHidden = false
        badge.alpha = 0; badge.setControlsVisible(false)
        setNeedsFocusUpdate(); updateFocusIfNeeded()
    }
    private func hideInfo() {
        infoVisible = false; backExitArmed = true
        infoController.view.isHidden = true
        badge.alpha = controlsVisible ? 1 : 0; badge.setControlsVisible(controlsVisible)
        setNeedsFocusUpdate(); updateFocusIfNeeded()
    }
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        infoVisible ? [infoController] : [playerController]
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        if gestureRecognizer === backGesture, presentedViewController != nil {
            backExitArmed = true
            return false // Native Back dismisses the stream menu/error first.
        }
        if gestureRecognizer === backGesture, infoVisible { return true }
        if gestureRecognizer === backGesture, !backExitArmed, controlsVisible {
            // Leave the first press to AVKit. Do not tear down/recreate its
            // controls while it is closing Info; that can reopen the panel.
            backExitArmed = true
            backTrace("Back: native hide")
            return false
        }
        return true
    }
    @objc private func backPressed(_ gesture: PlayerBackGesture) {
        guard gesture.state == .began else { return }
        if infoVisible {
            backTrace("Back: hide Info")
            hideInfo()
            gesture.isEnabled = false; gesture.isEnabled = true
        } else {
            backTrace("Back: exit")
            exitPlayer?()
        }
    }
    @objc private func nonBackInteraction() { backTrace("Other input"); backExitArmed = false }

}
private final class PlayerBackGesture: UILongPressGestureRecognizer {
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
@MainActor private func backTrace(_ event: String) {
    #if DEBUG
    if ProcessInfo.processInfo.environment["BEEB_CONTINUE_INFO_TEST"] == "1" {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Back-events.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (previous + event + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    #endif
}
/// An app-owned Info card with fixed, bounded description layout. Avoids
/// AVInfoPanelExpandingSummaryView's TextKit truncation loop on physical tvOS.
final class ProgrammeInfoViewController: UIViewController {
        private let poster = UIImageView()
    private let heading = UILabel()
    private let synopsis = UILabel()
    private let footer = UILabel()
    private let scroll = ProgrammeInfoScrollView()
    private var artwork: Data?
    private var synopsisText = ""
    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Info"
        preferredContentSize = CGSize(width: 1760, height: 300)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.12, alpha: 0.95); view.layer.cornerRadius = 24; view.clipsToBounds = true
        poster.contentMode = .scaleAspectFill; poster.clipsToBounds = true
        poster.layer.cornerRadius = 12
        heading.font = .systemFont(ofSize: 28, weight: .semibold); heading.textColor = .white
        synopsis.font = .systemFont(ofSize: 24); synopsis.textColor = .lightGray; synopsis.numberOfLines = 0
        footer.font = .systemFont(ofSize: 23); footer.textColor = .white
        heading.accessibilityIdentifier = "ProgrammeInfoTitle"
        footer.accessibilityIdentifier = "ProgrammeInfoFooter"
        scroll.accessibilityIdentifier = "ProgrammeInfoDescription"
        scroll.addSubview(synopsis)
        for child in [poster, heading, scroll, footer] { view.addSubview(child) }
    }
    override var preferredFocusEnvironments: [UIFocusEnvironment] { [scroll] }
    func configure(model: PlaybackModel) {
        loadViewIfNeeded()
        let text = PlaybackInfoMetadata.synopsis(model.infoProgramme)
        if synopsisText != text { synopsisText = text; synopsis.text = text; scroll.contentOffset = .zero }
        let title = model.infoProgramme?.showTitle ?? model.displayTitle
        let subtitle = model.displaySubtitle
        heading.text = subtitle.isEmpty || title.contains(subtitle) ? title : "\(title) — \(subtitle)"
        let duration = model.player.currentItem?.duration.seconds ?? .nan
        let runtime = model.infoProgramme?.durationText ?? (duration.isFinite && duration > 0 ? "\(max(1, Int(ceil((duration - 0.5) / 60)))) min" : nil)
        footer.text = [model.infoProgramme?.firstBroadcast, runtime, model.qualityBadge].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  •  ")
        if artwork != model.infoArtwork {
            artwork = model.infoArtwork
            poster.image = artwork.flatMap { UIImage(data: $0) }
        }
        view.setNeedsLayout()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        guard width > 100 else { return }
        let hasArtwork = poster.image != nil
        let imageHeight = max(1, view.bounds.height - 40)
        let imageWidth = imageHeight * 16 / 9
        poster.frame = CGRect(x: 20, y: 20, width: hasArtwork ? imageWidth : 0, height: imageHeight)
        let left: CGFloat = hasArtwork ? imageWidth + 48 : 24
        let available = max(1, width - left - 24)
        heading.frame = CGRect(x: left, y: 18, width: available, height: 38)
        scroll.frame = CGRect(x: left, y: 65, width: available, height: max(40, view.bounds.height - 123))
        // UILabel is measured once at a concrete positive width, without a
        // UITextView, automatic expanding summary, or intrinsic-size constraints.
        let height = synopsis.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude)).height
        synopsis.frame = CGRect(x: 0, y: 0, width: available, height: max(1, height))
        scroll.contentSize = synopsis.frame.size
        footer.frame = CGRect(x: left, y: view.bounds.height - 45, width: available, height: 32)
    }
}
private final class ProgrammeInfoScrollView: UIScrollView {
    override var canBecomeFocused: Bool { true }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let limit = max(0, contentSize.height - bounds.height)
        if presses.contains(where: { $0.type == .downArrow }), contentOffset.y < limit {
            setContentOffset(CGPoint(x: 0, y: min(limit, contentOffset.y + 90)), animated: true); return
        }
        if presses.contains(where: { $0.type == .upArrow }), contentOffset.y > 0 {
            setContentOffset(CGPoint(x: 0, y: max(0, contentOffset.y - 90)), animated: true); return
        }
        super.pressesBegan(presses, with: event)
    }
}

final class PlayerQualityOverlay: UIView {
    #if DEBUG
    static var layoutPassCount = 0
    #endif
    private let label = QualityBadgeLabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let liveLabel = UILabel()
    private weak var guide: UILayoutGuide?
    private var subtitle = ""
    private var isLive = false
    private var controlsVisible = false
    private var displayLink: CADisplayLink?
    private var lastGuideFrame: CGRect?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.font = .systemFont(ofSize: 21, weight: .semibold)
        label.textColor = .white
        label.layer.borderWidth = 1
        label.layer.borderColor = UIColor.white.cgColor
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.isHidden = true
        alpha = 0
        addSubview(label)
        titleLabel.font = .systemFont(ofSize: 57, weight: .bold)
        subtitleLabel.font = .systemFont(ofSize: 25, weight: .medium)
        liveLabel.font = .systemFont(ofSize: 21, weight: .bold)
        liveLabel.text = "LIVE"; liveLabel.backgroundColor = .systemRed
        liveLabel.layer.cornerRadius = 4; liveLabel.clipsToBounds = true
        liveLabel.textAlignment = .center
        for text in [titleLabel, subtitleLabel, liveLabel] {
            text.textColor = .white
            addSubview(text)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func align(with guide: UILayoutGuide) {
        // Read AVKit geometry without constraining AVKit's animated layout guide.
        // Cross-hierarchy constraints can repeatedly invalidate the Info transition.
        self.guide = guide
        setNeedsLayout()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateDisplayLink()
    }
    func setControlsVisible(_ visible: Bool) {
        controlsVisible = visible
        updateDisplayLink()
        setNeedsLayout()
    }
    private func updateDisplayLink() {
        if controlsVisible && window != nil {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(sampleGuide))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            displayLink?.invalidate(); displayLink = nil
        }
    }
    private var guideFrame: CGRect {
        guard let guide, let owner = guide.owningView else { return bounds }
        return convert(guide.layoutFrame, from: owner)
    }
    @objc private func sampleGuide() {
        let frame = guideFrame
        guard frame != lastGuideFrame else { return }
        lastGuideFrame = frame
        setNeedsLayout()
    }
    func configure(quality: String?, title: String, subtitle: String, isLive: Bool) {
        guard label.text != quality || titleLabel.text != title || self.subtitle != subtitle || self.isLive != isLive else { return }
        label.text = quality; label.isHidden = quality == nil
        titleLabel.text = title; subtitleLabel.text = subtitle
        liveLabel.isHidden = !isLive
        self.subtitle = subtitle
        self.isLive = isLive
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        #if DEBUG
        Self.layoutPassCount += 1
        #endif
        let frame = guideFrame
        let margin = max(32, bounds.width * 0.0433)
        let left = frame.minX + margin
        let liveWidth: CGFloat = isLive ? 96 : 0
        let badgeSize = label.intrinsicContentSize
        let available = max(0, frame.width * 0.7 - badgeSize.width - 14 - liveWidth)
        let subtitleWidth = min(subtitleLabel.intrinsicContentSize.width, available)
        let metadataY = frame.maxY - 157
        func place(_ view: UIView, _ rect: CGRect) {
            let rect = rect.integral
            if view.frame != rect { view.frame = rect }
        }
        place(titleLabel, CGRect(x: left, y: frame.maxY - 59 - titleLabel.intrinsicContentSize.height,
                                 width: max(0, bounds.width - left - margin), height: titleLabel.intrinsicContentSize.height))
        place(subtitleLabel, CGRect(x: left + liveWidth, y: metadataY - 15, width: subtitleWidth, height: 30))
        place(liveLabel, CGRect(x: left, y: metadataY - 15, width: 76, height: 30))
        place(label, CGRect(x: left + liveWidth + (subtitle.isEmpty ? 0 : subtitleWidth + 14),
                            y: metadataY - badgeSize.height / 2, width: badgeSize.width, height: badgeSize.height))
    }
}
private final class QualityBadgeLabel: UILabel {
    private let insets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
}
struct PlaybackScreen: View {
    @ObservedObject var model: PlaybackModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            NativePlayer(model: model, closeScreen: { model.stop(); dismiss() }).ignoresSafeArea()
            if let error = model.error {
                VStack(spacing: 24) {
                    Text(error).foregroundStyle(.orange).frame(maxWidth: 850)
                    Button("Close player") { dismiss() }
                }.padding(35).background(.black.opacity(0.9)).cornerRadius(16)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .beebLaunchLive)) { _ in model.stop(); dismiss() }
        .onChange(of: phase) { _, value in if value != .active { model.checkpoint() } }
    }
}

#if DEBUG
struct PlayerLayoutValidationView: View {
    @Environment(\.scenePhase) private var phase
    @State private var started = false
    @StateObject private var model = PlaybackModel(sourceResolver: { _, _ in
        guard let raw = ProcessInfo.processInfo.environment["BEEB_PLAYER_URL"], let url = URL(string: raw) else { throw BBCError.message("Missing local test video") }
        return PlaybackSource(url: url, requested1080: false)
    })
    var body: some View {
        PlaybackScreen(model: model).task(id: phase) {
            guard phase == .active, !started else { return }; started = true
            var programme = Programme(id: "p0000001", title: "Playback layout check", summary: "A local playback fixture used to check native programme information.", image: nil, version: "", guidance: "Test guidance.")
            if ProcessInfo.processInfo.environment["BEEB_PLAYER_INFO_STRESS"] == "1" {
                programme = Programme(id: "p0000001", title: "Playback Info stress check", summary: String(repeating: "This is a long programme synopsis for testing the native Info card, expanded description and remote navigation during continuous playback. ", count: 30), image: nil, version: "", guidance: "Test guidance.")
            }
            programme.episodeSubtitle = "Local test clip"
            programme.durationText = "20 secs"; programme.firstBroadcast = "1 Mar 2022"; programme.firstBroadcastDateTime = "2022-03-01T00:00:00.000Z"
            if ProcessInfo.processInfo.environment["BEEB_PLAYER_LIVE_LAYOUT"] == "1",
               let raw = ProcessInfo.processInfo.environment["BEEB_PLAYER_URL"], let url = URL(string: raw) {
                model.startLiveLayoutValidation(url: url)
            } else { model.start(programme) {} }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let metadata = model.player.currentItem?.externalMetadata ?? []
            let info = try? await metadata.first { $0.identifier == .commonIdentifierDescription }?.load(.stringValue)
            let values: [String: Any] = ["info": info ?? "", "metadataCount": metadata.count, "status": model.status, "error": model.error ?? "", "quality": model.qualityBadge ?? "", "time": model.player.currentTime().seconds.isFinite ? model.player.currentTime().seconds : 0]
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Player-state-validation.json")
            if let data = try? JSONSerialization.data(withJSONObject: values) { try? data.write(to: file, options: .atomic) }
            if ProcessInfo.processInfo.environment["BEEB_PLAYER_INFO_STRESS"] == "1" {
                for tick in 1...180 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    let pulse: [String: Any] = ["tick": tick, "time": model.player.currentTime().seconds.isFinite ? model.player.currentTime().seconds : 0, "layoutPasses": PlayerQualityOverlay.layoutPassCount, "error": model.error ?? ""]
                    if let data = try? JSONSerialization.data(withJSONObject: pulse) { try? data.write(to: file.deletingLastPathComponent().appendingPathComponent("Info-heartbeat.json"), options: .atomic) }
                }
            }
        }
    }
}
#endif

#if DEBUG
struct ResumeInfoValidationView: View {
    @StateObject private var history = WatchHistory(defaults: UserDefaults(suiteName: "BeebResumeInfoRegression")!)
    @StateObject private var catalogue = CatalogueStore()
    @StateObject private var library = Library(defaults: UserDefaults(suiteName: "BeebResumeInfoRegressionLibrary")!)
    var body: some View {
        VStack {
            Text("Resume Info regression").font(.title)
            ContinueWatchingRow(catalogue: catalogue, library: library)
        }.padding(60).environmentObject(history)
        .task {
            var programme = Programme(id: "p0000001", title: "Resume Info Test", summary: "A short cached episode description with no MORE button.", image: nil, version: "", guidance: nil)
            programme.episodeSubtitle = "Episode 1"; programme.firstBroadcast = "1 March 2022"
            programme.firstBroadcastDateTime = "2022-03-01T00:00:00Z"; programme.durationText = "3 mins"
            let episode = CatalogueEpisode(programme: programme, subtitle: "Episode 1", duration: "3 mins", sliceID: "test", seriesTitle: "Series 1")
            history.update(episode: episode, show: nil, next: nil, position: 12, duration: 180)
        }
    }
}
#endif

#if DEBUG
/// Screenshot harness uses downloaded BBC metadata and a local video fixture.
/// It is excluded from Release builds and never resolves a BBC media stream.
struct ReviewPlaybackView: View {
    @State private var playing = false
    @StateObject private var model = PlaybackModel(sourceResolver: { _, _ in
        guard let raw = ProcessInfo.processInfo.environment["BEEB_PLAYER_URL"], let url = URL(string: raw) else { throw BBCError.message("Missing review video") }
        return PlaybackSource(url: url, requested1080: false)
    })
    var body: some View {
        Button("Play review clip") {
            Task { @MainActor in
                let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("review-episode.json")
                guard let data = try? Data(contentsOf: file), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let raw = (root["episodes"] as? [[String: Any]])?.first,
                      let episode = try? CatalogueAPI.episode(raw) else { return }
                model.start(episode.programme) { playing = true }
            }
        }.fullScreenCover(isPresented: $playing, onDismiss: { model.stop() }) { PlaybackScreen(model: model) }
    }
}
#endif
#endif // !os(macOS)
