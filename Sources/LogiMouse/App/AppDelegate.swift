import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = SettingsStore.shared
        FrontmostApp.shared.start()

        let statusBar = StatusBarController { [weak self] in self?.showSettings() }
        statusBar.setVisible(!store.settings.general.hideMenuBarIcon)
        self.statusBar = statusBar

        HIDPPManager.shared.start()
        CursorController.shared.apply(store.settings.cursor)

        store.$settings
            .map(\.general.hideMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] hidden in self?.statusBar?.setVisible(!hidden) }
            .store(in: &cancellables)

        store.$settings
            .map(\.cursor)
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { cursor in CursorController.shared.apply(cursor) }
            .store(in: &cancellables)

        store.$settings
            .map { $0.general.enabled ? $0.keySubstitutions : [] }
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { substitutions in KeySubstitutions.shared.apply(substitutions) }
            .store(in: &cancellables)

        Permissions.shared.ensureAccessibility {
            EventTap.shared.start()
        }

        if store.isFirstLaunch || !Permissions.shared.trusted {
            showSettings()
        }
    }

    /// Launching the app again (e.g. with the menu bar icon hidden) opens the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SettingsStore.shared.saveNow()
        CursorController.shared.restoreIfApplied()
        KeySubstitutions.shared.clear()
        Task {
            await HIDPPManager.shared.releaseAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.show()
    }
}
