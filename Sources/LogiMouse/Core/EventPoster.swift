import AppKit
import CoreGraphics

/// Synthesizes input events. Every event we post is tagged so the event tap can ignore it.
enum EventPoster {
    static let marker: Int64 = 0x4C6F_6769_4D73

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }

    static func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
    }

    static var cursorLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static var currentFlags: CGEventFlags {
        CGEventSource.flagsState(.combinedSessionState)
    }

    // MARK: Mouse

    static func mouseEvent(button: Int, down: Bool, at location: CGPoint) -> CGEvent? {
        let type: CGEventType
        let cgButton: CGMouseButton
        switch button {
        case 0:
            type = down ? .leftMouseDown : .leftMouseUp
            cgButton = .left
        case 1:
            type = down ? .rightMouseDown : .rightMouseUp
            cgButton = .right
        default:
            type = down ? .otherMouseDown : .otherMouseUp
            cgButton = .center
        }
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: cgButton)
        event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        return event
    }

    static func click(button: Int, count: Int = 1, flags: CGEventFlags = [], at location: CGPoint? = nil) {
        let loc = location ?? cursorLocation
        for n in 1...max(1, count) {
            for down in [true, false] {
                guard let event = mouseEvent(button: button, down: down, at: loc) else { continue }
                event.flags = flags
                event.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                post(event)
            }
        }
    }

    // MARK: Keyboard

    static func key(_ code: UInt16, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
        event.flags = flags
        post(event)
    }

    static func keyStroke(_ code: UInt16, flags: CGEventFlags = []) {
        key(code, down: true, flags: flags)
        key(code, down: false, flags: flags)
    }

    static func keyStroke(_ combo: KeyCombo) {
        keyStroke(combo.keyCode, flags: combo.modifiers.cgFlags)
    }

    /// Posts an NX_SYSDEFINED auxiliary key (volume, brightness, media…).
    static func mediaKey(_ key: Int32) {
        for down in [true, false] {
            let state: Int32 = down ? 0xA : 0xB
            let flags = NSEvent.ModifierFlags(rawValue: UInt(state) << 8)
            let data1 = Int((key << 16) | (state << 8))
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                                 timestamp: 0, windowNumber: 0, context: nil,
                                                 subtype: 8, data1: data1, data2: -1),
                  let cg = event.cgEvent
            else { continue }
            post(cg)
        }
    }

    // MARK: Scroll

    static func scrollPixels(x: Int32, y: Int32, flags: CGEventFlags) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: y, wheel2: x, wheel3: 0)
        else { return }
        event.flags = flags
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        post(event)
    }

    static func scrollLines(x: Int32, y: Int32, flags: CGEventFlags = []) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                                  wheel1: y, wheel2: x, wheel3: 0)
        else { return }
        event.flags = flags
        post(event)
    }
}

/// NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h.
enum MediaKey {
    static let soundUp: Int32 = 0
    static let soundDown: Int32 = 1
    static let brightnessUp: Int32 = 2
    static let brightnessDown: Int32 = 3
    static let mute: Int32 = 7
    static let play: Int32 = 16
    static let next: Int32 = 17
    static let previous: Int32 = 18
    static let illuminationUp: Int32 = 21
    static let illuminationDown: Int32 = 22
}
