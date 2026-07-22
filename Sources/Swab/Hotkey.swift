import AppKit
import Carbon.HIToolbox

/// A system-wide key combination. Stored as Carbon key code + Carbon modifier
/// mask, which is what `RegisterEventHotKey` wants and what survives a
/// round-trip through UserDefaults.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultToggle = HotkeyBinding(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(optionKey | cmdKey))

    /// Built from a key-down event, or nil if the combination has no modifiers
    /// — an unmodified global hotkey would swallow the key everywhere.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        guard carbon != 0 else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = carbon
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// `⌥⌘S` — the way macOS writes it in menus.
    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(for: keyCode)
    }

    private static func keyName(for code: UInt32) -> String {
        // The keys people actually bind. Anything else falls back to its code,
        // which is ugly but never wrong.
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
        ]
        return names[Int(code)] ?? "key \(code)"
    }
}

/// The Carbon hotkey callback is a plain C function pointer, so the action has
/// to reach it through a global. Only ever touched on the main thread: the
/// handler is installed on the application event target, which dispatches
/// there.
private nonisolated(unsafe) var hotkeyActions: [UInt32: () -> Void] = [:]

/// Registers system-wide hotkeys through Carbon's `RegisterEventHotKey`, which
/// is still the only supported way to get a key combination that fires while
/// another app is frontmost — and, unlike a CGEventTap, it needs no extra
/// permission.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    private var handler: EventHandlerRef?
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    private init() {}

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // The Carbon handler runs on the main thread; hop the isolation
            // barrier without a detached task so the action is synchronous.
            MainActor.assumeIsolated { hotkeyActions[id]?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    /// Replaces any binding previously registered under `slot`.
    func register(_ binding: HotkeyBinding, slot: String, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(slot: slot)

        let id = slotIDs[slot] ?? {
            let fresh = nextID
            nextID += 1
            slotIDs[slot] = fresh
            return fresh
        }()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53574142), id: id)  // 'SWAB'
        let status = RegisterEventHotKey(binding.keyCode,
                                         binding.modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else { return false }
        registered[id] = ref
        hotkeyActions[id] = action
        return true
    }

    func unregister(slot: String) {
        guard let id = slotIDs[slot], let ref = registered[id] else { return }
        UnregisterEventHotKey(ref)
        registered[id] = nil
        hotkeyActions[id] = nil
    }

    private var slotIDs: [String: UInt32] = [:]
}
