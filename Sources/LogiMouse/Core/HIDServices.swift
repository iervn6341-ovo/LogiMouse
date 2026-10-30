import Foundation

/// Minimal access to IOHIDEventSystemClient services (the API behind `hidutil`), loaded at runtime.
final class HIDServices {
    static let shared = HIDServices()

    private typealias CreateClient = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias CopyServices = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
    private typealias ConformsTo = @convention(c) (UnsafeRawPointer, UInt32, UInt32) -> UInt8
    private typealias SetProperty = @convention(c) (UnsafeRawPointer, CFString, CFTypeRef) -> UInt8
    private typealias CopyProperty = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<CFTypeRef>?

    private var client: UnsafeMutableRawPointer?
    private var copyServices: CopyServices?
    private var conformsTo: ConformsTo?
    private var setPropertyFn: SetProperty?
    private var copyPropertyFn: CopyProperty?

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
        setPropertyFn = load("IOHIDServiceClientSetProperty", as: SetProperty.self)
        copyPropertyFn = load("IOHIDServiceClientCopyProperty", as: CopyProperty.self)
    }

    /// Services conforming to the given Generic Desktop usage (2 = mouse, 6 = keyboard).
    func services(usagePage: UInt32 = 0x01, usage: UInt32) -> [UnsafeRawPointer] {
        guard let client, let copyServices, let conformsTo,
              let array = copyServices(client)?.takeRetainedValue()
        else { return [] }
        var result: [UnsafeRawPointer] = []
        for i in 0..<CFArrayGetCount(array) {
            guard let service = CFArrayGetValueAtIndex(array, i) else { continue }
            if conformsTo(service, usagePage, usage) != 0 { result.append(service) }
        }
        // The array owned the services; keep it alive as long as the client lives.
        retainedArrays.append(array)
        if retainedArrays.count > 4 { retainedArrays.removeFirst() }
        return result
    }

    private var retainedArrays: [CFArray] = []

    @discardableResult
    func setProperty(_ service: UnsafeRawPointer, _ key: String, _ value: CFTypeRef) -> Bool {
        guard let setPropertyFn else { return false }
        return setPropertyFn(service, key as CFString, value) != 0
    }

    func property(_ service: UnsafeRawPointer, _ key: String) -> CFTypeRef? {
        guard let copyPropertyFn else { return nil }
        return copyPropertyFn(service, key as CFString)?.takeRetainedValue()
    }
}
