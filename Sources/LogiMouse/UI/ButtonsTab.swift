import SwiftUI

struct ButtonsTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var hid = HIDPPManager.shared
    /// Empty for global bindings, otherwise the bundle ID of an exception app.
    @State private var scope = ""
    @State private var recording = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: L("Button Bindings")) {
                    HStack {
                        Text(L("Bindings for:"))
                        Picker("", selection: $scope) {
                            Text(L("All apps")).tag("")
                            ForEach(store.settings.exceptions) { app in
                                Text(app.name).tag(app.bundleID)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Spacer()
                        Button(recording ? L("Press a mouse button… (click to cancel)") : L("Add Binding")) {
                            recording ? stopRecording() : startRecording()
                        }
                    }
                    HelpText(L("Click “Add Binding”, then press any mouse button other than the left one, optionally while holding modifier keys. Then choose how it is triggered and what it does. Buttons diverted from Logitech devices (Mouse tab) can be bound too."))

                    let bindings = bindingsForScope
                    if bindings.wrappedValue.isEmpty {
                        Text(L("No bindings yet.")).foregroundColor(.secondary).padding(.vertical, 6)
                    } else {
                        HStack {
                            Text(L("On")).frame(width: 28, alignment: .leading)
                            Text(L("Button")).frame(width: 170, alignment: .leading)
                            Text(L("Trigger")).frame(width: 170, alignment: .leading)
                            Text(L("Action"))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        ForEach(bindings) { $binding in
                            BindingRow(binding: $binding) {
                                let id = binding.id
                                DispatchQueue.main.async {
                                    bindings.wrappedValue.removeAll { $0.id == id }
                                }
                            }
                            Divider()
                        }
                    }
                }

                SettingsSection(title: L("Pan")) {
                    HelpText(L("Hold one of these buttons and drag to scroll freely in any direction, like on a trackpad. A short press without moving still clicks normally. Pan replaces drag gestures of that button."))
                    HStack(spacing: 14) {
                        ForEach(panCandidates, id: \.self) { button in
                            Toggle(ButtonNames.name(button), isOn: panBinding(button))
                        }
                    }
                    HStack(spacing: 18) {
                        Toggle(L("Momentum"), isOn: $store.settings.buttons.pan.momentum)
                        Toggle(L("Invert direction"), isOn: $store.settings.buttons.pan.invert)
                    }
                    SliderRow(title: L("Pan speed"), value: $store.settings.buttons.pan.speed,
                              range: 0.25...4, format: "%.2f×")
                }

                SettingsSection(title: L("Click Through")) {
                    Toggle(L("Left click-through"), isOn: $store.settings.buttons.leftClickThrough)
                    HelpText(L("Clicking a control in an inactive window activates the window and clicks the control at once, instead of needing a second click."))
                    Toggle(L("Right click-through"), isOn: $store.settings.buttons.rightClickThrough)
                    HelpText(L("Right-clicking an inactive window activates it before the context menu opens."))
                    SliderRow(title: L("Left drag dead zone (px)"), value: $store.settings.buttons.leftDragDeadZone,
                              range: 0...20, step: 1)
                    HelpText(L("Ignores tiny movements while the left button is down, so slightly shaky clicks don't become drags. 0 turns it off."))
                }

                SettingsSection(title: L("Timing")) {
                    SliderRow(title: L("Long press delay (ms)"), value: $store.settings.buttons.longPressDelay,
                              range: 150...1500, step: 10)
                    SliderRow(title: L("Long press repeat interval (ms)"),
                              value: $store.settings.buttons.longPressInterval, range: 30...800, step: 10)
                    SliderRow(title: L("Drag gesture distance (px)"), value: $store.settings.buttons.dragThreshold,
                              range: 10...200, step: 1)
                }
            }
            .padding(8)
        }
        .onDisappear { stopRecording() }
    }

    private var bindingsForScope: Binding<[ButtonBinding]> {
        if scope.isEmpty || !store.settings.exceptions.contains(where: { $0.bundleID == scope }) {
            return $store.settings.buttons.bindings
        }
        let id = scope
        return Binding(
            get: { store.settings.exceptions.first { $0.bundleID == id }?.bindings ?? [] },
            set: { newValue in
                if let i = store.settings.exceptions.firstIndex(where: { $0.bundleID == id }) {
                    store.settings.exceptions[i].bindings = newValue
                }
            }
        )
    }

    private var panCandidates: [Int] {
        var buttons = [1, 2, 3, 4]
        for device in hid.devices {
            for cid in device.diverted.sorted() {
                let button = ButtonNames.virtualBase + Int(cid)
                if !buttons.contains(button) { buttons.append(button) }
            }
        }
        for button in store.settings.buttons.pan.buttons where !buttons.contains(button) {
            buttons.append(button)
        }
        return buttons
    }

    private func panBinding(_ button: Int) -> Binding<Bool> {
        Binding(
            get: { store.settings.buttons.pan.buttons.contains(button) },
            set: { on in
                store.settings.buttons.pan.buttons.removeAll { $0 == button }
                if on { store.settings.buttons.pan.buttons.append(button) }
            }
        )
    }

    private func startRecording() {
        recording = true
        let target = bindingsForScope
        ButtonEngine.shared.recordHandler = { button, modifiers in
            stopRecording()
            let binding = ButtonBinding(trigger: Trigger(button: button, modifiers: modifiers, kind: .click),
                                        action: Action(kind: .none))
            target.wrappedValue.append(binding)
        }
    }

    private func stopRecording() {
        recording = false
        ButtonEngine.shared.recordHandler = nil
    }
}

private struct BindingRow: View {
    @Binding var binding: ButtonBinding
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Toggle("", isOn: $binding.enabled)
                .labelsHidden()
                .frame(width: 28, alignment: .leading)
            Text(binding.trigger.buttonDescription)
                .frame(width: 170, alignment: .leading)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Picker("", selection: $binding.trigger.kind) {
                    ForEach(TriggerKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                if binding.trigger.kind == .chord {
                    Picker("", selection: $binding.trigger.chordButton) {
                        ForEach([0, 1, 2, 3, 4], id: \.self) { button in
                            Text(ButtonNames.name(button)).tag(button)
                        }
                    }
                    .labelsHidden()
                }
                if binding.trigger.kind.supportsRepeat {
                    Toggle(L("Repeat"), isOn: $binding.repeats)
                }
            }
            .frame(width: 170)
            ActionEditor(action: $binding.action)
                .frame(maxWidth: .infinity)
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .padding(.top, 3)
        }
    }
}
