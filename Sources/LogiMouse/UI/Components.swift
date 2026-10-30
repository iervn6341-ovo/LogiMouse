import AppKit
import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox(label: Text(title).font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var format: String = "%.0f"

    var body: some View {
        HStack {
            Text(title).frame(width: 190, alignment: .leading)
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
            Text(String(format: format, value))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }
}

struct ModifierPicker: View {
    @Binding var modifiers: ModifierSet

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ModifierSet.all, id: \.rawValue) { modifier in
                Toggle(modifier.symbol, isOn: Binding(
                    get: { modifiers.contains(modifier) },
                    set: { on in
                        if on { modifiers.insert(modifier) } else { modifiers.remove(modifier) }
                    }
                ))
                .toggleStyle(.button)
            }
        }
    }
}

struct HelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ActionEditor: View {
    @Binding var action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("", selection: $action.kind) {
                ForEach(Array(ActionKind.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            }
            .labelsHidden()

            switch action.kind {
            case .keyboardShortcut:
                ShortcutRecorder(combo: $action.shortcut)
            case .openURL:
                TextField(L("URL or file path"), text: $action.text)
            case .launchApp:
                TextField(L("App path or bundle identifier"), text: $action.text)
            case .runShortcut:
                TextField(L("Shortcut name"), text: $action.text)
            default:
                EmptyView()
            }
        }
    }
}

/// Records a key combo while the settings window is focused.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    var placeholder = L("Record Shortcut")
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? L("Type a shortcut… (Esc to cancel)") : (combo?.description ?? placeholder)) {
            recording ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        KeyEngine.shared.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = ModifierSet(nsFlags: event.modifierFlags).subtracting(.fn)
            if event.keyCode == KeyCode.escape && mods.isEmpty {
                stop()
                return nil
            }
            combo = KeyCombo(keyCode: event.keyCode, modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        KeyEngine.shared.isRecording = false
    }
}

struct AppIcon: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app")
                .frame(width: 20, height: 20)
        }
    }
}
