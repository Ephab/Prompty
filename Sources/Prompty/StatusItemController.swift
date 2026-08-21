import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: PromptStore
    private let hotKeyController: HotKeyController
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var hostingController: NSHostingController<PromptyView>!
    private var settingsWindowController: NSWindowController?
    private var iconResetWorkItem: DispatchWorkItem?

    init(store: PromptStore, hotKeyController: HotKeyController) {
        self.store = store
        self.hotKeyController = hotKeyController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        let rootView = PromptyView(
            store: store,
            hotKeyController: hotKeyController,
            onCopy: { [weak self] in self?.showCopyConfirmation() },
            onClose: { [weak self] in self?.hidePopover() },
            onSettings: { [weak self] in self?.openSettings() },
            onContentSizeChange: { [weak self] size in
                self?.popover.contentSize = size
            }
        )
        hostingController = NSHostingController(rootView: rootView)

        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.image = Self.makeStatusImage(named: "text.quote", description: "Prompty")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "Prompty — Control–Option–Space"
            button.setAccessibilityLabel("Prompty")
        }
    }

    func install() {
        hotKeyController.onToggle = { [weak self] in
            self?.togglePopover()
        }
        _ = hotKeyController.register()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .promptyPopoverDidShow, object: nil)
        }
    }

    func hidePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.post(name: .promptyPopoverDidClose, object: nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    private func showCopyConfirmation() {
        guard let button = statusItem.button else { return }
        iconResetWorkItem?.cancel()
        button.image = Self.makeStatusImage(named: "checkmark", description: "Copied")
        button.image?.isTemplate = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            button.image = Self.makeStatusImage(named: "text.quote", description: "Prompty")
            button.image?.isTemplate = true
        }
        iconResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindowController == nil {
            let contentViewController = NSHostingController(
                rootView: SettingsView(hotKeyController: hotKeyController)
            )
            let window = NSWindow(contentViewController: contentViewController)
            window.title = "Prompty Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 430, height: 340))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindowController = NSWindowController(window: window)
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private static func makeStatusImage(named name: String, description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }

}
