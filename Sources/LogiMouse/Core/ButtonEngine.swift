import CoreGraphics
import Foundation

/// Turns button presses into clicks, long presses, drag gestures, chords, button+scroll and panning.
final class ButtonEngine {
    static let shared = ButtonEngine()

    /// When set, the next non-left button press is reported here instead of being handled.
    var recordHandler: (@MainActor (Int, ModifierSet) -> Void)?

    private struct Press {
        let button: Int
        let flags: CGEventFlags
        let isVirtual: Bool
        let bindings: [ButtonBinding]
        let panEnabled: Bool
        var accX = 0.0
        var accY = 0.0
        var travel = 0.0
        var consumed = false
        var panning = false
        var gestureDone = false
        var longPressActive = false
        var cursorHeld = false

        var hasDragBindings: Bool { bindings.contains { $0.trigger.kind.isDrag } }

        func binding(_ kind: TriggerKind) -> ButtonBinding? {
            bindings.first { $0.trigger.kind == kind }
        }
    }

    private var press: Press?
    private var longPressTimer: DispatchSourceTimer?
    private var swallowedUps = Set<Int>()

    private var settings: ButtonSettings { SettingsStore.shared.settings.buttons }

    // MARK: Events

    /// Returns true when the event should be swallowed.
    func mouseDown(button: Int, flags: CGEventFlags, location: CGPoint, isVirtual: Bool) -> Bool {
        let mods = ModifierSet(cgFlags: flags)

        if let handler = recordHandler, button != 0 {
            swallowedUps.insert(button)
            MainActor.assumeIsolated { handler(button, mods) }
            return true
        }

        // A second button while one is held: chord.
        if var p = press {
            guard p.button != button else { return false }
            if let b = p.bindings.first(where: { $0.trigger.kind == .chord && $0.trigger.chordButton == button }) {
                p.consumed = true
                press = p
                swallowedUps.insert(button)
                cancelLongPress()
                perform(b.action)
                return true
            }
            return false
        }

        guard button != 0 else { return false }
        let context = SettingsStore.shared.currentContext
        guard !context.disabled else { return false }

        let candidates = context.bindings.filter {
            $0.enabled && $0.trigger.button == button && $0.trigger.modifiers == mods
        }
        let panEnabled = settings.pan.buttons.contains(button)
        guard !candidates.isEmpty || panEnabled else { return isVirtual }

        var p = Press(button: button, flags: flags, isVirtual: isVirtual,
                      bindings: candidates, panEnabled: panEnabled)
        if SettingsStore.shared.settings.cursor.holdInGesture && (panEnabled || p.hasDragBindings) {
            CGAssociateMouseAndMouseCursorPosition(0)
            p.cursorHeld = true
        }
        press = p
        if p.binding(.longPress) != nil { scheduleLongPress() }
        return true
    }

    func mouseUp(button: Int) -> Bool {
        if swallowedUps.remove(button) != nil { return true }
        guard let p = press, p.button == button else { return false }

        press = nil
        cancelLongPress()
        if p.cursorHeld { CGAssociateMouseAndMouseCursorPosition(1) }
        if p.panning { ScrollEngine.shared.endPan() }

        if !p.consumed {
            if let b = p.binding(.click) {
                perform(b.action)
            } else if !p.isVirtual {
                // Nothing claimed the press: replay the original click.
                EventPoster.click(button: button, flags: p.flags)
            }
        }
        return true
    }

    func mouseMoved(dx: Double, dy: Double, isDrag: Bool) -> Bool {
        guard var p = press else { return false }
        // Diverted Logitech buttons don't produce drag events, only plain moves.
        guard isDrag || p.isVirtual else { return false }
        defer { press = p }

        p.travel += abs(dx) + abs(dy)

        if p.panning {
            ScrollEngine.shared.pan(dx: dx, dy: dy)
            return isDrag
        }
        if p.panEnabled && !p.consumed && p.travel > 4 {
            p.panning = true
            p.consumed = true
            cancelLongPress()
            ScrollEngine.shared.beginPan()
            ScrollEngine.shared.pan(dx: dx, dy: dy)
            return isDrag
        }

        guard p.hasDragBindings, !p.gestureDone, !p.longPressActive else { return isDrag }
        p.accX += dx
        p.accY += dy
        let threshold = max(5, settings.dragThreshold)
        guard max(abs(p.accX), abs(p.accY)) >= threshold else { return isDrag }

        let kind: TriggerKind
        if abs(p.accX) > abs(p.accY) {
            kind = p.accX > 0 ? .dragRight : .dragLeft
        } else {
            kind = p.accY > 0 ? .dragDown : .dragUp
        }
        p.accX = 0
        p.accY = 0
        if let b = p.binding(kind) {
            p.consumed = true
            cancelLongPress()
            if !b.repeats { p.gestureDone = true }
            perform(b.action)
        }
        return isDrag
    }

    func scrollWheel(deltaY: Int) -> Bool {
        guard var p = press, deltaY != 0 else { return false }
        guard let b = p.binding(deltaY > 0 ? .scrollUp : .scrollDown) else { return false }
        p.consumed = true
        press = p
        cancelLongPress()
        perform(b.action)
        return true
    }

    /// Entry point for buttons diverted through Logitech HID++.
    func virtualButton(_ button: Int, down: Bool) {
        if down {
            _ = mouseDown(button: button, flags: EventPoster.currentFlags,
                          location: EventPoster.cursorLocation, isVirtual: true)
        } else {
            _ = mouseUp(button: button)
        }
    }

    // MARK: Long press

    private func scheduleLongPress() {
        cancelLongPress()
        let delay = max(50, settings.longPressDelay)
        let interval = max(30, settings.longPressInterval)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(Int(delay)), repeating: .milliseconds(Int(interval)))
        timer.setEventHandler { [weak self] in self?.longPressFired() }
        timer.resume()
        longPressTimer = timer
    }

    private func cancelLongPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    private func longPressFired() {
        guard var p = press, let b = p.binding(.longPress), !(p.consumed && !p.longPressActive) else {
            cancelLongPress()
            return
        }
        p.consumed = true
        p.longPressActive = true
        press = p
        if !b.repeats { cancelLongPress() }
        perform(b.action)
    }

    private func perform(_ action: Action) {
        ActionExecutor.shared.perform(action)
    }
}
