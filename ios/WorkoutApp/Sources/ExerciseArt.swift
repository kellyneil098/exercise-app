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
    enum Implement { case none, barbell, barbellNarrow, shortBar, trapBar, dumbbell, dumbbellVertical, dumbbellFirst, barbellOnHips, handle, kettlebell, wheel }
    enum Prop {
        case bench, inclineBench, declineBench, seat, backrest, hackPad, frontPad, preacherPad, chestPad, kneePad, shoulderPads
        case cable, cableFromBehind, cableLowFront, cableBehindLow, cableFrontLevel
        case highBar, dipBars, smithRails, machineArm, tBar, post, supportRail, supportBench, handBench
        case anklePad, heelAnchor, calfBlock, rearBench, footBlock, footPlate, dipBelt
    }

    var hip: CGPoint
    var torso: CGFloat
    /// Neck direction when it should differ from the torso (e.g. looking at the floor in a quadruped).
    var headAngle: CGFloat? = nil
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
        if key.contains("barbell"), p.implement == .dumbbell { p.implement = .barbell }
        if key.contains("smith"), !p.props.contains(.smithRails) { p.props.append(.smithRails) }
        return p
    }

    // MARK: Standing / lying bases shared by several variants

    private static let standing = Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: 90, forearm: 90, thigh: 90, shin: 90)
    private static let seated = Pose(hip: CGPoint(x: 44, y: 38), torso: -90, upperArm: 90, forearm: 90, thigh: 0, shin: 90, props: [.seat, .backrest])
    private static let benchPress = Pose(hip: CGPoint(x: 58, y: 40), torso: 180, upperArm: -70, forearm: -90, thigh: 60, shin: 90, implement: .barbell, props: [.bench])
    private static let hinge = Pose(hip: CGPoint(x: 40, y: 32), torso: -38, upperArm: 90, forearm: 90, thigh: 40, shin: 75, implement: .barbell)
    private static let squat = Pose(hip: CGPoint(x: 44, y: 36), torso: -62, upperArm: -170, forearm: 10, thigh: 5, shin: 100, implement: .barbell)
    private static let row = Pose(hip: CGPoint(x: 44, y: 34), torso: -45, upperArm: 120, forearm: 30, thigh: 95, shin: 85, implement: .barbell)
    private static let hanging = Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: -135, forearm: -45, thigh: 95, shin: 120, props: [.highBar], grounded: false, floor: false)

    private static func variant(_ base: Pose, _ change: (inout Pose) -> Void) -> Pose { var p = base; change(&p); return p }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func base(exerciseKey key: String, pattern: String) -> Pose {
        switch key {
        // MARK: Press
        case "decline_push_up":   // feet on a block: body level/declined, hands still under shoulders
            return Pose(hip: CGPoint(x: 56, y: 38.6), torso: 175, upperArm: 90, forearm: 90, thigh: -5, shin: -5, props: [.footBlock], grounded: false)
        case "push_up":
            return Pose(hip: CGPoint(x: 56, y: 46.5), torso: -156, upperArm: 90, forearm: 90, thigh: 24, shin: 24, grounded: false)
        case "dumbbell_floor_press":   // on the floor, knees bent, elbows stop at the floor
            return Pose(hip: CGPoint(x: 56, y: 52.5), torso: 180, upperArm: -70, forearm: -90, thigh: -40, shin: 100, implement: .dumbbell, grounded: false)
        case "close_grip_bench_press":
            return variant(benchPress) { $0.implement = .barbellNarrow }
        case "machine_chest_press":   // seated, back on the pad, pressing the handles straight out
            return variant(seated) { $0.upperArm = 0; $0.forearm = 0; $0.implement = .handle; $0.props.append(.machineArm) }
        case "machine_shoulder_press":
            return variant(seated) { $0.upperArm = 0; $0.forearm = -90; $0.implement = .handle; $0.props.append(.machineArm) }
        case "seated_dumbbell_press", "dumbbell_shoulder_press":
            return variant(seated) { $0.upperArm = -45; $0.forearm = -135; $0.implement = .dumbbell }
        case "arnold_press":   // start: dumbbells in front of the shoulders, elbows in
            return variant(seated) { $0.upperArm = 40; $0.forearm = -70; $0.implement = .dumbbellVertical }
        case "weighted_dip":
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -75, upperArm: 150, forearm: 90, thigh: 100, shin: 170, props: [.dipBars, .dipBelt], grounded: false)
        case "bench_dip":   // hands on the bench behind, feet out front, elbows pointing back
            return Pose(hip: CGPoint(x: 52, y: 44), torso: -80, upperArm: 160, forearm: 90, thigh: 10, shin: 60, props: [.handBench])
        case "skullcrusher":   // lying, upper arms vertical, bar lowered behind the head
            return variant(benchPress) { $0.upperArm = -90; $0.forearm = 180; $0.implement = .shortBar }
        case "dumbbell_overhead_extension":   // stretch position: elbows up, dumbbell behind the head
            return variant(standing) { $0.upperArm = -80; $0.forearm = -160; $0.implement = .dumbbellVertical }
        case "overhead_cable_extension":   // facing away from the stack, slight lean, elbows forward
            return Pose(hip: CGPoint(x: 46, y: 36), torso: -70, upperArm: -100, forearm: -40, thigh: 80, shin: 90, implement: .handle, props: [.cableFromBehind])
        case "cable_pushdown":   // elbows pinned at the sides, forearms pressed down, cable overhead
            return variant(standing) { $0.upperArm = 90; $0.forearm = 80; $0.implement = .handle; $0.props = [.cable] }
        case "pec_deck_fly":   // seated, forearms on the pads, elbows at shoulder height squeezing forward
            return variant(seated) { $0.upperArm = 0; $0.forearm = -70; $0.props.append(.machineArm) }
        case "reverse_pec_deck":   // seated facing the pad, arms swept back
            return Pose(hip: CGPoint(x: 46, y: 38), torso: -90, upperArm: 175, forearm: 175, thigh: 0, shin: 90, implement: .handle, props: [.seat, .chestPad])
        case "cable_fly":   // standing, slight lean, arms sweeping together in front
            return Pose(hip: CGPoint(x: 46, y: 36), torso: -80, upperArm: -10, forearm: 0, thigh: 90, shin: 90, implement: .handle, props: [.cableFromBehind])
        case "cable_lateral_raise":
            return variant(standing) { $0.upperArm = 0; $0.forearm = 5; $0.implement = .handle; $0.props = [.cableLowFront] }
        case "lean_away_lateral_raise":   // holding the post, body tilted away from it
            return variant(standing) { $0.torso = -75; $0.upperArm = 0; $0.forearm = 5; $0.upperArm2 = 170; $0.forearm2 = 170; $0.implement = .handle; $0.props = [.cableLowFront, .post] }

        // MARK: Pull
        case "pull_up", "weighted_pull_up":
            return variant(hanging) { if key == "weighted_pull_up" { $0.props.append(.dipBelt) } }
        case "chin_up":   // narrower grip
            return variant(hanging) { $0.upperArm = -115; $0.forearm = -65 }
        case "neutral_grip_pulldown":
            return variant(latPulldown) { $0.implement = .barbellNarrow }
        case "straight_arm_pulldown":   // arms locked, hinging from the shoulder
            return Pose(hip: CGPoint(x: 46, y: 36), torso: -80, upperArm: -30, forearm: -30, thigh: 85, shin: 90, implement: .barbellNarrow, props: [.cable])
        case "kneeling_cable_pulldown":
            return Pose(hip: CGPoint(x: 46, y: 40), torso: -90, upperArm: -40, forearm: -110, thigh: 90, shin: 180, implement: .handle, props: [.cable])
        case "pendlay_row":   // back parallel to the floor, bar starts on the floor every rep
            return Pose(hip: CGPoint(x: 40, y: 34), torso: -20, headAngle: 10, upperArm: 90, forearm: 90, thigh: 40, shin: 75, implement: .barbell)
        case "t_bar_row":
            return variant(row) { $0.implement = .handle; $0.props = [.tBar] }
        case "chest_supported_row":   // chest on the incline pad, arms pulling from below it
            return Pose(hip: CGPoint(x: 44, y: 38), torso: -50, upperArm: 100, forearm: 100, thigh: 90, shin: 90, implement: .handle, props: [.seat, .frontPad])
        case "seated_cable_row":   // tall seat, feet braced on the plate, arms reaching to the handle
            return Pose(hip: CGPoint(x: 40, y: 44), torso: -95, upperArm: 10, forearm: 0, thigh: -10, shin: 40, implement: .handle, props: [.seat, .cableFrontLevel, .footPlate], grounded: false)
        case "single_arm_dumbbell_row":   // one hand braced on the bench, dumbbell hanging from the other
            return Pose(hip: CGPoint(x: 40, y: 36), torso: -30, upperArm: 100, forearm: 90, upperArm2: 60, forearm2: 60, thigh: 75, shin: 85, thigh2: 55, shin2: 80, implement: .dumbbellFirst, props: [.supportBench])
        case "inverted_row":   // straight body under the bar, heels on the floor
            return Pose(hip: CGPoint(x: 50, y: 49), torso: -160, upperArm: -90, forearm: -90, thigh: 20, shin: 20, props: [.highBar])
        case "face_pull":   // cable at face height, pulling toward the eyes
            return variant(standing) { $0.upperArm = -20; $0.forearm = -20; $0.thigh = 80; $0.thigh2 = 100; $0.shin2 = 90; $0.implement = .handle; $0.props = [.cableFrontLevel] }
        case "cable_reverse_fly":
            return variant(standing) { $0.torso = -80; $0.upperArm = 0; $0.forearm = 0; $0.implement = .handle; $0.props = [.cableFrontLevel] }

        // MARK: Arms
        case "hammer_curl":
            return variant(standing) { $0.upperArm = 90; $0.forearm = 0; $0.implement = .dumbbellVertical }
        case "cable_curl":
            return variant(standing) { $0.upperArm = 90; $0.forearm = 0; $0.implement = .handle; $0.props = [.cableLowFront] }
        case "preacher_curl":   // armpits over the top of the pad, upper arms flat on it
            return Pose(hip: CGPoint(x: 44, y: 38), torso: -90, upperArm: 35, forearm: -50, thigh: 0, shin: 90, implement: .shortBar, props: [.seat, .preacherPad])
        case "incline_dumbbell_curl":   // arms hang behind the torso line for the long-head stretch
            return Pose(hip: CGPoint(x: 52, y: 42), torso: -130, upperArm: 100, forearm: 20, thigh: 60, shin: 90, implement: .dumbbell, props: [.inclineBench])

        // MARK: Legs
        case "front_squat":   // bar racked on the front of the shoulders, elbows high, torso tall
            return variant(squat) { $0.torso = -75; $0.upperArm = -10; $0.forearm = 165 }
        case "goblet_squat":
            return variant(squat) { $0.torso = -80; $0.upperArm = 60; $0.forearm = -70; $0.implement = .dumbbellVertical }
        case "hack_squat":   // back on the angled pad, feet forward on the platform
            return Pose(hip: CGPoint(x: 44, y: 36), torso: -120, upperArm: 110, forearm: 60, thigh: 0, shin: 80, props: [.hackPad])
        case "leg_press":   // reclined, feet high on the plate, knees tracking over the feet
            return Pose(hip: CGPoint(x: 40, y: 42), torso: -130, upperArm: 20, forearm: 60, thigh: -50, shin: -10, props: [.seat, .backrest, .footPlate], grounded: false)
        case "bulgarian_split_squat":   // rear foot up on a bench, front shin vertical, torso tall
            return Pose(hip: CGPoint(x: 50, y: 36), torso: -90, upperArm: 90, forearm: 90, thigh: 0, shin: 90, thigh2: 135, shin2: 190, implement: .dumbbellVertical, props: [.rearBench])
        case "walking_lunge":   // front shin vertical, rear knee just off the floor
            return variant(standing) { $0.thigh = 0; $0.thigh2 = 125; $0.shin2 = 170; $0.implement = .dumbbellVertical }
        case "reverse_lunge":   // mid-step: standing tall, rear foot reaching back
            return variant(standing) { $0.thigh2 = 120; $0.shin2 = 150; $0.implement = .dumbbellVertical }
        case "step_up":   // front foot on the box, driving up through the heel
            return variant(standing) { $0.thigh = -10; $0.thigh2 = 90; $0.shin2 = 90; $0.implement = .dumbbellVertical; $0.props = [.footBlock] }
        case "romanian_deadlift":   // soft knees, hips back, bar sliding down the thighs
            return Pose(hip: CGPoint(x: 42, y: 32), torso: -28, upperArm: 100, forearm: 100, thigh: 60, shin: 80, implement: .barbell)
        case "trap_bar_deadlift":
            return variant(hinge) { $0.implement = .trapBar }
        case "good_morning":   // bar across the upper back, hinge with soft knees
            return Pose(hip: CGPoint(x: 42, y: 32), torso: -28, upperArm: -170, forearm: 30, thigh: 75, shin: 85, implement: .barbell)
        case "kettlebell_swing":   // bottom of the swing: hinge, bell between the knees
            return Pose(hip: CGPoint(x: 44, y: 34), torso: -35, upperArm: 95, forearm: 95, thigh: 50, shin: 80, implement: .kettlebell)
        case "cable_pull_through":   // facing away from the low pulley, rope between the legs
            return Pose(hip: CGPoint(x: 44, y: 32), torso: -30, upperArm: 120, forearm: 150, thigh: 60, shin: 85, implement: .handle, props: [.cableBehindLow])
        case "barbell_hip_thrust":
            return Pose(hip: CGPoint(x: 56, y: 40), torso: 180, upperArm: 0, forearm: 0, thigh: 0, shin: 90, implement: .barbellOnHips, props: [.bench])
        case "seated_leg_curl":
            return Pose(hip: CGPoint(x: 44, y: 38), torso: -95, upperArm: 20, forearm: 60, thigh: 0, shin: 60, props: [.seat, .backrest, .anklePad])
        case "nordic_curl":   // knees down, ankles anchored, straight line from knee to head
            return Pose(hip: CGPoint(x: 44, y: 46), torso: -70, upperArm: 60, forearm: 180, thigh: 110, shin: 180, props: [.heelAnchor])
        case "standing_calf_raise":   // shoulders under the pads, heels off the block
            return Pose(hip: CGPoint(x: 46, y: 33), torso: -90, upperArm: -20, forearm: -70, thigh: 90, shin: 90, implement: .handle, props: [.calfBlock, .shoulderPads])
        case "seated_calf_raise":
            return Pose(hip: CGPoint(x: 44, y: 38), torso: -90, upperArm: 40, forearm: 60, thigh: 0, shin: 90, props: [.seat, .calfBlock, .kneePad])
        case "dumbbell_calf_raise":   // one hand holds the weight, the other the rail
            return Pose(hip: CGPoint(x: 46, y: 33), torso: -90, upperArm: 90, forearm: 90, upperArm2: -10, forearm2: -10, thigh: 90, shin: 90, implement: .dumbbellFirst, props: [.calfBlock, .supportRail])
        case "bodyweight_calf_raise":
            return Pose(hip: CGPoint(x: 46, y: 33), torso: -90, upperArm: -10, forearm: -10, thigh: 90, shin: 90, props: [.calfBlock, .supportRail])

        // MARK: Core
        case "hanging_leg_raise":   // legs straight to just above parallel
            return variant(hanging) { $0.upperArm = -45; $0.forearm = -135; $0.thigh = -5; $0.shin = -5 }
        case "cable_crunch":   // kneeling, rope held at the head, spine flexing toward the floor
            return Pose(hip: CGPoint(x: 50, y: 40), torso: -50, upperArm: -140, forearm: -40, thigh: 90, shin: 180, props: [.cable])
        case "ab_wheel_rollout":   // knees down, hips open, wheel out in front
            return Pose(hip: CGPoint(x: 44, y: 47), torso: -20, upperArm: 55, forearm: 55, thigh: 120, shin: 180, implement: .wheel)
        case "decline_sit_up":
            return Pose(hip: CGPoint(x: 46, y: 44), torso: -115, upperArm: 40, forearm: 180, thigh: -25, shin: 60, props: [.declineBench], grounded: false)
        case "pallof_press":   // half-kneeling, arms locked out in front, resisting the cable
            return Pose(hip: CGPoint(x: 46, y: 40), torso: -90, upperArm: 0, forearm: 0, thigh: 90, shin: 180, thigh2: 0, shin2: 90, implement: .handle, props: [.cableFrontLevel])
        case "plank":   // forearms down, one straight line from head to heels
            return Pose(hip: CGPoint(x: 56, y: 52), torso: -165, upperArm: 90, forearm: 0, thigh: 15, shin: 15, grounded: false)
        case "side_plank":   // straight supporting arm, top arm reaching up, hips lifted
            return Pose(hip: CGPoint(x: 56, y: 47.2), torso: -154, upperArm: 90, forearm: 90, upperArm2: -90, forearm2: -90, thigh: 26, shin: 26, grounded: false)
        case "hollow_hold":   // lower back pressed down, shoulders and legs lifted
            return Pose(hip: CGPoint(x: 50, y: 52), torso: -165, upperArm: -100, forearm: -100, thigh: -12, shin: -12, grounded: false)
        case "dead_bug":   // arms to the ceiling, one knee at tabletop, the other leg reaching out
            return Pose(hip: CGPoint(x: 50, y: 52), torso: 180, upperArm: -90, forearm: -90, thigh: -90, shin: 0, thigh2: -10, shin2: -10, grounded: false)
        case "bird_dog":   // flat back, eyes on the floor, opposite arm and leg extended
            return Pose(hip: CGPoint(x: 42, y: 46), torso: -20, headAngle: 25, upperArm: 90, forearm: 90, upperArm2: -20, forearm2: -20, thigh: 90, shin: 180, thigh2: 170, shin2: 170, grounded: false)
        case "russian_twist":   // seated V, torso back 45°, arms out front
            return Pose(hip: CGPoint(x: 50, y: 54), torso: -120, upperArm: -25, forearm: -25, thigh: -45, shin: 65, grounded: false)
        default:
            break
        }

        switch pattern {
        case "horizontal_press": return benchPress
        case "incline_press":
            return Pose(hip: CGPoint(x: 58, y: 42), torso: -145, upperArm: -75, forearm: -90, thigh: 60, shin: 90, implement: .barbell, props: [.inclineBench])
        case "vertical_press":
            return variant(standing) { $0.upperArm = -45; $0.forearm = -135; $0.implement = .barbell }
        case "chest_fly":
            return Pose(hip: CGPoint(x: 58, y: 40), torso: 180, upperArm: -40, forearm: -55, upperArm2: -140, forearm2: -125, thigh: 60, shin: 90, implement: .dumbbell, props: [.bench])
        case "lateral_raise":
            return variant(standing) { $0.upperArm = 0; $0.forearm = 5; $0.upperArm2 = 180; $0.forearm2 = 175; $0.implement = .dumbbellVertical }
        case "triceps_extension":
            return variant(standing) { $0.upperArm = -80; $0.forearm = -160; $0.implement = .dumbbellVertical }
        case "vertical_pull": return latPulldown
        case "horizontal_row": return row
        case "rear_delt":   // bent over, arms sweeping out
            return Pose(hip: CGPoint(x: 44, y: 34), torso: -45, upperArm: -125, forearm: -115, thigh: 95, shin: 85, implement: .dumbbell)
        case "elbow_flexion":
            return variant(standing) { $0.upperArm = 90; $0.forearm = 0; $0.implement = .dumbbell }
        case "squat": return squat
        case "hinge": return hinge
        case "quad_isolation":
            return Pose(hip: CGPoint(x: 44, y: 36), torso: -90, upperArm: 90, forearm: 90, thigh: 0, shin: 0, props: [.seat, .backrest, .anklePad], grounded: false)
        case "hamstring_isolation":
            return Pose(hip: CGPoint(x: 54, y: 42), torso: 180, upperArm: 150, forearm: 90, thigh: 0, shin: -90, props: [.bench, .anklePad], grounded: false)
        case "calf":
            return Pose(hip: CGPoint(x: 46, y: 33), torso: -90, upperArm: -10, forearm: -10, thigh: 90, shin: 90, props: [.calfBlock, .supportRail])
        default: // crunch
            return Pose(hip: CGPoint(x: 50, y: 54), torso: -155, upperArm: -120, forearm: 160, thigh: -50, shin: 70, grounded: false)
        }
    }

    private static let latPulldown = Pose(hip: CGPoint(x: 46, y: 38), torso: -100, upperArm: 120, forearm: -30, thigh: 0, shin: 90, implement: .barbell, props: [.cable, .seat])
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
    private func circle(_ p: inout Path, at c: CGPoint, r: CGFloat) { p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }

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

    /// Unit vector pointing to the figure's front side (chest), perpendicular to the torso.
    private func frontNormal(_ torso: CGFloat) -> CGPoint {
        let r = torso * .pi / 180
        return CGPoint(x: -sin(r), y: cos(r))
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func draw(_ p: inout Path) {
        let P = pose
        var hip = P.hip
        var shoulder = seg(hip, P.torso, torsoLen)
        var head = seg(shoulder, P.headAngle ?? P.torso, neck + headR)
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
        circle(&p, at: head, r: headR)
        for (elbow, hand) in arms { line(&p, shoulder, elbow); line(&p, elbow, hand) }
        for (knee, foot, shinAngle) in legs {
            line(&p, hip, knee); line(&p, knee, foot)
            if abs(cos(shinAngle * .pi / 180)) < 0.5 { line(&p, foot, dx: 3.5, dy: 0) }
        }
        if P.floor { line(&p, CGPoint(x: 8, y: floorY), CGPoint(x: 92, y: floorY)) }

        // Implement, always in the hands
        let hand = arms[0].1
        let hand2 = arms.last!.1
        switch P.implement {
        case .none: break
        case .barbell: barbell(&p, at: hand)
        case .barbellNarrow: barbell(&p, at: hand, halfWidth: 10)
        case .shortBar: barbell(&p, at: hand, halfWidth: 8, plate: 3)
        case .trapBar:
            barbell(&p, at: hand, halfWidth: 10, plate: 4)
            line(&p, CGPoint(x: hand.x - 10, y: hand.y), CGPoint(x: hand.x - 6, y: hand.y - 4))
            line(&p, CGPoint(x: hand.x - 6, y: hand.y - 4), CGPoint(x: hand.x + 6, y: hand.y - 4))
            line(&p, CGPoint(x: hand.x + 6, y: hand.y - 4), CGPoint(x: hand.x + 10, y: hand.y))
        case .barbellOnHips: barbell(&p, at: hip, halfWidth: 12)
        case .dumbbell: for (_, h) in arms { dumbbell(&p, at: h, vertical: false) }
        case .dumbbellVertical: for (_, h) in arms { dumbbell(&p, at: h, vertical: true) }
        case .dumbbellFirst: dumbbell(&p, at: hand, vertical: true)
        case .handle: line(&p, CGPoint(x: hand.x - 3, y: hand.y), CGPoint(x: hand.x + 3, y: hand.y))
        case .kettlebell:
            line(&p, hand, CGPoint(x: hand.x, y: hand.y + 2))
            circle(&p, at: CGPoint(x: hand.x, y: hand.y + 5), r: 3)
        case .wheel: circle(&p, at: CGPoint(x: hand.x, y: floorY - 2.5), r: 2.5)
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
            case .declineBench:
                let knee = legs[0].0
                let low = CGPoint(x: hip.x - 12, y: hip.y + 5), high = CGPoint(x: knee.x + 2, y: knee.y + 2)
                line(&p, low, high)
                line(&p, low, CGPoint(x: low.x, y: floorY))
                line(&p, high, CGPoint(x: high.x, y: floorY))
            case .seat:
                line(&p, CGPoint(x: hip.x - 6, y: hip.y + 2.5), CGPoint(x: hip.x + 8, y: hip.y + 2.5))
                line(&p, CGPoint(x: hip.x - 4, y: hip.y + 2.5), CGPoint(x: hip.x - 4, y: floorY))
            case .backrest:
                line(&p, CGPoint(x: hip.x - 5, y: hip.y + 2.5), CGPoint(x: shoulder.x - 3, y: shoulder.y - 4))
            case .hackPad:   // angled pad along the back, down to the floor
                let n = frontNormal(P.torso)
                let low = CGPoint(x: hip.x - 3 * n.x, y: hip.y - 3 * n.y + 3), high = CGPoint(x: shoulder.x - 3 * n.x - 2, y: shoulder.y - 3 * n.y - 5)
                line(&p, low, high)
                line(&p, low, CGPoint(x: low.x + 4, y: floorY))
            case .frontPad:   // incline pad under the chest
                let n = frontNormal(P.torso)
                let low = CGPoint(x: hip.x + 3 * n.x, y: hip.y + 3 * n.y), high = CGPoint(x: shoulder.x + 3 * n.x + 2, y: shoulder.y + 3 * n.y - 2)
                line(&p, low, high)
                line(&p, low, CGPoint(x: low.x, y: floorY))
            case .preacherPad:
                let elbow = arms[0].0
                let top = CGPoint(x: shoulder.x + 1, y: shoulder.y + 3), bottom = CGPoint(x: elbow.x + 4, y: elbow.y + 3)
                line(&p, top, bottom)
                line(&p, bottom, CGPoint(x: bottom.x, y: floorY))
            case .chestPad:
                line(&p, CGPoint(x: shoulder.x + 3, y: shoulder.y - 5), CGPoint(x: shoulder.x + 3, y: hip.y + 2.5))
            case .kneePad:
                let k = legs[0].0
                line(&p, CGPoint(x: k.x - 3, y: k.y - 3.5), CGPoint(x: k.x + 4, y: k.y - 3.5))
                line(&p, CGPoint(x: k.x + 4, y: k.y - 3.5), CGPoint(x: k.x + 4, y: floorY))
            case .shoulderPads:
                line(&p, CGPoint(x: shoulder.x - 1, y: shoulder.y - 1.5), CGPoint(x: shoulder.x + 5, y: shoulder.y - 1.5))
                line(&p, CGPoint(x: shoulder.x + 5, y: 6), CGPoint(x: shoulder.x + 5, y: floorY))
                line(&p, CGPoint(x: shoulder.x + 5, y: hand.y), hand)
            case .cable:   // anchored forward of the figure so the line never crosses the head
                line(&p, hand, CGPoint(x: hand.x + 10, y: 4))
                line(&p, CGPoint(x: hand.x - 4, y: 4), CGPoint(x: hand.x + 24, y: 4))
            case .cableFromBehind:
                line(&p, hand, CGPoint(x: hand.x - 22, y: 4))
                line(&p, CGPoint(x: hand.x - 26, y: 4), CGPoint(x: hand.x - 18, y: 4))
            case .cableLowFront:
                line(&p, hand, CGPoint(x: hand.x + 6, y: floorY - 4))
                line(&p, CGPoint(x: hand.x + 3, y: floorY - 4), CGPoint(x: hand.x + 9, y: floorY - 4))
            case .cableBehindLow:
                line(&p, hand, CGPoint(x: hand.x - 18, y: floorY - 6))
                line(&p, CGPoint(x: hand.x - 21, y: floorY - 6), CGPoint(x: hand.x - 15, y: floorY - 6))
            case .cableFrontLevel:
                line(&p, hand, CGPoint(x: hand.x + 12, y: hand.y))
                line(&p, CGPoint(x: hand.x + 12, y: 4), CGPoint(x: hand.x + 12, y: floorY))
            case .rearBench:
                let f = legs[1].1
                line(&p, CGPoint(x: f.x - 6, y: f.y + 1), CGPoint(x: f.x + 5, y: f.y + 1))
                for x in [f.x - 4, f.x + 3] { line(&p, CGPoint(x: x, y: f.y + 1), CGPoint(x: x, y: floorY)) }
            case .footBlock:
                let f = legs[0].1
                line(&p, CGPoint(x: f.x - 4, y: f.y + 1), CGPoint(x: f.x + 5, y: f.y + 1))
                for x in [f.x - 4, f.x + 5] { line(&p, CGPoint(x: x, y: f.y + 1), CGPoint(x: x, y: floorY)) }
            case .footPlate:
                let f = legs[0].1
                line(&p, CGPoint(x: f.x + 1, y: f.y - 7), CGPoint(x: f.x + 2.5, y: f.y + 7))
            case .highBar:
                line(&p, CGPoint(x: hand.x - 20, y: hand.y), CGPoint(x: hand.x + 20, y: hand.y))
                for x in [hand.x - 20, hand.x + 20] { line(&p, CGPoint(x: x, y: hand.y), CGPoint(x: x, y: hand.y - 6)) }
            case .dipBars:
                line(&p, CGPoint(x: hand.x - 14, y: hand.y), CGPoint(x: hand.x + 14, y: hand.y))
                for x in [hand.x - 10, hand.x + 10] { line(&p, CGPoint(x: x, y: hand.y), CGPoint(x: x, y: floorY)) }
            case .smithRails:
                for x in [hand.x - 16, hand.x + 16] { line(&p, CGPoint(x: x, y: 4), CGPoint(x: x, y: floorY)) }
            case .machineArm:
                line(&p, hand, CGPoint(x: hand.x, y: hand.y + 12))
            case .tBar:
                line(&p, hand, CGPoint(x: hand.x + 16, y: floorY - 1))
            case .post:
                line(&p, CGPoint(x: hand2.x, y: 4), CGPoint(x: hand2.x, y: floorY))
            case .supportRail:
                line(&p, CGPoint(x: hand2.x + 1, y: hand2.y - 12), CGPoint(x: hand2.x + 1, y: floorY))
            case .supportBench:
                line(&p, CGPoint(x: hand2.x - 4, y: hand2.y + 1), CGPoint(x: hand2.x + 8, y: hand2.y + 1))
                for x in [hand2.x - 2, hand2.x + 6] { line(&p, CGPoint(x: x, y: hand2.y + 1), CGPoint(x: x, y: floorY)) }
            case .handBench:
                line(&p, CGPoint(x: hand.x - 10, y: hand.y + 1), CGPoint(x: hand.x + 3, y: hand.y + 1))
                for x in [hand.x - 8, hand.x + 1] { line(&p, CGPoint(x: x, y: hand.y + 1), CGPoint(x: x, y: floorY)) }
            case .anklePad:
                let foot = legs[0].1
                let seated = abs(cos(legs[0].2 * .pi / 180)) >= 0.5
                dumbbell(&p, at: CGPoint(x: foot.x, y: foot.y + (seated ? 2 : 0)), vertical: seated)
            case .heelAnchor:
                let f = legs[0].1
                line(&p, CGPoint(x: f.x - 3, y: floorY), CGPoint(x: f.x - 3, y: f.y - 4))
                line(&p, CGPoint(x: f.x - 3, y: f.y - 4), CGPoint(x: f.x + 3, y: f.y - 4))
            case .calfBlock:
                let f = legs[0].1
                line(&p, CGPoint(x: f.x + 2, y: f.y), CGPoint(x: f.x - 3, y: f.y - 3))       // raised heel
                line(&p, CGPoint(x: f.x + 1, y: f.y), CGPoint(x: f.x + 5, y: f.y))
                line(&p, CGPoint(x: f.x - 6, y: floorY), CGPoint(x: f.x + 8, y: floorY))      // block
                line(&p, CGPoint(x: f.x + 8, y: floorY), CGPoint(x: f.x + 8, y: floorY - 4))
                line(&p, CGPoint(x: f.x - 6, y: floorY - 4), CGPoint(x: f.x + 8, y: floorY - 4))
            case .dipBelt:
                line(&p, CGPoint(x: hip.x + 2, y: hip.y), CGPoint(x: hip.x + 3, y: hip.y + 6))
                circle(&p, at: CGPoint(x: hip.x + 3, y: hip.y + 8), r: 2)
            }
        }
    }
}
