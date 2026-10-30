import SwiftUI

struct RootView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        VStack(spacing: 0) {
            if !permissions.trusted {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(L("LogiMouse needs Accessibility permission to read and remap mouse events."))
                    Spacer()
                    Button(L("Open System Settings")) { Permissions.openAccessibilitySettings() }
                }
                .padding(10)
                .background(Color.orange.opacity(0.15))
            }
            if !store.settings.general.enabled {
                HStack {
                    Image(systemName: "pause.circle.fill").foregroundColor(.secondary)
                    Text(L("LogiMouse is paused."))
                    Spacer()
                    Button(L("Resume")) { store.settings.general.enabled = true }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.12))
            }
            TabView {
                ButtonsTab().tabItem { Text(L("Buttons")) }
                MouseTab().tabItem { Text(L("Mouse")) }
                ScrollTab().tabItem { Text(L("Scroll")) }
                KeyboardTab().tabItem { Text(L("Keyboard")) }
                ExceptionsTab().tabItem { Text(L("Exceptions")) }
                GeneralTab().tabItem { Text(L("Settings")) }
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}
