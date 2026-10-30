import Foundation

/// Adjusts pointer speed and acceleration of connected mice through the HID event system.
final class CursorController {
    static let shared = CursorController()

    private typealias CreateClient = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias ConformsTo = @convention(c) (UnsafeRawPointer, UInt32, UInt32) -> UInt8
    private typealias SetProperty = @convention(c) (UnsafeRawPointer, CFString, CFTypeRef) -> UInt8
    private typealias CopyProperty = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?

    private var client: UnsafeMutableRawPointer?
    private var copyServices: CopyServices?
    private var conformsTo: ConformsTo?
    private var setProperty: SetProperty?
    private var copyProperty: CopyProperty?

    private var timer: Timer?
    private var applied = false

    private static let defaultResolution = 400.0
    private static let fixedOne = 65536.0

    private init() {
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
            return unsafeBitCast(sym, to: type)
        }
        if let create = load("IOHIDEventSystemClientCreateSimpleClient", as: CreateClient.self) {
            client = create(kCFAllocatorDefault)
        }
        copyServices = load("IOHIDEventSystemClientCopyServices", as: CopyServices.self)
        conformsTo = load("IOHIDServiceClientConformsTo", as: ConformsTo.self)
        setProperty = load("IOHIDServiceClientSetProperty", as: SetProperty.self)
        copyProperty = load("IOHIDServiceClientCopyProperty", as: CopyProperty.self)
    }

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

    func restore() {
        let scaling = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.mouse.scaling"]
        let acceleration = (scaling as? Double) ?? (scaling as? NSNumber)?.doubleValue ?? 0.6875
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
        guard let client, let copyServices, let conformsTo, let setProperty,
              let services = copyServices(client)?.takeRetainedValue()
        else { return }

        let resolutionValue = NSNumber(value: Int(max(10, min(4000, resolution)) * Self.fixedOne))
        let accelerationValue = NSNumber(value: Int(acceleration * Self.fixedOne))

        for i in 0..<CFArrayGetCount(services) {
            guard let service = CFArrayGetValueAtIndex(services, i) else { continue }
            // Generic Desktop / Mouse
            guard conformsTo(service, 0x01, 0x02) != 0 else { continue }
            let accelerationKey = accelerationType(of: service) ?? "HIDMouseAcceleration"
            // Leave trackpads alone; they have their own settings.
            if accelerationKey == "HIDTrackpadAcceleration" { continue }
            _ = setProperty(service, "HIDPointerResolution" as CFString, resolutionValue)
            _ = setProperty(service, accelerationKey as CFString, accelerationValue)
        }
    }

    private func accelerationType(of service: UnsafeRawPointer) -> String? {
        guard let copyProperty,
              let value = copyProperty(service, "HIDPointerAccelerationType" as CFString)?.takeRetainedValue()
        else { return nil }
        return value as? String
    }
}
