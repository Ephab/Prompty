import AppKit
import Observation
import SwiftUI

extension Notification.Name {
    static let promptyPopoverDidShow = Notification.Name("PromptyPopoverDidShow")
    static let promptyPopoverDidClose = Notification.Name("PromptyPopoverDidClose")
}

struct PromptyView: View {
    @Bindable var store: PromptStore
    @ObservedObject var hotKeyController: HotKeyController

    let onCopy: () -> Void
    let onClose: () -> Void
    let onSettings: () -> Void
    let onContentSizeChange: (CGSize) -> Void

    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var editorID: UUID?
    @State private var draftTitle = ""
    @State private var draftBody = ""
    @State private var isNewEditor = false
    @State private var pendingSave: Task<Void, Never>?
    @State private var pendingSaveID: UUID?
    @State private var editorGeneration = UUID()
    @State private var errorMessage: String?
    @State private var pendingDeletion: Prompt?
    @AppStorage("prompty.liquidGlassEnabled") private var liquidGlassEnabled = true
    @AppStorage("prompty.promptLayout") private var promptLayoutValue = PromptLayout.list.rawValue
    @FocusState private var focusedField: Field?

    private let contentWidth: CGFloat = 420
    private let maximumVisiblePrompts = 6

    private enum Field: Hashable {
        case search
    }

    private var results: [Prompt] {
        store.matchingPrompts(for: query)
    }

    private var isEditing: Bool { editorID != nil }

    private var promptLayout: PromptLayout {
        PromptLayout(rawValue: promptLayoutValue) ?? .list
    }

    private var contentSize: CGSize {
        CGSize(width: contentWidth, height: isEditing ? 460 : libraryHeight)
    }

    private var libraryHeight: CGFloat {
        let promptCount = max(min(results.count, maximumVisiblePrompts), 1)
        let rowCount: Int
        let rowHeight: CGFloat
        let rowSpacing: CGFloat

        switch promptLayout {
        case .list:
            rowCount = promptCount
            rowHeight = 61
            rowSpacing = 2
        case .grid:
            rowCount = (promptCount + 1) / 2
            rowHeight = 104
            rowSpacing = 8
        }

        let promptListHeight = CGFloat(rowCount) * rowHeight
            + CGFloat(max(rowCount - 1, 0)) * rowSpacing
            + 16
        return 149 + promptListHeight
    }

    init(
        store: PromptStore,
        hotKeyController: HotKeyController,
        onCopy: @escaping () -> Void = { },
        onClose: @escaping () -> Void = { },
        onSettings: @escaping () -> Void = { },
        onContentSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        _store = Bindable(wrappedValue: store)
        self.hotKeyController = hotKeyController
        self.onCopy = onCopy
        self.onClose = onClose
        self.onSettings = onSettings
        self.onContentSizeChange = onContentSizeChange
    }

    var body: some View {
        rootContent
            .frame(width: contentSize.width, height: contentSize.height)
            .onAppear {
                onContentSizeChange(contentSize)
            }
            .onChange(of: contentSize) { _, newSize in
                onContentSizeChange(newSize)
            }
            .onReceive(NotificationCenter.default.publisher(for: .promptyPopoverDidShow)) { _ in
                guard !isEditing else { return }
                query = ""
                selectedID = nil
                focusedField = .search
            }
            .onReceive(NotificationCenter.default.publisher(for: .promptyPopoverDidClose)) { _ in
                if isEditing { finishEditing() }
            }
            .onChange(of: query) { _, _ in
                selectedID = results.first?.id
            }
            .onMoveCommand(perform: moveSelection)
            .onExitCommand(perform: onClose)
            .onKeyPress(.return) {
                copySelected()
                return .handled
            }
            .onKeyPress(.escape) {
                onClose()
                return .handled
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        let surface = VStack(spacing: 0) {
            if isEditing {
                editorContent
            } else {
                libraryContent
            }
        }
        .background {
            if liquidGlassEnabled {
                Color.clear
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }

        if #available(macOS 26.0, *), liquidGlassEnabled {
            surface.glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            surface
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.quote")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("Prompts")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Spacer(minLength: 0)

                Button(action: beginAdding) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.isEditingBlocked)
                .help("Add prompt")
                .accessibilityLabel("Add prompt")
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search prompts", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .search)
                    .onSubmit(copySelected)

                if !query.isEmpty {
                    Button {
                        query = ""
                        focusedField = .search
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()

            if store.isEditingBlocked, let storageError = store.storageError {
                storageErrorView(storageError)
            } else {
                VStack(spacing: 0) {
                    if let message = errorMessage ?? store.storageError?.localizedDescription {
                        errorView(message)
                    }
                    if results.isEmpty {
                        emptyState
                    } else {
                        promptList
                    }
                }
            }

            HStack(spacing: 0) {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")
                .accessibilityLabel("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
                .help("Quit Prompty")
                .accessibilityLabel("Quit Prompty")

                Spacer()

                Text("\(hotKeyController.shortcut.displayName) to open")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .padding(.vertical, 8)
        .confirmationDialog(
            "Delete this prompt?",
            isPresented: deleteConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let prompt = pendingDeletion else { return }
                pendingDeletion = nil
                deletePrompt(prompt)
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var promptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if promptLayout == .grid {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 8
                        ) {
                            ForEach(results) { prompt in
                                promptRow(prompt)
                                    .id(prompt.id)
                            }
                        }
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { prompt in
                                promptRow(prompt)
                                    .id(prompt.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func promptRow(_ prompt: Prompt) -> some View {
        if promptLayout == .grid {
            VStack(alignment: .leading, spacing: 8) {
                promptContent(prompt)

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    promptActions(prompt)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                selectedID == prompt.id ? Color.accentColor.opacity(0.13) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityElement(children: .contain)
        } else {
            HStack(spacing: 7) {
                promptContent(prompt)
                promptActions(prompt)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                selectedID == prompt.id ? Color.accentColor.opacity(0.13) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .accessibilityElement(children: .contain)
        }
    }

    private func promptContent(_ prompt: Prompt) -> some View {
        Button {
            copy(prompt)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(prompt.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered in
            if isHovered { selectedID = prompt.id }
        }
    }

    private func promptActions(_ prompt: Prompt) -> some View {
        HStack(spacing: 7) {
            Button {
                toggleFavorite(prompt)
            } label: {
                Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(prompt.isFavorite ? Color.yellow : Color.secondary)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(prompt.isFavorite ? "Remove favorite" : "Favorite prompt")
            .accessibilityLabel(prompt.isFavorite ? "Remove favorite" : "Favorite prompt")

            Button {
                beginEditing(prompt)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit prompt")
            .accessibilityLabel("Edit \(prompt.title)")

            Button(role: .destructive) {
                pendingDeletion = prompt
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete prompt")
            .accessibilityLabel("Delete \(prompt.title)")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: query.isEmpty ? "text.quote" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)

            Text(query.isEmpty ? "No prompts yet" : "No matching prompts")
                .font(.system(size: 14, weight: .medium))

            Button(query.isEmpty ? "Add prompt" : "Clear search") {
                if query.isEmpty {
                    beginAdding()
                } else {
                    query = ""
                    focusedField = .search
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(query.isEmpty && store.isEditingBlocked)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func storageErrorView(_ error: PromptStoreError) -> some View {
        VStack(spacing: 9) {
            Spacer(minLength: 0)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.orange)
            Text("Prompt library unavailable")
                .font(.system(size: 14, weight: .medium))
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Reveal data file") {
                NSWorkspace.shared.activateFileViewerSelecting([store.storageURL])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var editorContent: some View {
        EditorView(
            title: $draftTitle,
            bodyText: $draftBody,
            isNew: isNewEditor,
            onChanged: { _, _ in scheduleEditorSave() },
            onCancel: finishEditing,
            onDelete: deleteAction,
            storageError: store.storageError?.localizedDescription
        )
    }

    private var deleteAction: (() -> Void)? {
        isNewEditor ? nil : { deleteEditingPrompt() }
    }

    private func beginAdding() {
        pendingSave?.cancel()
        pendingSave = nil
        pendingSaveID = nil
        editorGeneration = UUID()
        editorID = UUID()
        draftTitle = ""
        draftBody = ""
        isNewEditor = true
        errorMessage = nil
    }

    private func beginEditing(_ prompt: Prompt) {
        pendingSave?.cancel()
        pendingSave = nil
        pendingSaveID = nil
        editorGeneration = UUID()
        editorID = prompt.id
        draftTitle = prompt.title
        draftBody = prompt.body
        isNewEditor = false
        errorMessage = nil
    }

    private func finishEditing() {
        if pendingSaveID != nil,
           let id = editorID,
           !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let favorite = store.prompts.first(where: { $0.id == id })?.isFavorite ?? false
            commitEditor(
                id: id,
                title: draftTitle,
                body: draftBody,
                creating: isNewEditor,
                favorite: favorite
            )
        }
        pendingSave?.cancel()
        pendingSave = nil
        pendingSaveID = nil
        editorGeneration = UUID()
        editorID = nil
        isNewEditor = false
        errorMessage = nil
    }

    private func scheduleEditorSave() {
        pendingSave?.cancel()
        pendingSave = nil
        pendingSaveID = nil
        guard let id = editorID,
              !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let title = draftTitle
        let body = draftBody
        let creating = isNewEditor
        let generation = editorGeneration
        let saveID = UUID()
        let favorite = store.prompts.first(where: { $0.id == id })?.isFavorite ?? false
        let task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }

            guard editorGeneration == generation,
                  editorID == id,
                  pendingSaveID == saveID else { return }
            commitEditor(
                id: id,
                title: title,
                body: body,
                creating: creating,
                favorite: favorite
            )
            if pendingSaveID == saveID {
                pendingSave = nil
                pendingSaveID = nil
            }
        }
        pendingSave = task
        pendingSaveID = saveID
    }

    private func commitEditor(
        id: UUID,
        title: String,
        body: String,
        creating: Bool,
        favorite: Bool
    ) {
        do {
            if creating {
                let prompt = try store.create(title: title, body: body)
                editorID = prompt.id
                isNewEditor = false
            } else {
                _ = try store.update(id: id, title: title, body: body, isFavorite: favorite)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEditingPrompt() {
        guard let id = editorID else { return }
        do {
            try removePrompt(id: id)
            finishEditing()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePrompt(_ prompt: Prompt) {
        do {
            try removePrompt(id: prompt.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removePrompt(id: UUID) throws {
        try store.delete(id: id)
        if selectedID == id {
            selectedID = nil
        }
    }

    private func toggleFavorite(_ prompt: Prompt) {
        do {
            _ = try store.toggleFavorite(id: prompt.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copy(_ prompt: Prompt) {
        guard NSPasteboard.general.clearContents() != 0 else { return }
        guard NSPasteboard.general.setString(prompt.body, forType: .string) else { return }
        _ = try? store.markUsed(id: prompt.id)
        onCopy()
        onClose()
    }

    private func copySelected() {
        guard !results.isEmpty else { return }
        let prompt = results.first(where: { $0.id == selectedID }) ?? results[0]
        copy(prompt)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !results.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in results.firstIndex(where: { $0.id == id }) }
        let nextIndex: Int
        switch direction {
        case .down:
            nextIndex = min((currentIndex ?? -1) + 1, results.count - 1)
        case .up:
            nextIndex = max((currentIndex ?? results.count) - 1, 0)
        default:
            return
        }
        selectedID = results[nextIndex].id
    }
}
