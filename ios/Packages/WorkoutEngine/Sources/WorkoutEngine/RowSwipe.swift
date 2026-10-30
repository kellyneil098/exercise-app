import Foundation

/// The arithmetic behind a swipeable overview row — axis lock, dead zone, threshold, momentum — kept out of the
/// view so it can be tested without a gesture. Distances are points; right is positive.
public struct RowSwipe: Equatable, Sendable {
    public enum Direction: Equatable, Sendable { case left, right }
    public enum Lock: Equatable, Sendable { case horizontal, vertical }

    /// Drag distance that commits the action.
    public var threshold: Double
    /// Movement under this shows nothing, so a nudge while scrolling never tints the row.
    public var deadZone: Double
    /// A drag must be this many times more sideways than vertical to count as a swipe at all.
    public var axisBias: Double
    /// Share of the predicted overshoot that counts toward the threshold, so a flick commits sooner.
    public var momentum: Double
    /// How far a row follows the finger in a direction that does nothing.
    public var resistance: Double

    public init(threshold: Double = 96, deadZone: Double = 20, axisBias: Double = 1.5, momentum: Double = 0.3, resistance: Double = 0.2) {
        self.threshold = threshold; self.deadZone = deadZone; self.axisBias = axisBias; self.momentum = momentum; self.resistance = resistance
    }

    /// Decided once, from the drag's first clear movement. Anything not clearly sideways belongs to the list
    /// (scroll or reorder) for the rest of the gesture.
    public func lock(width: Double, height: Double) -> Lock {
        abs(width) > abs(height) * axisBias ? .horizontal : .vertical
    }

    public static func direction(of width: Double) -> Direction { width < 0 ? .left : .right }

    /// How far the row actually moves for a horizontal drag: freely toward an action, rubber-banded otherwise.
    public func travel(width: Double, allowing directions: Set<Direction>) -> Double {
        directions.contains(Self.direction(of: width)) ? width : width * resistance
    }

    /// What letting go now would do and how committed the drag is (0…1 at the threshold); `nil` inside the dead zone
    /// or toward a direction that does nothing.
    public func pending(width: Double, allowing directions: Set<Direction>) -> (direction: Direction, strength: Double)? {
        let direction = Self.direction(of: width)
        guard directions.contains(direction), abs(width) > deadZone else { return nil }
        return (direction, min(1, (abs(width) - deadZone) / (threshold - deadZone)))
    }

    /// The action a finished drag commits to, with a little momentum from the predicted end, or `nil` to snap back.
    public func resolve(width: Double, predictedWidth: Double, allowing directions: Set<Direction>) -> Direction? {
        let x = width + (predictedWidth - width) * momentum
        let direction = Self.direction(of: x)
        guard directions.contains(direction), abs(x) > threshold else { return nil }
        return direction
    }
}
