import AppKit
import SwiftUI

struct LibraryView: View {
    @Bindable var viewModel: PromptyViewModel

    @FocusState private var searchFocused: Bool
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.7)
            mainArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.7)
            LibraryFooter(viewModel: viewModel)
        }
        .onAppear(perform: focusSearch)
        .onChange(of: viewModel.presentationID) { _, _ in focusSearch() }
        .onChange(of: viewModel.searchFocusRequest) { _, _ in focusSearch() }
    }

    private func focusSearch() {
        DispatchQueue.main.async { searchFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            searchField(fontSize: 20)
            filterChips
            addButton
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 58)
    }

    private func searchField(fontSize: CGFloat) -> some View {
        HStack(spacing: 6) {
            TextField("Search prompts…", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
                .focused($searchFocused)
                .accessibilityLabel("Search prompts")
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                    focusSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: fontSize * 0.7))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
    }

    private var filterChips: some View {
        HStack(spacing: 6) {
            FilterChip(title: "All  \(viewModel.store.prompts.count)", isOn: viewModel.filter == .all) {
                viewModel.filter = .all
            }
            FilterChip(
                title: "Favorites  \(viewModel.favoritesCount)",
                systemImage: "star.fill",
                iconTint: Theme.favorite,
                isOn: viewModel.filter == .favorites
            ) {
                viewModel.filter = .favorites
            }
        }
    }

    private var addButton: some View {
        Button {
            viewModel.beginAdding()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.store.isEditingBlocked)
        .opacity(viewModel.store.isEditingBlocked ? 0.4 : 1)
        .help("New Prompt (⌘N)")
        .accessibilityLabel("New prompt")
    }

    // MARK: Main area

    @ViewBuilder
    private var mainArea: some View {
        if viewModel.store.isEditingBlocked, let storageError = viewModel.store.storageError {
            StorageErrorView(error: storageError, storageURL: viewModel.store.storageURL)
        } else {
            VStack(spacing: 0) {
                if let message = viewModel.errorMessage ?? viewModel.store.storageError?.localizedDescription {
                    ErrorBanner(message: message)
                }
                if viewModel.results.isEmpty {
                    EmptyLibraryView(viewModel: viewModel)
                } else {
                    HStack(spacing: 0) {
                        resultsList
                            .frame(width: 300)
                        Divider().opacity(0.7)
                        PromptPreview(prompt: viewModel.selectedPrompt, viewModel: viewModel)
                    }
                }
            }
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if viewModel.showsSections {
                        let favorites = viewModel.results.filter(\.isFavorite)
                        SectionLabel(title: "Favorites")
                        rows(favorites, startingAt: 0)
                        SectionLabel(title: "Recent")
                            .padding(.top, 4)
                        rows(viewModel.results.filter { !$0.isFavorite }, startingAt: favorites.count)
                    } else {
                        rows(viewModel.results, startingAt: 0)
                    }
                }
                .padding(8)
                .animation(Theme.selection, value: viewModel.selectedID)
                .animation(Theme.selection, value: viewModel.commandHeld)
                .animation(Theme.selection, value: viewModel.copiedID)
            }
            .scrollIndicators(.automatic)
            .onChange(of: viewModel.keyboardRevealToken) { _, _ in
                guard let id = viewModel.selectedID else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func rows(_ prompts: [Prompt], startingAt start: Int) -> some View {
        ForEach(Array(prompts.enumerated()), id: \.element.id) { offset, prompt in
            PromptRow(
                prompt: prompt,
                slot: start + offset,
                isSelected: viewModel.selectedPrompt?.id == prompt.id,
                selectionNamespace: selectionNamespace,
                viewModel: viewModel
            )
            .id(prompt.id)
        }
    }
}

// MARK: - Preview

struct PromptPreview: View {
    let prompt: Prompt?
    let viewModel: PromptyViewModel

    var body: some View {
        if let prompt {
            let variables = prompt.variables(allowSingleBraces: Prompt.allowsSingleBraceVariables)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(prompt.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                        Text("\(Formatting.relativeUse(prompt.lastUsedAt)) · \(Formatting.size(of: prompt.body))")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    IconButton(
                        systemName: prompt.isFavorite ? "star.fill" : "star",
                        help: prompt.isFavorite ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)",
                        tint: prompt.isFavorite ? Theme.favorite : .secondary
                    ) { viewModel.toggleFavorite(prompt) }
                    IconButton(systemName: "pencil", help: "Edit (⌘E)") { viewModel.beginEditing(prompt) }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

                ScrollView {
                    Text(PreviewText.attributed(prompt, query: viewModel.query))
                        .font(.system(size: 12.5))
                        .lineSpacing(3.5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                }
                .scrollIndicators(.automatic)

                if !variables.isEmpty {
                    Divider().opacity(0.7)
                    HStack(spacing: 6) {
                        Text("Variables")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        ScrollView(.horizontal) {
                            HStack(spacing: 5) {
                                ForEach(variables, id: \.name) { variable in
                                    VariableChip(name: variable.name)
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }
}

struct VariableChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

enum PreviewText {
    /// The body with variable tokens drawn as tinted chips and query matches highlighted.
    static func attributed(_ prompt: Prompt, query: String) -> AttributedString {
        var result = AttributedString()
        for segment in prompt.segments() {
            switch segment {
            case let .text(text):
                result += SearchHighlight.attributed(text, query: query)
            case let .variable(_, token):
                var chip = AttributedString(token)
                chip.foregroundColor = .accentColor
                chip.backgroundColor = Color.accentColor.opacity(0.12)
                chip.font = .system(size: 12, weight: .medium, design: .monospaced)
                result += chip
            }
        }
        return result
    }
}

// MARK: - Footer

private struct LibraryFooter: View {
    let viewModel: PromptyViewModel

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 6) {
                LogoMark(height: 11)
                    .foregroundStyle(.tint)
                Text("Prompty")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 6)
            IconButton(systemName: "gearshape", help: "Settings (⌘,)", size: 24, action: viewModel.openSettings)
            IconButton(systemName: "questionmark.circle", help: "Shortcuts & Tips (⌘/)", size: 24, action: viewModel.showGuide)
            IconButton(systemName: "power", help: "Quit Prompty (⌘Q)", size: 24) { NSApp.terminate(nil) }

            Spacer(minLength: 8)

            if let prompt = viewModel.selectedPrompt {
                Button {
                    viewModel.copy(prompt)
                } label: {
                    KeyHint(prompt.placeholders.isEmpty ? "Copy" : "Fill & Copy", keys: "↵")
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 6)

                Button(action: viewModel.toggleActionPanel) {
                    KeyHint("Actions", keys: "⌘", "K")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 40)
        .background(Color.primary.opacity(0.025))
    }
}

// MARK: - Empty and error states

private struct EmptyLibraryView: View {
    let viewModel: PromptyViewModel

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            GlyphTile(systemName: glyph, tint: glyphTint, size: 46)
                .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
            buttons
                .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasQuery: Bool { !viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// nil shows the app's mark.
    private var glyph: String? {
        if hasQuery { return "magnifyingglass" }
        if viewModel.filter == .favorites { return "star" }
        return nil
    }

    private var glyphTint: Color {
        viewModel.filter == .favorites && !hasQuery ? Theme.favorite : .accentColor
    }

    private var title: String {
        if hasQuery { return "No matches for “\(viewModel.query.trimmingCharacters(in: .whitespaces))”" }
        if viewModel.filter == .favorites { return "No favorites yet" }
        return "Your prompt library is empty"
    }

    private var message: String {
        if hasQuery { return "Try fewer words, or save this as a new prompt." }
        if viewModel.filter == .favorites {
            return "Press ⌘D on a prompt to pin it here. Favorites keep their order, so ⌘1–⌘9 always reach the same prompts."
        }
        return "Save the prompts you reuse, then summon them from any app with \(viewModel.hotKeyController.shortcut.displayName)."
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            if hasQuery {
                Button("Clear Search") { viewModel.query = "" }
                    .controlSize(.regular)
                Button("New Prompt") { viewModel.beginAdding(title: viewModel.query) }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.store.isEditingBlocked)
            } else if viewModel.filter == .favorites {
                Button("Show All Prompts") { viewModel.filter = .all }
            } else {
                Button("New Prompt") { viewModel.beginAdding() }
                    .disabled(viewModel.store.isEditingBlocked)
                Button("Add Starter Prompts") { viewModel.insertStarterPrompts() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.regular)
    }
}

private struct StorageErrorView: View {
    let error: PromptStoreError
    let storageURL: URL

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            GlyphTile(systemName: "exclamationmark.triangle.fill", tint: .orange, size: 46)
            Text("Prompt library unavailable")
                .font(.system(size: 14, weight: .semibold))
            Text(error.localizedDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Reveal Data File") {
                NSWorkspace.shared.activateFileViewerSelecting([storageURL])
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - Action panel

struct ActionPanel: View {
    @Bindable var viewModel: PromptyViewModel

    var body: some View {
        let actions = viewModel.currentActions
        VStack(alignment: .leading, spacing: 0) {
            if let prompt = viewModel.selectedPrompt {
                Text(prompt.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }
            VStack(spacing: 1) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    Button {
                        viewModel.runAction(action)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 16)
                                .foregroundStyle(action.isDestructive ? Color.red : Color.secondary)
                            Text(action.title)
                                .font(.system(size: 12.5))
                                .foregroundStyle(action.isDestructive ? Color.red : Color.primary)
                            Spacer(minLength: 12)
                            HStack(spacing: 2) {
                                ForEach(action.keys, id: \.self) { Keycap($0) }
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background {
                            if index == viewModel.actionSelection {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.selectionFill)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { viewModel.actionSelection = index } }
                }
            }
            .padding(5)
        }
        .frame(width: 268)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions")
    }
}
