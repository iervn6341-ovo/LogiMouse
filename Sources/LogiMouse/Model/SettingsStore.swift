import Foundation

/// The effective configuration for the app currently in front.
struct ActiveContext {
    var disabled: Bool
    var bindings: [ButtonBinding]
    var keyMappings: [KeyMapping]
    var smoothScroll: Bool
}

/// Owns the persisted settings. Everything runs on the main thread.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { scheduleSave() }
    }

    private(set) var isFirstLaunch = false
    private let fileURL: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("LogiMouse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")

        var initial = AppSettings()
        var firstLaunch = false
        if let data = try? Data(contentsOf: url) {
            if let loaded = Self.decode(data) {
                initial = loaded
            } else {
                // Keep the unreadable file around instead of silently discarding it.
                let backup = dir.appendingPathComponent("settings.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: url, to: backup)
            }
        } else {
            firstLaunch = true
        }
        fileURL = url
        settings = initial
        isFirstLaunch = firstLaunch
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard let data = try? Self.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func export(to url: URL) throws {
        try Self.encode(settings).write(to: url, options: .atomic)
    }

    func importSettings(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let loaded = Self.decode(data) else { return false }
        settings = loaded
        saveNow()
        return true
    }

    func reset() {
        settings = AppSettings()
        saveNow()
    }

    private static func encode(_ s: AppSettings) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(s)
    }

    /// Decodes settings, filling keys missing from older files with defaults.
    private static func decode(_ data: Data) -> AppSettings? {
        guard let loaded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? encode(AppSettings()),
              let defaults = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return nil }
        let merged = merge(defaults, loaded)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: mergedData)
    }

    private static func merge(_ base: [String: Any], _ overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let b = base[key] as? [String: Any], let o = value as? [String: Any] {
                result[key] = merge(b, o)
            } else {
                result[key] = value
            }
        }
        return result
    }

    // MARK: Lookup

    func exception(for bundleID: String?) -> AppException? {
        guard let bundleID else { return nil }
        return settings.exceptions.first { $0.bundleID == bundleID }
    }

    func context(for bundleID: String?) -> ActiveContext {
        let s = settings
        guard s.general.enabled else {
            return ActiveContext(disabled: true, bindings: [], keyMappings: [], smoothScroll: false)
        }
        guard let ex = exception(for: bundleID) else {
            return ActiveContext(disabled: false, bindings: s.buttons.bindings,
                                 keyMappings: s.keyMappings, smoothScroll: s.scroll.smooth)
        }
        if ex.disableAll {
            return ActiveContext(disabled: true, bindings: [], keyMappings: [], smoothScroll: false)
        }
        var bindings = ex.bindings
        if !ex.ignoreGlobalBindings { bindings += s.buttons.bindings }
        return ActiveContext(disabled: false,
                             bindings: bindings,
                             keyMappings: ex.disableKeyMappings ? [] : s.keyMappings,
                             smoothScroll: s.scroll.smooth && !ex.disableSmoothScroll)
    }

    var currentContext: ActiveContext {
        context(for: FrontmostApp.shared.bundleID)
    }
}
