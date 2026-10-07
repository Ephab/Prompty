import AppKit
import SwiftUI

/// A borderless, non-activating panel: it takes keyboard focus without
/// bringing Prompty forward, so the app you were in stays frontmost.
final class PromptyPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        // The shadow is drawn by SwiftUI so it fades with the content instead
        // of lagging behind as a window shadow would.
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows and hides the Spotlight-style panel. The window never animates;
/// only the SwiftUI content does, driven by `viewModel.isPresented`.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private enum Phase {
        case hidden, showing, shown, hiding
    }

    private let viewModel: PromptyViewModel
    private let panel: PromptyPanel
    private var phase = Phase.hidden

    /// Shown while dragging, marking the panel's home position.
    private let silhouette: NSPanel
    private var silhouetteModel = SilhouetteModel()
    private var dragTimer: Timer?
    /// Set while the controller itself moves the window, so its own moves
    /// aren't mistaken for the user dragging.
    private var isPositioning = false
    /// Where the user left the card's top-left corner; nil means home.
    private var customTopLeft: NSPoint? = UserDefaults.standard.string(forKey: FloatingPanelController.positionKey).map(NSPointFromString)

    private static let positionKey = "prompty.panelTopLeft"
    /// How close to home a release snaps back, in points.
    private static let snapDistance: CGFloat = 56

    /// When the panel last closed because it lost focus. A click on the
    /// menu-bar icon causes that, and must not immediately reopen it.
    private(set) var lastResignHide = Date.distantPast

    var isVisible: Bool { phase == .showing || phase == .shown }
    var window: NSWindow { panel }

    init(viewModel: PromptyViewModel) {
        self.viewModel = viewModel
        let margin = Theme.panelShadowMargin
        let size = Theme.panelSize
        panel = PromptyPanel(contentRect: NSRect(x: 0, y: 0, width: size.width + margin * 2, height: size.height + margin * 2))

        silhouette = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        silhouette.level = .floating
        silhouette.backgroundColor = .clear
        silhouette.isOpaque = false
        silhouette.hasShadow = false
        silhouette.ignoresMouseEvents = true
        silhouette.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        silhouette.isReleasedWhenClosed = false
        super.init()

        let hostingView = NSHostingView(rootView: RootView(viewModel: viewModel))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.delegate = self
        silhouette.contentView = NSHostingView(rootView: SilhouetteView(model: silhouetteModel))
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        switch phase {
        case .showing, .shown:
            panel.makeKey()
            return
        case .hiding:
            // Reverse the exit animation in place; the pending orderOut is
            // skipped because the phase no longer matches.
            phase = .showing
            animateIn()
            return
        case .hidden:
            break
        }

        viewModel.prepareForPresentation(window: panel)
        positionOnActiveScreen()
        phase = .showing
        panel.orderFrontRegardless()
        panel.makeKey()
        // Start on the next turn so the hidden state is on screen first.
        DispatchQueue.main.async { [weak self] in
            self?.animateIn()
        }
    }

    func hide() {
        guard isVisible else { return }
        if dragTimer != nil { endDrag() }
        phase = .hiding
        let animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Animation.easeOut(duration: 0.1) : Theme.presentOut
        withAnimation(animation) {
            viewModel.isPresented = false
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.phase == .hiding else { return }
                self.panel.orderOut(nil)
                self.phase = .hidden
                self.viewModel.didDismiss()
            }
        }
    }

    private func animateIn() {
        guard phase == .showing else { return }
        let animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Animation.easeOut(duration: 0.12) : Theme.presentIn
        withAnimation(animation) {
            viewModel.isPresented = true
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.phase == .showing else { return }
                self.phase = .shown
            }
        }
    }

    private var currentScreen: NSScreen? {
        panel.screen ?? NSScreen.main
    }

    /// The card's home frame (without the shadow margin): centred
    /// horizontally, a little above the middle, like Spotlight.
    private func homeCardFrame(on screen: NSScreen?) -> NSRect? {
        guard let visible = screen?.visibleFrame else { return nil }
        let size = Theme.panelSize
        let top = visible.maxY - visible.height * 0.18
        return NSRect(x: (visible.midX - size.width / 2).rounded(), y: (top - size.height).rounded(), width: size.width, height: size.height)
    }

    private func setCardTopLeft(_ point: NSPoint, animate: Bool = false) {
        let margin = Theme.panelShadowMargin
        let frame = panel.frame
        let origin = NSPoint(x: point.x - margin, y: point.y + margin - frame.height)
        isPositioning = true
        panel.setFrame(NSRect(origin: origin, size: frame.size), display: true, animate: animate)
        isPositioning = false
    }

    private var cardTopLeft: NSPoint {
        let margin = Theme.panelShadowMargin
        return NSPoint(x: panel.frame.minX + margin, y: panel.frame.maxY - margin)
    }

    /// Opens where the user last left the panel if that spot is still on a
    /// screen; otherwise at home on the screen under the pointer.
    private func positionOnActiveScreen() {
        if let custom = customTopLeft, NSScreen.screens.contains(where: { NSMouseInRect(custom, $0.visibleFrame, false) }) {
            setCardTopLeft(custom)
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let home = homeCardFrame(on: screen) else { return }
        setCardTopLeft(NSPoint(x: home.minX, y: home.maxY))
    }

    private func rememberPosition(_ point: NSPoint?) {
        customTopLeft = point
        if let point {
            UserDefaults.standard.set(NSStringFromPoint(point), forKey: Self.positionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.positionKey)
        }
    }

    // MARK: - Dragging

    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, isVisible else { return }
        if dragTimer == nil { beginDrag() }
        updateSilhouette()
    }

    private func beginDrag() {
        guard let home = homeCardFrame(on: currentScreen) else { return }
        silhouette.setFrame(home, display: true)
        silhouetteModel.isNear = false
        silhouette.alphaValue = 1
        silhouette.order(.below, relativeTo: panel.windowNumber)
        // The system's drag loop swallows mouse-up, so watch the button state.
        // The timer runs in common modes so it fires during event tracking.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSEvent.pressedMouseButtons & 1 == 0 { self?.endDrag() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

    private func distanceFromHome() -> CGFloat? {
        guard let home = homeCardFrame(on: currentScreen) else { return nil }
        let point = cardTopLeft
        return hypot(point.x - home.minX, point.y - home.maxY)
    }

    private func updateSilhouette() {
        guard let home = homeCardFrame(on: currentScreen) else { return }
        if silhouette.frame != home { silhouette.setFrame(home, display: true) }
        let near = (distanceFromHome() ?? .infinity) < Self.snapDistance
        if near != silhouetteModel.isNear {
            withAnimation(Theme.selection) { silhouetteModel.isNear = near }
        }
    }

    private func endDrag() {
        dragTimer?.invalidate()
        dragTimer = nil
        silhouette.orderOut(nil)
        if let home = homeCardFrame(on: currentScreen), (distanceFromHome() ?? .infinity) < Self.snapDistance {
            setCardTopLeft(NSPoint(x: home.minX, y: home.maxY), animate: true)
            rememberPosition(nil)
        } else {
            rememberPosition(cardTopLeft)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Save and open panels from Settings take focus while they run;
        // the panel should still be there when they finish.
        guard isVisible, !viewModel.isRunningModal else { return }
        lastResignHide = .now
        hide()
    }
}

@MainActor
@Observable
private final class SilhouetteModel {
    var isNear = false
}

/// The outline of the panel's home position, shown while it is dragged.
private struct SilhouetteView: View {
    let model: SilhouetteModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
        shape
            .fill(Color.primary.opacity(model.isNear ? 0.12 : 0.06))
            .overlay {
                shape.strokeBorder(
                    model.isNear ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.28),
                    style: StrokeStyle(lineWidth: model.isNear ? 2 : 1.5, dash: model.isNear ? [] : [7, 5])
                )
            }
            .scaleEffect(model.isNear ? 1 : 0.985)
    }
}
