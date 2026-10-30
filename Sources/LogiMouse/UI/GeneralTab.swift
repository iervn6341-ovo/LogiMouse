import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: L("General")) {
                    Toggle(L("Enable LogiMouse"), isOn: $store.settings.general.enabled)
                    Toggle(L("Launch at login"), isOn: Binding(
                        get: { launchAtLogin },
                        set: { on in
                            LoginItem.setEnabled(on)
                            launchAtLogin = LoginItem.isEnabled
                        }
                    ))
                    .disabled(!LoginItem.isSupported)
                    if !LoginItem.isSupported {
                        HelpText(L("On macOS 12, add LogiMouse in System Preferences → Users & Groups → Login Items."))
                    }
                    Toggle(L("Hide menu bar icon"), isOn: $store.settings.general.hideMenuBarIcon)
                    HelpText(L("Open LogiMouse again from Finder or Spotlight to show this window while the icon is hidden."))
                    Toggle(L("Tighten menu bar icon spacing"), isOn: Binding(
                        get: { store.settings.general.tightenMenuBarIcons },
                        set: { on in
                            store.settings.general.tightenMenuBarIcons = on
                            MenuBarSpacing.apply(tight: on)
                        }
                    ))
                    HelpText(L("Takes effect after you log out and back in."))
                    Picker(L("Language"), selection: $store.settings.general.language) {
                        Text(L("System")).tag("system")
                        Text("English").tag("en")
                        Text("繁體中文").tag("zh-Hant")
                    }
                    .frame(width: 300)
                }

                SettingsSection(title: L("Permissions")) {
                    HStack {
                        Image(systemName: permissions.trusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(permissions.trusted ? .green : .red)
                        Text(permissions.trusted ? L("Accessibility permission granted") : L("Accessibility permission missing"))
                        Spacer()
                        Button(L("Open System Settings")) { Permissions.openAccessibilitySettings() }
                    }
                }

                SettingsSection(title: L("Settings File")) {
                    HStack {
                        Button(L("Save Settings to File…")) { exportSettings() }
                        Button(L("Load Settings from File…")) { importSettings() }
                        Spacer()
                        Button(L("Reset All Settings…")) { resetSettings() }
                    }
                }

                SettingsSection(title: L("About")) {
                    Text("LogiMouse \(version)")
                    HelpText(L("Free and open source. No account, no subscription, no telemetry."))
                    HStack {
                        Spacer()
                        Button(L("Quit LogiMouse")) { NSApp.terminate(nil) }
                    }
                }
            }
            .padding(8)
        }
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LogiMouse Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
        } catch {
            alert(L("Saving the settings file failed."), info: error.localizedDescription)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.importSettings(from: url) {
            alert(L("Settings loaded."), info: "")
        } else {
            alert(L("Loading failed: this is not a valid LogiMouse settings file."), info: "")
        }
    }

    private func resetSettings() {
        let alert = NSAlert()
        alert.messageText = L("Reset all settings?")
        alert.informativeText = L("All bindings, mappings, exceptions and device settings will be erased.")
        alert.addButton(withTitle: L("Reset"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            store.reset()
        }
    }

    private func alert(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }
}
