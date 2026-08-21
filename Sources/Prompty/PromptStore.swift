import Foundation
import Observation

enum PromptStoreError: LocalizedError, Equatable {
    case corruptFile(URL)
    case invalidPrompt
    case promptNotFound(UUID)
    case writeFailed(String)

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
        }
    }
}

@Observable
@MainActor
final class PromptStore {
    private(set) var prompts: [Prompt] = []
    private(set) var storageError: PromptStoreError?
    private(set) var isEditingBlocked = false

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
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return orderedPrompts }

        return sorted(prompts.filter { prompt in
            contains(prompt.title, query: query) || contains(prompt.body, query: query)
        })
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
            updatedAt: now
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
        prompt.title = title
        prompt.body = body
        prompt.isFavorite = isFavorite
        prompt.updatedAt = .now
        prompts[index] = prompt
        scheduleSave()
        return prompt
    }

    func delete(id: UUID) throws {
        try ensureEditingAllowed()
        guard let index = prompts.firstIndex(where: { $0.id == id }) else {
            throw PromptStoreError.promptNotFound(id)
        }

        prompts.remove(at: index)
        scheduleSave()
    }

    @discardableResult
    func toggleFavorite(id: UUID) throws -> Prompt {
        try ensureEditingAllowed()
        guard let index = prompts.firstIndex(where: { $0.id == id }) else {
            throw PromptStoreError.promptNotFound(id)
        }

        var prompt = prompts[index]
        prompt.isFavorite.toggle()
        prompt.updatedAt = .now
        prompts[index] = prompt
        scheduleSave()
        return prompt
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

    private func sorted(_ prompts: [Prompt]) -> [Prompt] {
        prompts.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
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
