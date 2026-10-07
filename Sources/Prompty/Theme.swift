import AppKit
import SwiftUI

enum Theme {
    /// The panel's content size. It never changes, so presenting and
    /// switching screens can't resize the window.
    static let panelSize = CGSize(width: 720, height: 460)
    static let panelCornerRadius: CGFloat = 22
    static let rowCornerRadius: CGFloat = 9
    static let fieldCornerRadius: CGFloat = 9
    /// Transparent room around the panel so its SwiftUI shadow is never clipped.
    static let panelShadowMargin: CGFloat = 48

    static let presentIn = Animation.spring(response: 0.26, dampingFraction: 0.88)
    static let presentOut = Animation.easeIn(duration: 0.12)
    static let screenChange = Animation.spring(response: 0.3, dampingFraction: 0.9)
    static let selection = Animation.snappy(duration: 0.16)

    static var selectionFill: Color { Color.accentColor.opacity(0.16) }
    static var hairline: Color { Color(nsColor: .separatorColor).opacity(0.6) }
    static var subtleFill: Color { Color.primary.opacity(0.05) }
    static var favorite: Color { Color(nsColor: .systemYellow) }
}

extension Theme {
    /// The app icon's panel and `>_` prompt as a template image, used in
    /// the menu bar and wherever the app shows its mark.
    static let logoMark: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()
            let card = NSBezierPath(roundedRect: NSRect(x: 1.75, y: 1.75, width: 16.5, height: 12.5), xRadius: 3.5, yRadius: 3.5)
            card.lineWidth = 1.5
            card.stroke()
            let chevron = NSBezierPath()
            chevron.lineWidth = 1.6
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.move(to: NSPoint(x: 5.5, y: 10.5))
            chevron.line(to: NSPoint(x: 8.5, y: 8))
            chevron.line(to: NSPoint(x: 5.5, y: 5.5))
            chevron.stroke()
            NSBezierPath(roundedRect: NSRect(x: 10, y: 4.7, width: 4.8, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Prompty"
        return image
    }()
}

/// The app's mark, tinted like an SF Symbol. `height` is the mark's height.
struct LogoMark: View {
    var height: CGFloat

    var body: some View {
        Image(nsImage: Theme.logoMark)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(20.0 / 16.0, contentMode: .fit)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// A small key-cap, as used in menus and launchers.
struct Keycap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 17)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
    }
}

/// A label followed by its key-caps, e.g. "Copy ↵".
struct KeyHint: View {
    let label: String
    let keys: [String]

    init(_ label: String, keys: String...) {
        self.label = label
        self.keys = keys
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { Keycap($0) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(keys.joined(separator: " "))")
    }
}

/// A rounded-square symbol tile that identifies a prompt's kind at a glance.
struct GlyphTile: View {
    /// An SF Symbol name, or nil for the app's own mark.
    let systemName: String?
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.44, weight: .semibold))
            } else {
                LogoMark(height: size * 0.4)
            }
        }
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct FilterChip: View {
    let title: String
    var systemImage: String?
    var iconTint: Color?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(iconTint ?? (isOn ? Color.accentColor : Color.secondary))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .medium))
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .background(isOn ? Color.accentColor.opacity(0.15) : Theme.subtleFill, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isOn ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A borderless icon button with a hover highlight.
struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color = .secondary
    var size: CGFloat = 26
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(isHovered ? Theme.subtleFill : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A behind-window blur for the borderless panel, used when Liquid Glass is off.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

enum Formatting {
    static func relativeUse(_ date: Date?) -> String {
        guard let date else { return "Never used" }
        if Date.now.timeIntervalSince(date) < 60 { return "Used just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Used " + formatter.localizedString(for: date, relativeTo: .now)
    }

    static func size(of text: String) -> String {
        let count = text.count
        let tokens = Prompt.approximateTokenCount(for: text)
        return "\(count.formatted()) chars · ~\(tokens.formatted()) tokens"
    }
}

/// The header shared by the editor, template fill and guide screens.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let backHelp: String
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "chevron.left", help: backHelp, size: 28, action: onBack)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .frame(height: 54)
    }
}
