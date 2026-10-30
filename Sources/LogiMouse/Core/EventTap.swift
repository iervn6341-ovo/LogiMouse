import CoreGraphics
import Foundation

/// A session-level event tap that routes mouse, scroll and key events to the engines.
/// The tap's run loop source is attached to the main run loop, so all handling happens on the main thread.
final class EventTap {
    static let shared = EventTap()

    private var tap: CFMachPort?
    private var retryTimer: Timer?

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel,
            .keyDown, .keyUp, .flagsChanged,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: mask,
                                           callback: eventTapCallback,
                                           userInfo: nil)
        else {
            // Permission may have just been granted; the tap can take a moment to become available.
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.start()
            }
            return
        }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns nil to swallow the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> CGEvent? {
        if EventPoster.isSynthetic(event) { return event }

        let buttons = ButtonEngine.shared
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if buttons.mouseDown(button: button, flags: event.flags, location: event.location, isVirtual: false) {
                return nil
            }
            if type == .leftMouseDown { return MouseExtras.shared.leftMouseDown(event) ? nil : event }
            if type == .rightMouseDown { MouseExtras.shared.rightMouseDown(event) }
            return event

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            if buttons.mouseUp(button: button) { return nil }
            if type == .leftMouseUp { return MouseExtras.shared.leftMouseUp(event) ? nil : event }
            return event

        case .leftMouseDragged:
            return MouseExtras.shared.leftMouseDragged(event) ? nil : event

        case .rightMouseDragged, .otherMouseDragged, .mouseMoved:
            let dx = event.getDoubleValueField(.mouseEventDeltaX)
            let dy = event.getDoubleValueField(.mouseEventDeltaY)
            return buttons.mouseMoved(dx: dx, dy: dy, isDrag: type != .mouseMoved) ? nil : event

        case .scrollWheel:
            let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            if buttons.scrollWheel(deltaY: Int(dy)) { return nil }
            if MouseExtras.shared.scroll(event) { return nil }
            return ScrollEngine.shared.handle(event)

        case .keyDown, .keyUp:
            return KeyEngine.shared.handle(type: type, event: event) ? nil : event

        case .flagsChanged:
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(KeyCode.capsLock) {
                let on = event.flags.contains(.maskAlphaShift)
                MainActor.assumeIsolated { HUD.shared.showCapsLock(on) }
            }
            return event

        default:
            return event
        }
    }
}

private func eventTapCallback(proxy: CGEventTapProxy,
                              type: CGEventType,
                              event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        EventTap.shared.reenable()
        return Unmanaged.passUnretained(event)
    }
    guard let result = EventTap.shared.handle(type: type, event: event) else { return nil }
    return Unmanaged.passUnretained(result)
}
