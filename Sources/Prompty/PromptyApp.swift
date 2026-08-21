import AppKit
import ServiceManagement
import SwiftUI

@main
struct PromptyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(hotKeyController: appDelegate.hotKeyController)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: PromptStore
    let hotKeyController: HotKeyController

    private var statusItemController: StatusItemController?
    private let defaults = UserDefaults.standard
    private let onboardingKey = "prompty.onboardingComplete"

    override init() {
        store = PromptStore()
        hotKeyController = HotKeyController()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItemController = StatusItemController(
            store: store,
            hotKeyController: hotKeyController
        )
        self.statusItemController = statusItemController
        statusItemController.install()

        guard !defaults.bool(forKey: onboardingKey) else { return }
        defaults.set(true, forKey: onboardingKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.showFirstRunPrompt()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? store.saveImmediately()
        hotKeyController.unregister()
    }

    private func showFirstRunPrompt() {
        statusItemController?.showPopover()
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Open Prompty at login?"
        alert.informativeText = "Prompty stays ready in your menu bar so your prompts are one shortcut away. You can change this later in Settings."
        alert.addButton(withTitle: "Start at Login")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try SMAppService.mainApp.register()
            } catch {
                let failure = NSAlert()
                failure.messageText = "Prompty couldn’t start at login"
                failure.informativeText = "You can try again in Settings. \(error.localizedDescription)"
                failure.runModal()
            }
        }
    }
}
