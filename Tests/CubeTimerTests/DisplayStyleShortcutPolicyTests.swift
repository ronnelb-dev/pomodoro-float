import XCTest
@testable import CubeTimer

final class DisplayStyleShortcutPolicyTests: XCTestCase {
    func testCommandShiftNumberMappingCoversEachDisplayAndRejectsOtherKeys() {
        XCTAssertEqual(DisplayStyleShortcutPolicy.style(forCommandShiftNumber: "1"), .cube)
        XCTAssertEqual(DisplayStyleShortcutPolicy.style(forCommandShiftNumber: "2"), .digital)
        XCTAssertEqual(DisplayStyleShortcutPolicy.style(forCommandShiftNumber: "3"), .clock)
        XCTAssertNil(DisplayStyleShortcutPolicy.style(forCommandShiftNumber: "4"))
    }

    func testExistingCommandNumberPresetShortcutsRemainOneThroughSix() {
        XCTAssertEqual((0..<6).compactMap(PresetShortcutPolicy.commandNumber(forPresetIndex:)),
                       Array("123456"))
        XCTAssertNil(PresetShortcutPolicy.commandNumber(forPresetIndex: 6))
    }

    func testPresetTileAccessibilityExplainsModeSpecificAction() {
        XCTAssertEqual(PresetTileAccessibilityPolicy.hint(displayStyle: .cube),
                       "Starts or restarts this preset immediately and plays the preset sound.")
        XCTAssertEqual(PresetTileAccessibilityPolicy.hint(displayStyle: .digital),
                       "Selects this preset without starting the timer.")
        XCTAssertEqual(PresetTileAccessibilityPolicy.hint(displayStyle: .clock),
                       "Selects this preset without starting the timer.")
    }

    func testPackageEnglishLocalizationResolvesWelcomeAndPreviewStrings() {
        XCTAssertEqual(AppStrings.localized("welcome.title"), "Welcome to Pomodoro Float")
        XCTAssertEqual(AppStrings.localized("sound.preview.preset"), "Preview Preset Click Sound")
        XCTAssertEqual(AppStrings.localizedFormat("announcement.phaseStarted", "Focus", "25 minutes"),
                       "Focus session started. 25 minutes remaining.")
    }
}
