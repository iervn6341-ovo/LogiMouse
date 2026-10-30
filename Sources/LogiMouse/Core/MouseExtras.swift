import AppKit
import ApplicationServices

/// Window helpers based on the window server list and Accessibility.
enum WindowUtils {
    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        // Never let a hung app stall the event tap.
        AXUIElementSetMessagingTimeout(element, 0.05)
        return element
    }()

    /// The process owning the topmost normal window under `point` (global, top-left origin).
    static func windowOwner(at point: CGPoint) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(point)
            else { continue }
            // The first window under the point decides; menus, panels and the Dock are not normal windows.
            guard layer == 0 else { return nil }
            return info[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    /// The pid of a normal window under `point` if it belongs to an app that is not frontmost.
    static func inactiveWindowOwner(at point: CGPoint) -> pid_t? {
        guard let pid = windowOwner(at: point),
              pid != NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        return pid
    }

    /// Activates `pid` and raises the specific window under `point`.
    static func activate(_ pid: pid_t, raisingWindowAt point: CGPoint) {
        if let window = element(at: point).flatMap(window(of:)) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        if #available(macOS 14.0, *) {
            NSRunningApplication(processIdentifier: pid)?.activate()
        } else {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        }
    }

    static func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success
        else { return nil }
        return element
    }

    static func window(of element: AXUIElement) -> AXUIElement? {
        attributeElement(element, kAXWindowAttribute)
    }

    static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func attributeElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// The slider under the pointer, looking through a couple of parents (e.g. the slider's knob).
    static func slider(at point: CGPoint) -> AXUIElement? {
        var current = element(at: point)
        for _ in 0..<3 {
            guard let element = current else { return nil }
            if role(of: element) == kAXSliderRole { return element }
            current = attributeElement(element, kAXParentAttribute)
        }
        return nil
    }
}

/// Left/right click-through, the left-drag dead zone, scroll-to-raise and slider scrolling.
final class MouseExtras {
    static let shared = MouseExtras()

    private enum ClickThrough {
        case none
        /// The original press was held back while the window activates.
        case waiting(location: CGPoint, flags: CGEventFlags, released: Bool)
        /// The press has been delivered; pass the rest of the click through.
        case delivered
    }

    private var clickThrough = ClickThrough.none
    private var leftDownLocation: CGPoint?
    private var deadZoneExceeded = false
    private var lastRaise = 0.0

    private var buttons: ButtonSettings { SettingsStore.shared.settings.buttons }

    // MARK: Left button

    /// Returns true when the event should be swallowed.
    func leftMouseDown(_ event: CGEvent) -> Bool {
        leftDownLocation = event.location
        deadZoneExceeded = false
        clickThrough = .none

        guard buttons.leftClickThrough, !SettingsStore.shared.currentContext.disabled,
              event.getIntegerValueField(.mouseEventClickState) <= 1,
              let pid = WindowUtils.inactiveWindowOwner(at: event.location)
        else { return false }

        let location = event.location
        clickThrough = .waiting(location: location, flags: event.flags, released: false)
        WindowUtils.activate(pid, raisingWindowAt: location)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.deliverHeldClick()
        }
        return true
    }

    func leftMouseUp(_ event: CGEvent) -> Bool {
        leftDownLocation = nil
        switch clickThrough {
        case .waiting(let location, let flags, _):
            clickThrough = .waiting(location: location, flags: flags, released: true)
            return true
        case .delivered:
            clickThrough = .none
            return false
        case .none:
            return false
        }
    }

    func leftMouseDragged(_ event: CGEvent) -> Bool {
        if case .waiting = clickThrough { return true }
        let deadZone = buttons.leftDragDeadZone
        guard deadZone > 0, !deadZoneExceeded, let start = leftDownLocation else { return false }
        let distance = hypot(event.location.x - start.x, event.location.y - start.y)
        if distance < deadZone { return true }
        deadZoneExceeded = true
        return false
    }

    private func deliverHeldClick() {
        guard case .waiting(let location, let flags, let released) = clickThrough else { return }
        if let down = EventPoster.mouseEvent(button: 0, down: true, at: location) {
            down.flags = flags
            EventPoster.post(down)
        }
        if released {
            if let up = EventPoster.mouseEvent(button: 0, down: false, at: location) {
                up.flags = flags
                EventPoster.post(up)
            }
            clickThrough = .none
        } else {
            clickThrough = .delivered
        }
    }

    // MARK: Right button

    func rightMouseDown(_ event: CGEvent) {
        guard buttons.rightClickThrough, !SettingsStore.shared.currentContext.disabled,
              let pid = WindowUtils.inactiveWindowOwner(at: event.location)
        else { return }
        WindowUtils.activate(pid, raisingWindowAt: event.location)
    }

    // MARK: Scroll

    /// Returns true when the scroll event was used to move a slider.
    func scroll(_ event: CGEvent) -> Bool {
        let s = SettingsStore.shared.settings.scroll
        guard s.scrollToRaise || s.verticalSliders || s.horizontalSliders,
              !SettingsStore.shared.currentContext.disabled
        else { return false }
        let location = event.location

        if s.scrollToRaise {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastRaise > 0.3, let pid = WindowUtils.inactiveWindowOwner(at: location) {
                lastRaise = now
                WindowUtils.activate(pid, raisingWindowAt: location)
            }
        }

        let dy = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let dx = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        guard !continuous else { return false }
        let useVertical = s.verticalSliders && dy != 0
        let useHorizontal = s.horizontalSliders && dx != 0 && dy == 0
        guard useVertical || useHorizontal, let slider = WindowUtils.slider(at: location) else { return false }

        let up = useVertical ? dy > 0 : dx < 0
        AXUIElementPerformAction(slider, (up ? kAXIncrementAction : kAXDecrementAction) as CFString)
        return true
    }
}
