import Foundation

@main
@MainActor
struct PromptStoreChecks {
    static func main() throws {
        try persistenceAndMutations()
        try corruptionProtection()
        try searchAndOrdering()
        try validation()
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
        precondition(store.orderedPrompts.map(\.title) == ["Recent favorite", "Café notes", "Recent"])
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

    private static func temporaryPromptURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptyChecks", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("prompts.json")
    }
}
