import Foundation
import XCTest
@testable import CubeTimer

@MainActor
final class AppearanceModelTests: XCTestCase {
    func testDisplayContrastUsesLinearSRGBAndKeepsReadableColors() {
        XCTAssertEqual(DisplayContrast.ratio(DisplayContrast.background), 1, accuracy: 0.001)
        XCTAssertGreaterThan(DisplayContrast.ratio(RGBColor(0xFFFFFF)), 19)
        for theme in [CubeTheme.dark, .light, .midnight] {
            let digits = CubeAppearance.preset(theme).display
            XCTAssertGreaterThanOrEqual(DisplayContrast.ratio(digits),
                                        DisplayContrast.minimumDigitRatio)
            XCTAssertEqual(DisplayContrast.readableDigits(digits, automatic: true), digits)
        }
    }

    func testAutomaticDigitsBrightenDarkColorButManualModeUsesExactColor() {
        let chosen = RGBColor(0x102040)
        XCTAssertLessThan(DisplayContrast.ratio(chosen), DisplayContrast.minimumDigitRatio)
        XCTAssertEqual(DisplayContrast.readableDigits(chosen, automatic: false), chosen)
        let rendered = DisplayContrast.readableDigits(chosen, automatic: true)
        XCTAssertGreaterThanOrEqual(DisplayContrast.ratio(rendered),
                                    DisplayContrast.minimumDigitRatio)
        XCTAssertGreaterThan(rendered.blue, rendered.red)
        XCTAssertEqual(chosen, RGBColor(0x102040))
    }

    func testAutomaticDigitsPreferencePersistsSeparatelyFromChosenColor() {
        let suite = "CubeTimerAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = AppearanceModel(defaults: defaults)
        XCTAssertTrue(model.automaticReadableDigits)
        model.setDisplay(RGBColor(0x101010))
        model.setAutomaticReadableDigits(false)
        let restored = AppearanceModel(defaults: defaults)
        XCTAssertFalse(restored.automaticReadableDigits)
        XCTAssertEqual(restored.value.display, RGBColor(0x101010))
        XCTAssertEqual(DisplayContrast.readableDigits(restored.value.display,
                                                      automatic: restored.automaticReadableDigits),
                       RGBColor(0x101010))
        restored.setAutomaticReadableDigits(true)
        XCTAssertTrue(AppearanceModel(defaults: defaults).automaticReadableDigits)
    }

    func testExistingAppearanceRecordLoadsWithAutomaticDigitsEnabled() throws {
        let suite = "CubeTimerAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldAppearance = CubeAppearance.preset(.midnight)
        defaults.set(try JSONEncoder().encode(oldAppearance), forKey: "cubeAppearance.v1")

        let model = AppearanceModel(defaults: defaults)
        XCTAssertEqual(model.value, oldAppearance)
        XCTAssertTrue(model.automaticReadableDigits)
        model.setAutomaticReadableDigits(false)
        XCTAssertEqual(AppearanceModel(defaults: defaults).value, oldAppearance)
    }

    func testSmallDisplayStrokeEmphasisTracksViewportSize() {
        XCTAssertEqual(DisplayStrokeSizing.emphasis(for: NSSize(width: 300, height: 300)), 0)
        XCTAssertEqual(DisplayStrokeSizing.emphasis(for: NSSize(width: 223, height: 223)), 1)
        XCTAssertEqual(DisplayStrokeSizing.emphasis(for: NSSize(width: 261.5, height: 261.5)),
                       0.5)
        XCTAssertEqual(DisplayStrokeSizing.emphasis(for: NSSize(width: 500, height: 240)),
                       0.8)
    }

    func testAppearanceChangesDoNotResetRunningTimer() {
        let suite = "CubeTimerAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let timer = TimerModel(defaults: defaults, notificationsEnabled: false)
        defer { timer.reset() }
        let appearance = AppearanceModel(defaults: defaults)
        timer.start()
        let session = defaults.data(forKey: SavedTimerSession.key)

        appearance.setDisplay(RGBColor(0x101820))
        appearance.setAutomaticReadableDigits(false)
        appearance.setAutomaticReadableDigits(true)
        appearance.setTheme(.light)

        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.selectedPreset, 0)
        XCTAssertEqual(timer.total, 300)
        XCTAssertEqual(defaults.data(forKey: SavedTimerSession.key), session)
    }

    func testCustomAppearancePersistsBetweenInstances() {
        let suite = "CubeTimerAppearanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = AppearanceModel(defaults: defaults)
        XCTAssertEqual(model.value, .preset(.dark))

        model.setTheme(.light)
        XCTAssertEqual(model.value, .preset(.light))
        model.setFinish(.gloss)
        model.setAccent(RGBColor(0xFF812A))
        model.setDisplay(RGBColor(0xC8FCFF))
        model.setLighting(0.35)

        let restored = AppearanceModel(defaults: defaults)
        XCTAssertEqual(restored.value.theme, .custom)
        XCTAssertEqual(restored.value.finish, .gloss)
        XCTAssertEqual(restored.value.accent, RGBColor(0xFF812A))
        XCTAssertEqual(restored.value.display, RGBColor(0xC8FCFF))
        XCTAssertEqual(restored.value.lighting, 0.35)
    }
}
