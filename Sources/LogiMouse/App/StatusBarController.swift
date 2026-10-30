import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "LogiMouse") {
                image.isTemplate = true
                item.button?.image = image
            } else {
                item.button?.title = "LM"
            }
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = SettingsStore.shared

        let title = NSMenuItem(title: "LogiMouse", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let enabled = NSMenuItem(title: L("Enabled"), action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = store.settings.general.enabled ? .on : .off
        menu.addItem(enabled)

        let devices = HIDPPManager.shared.devices
        if !devices.isEmpty {
            menu.addItem(.separator())
            for device in devices {
                var text = device.name
                if let battery = device.battery {
                    text += " — \(battery)%" + (device.charging ? " ⚡︎" : "")
                }
                let row = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                row.isEnabled = false
                menu.addItem(row)
            }
            HIDPPManager.shared.refresh()
        }

        if !Permissions.shared.trusted {
            menu.addItem(.separator())
            let permission = NSMenuItem(title: L("Grant Accessibility permission…"),
                                        action: #selector(openAccessibility), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: L("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: L("Quit LogiMouse"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        SettingsStore.shared.settings.general.enabled.toggle()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
