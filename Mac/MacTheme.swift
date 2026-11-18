// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

enum MacTheme {
    static let background = Color(red: 0.035, green: 0.015, blue: 0.055)
    static let grid = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 14, alignment: .top)]
    static let pagePadding: CGFloat = 28
}

/// Destinations pushed onto the detail column's navigation stack.
enum MacRoute: Hashable {
    case show(CatalogueShow, preferUHD: Bool)
    case category(Genre)
    case letter(String)
    case uhd
}

struct MacUHDBadge: View {
    var body: some View {
        Text("4K").font(.system(size: 11, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 3)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white)
            .accessibilityLabel("BBC lists a 4K version")
    }
}

/// A fixed 16:9 frame; artwork never decides the card's size.
struct MacThumbnail: View {
    let url: URL?
    var uhd = false
    var progress: Double? = nil
    var body: some View {
        Color.clear.aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Rectangle().fill(.white.opacity(0.08)).overlay(Image(systemName: "play.tv").font(.title).foregroundStyle(.tertiary)) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) { if uhd { MacUHDBadge().padding(6) } }
            .overlay(alignment: .bottom) {
                if let progress { ProgressView(value: progress).tint(.pink).padding(.horizontal, 6).padding(.bottom, 4) }
            }
    }
}

/// Pointer-driven replacement for the tvOS focus card: highlight on hover.
struct MacCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MacCardSurface(content: configuration.label, pressed: configuration.isPressed)
    }
}
private struct MacCardSurface<Content: View>: View {
    let content: Content
    let pressed: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        content.padding(8)
            .background(.white.opacity(hovering ? 0.13 : 0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(hovering ? 0.45 : 0), lineWidth: 1.5) }
            .scaleEffect(pressed ? 0.985 : 1).opacity(enabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct MacShowCard: View {
    let show: CatalogueShow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacThumbnail(url: show.image, uhd: show.uhdListed == true)
            Text(show.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
        }
    }
}

/// A card that opens a programme page.
struct MacShowLink: View {
    let show: CatalogueShow
    var preferUHD = false
    var body: some View {
        NavigationLink(value: MacRoute.show(show, preferUHD: preferUHD)) { MacShowCard(show: show) }
            .buttonStyle(MacCardStyle()).accessibilityLabel(show.title)
    }
}

struct MacShowGrid: View {
    let shows: [CatalogueShow]
    var preferUHD = false
    var body: some View {
        LazyVGrid(columns: MacTheme.grid, spacing: 14) {
            ForEach(shows) { MacShowLink(show: $0, preferUHD: preferUHD) }
        }
    }
}

/// Common page chrome: scrolling content on the Beeb background with a large title.
struct MacPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.largeTitle.bold())
                content
            }.padding(MacTheme.pagePadding).frame(maxWidth: .infinity, alignment: .leading)
        }.background(MacTheme.background)
    }
}

struct MacWarning: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
}
