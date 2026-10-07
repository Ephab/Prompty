import SwiftUI

/// The panel's content: switches screens inside a fixed frame (so the window
/// never resizes), draws the glass card, and runs the entrance animation.
struct RootView: View {
    @Bindable var viewModel: PromptyViewModel

    @AppStorage("prompty.liquidGlassEnabled") private var liquidGlassEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
            .modifier(PanelChrome(liquidGlass: liquidGlassEnabled))
            .modifier(PresentationEffect(isPresented: viewModel.isPresented, reduceMotion: reduceMotion))
            .padding(Theme.panelShadowMargin)
            .onChange(of: viewModel.store.prompts) { _, _ in
                viewModel.refreshResults()
            }
    }

    private var content: some View {
        ZStack {
            switch viewModel.screen {
            case .library:
                LibraryView(viewModel: viewModel)
                    .transition(.offset(x: -28).combined(with: .opacity))
            case .editing:
                EditorView(viewModel: viewModel)
                    .transition(.offset(x: 28).combined(with: .opacity))
            case .filling:
                QuickFillView(viewModel: viewModel)
                    .transition(.offset(x: 28).combined(with: .opacity))
            case .guide:
                GuideView(viewModel: viewModel, hotKeyController: viewModel.hotKeyController)
                    .transition(.offset(x: 28).combined(with: .opacity))
            case .settings:
                SettingsView(viewModel: viewModel, hotKeyController: viewModel.hotKeyController)
                    .transition(.offset(x: 28).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Theme.screenChange, value: viewModel.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Spacers and padding aren't hit-testable, so this layer catches
        // drags in the header's empty space too.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.isActionPanelOpen, viewModel.screen == .library {
                ActionPanel(viewModel: viewModel)
                    .padding(.trailing, 12)
                    .padding(.bottom, 46)
                    .transition(.scale(scale: 0.94, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = viewModel.toast {
                ToastView(toast: toast, onUndo: viewModel.undoFromToast)
                    .padding(.bottom, 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(Theme.selection, value: viewModel.isActionPanelOpen)
        // Dragging anywhere that isn't a control moves the panel.
        .gesture(WindowDragGesture())
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.toast)
        .clipped()
    }
}

/// Glass or blurred card for the floating panel.
private struct PanelChrome: ViewModifier {
    let liquidGlass: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelCornerRadius, style: .continuous)
        if liquidGlass {
            // Plain glass is too see-through over busy windows; a frosted
            // backing keeps text legible while the glass supplies the rim.
            content
                .background { VisualEffectBackground(material: .popover).opacity(0.82) }
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
                .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 0.5) }
                .background { shape.fill(.black.opacity(0.001)).shadow(color: .black.opacity(0.25), radius: 28, y: 14) }
        } else {
            content
                .background { VisualEffectBackground(material: .popover) }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 0.5) }
                .background { shape.fill(.black.opacity(0.001)).shadow(color: .black.opacity(0.28), radius: 28, y: 14) }
        }
    }
}

/// One animator for the panel: opacity plus a slight scale from the top.
/// The window itself never animates, which is what caused the old jitter.
private struct PresentationEffect: ViewModifier {
    let isPresented: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented || reduceMotion ? 1 : 0.965, anchor: .top)
            .offset(y: isPresented || reduceMotion ? 0 : -6)
    }
}

private struct ToastView: View {
    let toast: ToastState
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(toast.message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if toast.offersUndo {
                Divider().frame(height: 14)
                Button(action: onUndo) {
                    HStack(spacing: 4) {
                        Text("Undo")
                            .font(.system(size: 12, weight: .semibold))
                        Keycap("⌘Z")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Undo delete")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, toast.offersUndo ? 8 : 12)
        .frame(height: 32)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }
}
