import SwiftUI

struct PromptRow: View {
    let prompt: Prompt
    let slot: Int
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let viewModel: PromptyViewModel

    private var isCopied: Bool { viewModel.copiedID == prompt.id }
    private var variableCount: Int { prompt.placeholders.count }

    var body: some View {
        listRow
            .contentShape(RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous))
            .onTapGesture { viewModel.copy(prompt) }
            .onContinuousHover { phase in
                if case .active = phase {
                    viewModel.select(prompt, fromHover: true)
                }
            }
            .contextMenu {
                ForEach(viewModel.actions(for: prompt)) { action in
                    Button(role: action.isDestructive ? .destructive : nil, action: action.perform) {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    if action.id == "copy-raw" || (action.id == "copy" && variableCount == 0) || action.id == "move-down" {
                        Divider()
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(variableCount > 0 ? "Fills the template, then copies it" : "Copies the prompt")
            .accessibilityActions {
                ForEach(viewModel.actions(for: prompt).dropFirst()) { action in
                    Button(action.title, action: action.perform)
                }
            }
    }

    private var listRow: some View {
        HStack(spacing: 10) {
            glyph(size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(SearchHighlight.attributed(prompt.title, query: viewModel.query))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(SearchHighlight.attributed(SearchHighlight.excerpt(prompt.body, query: viewModel.query), query: viewModel.query))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background { selectionBackground }
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isCopied {
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Color.green.opacity(0.18))
        } else if isSelected {
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius, style: .continuous)
                .fill(Theme.selectionFill)
                .matchedGeometryEffect(id: "selection", in: selectionNamespace)
        }
    }

    @ViewBuilder
    private func glyph(size: CGFloat) -> some View {
        if prompt.isFavorite {
            GlyphTile(systemName: "star.fill", tint: Theme.favorite, size: size)
        } else if variableCount > 0 {
            GlyphTile(systemName: "curlybraces", tint: .accentColor, size: size)
        } else {
            GlyphTile(systemName: "text.alignleft", tint: .secondary, size: size)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isCopied {
            Label("Copied", systemImage: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
                .transition(.opacity)
        } else if viewModel.commandHeld && slot < 9 {
            Keycap("⌘\(slot + 1)")
                .transition(.opacity)
        } else if variableCount > 0 {
            Text("\(variableCount) var\(variableCount == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .frame(height: 17)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
    }
}

/// Query highlighting and match-centred excerpts for result rows.
enum SearchHighlight {
    static func tokens(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func attributed(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        for token in tokens(in: query) {
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let range = attributed[searchRange].range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[range].backgroundColor = Color.accentColor.opacity(0.22)
                attributed[range].foregroundColor = .primary
                attributed[range].inlinePresentationIntent = .stronglyEmphasized
                guard range.upperBound < attributed.endIndex else { break }
                searchRange = range.upperBound..<attributed.endIndex
            }
        }
        return attributed
    }

    /// The body on one line, starting near the first match when it would
    /// otherwise be cut off.
    static func excerpt(_ body: String, query: String) -> String {
        let flattened = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let firstMatch = tokens(in: query)
            .compactMap { flattened.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])?.lowerBound }
            .min()
        guard let firstMatch else { return flattened }

        let offset = flattened.distance(from: flattened.startIndex, to: firstMatch)
        guard offset > 40 else { return flattened }
        let start = flattened.index(flattened.startIndex, offsetBy: offset - 24)
        return "…" + flattened[start...].trimmingCharacters(in: .whitespaces)
    }
}
