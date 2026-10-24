// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

private struct OpenSidebarKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var beebOpenSidebar: (() -> Void)? {
        get { self[OpenSidebarKey.self] }
        set { self[OpenSidebarKey.self] = newValue }
    }
}

/// Observe failed native focus movements, so moving between cards, picker options and
/// keyboard keys retains tvOS behaviour. Only an actual content boundary opens navigation.
struct NavigationEdgeObserver: UIViewRepresentable {
    let enabled: Bool
    var onLeft: (() -> Void)?
    var onUp: (() -> Void)?
    func makeUIView(context: Context) -> BoundaryView { BoundaryView() }
    func updateUIView(_ view: BoundaryView, context: Context) {
        view.enabled = enabled; view.onLeft = onLeft; view.onUp = onUp
    }
    final class BoundaryView: UIView {
        var enabled = false
        var onLeft: (() -> Void)?
        var onUp: (() -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            NotificationCenter.default.addObserver(self, selector: #selector(failed(_:)), name: UIFocusSystem.movementDidFailNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        deinit { NotificationCenter.default.removeObserver(self) }
        @objc private func failed(_ notification: Notification) {
            guard enabled, let window, !isHidden,
                  let context = notification.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext,
                  let item = context.previouslyFocusedItem ?? UIFocusSystem.focusSystem(for: self)?.focusedItem else { return }
            // A root view can remain mounted under a pushed page, player or text-input sheet.
            // Only respond if this marker and the focused item belong to the visible root.
            var responder: UIResponder? = self
            while responder != nil && !(responder is UIViewController) { responder = responder?.next }
            guard let owner = responder as? UIViewController, owner.presentedViewController == nil else { return }
            var environment: UIFocusEnvironment? = item
            var belongs = false
            while let current = environment {
                if current === owner || current === owner.view { belongs = true; break }
                environment = current.parentFocusEnvironment
            }
            guard belongs, convert(bounds, to: window).intersects(window.bounds) else { return }
            let action = context.focusHeading == .left ? onLeft : context.focusHeading == .up ? onUp : nil
            // Avoid changing SwiftUI focus/state from inside the native focus transaction.
            if let action { DispatchQueue.main.async { [weak self] in if self?.enabled == true { action() } } }
        }
    }
}

private struct FocusNavigationKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var beebFocusNavigation: (() -> Void)? {
        get { self[FocusNavigationKey.self] }
        set { self[FocusNavigationKey.self] = newValue }
    }
}

/// Save a SwiftUI focus binding before the sidebar disables its underlying content.
/// The captured binding remains stable when UIKit recreates a focus responder.
@MainActor final class NavigationFocusMemory: ObservableObject {
    private var current: (() -> Void)?
    private var captured: (() -> Void)?
    func remember(_ action: @escaping () -> Void) { current = action }
    func capture() { captured = current }
    func discard() { captured = nil }
    func restore() -> Bool {
        guard let action = captured else { return false }
        captured = nil
        action()
        return true
    }
}
private struct SidebarFocusMemoryKey: EnvironmentKey {
    static let defaultValue: NavigationFocusMemory? = nil
}
extension EnvironmentValues {
    var beebFocusMemory: NavigationFocusMemory? {
        get { self[SidebarFocusMemoryKey.self] }
        set { self[SidebarFocusMemoryKey.self] = newValue }
    }
}
private struct RememberSidebarFocus: ViewModifier {
    @Environment(\.beebFocusMemory) private var memory
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).onChange(of: focused) { _, value in
            if value {
                let target = $focused
                memory?.remember { target.wrappedValue = true }
            }
        }
    }
}
extension View {
    func rememberSidebarFocus() -> some View { modifier(RememberSidebarFocus()) }
}

/// Native SwiftUI buttons keep a stable focus binding for each option, including
/// when the surrounding page is temporarily disabled by the sidebar.
struct BeebNavigationSegments: View {
    let title: String
    let options: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 14) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(option).font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(selection == option ? .pink : .gray)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                    .accessibilityLabel(option).accessibilityIdentifier(option)
                    .rememberSidebarFocus()
            }
        }.padding(8).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .focusSection().accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

@MainActor final class BookmarkFocusDestination: ObservableObject {
    weak var view: UIView?
    func item() -> UIFocusItem? {
        guard let view, let window = view.window else { return nil }
        let rect = view.convert(view.bounds, to: window)
        var visited = Set<ObjectIdentifier>()
        func find(_ container: UIFocusItemContainer) -> UIFocusItem? {
            guard visited.insert(ObjectIdentifier(container)).inserted else { return nil }
            for item in container.focusItems(in: window.convert(rect, to: container.coordinateSpace)) {
                if item.canBecomeFocused { return item }
                if let children = item.focusItemContainer, let found = find(children) { return found }
            }
            return nil
        }
        return find(window)
    }
}
struct BookmarkFocusAnchor: UIViewRepresentable {
    let destination: BookmarkFocusDestination
    func makeUIView(context: Context) -> UIView {
        let view = UIView(); view.isUserInteractionEnabled = false
        destination.view = view
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { destination.view = view }
}
/// A full-width native guide immediately above the episode grid makes Up from
/// any first-row episode reach Saved, including programmes with a series selector.
struct WideBookmarkFocusGuide: UIViewRepresentable {
    let destination: BookmarkFocusDestination
    let enabled: Bool
    func makeUIView(context: Context) -> GuideView { GuideView() }
    func updateUIView(_ view: GuideView, context: Context) {
        view.destination = destination; view.active = enabled; view.setNeedsLayout()
    }
    final class GuideView: UIView {
        let guide = UIFocusGuide()
        var destination: BookmarkFocusDestination?
        var active = false
        override init(frame: CGRect) {
            super.init(frame: frame)
            addLayoutGuide(guide)
            NSLayoutConstraint.activate([
                guide.leadingAnchor.constraint(equalTo: leadingAnchor),
                guide.trailingAnchor.constraint(equalTo: trailingAnchor),
                guide.topAnchor.constraint(equalTo: topAnchor),
                guide.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
        override func layoutSubviews() {
            super.layoutSubviews()
            let target = active ? destination?.item() : nil
            guide.preferredFocusEnvironments = target.map { [$0] } ?? []
            guide.isEnabled = target != nil
        }
    }
}
