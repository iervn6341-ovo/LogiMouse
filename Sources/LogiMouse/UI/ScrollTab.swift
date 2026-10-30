import SwiftUI

struct ScrollTab: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: L("Main Scroll Control")) {
                    Toggle(L("Smooth scrolling"), isOn: $store.settings.scroll.smooth)
                    if store.settings.scroll.smooth {
                        SliderRow(title: L("Distance per tick (px)"), value: $store.settings.scroll.step,
                                  range: 10...300, step: 1)
                        SliderRow(title: L("Duration (ms)"), value: $store.settings.scroll.duration,
                                  range: 60...1000, step: 10)
                        SliderRow(title: L("Acceleration"), value: $store.settings.scroll.acceleration,
                                  range: 0...10, step: 0.5, format: "%.1f")
                        Toggle(L("Extra smoothing"), isOn: $store.settings.scroll.moreSmooth)
                        HelpText(L("Acceleration makes content travel further when you spin the wheel quickly. Only physical mouse wheels are affected; trackpads and Magic Mouse keep their native scrolling."))
                    } else {
                        SliderRow(title: L("Speed multiplier"), value: $store.settings.scroll.lineMultiplier,
                                  range: 0.25...10, step: 0.25, format: "%.2f×")
                    }
                }

                SettingsSection(title: L("Physical Scroll Direction")) {
                    Toggle(L("Invert vertical wheel"), isOn: $store.settings.scroll.invertVertical)
                    Toggle(L("Invert horizontal wheel"), isOn: $store.settings.scroll.invertHorizontal)
                    SliderRow(title: L("Horizontal speed"), value: $store.settings.scroll.horizontalSpeed,
                              range: 0.25...4, step: 0.25, format: "%.2f×")
                    HelpText(L("Only affects mouse wheels, so you can keep natural scrolling for the trackpad and a classic direction for the mouse."))
                }

                SettingsSection(title: L("Modifier Keys")) {
                    modifierRow(title: L("Horizontal scroll"), enabled: $store.settings.scroll.horizontalEnabled,
                                modifiers: $store.settings.scroll.horizontalModifier) {
                        Toggle(L("Invert"), isOn: $store.settings.scroll.horizontalInvert)
                    }
                    modifierRow(title: L("Zoom"), enabled: $store.settings.scroll.zoomEnabled,
                                modifiers: $store.settings.scroll.zoomModifier) {
                        Toggle(L("Invert"), isOn: $store.settings.scroll.zoomInvert)
                    }
                    modifierRow(title: L("Fast scroll"), enabled: $store.settings.scroll.fastEnabled,
                                modifiers: $store.settings.scroll.fastModifier) {
                        Slider(value: $store.settings.scroll.fastMultiplier, in: 1.5...10, step: 0.5)
                            .frame(width: 140)
                        Text(String(format: "%.1f×", store.settings.scroll.fastMultiplier)).monospacedDigit()
                    }
                    HelpText(L("Hold the modifier while scrolling. Fast scroll also speeds up panning. Zoom sends ⌘+ / ⌘−."))
                }
            }
            .padding(8)
        }
    }

    private func modifierRow<Extra: View>(title: String, enabled: Binding<Bool>, modifiers: Binding<ModifierSet>,
                                          @ViewBuilder extra: () -> Extra) -> some View {
        HStack {
            Toggle(title, isOn: enabled).frame(width: 190, alignment: .leading)
            ModifierPicker(modifiers: modifiers).disabled(!enabled.wrappedValue)
            extra().disabled(!enabled.wrappedValue)
            Spacer()
        }
    }
}
