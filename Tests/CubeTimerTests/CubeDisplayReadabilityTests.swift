import XCTest
@testable import CubeTimer

final class CubeDisplayReadabilityTests: XCTestCase {
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
