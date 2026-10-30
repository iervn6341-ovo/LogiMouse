import Foundation

/// High-resolution wheel, thumb wheel, onboard profiles and report rate.
extension HIDPPDevice {
    var supportsHiResWheel: Bool { features[HIDPPFeature.hiResWheel] != nil }
    var supportsThumbWheel: Bool { features[HIDPPFeature.thumbWheel] != nil }

    func readExtras() async {
        if supportsHiResWheel {
            if let caps = try? await call(HIDPPFeature.hiResWheel, 0), let multiplier = caps.first, multiplier > 0 {
                hiResMultiplier = Int(multiplier)
            }
            if let mode = try? await call(HIDPPFeature.hiResWheel, 1), let flags = mode.first {
                hiResEnabled = flags & 0x01 != 0 && flags & 0x02 != 0
            }
        }
        if supportsThumbWheel {
            if let info = try? await call(HIDPPFeature.thumbWheel, 0), info.count >= 4 {
                let diverted = Int(info[2]) << 8 | Int(info[3])
                if diverted > 0 { thumbWheelResolution = diverted }
            }
            thumbWheelMode = savedSettings.thumbWheelMode ?? .native
        }
        if features[HIDPPFeature.onboardProfiles] != nil,
           let mode = try? await call(HIDPPFeature.onboardProfiles, 2), let m = mode.first {
            onboardProfilesEnabled = m == 1
        }
        if features[HIDPPFeature.reportRate] != nil {
            if let list = try? await call(HIDPPFeature.reportRate, 0), let mask = list.first {
                reportRates = (0..<8).filter { mask & (1 << $0) != 0 }.map { $0 + 1 }
            }
            if let current = try? await call(HIDPPFeature.reportRate, 1), let ms = current.first, ms > 0 {
                reportRate = Int(ms)
            }
        }
    }

    func applyExtras(_ saved: LogiDeviceSettings) async {
        if let onboard = saved.onboardProfiles, onboardProfilesEnabled != nil, onboard != onboardProfilesEnabled {
            await setOnboardProfiles(onboard)
        }
        if let rate = saved.reportRate, !reportRates.isEmpty, rate != reportRate {
            await setReportRate(rate)
        }
        if let hiRes = saved.hiResWheel, supportsHiResWheel {
            await setHiResWheel(hiRes)
        }
        if supportsThumbWheel {
            await setThumbWheel(saved.thumbWheelMode ?? .native)
        }
    }

    /// Hands the wheels back to the firmware.
    func releaseExtras() async {
        if supportsHiResWheel, hiResEnabled == true {
            _ = try? await call(HIDPPFeature.hiResWheel, 2, [0x00])
        }
        if supportsThumbWheel, thumbWheelMode != .native {
            _ = try? await call(HIDPPFeature.thumbWheel, 2, [0, 0])
        }
    }

    // MARK: High-resolution wheel

    /// Diverts the main wheel at full resolution so LogiMouse can turn it into finely grained scrolling.
    func setHiResWheel(_ on: Bool) async {
        // bit0: report through HID++, bit1: high resolution.
        let mode: UInt8 = on ? 0x03 : 0x00
        guard (try? await call(HIDPPFeature.hiResWheel, 2, [mode])) != nil else { return }
        hiResEnabled = on
        var saved = savedSettings
        saved.hiResWheel = on
        savedSettings = saved
    }

    // MARK: Thumb wheel

    func setThumbWheel(_ mode: ThumbWheelMode) async {
        let divert: UInt8 = mode == .native ? 0 : 1
        guard (try? await call(HIDPPFeature.thumbWheel, 2, [divert, 0])) != nil else { return }
        thumbWheelMode = mode
        thumbWheelAccumulator = 0
        var saved = savedSettings
        saved.thumbWheelMode = mode
        savedSettings = saved
    }

    func setThumbWheelOptions(invert: Bool, speed: Double) {
        var saved = savedSettings
        saved.thumbWheelInvert = invert
        saved.thumbWheelSpeed = speed
        savedSettings = saved
    }

    // MARK: Onboard profiles & report rate

    func setOnboardProfiles(_ on: Bool) async {
        guard (try? await call(HIDPPFeature.onboardProfiles, 1, [on ? 1 : 2])) != nil else { return }
        onboardProfilesEnabled = on
        var saved = savedSettings
        saved.onboardProfiles = on
        savedSettings = saved
        // The host-mode report rate may differ from the profile's.
        if let current = try? await call(HIDPPFeature.reportRate, 1), let ms = current.first, ms > 0 {
            reportRate = Int(ms)
        }
    }

    func setReportRate(_ milliseconds: Int) async {
        guard (try? await call(HIDPPFeature.reportRate, 2, [UInt8(clamping: milliseconds)])) != nil else { return }
        reportRate = milliseconds
        var saved = savedSettings
        saved.reportRate = milliseconds
        savedSettings = saved
    }

    // MARK: Notifications

    /// Returns true when the notification belonged to one of these features.
    func handleExtrasNotification(_ bytes: [UInt8], function: UInt8) -> Bool {
        if let index = features[HIDPPFeature.hiResWheel], bytes[2] == index, function == 0 {
            let flags = bytes[4]
            let delta = Double(Int16(bitPattern: UInt16(bytes[5]) << 8 | UInt16(bytes[6])))
            let highResolution = flags & 0x10 != 0
            var ticks = delta / Double(highResolution ? max(1, hiResMultiplier) : 1)
            // Synthesized events skip the system's natural-scrolling inversion, so apply it here.
            if Self.naturalScrolling { ticks = -ticks }
            ScrollEngine.shared.externalWheel(ticksY: ticks, ticksX: 0)
            return true
        }

        if let index = features[HIDPPFeature.thumbWheel], bytes[2] == index, function == 0, bytes.count >= 10 {
            let rotation = Double(Int16(bitPattern: UInt16(bytes[4]) << 8 | UInt16(bytes[5])))
            let flags = bytes[9]
            handleThumbWheel(rotation: rotation, tapped: flags & 0x04 != 0)
            return true
        }
        return false
    }

    private func handleThumbWheel(rotation: Double, tapped: Bool) {
        let saved = savedSettings
        let mode = thumbWheelMode ?? .native

        if mode == .buttons {
            if tapped && !thumbWheelTouching {
                ButtonEngine.shared.virtualButton(ButtonNames.thumbWheelTap, down: true)
                ButtonEngine.shared.virtualButton(ButtonNames.thumbWheelTap, down: false)
            }
            thumbWheelTouching = tapped
        }
        guard rotation != 0, mode != .native else { return }

        // About 18 "ticks" per full turn, scaled by the user's speed.
        var ticks = rotation / Double(max(1, thumbWheelResolution)) * 18 * saved.thumbWheelSpeed
        if saved.thumbWheelInvert { ticks = -ticks }

        switch mode {
        case .native:
            break
        case .horizontalScroll:
            ScrollEngine.shared.externalWheel(ticksY: 0, ticksX: -ticks, applyInversion: false)
        case .verticalScroll:
            ScrollEngine.shared.externalWheel(ticksY: ticks, ticksX: 0, applyInversion: false)
        case .zoom:
            ScrollEngine.shared.zoom(by: ticks / 2)
        case .buttons:
            if thumbWheelAccumulator != 0 && (thumbWheelAccumulator > 0) != (ticks > 0) { thumbWheelAccumulator = 0 }
            thumbWheelAccumulator += ticks
            while abs(thumbWheelAccumulator) >= 2 {
                let right = thumbWheelAccumulator > 0
                let button = right ? ButtonNames.thumbWheelRight : ButtonNames.thumbWheelLeft
                ButtonEngine.shared.virtualButton(button, down: true)
                ButtonEngine.shared.virtualButton(button, down: false)
                thumbWheelAccumulator += right ? -2 : 2
            }
        }
    }

    private static var naturalScrollingCache: (value: Bool, time: TimeInterval)?

    /// The system "natural scrolling" setting, re-read at most every few seconds.
    static var naturalScrolling: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if let cache = naturalScrollingCache, now - cache.time < 3 { return cache.value }
        let value = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.swipescrolldirection"]
        let natural = (value as? NSNumber)?.boolValue ?? true
        naturalScrollingCache = (natural, now)
        return natural
    }
}
