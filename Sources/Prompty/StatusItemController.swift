import AppKit
import Combine
import SwiftUI

/// Owns the menu-bar icon and the floating panel, and opens the panel from
/// the global shortcut or an icon click.
@MainActor
final class StatusItemController: NSObject {
    private let hotKeyController: HotKeyController
    private let viewModel: PromptyViewModel
    private let statusItem: NSStatusItem
    private let panelController: FloatingPanelController
    private var iconResetWorkItem: DispatchWorkItem?
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var shortcutSubscription: AnyCancellable?

    init(store: PromptStore, hotKeyController: HotKeyController) {
        self.hotKeyController = hotKeyController
        viewModel = PromptyViewModel(store: store, hotKeyController: hotKeyController)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panelController = FloatingPanelController(viewModel: viewModel)
        super.init()

        viewModel.onDismissRequest = { [weak self] in self?.panelController.hide() }
        viewModel.onCopied = { [weak self] in self?.showCopyConfirmation() }

        if let button = statusItem.button {
            button.image = Theme.logoMark
            button.target = self
            button.action = #selector(statusItemClicked)
            button.setAccessibilityLabel("Prompty")
        }
        shortcutSubscription = hotKeyController.$shortcut.sink { [weak self] shortcut in
            self?.statusItem.button?.toolTip = "Prompty — \(shortcut.displayName)"
        }
    }

    func install() {
        hotKeyController.onToggle = { [weak self] in
            self?.handleHotKey()
        }
        _ = hotKeyController.register()
        installEventMonitors()
    }

    func showLibrary() {
        panelController.show()
    }

    // MARK: - Routing

    private func handleHotKey() {
        // Pressing the current shortcut while recording a new one must not
        // close the Settings page out from under the recorder.
        guard !hotKeyController.isRecording else { return }
        panelController.toggle()
    }

    @objc private func statusItemClicked() {
        // The click itself takes focus from the panel and hides it; that same
        // click must not reopen it.
        guard Date.now.timeIntervalSince(panelController.lastResignHide) > 0.35 else { return }
        panelController.toggle()
    }

    // MARK: - Keyboard

    /// One local monitor routes keys for the panel, ahead of text fields and
    /// the menu bar.
    private func installEventMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.panelController.window else { return false }
                return self.viewModel.handleKeyDown(event)
            }
            return handled ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.viewModel.updateModifiers(event.modifierFlags)
            }
            return event
        }
    }

    // MARK: - Feedback

    private func showCopyConfirmation() {
        guard let button = statusItem.button else { return }
        iconResetWorkItem?.cancel()
        button.image = Self.statusImage(named: "checkmark", description: "Copied")

        let work = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.image = Theme.logoMark
        }
        iconResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private static func statusImage(named name: String, description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }
}
