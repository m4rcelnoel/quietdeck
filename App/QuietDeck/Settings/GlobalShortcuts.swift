import AppKit
import Carbon.HIToolbox

/// System-wide hot keys. Carbon's API needs no Accessibility permission.
@MainActor
final class GlobalShortcuts {
    static let shared = GlobalShortcuts()

    private static let signature: OSType = 0x5144_4B31  // "QDK1"

    private var references: [EventHotKeyRef] = []
    private var actions: [UInt32: ShortcutAction] = [:]
    private var isInstalled = false

    var handler: (ShortcutAction) -> Void = { _ in }

    /// Replaces all registered shortcuts.
    func register(_ shortcuts: [ShortcutAction: KeyCombo]) {
        installHandlerIfNeeded()
        for reference in references {
            UnregisterEventHotKey(reference)
        }
        references = []
        actions = [:]

        for (index, entry) in shortcuts.enumerated() {
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                entry.value.keyCode,
                entry.value.modifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetEventDispatcherTarget(),
                0,
                &reference
            )
            if status == noErr, let reference {
                references.append(reference)
                actions[id] = entry.key
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard !isInstalled else { return }
        isInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id
                )
                let pressed = id.id
                Task { @MainActor in GlobalShortcuts.shared.fire(pressed) }
                return noErr
            },
            1,
            &type,
            nil,
            nil
        )
    }

    private func fire(_ id: UInt32) {
        if let action = actions[id] {
            handler(action)
        }
    }
}

extension KeyCombo {
    /// Builds a combination from a key press. A shortcut needs Command, Control or Option,
    /// so that plain typing is never captured system-wide.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }

        var modifiers: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
            symbols += "⌃"
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
            symbols += "⌥"
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
            symbols += "⇧"
        }
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
            symbols += "⌘"
        }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, display: symbols + key)
    }
}
