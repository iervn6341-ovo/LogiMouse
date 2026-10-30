import Foundation

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none

    // Clicks
    case leftClick, rightClick, middleClick, backButton, forwardButton
    case doubleClick, tripleClick
    case cmdClick, shiftClick, optionClick, controlClick, shiftCmdClick

    // Navigation & system gestures
    case missionControl, appExpose, showDesktop, launchpad
    case spaceLeft, spaceRight
    case swipeBack, swipeForward
    case lookUp
    case zoomIn, zoomOut
    case scrollUp, scrollDown, scrollLeft, scrollRight

    // Media & hardware
    case volumeUp, volumeDown, volumeMute
    case playPause, nextTrack, previousTrack
    case brightnessUp, brightnessDown
    case keyboardBacklightUp, keyboardBacklightDown
    case micMute

    // Windows & apps
    case appSwitch, inputSourceSwitch
    case fullscreenWindow, zoomWindow, minimizeWindow, closeWindow, hideApp, quitApp

    // System
    case lockScreen, sleep, screenOff, logout, screenshot

    // Custom
    case keyboardShortcut, openURL, launchApp, runShortcut

    var id: String { rawValue }

    /// Groups used to lay out the action picker.
    static let groups: [[ActionKind]] = [
        [.none],
        [.leftClick, .rightClick, .middleClick, .backButton, .forwardButton,
         .doubleClick, .tripleClick, .cmdClick, .shiftClick, .optionClick, .controlClick, .shiftCmdClick],
        [.missionControl, .appExpose, .showDesktop, .launchpad, .spaceLeft, .spaceRight,
         .swipeBack, .swipeForward, .lookUp, .zoomIn, .zoomOut,
         .scrollUp, .scrollDown, .scrollLeft, .scrollRight],
        [.volumeUp, .volumeDown, .volumeMute, .playPause, .nextTrack, .previousTrack,
         .brightnessUp, .brightnessDown, .keyboardBacklightUp, .keyboardBacklightDown, .micMute],
        [.appSwitch, .inputSourceSwitch, .fullscreenWindow, .zoomWindow, .minimizeWindow,
         .closeWindow, .hideApp, .quitApp],
        [.lockScreen, .sleep, .screenOff, .logout, .screenshot],
        [.keyboardShortcut, .openURL, .launchApp, .runShortcut],
    ]

    var englishTitle: String {
        switch self {
        case .none: return "Do Nothing"
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .backButton: return "Back Button"
        case .forwardButton: return "Forward Button"
        case .doubleClick: return "Double Click"
        case .tripleClick: return "Triple Click"
        case .cmdClick: return "⌘ Click"
        case .shiftClick: return "⇧ Click"
        case .optionClick: return "⌥ Click"
        case .controlClick: return "⌃ Click"
        case .shiftCmdClick: return "⇧⌘ Click"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .spaceLeft: return "Space Left"
        case .spaceRight: return "Space Right"
        case .swipeBack: return "Swipe Back"
        case .swipeForward: return "Swipe Forward"
        case .lookUp: return "Look Up"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        case .scrollLeft: return "Scroll Left"
        case .scrollRight: return "Scroll Right"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .volumeMute: return "Volume Mute"
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        case .keyboardBacklightUp: return "Keyboard Backlight Up"
        case .keyboardBacklightDown: return "Keyboard Backlight Down"
        case .micMute: return "Mic Mute Toggle"
        case .appSwitch: return "App Switch"
        case .inputSourceSwitch: return "Input Source Switch"
        case .fullscreenWindow: return "Fullscreen Window"
        case .zoomWindow: return "Zoom Window"
        case .minimizeWindow: return "Minimize Window"
        case .closeWindow: return "Close Window"
        case .hideApp: return "Hide App"
        case .quitApp: return "Quit App"
        case .lockScreen: return "Lock Screen"
        case .sleep: return "Sleep"
        case .screenOff: return "Screen Off"
        case .logout: return "Log Out"
        case .screenshot: return "Screenshot"
        case .keyboardShortcut: return "Keyboard Shortcut"
        case .openURL: return "Open URL / File"
        case .launchApp: return "Launch App"
        case .runShortcut: return "Run Shortcut"
        }
    }

    var title: String { L(englishTitle) }

    var needsText: Bool {
        self == .openURL || self == .launchApp || self == .runShortcut
    }
}

struct Action: Codable, Hashable {
    var kind: ActionKind = .none
    var shortcut: KeyCombo?
    var text: String = ""

    var summary: String {
        switch kind {
        case .keyboardShortcut: return shortcut?.description ?? kind.title
        case .openURL, .launchApp, .runShortcut: return text.isEmpty ? kind.title : "\(kind.title): \(text)"
        default: return kind.title
        }
    }
}
