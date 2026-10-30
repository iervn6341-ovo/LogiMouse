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
            }
            .padding(8)
        }
    }
}

private struct LogiDeviceView: View {
    @ObservedObject var device: HIDPPDevice
    @State private var dpiDraft: Double = 1000
    @State private var thresholdDraft: Double = 30

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
