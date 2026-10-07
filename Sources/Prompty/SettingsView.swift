import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case templates
    case library
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .templates: "Templates"
        case .library: "Library"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .templates: "curlybraces"
        case .library: "tray.full.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .templates: .accentColor
        case .library: .orange
        case .about: .purple
        }
    }
}

/// Settings as a page inside the panel: a sidebar of sections on the left,
/// the selected section on the right.
struct SettingsView: View {
    @Bindable var viewModel: PromptyViewModel
    @ObservedObject var hotKeyController: HotKeyController

    @Namespace private var sidebarSelection

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Settings", backHelp: "Back (Esc)", onBack: viewModel.closeSettings) {
                KeyHint("Back", keys: "Esc")
            }
            Divider().opacity(0.7)

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 184)
                Divider().opacity(0.7)
                ScrollView {
                    pane
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
                .id(viewModel.settingsPane)
            }
        }
        .onDisappear { hotKeyController.stopRecording() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                let isSelected = viewModel.settingsPane == pane
                HStack(spacing: 9) {
                    GlyphTile(systemName: pane.systemImage, tint: pane.tint, size: 22)
                    Text(pane.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                            .fill(Theme.selectionFill)
                            .matchedGeometryEffect(id: "pane", in: sidebarSelection)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { viewModel.settingsPane = pane }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
            Spacer(minLength: 0)
            Text("↑↓ to switch sections")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .padding(8)
        .animation(Theme.selection, value: viewModel.settingsPane)
    }

    @ViewBuilder
    private var pane: some View {
        switch viewModel.settingsPane {
        case .general: GeneralSettings(hotKeyController: hotKeyController)
        case .templates: TemplateSettings()
        case .library: LibrarySettings(viewModel: viewModel)
        case .about: AboutSettings(viewModel: viewModel, hotKeyController: hotKeyController)
        }
    }
}

// MARK: - Panes

private struct GeneralSettings: View {
    @ObservedObject var hotKeyController: HotKeyController

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @AppStorage("prompty.liquidGlassEnabled") private var liquidGlassEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Shortcut") {
                SettingsRow(title: "Open Prompty", subtitle: "Press from any app to show or hide the panel.") {
                    HStack(spacing: 8) {
                        if hotKeyController.shortcut != .default && !hotKeyController.isRecording {
                            Button("Reset") { _ = hotKeyController.resetShortcut() }
                                .buttonStyle(.link)
                                .font(.system(size: 11.5))
                        }
                        ShortcutRecorderView(controller: hotKeyController)
                            .frame(width: 140, height: 28)
                    }
                }
                if let registrationError = hotKeyController.registrationError {
                    SettingsNote(text: registrationError, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
            }

            SettingsGroup(title: "Startup") {
                SettingsRow(title: "Open at login", subtitle: "Keep Prompty ready in the menu bar after you sign in.") {
                    Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: updateLaunchAtLogin))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                if let loginError {
                    SettingsNote(text: loginError, systemImage: "exclamationmark.circle.fill", tint: .orange)
                }
            }

            SettingsGroup(title: "Appearance") {
                SettingsRow(title: "Liquid Glass", subtitle: "Glass edges on the panel. Turn off for a plain frosted card.") {
                    Toggle("Liquid Glass", isOn: $liquidGlassEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct TemplateSettings: View {
    @AppStorage(Prompt.singleBraceDefaultsKey) private var singleBraceVariables = false
    @State private var rememberedCount = TemplateSettings.loadRememberedCount()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Variables") {
                SettingsRow(
                    title: "Also treat {name} as a variable",
                    subtitle: "{{name}} always works. Single braces are off by default because code and JSON use them."
                ) {
                    Toggle("Single-brace variables", isOn: $singleBraceVariables)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                Divider().padding(.leading, 14)
                SettingsRow(
                    title: "Remembered values",
                    subtitle: rememberedCount == 0
                        ? "Values you type are pre-filled next time. Nothing saved yet."
                        : "\(rememberedCount) value\(rememberedCount == 1 ? "" : "s") will be pre-filled next time."
                ) {
                    Button("Clear") {
                        UserDefaults.standard.removeObject(forKey: PromptyViewModel.variableMemoryKey)
                        rememberedCount = 0
                    }
                    .controlSize(.small)
                    .disabled(rememberedCount == 0)
                }
            }

            SettingsGroup(title: "Syntax") {
                syntaxRow("{{name}}", "A value you fill in before copying")
                syntaxRow("{{tone:friendly}}", "A variable with a default")
                syntaxRow("{{clipboard}}", "Starts with what you last copied")
                syntaxRow("{{date}}", "Today’s date")
            }
        }
    }

    private func syntaxRow(_ syntax: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(syntax)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 130, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 30)
    }

    private static func loadRememberedCount() -> Int {
        (UserDefaults.standard.dictionary(forKey: PromptyViewModel.variableMemoryKey) ?? [:]).count
    }
}

private struct LibrarySettings: View {
    let viewModel: PromptyViewModel

    @State private var status: String?

    private var store: PromptStore { viewModel.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Backup & Sharing") {
                SettingsRow(title: "Export", subtitle: "Save a copy of all \(store.prompts.count) prompts.") {
                    HStack(spacing: 6) {
                        Button("JSON…", action: exportJSON)
                        Button("Markdown…", action: exportMarkdown)
                    }
                    .controlSize(.small)
                }
                Divider().padding(.leading, 14)
                SettingsRow(title: "Import", subtitle: "Add prompts from a Prompty JSON export.") {
                    Button("Import…", action: importJSON)
                        .controlSize(.small)
                        .disabled(store.isEditingBlocked)
                }
                if let status {
                    SettingsNote(text: status, systemImage: "info.circle.fill", tint: .secondary)
                }
            }

            SettingsGroup(title: "Storage") {
                SettingsRow(title: "Data file", subtitle: (store.storageURL.path as NSString).abbreviatingWithTildeInPath) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.storageURL])
                    }
                    .controlSize(.small)
                }
                if let error = store.storageError {
                    SettingsNote(text: error.localizedDescription, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
            }
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.title = "Export Prompts as JSON"
        panel.nameFieldStringValue = "prompts.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        viewModel.runModal {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try store.exportJSON().write(to: url, options: .atomic)
                status = "Exported \(store.prompts.count) prompts to \(url.lastPathComponent)"
            } catch {
                status = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.title = "Export Prompts as Markdown"
        panel.nameFieldStringValue = "prompts.md"
        panel.canCreateDirectories = true
        viewModel.runModal {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try store.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
                status = "Exported \(store.prompts.count) prompts to \(url.lastPathComponent)"
            } catch {
                status = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.title = "Import Prompts"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        viewModel.runModal {
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let count = try store.importJSON(from: Data(contentsOf: url))
                status = "Imported \(count) prompt\(count == 1 ? "" : "s")"
            } catch {
                status = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct AboutSettings: View {
    let viewModel: PromptyViewModel
    @ObservedObject var hotKeyController: HotKeyController

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                .padding(.top, 18)
            Text("Prompty")
                .font(.system(size: 20, weight: .semibold))
            Text(version)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Your prompts, one shortcut away.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            HStack(spacing: 4) {
                Text("Press")
                Keycap(hotKeyController.shortcut.displayName)
                Text("in any app.")
            }
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                Button("Shortcuts & Tips", action: viewModel.showGuide)
                Button("Quit Prompty") { NSApp.terminate(nil) }
            }
            .controlSize(.regular)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Building blocks

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: title)
                .padding(.horizontal, -10)
            VStack(spacing: 0) {
                content
            }
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 0.5)
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct SettingsNote: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
