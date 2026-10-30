import AppKit
import CoreGraphics

/// Modifier keys that can be combined with a mouse button or key.
struct ModifierSet: OptionSet, Codable, Hashable {
    let rawValue: UInt32

    static let control = ModifierSet(rawValue: 1 << 0)
    static let option = ModifierSet(rawValue: 1 << 1)
    static let shift = ModifierSet(rawValue: 1 << 2)
    static let command = ModifierSet(rawValue: 1 << 3)
    static let fn = ModifierSet(rawValue: 1 << 4)

    static let all: [ModifierSet] = [.fn, .control, .option, .shift, .command]

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(cgFlags: CGEventFlags) {
        var set: ModifierSet = []
        if cgFlags.contains(.maskControl) { set.insert(.control) }
        if cgFlags.contains(.maskAlternate) { set.insert(.option) }
        if cgFlags.contains(.maskShift) { set.insert(.shift) }
        if cgFlags.contains(.maskCommand) { set.insert(.command) }
        if cgFlags.contains(.maskSecondaryFn) { set.insert(.fn) }
        self = set
    }

    init(nsFlags: NSEvent.ModifierFlags) {
        var set: ModifierSet = []
        if nsFlags.contains(.control) { set.insert(.control) }
        if nsFlags.contains(.option) { set.insert(.option) }
        if nsFlags.contains(.shift) { set.insert(.shift) }
        if nsFlags.contains(.command) { set.insert(.command) }
        if nsFlags.contains(.function) { set.insert(.fn) }
        self = set
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.fn) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        case .fn: return "fn"
        default: return symbols
        }
    }

    /// Symbols in the canonical macOS order (fn ⌃ ⌥ ⇧ ⌘).
    var symbols: String {
        var s = ""
        if contains(.fn) { s += "fn " }
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// A key plus modifiers, used both as a key-mapping trigger and as a shortcut action.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: ModifierSet

    var description: String {
        modifiers.symbols + KeyNames.name(keyCode)
    }
}

enum KeyNames {
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 10: "§",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
        50: "`", 51: "⌫", 53: "⎋", 57: "⇪", 64: "F17", 65: "Num .", 67: "Num *", 69: "Num +",
        71: "Clear", 75: "Num /", 76: "Num ↩", 78: "Num -", 79: "F18", 80: "F19", 81: "Num =",
        82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3", 86: "Num 4", 87: "Num 5", 88: "Num 6",
        89: "Num 7", 90: "F20", 91: "Num 8", 92: "Num 9", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "PgUp", 117: "⌦", 118: "F4",
        119: "End", 120: "F2", 121: "PgDn", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func name(_ code: UInt16) -> String {
        names[code] ?? "Key \(code)"
    }
}

/// Well-known virtual key codes used by built-in actions.
enum KeyCode {
    static let d: UInt16 = 2
    static let h: UInt16 = 4
    static let q: UInt16 = 12
    static let w: UInt16 = 13
    static let five: UInt16 = 23
    static let equal: UInt16 = 24
    static let minus: UInt16 = 27
    static let rightBracket: UInt16 = 30
    static let leftBracket: UInt16 = 33
    static let m: UInt16 = 46
    static let tab: UInt16 = 48
    static let escape: UInt16 = 53
    static let command: UInt16 = 55
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}
