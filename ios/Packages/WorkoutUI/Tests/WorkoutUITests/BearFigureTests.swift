import XCTest
import CoreGraphics
@testable import WorkoutUI

/// The bear's ears must sit on the crown (further from the neck than the head centre) and turn with the head.
final class BearFigureTests: XCTestCase {
    /// (name, head angle in degrees: 0 = facing +x, 90 = down, -90 = up)
    private let samples: [(String, CGFloat)] = [("standing", -90), ("hinged", -45), ("lying face up", 0), ("lying face down", 180), ("inverted", 90), ("tilted", -110)]

    private func unit(_ deg: CGFloat) -> CGPoint { CGPoint(x: cos(deg * .pi / 180), y: sin(deg * .pi / 180)) }
    private func normal(_ deg: CGFloat) -> CGPoint { CGPoint(x: -sin(deg * .pi / 180), y: cos(deg * .pi / 180)) }
    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    func testEarsSitOnTheCrownInEveryPose() {
        let r: CGFloat = 5.4, neckLen: CGFloat = 6.6
        for (name, deg) in samples {
            let up = unit(deg), side = normal(deg)
            let neck = CGPoint(x: 10, y: 20)
            let head = CGPoint(x: neck.x + up.x * neckLen, y: neck.y + up.y * neckLen)
            let ears = BearFigure.earCentres(head: head, up: up, side: side, r: r)
            XCTAssertEqual(ears.count, 2, name)
            let mid = CGPoint(x: (ears[0].x + ears[1].x) / 2, y: (ears[0].y + ears[1].y) / 2)
            XCTAssertGreaterThan(dist(mid, neck), dist(head, neck) + r * 0.5, "\(name): ear midpoint should be beyond the head centre, away from the neck")
            for ear in ears {
                XCTAssertEqual(dist(ear, head), r * 0.65 * sqrt(2), accuracy: 0.01, "\(name): ears ride the skull rim")
                // Ears peek out past the head circle but never float free of it.
                XCTAssertGreaterThan(dist(ear, head) + BearFigure.earRadiusRatio * r, r, name)
                XCTAssertLessThan(dist(ear, head), r, name)
            }
            // Symmetric about the up axis: both ears are the same distance along `up`.
            let along0 = (ears[0].x - head.x) * up.x + (ears[0].y - head.y) * up.y
            let along1 = (ears[1].x - head.x) * up.x + (ears[1].y - head.y) * up.y
            XCTAssertEqual(along0, along1, accuracy: 0.001, name)
            XCTAssertGreaterThan(along0, 0, "\(name): ears are above the head centre, toward the crown")
        }
    }
}
