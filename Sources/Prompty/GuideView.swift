import SwiftUI

/// The single reference for Prompty's template syntax and keyboard shortcuts.
struct GuideView: View {
    let viewModel: PromptyViewModel
    @ObservedObject var hotKeyController: HotKeyController

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Shortcuts & Tips", backHelp: "Back (Esc)", onBack: viewModel.closeGuide) {
                EmptyView()
            }
            Divider().opacity(0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("Templates") {
                        syntaxRow("{{name}}", "A value you fill in before copying")
                        syntaxRow("{{tone:friendly}}", "A variable with a default value")
                        syntaxRow("{{clipboard}}", "Starts with whatever you last copied")
                        syntaxRow("{{date}}", "Today’s date")
                    }

                    group("Library") {
                        shortcutRow([hotKeyController.shortcut.displayName], "Open Prompty from any app")
                        shortcutRow(["↵"], "Copy, or fill a template first")
                        shortcutRow(["⇧", "↵"], "Copy a template without filling it")
                        shortcutRow(["⌘", "1–9"], "Copy a numbered result (hold ⌘ to see them)")
                        shortcutRow(["⌘", "K"], "Show all actions for the selected prompt")
                        shortcutRow(["⌘", "N"], "New prompt")
                        shortcutRow(["⌘", "E"], "Edit")
                        shortcutRow(["⌘", "J"], "Duplicate")
                        shortcutRow(["⌘", "D"], "Add or remove a favorite")
                        shortcutRow(["⌥", "⌘", "↑↓"], "Reorder favorites")
                        shortcutRow(["⌘", "⌫"], "Delete (⌘Z undoes it)")
                        shortcutRow(["Esc"], "Clear the search, then close")
                    }

                    group("Editing") {
                        shortcutRow(["⌘", "↵"], "Save and close")
                        shortcutRow(["Esc"], "Discard changes")
                    }

                    Text("Favorites keep the order you give them, so ⌘1–⌘9 always reach the same prompts. Everything else is sorted by when you last used it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title: title)
                .padding(.horizontal, -10)
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func syntaxRow(_ syntax: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Text(syntax)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 140, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
    }

    private func shortcutRow(_ keys: [String], _ description: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { Keycap($0) }
            }
            .frame(width: 140, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}
