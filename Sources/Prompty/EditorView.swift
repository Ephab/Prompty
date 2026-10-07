import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: PromptyViewModel

    @State private var textController = PromptTextEditorController()
    @FocusState private var titleFocused: Bool

    private var session: EditorSession? { viewModel.editor }
    private var isNew: Bool { session?.isNew ?? true }
    private var bodyText: String { session?.body ?? "" }
    private var titleText: String { session?.title ?? "" }

    private var titleBinding: Binding<String> {
        Binding(
            get: { viewModel.editor?.title ?? "" },
            set: { newValue in
                guard viewModel.editor?.title != newValue else { return }
                viewModel.editor?.title = newValue
                viewModel.editorDidChange()
            }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { viewModel.editor?.body ?? "" },
            set: { newValue in
                guard viewModel.editor?.body != newValue else { return }
                viewModel.editor?.body = newValue
                viewModel.editorDidChange()
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: isNew ? "New Prompt" : "Edit Prompt",
                subtitle: "Esc discards · ⌘↵ saves",
                backHelp: "Discard Changes (Esc)",
                onBack: viewModel.cancelEditing
            ) {
                HStack(spacing: 6) {
                    if !isNew {
                        IconButton(systemName: "trash", help: "Delete Prompt", size: 28, action: viewModel.deleteEditingPrompt)
                    }
                    Button("Done", action: viewModel.finishEditing)
                        .buttonStyle(.borderedProminent)
                        .disabled(session?.hasContent != true)
                        .help("Save and Close (⌘↵)")
                }
            }
            Divider().opacity(0.7)

            VStack(alignment: .leading, spacing: 0) {
                TextField("Untitled prompt", text: titleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .focused($titleFocused)
                    .onSubmit { textController.focus() }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .accessibilityLabel("Title")

                Group {
                    if titleText.trimmingCharacters(in: .whitespaces).isEmpty,
                       !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Will be saved as “\(Prompt.derivedTitle(from: bodyText))”")
                    } else {
                        Text(" ")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .padding(.top, 2)

                PromptTextEditor(text: bodyBinding, controller: textController)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if bodyText.isEmpty {
                            Text("Write or paste your prompt. Use {{name}} for anything you fill in each time.")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 23)
                                .padding(.top, 8)
                                .padding(.trailing, 18)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Prompt")

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                Divider().opacity(0.7)
                footer
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                if titleText.isEmpty {
                    titleFocused = true
                } else {
                    textController.focus()
                }
            }
        }
    }

    private var footer: some View {
        let detected = Prompt(title: titleText, body: bodyText).placeholders
        return HStack(spacing: 8) {
            Menu {
                Section("Insert Variable") {
                    ForEach(viewModel.knownVariableNames, id: \.self) { name in
                        Button("{{\(name)}}") { textController.insert("{{\(name)}}") }
                    }
                }
                Divider()
                Button("New Variable…") {
                    textController.insert("{{variable}}", selecting: NSRange(location: 2, length: 8))
                }
            } label: {
                Label("Variable", systemImage: "curlybraces")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Insert a {{variable}} at the cursor")

            if !detected.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(detected, id: \.self) { VariableChip(name: $0) }
                    }
                }
                .scrollIndicators(.never)
            }

            Spacer(minLength: 8)

            Text(Formatting.size(of: bodyText))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }
}
