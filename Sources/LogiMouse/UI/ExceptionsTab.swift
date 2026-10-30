import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExceptionsTab: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: L("Per-App Exceptions")) {
                    HelpText(L("Turn LogiMouse features off for specific apps, or give them their own button bindings (choose the app in “Bindings for:” on the Buttons tab)."))
                    HStack {
                        Menu(L("Add Running App")) {
                            ForEach(runningApps, id: \.bundleIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app) }
                            }
                        }
                        .frame(width: 200)
                        Button(L("Add Manually…")) { addManually() }
                        Spacer()
                    }
                    if store.settings.exceptions.isEmpty {
                        Text(L("No exceptions yet.")).foregroundColor(.secondary)
                    }
                    ForEach($store.settings.exceptions) { $app in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                AppIcon(bundleID: app.bundleID)
                                Text(app.name).font(.headline)
                                Text(app.bundleID).font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button {
                                    let id = app.bundleID
                                    DispatchQueue.main.async {
                                        store.settings.exceptions.removeAll { $0.bundleID == id }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            HStack(spacing: 16) {
                                Toggle(L("Disable LogiMouse"), isOn: $app.disableAll)
                                Toggle(L("Disable smooth scroll"), isOn: $app.disableSmoothScroll)
                                Toggle(L("Ignore global bindings"), isOn: $app.ignoreGlobalBindings)
                                Toggle(L("Disable key mappings"), isOn: $app.disableKeyMappings)
                            }
                            if !app.bindings.isEmpty {
                                Text(String(format: L("%d app-specific bindings"), app.bindings.count))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Divider()
                    }
                }
            }
            .padding(8)
        }
    }

    private var runningApps: [NSRunningApplication] {
        let existing = Set(store.settings.exceptions.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !existing.contains($0.bundleIdentifier ?? "") }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        addException(bundleID: id, name: app.localizedName ?? id)
    }

    private func addManually() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            addException(bundleID: id, name: name)
        }
    }

    private func addException(bundleID: String, name: String) {
        guard !store.settings.exceptions.contains(where: { $0.bundleID == bundleID }) else { return }
        store.settings.exceptions.append(AppException(bundleID: bundleID, name: name))
    }
}
