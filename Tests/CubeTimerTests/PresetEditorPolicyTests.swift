import XCTest
@testable import CubeTimer

final class PresetEditorPolicyTests: XCTestCase {
    func testUnchangedRowKeepsActionsVisibleButDisablesSaveAndUseNextTime() {
        let state = PresetEditorRowPolicy.state(
            durationChanged: false, metadataChanged: false, canAffectActiveSession: true)

        XCTAssertFalse(state.isSaveEnabled)
        XCTAssertFalse(state.isUseNextTimeEnabled)
        XCTAssertFalse(state.showsImmediateAction)
    }

    func testMetadataEditEnablesSaveWithoutEnablingUseNextTime() {
        let state = PresetEditorRowPolicy.state(
            durationChanged: false, metadataChanged: true, canAffectActiveSession: false)

        XCTAssertTrue(state.isSaveEnabled)
        XCTAssertFalse(state.isUseNextTimeEnabled)
        XCTAssertFalse(state.showsImmediateAction)
    }

    func testDurationEditEnablesNextTimeAndShowsApplicableCurrentSessionAction() {
        let state = PresetEditorRowPolicy.state(
            durationChanged: true, metadataChanged: false, canAffectActiveSession: true)

        XCTAssertTrue(state.isSaveEnabled)
        XCTAssertTrue(state.isUseNextTimeEnabled)
        XCTAssertTrue(state.showsImmediateAction)
    }

    func testDuplicateDurationNamesExcludeEditedPresetAndReturnMatchingSlots() {
        let matches = PresetEditorRowPolicy.duplicateNames(
            for: 600,
            editingIndex: 1,
            presetSeconds: [600, 600, 300, 600, 900],
            presetNames: ["Quick", "Current", "Break", "Reading", "Long"])

        XCTAssertEqual(matches, ["Quick", "Reading"])
    }

    func testPresetRolesExplainTheirPomodoroUse() {
        XCTAssertEqual(PresetRole.focus.pomodoroDescription,
                       "Used for Pomodoro focus phases.")
        XCTAssertEqual(PresetRole.shortBreak.pomodoroDescription,
                       "Used for Pomodoro short breaks.")
        XCTAssertEqual(PresetRole.general.pomodoroDescription,
                       "Starts as an independent timer outside Pomodoro phases.")
    }
}
