import AppKit
import ApplicationServices
import Carbon
import CoreAudio

/// Performs bound actions.
final class ActionExecutor {
    static let shared = ActionExecutor()

    func perform(_ action: Action) {
        switch action.kind {
        case .none:
            break

        case .leftClick: EventPoster.click(button: 0)
        case .rightClick: EventPoster.click(button: 1)
        case .middleClick: EventPoster.click(button: 2)
        case .backButton: EventPoster.click(button: 3)
        case .forwardButton: EventPoster.click(button: 4)
        case .doubleClick: EventPoster.click(button: 0, count: 2)
        case .tripleClick: EventPoster.click(button: 0, count: 3)
        case .cmdClick: EventPoster.click(button: 0, flags: .maskCommand)
        case .shiftClick: EventPoster.click(button: 0, flags: .maskShift)
        case .optionClick: EventPoster.click(button: 0, flags: .maskAlternate)
        case .controlClick: EventPoster.click(button: 0, flags: .maskControl)
        case .shiftCmdClick: EventPoster.click(button: 0, flags: [.maskShift, .maskCommand])

        case .missionControl: dock("com.apple.expose.awake", missionControlArgument: nil)
        case .appExpose: dock("com.apple.expose.front.awake", missionControlArgument: "2")
        case .showDesktop: dock("com.apple.showdesktop.awake", missionControlArgument: "1")
        case .launchpad: dock("com.apple.launchpad.toggle", missionControlArgument: nil, fallbackApp: "Launchpad")
        case .spaceLeft: EventPoster.keyStroke(KeyCode.leftArrow, flags: [.maskControl, .maskSecondaryFn])
        case .spaceRight: EventPoster.keyStroke(KeyCode.rightArrow, flags: [.maskControl, .maskSecondaryFn])
        case .swipeBack: EventPoster.keyStroke(KeyCode.leftBracket, flags: .maskCommand)
        case .swipeForward: EventPoster.keyStroke(KeyCode.rightBracket, flags: .maskCommand)
        case .lookUp: EventPoster.keyStroke(KeyCode.d, flags: [.maskControl, .maskCommand])
        case .zoomIn: zoom(in: true)
        case .zoomOut: zoom(in: false)
        case .scrollUp: ScrollEngine.shared.impulse(ticksX: 0, ticksY: 1)
        case .scrollDown: ScrollEngine.shared.impulse(ticksX: 0, ticksY: -1)
        case .scrollLeft: ScrollEngine.shared.impulse(ticksX: 1, ticksY: 0)
        case .scrollRight: ScrollEngine.shared.impulse(ticksX: -1, ticksY: 0)

        case .volumeUp: EventPoster.mediaKey(MediaKey.soundUp)
        case .volumeDown: EventPoster.mediaKey(MediaKey.soundDown)
        case .volumeMute: EventPoster.mediaKey(MediaKey.mute)
        case .playPause: EventPoster.mediaKey(MediaKey.play)
        case .nextTrack: EventPoster.mediaKey(MediaKey.next)
        case .previousTrack: EventPoster.mediaKey(MediaKey.previous)
        case .brightnessUp: EventPoster.mediaKey(MediaKey.brightnessUp)
        case .brightnessDown: EventPoster.mediaKey(MediaKey.brightnessDown)
        case .keyboardBacklightUp: EventPoster.mediaKey(MediaKey.illuminationUp)
        case .keyboardBacklightDown: EventPoster.mediaKey(MediaKey.illuminationDown)
        case .micMute: toggleMicMute()

        case .appSwitch: switchToPreviousApp()
        case .inputSourceSwitch: selectNextInputSource()
        case .fullscreenWindow: toggleFullscreen()
        case .zoomWindow: pressWindowButton(kAXZoomButtonAttribute)
        case .minimizeWindow: EventPoster.keyStroke(KeyCode.m, flags: .maskCommand)
        case .closeWindow: pressWindowButton(kAXCloseButtonAttribute)
        case .hideApp: NSWorkspace.shared.frontmostApplication?.hide()
        case .quitApp: NSWorkspace.shared.frontmostApplication?.terminate()

        case .lockScreen: EventPoster.keyStroke(KeyCode.q, flags: [.maskControl, .maskCommand])
        case .sleep: run("/usr/bin/pmset", ["sleepnow"])
        case .screenOff: run("/usr/bin/pmset", ["displaysleepnow"])
        case .logout: run("/usr/bin/osascript", ["-e", "tell application \"loginwindow\" to «event aevtlogo»"])
        case .screenshot: EventPoster.keyStroke(KeyCode.five, flags: [.maskShift, .maskCommand])

        case .keyboardShortcut:
            if let combo = action.shortcut { EventPoster.keyStroke(combo) }
        case .openURL: openURL(action.text)
        case .launchApp: launchApp(action.text)
        case .runShortcut:
            let name = action.text.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { run("/usr/bin/shortcuts", ["run", name]) }
        }
    }

    func zoom(in zoomIn: Bool) {
        EventPoster.keyStroke(zoomIn ? KeyCode.equal : KeyCode.minus, flags: .maskCommand)
    }

    // MARK: Dock / Mission Control

    private typealias CoreDockSendNotification = @convention(c) (CFString, Int32) -> Void

    private lazy var coreDockSend: CoreDockSendNotification? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: CoreDockSendNotification.self)
    }()

    private func dock(_ notification: String, missionControlArgument: String?, fallbackApp: String = "Mission Control") {
        if let send = coreDockSend {
            send(notification as CFString, 0)
            return
        }
        var args = ["-a", fallbackApp]
        if let arg = missionControlArgument { args += ["--args", arg] }
        run("/usr/bin/open", args)
    }

    // MARK: Apps & windows

    private func switchToPreviousApp() {
        EventPoster.key(KeyCode.command, down: true, flags: .maskCommand)
        EventPoster.key(KeyCode.tab, down: true, flags: .maskCommand)
        EventPoster.key(KeyCode.tab, down: false, flags: .maskCommand)
        EventPoster.key(KeyCode.command, down: false, flags: [])
    }

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return (window as! AXUIElement)
    }

    private func toggleFullscreen() {
        guard let window = focusedWindow() else { return }
        let attribute = "AXFullScreen" as CFString
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, attribute, &value)
        let isFullscreen = (value as? Bool) ?? false
        AXUIElementSetAttributeValue(window, attribute, isFullscreen ? kCFBooleanFalse : kCFBooleanTrue)
    }

    private func pressWindowButton(_ attribute: String) {
        guard let window = focusedWindow() else { return }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let button = value, CFGetTypeID(button) == AXUIElementGetTypeID()
        else { return }
        AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    private func openURL(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else {
            let path = (trimmed as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func launchApp(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let url: URL?
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        } else {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed)
        }
        guard let url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            NSLog("LogiMouse: failed to run \(path): \(error)")
        }
    }

    // MARK: Input sources

    private func selectNextInputSource() {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              list.count > 1
        else { return }
        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let currentID = sourceID(current)
        let index = list.firstIndex { sourceID($0) == currentID } ?? -1
        TISSelectInputSource(list[(index + 1) % list.count])
    }

    private func sourceID(_ source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    // MARK: Audio

    private func toggleMicMute() {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultInput = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                      mScope: kAudioObjectPropertyScopeGlobal,
                                                      mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultInput,
                                         0, nil, &size, &deviceID) == noErr
        else { return }

        var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                     mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(deviceID, &muteAddress, 0, nil, &size, &muted) == noErr {
            muted = muted == 0 ? 1 : 0
            AudioObjectSetPropertyData(deviceID, &muteAddress, 0, nil, size, &muted)
            return
        }

        // Devices without a mute control: toggle the input volume between 0 and its previous level.
        var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                       mScope: kAudioDevicePropertyScopeInput,
                                                       mElement: kAudioObjectPropertyElementMain)
        var volume: Float32 = 0
        size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &volumeAddress, 0, nil, &size, &volume) == noErr else { return }
        if volume > 0 {
            savedInputVolume = volume
            volume = 0
        } else {
            volume = savedInputVolume
        }
        AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, size, &volume)
    }

    private var savedInputVolume: Float32 = 0.75
}
