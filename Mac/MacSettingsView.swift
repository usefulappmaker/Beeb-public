// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject private var catalogue: CatalogueStore
    @AppStorage("display4KUHDCategory") private var display4KUHDCategory = true
    @AppStorage("bbcOneRegion") private var bbcOne = "bbc_one_london"
    @AppStorage("bbcTwoRegion") private var bbcTwo = "bbc_two_england"
    var body: some View {
        MacPage(title: "Settings") {
            MacSettingsGroup(title: "Live channels") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("BBC One region")
                        Picker("BBC One region", selection: $bbcOne) {
                            ForEach(RegionalChannels.bbcOne) { Text($0.title).tag($0.id) }
                        }.labelsHidden().fixedSize()
                    }
                    GridRow {
                        Text("BBC Two version")
                        Picker("BBC Two version", selection: $bbcTwo) {
                            ForEach(RegionalChannels.bbcTwo) { Text($0.title).tag($0.id) }
                        }.labelsHidden().fixedSize()
                    }
                }
            }
            MacSettingsGroup(title: "Catalogue") {
                Toggle("Display 4K UHD category", isOn: $display4KUHDCategory)
                Button("Refresh homepage") { Task { await catalogue.refreshHome() } }.disabled(catalogue.loading)
                Text("Programme listings load only when you select a category or letter. Series and episodes load when you open a programme. Saved programmes include all their series.")
                    .font(.callout).foregroundStyle(.secondary)
                if let warning = catalogue.storageWarning { MacWarning(warning) }
            }
            MacSettingsGroup(title: "Playback") {
                Text("Playback automatically selects the best available quality, including 4K HDR when available. Live channel quality adapts to the stream BBC supplies.")
                    .font(.callout).foregroundStyle(.secondary)
                MacUHDSetupView()
            }
            Text("Beeb \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") for Mac • Independent BBC player, not produced or endorsed by the BBC")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct MacSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            content
        }.padding(20).frame(maxWidth: 720, alignment: .leading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// The same one-button UHD setup as on Apple TV, driven by the shared UHDSetupState.
private struct MacUHDSetupView: View {
    @StateObject private var state = UHDSetupState()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text("Enable BBC UHD").font(.headline)
                Text(state.configured ? "UHD identity connected" : "One-time setup required")
                    .font(.callout).foregroundStyle(state.configured ? .green : .secondary)
            }
            Text("Set up 4K playback directly on this Mac. Beeb downloads the UHD configuration, stores the identity in this Mac's Keychain and checks for a compatible BBC 4K stream.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(state.busy ? "Connecting…" : "Enable BBC UHD") { state.connectDirect() }
                    .disabled(state.busy).accessibilityIdentifier("EnableBBCUHD")
                if state.busy {
                    ProgressView().controlSize(.small).accessibilityLabel("UHD setup in progress")
                    Button("Cancel setup") { state.cancel() }
                }
                if state.configured {
                    Button("Forget UHD identity") {
                        UHDIdentityVault.remove(); state.configured = false
                        state.message = "UHD identity removed from this Mac."
                    }.disabled(state.busy)
                }
            }
            if let message = state.message { Text(message).font(.callout).textSelection(.enabled).accessibilityIdentifier("BBCUHDSetupResult") }
        }
        .onAppear { state.configured = UHDIdentityVault.isConfigured }
        .onDisappear { state.cancel() }
    }
}
