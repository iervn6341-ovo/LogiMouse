import Foundation
import IOKit.hid

enum HIDPPError: Error {
    case io(IOReturn)
    case timeout
    case protocolError(UInt8)
    case unsupported
}

/// Sends HID++ long reports to one IOHIDDevice (a receiver or a directly connected device)
/// and matches the responses.
@MainActor
final class HIDPPTransport {
    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let longReportLength = 20

    let device: IOHIDDevice
    let isReceiver: Bool
    let productID: Int
    let productName: String
    var notificationHandler: (([UInt8]) -> Void)?

    private let inputBuffer: UnsafeMutablePointer<UInt8>
    private static let inputBufferSize = 64
    private var pending: [UInt32: (Result<[UInt8], HIDPPError>) -> Void] = [:]
    private var nextSoftwareID: UInt8 = 1

    init(device: IOHIDDevice) {
        self.device = device
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech"
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        productName = product
        self.productID = productID
        isReceiver = Self.receiverProductIDs.contains(productID) || product.localizedCaseInsensitiveContains("receiver")
        inputBuffer = .allocate(capacity: Self.inputBufferSize)
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, Self.inputBufferSize, hidppInputCallback,
                                               Unmanaged.passUnretained(self).toOpaque())
    }

    func invalidate() {
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, Self.inputBufferSize, nil, nil)
        for (_, handler) in pending { handler(.failure(.timeout)) }
        pending.removeAll()
    }

    static let unifyingProductIDs: Set<Int> = [0xC52B, 0xC532]

    private static let receiverProductIDs: Set<Int> = [
        0xC52B, 0xC532, // Unifying
        0xC548, // Bolt
        0xC534, 0xC539, 0xC53A, 0xC53F, 0xC541, 0xC545, 0xC547, // Nano / Lightspeed
    ]

    /// Sends a HID++ 2.0 request and waits for its response parameters.
    func request(deviceIndex: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = [],
                 timeout: TimeInterval = 2) async throws -> [UInt8] {
        let swID = nextSoftwareID
        nextSoftwareID = nextSoftwareID >= 0x0F ? 1 : nextSoftwareID + 1

        var report = [UInt8](repeating: 0, count: Self.longReportLength)
        report[0] = Self.longReportID
        report[1] = deviceIndex
        report[2] = feature
        report[3] = (function << 4) | swID
        for (i, p) in params.prefix(Self.longReportLength - 4).enumerated() {
            report[4 + i] = p
        }
        let key = Self.key(deviceIndex, feature, report[3])

        return try await withCheckedThrowingContinuation { continuation in
            if let previous = pending.removeValue(forKey: key) { previous(.failure(.timeout)) }
            pending[key] = { continuation.resume(with: $0) }

            let result = report.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Self.longReportID),
                                     buffer.baseAddress!, buffer.count)
            }
            guard result == kIOReturnSuccess else {
                pending.removeValue(forKey: key)?(.failure(.io(result)))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.pending.removeValue(forKey: key)?(.failure(.timeout))
            }
        }
    }

    /// Writes a HID++ 1.0 short register (used for receiver pairing).
    func writeRegister(deviceIndex: UInt8, register: UInt8, params: [UInt8], timeout: TimeInterval = 2) async throws {
        var report = [UInt8](repeating: 0, count: 7)
        report[0] = Self.shortReportID
        report[1] = deviceIndex
        report[2] = 0x80
        report[3] = register
        for (i, p) in params.prefix(3).enumerated() {
            report[4 + i] = p
        }
        let key = Self.key(deviceIndex, 0x80, register)

        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], Error>) in
            if let previous = pending.removeValue(forKey: key) { previous(.failure(.timeout)) }
            pending[key] = { continuation.resume(with: $0) }
            let result = report.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(Self.shortReportID),
                                     buffer.baseAddress!, buffer.count)
            }
            guard result == kIOReturnSuccess else {
                pending.removeValue(forKey: key)?(.failure(.io(result)))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.pending.removeValue(forKey: key)?(.failure(.timeout))
            }
        }
    }

    private static func key(_ index: UInt8, _ feature: UInt8, _ functionAndSW: UInt8) -> UInt32 {
        UInt32(index) << 16 | UInt32(feature) << 8 | UInt32(functionAndSW)
    }

    fileprivate func handleInput(_ bytes: [UInt8]) {
        guard bytes.count >= 7 else { return }
        let reportID = bytes[0]
        let index = bytes[1]

        if reportID == Self.longReportID || reportID == Self.shortReportID {
            // HID++ 2.0 error: [id, index, 0xFF, feature, fn|sw, code]
            if reportID == Self.longReportID && bytes[2] == 0xFF {
                pending.removeValue(forKey: Self.key(index, bytes[3], bytes[4]))?(.failure(.protocolError(bytes[5])))
                return
            }
            // HID++ 1.0 error: [0x10, index, 0x8F, subID, address, code]
            if reportID == Self.shortReportID && bytes[2] == 0x8F {
                pending.removeValue(forKey: Self.key(index, bytes[3], bytes[4]))?(.failure(.protocolError(bytes[5])))
                return
            }
            // HID++ 1.0 register write acknowledgement: [0x10, index, 0x80, register, …]
            if reportID == Self.shortReportID,
               let handler = pending.removeValue(forKey: Self.key(index, bytes[2], bytes[3])) {
                handler(.success(Array(bytes[4...])))
                return
            }
            if reportID == Self.longReportID && bytes[3] & 0x0F != 0,
               let handler = pending.removeValue(forKey: Self.key(index, bytes[2], bytes[3])) {
                handler(.success(Array(bytes[4...])))
                return
            }
        }
        notificationHandler?(bytes)
    }
}

private let hidppInputCallback: IOHIDReportCallback = { context, _, _, _, _, report, length in
    guard let context else { return }
    let transport = Unmanaged<HIDPPTransport>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: length))
    // Devices are scheduled on the main run loop.
    MainActor.assumeIsolated {
        transport.handleInput(bytes)
    }
}
