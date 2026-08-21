import SwiftUI

struct EditorView: View {
    @Binding var title: String
    @Binding var bodyText: String

    let isNew: Bool
    let onChanged: (String, String) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?
    let storageError: String?

    @State private var showingDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case body
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .help("Back to prompts")
                .accessibilityLabel("Back to prompts")

                Text(isNew ? "New prompt" : "Edit prompt")
                    .font(.system(.title3, design: .rounded).weight(.semibold))

                Spacer(minLength: 0)

                if let onDelete {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .help("Delete prompt")
                    .accessibilityLabel("Delete prompt")
                    .confirmationDialog(
                        "Delete this prompt?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive, action: onDelete)
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This cannot be undone.")
                    }
                }

                Button("Done", action: onCancel)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Title")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("A name you will recognize", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .title)
                            .onChange(of: title) { _, newValue in
                                onChanged(newValue, bodyText)
                            }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Prompt")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $bodyText)
                                .font(.system(size: 13))
                                .focused($focusedField, equals: .body)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 5)
                                .frame(minHeight: 250)
                                .background(.quaternary.opacity(0.36), in: RoundedRectangle(cornerRadius: 9))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(.separator.opacity(0.65), lineWidth: 1)
                                }
                                .onChange(of: bodyText) { _, newValue in
                                    onChanged(title, newValue)
                                }

                            if bodyText.isEmpty {
                                Text("Write or paste the reusable prompt here")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 12)
                                    .padding(.top, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    if !isValid {
                        Label("Title and prompt are both required", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let storageError {
                        Label(storageError, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(18)
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
        .accessibilityElement(children: .contain)
    }
}
