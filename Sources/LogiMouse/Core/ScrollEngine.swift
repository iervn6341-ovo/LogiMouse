import CoreGraphics
import Foundation
import QuartzCore

/// Smooth scrolling, wheel acceleration, direction inversion, modifier scrolling and pan momentum.
final class ScrollEngine {
    static let shared = ScrollEngine()

    private var pendingX = 0.0
    private var pendingY = 0.0
    private var velocityX = 0.0
    private var velocityY = 0.0
    private var momentumX = 0.0
    private var momentumY = 0.0
    private var remainderX = 0.0
    private var remainderY = 0.0

    private var postFlags: CGEventFlags = []
    private var lastTickTime = 0.0
    private var lastTickSign = 0
    private var streak = 0

    private var panSamples: [(time: Double, dx: Double, dy: Double)] = []

    private var timer: DispatchSourceTimer?
    private var lastFrame = 0.0

    private var settings: ScrollSettings { SettingsStore.shared.settings.scroll }

    // MARK: Wheel events

    /// Returns the event to pass on, or nil when it was consumed.
    func handle(_ event: CGEvent) -> CGEvent? {
        let s = settings
        let context = SettingsStore.shared.currentContext
        guard !context.disabled else { return event }

        // Trackpads, Magic Mouse and other continuous devices already scroll smoothly.
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return event }

        var y = Axis(event: event, axis: 1)
        var x = Axis(event: event, axis: 2)
        guard !y.isZero || !x.isZero else { return event }

        let mods = ModifierSet(cgFlags: event.flags)
        var flags = event.flags

        if s.invertVertical { y.scale(-1) }
        if s.invertHorizontal { x.scale(-1) }
        x.scale(s.horizontalSpeed)

        if s.zoomEnabled, !s.zoomModifier.isEmpty, mods.isSuperset(of: s.zoomModifier), !y.isZero {
            let zoomIn = (y.direction > 0) != s.zoomInvert
            ActionExecutor.shared.zoom(in: zoomIn)
            return nil
        }

        var multiplier = 1.0
        if s.fastEnabled, !s.fastModifier.isEmpty, mods.isSuperset(of: s.fastModifier) {
            multiplier = s.fastMultiplier
            flags.remove(s.fastModifier.cgFlags)
        }

        if s.horizontalEnabled, !s.horizontalModifier.isEmpty, mods.isSuperset(of: s.horizontalModifier), !y.isZero {
            x = y
            if s.horizontalInvert { x.scale(-1) }
            y = Axis()
            flags.remove(s.horizontalModifier.cgFlags)
        }

        guard context.smoothScroll else {
            y.scale(multiplier * s.lineMultiplier)
            x.scale(multiplier * s.lineMultiplier)
            y.write(to: event, axis: 1)
            x.write(to: event, axis: 2)
            event.flags = flags
            return event
        }

        postFlags = flags
        let now = CACurrentMediaTime()
        let step = s.step * multiplier
        if y.direction != 0 {
            let factor = accelerationFactor(sign: y.direction, now: now)
            if pendingY != 0 && (pendingY > 0) != (y.direction > 0) { pendingY = 0; velocityY = 0 }
            pendingY += Double(y.direction) * step * factor
        }
        if x.direction != 0 {
            let factor = y.direction == 0 ? accelerationFactor(sign: x.direction * 2, now: now) : 1
            if pendingX != 0 && (pendingX > 0) != (x.direction > 0) { pendingX = 0; velocityX = 0 }
            pendingX += Double(x.direction) * step * factor
        }
        momentumX = 0
        momentumY = 0
        startTimer()
        return nil
    }

    /// Scrolls by a number of wheel ticks; used by the scroll actions.
    func impulse(ticksX: Int, ticksY: Int) {
        let s = settings
        guard s.smooth else {
            EventPoster.scrollLines(x: Int32(ticksX * 3), y: Int32(ticksY * 3))
            return
        }
        postFlags = []
        pendingX += Double(ticksX) * s.step
        pendingY += Double(ticksY) * s.step
        startTimer()
    }

    private func accelerationFactor(sign: Int, now: Double) -> Double {
        if sign == lastTickSign && now - lastTickTime < 0.12 {
            streak += 1
        } else {
            streak = 0
        }
        lastTickSign = sign
        lastTickTime = now
        let a = max(0, min(10, settings.acceleration))
        return 1 + a * 0.04 * pow(Double(min(streak, 40)), 1.25)
    }

    // MARK: Pan

    func beginPan() {
        pendingX = 0; pendingY = 0
        velocityX = 0; velocityY = 0
        momentumX = 0; momentumY = 0
        panSamples.removeAll()
    }

    func pan(dx: Double, dy: Double) {
        let pan = SettingsStore.shared.settings.buttons.pan
        let s = settings
        var speed = pan.speed * (pan.invert ? -1 : 1)
        var flags = EventPoster.currentFlags
        if s.fastEnabled, !s.fastModifier.isEmpty, ModifierSet(cgFlags: flags).isSuperset(of: s.fastModifier) {
            speed *= s.fastMultiplier
            flags.remove(s.fastModifier.cgFlags)
        }
        let px = dx * speed
        let py = dy * speed
        let now = CACurrentMediaTime()
        panSamples.append((time: now, dx: px, dy: py))
        panSamples.removeAll { now - $0.time > 0.1 }
        postFlags = flags
        emit(x: px, y: py)
    }

    func endPan() {
        defer { panSamples.removeAll() }
        guard SettingsStore.shared.settings.buttons.pan.momentum else { return }
        let now = CACurrentMediaTime()
        let recent = panSamples.filter { now - $0.time < 0.08 }
        guard let first = recent.first, let last = recent.last, recent.count >= 2, now - last.time < 0.05 else { return }
        let span = max(1.0 / 60.0, now - first.time)
        momentumX = recent.reduce(0) { $0 + $1.dx } / span
        momentumY = recent.reduce(0) { $0 + $1.dy } / span
        startTimer()
    }

    // MARK: Animation

    private func startTimer() {
        guard timer == nil else { return }
        lastFrame = CACurrentMediaTime()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 120), leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.frame() }
        t.resume()
        timer = t
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
        pendingX = 0; pendingY = 0
        velocityX = 0; velocityY = 0
        momentumX = 0; momentumY = 0
        remainderX = 0; remainderY = 0
    }

    private func frame() {
        let now = CACurrentMediaTime()
        let dt = max(1.0 / 240.0, min(1.0 / 20.0, now - lastFrame))
        lastFrame = now

        let s = settings
        let tau = max(0.02, s.duration / 1000 / 3)
        let k = 1 - exp(-dt / tau)

        var outX = pendingX * k
        var outY = pendingY * k
        if s.moreSmooth {
            velocityX += (outX - velocityX) * 0.35
            velocityY += (outY - velocityY) * 0.35
            outX = clampToward(velocityX, limit: pendingX)
            outY = clampToward(velocityY, limit: pendingY)
        }
        pendingX -= outX
        pendingY -= outY

        outX += momentumX * dt
        outY += momentumY * dt
        let decay = exp(-dt * 3.2)
        momentumX *= decay
        momentumY *= decay

        emit(x: outX, y: outY)

        let idle = abs(pendingX) < 0.5 && abs(pendingY) < 0.5
            && abs(momentumX) < 15 && abs(momentumY) < 15
        if idle {
            emit(x: pendingX, y: pendingY)
            stopTimer()
        }
    }

    private func clampToward(_ value: Double, limit: Double) -> Double {
        if limit >= 0 { return max(0, min(value, limit)) }
        return min(0, max(value, limit))
    }

    private func emit(x: Double, y: Double) {
        remainderX += x
        remainderY += y
        let ix = remainderX.rounded(.towardZero)
        let iy = remainderY.rounded(.towardZero)
        remainderX -= ix
        remainderY -= iy
        guard ix != 0 || iy != 0 else { return }
        EventPoster.scrollPixels(x: Int32(clamping: Int(ix)), y: Int32(clamping: Int(iy)), flags: postFlags)
    }
}

/// The three delta representations a wheel event carries for one axis.
private struct Axis {
    var line = 0.0
    var fixed = 0.0
    var point = 0.0

    init() {}

    init(event: CGEvent, axis: Int) {
        switch axis {
        case 1:
            line = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            point = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        default:
            line = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            point = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        }
    }

    var isZero: Bool { line == 0 && fixed == 0 && point == 0 }

    var direction: Int {
        let v = line != 0 ? line : (fixed != 0 ? fixed : point)
        return v > 0 ? 1 : (v < 0 ? -1 : 0)
    }

    mutating func scale(_ factor: Double) {
        line *= factor
        fixed *= factor
        point *= factor
    }

    func write(to event: CGEvent, axis: Int) {
        // Keep at least one line so slow multipliers don't swallow ticks entirely.
        var lineValue = line.rounded()
        if lineValue == 0 && line != 0 { lineValue = line > 0 ? 1 : -1 }
        switch axis {
        case 1:
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(lineValue))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: fixed)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(point.rounded()))
        default:
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(lineValue))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(point.rounded()))
        }
    }
}
