import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut via Carbon's `RegisterEventHotKey`, which, unlike
/// event monitors, needs no Accessibility permission.
@MainActor
final class HotKey {
    struct Combination: Codable, Equatable {
        var keyCode: UInt32
        var modifiers: UInt32

        /// ⌃⌥L ("L" for Licht) — rarely taken by other apps.
        static let `default` = Combination(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey))

        init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        init?(event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var carbon: UInt32 = 0
            if flags.contains(.command) { carbon |= UInt32(cmdKey) }
            if flags.contains(.option) { carbon |= UInt32(optionKey) }
            if flags.contains(.control) { carbon |= UInt32(controlKey) }
            if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
            // Require at least one of ⌘⌥⌃ so plain typing can't trigger it.
            guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
            self.init(keyCode: UInt32(event.keyCode), modifiers: carbon)
        }

        var displayString: String {
            var result = ""
            if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
            return result + Self.keyName(keyCode)
        }

        private static func keyName(_ keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_Space: return "Leertaste"
            case kVK_Return: return "↩"
            case kVK_Escape: return "⎋"
            default: break
            }
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return "?" }
            let layout = unsafeBitCast(pointer, to: CFData.self) as Data
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = layout.withUnsafeBytes { buffer -> OSStatus in
                guard let base = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
                return UCKeyTranslate(
                    base, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &characters
                )
            }
            guard status == noErr, length > 0 else { return "?" }
            return String(utf16CodeUnits: characters, count: length).uppercased()
        }
    }

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        installHandler()
    }

    func register(_ combination: Combination) {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x484F_4B55), id: 1) // "HOKU"
        RegisterEventHotKey(combination.keyCode, combination.modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, context, &handler)
    }
}
