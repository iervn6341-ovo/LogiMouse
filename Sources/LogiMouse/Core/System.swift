import AppKit
import ApplicationServices
import ServiceManagement

/// Tracks the bundle identifier of the frontmost application.
final class FrontmostApp {
    static let shared = FrontmostApp()

    private(set) var bundleID: String?
    private var observer: NSObjectProtocol?

    func start() {
        bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.bundleID = app?.bundleIdentifier
        }
    }
}

/// Accessibility permission, required for the event tap.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var trusted = AXIsProcessTrusted()
    private var timer: Timer?

    /// Prompts if needed and calls `onTrusted` once the permission is granted.
    func ensureAccessibility(onTrusted: @escaping () -> Void) {
        if AXIsProcessTrusted() {
            trusted = true
            onTrusted()
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.trusted = true
            onTrusted()
        }
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LoginItem {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LogiMouse: login item update failed: \(error)")
        }
    }
}

enum MenuBarSpacing {
    /// Tightens (or restores) the spacing between menu bar extras. Takes effect after logging out.
    static func apply(tight: Bool) {
        let keys = ["NSStatusItemSpacing": 6, "NSStatusItemSelectionPadding": 4]
        for (key, value) in keys {
            let args = tight
                ? ["-currentHost", "write", "-globalDomain", key, "-int", "\(value)"]
                : ["-currentHost", "delete", "-globalDomain", key]
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = args
            try? process.run()
        }
    }
}
