import AppKit
import SwiftUI

/// A small on-screen indicator for Caps Lock and microphone mute changes.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func showCapsLock(_ on: Bool) {
        guard SettingsStore.shared.settings.general.capsLockPopup else { return }
        show(symbol: on ? "capslock.fill" : "capslock", text: on ? L("Caps Lock On") : L("Caps Lock Off"))
    }

    func showMicMute(_ muted: Bool) {
        guard SettingsStore.shared.settings.general.micMutePopup else { return }
        show(symbol: muted ? "mic.slash.fill" : "mic.fill", text: muted ? L("Microphone Muted") : L("Microphone On"))
    }

    private func show(symbol: String, text: String) {
        let size = NSSize(width: 180, height: 150)
        let panel = self.panel ?? makePanel(size: size)
        self.panel = panel
        panel.contentView = NSHostingView(rootView: HUDView(symbol: symbol, text: text))

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.18))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { panel.orderOut(nil) }
                })
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }
}

private struct HUDView: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .medium))
            Text(text)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.primary)
        .frame(width: 180, height: 150)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
