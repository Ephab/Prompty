import Carbon.HIToolbox
import Foundation
import AppKit
import SwiftUI

/// The portion of a keyboard shortcut that is stable across app launches.
struct PromptyShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String?

    static let `default` = PromptyShortcut(
        keyCode: 49, // Space
        modifiers: UInt32(controlKey | optionKey),
        keyLabel: nil
    )

    var displayName: String {
        let modifierText = [
            (modifiers & UInt32(controlKey)) != 0 ? "⌃" : "",
            (modifiers & UInt32(optionKey)) != 0 ? "⌥" : "",
            (modifiers & UInt32(shiftKey)) != 0 ? "⇧" : "",
            (modifiers & UInt32(cmdKey)) != 0 ? "⌘" : ""
        ].joined()

        return modifierText + (keyLabel ?? Self.keyName(for: keyCode))
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Esc"
        case 115: return "Home"
        case 119: return "End"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            // Carbon key codes are intentionally used here instead of the
            // current keyboard layout. The recorder still gives the user a
            // useful fallback for keys that do not have a friendly name.
            return "Key \(keyCode)"
        }
    }
}

/// Registers one global Carbon hot key for the menu-bar utility.
final class HotKeyController: NSObject, ObservableObject {
    @Published private(set) var shortcut: PromptyShortcut
    @Published private(set) var registrationError: String?
    @Published private(set) var isRecording = false

    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private let defaults: UserDefaults
    private let defaultsKey = "prompty.shortcut"
    private let hotKeySignature: OSType = 0x50524D54 // PRMT
    private let hotKeyIdentifier: UInt32 = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let storedShortcut = try? JSONDecoder().decode(PromptyShortcut.self, from: data) {
            shortcut = storedShortcut
        } else {
            shortcut = .default
        }
        super.init()
    }

    deinit {
        stopRecording()
        unregister()
    }

    @discardableResult
    func register() -> Bool {
        installEventHandlerIfNeeded()
        return register(shortcut: shortcut)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    /// Attempts to replace the current shortcut. On failure the previous
    /// shortcut remains registered and persisted.
    @discardableResult
    func updateShortcut(keyCode: UInt32, modifiers: UInt32, keyLabel: String? = nil) -> Bool {
        let candidate = PromptyShortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
        guard candidate != shortcut else {
            stopRecording()
            return true
        }

        let previous = shortcut
        if register(shortcut: candidate) {
            shortcut = candidate
            persistShortcut()
            stopRecording()
            return true
        }

        // Re-registering is best-effort: if the old registration disappeared
        // while the new one was rejected, the status item still works by click.
        _ = register(shortcut: previous)
        registrationError = "That shortcut is unavailable."
        stopRecording()
        return false
    }

    func beginRecording() {
        registrationError = nil
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
    }

    @discardableResult
    func resetShortcut() -> Bool {
        stopRecording()
        return updateShortcut(
            keyCode: PromptyShortcut.default.keyCode,
            modifiers: PromptyShortcut.default.modifiers
        )
    }

    fileprivate func record(_ event: NSEvent) {
        guard isRecording else { return }

        let modifiers = event.modifierFlags.promptyCarbonFlags
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        let label = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        _ = updateShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: label?.isEmpty == false ? label : nil
        )
    }

    private func persistShortcut() {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    @discardableResult
    private func register(shortcut: PromptyShortcut) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        let id = EventHotKeyID(signature: hotKeySignature, id: hotKeyIdentifier)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            registrationError = "That shortcut is unavailable."
            return false
        }

        registrationError = nil
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            promptyHotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
    }

    fileprivate func handle(hotKeyID: EventHotKeyID) {
        guard hotKeyID.signature == hotKeySignature,
              hotKeyID.id == hotKeyIdentifier else { return }
        // Carbon delivers application hot-key events on the app's main event
        // target, so invoking the callback here avoids crossing actors with a
        // non-Sendable controller.
        onToggle?()
    }
}

private func promptyHotKeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let size = UInt32(MemoryLayout<EventHotKeyID>.size)
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        Int(size),
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
    controller.handle(hotKeyID: hotKeyID)
    return noErr
}

private extension NSEvent.ModifierFlags {
    var promptyCarbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}

/// A small native recorder. It is deliberately an NSView rather than a
/// dependency-backed control so it works in an accessory app and VoiceOver
/// still receives a concise value through `accessibilityValue`.
struct ShortcutRecorderView: NSViewRepresentable {
    @ObservedObject var controller: HotKeyController

    func makeNSView(context: Context) -> PromptyShortcutRecorderNSView {
        let view = PromptyShortcutRecorderNSView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: PromptyShortcutRecorderNSView, context: Context) {
        nsView.controller = controller
        nsView.needsDisplay = true
    }
}

final class PromptyShortcutRecorderNSView: NSView {
    weak var controller: HotKeyController?
    private nonisolated(unsafe) var mouseMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMouseMonitor()

        guard window != nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window,
                  self.controller?.isRecording == true else {
                return event
            }

            let point = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(point) {
                self.controller?.stopRecording()
                window.makeFirstResponder(nil)
                self.needsDisplay = true
            }
            return event
        }
    }

    deinit {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        controller?.beginRecording()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        controller?.record(event)
        needsDisplay = true
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.stopRecording()
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        controller?.stopRecording()
        return super.resignFirstResponder()
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)

        (controller.isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor)
            .setFill()
        path.fill()

        (controller.isRecording ? NSColor.controlAccentColor : NSColor.separatorColor)
            .setStroke()
        path.lineWidth = controller.isRecording ? 1.5 : 1
        path.stroke()

        let text = controller.isRecording ? "Press a shortcut…" : controller.shortcut.displayName
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? { "Global shortcut" }

    override func accessibilityValue() -> Any? {
        controller?.isRecording == true ? "Press a shortcut" : controller?.shortcut.displayName
    }
}
