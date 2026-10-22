import SwiftUI
import WorkoutEngine
import WorkoutUI

/// Cartoon pictogram of a movement: an articulated wooden-mannequin figure with a mascot-sized head,
/// drawn from a small kinematic skeleton so limb proportions are consistent and the implement is always
/// in the hands. Every pose is a side view chosen for correct form (neutral spine, bar over mid-foot,
/// knees over toes) and free-standing poses keep the combined centre of mass over the feet.
/// Barbells are seen end-on (a plate ring at the hand) because the figure is in profile.
/// Unit box 100×60, auto-framed around the figure, then scaled to fit.
struct ExerciseArt: View {
    let exerciseKey: String
    let pattern: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.card)
            Canvas(rendersAsynchronously: true) { ctx, size in
                FigureRenderer(pose: Pose.for(exerciseKey: exerciseKey, pattern: pattern)).draw(in: &ctx, size: size)
            }
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
    var headAngle: CGFloat? = nil
    var upperArm: CGFloat, forearm: CGFloat
    var upperArm2: CGFloat? = nil, forearm2: CGFloat? = nil
    var thigh: CGFloat, shin: CGFloat
    var thigh2: CGFloat? = nil, shin2: CGFloat? = nil
    var implement: Implement = .none
    var props: [Prop] = []
    var grounded = true
    var floor = true

    init(_ hx: CGFloat, _ hy: CGFloat, _ torso: CGFloat, _ upperArm: CGFloat, _ forearm: CGFloat, _ thigh: CGFloat, _ shin: CGFloat,
         headAngle: CGFloat? = nil, upperArm2: CGFloat? = nil, forearm2: CGFloat? = nil, thigh2: CGFloat? = nil, shin2: CGFloat? = nil,
         implement: Implement = .none, props: [Prop] = [], grounded: Bool = true, floor: Bool = true) {
        hip = CGPoint(x: hx, y: hy)
        self.torso = torso; self.headAngle = headAngle
        self.upperArm = upperArm; self.forearm = forearm; self.upperArm2 = upperArm2; self.forearm2 = forearm2
        self.thigh = thigh; self.shin = shin; self.thigh2 = thigh2; self.shin2 = shin2
        self.implement = implement; self.props = props; self.grounded = grounded; self.floor = floor
    }

    func with(_ edit: (inout Pose) -> Void) -> Pose { var p = self; edit(&p); return p }

    static func `for`(exerciseKey key: String, pattern: String) -> Pose {
        var p = base(exerciseKey: key, pattern: pattern)
        if key.contains("dumbbell"), p.implement == .barbell { p.implement = .dumbbell }
        if key.contains("barbell"), p.implement == .dumbbell { p.implement = .barbell }
        if key.contains("smith"), !p.props.contains(.smithRails) { p.props.append(.smithRails) }
        return p
    }

    // MARK: - Shared bases

    private static let standing = Pose(50, 36, -90, 90, 90, 90, 90)
    private static let seated = Pose(44, 38, -90, 90, 90, 0, 90, props: [.seat, .backrest])
    private static let benchPress = Pose(58, 40, 180, -70, -90, 60, 90, implement: .barbell, props: [.bench])
    /// Hips back, shins near vertical, shoulders over the bar, bar over mid-foot.
    private static let hinge = Pose(40, 32, -40, 90, 90, 50, 68, implement: .barbell)
    /// Knees travel forward, torso leans so the bar stays over mid-foot.
    private static let squat = Pose(44, 36, -55, -170, 10, 10, 115, implement: .barbell)
    /// Top of the pull: elbows behind the torso, bar at the lower ribs, hips back over the heels.
    private static let row = Pose(44, 34, -35, 150, 60, 60, 80, implement: .barbell)
    private static let hanging = Pose(50, 36, -90, -135, -45, 95, 120, props: [.highBar], grounded: false, floor: false)
    private static let latPulldown = Pose(46, 38, -100, 120, -30, 0, 90, implement: .barbell, props: [.cable, .seat])
    private static let romanianDeadlift = Pose(42, 32, -32, 100, 100, 72, 85, implement: .barbell)
    private static let crunch = Pose(50, 54, -155, -120, 160, -50, 70, grounded: false)

    // MARK: - Table

    private static func base(exerciseKey key: String, pattern: String) -> Pose {
        switch key {
        case "decline_push_up": return Pose(56, 38.6, 175, 90, 90, -5, -5, props: [.footBlock], grounded: false)
        case "push_up": return Pose(56, 46.5, -156, 90, 90, 24, 24, grounded: false)
        case "dumbbell_floor_press": return Pose(56, 52.5, 180, -70, -90, -40, 100, implement: .dumbbell, grounded: false)
        case "close_grip_bench_press": return benchPress.with { $0.implement = .barbellNarrow }
        case "machine_chest_press": return seated.with { $0.upperArm = 0; $0.forearm = 0; $0.implement = .handle; $0.props = [.seat, .backrest, .machineArm] }
        case "machine_shoulder_press": return seated.with { $0.upperArm = 0; $0.forearm = -90; $0.implement = .handle; $0.props = [.seat, .backrest, .machineArm] }
        case "seated_dumbbell_press", "dumbbell_shoulder_press": return seated.with { $0.upperArm = -45; $0.forearm = -135; $0.implement = .dumbbell }
        case "arnold_press": return seated.with { $0.upperArm = 40; $0.forearm = -70; $0.implement = .dumbbellVertical }
        case "weighted_dip": return Pose(50, 36, -75, 150, 90, 100, 170, props: [.dipBars, .dipBelt], grounded: false, floor: false)
        case "bench_dip": return Pose(52, 44, -80, 160, 90, 10, 60, props: [.handBench])
        case "skullcrusher": return benchPress.with { $0.upperArm = -90; $0.forearm = 180; $0.implement = .shortBar }
        case "dumbbell_overhead_extension": return standing.with { $0.torso = -86; $0.upperArm = -75; $0.forearm = -160; $0.implement = .dumbbellVertical }
        case "overhead_cable_extension": return Pose(46, 36, -70, -100, -40, 80, 90, implement: .handle, props: [.cableFromBehind])
        case "cable_pushdown": return standing.with { $0.upperArm = 90; $0.forearm = 80; $0.implement = .handle; $0.props = [.cable] }
        case "pec_deck_fly": return seated.with { $0.upperArm = 0; $0.forearm = -70; $0.props = [.seat, .backrest, .machineArm] }
        case "reverse_pec_deck": return Pose(46, 38, -90, 175, 175, 0, 90, implement: .handle, props: [.seat, .chestPad])
        case "cable_fly": return Pose(46, 36, -80, -10, 0, 90, 90, implement: .handle, props: [.cableFromBehind])
        case "cable_lateral_raise": return standing.with { $0.upperArm = 0; $0.forearm = 5; $0.implement = .handle; $0.props = [.cableLowFront] }
        case "lean_away_lateral_raise": return standing.with { $0.torso = -75; $0.upperArm = 0; $0.forearm = 5; $0.upperArm2 = 170; $0.forearm2 = 170; $0.implement = .handle; $0.props = [.cableLowFront, .post] }
        case "pull_up": return hanging
        case "weighted_pull_up": return hanging.with { $0.props = [.highBar, .dipBelt] }
        case "chin_up": return hanging.with { $0.upperArm = -115; $0.forearm = -65 }
        case "neutral_grip_pulldown": return latPulldown.with { $0.implement = .barbellNarrow }
        case "straight_arm_pulldown": return Pose(46, 36, -80, -30, -30, 85, 90, implement: .barbellNarrow, props: [.cable])
        case "kneeling_cable_pulldown": return Pose(46, 40, -90, -40, -110, 90, 180, implement: .handle, props: [.cable])
        case "pendlay_row": return Pose(40, 34, -20, 90, 90, 40, 75, headAngle: 10, implement: .barbell)
        case "t_bar_row": return row.with { $0.implement = .handle; $0.props = [.tBar] }
        case "chest_supported_row": return Pose(44, 38, -50, 100, 100, 90, 90, implement: .handle, props: [.seat, .frontPad])
        case "seated_cable_row": return Pose(40, 44, -95, 10, 0, -10, 40, implement: .handle, props: [.seat, .cableFrontLevel, .footPlate], grounded: false)
        case "single_arm_dumbbell_row": return Pose(40, 36, -30, 100, 90, 75, 85, upperArm2: 60, forearm2: 60, thigh2: 55, shin2: 80, implement: .dumbbellFirst, props: [.supportBench])
        case "inverted_row": return Pose(50, 49, -160, -90, -90, 20, 20, props: [.highBar])
        case "face_pull": return standing.with { $0.upperArm = -20; $0.forearm = -20; $0.thigh = 80; $0.thigh2 = 100; $0.shin2 = 90; $0.implement = .handle; $0.props = [.cableFrontLevel] }
        case "cable_reverse_fly": return standing.with { $0.torso = -80; $0.upperArm = 0; $0.forearm = 0; $0.implement = .handle; $0.props = [.cableFrontLevel] }
        case "hammer_curl": return standing.with { $0.upperArm = 90; $0.forearm = 0; $0.implement = .dumbbellVertical }
        case "cable_curl": return standing.with { $0.upperArm = 90; $0.forearm = 0; $0.implement = .handle; $0.props = [.cableLowFront] }
        case "preacher_curl": return Pose(44, 38, -90, 35, -50, 0, 90, implement: .shortBar, props: [.seat, .preacherPad])
        case "incline_dumbbell_curl": return Pose(52, 42, -130, 100, 20, 60, 90, implement: .dumbbell, props: [.inclineBench])
        case "front_squat": return squat.with { $0.torso = -70; $0.shin = 120; $0.upperArm = -10; $0.forearm = 165 }
        case "goblet_squat": return squat.with { $0.torso = -72; $0.shin = 120; $0.upperArm = 60; $0.forearm = -70; $0.implement = .dumbbellVertical }
        case "hack_squat": return Pose(44, 36, -120, 110, 60, 0, 80, props: [.hackPad])
        case "leg_press": return Pose(40, 42, -130, 20, 60, -50, -10, props: [.seat, .backrest, .footPlate], grounded: false)
        case "bulgarian_split_squat": return Pose(50, 36, -90, 90, 90, 0, 90, thigh2: 135, shin2: 190, implement: .dumbbellVertical, props: [.rearBench])
        case "walking_lunge": return standing.with { $0.thigh = 0; $0.thigh2 = 125; $0.shin2 = 170; $0.implement = .dumbbellVertical }
        case "reverse_lunge": return standing.with { $0.torso = -88; $0.thigh2 = 120; $0.shin2 = 150; $0.implement = .dumbbellVertical }
        case "step_up": return standing.with { $0.thigh = -10; $0.thigh2 = 90; $0.shin2 = 90; $0.implement = .dumbbellVertical; $0.props = [.footBlock] }
        case "romanian_deadlift": return romanianDeadlift
        case "dumbbell_romanian_deadlift": return romanianDeadlift.with { $0.implement = .dumbbell }
        case "trap_bar_deadlift": return hinge.with { $0.implement = .trapBar }
        case "good_morning": return Pose(42, 32, -32, -170, 30, 60, 80, implement: .barbell)
        case "kettlebell_swing": return Pose(44, 34, -35, 95, 95, 50, 80, implement: .kettlebell)
        case "cable_pull_through": return Pose(44, 32, -30, 120, 150, 60, 85, implement: .handle, props: [.cableBehindLow])
        case "barbell_hip_thrust": return Pose(56, 40, 180, 0, 0, 0, 90, implement: .barbellOnHips, props: [.bench])
        case "seated_leg_curl": return Pose(44, 38, -95, 20, 60, 0, 60, props: [.seat, .backrest, .anklePad])
        case "nordic_curl": return Pose(44, 46, -70, 60, 180, 110, 180, props: [.heelAnchor])
        case "standing_calf_raise": return Pose(46, 33, -90, -20, -70, 90, 90, implement: .handle, props: [.calfBlock, .shoulderPads])
        case "seated_calf_raise": return Pose(44, 38, -90, 40, 60, 0, 90, props: [.seat, .calfBlock, .kneePad])
        case "dumbbell_calf_raise": return Pose(46, 33, -90, 90, 90, 90, 90, upperArm2: -10, forearm2: -10, implement: .dumbbellFirst, props: [.calfBlock, .supportRail])
        case "bodyweight_calf_raise": return Pose(46, 33, -90, -10, -10, 90, 90, props: [.calfBlock, .supportRail])
        case "hanging_leg_raise": return hanging.with { $0.upperArm = -45; $0.forearm = -135; $0.thigh = -5; $0.shin = -5 }
        case "cable_crunch": return Pose(50, 40, -50, -140, -40, 90, 180, props: [.cable])
        case "ab_wheel_rollout": return Pose(44, 47, -20, 55, 55, 120, 180, implement: .wheel)
        case "decline_sit_up": return Pose(46, 44, -115, 40, 180, -25, 60, props: [.declineBench], grounded: false)
        case "pallof_press": return Pose(46, 40, -90, 0, 0, 90, 180, thigh2: 0, shin2: 90, implement: .handle, props: [.cableFrontLevel])
        case "plank": return Pose(56, 52, -165, 90, 0, 15, 15, grounded: false)
        case "side_plank": return Pose(56, 47.2, -154, 90, 90, 26, 26, upperArm2: -90, forearm2: -90, grounded: false)
        case "hollow_hold": return Pose(50, 52, -165, -100, -100, -12, -12, grounded: false)
        case "dead_bug": return Pose(50, 52, 180, -90, -90, -90, 0, thigh2: -10, shin2: -10, grounded: false)
        case "bird_dog": return Pose(42, 46, -20, 90, 90, 90, 180, headAngle: 25, upperArm2: -20, forearm2: -20, thigh2: 170, shin2: 170, grounded: false)
        case "russian_twist": return Pose(50, 54, -120, -25, -25, -45, 65, grounded: false)
        default: break
        }
        switch pattern {
        case "horizontal_press": return benchPress
        case "incline_press": return Pose(58, 42, -145, -75, -90, 60, 90, implement: .barbell, props: [.inclineBench])
        case "vertical_press": return standing.with { $0.upperArm = -45; $0.forearm = -135; $0.implement = .barbell }
        case "chest_fly": return Pose(58, 40, 180, -40, -55, 60, 90, upperArm2: -140, forearm2: -125, implement: .dumbbell, props: [.bench])
        case "lateral_raise": return standing.with { $0.upperArm = 0; $0.forearm = 5; $0.upperArm2 = 180; $0.forearm2 = 175; $0.implement = .dumbbellVertical }
        case "triceps_extension": return standing.with { $0.upperArm = -80; $0.forearm = -160; $0.implement = .dumbbellVertical }
        case "vertical_pull": return latPulldown
        case "horizontal_row": return row
        case "rear_delt": return Pose(44, 34, -45, -125, -115, 95, 85, implement: .dumbbell)
        case "elbow_flexion": return standing.with { $0.upperArm = 90; $0.forearm = 0; $0.implement = .dumbbell }
        case "squat": return squat
        case "hinge": return hinge
        case "quad_isolation": return Pose(44, 36, -90, 90, 90, 0, 0, props: [.seat, .backrest, .anklePad], grounded: false)
        case "hamstring_isolation": return Pose(54, 42, 180, 150, 90, 0, -90, props: [.bench, .anklePad], grounded: false)
        case "calf": return Pose(46, 33, -90, -10, -10, 90, 90, props: [.calfBlock, .supportRail])
        default: return crunch
        }
    }
}

// MARK: - Skeleton

private let floorY: CGFloat = 56

private func seg(_ p: CGPoint, _ deg: CGFloat, _ len: CGFloat) -> CGPoint {
    let r = deg * .pi / 180
    return CGPoint(x: p.x + len * cos(r), y: p.y + len * sin(r))
}
private func off(_ p: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: p.x + dx, y: p.y + dy) }
/// Unit vector pointing out of the figure's front for a torso at `deg`.
private func frontNormal(_ deg: CGFloat) -> CGPoint { let r = deg * .pi / 180; return CGPoint(x: -sin(r), y: cos(r)) }

private struct Skeleton {
    struct Arm { var elbow: CGPoint, hand: CGPoint }
    struct Leg { var knee: CGPoint, foot: CGPoint, shinAngle: CGFloat }

    static let torsoLen: CGFloat = 15, neckLen: CGFloat = 6.6, upperArmLen: CGFloat = 8, forearmLen: CGFloat = 8, thighLen: CGFloat = 10, shinLen: CGFloat = 10

    let pose: Pose
    var hip: CGPoint, shoulder: CGPoint, head: CGPoint
    var arms: [Arm]
    var legs: [Leg]
    var headAngle: CGFloat { pose.headAngle ?? pose.torso }
    var hand: CGPoint { arms[0].hand }
    var farHand: CGPoint { arms[arms.count - 1].hand }

    init(_ p: Pose) {
        pose = p
        hip = p.hip
        shoulder = seg(hip, p.torso, Self.torsoLen)
        head = seg(shoulder, p.headAngle ?? p.torso, Self.neckLen)
        let e = seg(shoulder, p.upperArm, Self.upperArmLen)
        arms = [Arm(elbow: e, hand: seg(e, p.forearm, Self.forearmLen))]
        if let ua2 = p.upperArm2, let fa2 = p.forearm2 {
            let e2 = seg(shoulder, ua2, Self.upperArmLen)
            arms.append(Arm(elbow: e2, hand: seg(e2, fa2, Self.forearmLen)))
        }
        let k = seg(hip, p.thigh, Self.thighLen)
        legs = [Leg(knee: k, foot: seg(k, p.shin, Self.shinLen), shinAngle: p.shin)]
        if let t2 = p.thigh2, let s2 = p.shin2 {
            let k2 = seg(hip, t2, Self.thighLen)
            legs.append(Leg(knee: k2, foot: seg(k2, s2, Self.shinLen), shinAngle: s2))
        }
        if p.grounded {
            let dy = floorY - legs.map(\.foot.y).max()!
            hip.y += dy; shoulder.y += dy; head.y += dy
            arms = arms.map { Arm(elbow: off($0.elbow, 0, dy), hand: off($0.hand, 0, dy)) }
            legs = legs.map { Leg(knee: off($0.knee, 0, dy), foot: off($0.foot, 0, dy), shinAngle: $0.shinAngle) }
        }
    }

    /// Shin is roughly vertical, so the foot is flat and gets a toe mark.
    static func footFlat(_ leg: Leg) -> Bool { abs(cos(leg.shinAngle * .pi / 180)) < 0.5 }
}

// MARK: - Renderer

private struct FigureRenderer {
    enum Prim {
        case line(CGPoint, CGPoint), plate(CGPoint, CGPoint), circle(CGPoint, CGFloat), floor
    }
    struct Segment { var a: CGPoint, b: CGPoint, isTorso: Bool, far: Bool }

    static let headR: CGFloat = 5.4, torsoW: CGFloat = 5.0, limbW: CGFloat = 3.4, outline: CGFloat = 1.4
    static let plateR: [Pose.Implement: CGFloat] = [.barbell: 5.0, .barbellOnHips: 5.0, .trapBar: 5.0, .barbellNarrow: 3.6, .shortBar: 3.0]

    let brass = Theme.Colors.brass, card = Theme.Colors.card
    let far = Theme.Colors.brass.opacity(0.55)
    let gear = Theme.Colors.textPrimary.opacity(0.6), gearFill = Theme.Colors.textPrimary.opacity(0.1)
    let propColor = Theme.Colors.brass.opacity(0.38)

    let sk: Skeleton
    init(pose: Pose) { sk = Skeleton(pose) }

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let props = propPrims()
        let (origin, span) = frame(props)
        let fit = min(size.width / 100, size.height / 60)
        let scale = min(100 / span.width, 60 / span.height, 1.5)
        let k = fit * scale
        let vw = 100 / scale, vh = 60 / scale
        ctx.translateBy(x: (size.width - 100 * fit) / 2, y: (size.height - 60 * fit) / 2)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -(origin.x + span.width / 2 - vw / 2), y: -(origin.y + span.height / 2 - vh / 2))

        for prim in props {
            switch prim {
            case .line(let a, let b): line(&ctx, a, b, 1.4, propColor)
            case .plate(let a, let b): line(&ctx, a, b, 2.4, propColor)
            case .circle(let c, let r): circle(&ctx, c, r, stroke: propColor, w: 1.4)
            case .floor: line(&ctx, CGPoint(x: origin.x - 1.5, y: floorY), CGPoint(x: origin.x + span.width + 1.5, y: floorY), 1.4, propColor)
            }
        }
        drawImplement(&ctx)

        let (rest, nearArm) = segments()
        for s in rest { segment(&ctx, s) }
        for leg in sk.legs where Skeleton.footFlat(leg) {
            let toe = off(leg.foot, 5, 0)
            line(&ctx, leg.foot, toe, Self.limbW + 1.0, card)
            line(&ctx, leg.foot, toe, Self.limbW - 0.4, brass)
        }
        drawHead(&ctx)
        for s in nearArm { segment(&ctx, s) }
        circle(&ctx, sk.hand, Self.limbW * 0.6, fill: brass, stroke: card, w: 0.9)
    }

    /// Bounding box (with padding) around everything that will be drawn, in unit space.
    private func frame(_ props: [Prim]) -> (CGPoint, CGSize) {
        var pts = [sk.hip, sk.shoulder, off(sk.head, -Self.headR, -Self.headR), off(sk.head, Self.headR, Self.headR)]
        for a in sk.arms { pts += [a.elbow, a.hand] }
        for l in sk.legs { pts += [l.knee, l.foot] }
        if sk.pose.implement != .none {
            let r = Self.plateR[sk.pose.implement] ?? 4
            let c = sk.pose.implement == .barbellOnHips ? sk.hip : sk.hand
            pts += [off(c, -r, -r), off(c, r, r)]
        }
        for prim in props {
            switch prim {
            case .line(let a, let b), .plate(let a, let b): pts += [a, b]
            case .circle(let c, let r): pts += [off(c, -r, -r), off(c, r, r)]
            case .floor: break
            }
        }
        var x0 = pts.map(\.x).min()!, x1 = pts.map(\.x).max()!
        var y0 = pts.map(\.y).min()!, y1 = pts.map(\.y).max()!
        if sk.pose.floor { y1 = max(y1, floorY) }
        let pad: CGFloat = 4.5
        x0 -= pad; x1 += pad; y0 -= pad; y1 += pad
        return (CGPoint(x: x0, y: y0), CGSize(width: x1 - x0, height: y1 - y0))
    }

    /// Far limbs first (dimmed), then torso, then the near leg; the near arm is returned separately
    /// so it can be drawn over the head.
    private func segments() -> ([Segment], [Segment]) {
        var rest: [Segment] = [], near: [Segment] = []
        for (i, leg) in sk.legs.reversed().enumerated() {
            let far = sk.legs.count > 1 && i == 0
            rest.append(Segment(a: sk.hip, b: leg.knee, isTorso: false, far: far))
            rest.append(Segment(a: leg.knee, b: leg.foot, isTorso: false, far: far))
        }
        rest.append(Segment(a: sk.hip, b: sk.shoulder, isTorso: true, far: false))
        for (i, arm) in sk.arms.reversed().enumerated() {
            let far = sk.arms.count > 1 && i == 0
            let segs = [Segment(a: sk.shoulder, b: arm.elbow, isTorso: false, far: far), Segment(a: arm.elbow, b: arm.hand, isTorso: false, far: far)]
            if far { rest += segs } else { near += segs }
        }
        return (rest, near)
    }

    private func segment(_ ctx: inout GraphicsContext, _ s: Segment) {
        let w = s.isTorso ? Self.torsoW : Self.limbW
        line(&ctx, s.a, s.b, w + Self.outline, card)
        line(&ctx, s.a, s.b, w, s.far ? far : brass)
    }

    private func drawHead(_ ctx: inout GraphicsContext) {
        let h = sk.head, r = Self.headR
        circle(&ctx, h, r, fill: brass, stroke: card, w: 1.1)
        let ang = sk.headAngle
        let f = frontNormal(ang), u = CGPoint(x: cos(ang * .pi / 180), y: sin(ang * .pi / 180))
        let eye = CGPoint(x: h.x + f.x * r * 0.5 + u.x * r * 0.12, y: h.y + f.y * r * 0.5 + u.y * r * 0.12)
        circle(&ctx, eye, r * 0.19, fill: card)
        let a = CGPoint(x: eye.x - f.x * r * 0.12 + u.x * r * 0.34, y: eye.y - f.y * r * 0.12 + u.y * r * 0.34)
        let b = CGPoint(x: eye.x + f.x * r * 0.32 + u.x * r * 0.4, y: eye.y + f.y * r * 0.32 + u.y * r * 0.4)
        line(&ctx, a, b, r * 0.18, card)
    }

    /// Side view: a loaded bar is seen end-on, so it reads as a plate ring with the bar end at the hand.
    private func drawImplement(_ ctx: inout GraphicsContext) {
        let hand = sk.hand
        func plate(_ c: CGPoint, _ r: CGFloat) {
            circle(&ctx, c, r, fill: gearFill, stroke: gear, w: 1.6)
            circle(&ctx, c, 1.3, fill: gear)
        }
        func dumbbell(_ h: CGPoint, vertical: Bool) {
            if vertical {
                line(&ctx, off(h, 0, -3.2), off(h, 0, 3.2), 1.6, gear)
                for y: CGFloat in [-3.2, 3.2] { line(&ctx, off(h, -2.4, y), off(h, 2.4, y), 2.6, gear) }
            } else {
                line(&ctx, off(h, -3.2, 0), off(h, 3.2, 0), 1.6, gear)
                for x: CGFloat in [-3.2, 3.2] { line(&ctx, off(h, x, -2.4), off(h, x, 2.4), 2.6, gear) }
            }
        }
        switch sk.pose.implement {
        case .none: break
        case .barbell, .barbellNarrow, .shortBar: plate(hand, Self.plateR[sk.pose.implement]!)
        case .barbellOnHips: plate(sk.hip, Self.plateR[.barbellOnHips]!)
        case .trapBar:
            plate(hand, Self.plateR[.trapBar]!)
            line(&ctx, off(hand, 0, -4), off(hand, 0, 4), 1.8, gear)
        case .dumbbell: for a in sk.arms { dumbbell(a.hand, vertical: false) }
        case .dumbbellVertical: for a in sk.arms { dumbbell(a.hand, vertical: true) }
        case .dumbbellFirst: dumbbell(hand, vertical: true)
        case .handle: line(&ctx, off(hand, -2.6, 0), off(hand, 2.6, 0), 2.2, gear)
        case .kettlebell:
            line(&ctx, hand, off(hand, 0, 2.5), 1.6, gear)
            circle(&ctx, off(hand, 0, 5.5), 3.2, fill: gear)
        case .wheel: circle(&ctx, CGPoint(x: hand.x, y: floorY - 2.6), 2.6, fill: gearFill, stroke: gear, w: 1.6)
        }
    }

    // MARK: Props (benches, cables, machines)

    private func propPrims() -> [Prim] {
        let p = sk.pose
        let hip = sk.hip, shoulder = sk.shoulder, hand = sk.hand, hand2 = sk.farHand
        let knee = sk.legs[0].knee, foot = sk.legs[0].foot
        var out: [Prim] = []
        func L(_ a: CGPoint, _ b: CGPoint) { out.append(.line(a, b)) }
        func LXY(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) { out.append(.line(CGPoint(x: ax, y: ay), CGPoint(x: bx, y: by))) }
        func legs(_ a: CGPoint, _ b: CGPoint) { L(a, b); L(a, CGPoint(x: a.x, y: floorY)); L(b, CGPoint(x: b.x, y: floorY)) }
        func pad(_ c: CGPoint, vertical: Bool) {
            if vertical {
                out.append(.line(off(c, 0, -3.5), off(c, 0, 3.5)))
                for y: CGFloat in [-3.5, 3.5] { out.append(.plate(off(c, -2.5, y), off(c, 2.5, y))) }
            } else {
                out.append(.line(off(c, -3.5, 0), off(c, 3.5, 0)))
                for x: CGFloat in [-3.5, 3.5] { out.append(.plate(off(c, x, -2.5), off(c, x, 2.5))) }
            }
        }
        for prop in p.props {
            switch prop {
            case .bench:
                let y = shoulder.y + 2.5
                LXY(shoulder.x - 10, y, hip.x + 4, y); LXY(shoulder.x - 6, y, shoulder.x - 6, floorY); LXY(hip.x, y, hip.x, floorY)
            case .inclineBench:
                let seat = CGPoint(x: hip.x + 2, y: hip.y + 2.5)
                L(seat, CGPoint(x: shoulder.x - 6, y: shoulder.y - 2)); L(seat, CGPoint(x: seat.x, y: floorY)); L(CGPoint(x: hip.x - 8, y: seat.y), seat)
            case .declineBench:
                legs(CGPoint(x: hip.x - 12, y: hip.y + 5), CGPoint(x: knee.x + 2, y: knee.y + 2))
            case .seat:
                LXY(hip.x - 6, hip.y + 2.5, hip.x + 8, hip.y + 2.5); LXY(hip.x - 4, hip.y + 2.5, hip.x - 4, floorY)
            case .backrest:
                LXY(hip.x - 5, hip.y + 2.5, shoulder.x - 3, shoulder.y - 4)
            case .hackPad:
                let n = frontNormal(p.torso)
                let low = CGPoint(x: hip.x - 3 * n.x, y: hip.y - 3 * n.y + 3), high = CGPoint(x: shoulder.x - 3 * n.x - 2, y: shoulder.y - 3 * n.y - 5)
                L(low, high); L(low, CGPoint(x: low.x + 4, y: floorY))
            case .frontPad:
                let n = frontNormal(p.torso)
                let low = CGPoint(x: hip.x + 3 * n.x, y: hip.y + 3 * n.y), high = CGPoint(x: shoulder.x + 3 * n.x + 2, y: shoulder.y + 3 * n.y - 2)
                L(low, high); L(low, CGPoint(x: low.x, y: floorY))
            case .preacherPad:
                let elbow = sk.arms[0].elbow
                let top = CGPoint(x: shoulder.x + 1, y: shoulder.y + 3), bottom = CGPoint(x: elbow.x + 4, y: elbow.y + 3)
                L(top, bottom); L(bottom, CGPoint(x: bottom.x, y: floorY))
            case .chestPad:
                LXY(shoulder.x + 3, shoulder.y - 5, shoulder.x + 3, hip.y + 2.5)
            case .kneePad:
                LXY(knee.x - 3, knee.y - 3.5, knee.x + 4, knee.y - 3.5); LXY(knee.x + 4, knee.y - 3.5, knee.x + 4, floorY)
            case .shoulderPads:
                LXY(shoulder.x - 1, shoulder.y - 1.5, shoulder.x + 5, shoulder.y - 1.5); LXY(shoulder.x + 5, 6, shoulder.x + 5, floorY); L(CGPoint(x: shoulder.x + 5, y: hand.y), hand)
            case .cable:
                L(hand, CGPoint(x: hand.x + 10, y: 4)); LXY(hand.x - 4, 4, hand.x + 24, 4)
            case .cableFromBehind:
                L(hand, CGPoint(x: hand.x - 22, y: 4)); LXY(hand.x - 26, 4, hand.x - 18, 4)
            case .cableLowFront:
                L(hand, CGPoint(x: hand.x + 6, y: floorY - 4)); LXY(hand.x + 3, floorY - 4, hand.x + 9, floorY - 4)
            case .cableBehindLow:
                L(hand, CGPoint(x: hand.x - 18, y: floorY - 6)); LXY(hand.x - 21, floorY - 6, hand.x - 15, floorY - 6)
            case .cableFrontLevel:
                L(hand, CGPoint(x: hand.x + 12, y: hand.y)); LXY(hand.x + 12, 4, hand.x + 12, floorY)
            case .rearBench:
                let f = sk.legs[sk.legs.count - 1].foot
                LXY(f.x - 6, f.y + 1, f.x + 5, f.y + 1)
                for x in [f.x - 4, f.x + 3] { LXY(x, f.y + 1, x, floorY) }
            case .footBlock:
                LXY(foot.x - 4, foot.y + 1, foot.x + 5, foot.y + 1)
                for x in [foot.x - 4, foot.x + 5] { LXY(x, foot.y + 1, x, floorY) }
            case .footPlate:
                LXY(foot.x + 1, foot.y - 7, foot.x + 2.5, foot.y + 7)
            case .highBar:
                LXY(hand.x - 20, hand.y, hand.x + 20, hand.y)
                for x in [hand.x - 20, hand.x + 20] { LXY(x, hand.y, x, hand.y - 6) }
            case .dipBars:
                LXY(hand.x - 14, hand.y, hand.x + 14, hand.y)
                for x in [hand.x - 10, hand.x + 10] { LXY(x, hand.y, x, floorY) }
            case .smithRails:
                for x in [hand.x - 16, hand.x + 16] { LXY(x, 4, x, floorY) }
            case .machineArm: L(hand, CGPoint(x: hand.x, y: hand.y + 12))
            case .tBar: L(hand, CGPoint(x: hand.x + 16, y: floorY - 1))
            case .post: LXY(hand2.x, 4, hand2.x, floorY)
            case .supportRail: LXY(hand2.x + 1, hand2.y - 12, hand2.x + 1, floorY)
            case .supportBench:
                LXY(hand2.x - 4, hand2.y + 1, hand2.x + 8, hand2.y + 1)
                for x in [hand2.x - 2, hand2.x + 6] { LXY(x, hand2.y + 1, x, floorY) }
            case .handBench:
                LXY(hand.x - 10, hand.y + 1, hand.x + 3, hand.y + 1)
                for x in [hand.x - 8, hand.x + 1] { LXY(x, hand.y + 1, x, floorY) }
            case .anklePad:
                let seatedLeg = !Skeleton.footFlat(sk.legs[0])
                pad(CGPoint(x: foot.x, y: foot.y + (seatedLeg ? 2 : 0)), vertical: seatedLeg)
            case .heelAnchor:
                LXY(foot.x - 3, floorY, foot.x - 3, foot.y - 4); LXY(foot.x - 3, foot.y - 4, foot.x + 3, foot.y - 4)
            case .calfBlock:
                LXY(foot.x + 2, foot.y, foot.x - 3, foot.y - 3); LXY(foot.x + 1, foot.y, foot.x + 5, foot.y)
                LXY(foot.x - 6, floorY, foot.x + 8, floorY); LXY(foot.x + 8, floorY, foot.x + 8, floorY - 4); LXY(foot.x - 6, floorY - 4, foot.x + 8, floorY - 4)
            case .dipBelt:
                LXY(hip.x + 2, hip.y, hip.x + 3, hip.y + 6); out.append(.circle(CGPoint(x: hip.x + 3, y: hip.y + 8), 2))
            }
        }
        if p.floor { out.append(.floor) }
        return out
    }

    // MARK: Primitives

    private func line(_ ctx: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ w: CGFloat, _ color: Color) {
        var path = Path(); path.move(to: a); path.addLine(to: b)
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    private func circle(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, fill: Color? = nil, stroke: Color? = nil, w: CGFloat = 0) {
        let path = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        if let fill { ctx.fill(path, with: .color(fill)) }
        if let stroke, w > 0 { ctx.stroke(path, with: .color(stroke), lineWidth: w) }
    }
}
