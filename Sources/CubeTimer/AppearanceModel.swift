import AppKit
import Combine
import SwiftUI

struct RGBColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    init(_ color: NSColor) {
        let converted = color.usingColorSpace(.deviceRGB) ?? color
        red = min(1, max(0, Double(converted.redComponent)))
        green = min(1, max(0, Double(converted.greenComponent)))
        blue = min(1, max(0, Double(converted.blueComponent)))
    }

    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
    var nsColor: NSColor { NSColor(deviceRed: red, green: green, blue: blue, alpha: 1) }
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

enum DisplayContrast {
    static let background = RGBColor(0x060606)
    static let minimumDigitRatio = 4.5
    static let minimumRingRatio = 3.0

    static func ratio(_ foreground: RGBColor,
                      against background: RGBColor = DisplayContrast.background) -> Double {
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func readableDigits(_ chosen: RGBColor, automatic: Bool) -> RGBColor {
        guard automatic, ratio(chosen) < minimumDigitRatio else { return chosen }
        var low = 0.0
        var high = 1.0
        for _ in 0..<24 {
            let amount = (low + high) / 2
            if ratio(blend(chosen, toward: RGBColor(0xFFFFFF), amount: amount)) < minimumDigitRatio {
                low = amount
            } else {
                high = amount
            }
        }
        return blend(chosen, toward: RGBColor(0xFFFFFF), amount: high)
    }

    private static func relativeLuminance(_ color: RGBColor) -> Double {
        func linear(_ component: Double) -> Double {
            let value = min(1, max(0, component))
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private static func blend(_ source: RGBColor, toward target: RGBColor,
                              amount: Double) -> RGBColor {
        let keep = 1 - amount
        return RGBColor(red: source.red * keep + target.red * amount,
                        green: source.green * keep + target.green * amount,
                        blue: source.blue * keep + target.blue * amount)
    }
}

enum CubeTheme: String, Codable, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case midnight = "Midnight"
    case custom = "Custom"
    var id: String { rawValue }
}

enum CubeFinish: String, Codable, CaseIterable, Identifiable {
    case matte = "Matte"
    case satin = "Satin"
    case gloss = "Gloss"
    var id: String { rawValue }

    var roughness: CGFloat {
        switch self {
        case .matte: 0.84
        case .satin: 0.46
        case .gloss: 0.16
        }
    }
}

struct CubeAppearance: Codable, Equatable {
    var theme: CubeTheme
    var finish: CubeFinish
    var body: RGBColor
    var accent: RGBColor
    var display: RGBColor
    var lighting: Double

    static func preset(_ theme: CubeTheme) -> CubeAppearance {
        switch theme {
        case .dark, .custom:
            return CubeAppearance(theme: .dark, finish: .satin,
                                  body: RGBColor(0x1C1F22), accent: RGBColor(0xEFA661),
                                  display: RGBColor(0xE7F5F3), lighting: 0.62)
        case .light:
            return CubeAppearance(theme: .light, finish: .matte,
                                  body: RGBColor(0xC4C7C3), accent: RGBColor(0xD9753D),
                                  display: RGBColor(0xDDF5F6), lighting: 0.70)
        case .midnight:
            return CubeAppearance(theme: .midnight, finish: .gloss,
                                  body: RGBColor(0x20334D), accent: RGBColor(0xF6BE76),
                                  display: RGBColor(0xBCEAFF), lighting: 0.48)
        }
    }
}

@MainActor
final class AppearanceModel: ObservableObject {
    @Published private(set) var value: CubeAppearance
    @Published private(set) var automaticReadableDigits: Bool
    private let defaults: UserDefaults
    private static let key = "cubeAppearance.v1"
    private static let automaticDigitsKey = "automaticReadableDigits"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticReadableDigits = defaults.object(forKey: Self.automaticDigitsKey) == nil
            ? true : defaults.bool(forKey: Self.automaticDigitsKey)
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(CubeAppearance.self, from: data) {
            value = decoded
        } else {
            value = .preset(.dark)
        }
    }

    func setTheme(_ theme: CubeTheme) {
        guard theme != .custom else { return }
        update(.preset(theme))
    }

    func setFinish(_ finish: CubeFinish) {
        var next = value
        next.finish = finish
        next.theme = .custom
        update(next)
    }

    func setBody(_ color: RGBColor) { customize { $0.body = color } }
    func setAccent(_ color: RGBColor) { customize { $0.accent = color } }
    func setDisplay(_ color: RGBColor) { customize { $0.display = color } }
    func setAutomaticReadableDigits(_ enabled: Bool) {
        guard enabled != automaticReadableDigits else { return }
        automaticReadableDigits = enabled
        defaults.set(enabled, forKey: Self.automaticDigitsKey)
    }
    func setLighting(_ intensity: Double) {
        customize { $0.lighting = min(1, max(0, intensity)) }
    }

    private func customize(_ edit: (inout CubeAppearance) -> Void) {
        var next = value
        edit(&next)
        next.theme = .custom
        update(next)
    }

    private func update(_ next: CubeAppearance) {
        guard next != value else { return }
        value = next
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
