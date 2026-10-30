import CoreGraphics
import Foundation

/// App-level key remapping: a key combo triggers an action instead of being delivered.
final class KeyEngine {
    static let shared = KeyEngine()

    /// Set while the UI records a shortcut, so mappings don't fire.
    var isRecording = false
    private var swallowedKeyUps = Set<Int64>()

    /// Returns true when the event should be swallowed.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            return swallowedKeyUps.remove(code) != nil
        }
        guard !isRecording else { return false }

        let context = SettingsStore.shared.currentContext
        guard !context.disabled, !context.keyMappings.isEmpty else { return false }

        // Arrow and function keys carry the fn flag implicitly, so fn is not part of key matching.
        let mods = ModifierSet(cgFlags: event.flags).subtracting(.fn)
        guard let mapping = context.keyMappings.first(where: {
            $0.enabled && Int64($0.from.keyCode) == code && $0.from.modifiers.subtracting(.fn) == mods
        }) else { return false }

        swallowedKeyUps.insert(code)
        ActionExecutor.shared.perform(mapping.action)
        return true
    }
}
