import AppKit
import SwiftUI

/// Lets SwiftUI insert text at the editor's cursor.
@MainActor
final class PromptTextEditorController {
    fileprivate weak var textView: NSTextView?

    /// Inserts `text` at the selection, optionally selecting a sub-range of it
    /// (for example the placeholder name inside `{{name}}`).
    func insert(_ text: String, selecting selection: NSRange? = nil) {
        guard let textView else { return }
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        if let selection {
            textView.setSelectedRange(NSRange(location: range.location + selection.location, length: selection.length))
        } else {
            textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        }
        textView.window?.makeFirstResponder(textView)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

/// A plain-text editor that tints `{{variables}}` as you type. Smart quotes
/// and dashes are off because prompts often contain code.
struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: PromptTextEditorController
    var fontSize: CGFloat = 13

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = Coordinator.baseAttributes(fontSize: fontSize)
        textView.string = text
        context.coordinator.fontSize = fontSize
        context.coordinator.highlight(textView)
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        controller.textView = textView
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var fontSize: CGFloat = 13

        init(text: Binding<String>) {
            self.text = text
        }

        static func baseAttributes(fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            return [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            highlight(textView)
            if text.wrappedValue != textView.string {
                text.wrappedValue = textView.string
            }
        }

        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(Self.baseAttributes(fontSize: fontSize), range: fullRange)
            for range in Prompt.variableNSRanges(in: storage.string) {
                storage.addAttributes([
                    .foregroundColor: NSColor.controlAccentColor,
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12),
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize - 0.5, weight: .medium)
                ], range: range)
            }
            storage.endEditing()
            textView.typingAttributes = Self.baseAttributes(fontSize: fontSize)
        }
    }
}
