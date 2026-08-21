import Foundation

enum PromptLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:
            "List"
        case .grid:
            "Grid"
        }
    }
}

struct Prompt: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        isFavorite: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastUsedAt = lastUsedAt
    }
}
