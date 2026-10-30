import Foundation

/// Physical key substitution for every keyboard, like `hidutil property --set '{"UserKeyMapping": …}'`.
final class KeySubstitutions {
    static let shared = KeySubstitutions()

    private var timer: Timer?
    private var applied = false

    func apply(_ substitutions: [KeySubstitution]) {
        let active = SettingsStore.shared.settings.general.enabled ? substitutions.filter(\.enabled) : []
        guard !active.isEmpty else {
            if applied { write([]) }
            applied = false
            timer?.invalidate()
            timer = nil
            return
        }
        write(active)
        applied = true
        if timer == nil {
            // Keyboards connected later need the mapping too.
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                let s = SettingsStore.shared.settings
                self?.write(s.general.enabled ? s.keySubstitutions.filter(\.enabled) : [])
            }
        }
    }

    func clear() {
        if applied { write([]) }
        applied = false
    }

    private func write(_ substitutions: [KeySubstitution]) {
        let mapping: [[String: NSNumber]] = substitutions.map {
            ["HIDKeyboardModifierMappingSrc": NSNumber(value: $0.from),
             "HIDKeyboardModifierMappingDst": NSNumber(value: $0.to)]
        }
        let hid = HIDServices.shared
        for service in hid.services(usage: 0x06) {
            hid.setProperty(service, "UserKeyMapping", mapping as CFArray)
        }
    }
}

/// Keys offered for substitution, as HID usages (page 0x07 keyboard, 0xFF Apple top case).
enum KeyUsage {
    static let keys: [(name: String, usage: UInt64)] = {
        var list: [(String, UInt64)] = [
            ("⇪ Caps Lock", 0x39),
            ("Left ⌃ Control", 0xE0), ("Left ⇧ Shift", 0xE1), ("Left ⌥ Option", 0xE2), ("Left ⌘ Command", 0xE3),
            ("Right ⌃ Control", 0xE4), ("Right ⇧ Shift", 0xE5), ("Right ⌥ Option", 0xE6), ("Right ⌘ Command", 0xE7),
            ("⎋ Escape", 0x29), ("⇥ Tab", 0x2B), ("↩ Return", 0x28), ("⌫ Delete", 0x2A), ("⌦ Forward Delete", 0x4C),
            ("Space", 0x2C), ("` Grave", 0x35), ("§ Section", 0x64),
            ("Home", 0x4A), ("End", 0x4D), ("Page Up", 0x4B), ("Page Down", 0x4E),
            ("Insert", 0x49), ("Print Screen", 0x46), ("Scroll Lock", 0x47), ("Pause", 0x48),
            ("Application / Menu", 0x65),
            ("←", 0x50), ("→", 0x4F), ("↓", 0x51), ("↑", 0x52),
        ]
        for n in 1...12 { list.append(("F\(n)", UInt64(0x3A + n - 1))) }
        for n in 13...24 { list.append(("F\(n)", UInt64(0x68 + n - 13))) }
        return list.map { (name: $0.0, usage: 0x7_0000_0000 | $0.1) } + [(name: "fn", usage: 0xFF_0000_0003)]
    }()

    static func name(_ usage: UInt64) -> String {
        keys.first { $0.usage == usage }?.name ?? String(format: "0x%llX", usage)
    }
}
