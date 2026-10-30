import Foundation
import IOKit.hid

/// Discovers Logitech receivers and devices that speak HID++ and keeps the device list current.
@MainActor
final class HIDPPManager: ObservableObject {
    static let shared = HIDPPManager()

    @Published private(set) var devices: [HIDPPDevice] = []

    private var manager: IOHIDManager?
    private var transports: [HIDPPTransport] = []
    private var probing = Set<String>()

    private static let logitechVendorID = 0x046D

    func start() {
        guard manager == nil else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Any]] = [
            // Receivers and USB devices expose HID++ on a vendor-defined collection.
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDDeviceUsagePageKey: 0xFF00],
            // Bluetooth LE devices.
            [kIOHIDVendorIDKey: Self.logitechVendorID, kIOHIDDeviceUsagePageKey: 0xFF43],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(m, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, hidppDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, hidppDeviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = m
    }

    func refresh() {
        for device in devices {
            Task { await device.refreshBattery() }
        }
    }

    /// Returns diverted buttons to the firmware so the mouse keeps working after we quit.
    func releaseAll() async {
        for device in devices {
            await device.releaseDiversions()
        }
    }

    fileprivate func deviceMatched(_ hidDevice: IOHIDDevice) {
        guard !transports.contains(where: { $0.device === hidDevice }) else { return }
        let transport = HIDPPTransport(device: hidDevice)
        transport.notificationHandler = { [weak self, weak transport] bytes in
            guard let self, let transport else { return }
            self.handleNotification(bytes, from: transport)
        }
        transports.append(transport)

        let indices: [UInt8] = transport.isReceiver ? Array(1...6) : [0xFF]
        for index in indices {
            probe(transport: transport, index: index)
        }
    }

    fileprivate func deviceRemoved(_ hidDevice: IOHIDDevice) {
        guard let i = transports.firstIndex(where: { $0.device === hidDevice }) else { return }
        let transport = transports.remove(at: i)
        transport.invalidate()
        devices.removeAll { $0.transport === transport }
    }

    private func transportID(_ transport: HIDPPTransport) -> String {
        let location = IOHIDDeviceGetProperty(transport.device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        return String(format: "%08X", location)
    }

    private func probe(transport: HIDPPTransport, index: UInt8) {
        let prefix = transportID(transport)
        let key = "\(prefix)-\(index)"
        guard !probing.contains(key) else { return }
        probing.insert(key)

        Task { [self] in
            defer { probing.remove(key) }
            if let existing = devices.first(where: { $0.transport === transport && $0.index == index }) {
                await existing.applySavedSettings()
                return
            }
            let device = HIDPPDevice(transport: transport, index: index, idPrefix: prefix)
            guard await device.probe() else { return }
            guard transports.contains(where: { $0 === transport }),
                  !devices.contains(where: { $0.id == device.id })
            else { return }
            devices.append(device)
        }
    }

    private func handleNotification(_ bytes: [UInt8], from transport: HIDPPTransport) {
        guard bytes.count >= 5 else { return }
        let index = bytes[1]

        // Receiver "device connection" notification (HID++ 1.0, sub ID 0x41).
        if bytes[0] == HIDPPTransport.shortReportID && bytes[2] == 0x41 {
            let linkEstablished = bytes[4] & 0x40 == 0
            if linkEstablished {
                Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    self.probe(transport: transport, index: index)
                }
            }
            return
        }

        devices.first { $0.transport === transport && $0.index == index }?.handleNotification(bytes)
    }
}

private let hidppDeviceMatched: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let manager = Unmanaged<HIDPPManager>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { manager.deviceMatched(device) }
}

private let hidppDeviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
    guard let context else { return }
    let manager = Unmanaged<HIDPPManager>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { manager.deviceRemoved(device) }
}
