import AppKit
import SwiftUI

struct MouseTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var hid = HIDPPManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: L("Cursor")) {
                    Toggle(L("Enable cursor control"), isOn: $store.settings.cursor.enabled)
                    Group {
                        SliderRow(title: L("Speed"), value: $store.settings.cursor.speed,
                                  range: 0.2...5, format: "%.2f×")
                        Toggle(L("Disable pointer acceleration"), isOn: $store.settings.cursor.disableAcceleration)
                        SliderRow(title: L("Acceleration"), value: $store.settings.cursor.acceleration,
                                  range: 0...3, format: "%.2f")
                            .disabled(store.settings.cursor.disableAcceleration)
                    }
                    .disabled(!store.settings.cursor.enabled)
                    HelpText(L("Applies to all connected mice (not trackpads). Turning cursor control off restores the system setting."))
                    Divider()
                    Toggle(L("Hold cursor still during drag gestures and panning"),
                           isOn: $store.settings.cursor.holdInGesture)
                }

                SettingsSection(title: L("Logitech Devices")) {
                    HStack {
                        HelpText(L("Logitech mice connected through a Unifying/Bolt receiver, Bluetooth or USB that speak HID++ 2.0 appear here."))
                        Spacer()
                        Button(L("Refresh")) { hid.refresh() }
                    }
                    if hid.devices.isEmpty {
                        Text(L("No Logitech HID++ device found.")).foregroundColor(.secondary)
                    }
                    ForEach(hid.devices) { device in
                        LogiDeviceView(device: device)
                        Divider()
                    }
                }

                if !hid.receivers.isEmpty {
                    SettingsSection(title: L("Receivers")) {
                        ForEach(hid.receivers) { receiver in
                            HStack {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text(receiver.name)
                                Spacer()
                                if !receiver.supportsPairing {
                                    Text(L("Pair Bolt devices with Logi Options+ or Solaar for now."))
                                        .font(.caption).foregroundColor(.secondary)
                                } else if hid.pairingReceiverID == receiver.id {
                                    ProgressView().controlSize(.small)
                                    Text(L("Turn on the device you want to pair…"))
                                    Button(L("Cancel")) { Task { await hid.stopPairing(receiver) } }
                                } else {
                                    Button(L("Pair New Device")) { Task { await hid.startPairing(receiver) } }
                                }
                            }
                        }
                        HelpText(L("To pair: choose a free channel on the mouse, switch it off, click “Pair New Device”, then switch the mouse back on within 30 seconds."))
                    }
                }
            }
            .padding(8)
        }
    }
}

private struct LogiDeviceView: View {
    @ObservedObject var device: HIDPPDevice
    @State private var dpiDraft: Double = 1000
    @State private var thresholdDraft: Double = 30
    @State private var thumbSpeed: Double = 1
    @State private var thumbInvert = false
    @ObservedObject private var hid = HIDPPManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "computermouse")
                Text(device.name).font(.headline)
                Spacer()
                if let battery = device.battery {
                    Image(systemName: device.charging ? "battery.100.bolt" : batterySymbol(battery))
                    Text("\(battery)%").monospacedDigit()
                }
                if device.transport.isReceiver && HIDPPTransport.unifyingProductIDs.contains(device.transport.productID) {
                    Button(L("Unpair")) { confirmUnpair() }
                }
            }

            if let range = device.dpiRange {
                if let step = range.step, step > 0 {
                    HStack {
                        Text(L("DPI")).frame(width: 190, alignment: .leading)
                        Slider(value: $dpiDraft, in: Double(range.min)...Double(range.max), step: Double(step), onEditingChanged: { editing in
                            if !editing { Task { await device.setDPI(Int(dpiDraft)) } }
                        })
                        Text("\(Int(dpiDraft))").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                } else {
                    Picker(L("DPI"), selection: Binding(
                        get: { device.dpi ?? range.min },
                        set: { value in Task { await device.setDPI(value) } }
                    )) {
                        ForEach(range.values, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .frame(width: 320)
                }
            }

            if let mode = device.wheelMode {
                Picker(L("Scroll wheel"), selection: Binding(
                    get: { mode },
                    set: { newMode in
                        Task { await device.setWheel(mode: newMode, threshold: Int(thresholdDraft)) }
                    }
                )) {
                    ForEach(WheelMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .frame(width: 420)
                if mode == .smartShift {
                    HStack {
                        Text(L("SmartShift sensitivity")).frame(width: 190, alignment: .leading)
                        Slider(value: $thresholdDraft, in: 1...100, step: 1, onEditingChanged: { editing in
                            if !editing {
                                Task { await device.setWheel(mode: .smartShift, threshold: Int(thresholdDraft)) }
                            }
                        })
                        Text("\(Int(thresholdDraft))").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
            }

            if let hiRes = device.hiResEnabled {
                Toggle(L("High-resolution wheel"), isOn: Binding(
                    get: { hiRes },
                    set: { on in Task { await device.setHiResWheel(on) } }
                ))
                HelpText(L("The wheel reports about 8× finer steps to LogiMouse, which turns them into very smooth scrolling."))
            }

            if let thumbMode = device.thumbWheelMode {
                Picker(L("Thumb wheel"), selection: Binding(
                    get: { thumbMode },
                    set: { mode in Task { await device.setThumbWheel(mode) } }
                )) {
                    ForEach(ThumbWheelMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .frame(width: 420)
                if thumbMode != .native {
                    HStack {
                        Toggle(L("Invert"), isOn: Binding(
                            get: { thumbInvert },
                            set: { on in
                                thumbInvert = on
                                device.setThumbWheelOptions(invert: on, speed: thumbSpeed)
                            }
                        ))
                        Text(L("Speed"))
                        Slider(value: $thumbSpeed, in: 0.25...4, step: 0.25, onEditingChanged: { editing in
                            if !editing { device.setThumbWheelOptions(invert: thumbInvert, speed: thumbSpeed) }
                        })
                        .frame(width: 160)
                        Text(String(format: "%.2f×", thumbSpeed)).monospacedDigit()
                    }
                }
                if thumbMode == .buttons {
                    HelpText(L("Rotating left/right and tapping the thumb wheel act as buttons you can bind on the Buttons tab."))
                }
            }

            if let onboard = device.onboardProfilesEnabled {
                Toggle(L("Onboard profiles"), isOn: Binding(
                    get: { onboard },
                    set: { on in Task { await device.setOnboardProfiles(on) } }
                ))
                HelpText(L("Turn onboard profiles off to free profile and DPI buttons for binding and to let LogiMouse control DPI and report rate."))
            }

            if !device.reportRates.isEmpty {
                Picker(L("Report rate"), selection: Binding(
                    get: { device.reportRate ?? device.reportRates.first ?? 8 },
                    set: { ms in Task { await device.setReportRate(ms) } }
                )) {
                    ForEach(device.reportRates, id: \.self) { ms in
                        Text("\(1000 / ms) Hz").tag(ms)
                    }
                }
                .frame(width: 320)
            }

            if !device.controls.isEmpty {
                Text(L("Divert buttons to LogiMouse")).font(.subheadline)
                HelpText(L("A diverted button stops doing its built-in function and can be bound on the Buttons tab, including gestures and long presses."))
                ForEach(device.controls) { control in
                    Toggle(control.name, isOn: Binding(
                        get: { device.diverted.contains(control.cid) },
                        set: { on in Task { await device.setDiverted(control.cid, on) } }
                    ))
                }
            }
        }
        .onAppear(perform: syncDrafts)
        .onReceive(device.objectWillChange) { _ in
            DispatchQueue.main.async { syncDrafts() }
        }
    }

    private func syncDrafts() {
        if let dpi = device.dpi { dpiDraft = Double(dpi) }
        thresholdDraft = Double(device.smartShiftThreshold)
        thumbSpeed = device.savedSettings.thumbWheelSpeed
        thumbInvert = device.savedSettings.thumbWheelInvert
    }

    private func confirmUnpair() {
        let alert = NSAlert()
        alert.messageText = String(format: L("Unpair %@?"), device.name)
        alert.informativeText = L("The device will stop working with this receiver until it is paired again.")
        alert.addButton(withTitle: L("Unpair"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await hid.unpair(device) }
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}
