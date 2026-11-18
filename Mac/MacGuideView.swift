// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// A timeline of what was, is and will be on each channel, with the channel names pinned on the left.
struct MacGuideView: View {
    let channels: [LiveChannel]
    @EnvironmentObject private var player: MacPlayerController
    @State private var guide = [GuideChannel]()
    @State private var loaded = false
    private let pointsPerMinute: CGFloat = 4.5
    private let rowHeight: CGFloat = 62
    private let rulerHeight: CGFloat = 26
    private let gap: CGFloat = 4
    /// Earlier programmes that can still be watched, then the next half day.
    private let hoursBack = 12
    private let hoursAhead = 12
    private var hours: Int { hoursBack + hoursAhead }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !loaded { ProgressView("Getting schedules…") }
            else if guide.allSatisfy({ $0.entries.isEmpty }) { Text("No schedules are available at the moment.").foregroundStyle(.secondary) }
            else {
                // Half-minute ticks keep the "now" line and the on-air highlight current.
                TimelineView(.periodic(from: .now, by: 30)) { context in grid(now: context.date) }
            }
        }
        .task(id: channels.map(\.id)) {
            guard !channels.isEmpty else { return }
            while !Task.isCancelled {
                let fresh = await ChannelGuide.load(channels, from: ChannelGuide.origin(for: Date(), hoursBack: hoursBack), perPage: 100)
                guard !Task.isCancelled else { return }
                // Keep the last good schedule if a refresh returns nothing.
                if !loaded || fresh.contains(where: { !$0.entries.isEmpty }) { guide = fresh }
                loaded = true
                do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
            }
        }
    }
    private func grid(now: Date) -> some View {
        let origin = ChannelGuide.origin(for: now, hoursBack: hoursBack)
        let end = origin.addingTimeInterval(Double(hours) * 3600)
        let width = CGFloat(hours * 60) * pointsPerMinute
        return HStack(alignment: .top, spacing: gap) {
            VStack(alignment: .leading, spacing: gap) {
                Color.clear.frame(width: 150, height: rulerHeight)
                ForEach(guide) { row in
                    Button { player.playLive(row.channel) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.caption).foregroundStyle(.pink)
                            Text(row.channel.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 10).frame(width: 150, height: rowHeight)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8)).contentShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).help("Watch \(row.channel.title) live")
                }
            }
            ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack(spacing: 0) {
                        ForEach(0..<(hours * 2), id: \.self) { slot in
                            Text(ChannelGuide.clock(origin.addingTimeInterval(Double(slot) * 1800)))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .frame(width: 30 * pointsPerMinute, height: rulerHeight, alignment: .leading)
                                .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.15)).frame(width: 1).offset(x: -5) }
                                .id("guide-slot-\(slot)")
                        }
                    }
                    ForEach(guide) { row in
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.02))
                            ForEach(row.entries.filter { $0.end > origin && $0.start < end }) { entry in
                                let from = max(entry.start, origin), to = min(entry.end, end)
                                let span = CGFloat(to.timeIntervalSince(from) / 60) * pointsPerMinute
                                // A long programme on air keeps its title where the guide opens, not off to the left.
                                let lead = entry.isOnAir(at: now) ? max(0, min(CGFloat(ChannelGuide.origin(for: now).timeIntervalSince(from) / 60) * pointsPerMinute, span - 200)) : 0
                                MacGuideBlock(entry: entry, channel: row.channel, onAir: entry.isOnAir(at: now), past: entry.isPast(at: now), lead: lead)
                                    .frame(width: max(2, CGFloat(to.timeIntervalSince(from) / 60) * pointsPerMinute - 2), height: rowHeight)
                                    .offset(x: CGFloat(from.timeIntervalSince(origin) / 60) * pointsPerMinute)
                            }
                        }.frame(width: width, height: rowHeight, alignment: .topLeading)
                    }
                }
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(.pink).frame(width: 2)
                        .offset(x: CGFloat(now.timeIntervalSince(origin) / 60) * pointsPerMinute - 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                .padding(.bottom, 12)
            }
            // Open at the present; earlier programmes are a scroll to the left.
            .onAppear { proxy.scrollTo("guide-slot-\(hoursBack * 2)", anchor: .leading) }
            }
        }
    }
}

private struct MacGuideBlock: View {
    let entry: GuideEntry
    let channel: LiveChannel
    let onAir: Bool
    let past: Bool
    let lead: CGFloat
    /// Shown earlier and not on iPlayer: kept for context, with nothing to play.
    private var expired: Bool { past && !entry.onDemand }
    /// On iPlayer now, earlier or later in the schedule: tinted so it stands apart from what cannot be played yet.
    private var available: Bool { entry.onDemand && !onAir }
    @EnvironmentObject private var player: MacPlayerController
    @EnvironmentObject private var history: WatchHistory
    @State private var hovering = false
    @State private var showDetails = false
    @State private var opening = false
    @State private var error: String?
    private var times: String { ChannelGuide.times(entry) }
    var body: some View {
        Button { if onAir { player.playLive(channel) } else { showDetails = true } } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout.weight(.semibold)).lineLimit(1)
                if !entry.subtitle.isEmpty { Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 5) {
                    Text(onAir ? "On now · until \(ChannelGuide.clock(entry.end))" : ChannelGuide.clock(entry.start)).font(.caption2.monospaced())
                    if available { Image(systemName: "play.circle.fill").font(.caption2).foregroundStyle(.teal).accessibilityLabel("Available on demand") }
                }.foregroundStyle(onAir ? Color.pink : Color.secondary).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.leading, lead).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(onAir ? Color.pink.opacity(hovering ? 0.34 : 0.22) : available ? Color.teal.opacity(hovering ? 0.36 : 0.22) : Color.white.opacity(hovering ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(hovering ? 0.45 : 0), lineWidth: 1.5) }
            .clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(expired ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(entry.title) · \(times)\(onAir ? " · click to watch live" : expired ? " · no longer available" : entry.onDemand ? " · available on demand" : "")")
        .accessibilityLabel("\(entry.title), \(channel.title), \(times)")
        .contextMenu {
            if !past { Button("Watch \(channel.title) live") { player.playLive(channel) } }
            Button("Programme details") { showDetails = true }
        }
        .popover(isPresented: $showDetails, arrowEdge: .bottom) { details }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.title).font(.headline)
            if !entry.subtitle.isEmpty { Text(entry.subtitle).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Text(times).font(.callout.monospaced())
                Text(channel.title).font(.callout).foregroundStyle(.secondary)
                if past { Text(expired ? "Shown earlier · not available" : "Shown earlier").font(.caption).foregroundStyle(.secondary) }
                if entry.isRepeat { Text("Repeat").font(.caption).foregroundStyle(.secondary) }
            }
            if !entry.synopsis.isEmpty { Text(entry.synopsis).font(.callout).fixedSize(horizontal: false, vertical: true) }
            if let error { MacWarning(error) }
            HStack(spacing: 10) {
                if onAir { Button("Watch live") { showDetails = false; player.playLive(channel) }.keyboardShortcut(.defaultAction) }
                // Earlier programmes, repeats and box-set episodes are on iPlayer already.
                if entry.onDemand, let id = entry.episodeID {
                    Button(onAir ? "Watch from the start" : past ? "Watch on demand" : "Watch now on demand") { watch(id) }.disabled(opening)
                }
                if opening { ProgressView().controlSize(.small) }
            }.padding(.top, 2)
        }.padding(16).frame(width: 340, alignment: .leading)
    }
    private func watch(_ id: String) {
        opening = true; error = nil
        Task { @MainActor in
            defer { opening = false }
            do {
                let programme = try await BBCService().programme(id)
                showDetails = false
                player.play(programme, show: nil, history: history)
            } catch { self.error = error.localizedDescription }
        }
    }
}
