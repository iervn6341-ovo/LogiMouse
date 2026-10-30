import SwiftUI

struct KeyboardTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var newKey: KeyCombo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSection(title: L("Key Mapping")) {
                    HelpText(L("Map a key or key combination to another shortcut or to any action. Mappings apply in all apps except where disabled on the Exceptions tab."))
                    HStack {
                        Text(L("New mapping from:"))
                        ShortcutRecorder(combo: $newKey, placeholder: L("Record Key"))
                        Spacer()
                    }
                    if store.settings.keyMappings.isEmpty {
                        Text(L("No key mappings yet.")).foregroundColor(.secondary)
                    }
                    ForEach($store.settings.keyMappings) { $mapping in
                        HStack(alignment: .top) {
                            Toggle("", isOn: $mapping.enabled).labelsHidden()
                            Text(mapping.from.description)
                                .frame(width: 140, alignment: .leading)
                                .padding(.top, 3)
                            Image(systemName: "arrow.right").padding(.top, 4)
                            ActionEditor(action: $mapping.action)
                            Button {
                                let id = mapping.id
                                DispatchQueue.main.async {
                                    store.settings.keyMappings.removeAll { $0.id == id }
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 3)
                        }
                        Divider()
                    }
                }
            }
            .padding(8)
        }
        .onChange(of: newKey) { key in
            guard let key else { return }
            let mapping = KeyMapping(from: key, action: Action(kind: .keyboardShortcut))
            store.settings.keyMappings.append(mapping)
            newKey = nil
        }
    }
}
