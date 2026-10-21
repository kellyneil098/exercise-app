import SwiftUI
import WorkoutEngine
import WorkoutUI

/// Minimal line-art pictogram of a movement, drawn from a small kinematic stick figure so limb
/// proportions are consistent and the implement is always in the hands. Each pose is chosen to show
/// correct form (neutral spine, bar over mid-foot, knees over toes, elbows tucked, etc.).
/// Unit box 100×60, scaled to fit; stroked only.
struct ExerciseArt: View {
    let exerciseKey: String
    let pattern: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.card)
            FigureShape(pose: Pose.for(exerciseKey: exerciseKey, pattern: pattern))
                .stroke(Theme.Colors.brass, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .padding(Theme.Spacing.m)
        }
        .aspectRatio(100.0 / 60.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// World angles in degrees: 0 = toward the front (+x), 90 = down, -90 = up, 180 = behind.
struct Pose {
    enum Implement { case none, barbell, dumbbell, dumbbellVertical, barbellOnHips, handle }
    enum Prop { case bench, inclineBench, seat, backrest, cable, cableFromBehind, highBar, dipBars, anklePad, calfBlock, rearBench, footBlock, chestPad }

    var hip: CGPoint
    var torso: CGFloat
    var upperArm: CGFloat, forearm: CGFloat
    var upperArm2: CGFloat? = nil, forearm2: CGFloat? = nil
    var thigh: CGFloat, shin: CGFloat
    var thigh2: CGFloat? = nil, shin2: CGFloat? = nil
    var implement: Implement = .none
    var props: [Prop] = []
    /// Translate so the lowest foot rests on the floor line.
    var grounded = true
    var floor = true

    static func `for`(exerciseKey key: String, pattern: String) -> Pose {
        var p = base(exerciseKey: key, pattern: pattern)
        if key.contains("dumbbell"), p.implement == .barbell { p.implement = .dumbbell }
        return p
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func base(exerciseKey key: String, pattern: String) -> Pose {
        if key.contains("push_up") {
            if key.contains("elevated") {   // feet on a block: body level/declined, hands still under shoulders
                return Pose(hip: CGPoint(x: 56, y: 38.6), torso: 175, upperArm: 90, forearm: 90, thigh: -5, shin: -5, props: [.footBlock], grounded: false)
            }
            return Pose(hip: CGPoint(x: 56, y: 46.5), torso: -156, upperArm: 90, forearm: 90, thigh: 24, shin: 24, grounded: false)
        }
        if key.contains("pushdown") {       // elbows pinned at the sides, forearms pressed down, cable overhead
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: 90, forearm: 80, thigh: 90, shin: 90, implement: .handle, props: [.cable])
        }
        if key.contains("pec_deck") || key.contains("reverse_fly_machine") {   // seated facing the pad, arms swept back
            return Pose(hip: CGPoint(x: 46, y: 38), torso: -90, upperArm: 175, forearm: 175, thigh: 0, shin: 90, implement: .handle, props: [.seat, .chestPad])
        }
        if key.contains("cable_crunch") {   // kneeling, rope held at the head, spine flexing toward the floor
            return Pose(hip: CGPoint(x: 50, y: 40), torso: -50, upperArm: -140, forearm: -40, thigh: 90, shin: 180, props: [.cable])
        }
        if key.contains("dip") {
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -75, upperArm: 150, forearm: 90, thigh: 100, shin: 170, props: [.dipBars], grounded: false)
        }
        if key.contains("pull_up") || key.contains("chin_up") {
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: -125, forearm: -55, thigh: 95, shin: 120, props: [.highBar], grounded: false, floor: false)
        }
        if key.contains("bulgarian") {      // rear foot up on a bench, front shin vertical, torso tall
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: 90, forearm: 90, thigh: 0, shin: 90, thigh2: 135, shin2: 190, implement: .dumbbellVertical, props: [.rearBench])
        }
        if key.contains("lunge") || key.contains("split_squat") || key.contains("step_up") {
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: 90, forearm: 90, thigh: 0, shin: 90, thigh2: 125, shin2: 170, implement: .dumbbellVertical)
        }
        if key.contains("hip_thrust") {
            return Pose(hip: CGPoint(x: 56, y: 40), torso: 180, upperArm: 0, forearm: 0, thigh: 0, shin: 90, implement: .barbellOnHips, props: [.bench])
        }
        if key.contains("plank") || key.contains("hollow") || key.contains("pallof") {
            return Pose(hip: CGPoint(x: 56, y: 52), torso: -165, upperArm: 90, forearm: 0, thigh: 15, shin: 15, grounded: false)
        }
        if key.contains("hanging") {
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: -60, forearm: -120, thigh: 0, shin: 20, props: [.highBar], grounded: false, floor: false)
        }
        if key.contains("dead_bug") || key.contains("bird_dog") {
            return Pose(hip: CGPoint(x: 52, y: 52), torso: 180, upperArm: -90, forearm: -90, upperArm2: -170, forearm2: -170, thigh: 10, shin: 10, thigh2: -90, shin2: 0, grounded: false)
        }
        switch pattern {
        case "horizontal_press":
            return Pose(hip: CGPoint(x: 58, y: 40), torso: 180, upperArm: -70, forearm: -90, thigh: 60, shin: 90, implement: .barbell, props: [.bench])
        case "incline_press":
            return Pose(hip: CGPoint(x: 58, y: 42), torso: -145, upperArm: -75, forearm: -90, thigh: 60, shin: 90, implement: .barbell, props: [.inclineBench])
        case "vertical_press":
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: -60, forearm: -120, thigh: 90, shin: 90, implement: .barbell)
        case "chest_fly" where key.contains("cable"):   // standing, slight lean, arms sweeping together in front
            return Pose(hip: CGPoint(x: 46, y: 36), torso: -80, upperArm: -10, forearm: 0, thigh: 90, shin: 90, implement: .handle, props: [.cableFromBehind])
        case "chest_fly":
            return Pose(hip: CGPoint(x: 58, y: 40), torso: 180, upperArm: -40, forearm: -55, upperArm2: -140, forearm2: -125, thigh: 60, shin: 90, implement: .dumbbell, props: [.bench])
        case "lateral_raise":
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: 0, forearm: 5, upperArm2: 180, forearm2: 175, thigh: 90, shin: 90, implement: .dumbbellVertical)
        case "triceps_extension":
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: -90, forearm: 135, thigh: 90, shin: 90, implement: .dumbbell)
        case "vertical_pull":
            return Pose(hip: CGPoint(x: 46, y: 38), torso: -100, upperArm: 120, forearm: -30, thigh: 0, shin: 90, implement: .barbell, props: [.cable, .seat])
        case "horizontal_row":
            return Pose(hip: CGPoint(x: 44, y: 34), torso: -45, upperArm: 120, forearm: 30, thigh: 95, shin: 85, implement: .barbell)
        case "rear_delt":
            return Pose(hip: CGPoint(x: 44, y: 34), torso: -45, upperArm: -135, forearm: -120, thigh: 95, shin: 85, implement: .dumbbell)
        case "elbow_flexion":
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: 90, forearm: 0, thigh: 90, shin: 90, implement: .dumbbellVertical)
        case "squat":
            return Pose(hip: CGPoint(x: 44, y: 36), torso: -62, upperArm: -170, forearm: -10, thigh: 5, shin: 100, implement: .barbell)
        case "hinge":
            return Pose(hip: CGPoint(x: 40, y: 32), torso: -38, upperArm: 90, forearm: 90, thigh: 40, shin: 75, implement: .barbell)
        case "quad_isolation":
            return Pose(hip: CGPoint(x: 44, y: 36), torso: -90, upperArm: 90, forearm: 90, thigh: 0, shin: 0, props: [.seat, .backrest, .anklePad], grounded: false)
        case "hamstring_isolation":
            return Pose(hip: CGPoint(x: 54, y: 42), torso: 180, upperArm: 150, forearm: 90, thigh: 0, shin: -90, props: [.bench, .anklePad], grounded: false)
        case "calf":
            return Pose(hip: CGPoint(x: 46, y: 33), torso: -90, upperArm: -10, forearm: -10, thigh: 90, shin: 90, props: [.calfBlock])
        default: // crunch
            return Pose(hip: CGPoint(x: 50, y: 54), torso: -155, upperArm: -120, forearm: 160, thigh: -50, shin: 70, grounded: false)
        }
    }
}

struct FigureShape: Shape {
    let pose: Pose

    private let torsoLen: CGFloat = 16, neck: CGFloat = 2, headR: CGFloat = 3.5
    private let upperArmLen: CGFloat = 8, forearmLen: CGFloat = 8, thighLen: CGFloat = 10, shinLen: CGFloat = 10
    private let floorY: CGFloat = 56

    func path(in rect: CGRect) -> Path {
        var p = Path()
        draw(&p)
        let s = min(rect.width / 100, rect.height / 60)
        return p.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: rect.midX - 50 * s, ty: rect.midY - 30 * s))
    }

    private func seg(_ from: CGPoint, _ angle: CGFloat, _ len: CGFloat) -> CGPoint {
        let r = angle * .pi / 180
        return CGPoint(x: from.x + len * cos(r), y: from.y + len * sin(r))
    }

    private func line(_ p: inout Path, _ a: CGPoint, _ b: CGPoint) { p.move(to: a); p.addLine(to: b) }
    private func line(_ p: inout Path, _ a: CGPoint, dx: CGFloat, dy: CGFloat) { line(&p, a, CGPoint(x: a.x + dx, y: a.y + dy)) }

    private func barbell(_ p: inout Path, at c: CGPoint, halfWidth: CGFloat = 16, plate: CGFloat = 5) {
        line(&p, CGPoint(x: c.x - halfWidth, y: c.y), CGPoint(x: c.x + halfWidth, y: c.y))
        for x in [c.x - halfWidth, c.x + halfWidth] { line(&p, CGPoint(x: x, y: c.y - plate), CGPoint(x: x, y: c.y + plate)) }
    }

    private func dumbbell(_ p: inout Path, at c: CGPoint, vertical: Bool) {
        if vertical {
            line(&p, CGPoint(x: c.x, y: c.y - 3.5), CGPoint(x: c.x, y: c.y + 3.5))
            for y in [c.y - 3.5, c.y + 3.5] { line(&p, CGPoint(x: c.x - 2.5, y: y), CGPoint(x: c.x + 2.5, y: y)) }
        } else {
            line(&p, CGPoint(x: c.x - 3.5, y: c.y), CGPoint(x: c.x + 3.5, y: c.y))
            for x in [c.x - 3.5, c.x + 3.5] { line(&p, CGPoint(x: x, y: c.y - 2.5), CGPoint(x: x, y: c.y + 2.5)) }
        }
    }

    private func draw(_ p: inout Path) {
        let P = pose
        var hip = P.hip
        var shoulder = seg(hip, P.torso, torsoLen)
        var head = seg(shoulder, P.torso, neck + headR)
        var arms = [(seg(shoulder, P.upperArm, upperArmLen), P.forearm)].map { ($0.0, seg($0.0, $0.1, forearmLen)) }
        if let ua = P.upperArm2, let fa = P.forearm2 { let e = seg(shoulder, ua, upperArmLen); arms.append((e, seg(e, fa, forearmLen))) }
        var legs = [(seg(hip, P.thigh, thighLen), P.shin)].map { ($0.0, seg($0.0, $0.1, shinLen), $0.1) }
        if let th = P.thigh2, let sh = P.shin2 { let k = seg(hip, th, thighLen); legs.append((k, seg(k, sh, shinLen), sh)) }

        if P.grounded {
            let dy = floorY - (legs.map(\.1.y).max() ?? floorY)
            func t(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x, y: q.y + dy) }
            hip = t(hip); shoulder = t(shoulder); head = t(head)
            arms = arms.map { (t($0.0), t($0.1)) }
            legs = legs.map { (t($0.0), t($0.1), $0.2) }
        }

        // Figure
        line(&p, hip, shoulder)
        p.addEllipse(in: CGRect(x: head.x - headR, y: head.y - headR, width: 2 * headR, height: 2 * headR))
        for (elbow, hand) in arms { line(&p, shoulder, elbow); line(&p, elbow, hand) }
        for (knee, foot, shinAngle) in legs {
            line(&p, hip, knee); line(&p, knee, foot)
            if abs(cos(shinAngle * .pi / 180)) < 0.5 { line(&p, foot, dx: 3.5, dy: 0) }
        }
        if P.floor { line(&p, CGPoint(x: 8, y: floorY), CGPoint(x: 92, y: floorY)) }

        // Implement, always in the hands
        let hand = arms[0].1
        switch P.implement {
        case .none: break
        case .barbell: barbell(&p, at: hand)
        case .barbellOnHips: barbell(&p, at: hip, halfWidth: 12)
        case .dumbbell: for (_, h) in arms { dumbbell(&p, at: h, vertical: false) }
        case .dumbbellVertical: for (_, h) in arms { dumbbell(&p, at: h, vertical: true) }
        case .handle: line(&p, CGPoint(x: hand.x - 3, y: hand.y), CGPoint(x: hand.x + 3, y: hand.y))
        }

        // Props
        for prop in P.props {
            switch prop {
            case .bench:
                let y = shoulder.y + 2.5
                line(&p, CGPoint(x: shoulder.x - 10, y: y), CGPoint(x: hip.x + 4, y: y))
                line(&p, CGPoint(x: shoulder.x - 6, y: y), CGPoint(x: shoulder.x - 6, y: floorY))
                line(&p, CGPoint(x: hip.x, y: y), CGPoint(x: hip.x, y: floorY))
            case .inclineBench:
                let seat = CGPoint(x: hip.x + 2, y: hip.y + 2.5)
                line(&p, seat, CGPoint(x: shoulder.x - 6, y: shoulder.y - 2))
                line(&p, seat, CGPoint(x: seat.x, y: floorY))
                line(&p, CGPoint(x: hip.x - 8, y: seat.y), seat)
            case .seat:
                line(&p, CGPoint(x: hip.x - 6, y: hip.y + 2.5), CGPoint(x: hip.x + 8, y: hip.y + 2.5))
                line(&p, CGPoint(x: hip.x - 4, y: hip.y + 2.5), CGPoint(x: hip.x - 4, y: floorY))
            case .backrest:
                line(&p, CGPoint(x: hip.x - 5, y: hip.y + 2.5), CGPoint(x: shoulder.x - 3, y: shoulder.y - 4))
            case .cable:
                line(&p, hand, CGPoint(x: hand.x + 2, y: 4))
                line(&p, CGPoint(x: hand.x - 12, y: 4), CGPoint(x: hand.x + 16, y: 4))
            case .cableFromBehind:
                line(&p, hand, CGPoint(x: hand.x - 30, y: 4))
                line(&p, CGPoint(x: hand.x - 34, y: 4), CGPoint(x: hand.x - 26, y: 4))
            case .rearBench:
                let f = legs[1].1
                line(&p, CGPoint(x: f.x - 6, y: f.y + 1), CGPoint(x: f.x + 5, y: f.y + 1))
                for x in [f.x - 4, f.x + 3] { line(&p, CGPoint(x: x, y: f.y + 1), CGPoint(x: x, y: floorY)) }
            case .footBlock:
                let f = legs[0].1
                line(&p, CGPoint(x: f.x - 4, y: f.y + 1), CGPoint(x: f.x + 5, y: f.y + 1))
                for x in [f.x - 4, f.x + 5] { line(&p, CGPoint(x: x, y: f.y + 1), CGPoint(x: x, y: floorY)) }
            case .chestPad:
                line(&p, CGPoint(x: shoulder.x + 3, y: shoulder.y - 5), CGPoint(x: shoulder.x + 3, y: hip.y + 2.5))
            case .highBar:
                line(&p, CGPoint(x: hand.x - 20, y: hand.y), CGPoint(x: hand.x + 20, y: hand.y))
                for x in [hand.x - 20, hand.x + 20] { line(&p, CGPoint(x: x, y: hand.y), CGPoint(x: x, y: hand.y - 6)) }
            case .dipBars:
                line(&p, CGPoint(x: hand.x - 14, y: hand.y), CGPoint(x: hand.x + 14, y: hand.y))
                for x in [hand.x - 10, hand.x + 10] { line(&p, CGPoint(x: x, y: hand.y), CGPoint(x: x, y: floorY)) }
            case .anklePad:
                let foot = legs[0].1
                let seated = abs(cos(legs[0].2 * .pi / 180)) > 0.5
                dumbbell(&p, at: CGPoint(x: foot.x, y: foot.y + (seated ? 2 : 0)), vertical: seated)
            case .calfBlock:
                let f = legs[0].1
                line(&p, CGPoint(x: f.x + 2, y: f.y), CGPoint(x: f.x - 3, y: f.y - 3))       // raised heel
                line(&p, CGPoint(x: f.x + 1, y: f.y), CGPoint(x: f.x + 5, y: f.y))
                line(&p, CGPoint(x: f.x - 6, y: floorY), CGPoint(x: f.x + 8, y: floorY))      // block
                line(&p, CGPoint(x: f.x + 8, y: floorY), CGPoint(x: f.x + 8, y: floorY - 4))
                line(&p, CGPoint(x: f.x - 6, y: floorY - 4), CGPoint(x: f.x + 8, y: floorY - 4))
                line(&p, CGPoint(x: hand.x + 1, y: hand.y - 12), CGPoint(x: hand.x + 1, y: floorY))   // support rail
            }
        }
    }
}
