// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct GuideSelection: Identifiable {
    let entry: GuideEntry
    let channel: LiveChannel
    var id: String { channel.id + "/" + entry.id }
}

/// A remote-driven timeline of what is, was and will be on each channel. Every cell keeps
/// its true width, so short programmes stay aligned; the panel above names the focused one.
struct ChannelGuideView: View {
    let channels: [LiveChannel]
    let playLive: (LiveChannel) -> Void
    let playEpisode: (Programme) -> Void
    @Environment(\.beebFocusMemory) private var focusMemory
    @State private var guide = [GuideChannel]()
    @State private var loaded = false
    @State private var selection: GuideSelection?
    @FocusState private var focusedCell: String?
    private let pointsPerMinute: CGFloat = 9
    private let rowHeight: CGFloat = 92
    private let rulerHeight: CGFloat = 40
    private let channelWidth: CGFloat = 230
    private let gap: CGFloat = 8
    /// Earlier programmes that can still be watched, then the rest of the evening.
    private let hoursBack = 8
    private let hoursAhead = 6
    private var focused: GuideSelection? {
        guard let focusedCell else { return nil }
        for row in guide { for entry in row.entries where row.channel.id + "/" + entry.id == focusedCell { return GuideSelection(entry: entry, channel: row.channel) } }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !loaded { ProgressView("Getting schedules…") }
            else if guide.allSatisfy({ $0.entries.isEmpty }) { Text("No schedules are available at the moment.").foregroundStyle(.secondary) }
            else {
                // Half-minute ticks keep the "now" line and the on-air highlight current.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 18) {
                        infoPanel(now: context.date)
                        grid(now: context.date)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: channels.map(\.id)) {
            guard !channels.isEmpty else { return }
            while !Task.isCancelled {
                // Leave the network to the player while something is on screen.
                if !PlaybackActivity.active {
                    let fresh = await ChannelGuide.load(channels, from: ChannelGuide.origin(for: Date(), hoursBack: hoursBack), perPage: 100)
                    guard !Task.isCancelled else { return }
                    // Keep the last good schedule if a refresh returns nothing.
                    if !loaded || fresh.contains(where: { !$0.entries.isEmpty }) { guide = fresh }
                    loaded = true
                }
                do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
            }
        }
        .onChange(of: focusedCell) { _, cell in
            if let cell {
                let target = $focusedCell
                focusMemory?.remember { target.wrappedValue = cell }
            }
        }
        .sheet(item: $selection) { GuideEntryDetail(selection: $0, playLive: playLive, playEpisode: playEpisode) }
        #if DEBUG
        // BEEB_GUIDE_FOCUS="row,column" focuses that cell, counted from the programme on air,
        // for a layout check; BEEB_GUIDE_SELECT=1 then selects it.
        .task(id: loaded) {
            guard loaded, let raw = ProcessInfo.processInfo.environment["BEEB_GUIDE_FOCUS"] else { return }
            let parts = raw.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2, guide.indices.contains(parts[0]) else { return }
            let row = guide[parts[0]]
            let visible = row.entries.filter { !$0.isPast(at: Date()) }
            guard visible.indices.contains(parts[1]) else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            focusedCell = row.channel.id + "/" + visible[parts[1]].id
            if ProcessInfo.processInfo.environment["BEEB_GUIDE_SELECT"] == "1" {
                try? await Task.sleep(nanoseconds: 800_000_000)
                activate(visible[parts[1]], on: row.channel)
            }
        }
        #endif
    }
    private func infoPanel(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let focused {
                Text(focused.entry.subtitle.isEmpty ? focused.entry.title : "\(focused.entry.title) — \(focused.entry.subtitle)")
                    .font(.system(size: 34, weight: .bold)).lineLimit(1)
                HStack(spacing: 18) {
                    Text(ChannelGuide.times(focused.entry)).font(.system(size: 25, weight: .medium).monospaced())
                    Text(focused.channel.title).font(.system(size: 25)).foregroundStyle(.secondary)
                    if focused.entry.isOnAir(at: now) { Text("On now").font(.system(size: 25, weight: .semibold)).foregroundStyle(.pink) }
                    else if focused.entry.onDemand { Text(focused.entry.isPast(at: now) ? "Shown earlier · available on demand" : "Available on demand").font(.system(size: 25, weight: .semibold)).foregroundStyle(.teal) }
                }
                Text(focused.entry.synopsis).font(.system(size: 25)).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text("Channel guide").font(.system(size: 34, weight: .bold))
                Text("Select a programme that is on now to watch it live. Move left for earlier programmes you can still watch, right for what is on later.")
                    .font(.system(size: 25)).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .topLeading)
    }
    private func grid(now: Date) -> some View {
        let origin = ChannelGuide.origin(for: now, hoursBack: hoursBack)
        let end = origin.addingTimeInterval(Double(hoursBack + hoursAhead) * 3600)
        let width = CGFloat((hoursBack + hoursAhead) * 60) * pointsPerMinute
        // Where the guide opens. A programme that began before it would hide its title off to the left.
        let opening = ChannelGuide.origin(for: now)
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    Color.clear.frame(width: channelWidth, height: rulerHeight)
                    ForEach(guide) { row in
                        Text(row.channel.title).font(.system(size: 26, weight: .bold)).lineLimit(2)
                            .padding(.horizontal, 18).frame(width: channelWidth, height: rowHeight, alignment: .leading)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: gap) {
                            HStack(spacing: 0) {
                                ForEach(0..<((hoursBack + hoursAhead) * 2), id: \.self) { slot in
                                    Text(ChannelGuide.clock(origin.addingTimeInterval(Double(slot) * 1800)))
                                        .font(.system(size: 22, weight: .medium).monospaced()).foregroundStyle(.secondary)
                                        .frame(width: 30 * pointsPerMinute, height: rulerHeight, alignment: .leading)
                                        .id("guide-slot-\(slot)")
                                }
                            }
                            ForEach(guide) { row in
                                HStack(spacing: 0) {
                                    ForEach(ChannelGuide.segments(row.entries, from: origin, to: end)) { segment in
                                        let span = CGFloat(segment.minutes) * pointsPerMinute
                                        if let entry = segment.entry {
                                            let lead = entry.isOnAir(at: now) ? max(0, min(CGFloat(opening.timeIntervalSince(segment.start) / 60) * pointsPerMinute, span - 220)) : 0
                                            cell(entry, on: row.channel, span: span, lead: lead, now: now)
                                        }
                                        else { Color.clear.frame(width: span, height: rowHeight) }
                                    }
                                }.frame(width: width, height: rowHeight, alignment: .leading)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            Rectangle().fill(.pink).frame(width: 3)
                                .offset(x: CGFloat(now.timeIntervalSince(origin) / 60) * pointsPerMinute - 1.5)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                        .padding(.trailing, 60)
                    }
                    // Open at the present; earlier programmes are a move to the left.
                    .onAppear { proxy.scrollTo("guide-slot-\(hoursBack * 2)", anchor: .leading) }
                }
            }.padding(.bottom, 60)
        }
    }
    @ViewBuilder private func cell(_ entry: GuideEntry, on channel: LiveChannel, span: CGFloat, lead: CGFloat, now: Date) -> some View {
        let onAir = entry.isOnAir(at: now), past = entry.isPast(at: now)
        if past && !entry.onDemand {
            // No longer playable: keep its place on the timeline, but out of the remote's path.
            GuideCellLabel(entry: entry, onAir: false, roomy: span >= 120, lead: 0)
                .foregroundStyle(.white.opacity(0.35))
                .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .frame(width: max(6, span - 6), height: rowHeight).padding(.trailing, 6)
                .accessibilityHidden(true)
        } else {
            Button { activate(entry, on: channel) } label: { GuideCellLabel(entry: entry, onAir: onAir, roomy: span >= 120, lead: lead) }
                .buttonStyle(GuideCellStyle(onAir: onAir, onDemand: entry.onDemand))
                .focused($focusedCell, equals: channel.id + "/" + entry.id)
                .frame(width: max(6, span - 6), height: rowHeight).padding(.trailing, 6)
                .accessibilityLabel("\(entry.title), \(channel.title), \(ChannelGuide.times(entry))")
        }
    }
    private func activate(_ entry: GuideEntry, on channel: LiveChannel) {
        if entry.isOnAir(at: Date()) { playLive(channel) } else { selection = GuideSelection(entry: entry, channel: channel) }
    }
}

private struct GuideCellLabel: View {
    let entry: GuideEntry
    let onAir: Bool
    /// Cells for very short programmes are too narrow for text; the panel above describes them.
    let roomy: Bool
    /// Pushes the text of a long programme on air to where the guide opens.
    let lead: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if roomy {
                Text(entry.title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                if !entry.subtitle.isEmpty { Text(entry.subtitle).font(.system(size: 19)).opacity(0.7).lineLimit(1) }
                HStack(spacing: 8) {
                    Text(onAir ? "On now" : ChannelGuide.clock(entry.start)).font(.system(size: 18, weight: .medium).monospaced())
                    if entry.onDemand && !onAir { Image(systemName: "play.circle.fill").font(.system(size: 17)).accessibilityLabel("Available on demand") }
                }.opacity(0.75).lineLimit(1)
            }
        }.padding(.horizontal, roomy ? 14 : 0).padding(.leading, lead).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Focus changes colour, not size: neighbouring cells sit edge to edge.
private struct GuideCellStyle: ButtonStyle {
    let onAir: Bool
    /// On iPlayer already: tinted so it stands apart from later programmes that cannot be played yet.
    let onDemand: Bool
    func makeBody(configuration: Configuration) -> some View {
        GuideCellSurface(content: configuration.label, pressed: configuration.isPressed, onAir: onAir, onDemand: onDemand)
    }
}
private struct GuideCellSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    let onAir: Bool
    let onDemand: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        content.foregroundStyle(focused ? Color.black : Color.white)
            .background(focused ? Color.white : onAir ? Color.pink.opacity(0.3) : onDemand ? Color.teal.opacity(0.3) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .pink.opacity(focused ? 0.55 : 0), radius: 14)
            .opacity(pressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: focused)
            .focusEffectDisabled()
    }
}

/// Details for a programme that is not on air, with a route to the episode when BBC offers it.
private struct GuideEntryDetail: View {
    let selection: GuideSelection
    let playLive: (LiveChannel) -> Void
    let playEpisode: (Programme) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var opening = false
    @State private var error: String?
    private var past: Bool { selection.entry.isPast(at: Date()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text(selection.entry.title).font(.largeTitle).bold()
            if !selection.entry.subtitle.isEmpty { Text(selection.entry.subtitle).font(.title2) }
            HStack(spacing: 18) {
                Text(ChannelGuide.times(selection.entry)).font(.title3.monospaced())
                Text(selection.channel.title).font(.title3).foregroundStyle(.secondary)
                if past { Text("Shown earlier").font(.callout).foregroundStyle(.secondary) }
                if selection.entry.isRepeat { Text("Repeat").font(.callout).foregroundStyle(.secondary) }
            }
            if !selection.entry.synopsis.isEmpty { Text(selection.entry.synopsis).font(.title3) }
            if let error { Text(error).foregroundStyle(.orange).font(.callout) }
            HStack(spacing: 24) {
                // Earlier programmes, repeats and box-set episodes are on iPlayer already.
                if selection.entry.onDemand, let id = selection.entry.episodeID {
                    Button(opening ? "Finding episode…" : past ? "Watch on demand" : "Watch now on demand") { watch(id) }.disabled(opening)
                }
                if !past { Button("Watch \(selection.channel.title) live") { close { playLive(selection.channel) } }.disabled(opening) }
                Button("Close") { dismiss() }
            }.buttonStyle(OutlinedActionButtonStyle())
        }.padding(70)
        .onExitCommand { dismiss() }
    }
    /// Let this sheet leave before the player cover is presented over the Live page.
    private func close(then action: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            action()
        }
    }
    private func watch(_ id: String) {
        opening = true; error = nil
        Task { @MainActor in
            do {
                let programme = try await BBCService().programme(id)
                close { playEpisode(programme) }
            } catch { self.error = error.localizedDescription; opening = false }
        }
    }
}
