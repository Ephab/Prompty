import AppKit
import Observation
import SwiftUI

enum LibraryFilter: Equatable {
    case all
    case favorites
}

enum Screen: Equatable {
    case library
    case editing
    case filling
    case guide
    case settings
}

/// The prompt being written or changed. A new prompt only enters the store
/// once autosave first commits it, so cancelling must remove it again.
struct EditorSession: Equatable {
    var promptID: UUID?
    var snapshot: Prompt?
    var createdDuringSession = false
    var title: String
    var body: String

    var isNew: Bool { snapshot == nil }
    var hasContent: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct FillSession: Equatable {
    var prompt: Prompt
    var variables: [PromptVariable]
    var values: [String: String]
}

struct ToastState: Equatable {
    let id = UUID()
    var message: String
    var systemImage: String
    var offersUndo = false
}

struct PromptAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let keys: [String]
    var isDestructive = false
    let perform: () -> Void
}

/// State and behaviour for the floating panel.
@Observable
@MainActor
final class PromptyViewModel {
    let store: PromptStore
    let hotKeyController: HotKeyController

    var query = "" {
        didSet { if query != oldValue { refreshResults(resetSelection: true) } }
    }
    var filter: LibraryFilter = .all {
        didSet { if filter != oldValue { refreshResults(resetSelection: true) } }
    }
    var selectedID: UUID?
    private(set) var results: [Prompt] = []

    var screen: Screen = .library
    var settingsPane: SettingsPane = .general
    var editor: EditorSession?
    var fill: FillSession?

    private(set) var toast: ToastState?
    private(set) var copiedID: UUID?
    var errorMessage: String?

    var isActionPanelOpen = false
    var actionSelection = 0
    private(set) var commandHeld = false

    /// Drives the panel's entrance and exit animation.
    var isPresented = false
    /// Changes every time a surface is presented so views can move focus.
    private(set) var presentationID = UUID()
    /// Changes when the library should put focus back in the search field.
    private(set) var searchFocusRequest = UUID()
    /// Changes when keyboard navigation moves the selection, so the list
    /// scrolls only for the keyboard and never chases the mouse.
    private(set) var keyboardRevealToken = 0

    @ObservationIgnored weak var activeWindow: NSWindow?
    @ObservationIgnored var onDismissRequest: () -> Void = { }
    @ObservationIgnored var onCopied: () -> Void = { }
    /// True while a save or open dialog started from the panel is up.
    @ObservationIgnored private(set) var isRunningModal = false

    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var lastKeyboardNavigation = Date.distantPast

    static let variableMemoryKey = "prompty.variableMemory"

    init(store: PromptStore, hotKeyController: HotKeyController) {
        self.store = store
        self.hotKeyController = hotKeyController
        refreshResults(resetSelection: true)
    }

    // MARK: - Derived state

    var selectedPrompt: Prompt? {
        results.first(where: { $0.id == selectedID }) ?? results.first
    }

    var favoritesCount: Int { store.prompts.lazy.filter(\.isFavorite).count }

    /// Favorites and the rest are shown as separate sections when browsing.
    var showsSections: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && filter == .all
            && results.contains(where: \.isFavorite) && results.contains(where: { !$0.isFavorite })
    }

    func refreshResults(resetSelection: Bool = false) {
        var matches = store.matchingPrompts(for: query)
        if filter == .favorites {
            matches = matches.filter(\.isFavorite)
        }
        results = matches
        if resetSelection || !matches.contains(where: { $0.id == selectedID }) {
            selectedID = matches.first?.id
        }
    }

    // MARK: - Presentation

    /// Called synchronously before a surface appears, so nothing re-lays out
    /// while it animates in.
    func prepareForPresentation(window: NSWindow?) {
        activeWindow = window
        isActionPanelOpen = false
        commandHeld = false
        if screen == .library || screen == .guide || screen == .settings {
            screen = .library
            if !query.isEmpty { query = "" }
            refreshResults(resetSelection: true)
        }
        presentationID = UUID()
    }

    func didDismiss() {
        if screen == .editing {
            finishEditing()
        }
        if screen == .filling || screen == .guide || screen == .settings {
            fill = nil
            screen = .library
        }
        isActionPanelOpen = false
        commandHeld = false
        copiedID = nil
        activeWindow = nil
    }

    func dismiss() {
        onDismissRequest()
    }

    // MARK: - Library actions

    func select(_ prompt: Prompt, fromHover: Bool = false) {
        if fromHover && Date.now.timeIntervalSince(lastKeyboardNavigation) < 0.35 { return }
        guard selectedID != prompt.id else { return }
        selectedID = prompt.id
    }

    func moveSelection(by step: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex(where: { $0.id == selectedID }) ?? (step > 0 ? -1 : results.count)
        let next = min(max(current + step, 0), results.count - 1)
        lastKeyboardNavigation = .now
        selectedID = results[next].id
        keyboardRevealToken += 1
    }

    func copy(_ prompt: Prompt, fillingVariables: Bool = true) {
        let variables = prompt.variables(allowSingleBraces: Prompt.allowsSingleBraceVariables)
        if fillingVariables && !variables.isEmpty {
            beginFill(prompt, variables: variables)
        } else {
            performCopy(prompt.body, promptID: prompt.id)
        }
    }

    func copySlot(_ index: Int) {
        guard results.indices.contains(index) else { return }
        copy(results[index])
    }

    func toggleFavorite(_ prompt: Prompt) {
        perform { _ = try store.toggleFavorite(id: prompt.id) }
    }

    func moveFavorite(_ prompt: Prompt, by offset: Int) {
        perform { _ = try store.moveFavorite(id: prompt.id, by: offset) }
    }

    func duplicate(_ prompt: Prompt) {
        perform {
            let copy = try store.duplicate(id: prompt.id)
            refreshResults()
            selectedID = copy.id
            showToast("Duplicated “\(prompt.title)”", systemImage: "plus.square.on.square")
        }
    }

    func delete(_ prompt: Prompt) {
        let index = results.firstIndex(where: { $0.id == prompt.id })
        perform {
            try store.delete(id: prompt.id)
            refreshResults()
            if let index, !results.isEmpty {
                selectedID = results[min(index, results.count - 1)].id
            }
            showToast("Deleted “\(prompt.title)”", systemImage: "trash", offersUndo: true)
        }
    }

    func undoDelete() {
        perform {
            guard let restored = try store.undoDelete() else { return }
            refreshResults()
            selectedID = restored.id
            showToast("Restored “\(restored.title)”", systemImage: "arrow.uturn.backward")
        }
    }

    func insertStarterPrompts() {
        perform {
            let count = try store.insertSamplePrompts()
            refreshResults(resetSelection: true)
            if count > 0 {
                showToast("Added \(count) starter prompts", systemImage: "sparkles")
            }
        }
    }

    func clearQueryOrDismiss() {
        if !query.isEmpty {
            query = ""
        } else if filter != .all {
            filter = .all
        } else {
            dismiss()
        }
    }

    func showGuide() {
        isActionPanelOpen = false
        screen = .guide
    }

    func closeGuide() {
        screen = .library
        searchFocusRequest = UUID()
    }

    func openSettings() {
        isActionPanelOpen = false
        screen = .settings
    }

    func closeSettings() {
        hotKeyController.stopRecording()
        screen = .library
        searchFocusRequest = UUID()
    }

    /// Runs an app-modal dialog (save, open) without the panel hiding itself
    /// when the dialog takes focus, then gives the panel focus back.
    func runModal(_ body: () -> Void) {
        isRunningModal = true
        NSApp.activate()
        body()
        isRunningModal = false
        activeWindow?.makeKey()
    }

    private func performCopy(_ text: String, promptID: UUID) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            errorMessage = "Prompty couldn’t write to the clipboard."
            return
        }
        _ = try? store.markUsed(id: promptID)
        copiedID = promptID
        onCopied()
        // Let the "Copied" state register before the surface animates away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.onDismissRequest()
        }
    }

    // MARK: - Template fill

    private func beginFill(_ prompt: Prompt, variables: [PromptVariable]) {
        let memory = UserDefaults.standard.dictionary(forKey: Self.variableMemoryKey) as? [String: String] ?? [:]
        var values: [String: String] = [:]
        for variable in variables {
            switch variable.name.lowercased() {
            case "clipboard":
                values[variable.name] = NSPasteboard.general.string(forType: .string) ?? ""
            case "date":
                values[variable.name] = Date.now.formatted(date: .long, time: .omitted)
            default:
                values[variable.name] = memory[variable.name] ?? variable.defaultValue ?? ""
            }
        }
        isActionPanelOpen = false
        fill = FillSession(prompt: prompt, variables: variables, values: values)
        screen = .filling
    }

    func completeFill() {
        guard let fill else { return }
        var memory = UserDefaults.standard.dictionary(forKey: Self.variableMemoryKey) as? [String: String] ?? [:]
        for variable in fill.variables where !["clipboard", "date"].contains(variable.name.lowercased()) {
            let value = fill.values[variable.name] ?? ""
            if value.isEmpty || value == variable.defaultValue {
                memory.removeValue(forKey: variable.name)
            } else {
                memory[variable.name] = value
            }
        }
        UserDefaults.standard.set(memory, forKey: Self.variableMemoryKey)

        let text = fill.prompt.interpolatedBody(with: fill.values)
        performCopy(text, promptID: fill.prompt.id)
    }

    func cancelFill() {
        fill = nil
        screen = .library
        searchFocusRequest = UUID()
    }

    // MARK: - Editing

    /// Starts a new prompt, optionally titled from the search that found nothing.
    func beginAdding(title: String = "") {
        guard !store.isEditingBlocked else { return }
        pendingSave?.cancel()
        isActionPanelOpen = false
        errorMessage = nil
        editor = EditorSession(title: title.trimmingCharacters(in: .whitespaces), body: "")
        screen = .editing
    }

    func beginEditing(_ prompt: Prompt) {
        pendingSave?.cancel()
        isActionPanelOpen = false
        errorMessage = nil
        editor = EditorSession(promptID: prompt.id, snapshot: prompt, title: prompt.title, body: prompt.body)
        screen = .editing
    }

    func editorDidChange() {
        pendingSave?.cancel()
        guard editor?.hasContent == true else { return }
        pendingSave = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistDraft()
        }
    }

    /// Saves and closes the editor. Drafts without a title take one from the
    /// first line of the body; drafts without a body are dropped.
    func finishEditing() {
        pendingSave?.cancel()
        persistDraft()
        let savedID = editor?.promptID
        closeEditor()
        if let savedID {
            refreshResults()
            selectedID = savedID
        }
    }

    /// Discards the session: a prompt created during it is removed, and an
    /// existing prompt is put back exactly as it was.
    func cancelEditing() {
        pendingSave?.cancel()
        if let session = editor {
            if session.createdDuringSession, let id = session.promptID {
                try? store.delete(id: id, recordUndo: false)
            } else if let snapshot = session.snapshot {
                try? store.restore(snapshot)
            }
        }
        closeEditor()
        refreshResults()
    }

    func deleteEditingPrompt() {
        pendingSave?.cancel()
        guard let session = editor, let id = session.promptID,
              let prompt = store.prompts.first(where: { $0.id == id }) else {
            cancelEditing()
            return
        }
        closeEditor()
        delete(prompt)
    }

    private func closeEditor() {
        editor = nil
        errorMessage = nil
        screen = .library
        searchFocusRequest = UUID()
    }

    private func persistDraft() {
        guard let session = editor, session.hasContent else { return }
        var title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = Prompt.derivedTitle(from: session.body)
        }
        do {
            if let id = session.promptID {
                let isFavorite = store.prompts.first(where: { $0.id == id })?.isFavorite ?? false
                _ = try store.update(id: id, title: title, body: session.body, isFavorite: isFavorite)
            } else {
                let prompt = try store.create(title: title, body: session.body)
                if var current = editor {
                    current.promptID = prompt.id
                    current.createdDuringSession = true
                    editor = current
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Variable names already used across the library, for quick insertion.
    var knownVariableNames: [String] {
        var counts: [String: Int] = [:]
        for prompt in store.prompts {
            for variable in prompt.variables(allowSingleBraces: false) {
                counts[variable.name, default: 0] += 1
            }
        }
        let builtIns = ["clipboard", "date"]
        let used = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
            .filter { !builtIns.contains($0) }
        return Array(used.prefix(6)) + builtIns
    }

    // MARK: - Action panel

    func actions(for prompt: Prompt) -> [PromptAction] {
        let isTemplate = !prompt.placeholders.isEmpty
        var actions: [PromptAction] = [
            PromptAction(id: "copy", title: isTemplate ? "Fill & Copy" : "Copy", systemImage: "doc.on.doc", keys: ["↵"]) { [weak self] in
                self?.copy(prompt)
            }
        ]
        if isTemplate {
            actions.append(PromptAction(id: "copy-raw", title: "Copy Without Filling", systemImage: "curlybraces", keys: ["⇧", "↵"]) { [weak self] in
                self?.copy(prompt, fillingVariables: false)
            })
        }
        actions += [
            PromptAction(id: "edit", title: "Edit", systemImage: "pencil", keys: ["⌘", "E"]) { [weak self] in
                self?.beginEditing(prompt)
            },
            PromptAction(id: "duplicate", title: "Duplicate", systemImage: "plus.square.on.square", keys: ["⌘", "J"]) { [weak self] in
                self?.duplicate(prompt)
            },
            PromptAction(
                id: "favorite",
                title: prompt.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                systemImage: prompt.isFavorite ? "star.slash" : "star",
                keys: ["⌘", "D"]
            ) { [weak self] in
                self?.toggleFavorite(prompt)
            }
        ]
        if prompt.isFavorite {
            actions += [
                PromptAction(id: "move-up", title: "Move Up", systemImage: "arrow.up", keys: ["⌥", "⌘", "↑"]) { [weak self] in
                    self?.moveFavorite(prompt, by: -1)
                },
                PromptAction(id: "move-down", title: "Move Down", systemImage: "arrow.down", keys: ["⌥", "⌘", "↓"]) { [weak self] in
                    self?.moveFavorite(prompt, by: 1)
                }
            ]
        }
        actions.append(PromptAction(id: "delete", title: "Delete", systemImage: "trash", keys: ["⌘", "⌫"], isDestructive: true) { [weak self] in
            self?.delete(prompt)
        })
        return actions
    }

    var currentActions: [PromptAction] {
        guard let prompt = selectedPrompt else { return [] }
        return actions(for: prompt)
    }

    func toggleActionPanel() {
        guard selectedPrompt != nil else { return }
        actionSelection = 0
        isActionPanelOpen.toggle()
    }

    func runAction(_ action: PromptAction) {
        isActionPanelOpen = false
        action.perform()
    }

    // MARK: - Toast

    func showToast(_ message: String, systemImage: String, offersUndo: Bool = false) {
        toastTask?.cancel()
        toast = ToastState(message: message, systemImage: systemImage, offersUndo: offersUndo)
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(offersUndo ? 4 : 2.2))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func undoFromToast() {
        toastTask?.cancel()
        toast = nil
        undoDelete()
    }

    // MARK: - Keyboard

    func updateModifiers(_ flags: NSEvent.ModifierFlags) {
        let held = flags.intersection(.deviceIndependentFlagsMask) == .command
        if held != commandHeld { commandHeld = held }
    }

    /// Central keyboard routing for both surfaces. Runs before the text fields
    /// and the menu bar see the event, so shortcuts behave the same no matter
    /// which control has focus. Returns true when the event was handled.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let firstResponder = event.window?.firstResponder as? NSTextView

        // Let input methods finish composing before treating Return or Esc as commands.
        if firstResponder?.hasMarkedText() == true { return false }
        // The shortcut recorder needs every key, Esc included.
        if hotKeyController.isRecording { return false }

        if flags == .command, key == "q" {
            NSApp.terminate(nil)
            return true
        }

        let handled: Bool
        switch screen {
        case .library: handled = handleLibraryKey(event, flags: flags, key: key)
        case .editing: handled = handleEditorKey(event, flags: flags, key: key)
        case .filling: handled = handleFillKey(event, flags: flags)
        case .guide: handled = handleGuideKey(event, flags: flags, key: key)
        case .settings: handled = handleSettingsKey(event, flags: flags, key: key)
        }
        if handled { return true }

        return performStandardEditCommand(flags: flags, key: key, responder: firstResponder)
    }

    private func handleLibraryKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, key: String) -> Bool {
        if isActionPanelOpen {
            let actions = currentActions
            switch event.keyCode {
            case KeyCode.escape:
                isActionPanelOpen = false
            case KeyCode.upArrow:
                actionSelection = max(actionSelection - 1, 0)
            case KeyCode.downArrow:
                actionSelection = min(actionSelection + 1, actions.count - 1)
            case KeyCode.returnKey, KeyCode.keypadEnter:
                if actions.indices.contains(actionSelection) { runAction(actions[actionSelection]) }
            default:
                if flags == .command, key == "k" {
                    isActionPanelOpen = false
                } else {
                    return false
                }
            }
            return true
        }

        switch (event.keyCode, flags) {
        case (KeyCode.escape, []):
            clearQueryOrDismiss()
        case (KeyCode.returnKey, []), (KeyCode.keypadEnter, []):
            if let prompt = selectedPrompt { copy(prompt) }
        case (KeyCode.returnKey, .shift), (KeyCode.keypadEnter, .shift):
            if let prompt = selectedPrompt { copy(prompt, fillingVariables: false) }
        case (KeyCode.downArrow, []):
            moveSelection(by: 1)
        case (KeyCode.upArrow, []):
            moveSelection(by: -1)
        case (KeyCode.upArrow, [.command, .option]):
            if let prompt = selectedPrompt { moveFavorite(prompt, by: -1) }
        case (KeyCode.downArrow, [.command, .option]):
            if let prompt = selectedPrompt { moveFavorite(prompt, by: 1) }
        case (KeyCode.delete, .command):
            if let prompt = selectedPrompt { delete(prompt) }
        default:
            guard flags == .command else { return false }
            if let digit = Int(key), (1...9).contains(digit) {
                copySlot(digit - 1)
                return true
            }
            switch key {
            case "k": toggleActionPanel()
            case "n": beginAdding()
            case "e": if let prompt = selectedPrompt { beginEditing(prompt) }
            case "j": if let prompt = selectedPrompt { duplicate(prompt) }
            case "d": if let prompt = selectedPrompt { toggleFavorite(prompt) }
            case "/", "?": showGuide()
            case ",": openSettings()
            case "z":
                // Restores the last deletion while its toast is up; otherwise
                // ⌘Z stays ordinary text undo in the search field.
                guard toast?.offersUndo == true else { return false }
                undoFromToast()
            default: return false
            }
        }
        return true
    }

    private func handleEditorKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, key: String) -> Bool {
        if event.keyCode == KeyCode.escape && flags.isEmpty {
            cancelEditing()
            return true
        }
        if flags == .command && (event.keyCode == KeyCode.returnKey || key == "s") {
            if editor?.hasContent == true { finishEditing() } else { NSSound.beep() }
            return true
        }
        return false
    }

    private func handleFillKey(_ event: NSEvent, flags: NSEvent.ModifierFlags) -> Bool {
        if event.keyCode == KeyCode.escape && flags.isEmpty {
            cancelFill()
            return true
        }
        if flags == .command && (event.keyCode == KeyCode.returnKey || event.keyCode == KeyCode.keypadEnter) {
            completeFill()
            return true
        }
        return false
    }

    private func handleGuideKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, key: String) -> Bool {
        if (event.keyCode == KeyCode.escape && flags.isEmpty) || (flags == .command && (key == "/" || key == "?")) {
            closeGuide()
            return true
        }
        return false
    }

    private func handleSettingsKey(_ event: NSEvent, flags: NSEvent.ModifierFlags, key: String) -> Bool {
        switch (event.keyCode, flags) {
        case (KeyCode.escape, []):
            closeSettings()
        case (KeyCode.upArrow, []), (KeyCode.downArrow, []):
            let panes = SettingsPane.allCases
            let index = panes.firstIndex(of: settingsPane) ?? 0
            let next = event.keyCode == KeyCode.upArrow ? max(index - 1, 0) : min(index + 1, panes.count - 1)
            settingsPane = panes[next]
        default:
            guard flags == .command, key == "," || key == "[" else { return false }
            closeSettings()
        }
        return true
    }

    /// Cut, copy, paste, select-all and undo for text views, so editing works in
    /// the non-activating panel even when the menu bar does not route them.
    private func performStandardEditCommand(flags: NSEvent.ModifierFlags, key: String, responder: NSTextView?) -> Bool {
        guard let responder, flags == .command || flags == [.command, .shift] else { return false }
        let selector: Selector
        switch (key, flags) {
        case ("x", .command): selector = #selector(NSText.cut(_:))
        case ("c", .command): selector = #selector(NSText.copy(_:))
        case ("v", .command): selector = #selector(NSText.paste(_:))
        case ("a", .command): selector = #selector(NSText.selectAll(_:))
        case ("z", .command):
            responder.undoManager?.undo()
            return true
        case ("z", [.command, .shift]):
            responder.undoManager?.redo()
            return true
        default:
            return false
        }
        return NSApp.sendAction(selector, to: responder, from: nil)
    }

    // MARK: - Helpers

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
            errorMessage = nil
            refreshResults()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
