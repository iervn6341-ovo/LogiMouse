import Foundation

/// Adjusts pointer speed and acceleration of connected mice through the HID event system.
final class CursorController {
    static let shared = CursorController()

    private var timer: Timer?
    private var applied = false

    private static let defaultResolution = 400.0
    private static let fixedOne = 65536.0

    func apply(_ settings: CursorSettings) {
        guard settings.enabled else {
            if applied { restore() }
            timer?.invalidate()
            timer = nil
            return
        }
        applyNow(settings)
        if timer == nil {
            // Re-apply periodically so mice connected later pick up the settings too.
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.applyNow(SettingsStore.shared.settings.cursor)
            }
        }
    }

    func restoreIfApplied() {
        if applied { restore() }
    }

    func restore() {
        let scaling = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.mouse.scaling"]
        let acceleration = (scaling as? NSNumber)?.doubleValue ?? 0.6875
        write(resolution: Self.defaultResolution, acceleration: acceleration)
        applied = false
    }

    private func applyNow(_ settings: CursorSettings) {
        let speed = max(0.1, min(10, settings.speed))
        let acceleration = settings.disableAcceleration ? -1 : max(0, settings.acceleration)
        write(resolution: Self.defaultResolution / speed, acceleration: acceleration)
        applied = true
    }

    private func write(resolution: Double, acceleration: Double) {
        let hid = HIDServices.shared
        let resolutionValue = NSNumber(value: Int(max(10, min(4000, resolution)) * Self.fixedOne))
        let accelerationValue = NSNumber(value: Int(acceleration * Self.fixedOne))

        for service in hid.services(usage: 0x02) {
            let accelerationKey = hid.property(service, "HIDPointerAccelerationType") as? String ?? "HIDMouseAcceleration"
            // Leave trackpads alone; they have their own settings.
            if accelerationKey == "HIDTrackpadAcceleration" { continue }
            hid.setProperty(service, "HIDPointerResolution", resolutionValue)
            hid.setProperty(service, accelerationKey, accelerationValue)
        }
    }
}
