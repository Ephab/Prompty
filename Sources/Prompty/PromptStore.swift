import Foundation
import Observation

enum PromptStoreError: LocalizedError, Equatable {
    case corruptFile(URL)
    case invalidPrompt
    case promptNotFound(UUID)
    case writeFailed(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .corruptFile:
            "Prompty could not read its prompt library. The existing file was left untouched."
        case .invalidPrompt:
            "A prompt needs a non-empty title and body."
        case .promptNotFound:
            "That prompt no longer exists."
        case let .writeFailed(message):
            "Prompty could not save your prompt library: \(message)"
        case let .importFailed(message):
            "Prompty could not import prompt library: \(message)"
        }
    }
}

@Observable
@MainActor
final class PromptStore {
    private(set) var prompts: [Prompt] = []
    private(set) var storageError: PromptStoreError?
    private(set) var isEditingBlocked = false
    private(set) var deletedPromptsStack: [Prompt] = []

    let storageURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var saveTask: Task<Void, Never>?

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser

        return applicationSupport
            .appendingPathComponent("Prompty", isDirectory: true)
            .appendingPathComponent("prompts.json", isDirectory: false)
    }

    var orderedPrompts: [Prompt] {
        sorted(prompts)
    }

    func matchingPrompts(for query: String) -> [Prompt] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return orderedPrompts }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return orderedPrompts }

        let filtered = prompts.filter { prompt in
            tokens.allSatisfy { token in
                contains(prompt.title, query: token) || contains(prompt.body, query: token)
            }
        }

        return sorted(filtered, tokens: tokens)
    }

    @discardableResult
    func create(title: String, body: String, isFavorite: Bool = false) throws -> Prompt {
        try ensureEditingAllowed()
        try validate(title: title, body: body)

        let now = Date.now
        let prompt = Prompt(
            title: title,
            body: body,
            isFavorite: isFavorite,
            createdAt: now,
            updatedAt: now,
            favoriteOrder: isFavorite ? nextFavoriteOrder() : nil
        )
        prompts.append(prompt)
        scheduleSave()
        return prompt
    }

    @discardableResult
    func update(
        id: UUID,
        title: String,
        body: String,
        isFavorite: Bool
    ) throws -> Prompt {
        try ensureEditingAllowed()
        try validate(title: title, body: body)

        guard let index = prompts.firstIndex(where: { $0.id == id }) else {
            throw PromptStoreError.promptNotFound(id)
        }

        var prompt = prompts[index]
        if prompt.isFavorite != isFavorite {
            prompt.favoriteOrder = isFavorite ? nextFavoriteOrder() : nil
        }
        prompt.title = title
        prompt.body = body
        prompt.isFavorite = isFavorite
        prompt.updatedAt = .now
        prompts[index] = prompt
        scheduleSave()
        return prompt
    }

    /// Removes a prompt. Pass `recordUndo: false` when discarding something the
    /// user never meant to keep, such as a cancelled new draft.
    func delete(id: UUID, recordUndo: Bool = true) throws {
        try ensureEditingAllowed()
        guard let index = prompts.firstIndex(where: { $0.id == id }) else {
            throw PromptStoreError.promptNotFound(id)
        }

        let removed = prompts.remove(at: index)
        if recordUndo {
            deletedPromptsStack.append(removed)
        }
        scheduleSave()
    }

    /// Puts a prompt back exactly as given, timestamps included. Used to revert
    /// an edit session without making the prompt look recently modified.
    func restore(_ prompt: Prompt) throws {
        try ensureEditingAllowed()
        if let index = prompts.firstIndex(where: { $0.id == prompt.id }) {
            guard prompts[index] != prompt else { return }
            prompts[index] = prompt
        } else {
            prompts.append(prompt)
        }
        scheduleSave()
    }

    @discardableResult
    func undoDelete() throws -> Prompt? {
        try ensureEditingAllowed()
        guard let restored = deletedPromptsStack.popLast() else { return nil }

        if let existingIndex = prompts.firstIndex(where: { $0.id == restored.id }) {
            prompts[existingIndex] = restored
        } else {
            prompts.append(restored)
        }
        scheduleSave()
        return restored
    }

    @discardableResult
    func duplicate(id: UUID) throws -> Prompt {
        try ensureEditingAllowed()
        guard let original = prompts.first(where: { $0.id == id }) else {
            throw PromptStoreError.promptNotFound(id)
        }

        let now = Date.now
        let copy = Prompt(
            title: "\(original.title) (Copy)",
            body: original.body,
            isFavorite: original.isFavorite,
            createdAt: now,
            updatedAt: now,
            favoriteOrder: original.isFavorite ? nextFavoriteOrder() : nil
        )
        prompts.append(copy)
        scheduleSave()
        return copy
    }

    func exportJSON() throws -> Data {
        try encoder.encode(prompts)
    }

    func exportMarkdown() -> String {
        prompts.map { prompt in
            "# \(prompt.title)\n\n\(prompt.body)"
        }.joined(separator: "\n\n---\n\n")
    }

    @discardableResult
    func importJSON(from data: Data) throws -> Int {
        try ensureEditingAllowed()
        let decoded: [Prompt]
        do {
            decoded = try decoder.decode([Prompt].self, from: data)
        } catch {
            throw PromptStoreError.importFailed(error.localizedDescription)
        }

        var importedCount = 0
        var existingIDs = Set(prompts.map(\.id))

        for item in decoded {
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            if existingIDs.contains(item.id) {
                let uniquePrompt = Prompt(
                    id: UUID(),
                    title: "\(item.title) (Imported)",
                    body: item.body,
                    isFavorite: item.isFavorite,
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt,
                    lastUsedAt: item.lastUsedAt
                )
                prompts.append(uniquePrompt)
                existingIDs.insert(uniquePrompt.id)
            } else {
                prompts.append(item)
                existingIDs.insert(item.id)
            }
            importedCount += 1
        }

        if importedCount > 0 {
            scheduleSave()
        }
        return importedCount
    }

    @discardableResult
    func insertSamplePrompts() throws -> Int {
        try ensureEditingAllowed()
        var addedCount = 0
        for var sample in Prompt.samplePrompts {
            if !prompts.contains(where: { $0.title == sample.title }) {
                if sample.isFavorite {
                    sample.favoriteOrder = nextFavoriteOrder()
                }
                prompts.append(sample)
                addedCount += 1
            }
        }
        if addedCount > 0 {
            scheduleSave()
        }
        return addedCount
    }

    @discardableResult
    func toggleFavorite(id: UUID) throws -> Prompt {
        try ensureEditingAllowed()
        guard let index = prompts.firstIndex(where: { $0.id == id }) else {
            throw PromptStoreError.promptNotFound(id)
        }

        var prompt = prompts[index]
        prompt.isFavorite.toggle()
        prompt.favoriteOrder = prompt.isFavorite ? nextFavoriteOrder() : nil
        prompt.updatedAt = .now
        prompts[index] = prompt
        scheduleSave()
        return prompt
    }

    /// Moves a favorite up (negative offset) or down (positive offset) in the
    /// favorites order. Returns false when the prompt is not a favorite or is
    /// already at that edge.
    @discardableResult
    func moveFavorite(id: UUID, by offset: Int) throws -> Bool {
        try ensureEditingAllowed()
        var favorites = prompts.filter(\.isFavorite).sorted(by: Self.favoriteOrdering)
        guard let from = favorites.firstIndex(where: { $0.id == id }) else { return false }
        let to = from + offset
        guard favorites.indices.contains(to) else { return false }

        favorites.swapAt(from, to)
        for (order, favorite) in favorites.enumerated() {
            if let index = prompts.firstIndex(where: { $0.id == favorite.id }) {
                prompts[index].favoriteOrder = order
            }
        }
        scheduleSave()
        return true
    }

    @discardableResult
    func markUsed(id: UUID, at date: Date = .now) throws -> Prompt {
        try ensureEditingAllowed()
        guard let index = prompts.firstIndex(where: { $0.id == id }) else {
            throw PromptStoreError.promptNotFound(id)
        }

        var prompt = prompts[index]
        prompt.lastUsedAt = date
        prompts[index] = prompt
        scheduleSave()
        return prompt
    }

    func saveImmediately() throws {
        try ensureEditingAllowed()
        saveTask?.cancel()
        saveTask = nil
        try save()
    }

    private func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            prompts = try decoder.decode([Prompt].self, from: data)
            storageError = nil
            isEditingBlocked = false
        } catch {
            storageError = .corruptFile(storageURL)
            isEditingBlocked = true
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard let self else { return }
            do {
                try self.save()
            } catch {
                // The in-memory change remains available; storageError tells the UI
                // that it needs to surface the failure to the user.
            }
        }
    }

    private func save() throws {
        do {
            let directory = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try encoder.encode(prompts)
            try data.write(to: storageURL, options: .atomic)
            storageError = nil
        } catch {
            let message = (error as NSError).localizedDescription
            let storeError = PromptStoreError.writeFailed(message)
            storageError = storeError
            throw storeError
        }
    }

    private func nextFavoriteOrder() -> Int {
        (prompts.compactMap(\.favoriteOrder).max() ?? -1) + 1
    }

    private static func favoriteOrdering(_ lhs: Prompt, _ rhs: Prompt) -> Bool {
        switch (lhs.favoriteOrder, rhs.favoriteOrder) {
        case let (l?, r?) where l != r:
            return l < r
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func ensureEditingAllowed() throws {
        if isEditingBlocked, let storageError {
            throw storageError
        }
    }

    private func validate(title: String, body: String) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptStoreError.invalidPrompt
        }
    }

    private func contains(_ value: String, query: String) -> Bool {
        value.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        ) != nil
    }

    private func sorted(_ prompts: [Prompt], tokens: [String] = []) -> [Prompt] {
        prompts.sorted { lhs, rhs in
            if !tokens.isEmpty {
                let lhsTitleMatch = tokens.allSatisfy { contains(lhs.title, query: $0) }
                let rhsTitleMatch = tokens.allSatisfy { contains(rhs.title, query: $0) }
                if lhsTitleMatch != rhsTitleMatch {
                    return lhsTitleMatch
                }
            }

            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }

            // Favorites keep a stable, user-controlled order so ⌘1–⌘9 stay put;
            // only the rest of the library is ordered by recency.
            if lhs.isFavorite {
                return Self.favoriteOrdering(lhs, rhs)
            }

            let lhsUsed = lhs.lastUsedAt ?? .distantPast
            let rhsUsed = rhs.lastUsedAt ?? .distantPast
            if lhsUsed != rhsUsed {
                return lhsUsed > rhsUsed
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
