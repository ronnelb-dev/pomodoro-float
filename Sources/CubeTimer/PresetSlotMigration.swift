import Foundation

enum PresetSlotMigration {
    private static let schemaVersionKey = "presetSlotSchemaVersion"
    private static let currentSchemaVersion = 2
    private static let legacySlotIndices = 3...4
    private static let settings = ["presetSeconds", "presetName", "presetRole"]

    static func hasExistingPresetData(in defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: "selectedPreset") != nil ||
            defaults.data(forKey: SavedTimerSession.key) != nil {
            return true
        }
        return (0..<5).contains { index in
            settings.contains { defaults.object(forKey: "\($0).\(index)") != nil }
        }
    }

    static func migratePreferences(in defaults: UserDefaults) {
        guard defaults.integer(forKey: schemaVersionKey) < currentSchemaVersion else { return }

        var legacyValues: [Int: [String: Any]] = [:]
        for index in legacySlotIndices {
            legacyValues[index] = Dictionary(uniqueKeysWithValues: settings.compactMap { setting in
                defaults.object(forKey: "\(setting).\(index)").map { (setting, $0) }
            })
        }

        for index in legacySlotIndices {
            for setting in settings {
                defaults.removeObject(forKey: "\(setting).\(index)")
            }
        }

        for oldIndex in legacySlotIndices {
            let newIndex = currentIndex(fromLegacy: oldIndex)
            for (setting, oldValue) in legacyValues[oldIndex] ?? [:] {
                defaults.set(migratedValue(oldValue, setting: setting, oldIndex: oldIndex),
                             forKey: "\(setting).\(newIndex)")
            }
        }

        if let selected = defaults.object(forKey: "selectedPreset") as? Int,
           (0..<5).contains(selected) {
            defaults.set(currentIndex(fromLegacy: selected), forKey: "selectedPreset")
        }
        defaults.set(currentSchemaVersion, forKey: schemaVersionKey)
    }

    static func currentIndex(fromLegacy index: Int) -> Int {
        switch index {
        case 3: 4
        case 4: 5
        default: index
        }
    }

    private static func migratedValue(_ value: Any, setting: String, oldIndex: Int) -> Any {
        if oldIndex == 3, setting == "presetSeconds", (value as? NSNumber)?.intValue == 3_000 {
            return 2_700
        }
        if oldIndex == 3, setting == "presetName", (value as? String) == "50 MIN" {
            return "45 MIN"
        }
        return value
    }
}
