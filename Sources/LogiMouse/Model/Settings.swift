import Foundation

// MARK: - Button bindings

enum TriggerKind: String, Codable, CaseIterable, Identifiable {
    case click, longPress
    case dragUp, dragDown, dragLeft, dragRight
    case scrollUp, scrollDown
    case chord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: return L("Click")
        case .longPress: return L("Long Press")
        case .dragUp: return L("Drag ↑")
        case .dragDown: return L("Drag ↓")
        case .dragLeft: return L("Drag ←")
        case .dragRight: return L("Drag →")
        case .scrollUp: return L("Hold + Scroll ↑")
        case .scrollDown: return L("Hold + Scroll ↓")
        case .chord: return L("Hold + Click")
        }
    }

    var isDrag: Bool {
        self == .dragUp || self == .dragDown || self == .dragLeft || self == .dragRight
    }

    var supportsRepeat: Bool {
        self == .longPress || isDrag
    }
}

struct Trigger: Codable, Hashable {
    var button: Int
    var modifiers: ModifierSet = []
    var kind: TriggerKind = .click
    /// The second button for `.chord` triggers.
    var chordButton: Int = 0

    var buttonDescription: String {
        modifiers.symbols + ButtonNames.name(button)
    }
}

struct ButtonBinding: Codable, Hashable, Identifiable {
    var id = UUID()
    var enabled = true
    var trigger: Trigger
    var action: Action
    /// Repeat the action while the long press is held, or on every drag step.
    var repeats = false
}

enum ButtonNames {
    /// Buttons diverted from Logitech HID++ devices are reported as `virtualBase + CID`.
    static let virtualBase = 1000

    static func name(_ button: Int) -> String {
        switch button {
        case 0: return L("Left Button")
        case 1: return L("Right Button")
        case 2: return L("Middle Button")
        case 3: return L("Back Button")
        case 4: return L("Forward Button")
        case virtualBase...:
            return "Logi " + LogiControlNames.name(UInt16(button - virtualBase))
        default: return L("Button") + " \(button + 1)"
        }
    }
}

struct PanSettings: Codable, Hashable {
    var buttons: [Int] = []
    var momentum = true
    var invert = false
    var speed: Double = 1.0
}

struct ButtonSettings: Codable, Hashable {
    var bindings: [ButtonBinding] = ButtonSettings.defaultBindings
    var longPressDelay: Double = 400
    var longPressInterval: Double = 120
    var dragThreshold: Double = 40
    var pan = PanSettings()

    static var defaultBindings: [ButtonBinding] {
        [
            ButtonBinding(trigger: Trigger(button: 2, kind: .dragUp), action: Action(kind: .missionControl)),
            ButtonBinding(trigger: Trigger(button: 2, kind: .dragDown), action: Action(kind: .appExpose)),
            ButtonBinding(trigger: Trigger(button: 2, kind: .dragLeft), action: Action(kind: .spaceRight)),
            ButtonBinding(trigger: Trigger(button: 2, kind: .dragRight), action: Action(kind: .spaceLeft)),
            ButtonBinding(trigger: Trigger(button: 3, kind: .click), action: Action(kind: .swipeBack)),
            ButtonBinding(trigger: Trigger(button: 4, kind: .click), action: Action(kind: .swipeForward)),
        ]
    }
}

// MARK: - Cursor

struct CursorSettings: Codable, Hashable {
    var enabled = false
    /// Multiplier relative to the macOS base resolution (1.0 = system default).
    var speed: Double = 1.0
    var acceleration: Double = 0.6875
    var disableAcceleration = false
    var holdInGesture = true
}

// MARK: - Scroll

struct ScrollSettings: Codable, Hashable {
    var smooth = true
    /// Pixels scrolled per wheel tick with smooth scrolling.
    var step: Double = 60
    /// Time in milliseconds a single tick takes to settle.
    var duration: Double = 300
    /// 0 (off) … 10.
    var acceleration: Double = 5
    var moreSmooth = false
    /// Line multiplier when smooth scrolling is off.
    var lineMultiplier: Double = 1.0

    var invertVertical = false
    var invertHorizontal = false
    var horizontalSpeed: Double = 1.0

    var horizontalEnabled = true
    var horizontalModifier: ModifierSet = [.shift]
    var horizontalInvert = false

    var zoomEnabled = false
    var zoomModifier: ModifierSet = [.control]
    var zoomInvert = false

    var fastEnabled = true
    var fastModifier: ModifierSet = [.option]
    var fastMultiplier: Double = 3.0
}

// MARK: - Keyboard

struct KeyMapping: Codable, Hashable, Identifiable {
    var id = UUID()
    var enabled = true
    var from: KeyCombo
    var action: Action
}

// MARK: - Per-app exceptions

struct AppException: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var disableAll = false
    var disableSmoothScroll = false
    var ignoreGlobalBindings = false
    var disableKeyMappings = false
    /// Bindings that only apply in this app and take precedence over global ones.
    var bindings: [ButtonBinding] = []

    var id: String { bundleID }
}

// MARK: - Logitech

enum WheelMode: String, Codable, CaseIterable, Identifiable {
    case smartShift, ratchet, freeSpin
    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartShift: return L("SmartShift (auto)")
        case .ratchet: return L("Always ratchet")
        case .freeSpin: return L("Always free spin")
        }
    }
}

struct LogiDeviceSettings: Codable, Hashable {
    var dpi: Int?
    var wheelMode: WheelMode?
    var smartShiftThreshold: Int?
    var divertedControls: [UInt16] = []
}

// MARK: - General

struct GeneralSettings: Codable, Hashable {
    var enabled = true
    var hideMenuBarIcon = false
    /// "system", "en" or "zh-Hant".
    var language = "system"
    var tightenMenuBarIcons = false
}

// MARK: - Root

struct AppSettings: Codable, Hashable {
    var version = 1
    var general = GeneralSettings()
    var buttons = ButtonSettings()
    var cursor = CursorSettings()
    var scroll = ScrollSettings()
    var keyMappings: [KeyMapping] = []
    var exceptions: [AppException] = []
    /// Keyed by device name.
    var logi: [String: LogiDeviceSettings] = [:]
}
