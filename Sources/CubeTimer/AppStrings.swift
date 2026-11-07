import Foundation

enum AppStrings {
    static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: .module)
    }

    static func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: Locale.current, arguments: arguments)
    }
}
