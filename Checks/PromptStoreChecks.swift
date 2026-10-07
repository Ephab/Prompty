import Foundation

@main
@MainActor
struct PromptStoreChecks {
    static func main() throws {
        try persistenceAndMutations()
        try corruptionProtection()
        try searchAndOrdering()
        try validation()
        try undoAndDuplicate()
        try exportAndImport()
        try templatePlaceholders()
        try samplePromptsSeeding()
        try restoreAndDraftDiscard()
        try stableFavoriteOrdering()
        try legacyDecoding()
        try templateDefaultsAndSpacing()
        print("PromptStore checks passed")
    }

    private static func persistenceAndMutations() throws {
        let url = temporaryPromptURL()
        let store = PromptStore(storageURL: url)
        precondition(store.prompts.isEmpty)

        let prompt = try store.create(title: "Summarize", body: "Summarize this text.")
        let updated = try store.update(
            id: prompt.id,
            title: "Updated",
            body: "New body",
            isFavorite: true
        )
        let usedAt = Date(timeIntervalSince1970: 1_900_000_000)
        _ = try store.markUsed(id: updated.id, at: usedAt)
        try store.saveImmediately()

        let reloaded = PromptStore(storageURL: url)
        precondition(reloaded.prompts.first?.title == "Updated")
        precondition(reloaded.prompts.first?.isFavorite == true)
        precondition(reloaded.prompts.first?.lastUsedAt == usedAt)

        try reloaded.delete(id: prompt.id)
        try reloaded.saveImmediately()
        precondition(PromptStore(storageURL: url).prompts.isEmpty)
    }

    private static func corruptionProtection() throws {
        let url = temporaryPromptURL()
        let original = Data("not json".utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try original.write(to: url)

        let store = PromptStore(storageURL: url)
        precondition(store.isEditingBlocked)
        let preserved = try Data(contentsOf: url)
        precondition(preserved == original)
        do {
            _ = try store.create(title: "New", body: "Body")
            preconditionFailure("A corrupt library must block edits")
        } catch PromptStoreError.corruptFile {
            // Expected: the original file remains untouched.
        }
        do {
            try store.saveImmediately()
            preconditionFailure("An explicit save must not overwrite a corrupt library")
        } catch PromptStoreError.corruptFile {
            let stillPreserved = try Data(contentsOf: url)
            precondition(stillPreserved == original)
        }
    }

    private static func searchAndOrdering() throws {
        let url = temporaryPromptURL()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let prompts = [
            Prompt(title: "Café notes", body: "One", isFavorite: true,
                   createdAt: now.addingTimeInterval(-300), updatedAt: now.addingTimeInterval(-200)),
            Prompt(title: "Recent", body: "Prepare a cafe menu", createdAt: now.addingTimeInterval(-200),
                   updatedAt: now.addingTimeInterval(-100), lastUsedAt: now.addingTimeInterval(-10)),
            Prompt(title: "Recent favorite", body: "Three", isFavorite: true,
                   createdAt: now.addingTimeInterval(-100), updatedAt: now.addingTimeInterval(-50),
                   lastUsedAt: now.addingTimeInterval(-20))
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(prompts).write(to: url)

        let store = PromptStore(storageURL: url)
        precondition(store.matchingPrompts(for: "CAFE").count == 2)
        precondition(store.matchingPrompts(for: "prepare menu").count == 1)
        precondition(store.matchingPrompts(for: "prepare menu").first?.title == "Recent")
        // Favorites without an explicit order fall back to creation order, then the rest by recency.
        precondition(store.orderedPrompts.map(\.title) == ["Café notes", "Recent favorite", "Recent"])
    }

    private static func validation() throws {
        let store = PromptStore(storageURL: temporaryPromptURL())
        do {
            _ = try store.create(title: " ", body: "Text")
            preconditionFailure("Whitespace-only titles must be rejected")
        } catch PromptStoreError.invalidPrompt {
            precondition(store.prompts.isEmpty)
        }
    }

    private static func undoAndDuplicate() throws {
        let store = PromptStore(storageURL: temporaryPromptURL())
        let prompt = try store.create(title: "Original", body: "Body text", isFavorite: true)

        let duplicate = try store.duplicate(id: prompt.id)
        precondition(duplicate.title == "Original (Copy)")
        precondition(duplicate.body == "Body text")
        precondition(duplicate.isFavorite == true)
        precondition(store.prompts.count == 2)

        try store.delete(id: duplicate.id)
        precondition(store.prompts.count == 1)

        let restored = try store.undoDelete()
        precondition(restored?.id == duplicate.id)
        precondition(restored?.title == "Original (Copy)")
        precondition(store.prompts.count == 2)
    }

    private static func exportAndImport() throws {
        let store1 = PromptStore(storageURL: temporaryPromptURL())
        _ = try store1.create(title: "First", body: "First body", isFavorite: true)
        _ = try store1.create(title: "Second", body: "Second body")

        let jsonData = try store1.exportJSON()
        precondition(!jsonData.isEmpty)

        let markdown = store1.exportMarkdown()
        precondition(markdown.contains("# First"))
        precondition(markdown.contains("Second body"))

        let store2 = PromptStore(storageURL: temporaryPromptURL())
        let importedCount = try store2.importJSON(from: jsonData)
        precondition(importedCount == 2)
        precondition(store2.prompts.count == 2)
        precondition(store2.prompts.contains(where: { $0.title == "First" && $0.isFavorite }))
    }

    private static func templatePlaceholders() throws {
        let prompt = Prompt(
            title: "Test",
            body: "Hello {{name}}, please review {file} for {{language}} and {file} again."
        )
        precondition(prompt.variables(allowSingleBraces: true).map(\.name) == ["name", "file", "language"])
        precondition(prompt.variables(allowSingleBraces: false).map(\.name) == ["name", "language"])

        let filled = prompt.interpolatedBody(with: [
            "name": "Alice",
            "file": "Main.swift",
            "language": "Swift"
        ], allowSingleBraces: true)
        precondition(filled == "Hello Alice, please review Main.swift for Swift and Main.swift again.")
    }

    private static func samplePromptsSeeding() throws {
        let store = PromptStore(storageURL: temporaryPromptURL())
        precondition(store.prompts.isEmpty)

        let count = try store.insertSamplePrompts()
        precondition(count == Prompt.samplePrompts.count)
        precondition(store.prompts.count == Prompt.samplePrompts.count)

        // Second call should not duplicate
        let secondCount = try store.insertSamplePrompts()
        precondition(secondCount == 0)
        precondition(store.prompts.count == Prompt.samplePrompts.count)
    }

    private static func restoreAndDraftDiscard() throws {
        let store = PromptStore(storageURL: temporaryPromptURL())
        let original = try store.create(title: "Keep", body: "Original")
        _ = try store.update(id: original.id, title: "Keep", body: "Edited", isFavorite: false)
        try store.restore(original)
        precondition(store.prompts.first == original)
        precondition(store.prompts.first?.updatedAt == original.updatedAt)

        let draft = try store.create(title: "Draft", body: "Throwaway")
        try store.delete(id: draft.id, recordUndo: false)
        precondition(store.deletedPromptsStack.isEmpty)
        let undone = try store.undoDelete()
        precondition(undone == nil)

        precondition(Prompt.derivedTitle(from: "\n  First line\nSecond") == "First line")
        precondition(Prompt.derivedTitle(from: String(repeating: "a", count: 80)).count == 60)
    }

    private static func stableFavoriteOrdering() throws {
        let store = PromptStore(storageURL: temporaryPromptURL())
        let first = try store.create(title: "First", body: "1", isFavorite: true)
        let second = try store.create(title: "Second", body: "2", isFavorite: true)
        let other = try store.create(title: "Other", body: "3")

        _ = try store.markUsed(id: second.id)
        _ = try store.markUsed(id: other.id)
        precondition(store.orderedPrompts.map(\.id) == [first.id, second.id, other.id])

        let moved = try store.moveFavorite(id: second.id, by: -1)
        precondition(moved)
        precondition(store.orderedPrompts.map(\.id) == [second.id, first.id, other.id])
        let movedPastTop = try store.moveFavorite(id: second.id, by: -1)
        precondition(!movedPastTop)
        let movedNonFavorite = try store.moveFavorite(id: other.id, by: 1)
        precondition(!movedNonFavorite)

        _ = try store.toggleFavorite(id: other.id)
        precondition(store.orderedPrompts.last?.id == other.id)
        _ = try store.toggleFavorite(id: first.id)
        precondition(store.prompts.first(where: { $0.id == first.id })?.favoriteOrder == nil)
    }

    private static func legacyDecoding() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","title":"Old","body":"Body","isFavorite":true,
          "createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}]
        """
        let store = PromptStore(storageURL: temporaryPromptURL())
        let imported = try store.importJSON(from: Data(legacy.utf8))
        precondition(imported == 1)
        precondition(store.prompts.first?.favoriteOrder == nil)
        precondition(store.prompts.first?.isFavorite == true)
    }

    private static func templateDefaultsAndSpacing() throws {
        let prompt = Prompt(
            title: "T",
            body: "Write about {{ topic }} in a {{tone: friendly }} tone. Code: if x {return} {{ topic }}"
        )
        let variables = prompt.variables(allowSingleBraces: false)
        precondition(variables.map(\.name) == ["topic", "tone"])
        precondition(variables[1].defaultValue == "friendly")

        let filled = prompt.interpolatedBody(with: ["topic": "Swift", "tone": ""], allowSingleBraces: false)
        precondition(filled == "Write about Swift in a friendly tone. Code: if x {return} Swift")

        let untouched = prompt.interpolatedBody(with: [:], allowSingleBraces: false)
        precondition(untouched.contains("{{ topic }}"))
        precondition(untouched.contains("in a friendly tone"))
        precondition(prompt.variableRanges(allowSingleBraces: false).count == 3)
    }

    private static func temporaryPromptURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptyChecks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("prompts.json")
    }
}

