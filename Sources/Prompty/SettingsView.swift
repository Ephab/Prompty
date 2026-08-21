import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var hotKeyController: HotKeyController

    @State private var launchAtLogin = false
    @State private var loginError: String?
    @State private var didLoadLoginStatus = false
    @AppStorage("prompty.liquidGlassEnabled") private var liquidGlassEnabled = true

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Prompty at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard didLoadLoginStatus else { return }
                        updateLaunchAtLogin(enabled)
                    }

                if let loginError {
                    Label(loginError, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Appearance") {
                Toggle("Liquid Glass", isOn: $liquidGlassEnabled)
            }

            Section("Shortcut") {
                HStack {
                    Text("Show Prompty")
                    Spacer()
                    ShortcutRecorderView(controller: hotKeyController)
                        .frame(width: 150, height: 30)
                }

                if let registrationError = hotKeyController.registrationError {
                    Label(registrationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Text(hotKeyController.isRecording ? "Press a key combination" : hotKeyController.shortcut.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        _ = hotKeyController.updateShortcut(
                            keyCode: PromptyShortcut.default.keyCode,
                            modifiers: PromptyShortcut.default.modifiers
                        )
                    }
                    .buttonStyle(.link)
                    .disabled(hotKeyController.shortcut == .default)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 430)
        .padding(.vertical, 8)
        .navigationTitle("Prompty Settings")
        .onAppear {
            didLoadLoginStatus = false
            launchAtLogin = SMAppService.mainApp.status == .enabled
            _ = hotKeyController.register()
            Task { @MainActor in
                await Task.yield()
                didLoadLoginStatus = true
            }
        }
        .onDisappear {
            hotKeyController.stopRecording()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
