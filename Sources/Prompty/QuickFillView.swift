import SwiftUI

/// Collects values for a template's variables, with a live preview of the
/// prompt that will be copied.
struct QuickFillView: View {
    @Bindable var viewModel: PromptyViewModel

    @FocusState private var focusedIndex: Int?

    var body: some View {
        if let fill = viewModel.fill {
            VStack(spacing: 0) {
                ScreenHeader(
                    title: "Fill Template",
                    subtitle: fill.prompt.title,
                    backHelp: "Back (Esc)",
                    onBack: viewModel.cancelFill
                ) {
                    Button(action: viewModel.completeFill) {
                        HStack(spacing: 6) {
                            Text("Copy")
                            Text("⌘↵")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .opacity(0.75)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Copy the filled prompt (⌘↵)")
                }
                Divider().opacity(0.7)

                HStack(spacing: 0) {
                    form(fill)
                        .frame(width: 320)
                    Divider().opacity(0.7)
                    preview(fill)
                }
            }
            .onAppear {
                DispatchQueue.main.async { focusedIndex = 0 }
            }
        }
    }

    private func form(_ fill: FillSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(fill.variables.enumerated()), id: \.element.name) { index, variable in
                    field(variable, index: index, isLast: index == fill.variables.count - 1)
                }
                Text("Return moves to the next field · ⌥Return adds a new line")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
        }
        .frame(maxHeight: .infinity)
    }

    private func field(_ variable: PromptVariable, index: Int, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(variable.name)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                if let badge = badge(for: variable) {
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            TextField(
                "Value for \(variable.name)",
                text: Binding(
                    get: { viewModel.fill?.values[variable.name] ?? "" },
                    set: { viewModel.fill?.values[variable.name] = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: Theme.fieldCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.fieldCornerRadius, style: .continuous)
                    .strokeBorder(focusedIndex == index ? Color.accentColor.opacity(0.55) : Theme.hairline.opacity(0.6),
                                  lineWidth: focusedIndex == index ? 1 : 0.5)
            }
            .focused($focusedIndex, equals: index)
            .onSubmit {
                if isLast {
                    viewModel.completeFill()
                } else {
                    focusedIndex = index + 1
                }
            }
        }
    }

    private func badge(for variable: PromptVariable) -> String? {
        switch variable.name.lowercased() {
        case "clipboard": return "from clipboard"
        case "date": return "today"
        default:
            if let defaultValue = variable.defaultValue, !defaultValue.isEmpty {
                return "default: \(defaultValue)"
            }
            return nil
        }
    }

    private func preview(_ fill: FillSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Preview")
                .padding(.horizontal, 8)
                .padding(.top, 6)
            ScrollView {
                Text(filledText(fill))
                    .font(.system(size: 12.5))
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Filled values are tinted so they are easy to proof-read; missing ones
    /// stay visible as their original tokens.
    private func filledText(_ fill: FillSession) -> AttributedString {
        var result = AttributedString()
        for segment in fill.prompt.segments() {
            switch segment {
            case let .text(text):
                result += AttributedString(text)
            case let .variable(variable, token):
                let value = fill.values[variable.name] ?? ""
                let shown = value.isEmpty ? (variable.defaultValue ?? "") : value
                if shown.isEmpty {
                    var missing = AttributedString(token)
                    missing.foregroundColor = .orange
                    missing.font = .system(size: 12, weight: .medium, design: .monospaced)
                    result += missing
                } else {
                    var filled = AttributedString(shown)
                    filled.backgroundColor = Color.accentColor.opacity(0.12)
                    filled.foregroundColor = .primary
                    result += filled
                }
            }
        }
        return result
    }
}
