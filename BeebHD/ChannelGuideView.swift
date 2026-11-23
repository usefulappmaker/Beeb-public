// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct GuideSelection: Identifiable {
    let entry: GuideEntry
    let channel: LiveChannel
    var id: String { channel.id + "/" + entry.id }
}

/// A remote-driven timeline of what is, was and will be on each channel. It shows a fixed stretch of
/// time that pages at its edges: Up and Down keep the same column, so the timeline never lurches to
/// another programme's start. Every cell keeps its true width; the panel above names the focused one.
struct ChannelGuideView: View {
    let channels: [LiveChannel]
    /// Event streams without a published schedule (Red Button), listed under the channels.
    var additionalStreams: [AdditionalLiveStream] = []
    let playLive: (LiveChannel) -> Void
    var playStream: (AdditionalLiveStream) -> Void = { _ in }
    let playEpisode: (Programme) -> Void
    @Environment(\.beebFocusMemory) private var focusMemory
    @State private var guide = [GuideChannel]()
    @State private var loaded = false
    @State private var selection: GuideSelection?
    @FocusState private var focusedCell: String?
    @FocusState private var focusedDay: Date?
    /// When focus last moved: a press followed by no move is one the focus engine couldn't place.
    @State private var lastFocusMove = Date.distantPast
    /// When focus last left the day row, to tell entering the guide from below the days from returning to it.
    @State private var leftDays = Date.distantPast
    /// Start of the time on screen; nil follows the present.
    @State private var windowStart: Date?
    /// The time Up and Down aim for; nil means now.
    @State private var focusTime: Date?
    @State private var gridWidth: CGFloat = 1500
    /// Fetching an earlier programme to play on demand.
    @State private var opening: Task<Void, Never>?
    private let pointsPerMinute: CGFloat = 9
    private let rowHeight: CGFloat = 92
    private let rulerHeight: CGFloat = 40
    private let channelWidth: CGFloat = 230
    private let gap: CGFloat = 8
    /// Five days of earlier programmes that can still be watched, then the next 24 hours.
    private let hoursBack = 5 * 24
    private let hoursAhead = 24
    private static let streamPrefix = "stream/"
    /// The focused row's channel name catches Left at the window's edge, so focus pages the guide
    /// instead of escaping to the controls above.
    private static let edgePrefix = "edge/"
    private var span: TimeInterval { Double(gridWidth / pointsPerMinute) * 60 }
    private func earliest(_ now: Date) -> Date { ChannelGuide.origin(for: now, hoursBack: hoursBack) }
    private func latest(_ now: Date) -> Date { earliest(now).addingTimeInterval(Double(hoursBack + hoursAhead) * 3600) }
    /// The window on screen, kept inside the loaded schedule.
    private func start(_ now: Date) -> Date {
        let lastStart = max(earliest(now), latest(now).addingTimeInterval(-span))
        return min(max(windowStart ?? ChannelGuide.origin(for: now), earliest(now)), lastStart)
    }
    private func cellID(_ channel: LiveChannel, _ entry: GuideEntry) -> String { channel.id + "/" + entry.id }
    private func locate(_ cell: String?) -> (row: GuideChannel, entry: GuideEntry)? {
        guard let cell else { return nil }
        for row in guide { for entry in row.entries where cellID(row.channel, entry) == cell { return (row, entry) } }
        return nil
    }
    private var focused: GuideSelection? { locate(focusedCell).map { GuideSelection(entry: $0.entry, channel: $0.row.channel) } }
    private var focusedStream: AdditionalLiveStream? {
        guard let cell = focusedCell, cell.hasPrefix(Self.streamPrefix) else { return nil }
        return additionalStreams.first { Self.streamPrefix + $0.id == cell }
    }
    private func rowID(_ cell: String?) -> String? {
        cell.flatMap { $0.hasPrefix(Self.streamPrefix) ? $0 : $0.hasPrefix(Self.edgePrefix) ? String($0.dropFirst(Self.edgePrefix.count)) : locate($0)?.row.id }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !loaded { ProgressView("Getting schedules…") }
            else if guide.allSatisfy({ $0.entries.isEmpty }) && additionalStreams.isEmpty { Text("No schedules are available at the moment.").foregroundStyle(.secondary) }
            else {
                // Half-minute ticks keep the "now" line and the on-air highlight current.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 18) {
                        infoPanel(now: context.date)
                        dayPicker(now: context.date)
                        GeometryReader { geometry in
                            let width = max(600, geometry.size.width - channelWidth - gap)
                            grid(now: context.date, width: width)
                                .onAppear { gridWidth = width }
                                .onChange(of: width) { _, value in gridWidth = value }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Leaving the guide, or switching profile, abandons a programme still being looked up.
        .onDisappear { cancelOpening() }
        .onReceive(NotificationCenter.default.publisher(for: ProfileStore.changed)) { _ in cancelOpening() }
        .task(id: channels.map(\.id)) {
            guard !channels.isEmpty else { return }
            while !Task.isCancelled {
                // Leave the network to the player while something is on screen.
                if !PlaybackActivity.active {
                    if !loaded {
                        // The next few hours first, so the guide opens quickly; then the whole range.
                        let first = await ChannelGuide.load(channels, from: ChannelGuide.origin(for: Date()), perPage: 100)
                        guard !Task.isCancelled else { return }
                        guide = first; loaded = true
                    }
                    let now = Date()
                    let fresh = await ChannelGuide.load(channels, from: earliest(now), until: latest(now), perPage: 100)
                    guard !Task.isCancelled else { return }
                    // Keep the last good schedule if a refresh returns nothing.
                    if !loaded || fresh.contains(where: { !$0.entries.isEmpty }) { guide = fresh }
                    loaded = true
                }
                do { try await Task.sleep(nanoseconds: 600_000_000_000) } catch { return }
            }
        }
        .onChange(of: focusedCell) { old, cell in
            lastFocusMove = Date()
            guard let cell else { return }
            if cell.hasPrefix(Self.edgePrefix) {
                // Left from the first programme on screen: page back, or return to where focus was.
                guard let old, let (row, entry) = locate(old), !move(row, entry, forward: false) else { return }
                focusedCell = old
                return
            }
            // The focus engine can skip a row whose programme is off to one side: land on the nearest row instead.
            if old == nil {
                // Arriving from the day row: check once both focus changes have been applied.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    if focusedCell == cell, let expected = expectedLanding(from: nil, to: cell), expected != cell { focusedCell = expected }
                }
            } else if let expected = expectedLanding(from: old, to: cell), expected != cell { focusedCell = expected; return }
            // Left and Right set the time Up and Down aim for; moving between rows keeps it.
            if focusTime == nil, let entry = locate(cell)?.entry { focusTime = max(entry.start, start(Date())) }
            if let old, rowID(old) == rowID(cell), let entry = locate(cell)?.entry {
                focusTime = max(entry.start, start(Date()))
            }
            let target = $focusedCell
            focusMemory?.remember { target.wrappedValue = cell }
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
            let entry = visible[parts[1]]
            if entry.end <= start(Date()) || entry.start >= start(Date()).addingTimeInterval(span) { windowStart = ChannelGuide.halfHour(entry.start) }
            focusTime = entry.start
            focusedCell = cellID(row.channel, entry)
            if ProcessInfo.processInfo.environment["BEEB_GUIDE_SELECT"] == "1" {
                try? await Task.sleep(nanoseconds: 800_000_000)
                activate(entry, on: row.channel)
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
                    Text((Calendar.current.isDateInToday(focused.entry.start) ? "" : Self.dayName(focused.entry.start, now: now) + " ") + ChannelGuide.times(focused.entry))
                        .font(.system(size: 25, weight: .medium).monospaced())
                    Text(focused.channel.title).font(.system(size: 25)).foregroundStyle(.secondary)
                    if focused.entry.isOnAir(at: now) { Text("On now").font(.system(size: 25, weight: .semibold)).foregroundStyle(.pink) }
                    else if focused.entry.onDemand { Text(focused.entry.isPast(at: now) ? "Shown earlier · available on demand" : "Available on demand").font(.system(size: 25, weight: .semibold)).foregroundStyle(.teal) }
                    else if focused.entry.isPast(at: now) { Text("Shown earlier · not available").font(.system(size: 25, weight: .semibold)).foregroundStyle(.secondary) }
                }
                Text(focused.entry.synopsis).font(.system(size: 25)).foregroundStyle(.secondary).lineLimit(2)
            } else if let stream = focusedStream {
                Text(stream.title).font(.system(size: 34, weight: .bold)).lineLimit(1)
                Text(Self.streamDescription(stream)).font(.system(size: 25)).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text("Channel guide").font(.system(size: 34, weight: .bold))
                Text("Select a programme that is on now to watch it live. Move left for earlier programmes you can still watch, right for what is on later.")
                    .font(.system(size: 25)).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, minHeight: 124, maxHeight: 124, alignment: .topLeading)
    }
    private static func dayName(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let next = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: next) { return "Tomorrow" }
        if let previous = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: previous) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }
    /// Quick jumps between days: the same time of day on the chosen day; Now returns to the present.
    private func dayPicker(now: Date) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = (-(hoursBack / 24)...(hoursAhead / 24)).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let shown = calendar.startOfDay(for: start(now).addingTimeInterval(span / 2))
        return HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let selected = calendar.isDate(day, inSameDayAs: shown)
                Button { jump(to: day, now: now) } label: { Text(calendar.isDate(day, inSameDayAs: today) ? "Now" : Self.dayName(day, now: now)) }
                    .buttonStyle(GuideDayStyle(selected: selected))
                    .focused($focusedDay, equals: day)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
            // Over the timeline, so Down from any day has a programme beneath it; the section spans the full
            // width so Up from anywhere in the guide reaches the days rather than the top bar.
            .padding(.leading, channelWidth + gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection().accessibilityElement(children: .contain).accessibilityLabel("Day")
            .onMoveCommand { direction in if direction == .down { ensureVerticalMove(true) } }
            // Arriving from above or below lands on the day on screen, not the first in the row.
            .onChange(of: focusedDay) { old, day in
                lastFocusMove = Date()
                if day == nil { leftDays = Date() }
                if old == nil, day != nil, day != shown { focusedDay = shown }
            }
    }
    private func jump(to day: Date, now: Date) {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { windowStart = nil; focusTime = nil; return }
        let current = start(now)
        let target = day.addingTimeInterval(current.timeIntervalSince(calendar.startOfDay(for: current)))
        windowStart = target
        focusTime = max(target, earliest(now))
    }
    private static func streamDescription(_ stream: AdditionalLiveStream) -> String {
        let extra = stream.id == "uk_bbc_stream_041" ? "Events in Ultra HD when they're on." : "Extra live coverage when it's on, such as sport and events."
        return extra + " BBC doesn't publish a schedule for it; select to try it now."
    }
    private func grid(now: Date, width: CGFloat) -> some View {
        let start = start(now)
        let end = start.addingTimeInterval(Double(width / pointsPerMinute) * 60)
        let aim = min(max(focusTime ?? now, start), end.addingTimeInterval(-60))
        let currentRow = rowID(focusedCell)
        let neighbours = neighbourRows(of: currentRow)
        func x(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(start) / 60) * pointsPerMinute }
        let marks = stride(from: ChannelGuide.halfHour(start, roundingUp: true).timeIntervalSinceReferenceDate, to: end.timeIntervalSinceReferenceDate - 1500, by: 1800)
            .map { Date(timeIntervalSinceReferenceDate: $0) }
        return ScrollView(.vertical) {
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    Color.clear.frame(width: channelWidth, height: rulerHeight)
                    ForEach(guide) { row in
                        channelName(row.channel.title).overlay {
                            Button {} label: { Color.clear }
                                .buttonStyle(GuideEdgeStyle())
                                .focused($focusedCell, equals: Self.edgePrefix + row.id)
                                .disabled(currentRow != row.id)
                                .accessibilityHidden(true)
                        }
                    }
                    ForEach(additionalStreams) { stream in channelName(stream.title) }
                }
                VStack(alignment: .leading, spacing: gap) {
                    ZStack(alignment: .topLeading) {
                        ForEach(marks, id: \.self) { mark in
                            Text(ChannelGuide.clock(mark)).font(.system(size: 22, weight: .medium).monospaced()).foregroundStyle(.secondary)
                                .offset(x: x(mark))
                        }
                    }.frame(width: width, height: rulerHeight, alignment: .topLeading).clipped()
                    ForEach(guide) { row in
                        // Away from the focused row only the programme at the focus time takes focus,
                        // so Up and Down land in the same column.
                        let landing = currentRow == row.id || !neighbours.contains(row.id) ? nil : ChannelGuide.landing(in: row.entries, at: aim, from: start, to: end)
                        HStack(spacing: 0) {
                            ForEach(ChannelGuide.segments(row.entries, from: start, to: end)) { segment in
                                let cellWidth = CGFloat(segment.minutes) * pointsPerMinute
                                if let entry = segment.entry {
                                    cell(entry, on: row.channel, width: cellWidth, continues: entry.start < start, now: now,
                                         reachable: currentRow == row.id || landing?.id == entry.id,
                                         growsLeft: x(segment.start) + Self.expandedWidth > width)
                                }
                                else { Color.clear.frame(width: cellWidth, height: rowHeight) }
                            }
                        }.frame(width: width, height: rowHeight, alignment: .leading)
                    }
                    ForEach(additionalStreams) { stream in
                        let id = Self.streamPrefix + stream.id
                        streamCell(stream, width: width, reachable: currentRow == id || neighbours.contains(id))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if now >= start && now < end {
                        Rectangle().fill(.pink).frame(width: 3)
                            .offset(x: x(now) - 1.5)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .onMoveCommand { direction in
                    if direction == .up || direction == .down { ensureVerticalMove(direction == .down); return }
                    // Right at the window's edge; Left is caught by the channel name.
                    guard direction == .right, let (row, entry) = locate(focusedCell) else { return }
                    move(row, entry, forward: true)
                }
            }.padding(.bottom, 60)
        }
    }
    /// The programme to land on in each row, top to bottom, for the time Up and Down aim for.
    private func landings(now: Date) -> [(row: String, cell: String)] {
        let start = start(now), end = start.addingTimeInterval(span)
        let aim = min(max(focusTime ?? now, start), end.addingTimeInterval(-60))
        return guide.compactMap { row in
            ChannelGuide.landing(in: row.entries, at: aim, from: start, to: end).map { (row.id, cellID(row.channel, $0)) }
        } + additionalStreams.map { (Self.streamPrefix + $0.id, Self.streamPrefix + $0.id) }
    }
    /// After a move between rows (or down from the day row), the cell that should have taken focus.
    private func expectedLanding(from old: String?, to cell: String) -> String? {
        let order = guide.map(\.id) + additionalStreams.map { Self.streamPrefix + $0.id }
        guard let new = rowID(cell), !cell.hasPrefix(Self.edgePrefix), let to = order.firstIndex(of: new) else { return nil }
        let rows = landings(now: Date())
        if old == nil {   // entering from the day row: the first row with something to land on
            guard Date().timeIntervalSince(leftDays) < 0.3 else { return nil }
            return rows.first?.cell
        }
        guard let old, !old.hasPrefix(Self.edgePrefix), let previous = rowID(old), previous != new, let from = order.firstIndex(of: previous) else { return nil }
        let between = to > from ? Array(order[(from + 1)...to]) : Array(order[to..<from].reversed())
        return between.lazy.compactMap { id in rows.first { $0.row == id }?.cell }.first
    }
    /// The focus engine only moves to something roughly beneath the focus. When the programme to land on is off to
    /// one side (the one at the focus time is greyed out), the press goes nowhere, so move focus here instead.
    /// The press is reported after any move it made, so only act when focus hasn't moved at all.
    private func ensureVerticalMove(_ down: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard Date().timeIntervalSince(lastFocusMove) > 0.3 else { return }
            let now = Date(), rows = landings(now: now)
            guard let cell = focusedCell else {   // from the day row into the guide
                if down, focusedDay != nil, let first = rows.first { focusedCell = first.cell }
                return
            }
            // Rows above or below the current one, nearest first.
            let order = guide.map(\.id) + additionalStreams.map { Self.streamPrefix + $0.id }
            guard let current = rowID(cell), let position = order.firstIndex(of: current) else { return }
            let targets = down ? Array(order[(position + 1)...]) : Array(order[..<position].reversed())
            if let next = targets.lazy.compactMap({ id in rows.first { $0.row == id } }).first { focusedCell = next.cell }
            else if !down { focusedDay = Calendar.current.startOfDay(for: start(now).addingTimeInterval(span / 2)) }
        }
    }
    /// Left or Right at the edge of the window: move it to the next programme and focus that.
    @discardableResult private func move(_ row: GuideChannel, _ entry: GuideEntry, forward: Bool) -> Bool {
        let now = Date()
        guard let move = ChannelGuide.page(row.entries, from: entry, forward: forward, start: start(now), span: span,
                                           earliest: earliest(now), latest: latest(now)) else { return false }
        let target = cellID(row.channel, move.entry)
        withTransaction(Transaction(animation: nil)) {
            windowStart = move.start
            focusTime = max(move.entry.start, move.start)
            focusedCell = target
        }
        // The old cell may have left the screen; claim focus again once the new window is laid out.
        Task { @MainActor in
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                if focusedCell != target { focusedCell = target }
            }
        }
        return true
    }
    private func channelName(_ title: String) -> some View {
        Text(title).font(.system(size: 26, weight: .bold)).lineLimit(2)
            .padding(.horizontal, 18).frame(width: channelWidth, height: rowHeight, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    /// A focused programme narrower than this shows a wider copy over its neighbours, so its title can be read in place.
    private static let expandedWidth: CGFloat = 340
    private func cell(_ entry: GuideEntry, on channel: LiveChannel, width: CGFloat, continues: Bool, now: Date, reachable: Bool, growsLeft: Bool) -> some View {
        let onAir = entry.isOnAir(at: now)
        let expanded = focusedCell == cellID(channel, entry) && width - 6 < Self.expandedWidth
        let available = ChannelGuide.playable(entry, at: now)
        return Button { activate(entry, on: channel) } label: { GuideCellLabel(entry: entry, onAir: onAir, roomy: width >= 120, continues: continues) }
            // No longer watchable: greyed out, but it still takes focus so Up and Down keep their column.
            .buttonStyle(GuideCellStyle(onAir: onAir, onDemand: entry.onDemand, unavailable: !available))
            .focused($focusedCell, equals: cellID(channel, entry))
            .disabled(!reachable)   // the style ignores this: only the remote's path changes
            .frame(width: max(6, width - 6), height: rowHeight)
            // Drawn over the neighbours without changing the cell's frame, so the remote's path stays the same.
            .overlay(alignment: growsLeft ? .trailing : .leading) {
                if expanded {
                    GuideCellLabel(entry: entry, onAir: onAir, roomy: true, continues: continues)
                        .foregroundStyle(.black)
                        .frame(width: Self.expandedWidth, height: rowHeight)
                        .background(available ? Color.white : Color(white: 0.6), in: RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .pink.opacity(0.55), radius: 14)
                        .allowsHitTesting(false).accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: expanded)
            .padding(.trailing, 6)
            .zIndex(expanded ? 1 : 0)
            .accessibilityLabel("\(entry.title), \(channel.title), \(ChannelGuide.times(entry))" + (available ? "" : ", not available"))
    }
    /// Away from the focused row, only the nearest rows above and below (or the first row, from the day row) take
    /// focus, each at the focus time, so Up and Down move exactly one row and the focus engine can't skip one.
    private func neighbourRows(of current: String?) -> Set<String> {
        let order = guide.map(\.id) + additionalStreams.map { Self.streamPrefix + $0.id }
        let landable = Set(landings(now: Date()).map(\.row))
        guard let current, let index = order.firstIndex(of: current) else { return Set(order.first { landable.contains($0) }.map { [$0] } ?? []) }
        let above = order[..<index].reversed().first { landable.contains($0) }
        let below = order[(index + 1)...].first { landable.contains($0) }
        return Set([above, below].compactMap { $0 })
    }
    private func streamCell(_ stream: AdditionalLiveStream, width: CGFloat, reachable: Bool) -> some View {
        Button { cancelOpening(); playStream(stream) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(stream.title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                Text(stream.id == "uk_bbc_stream_041" ? "Ultra HD events when on air" : "Live events and extra coverage when on air")
                    .font(.system(size: 19)).opacity(0.7).lineLimit(1)
                Text("Select to watch").font(.system(size: 18, weight: .medium)).opacity(0.75).lineLimit(1)
            }.padding(.horizontal, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .buttonStyle(GuideCellStyle(onAir: true, onDemand: false))
        .focused($focusedCell, equals: Self.streamPrefix + stream.id)
        .disabled(!reachable)
        .frame(width: max(6, width - 6), height: rowHeight).padding(.trailing, 6)
        .accessibilityLabel("\(stream.title), live events when on air")
    }
    private func cancelOpening() { opening?.cancel(); opening = nil }
    private func activate(_ entry: GuideEntry, on channel: LiveChannel) {
        cancelOpening()   // a new choice replaces a programme still being looked up
        let now = Date()
        if entry.isOnAir(at: now) { playLive(channel); return }
        // Finished and on iPlayer: play the episode straight away; the details card is the fallback.
        guard entry.isPast(at: now), entry.onDemand, let id = entry.episodeID else { selection = GuideSelection(entry: entry, channel: channel); return }
        opening = Task { @MainActor in
            do {
                let programme = try await BBCService().programme(id)
                try Task.checkCancellation()
                playEpisode(programme)
            } catch { if !Task.isCancelled { selection = GuideSelection(entry: entry, channel: channel) } }
            if !Task.isCancelled { opening = nil }
        }
    }
}

private struct GuideCellLabel: View {
    let entry: GuideEntry
    let onAir: Bool
    /// Cells for very short programmes are too narrow for text; the panel above describes them.
    let roomy: Bool
    /// The programme began before the time on screen.
    let continues: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if roomy {
                HStack(spacing: 6) {
                    if continues { Image(systemName: "chevron.left").font(.system(size: 18, weight: .bold)).opacity(0.6).accessibilityHidden(true) }
                    Text(entry.title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                }
                if !entry.subtitle.isEmpty { Text(entry.subtitle).font(.system(size: 19)).opacity(0.7).lineLimit(1) }
                HStack(spacing: 8) {
                    Text(onAir ? "On now" : ChannelGuide.clock(entry.start)).font(.system(size: 18, weight: .medium).monospaced())
                    if entry.onDemand && !onAir { Image(systemName: "play.circle.fill").font(.system(size: 17)).accessibilityLabel("Available on demand") }
                }.opacity(0.75).lineLimit(1)
            }
        }.padding(.horizontal, roomy ? 14 : 0).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Slim day choice: the day on screen is pink and underlined; focus is a small white pill.
private struct GuideDayStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View { GuideDayLabel(label: configuration.label, selected: selected) }
}
private struct GuideDayLabel<Label: View>: View {
    let label: Label
    let selected: Bool
    @Environment(\.isFocused) private var focused
    var body: some View {
        label.font(.system(size: 22, weight: .semibold)).lineLimit(1).fixedSize()
            .foregroundStyle(focused ? Color.black : selected ? Color.pink : Color.white.opacity(0.6))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(focused ? Color.white : Color.clear, in: Capsule())
            .overlay(alignment: .bottom) {
                if selected && !focused { Capsule().fill(.pink).frame(height: 3).padding(.horizontal, 14).offset(y: 2) }
            }
            .animation(.easeOut(duration: 0.12), value: focused)
            .focusEffectDisabled()
    }
}

/// Invisible: focus only passes through it on the way to another window of programmes.
private struct GuideEdgeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.focusEffectDisabled() }
}

/// Focus changes colour, not size: neighbouring cells sit edge to edge.
private struct GuideCellStyle: ButtonStyle {
    let onAir: Bool
    /// On iPlayer already: tinted so it stands apart from later programmes that cannot be played yet.
    let onDemand: Bool
    /// Shown earlier and not on iPlayer: greyed out.
    var unavailable = false
    func makeBody(configuration: Configuration) -> some View {
        GuideCellSurface(content: configuration.label, pressed: configuration.isPressed, onAir: onAir, onDemand: onDemand, unavailable: unavailable)
    }
}
private struct GuideCellSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    let onAir: Bool
    let onDemand: Bool
    let unavailable: Bool
    @Environment(\.isFocused) private var focused
    private var fill: Color {
        if unavailable { return focused ? Color(white: 0.6) : Color.white.opacity(0.03) }
        return focused ? Color.white : onAir ? Color.pink.opacity(0.3) : onDemand ? Color.teal.opacity(0.3) : Color.white.opacity(0.08)
    }
    var body: some View {
        content.foregroundStyle(focused ? Color.black : unavailable ? Color.white.opacity(0.35) : Color.white)
            .background(fill, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .pink.opacity(focused && !unavailable ? 0.55 : 0), radius: 14)
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
    @State private var lookup: Task<Void, Never>?
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
        .onDisappear { lookup?.cancel() }   // closed while still looking the episode up
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
        lookup = Task { @MainActor in
            do {
                let programme = try await BBCService().programme(id)
                try Task.checkCancellation()
                close { playEpisode(programme) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; opening = false } }
        }
    }
}
