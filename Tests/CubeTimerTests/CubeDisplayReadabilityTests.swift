import XCTest
@testable import CubeTimer

final class CubeDisplayReadabilityTests: XCTestCase {
    func testSixCubeFacesEachMapToOneDistinctPreset() {
        XCTAssertEqual(CubeFace.allCases.map(\.preset), Array(0..<6))
        for preset in 0..<6 {
            XCTAssertEqual(CubeFace.primary(for: preset).preset, preset)
        }
    }

    func testActiveFaceRetainsPresetDurationBesideTheLiveCountdown() {
        let expectedPreset = CubePresetDurationLabel(seconds: 1_500)
        for countdown in ["25:00", "24:59", "12:34", "00:00"] {
            let content = CubeActiveDisplayContent(countdown: countdown, presetSeconds: 1_500)

            XCTAssertEqual(content.countdown, countdown)
            XCTAssertEqual(content.presetDuration, expectedPreset)
        }
    }

    func testActiveFaceCanOmitPresetDurationForOneOffTimers() {
        let content = CubeActiveDisplayContent(countdown: "12:34", presetSeconds: nil)

        XCTAssertEqual(content.countdown, "12:34")
        XCTAssertNil(content.presetDuration)
    }

    func testCustomPresetDurationWithSecondsKeepsItsExactValue() {
        let label = CubePresetDurationLabel(seconds: 1_325)

        XCTAssertEqual(label.value, "22:05")
        XCTAssertEqual(label.unit, "M : S")
    }

    func testDefaultAngleIsReadableAndTurnedAwayFaceNeedsReadout() {
        XCTAssertTrue(CubeDisplayReadability.readable(facing: 0.75,
                                                      previouslyReadable: nil))
        XCTAssertFalse(CubeDisplayReadability.readable(facing: 0.2,
                                                       previouslyReadable: true))
    }

    func testHysteresisAvoidsReadoutFlickerNearThreshold() {
        XCTAssertFalse(CubeDisplayReadability.readable(facing: 0.66,
                                                       previouslyReadable: false))
        XCTAssertTrue(CubeDisplayReadability.readable(facing: 0.66,
                                                      previouslyReadable: true))
        XCTAssertTrue(CubeDisplayReadability.readable(facing: 0.71,
                                                      previouslyReadable: false))
    }
}
