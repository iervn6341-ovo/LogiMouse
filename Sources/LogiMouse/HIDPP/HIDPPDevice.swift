import Foundation

/// HID++ 2.0 feature IDs used by LogiMouse.
enum HIDPPFeature {
    static let root: UInt16 = 0x0000
    static let deviceName: UInt16 = 0x0005
    static let batteryStatus: UInt16 = 0x1000
    static let unifiedBattery: UInt16 = 0x1004
    static let reprogControlsV4: UInt16 = 0x1B04
    static let wirelessStatus: UInt16 = 0x1D4B
    static let smartShift: UInt16 = 0x2110
    static let smartShiftEnhanced: UInt16 = 0x2111
    static let adjustableDPI: UInt16 = 0x2201
}

enum LogiControlNames {
    private static let names: [UInt16: String] = [
        0x0050: "Left Button",
        0x0051: "Right Button",
        0x0052: "Middle Button",
        0x0053: "Back Button",
        0x0056: "Forward Button",
        0x005B: "Wheel Tilt Left",
        0x005D: "Wheel Tilt Right",
        0x00C3: "Gesture Button",
        0x00C4: "Mode Shift Button",
        0x00D7: "Virtual Gesture Button",
        0x00FD: "DPI Switch",
    ]

    static func name(_ cid: UInt16) -> String {
        if let name = names[cid] { return L(name) }
        return String(format: "Control 0x%04X", cid)
    }
}

struct DPIRange: Equatable {
    var values: [Int]
    var step: Int?

    var min: Int { values.min() ?? 400 }
    var max: Int { values.max() ?? 4000 }
}

struct ReprogControl: Identifiable, Equatable {
    let cid: UInt16
    let persistentlyDivertable: Bool
    var id: UInt16 { cid }
    var name: String { LogiControlNames.name(cid) }
}

/// One HID++ 2.0 device, either behind a receiver (index 1…6) or directly connected (index 0xFF).
@MainActor
final class HIDPPDevice: ObservableObject, Identifiable {
    let transport: HIDPPTransport
    let index: UInt8
    nonisolated let id: String

    @Published private(set) var name: String
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var dpi: Int?
    @Published private(set) var dpiRange: DPIRange?
    @Published private(set) var wheelMode: WheelMode?
    @Published private(set) var smartShiftThreshold = 30
    @Published private(set) var controls: [ReprogControl] = []
    @Published private(set) var diverted: Set<UInt16> = []

    private var features: [UInt16: UInt8] = [:]
    private var pressedControls: Set<UInt16> = []
    private var smartShiftTorque: UInt8 = 0

    init(transport: HIDPPTransport, index: UInt8, idPrefix: String) {
        self.transport = transport
        self.index = index
        self.id = "\(idPrefix)-\(index)"
        self.name = transport.productName
    }

    var supportsDPI: Bool { features[HIDPPFeature.adjustableDPI] != nil }
    var supportsSmartShift: Bool {
        features[HIDPPFeature.smartShift] != nil || features[HIDPPFeature.smartShiftEnhanced] != nil
    }

    private var savedSettings: LogiDeviceSettings {
        get { SettingsStore.shared.settings.logi[name] ?? LogiDeviceSettings() }
        set { SettingsStore.shared.settings.logi[name] = newValue }
    }

    // MARK: Requests

    private func call(_ feature: UInt16, _ function: UInt8, _ params: [UInt8] = []) async throws -> [UInt8] {
        guard let featureIndex = features[feature] else { throw HIDPPError.unsupported }
        return try await transport.request(deviceIndex: index, feature: featureIndex, function: function, params: params)
    }

    /// Pings the device and discovers its features. Returns false when nothing HID++ 2.0 answers.
    func probe() async -> Bool {
        do {
            let ping = try await transport.request(deviceIndex: index, feature: 0x00, function: 0x1,
                                                   params: [0, 0, 0xAA], timeout: 1)
            guard let major = ping.first, major >= 2 else { return false }
        } catch {
            return false
        }

        let wanted = [HIDPPFeature.deviceName, HIDPPFeature.batteryStatus, HIDPPFeature.unifiedBattery,
                      HIDPPFeature.reprogControlsV4, HIDPPFeature.wirelessStatus, HIDPPFeature.smartShift,
                      HIDPPFeature.smartShiftEnhanced, HIDPPFeature.adjustableDPI]
        for feature in wanted {
            let params = [UInt8(feature >> 8), UInt8(feature & 0xFF)]
            if let r = try? await transport.request(deviceIndex: index, feature: 0x00, function: 0x0, params: params),
               let featureIndex = r.first, featureIndex != 0 {
                features[feature] = featureIndex
            }
        }

        await readName()
        await refreshBattery()
        await readDPI()
        await readSmartShift()
        await readControls()
        await applySavedSettings()
        return true
    }

    private func readName() async {
        guard let lengthResponse = try? await call(HIDPPFeature.deviceName, 0), let length = lengthResponse.first,
              length > 0
        else { return }
        var bytes: [UInt8] = []
        while bytes.count < Int(length) {
            guard let chunk = try? await call(HIDPPFeature.deviceName, 1, [UInt8(bytes.count)]) else { break }
            bytes += chunk.prefix(Int(length) - bytes.count)
        }
        if let decoded = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters),
           !decoded.isEmpty {
            name = decoded
        }
    }

    func refreshBattery() async {
        if let r = try? await call(HIDPPFeature.unifiedBattery, 1), r.count >= 3 {
            battery = Int(r[0])
            charging = r[2] == 1 || r[2] == 2
        } else if let r = try? await call(HIDPPFeature.batteryStatus, 0), r.count >= 3 {
            battery = Int(r[0])
            charging = r[2] >= 1 && r[2] <= 3
        }
    }

    // MARK: DPI

    private func readDPI() async {
        guard supportsDPI else { return }
        var values: [Int] = []
        var step: Int?
        if let list = try? await call(HIDPPFeature.adjustableDPI, 1, [0]) {
            var i = 1
            while i + 1 < list.count {
                let value = Int(list[i]) << 8 | Int(list[i + 1])
                if value == 0 { break }
                if value & 0xE000 == 0xE000 {
                    step = value & 0x1FFF
                } else {
                    values.append(value)
                }
                i += 2
            }
        }
        if !values.isEmpty { dpiRange = DPIRange(values: values, step: step) }
        if let current = try? await call(HIDPPFeature.adjustableDPI, 2, [0]), current.count >= 3 {
            dpi = Int(current[1]) << 8 | Int(current[2])
        }
    }

    func setDPI(_ value: Int) async {
        let clamped = UInt16(clamping: value)
        guard (try? await call(HIDPPFeature.adjustableDPI, 3, [0, UInt8(clamped >> 8), UInt8(clamped & 0xFF)])) != nil
        else { return }
        dpi = Int(clamped)
        savedSettings.dpi = Int(clamped)
    }

    // MARK: SmartShift

    private func readSmartShift() async {
        let response: [UInt8]?
        if features[HIDPPFeature.smartShiftEnhanced] != nil {
            response = try? await call(HIDPPFeature.smartShiftEnhanced, 1)
        } else {
            response = try? await call(HIDPPFeature.smartShift, 0)
        }
        guard let r = response, r.count >= 2 else { return }
        if r.count >= 3 { smartShiftTorque = r[2] }
        switch (r[0], r[1]) {
        case (1, _): wheelMode = .freeSpin
        case (_, 0xFF): wheelMode = .ratchet
        default:
            wheelMode = .smartShift
            if r[1] > 0 { smartShiftThreshold = Int(r[1]) }
        }
    }

    func setWheel(mode: WheelMode, threshold: Int) async {
        let modeByte: UInt8 = mode == .freeSpin ? 1 : 2
        let thresholdByte: UInt8 = mode == .ratchet ? 0xFF : UInt8(clamping: max(1, min(254, threshold)))
        let ok: Bool
        if features[HIDPPFeature.smartShiftEnhanced] != nil {
            ok = (try? await call(HIDPPFeature.smartShiftEnhanced, 2, [modeByte, thresholdByte, smartShiftTorque])) != nil
        } else {
            ok = (try? await call(HIDPPFeature.smartShift, 1, [modeByte, thresholdByte, 0])) != nil
        }
        guard ok else { return }
        wheelMode = mode
        if mode == .smartShift { smartShiftThreshold = Int(thresholdByte) }
        var saved = savedSettings
        saved.wheelMode = mode
        saved.smartShiftThreshold = smartShiftThreshold
        savedSettings = saved
    }

    // MARK: Button diversion

    private func readControls() async {
        guard let countResponse = try? await call(HIDPPFeature.reprogControlsV4, 0),
              let count = countResponse.first
        else { return }
        var list: [ReprogControl] = []
        for i in 0..<count {
            guard let r = try? await call(HIDPPFeature.reprogControlsV4, 1, [i]), r.count >= 9 else { continue }
            let cid = UInt16(r[0]) << 8 | UInt16(r[1])
            let flags = UInt16(r[4]) | UInt16(r[8]) << 8
            let divertable = flags & 0x20 != 0
            // Never offer to take over the primary buttons.
            guard divertable, cid != 0x50, cid != 0x51 else { continue }
            list.append(ReprogControl(cid: cid, persistentlyDivertable: flags & 0x40 != 0))
        }
        controls = list
    }

    func setDiverted(_ cid: UInt16, _ on: Bool) async {
        let params: [UInt8] = [UInt8(cid >> 8), UInt8(cid & 0xFF), on ? 0x03 : 0x02, 0, 0]
        guard (try? await call(HIDPPFeature.reprogControlsV4, 3, params)) != nil else { return }
        if on {
            diverted.insert(cid)
        } else {
            diverted.remove(cid)
            if pressedControls.remove(cid) != nil {
                ButtonEngine.shared.virtualButton(ButtonNames.virtualBase + Int(cid), down: false)
            }
        }
        var saved = savedSettings
        saved.divertedControls = Array(diverted).sorted()
        savedSettings = saved
    }

    /// Hands every diverted control back to the device firmware.
    func releaseDiversions() async {
        for cid in diverted {
            let params: [UInt8] = [UInt8(cid >> 8), UInt8(cid & 0xFF), 0x02, 0, 0]
            _ = try? await call(HIDPPFeature.reprogControlsV4, 3, params)
        }
    }

    // MARK: Saved state

    /// Re-applies DPI, wheel mode and diversions; the device forgets them when it reconnects.
    func applySavedSettings() async {
        let saved = savedSettings
        if let dpi = saved.dpi, supportsDPI, dpi != self.dpi {
            await setDPI(dpi)
        }
        if let mode = saved.wheelMode, supportsSmartShift {
            await setWheel(mode: mode, threshold: saved.smartShiftThreshold ?? smartShiftThreshold)
        }
        let available = Set(controls.map(\.cid))
        for cid in saved.divertedControls where available.contains(cid) {
            await setDiverted(cid, true)
        }
    }

    // MARK: Notifications

    func handleNotification(_ bytes: [UInt8]) {
        guard bytes.count >= 8, bytes[0] == HIDPPTransport.longReportID, bytes[3] & 0x0F == 0 else { return }
        let function = bytes[3] >> 4

        if let reprog = features[HIDPPFeature.reprogControlsV4], bytes[2] == reprog, function == 0 {
            var now = Set<UInt16>()
            for i in stride(from: 4, to: min(12, bytes.count - 1), by: 2) {
                let cid = UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
                if cid != 0 { now.insert(cid) }
            }
            let released = pressedControls.subtracting(now)
            let pressed = now.subtracting(pressedControls)
            pressedControls = now
            for cid in released {
                ButtonEngine.shared.virtualButton(ButtonNames.virtualBase + Int(cid), down: false)
            }
            for cid in pressed {
                ButtonEngine.shared.virtualButton(ButtonNames.virtualBase + Int(cid), down: true)
            }
            return
        }

        if let wireless = features[HIDPPFeature.wirelessStatus], bytes[2] == wireless, function == 0 {
            Task { await self.applySavedSettings() }
            return
        }

        if let unified = features[HIDPPFeature.unifiedBattery], bytes[2] == unified, function == 0 {
            battery = Int(bytes[4])
            charging = bytes[6] == 1 || bytes[6] == 2
        } else if let status = features[HIDPPFeature.batteryStatus], bytes[2] == status, function == 0 {
            battery = Int(bytes[4])
            charging = bytes[6] >= 1 && bytes[6] <= 3
        }
    }
}
