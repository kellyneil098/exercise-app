import XCTest
@testable import WorkoutEngine

/// Thresholds and axis locking for the overview's swipeable rows.
final class RowSwipeTests: XCTestCase {
    let swipe = RowSwipe()   // threshold 96, dead zone 20, axis bias 1.5, momentum 0.3, resistance 0.2
    let both: Set<RowSwipe.Direction> = [.left, .right]
    let restoreOnly: Set<RowSwipe.Direction> = [.right]

    func testClearlySidewaysDragsLockHorizontal() {
        XCTAssertEqual(swipe.lock(width: 30, height: 10), .horizontal)
        XCTAssertEqual(swipe.lock(width: -40, height: 20), .horizontal)
    }

    func testDiagonalAndVerticalDragsBelongToTheList() {
        XCTAssertEqual(swipe.lock(width: 30, height: 25), .vertical, "needs 1.5× more sideways than vertical")
        XCTAssertEqual(swipe.lock(width: 10, height: 40), .vertical)
        XCTAssertEqual(swipe.lock(width: 0, height: 0), .vertical, "nothing moved yet: leave it to the list")
    }

    func testDeadZoneShowsNothing() {
        XCTAssertNil(swipe.pending(width: 10, allowing: both))
        XCTAssertNil(swipe.pending(width: -20, allowing: both))
    }

    func testPendingStrengthGrowsToOneAtTheThreshold() {
        let half = swipe.pending(width: 58, allowing: both)
        XCTAssertEqual(half?.direction, .right)
        XCTAssertEqual(half!.strength, 0.5, accuracy: 0.001)
        let full = swipe.pending(width: -96, allowing: both)
        XCTAssertEqual(full?.direction, .left)
        XCTAssertEqual(full!.strength, 1, accuracy: 0.001)
        XCTAssertEqual(swipe.pending(width: 300, allowing: both)!.strength, 1, "capped past the threshold")
    }

    func testLeftIsDeleteAndRightIsSwapOrRestore() {
        XCTAssertEqual(swipe.resolve(width: -120, predictedWidth: -120, allowing: both), .left)
        XCTAssertEqual(swipe.resolve(width: 120, predictedWidth: 120, allowing: both), .right)
    }

    func testShortDragSnapsBack() {
        XCTAssertNil(swipe.resolve(width: 90, predictedWidth: 90, allowing: both))
        XCTAssertNil(swipe.resolve(width: -50, predictedWidth: -50, allowing: both))
    }

    func testAFlickCommitsWithMomentum() {
        // 90 + 0.3 × (150 − 90) = 108 > 96
        XCTAssertEqual(swipe.resolve(width: 90, predictedWidth: 150, allowing: both), .right)
        // 90 + 0.3 × (100 − 90) = 93 < 96
        XCTAssertNil(swipe.resolve(width: 90, predictedWidth: 100, allowing: both))
    }

    func testDeletedRowsOnlyRestore() {
        XCTAssertNil(swipe.pending(width: -80, allowing: restoreOnly))
        XCTAssertNil(swipe.resolve(width: -200, predictedWidth: -200, allowing: restoreOnly))
        XCTAssertEqual(swipe.resolve(width: 120, predictedWidth: 120, allowing: restoreOnly), .right)
        XCTAssertEqual(swipe.travel(width: -80, allowing: restoreOnly), -16, accuracy: 0.001, "rubber-bands the way that does nothing")
        XCTAssertEqual(swipe.travel(width: 80, allowing: restoreOnly), 80, accuracy: 0.001)
    }

    func testCustomThresholdsAreHonoured() {
        let tight = RowSwipe(threshold: 50, deadZone: 10, axisBias: 1, momentum: 0, resistance: 0)
        XCTAssertEqual(tight.lock(width: 11, height: 10), .horizontal)
        XCTAssertEqual(tight.pending(width: 30, allowing: both)!.strength, 0.5, accuracy: 0.001)
        XCTAssertNil(tight.resolve(width: 45, predictedWidth: 500, allowing: both), "no momentum: prediction ignored")
        XCTAssertEqual(tight.travel(width: -40, allowing: restoreOnly), 0, accuracy: 0.001)
    }
}
