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

                SettingsSection(title: L("Physical Key Substitution")) {
                    HelpText(L("Swap physical keys at the system level, for every keyboard (for example Caps Lock → Escape). It works in every app and takes priority over key mapping."))
                    ForEach($store.settings.keySubstitutions) { $substitution in
                        HStack {
                            Toggle("", isOn: $substitution.enabled).labelsHidden()
                            keyPicker($substitution.from)
                            Image(systemName: "arrow.right")
                            keyPicker($substitution.to)
                            Button {
                                let id = substitution.id
                                DispatchQueue.main.async {
                                    store.settings.keySubstitutions.removeAll { $0.id == id }
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                    }
                    Button(L("Add Substitution")) {
                        store.settings.keySubstitutions.append(
                            KeySubstitution(from: KeyUsage.keys[0].usage, to: KeyUsage.keys[9].usage))
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

    private func keyPicker(_ usage: Binding<UInt64>) -> some View {
        Picker("", selection: usage) {
            ForEach(KeyUsage.keys, id: \.usage) { key in
                Text(key.name).tag(key.usage)
            }
        }
        .labelsHidden()
        .frame(width: 200)
    }
}
