import SwiftUI
import WorkoutEngine
import WorkoutUI

/// Animated pictogram of a movement: an articulated wooden-mannequin figure with a mascot-sized head,
/// drawn from a small kinematic skeleton so limb proportions are consistent and the implement is always
/// in the hands. Every exercise is two keyframe poses (start / end of the rep) chosen for correct form
/// (neutral spine, bar over mid-foot, knees over toes); the figure eases between them, pinned at an
/// anchor (standing foot, bar in the hands, shoulders on a bench) so gear stays put while the body moves.
/// Barbells are seen end-on (a plate ring at the hand) because the figure is in profile.
/// Unit box 100×60, auto-framed around both keyframes, then scaled to fit.
///
/// The pose table is generated from tools/pictograms/motions.py, which also builds the HTML review sheet;
/// edit it there and rerun `python3 motions.py swift`.
struct ExerciseArt: View {
    let exerciseKey: String
    let pattern: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let repPeriod: TimeInterval = 2.8

    var body: some View {
        let renderer = FigureRenderer(motion: Motion.for(exerciseKey: exerciseKey, pattern: pattern))
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.card)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                Canvas(rendersAsynchronously: true) { ctx, size in
                    let t = reduceMotion ? 0 : Motion.phase(timeline.date.timeIntervalSinceReferenceDate, period: Self.repPeriod)
                    renderer.draw(in: &ctx, size: size, phase: t)
                }
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
        case cable, cableHigh, cableFromBehind, cableLowFront, cableBehindLow, cableFrontLevel
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

    /// Linear blend of joint angles; gear and props come from `a`.
    static func lerp(_ a: Pose, _ b: Pose, _ t: CGFloat) -> Pose {
        func L(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        func LO(_ x: CGFloat?, _ y: CGFloat?) -> CGFloat? {
            guard let x else { return y }; guard let y else { return x }; return L(x, y)
        }
        return Pose(L(a.hip.x, b.hip.x), L(a.hip.y, b.hip.y), L(a.torso, b.torso), L(a.upperArm, b.upperArm), L(a.forearm, b.forearm),
                    L(a.thigh, b.thigh), L(a.shin, b.shin),
                    headAngle: L(a.headAngle ?? a.torso, b.headAngle ?? b.torso),
                    upperArm2: LO(a.upperArm2, b.upperArm2), forearm2: LO(a.forearm2, b.forearm2),
                    thigh2: LO(a.thigh2, b.thigh2), shin2: LO(a.shin2, b.shin2),
                    implement: a.implement, props: a.props, grounded: a.grounded, floor: a.floor)
    }
}

/// Two keyframes of one rep plus the point that stays fixed while the body moves between them.
struct Motion {
    enum Anchor { case auto, hip, foot, foot2, hand, shoulder }

    var a: Pose, b: Pose
    var anchor: Anchor = .auto
    /// Interpolate arm joints in Cartesian space so a transverse sweep (fly, rear delt, face pull) foreshortens
    /// through the shoulder instead of swinging through the floor.
    var armsXY = false

    init(_ a: Pose, _ b: Pose, anchor: Anchor = .auto, armsXY: Bool = false) {
        var b = b
        if b.upperArm2 == nil { b.upperArm2 = a.upperArm2 }
        if b.forearm2 == nil { b.forearm2 = a.forearm2 }
        if b.thigh2 == nil { b.thigh2 = a.thigh2 }
        if b.shin2 == nil { b.shin2 = a.shin2 }
        self.a = a; self.b = b; self.anchor = anchor; self.armsXY = armsXY
    }

    var resolvedAnchor: Anchor {
        if anchor != .auto { return anchor }
        if !a.grounded && !a.floor { return .hand }
        return a.grounded ? .foot : .hip
    }

    /// Eased ping-pong A → B → A with a short hold at each end; 0...1.
    static func phase(_ time: TimeInterval, period: TimeInterval) -> CGFloat {
        let u = time.truncatingRemainder(dividingBy: period) / period
        let hold = 0.08, span = 0.5 - hold
        let t: Double
        if u < span { t = u / span } else if u < 0.5 { t = 1 } else if u < 0.5 + span { t = 1 - (u - 0.5) / span } else { t = 0 }
        return CGFloat((1 - cos(.pi * t)) / 2)
    }

    static func `for`(exerciseKey key: String, pattern: String) -> Motion {
        var m = base(exerciseKey: key, pattern: pattern)
        func fix(_ p: inout Pose) {
            if key.contains("dumbbell"), p.implement == .barbell { p.implement = .dumbbell }
            if key.contains("barbell"), p.implement == .dumbbell { p.implement = .barbell }
            if key.contains("smith"), !p.props.contains(.smithRails) { p.props.append(.smithRails) }
        }
        fix(&m.a); fix(&m.b)
        return m
    }

    // MARK: - Table (generated)

    // Generated by tools/pictograms/motions.py — edit that file and rerun `python3 motions.py swift`.
    static func base(exerciseKey key: String, pattern: String) -> Motion {
        switch key {
        case "decline_push_up":
            return Motion(Pose(56, 38.6, 175, 90, 90, -5, -5, props: [.footBlock], grounded: false),
                   Pose(56, 38.6, 159, 45, 174, -21, -21, headAngle: 172, props: [.footBlock], grounded: false), anchor: .foot)
        case "push_up":
            return Motion(Pose(56, 46.5, -156, 90, 90, 24, 24, grounded: false),
                   Pose(56, 46.5, -170, -10, 130, 10, 10, grounded: false), anchor: .foot)
        case "dumbbell_floor_press":
            return Motion(Pose(56, 52.5, 180, -70, -90, -40, 100, implement: .dumbbell, grounded: false),
                   Pose(56, 52.5, 180, 20, -90, -40, 100, implement: .dumbbell, grounded: false))
        case "close_grip_bench_press":
            return Motion(Pose(58, 40, 180, -70, -90, 60, 90, implement: .barbellNarrow, props: [.bench]),
                   Pose(58, 40, 180, 5, -80, 60, 90, implement: .barbellNarrow, props: [.bench]))
        case "machine_chest_press":
            return Motion(Pose(44, 38, -90, 0, 0, 0, 90, implement: .handle, props: [.seat, .backrest, .machineArm]),
                   Pose(44, 38, -90, 125, -15, 0, 90, implement: .handle, props: [.seat, .backrest, .machineArm]))
        case "weighted_dip":
            return Motion(Pose(50, 36, -75, 150, 90, 100, 170, props: [.dipBars, .dipBelt], grounded: false, floor: false),
                   Pose(50, 36, -82, 90, 90, 100, 170, props: [.dipBars, .dipBelt], grounded: false, floor: false))
        case "machine_shoulder_press":
            return Motion(Pose(44, 38, -90, 30, -90, 0, 90, implement: .handle, props: [.seat, .backrest, .machineArm]),
                   Pose(44, 38, -90, -80, -90, 0, 90, implement: .handle, props: [.seat, .backrest, .machineArm]))
        case "seated_dumbbell_press":
            return Motion(Pose(44, 38, -90, 65, -105, 0, 90, implement: .dumbbell, props: [.seat, .backrest]),
                   Pose(44, 38, -90, -90, -90, 0, 90, implement: .dumbbell, props: [.seat, .backrest]))
        case "dumbbell_shoulder_press":
            return Motion(Pose(44, 38, -90, 65, -105, 0, 90, implement: .dumbbell, props: [.seat, .backrest]),
                   Pose(44, 38, -90, -90, -90, 0, 90, implement: .dumbbell, props: [.seat, .backrest]))
        case "arnold_press":
            return Motion(Pose(44, 38, -90, 40, -70, 0, 90, implement: .dumbbellVertical, props: [.seat, .backrest]),
                   Pose(44, 38, -90, -90, -90, 0, 90, implement: .dumbbellVertical, props: [.seat, .backrest]))
        case "skullcrusher":
            return Motion(Pose(58, 40, 180, -90, 180, 60, 90, implement: .shortBar, props: [.bench]),
                   Pose(58, 40, 180, -90, 270, 60, 90, implement: .shortBar, props: [.bench]))
        case "dumbbell_overhead_extension":
            return Motion(Pose(50, 36, -86, -75, -160, 90, 90, implement: .dumbbellVertical),
                   Pose(50, 36, -86, -75, -90, 90, 90, implement: .dumbbellVertical))
        case "overhead_cable_extension":
            return Motion(Pose(46, 36, -70, -100, -165, 80, 90, implement: .handle, props: [.cableFromBehind]),
                   Pose(46, 36, -70, -100, -40, 80, 90, implement: .handle, props: [.cableFromBehind]))
        case "cable_pushdown":
            return Motion(Pose(50, 36, -90, 90, -30, 90, 90, implement: .handle, props: [.cable]),
                   Pose(50, 36, -90, 90, 80, 90, 90, implement: .handle, props: [.cable]))
        case "bench_dip":
            return Motion(Pose(52, 44, -80, 160, 90, 10, 60, props: [.handBench]),
                   Pose(55, 40.6, -105, 104.6, 104.6, 38, 66, props: [.handBench], grounded: false), anchor: .hand)
        case "pec_deck_fly":
            return Motion(Pose(44, 38, -90, 135, -75, 0, 90, props: [.seat, .backrest, .machineArm]),
                   Pose(44, 38, -90, 0, -70, 0, 90, props: [.seat, .backrest, .machineArm]), armsXY: true)
        case "reverse_pec_deck":
            return Motion(Pose(46, 38, -90, 5, 5, 0, 90, implement: .handle, props: [.seat, .chestPad]),
                   Pose(46, 38, -90, 175, 175, 0, 90, implement: .handle, props: [.seat, .chestPad]), armsXY: true)
        case "cable_fly":
            return Motion(Pose(46, 36, -80, 140, -110, 90, 90, implement: .handle, props: [.cableFromBehind]),
                   Pose(46, 36, -80, -10, 0, 90, 90, implement: .handle, props: [.cableFromBehind]), armsXY: true)
        case "cable_lateral_raise":
            return Motion(Pose(50, 36, -90, 80, 60, 90, 90, implement: .handle, props: [.cableLowFront]),
                   Pose(50, 36, -90, 0, 5, 90, 90, implement: .handle, props: [.cableLowFront]))
        case "lean_away_lateral_raise":
            return Motion(Pose(50, 36, -75, 85, 80, 90, 90, upperArm2: 170, forearm2: 170, implement: .handle, props: [.cableLowFront, .post]),
                   Pose(50, 36, -75, 0, 5, 90, 90, upperArm2: 170, forearm2: 170, implement: .handle, props: [.cableLowFront, .post]))
        case "pull_up":
            return Motion(Pose(50, 36, -90, -90, -90, 95, 120, props: [.highBar], grounded: false, floor: false),
                   Pose(50, 36, -90, -135, -45, 95, 120, props: [.highBar], grounded: false, floor: false))
        case "weighted_pull_up":
            return Motion(Pose(50, 36, -90, -90, -90, 95, 120, props: [.highBar, .dipBelt], grounded: false, floor: false),
                   Pose(50, 36, -90, -135, -45, 95, 120, props: [.highBar, .dipBelt], grounded: false, floor: false))
        case "chin_up":
            return Motion(Pose(50, 36, -90, -85, -85, 95, 120, props: [.highBar], grounded: false, floor: false),
                   Pose(50, 36, -90, 20, -120, 95, 120, props: [.highBar], grounded: false, floor: false))
        case "neutral_grip_pulldown":
            return Motion(Pose(46, 38, -100, -80, -80, 0, 90, implement: .barbellNarrow, props: [.cableHigh, .seat]),
                   Pose(46, 38, -100, 120, -30, 0, 90, implement: .barbellNarrow, props: [.cableHigh, .seat]))
        case "straight_arm_pulldown":
            return Motion(Pose(46, 36, -80, -30, -30, 85, 90, implement: .barbellNarrow, props: [.cable]),
                   Pose(46, 36, -80, 75, 75, 85, 90, implement: .barbellNarrow, props: [.cable]))
        case "kneeling_cable_pulldown":
            return Motion(Pose(46, 40, -90, -40, -110, 90, 180, implement: .handle, props: [.cable]),
                   Pose(46, 40, -90, 150, -40, 90, 180, implement: .handle, props: [.cable]))
        case "pendlay_row":
            return Motion(Pose(40, 34, -20, 90, 90, 40, 75, headAngle: 10, implement: .barbell),
                   Pose(40, 34, -20, 160, 50, 40, 75, headAngle: 10, implement: .barbell))
        case "t_bar_row":
            return Motion(Pose(44, 34, -35, 90, 90, 60, 80, implement: .handle, props: [.tBar]),
                   Pose(44, 34, -35, 150, 60, 60, 80, implement: .handle, props: [.tBar]))
        case "chest_supported_row":
            return Motion(Pose(44, 38, -50, 100, 100, 90, 90, implement: .handle, props: [.seat, .frontPad]),
                   Pose(44, 38, -50, 160, 70, 90, 90, implement: .handle, props: [.seat, .frontPad]))
        case "seated_cable_row":
            return Motion(Pose(40, 44, -95, 10, 0, -10, 40, implement: .handle, props: [.seat, .cableFrontLevel, .footPlate], grounded: false),
                   Pose(40, 44, -95, 160, 20, -10, 40, implement: .handle, props: [.seat, .cableFrontLevel, .footPlate], grounded: false))
        case "single_arm_dumbbell_row":
            return Motion(Pose(40, 36, -30, 100, 90, 75, 85, upperArm2: 60, forearm2: 60, thigh2: 55, shin2: 80, implement: .dumbbellFirst, props: [.supportBench]),
                   Pose(40, 36, -30, 165, 75, 75, 85, upperArm2: 60, forearm2: 60, thigh2: 55, shin2: 80, implement: .dumbbellFirst, props: [.supportBench]))
        case "inverted_row":
            return Motion(Pose(50, 49, -160, -90, -90, 20, 20, props: [.highBar], grounded: false),
                   Pose(53.7, 42.7, -139.2, 158, -82, 40.8, 40.8, props: [.highBar], grounded: false), anchor: .hand)
        case "face_pull":
            return Motion(Pose(50, 36, -90, -20, -20, 80, 90, thigh2: 100, shin2: 90, implement: .handle, props: [.cableFrontLevel]),
                   Pose(50, 36, -90, 160, -40, 80, 90, thigh2: 100, shin2: 90, implement: .handle, props: [.cableFrontLevel]), armsXY: true)
        case "cable_reverse_fly":
            return Motion(Pose(50, 36, -80, 0, 0, 90, 90, implement: .handle, props: [.cableFrontLevel]),
                   Pose(50, 36, -80, 175, 175, 90, 90, implement: .handle, props: [.cableFrontLevel]), armsXY: true)
        case "hammer_curl":
            return Motion(Pose(50, 36, -90, 90, 85, 90, 90, implement: .dumbbellVertical),
                   Pose(50, 36, -90, 90, -55, 90, 90, implement: .dumbbellVertical))
        case "cable_curl":
            return Motion(Pose(50, 36, -90, 90, 85, 90, 90, implement: .handle, props: [.cableLowFront]),
                   Pose(50, 36, -90, 90, -55, 90, 90, implement: .handle, props: [.cableLowFront]))
        case "preacher_curl":
            return Motion(Pose(44, 38, -90, 35, 30, 0, 90, implement: .shortBar, props: [.seat, .preacherPad]),
                   Pose(44, 38, -90, 35, -50, 0, 90, implement: .shortBar, props: [.seat, .preacherPad]))
        case "incline_dumbbell_curl":
            return Motion(Pose(52, 42, -130, 100, 100, 60, 90, implement: .dumbbell, props: [.inclineBench]),
                   Pose(52, 42, -130, 100, -45, 60, 90, implement: .dumbbell, props: [.inclineBench]))
        case "front_squat":
            return Motion(Pose(44, 36, -70, -10, 165, 10, 120, implement: .barbell),
                   Pose(44, 36, -90, -10, 165, 90, 90, implement: .barbell))
        case "goblet_squat":
            return Motion(Pose(44, 36, -72, 60, -70, 10, 120, implement: .dumbbellVertical),
                   Pose(44, 36, -90, 60, -70, 90, 90, implement: .dumbbellVertical))
        case "hack_squat":
            return Motion(Pose(44, 36, -120, 110, 60, 0, 80, props: [.hackPad]),
                   Pose(44, 36, -120, 110, 60, 40, 48, props: [.hackPad]))
        case "leg_press":
            return Motion(Pose(40, 42, -130, 20, 60, -50, -10, props: [.seat, .backrest, .footPlate], grounded: false),
                   Pose(40, 42, -130, 20, 60, -83, 23, props: [.seat, .backrest, .footPlate], grounded: false))
        case "bulgarian_split_squat":
            return Motion(Pose(50, 36, -90, 90, 90, 0, 90, thigh2: 135, shin2: 190, implement: .dumbbellVertical, props: [.rearBench]),
                   Pose(50, 36, -90, 90, 90, 37, 90, thigh2: 150, shin2: 150, implement: .dumbbellVertical, props: [.rearBench]))
        case "walking_lunge":
            return Motion(Pose(50, 36, -90, 90, 90, 90, 90, thigh2: 90, shin2: 90, implement: .dumbbellVertical),
                   Pose(50, 36, -90, 90, 90, 0, 90, thigh2: 125, shin2: 170, implement: .dumbbellVertical), anchor: .foot2)
        case "reverse_lunge":
            return Motion(Pose(50, 36, -88, 90, 90, 90, 90, thigh2: 90, shin2: 90, implement: .dumbbellVertical),
                   Pose(50, 36, -88, 90, 90, 0, 90, thigh2: 125, shin2: 170, implement: .dumbbellVertical), anchor: .foot)
        case "step_up":
            return Motion(Pose(50, 36, -90, 90, 90, -10, 90, thigh2: 90, shin2: 90, implement: .dumbbellVertical, props: [.footBlock], grounded: false),
                   Pose(50, 24.3, -90, 90, 90, 90, 90, thigh2: 90, shin2: 90, implement: .dumbbellVertical, props: [.footBlock], grounded: false), anchor: .foot)
        case "romanian_deadlift":
            return Motion(Pose(42, 32, -90, 90, 90, 90, 90, implement: .barbell),
                   Pose(42, 32, -32, 100, 100, 72, 85, implement: .barbell))
        case "dumbbell_romanian_deadlift":
            return Motion(Pose(42, 32, -90, 90, 90, 90, 90, implement: .dumbbell),
                   Pose(42, 32, -32, 100, 100, 72, 85, implement: .dumbbell))
        case "trap_bar_deadlift":
            return Motion(Pose(40, 32, -40, 90, 90, 50, 68, implement: .trapBar),
                   Pose(40, 32, -90, 90, 90, 90, 90, implement: .trapBar))
        case "good_morning":
            return Motion(Pose(42, 32, -90, -170, 30, 88, 90, implement: .barbell),
                   Pose(42, 32, -32, -170, 30, 60, 80, implement: .barbell))
        case "kettlebell_swing":
            return Motion(Pose(44, 34, -35, 95, 95, 50, 80, implement: .kettlebell),
                   Pose(44, 34, -90, 0, 0, 90, 90, implement: .kettlebell))
        case "cable_pull_through":
            return Motion(Pose(44, 32, -30, 120, 150, 60, 85, implement: .handle, props: [.cableBehindLow]),
                   Pose(44, 32, -90, 95, 80, 90, 90, implement: .handle, props: [.cableBehindLow]))
        case "barbell_hip_thrust":
            return Motion(Pose(56, 40, 180, 0, 0, 0, 90, implement: .barbellOnHips, props: [.bench]),
                   Pose(54.6, 52.3, -155, 10, 10, -35, 71, implement: .barbellOnHips, props: [.bench], grounded: false), anchor: .shoulder)
        case "seated_leg_curl":
            return Motion(Pose(44, 38, -95, 20, 60, 0, 5, props: [.seat, .backrest, .anklePad]),
                   Pose(44, 38, -95, 20, 60, 0, 80, props: [.seat, .backrest, .anklePad]))
        case "nordic_curl":
            return Motion(Pose(44, 46, -70, 60, 180, 110, 180, props: [.heelAnchor]),
                   Pose(44, 46, -30, 65, 40, 150, 180, props: [.heelAnchor]))
        case "standing_calf_raise":
            return Motion(Pose(46, 36, -90, -20, -70, 90, 90, implement: .handle, props: [.calfBlock, .shoulderPads], grounded: false),
                   Pose(46, 33, -90, -20, -70, 90, 90, implement: .handle, props: [.calfBlock, .shoulderPads], grounded: false))
        case "seated_calf_raise":
            return Motion(Pose(44, 46, -90, 40, 60, 0, 90, props: [.seat, .calfBlock, .kneePad], grounded: false),
                   Pose(44, 46, -90, 40, 60, -17, 90, props: [.seat, .calfBlock, .kneePad], grounded: false), anchor: .hip)
        case "dumbbell_calf_raise":
            return Motion(Pose(46, 36, -90, 90, 90, 90, 90, upperArm2: -10, forearm2: -10, implement: .dumbbellFirst, props: [.calfBlock, .supportRail], grounded: false),
                   Pose(46, 33, -90, 90, 90, 90, 90, upperArm2: -10, forearm2: -10, implement: .dumbbellFirst, props: [.calfBlock, .supportRail], grounded: false))
        case "bodyweight_calf_raise":
            return Motion(Pose(46, 36, -90, -10, -10, 90, 90, props: [.calfBlock, .supportRail], grounded: false),
                   Pose(46, 33, -90, -10, -10, 90, 90, props: [.calfBlock, .supportRail], grounded: false))
        case "hanging_leg_raise":
            return Motion(Pose(50, 36, -90, -90, -90, 85, 88, props: [.highBar], grounded: false, floor: false),
                   Pose(50, 36, -90, -90, -90, -5, -5, props: [.highBar], grounded: false, floor: false))
        case "cable_crunch":
            return Motion(Pose(50, 40, -88, -140, -40, 90, 180, props: [.cable]),
                   Pose(50, 40, -50, -140, -40, 90, 180, props: [.cable]))
        case "ab_wheel_rollout":
            return Motion(Pose(44, 47, -45, 75, 75, 100, 180, implement: .wheel),
                   Pose(44, 47, -20, 55, 55, 120, 180, implement: .wheel))
        case "decline_sit_up":
            return Motion(Pose(46, 44, 160, -60, 80, -25, 60, props: [.declineBench], grounded: false),
                   Pose(46, 44, 260, 40, 180, -25, 60, props: [.declineBench], grounded: false))
        case "pallof_press":
            return Motion(Pose(46, 40, -90, 120, -50, 90, 180, thigh2: 0, shin2: 90, implement: .handle, props: [.cableFrontLevel]),
                   Pose(46, 40, -90, 0, 0, 90, 180, thigh2: 0, shin2: 90, implement: .handle, props: [.cableFrontLevel]))
        case "plank":
            return Motion(Pose(56, 52, -165, 90, 0, 15, 15, grounded: false),
                   Pose(56, 52, -164, 90, 0, 14.5, 14.5, grounded: false), anchor: .foot)
        case "side_plank":
            return Motion(Pose(56, 47.2, -154, 90, 90, 26, 26, upperArm2: -90, forearm2: -90, grounded: false),
                   Pose(56, 47.2, -153, 90, 90, 25.5, 25.5, upperArm2: -92, forearm2: -92, grounded: false), anchor: .foot)
        case "hollow_hold":
            return Motion(Pose(50, 52, -165, -100, -100, -12, -12, grounded: false),
                   Pose(50, 52, -163, -98, -98, -14, -14, grounded: false), anchor: .hip)
        case "dead_bug":
            return Motion(Pose(50, 52, 180, -90, -90, -90, 0, thigh2: -10, shin2: -10, grounded: false),
                   Pose(50, 52, 180, -150, -170, -15, -5, thigh2: -90, shin2: 0, grounded: false))
        case "bird_dog":
            return Motion(Pose(42, 46, -20, 90, 90, 90, 180, headAngle: 25, upperArm2: -20, forearm2: -20, thigh2: 170, shin2: 170, grounded: false),
                   Pose(42, 46, -20, 90, 90, 90, 180, headAngle: 25, upperArm2: 90, forearm2: 90, thigh2: 90, shin2: 180, grounded: false), anchor: .foot)
        case "russian_twist":
            return Motion(Pose(50, 54, -120, -25, -25, -45, 65, grounded: false),
                   Pose(50, 54, -120, 150, -25, -45, 65, grounded: false), armsXY: true)
        default: break
        }
        switch pattern {
        case "horizontal_press":
            return Motion(Pose(58, 40, 180, -70, -90, 60, 90, implement: .barbell, props: [.bench]),
                   Pose(58, 40, 180, 5, -80, 60, 90, implement: .barbell, props: [.bench]))
        case "incline_press":
            return Motion(Pose(58, 42, -145, -75, -90, 60, 90, implement: .barbell, props: [.inclineBench]),
                   Pose(58, 42, -145, 30, -93, 60, 90, implement: .barbell, props: [.inclineBench]))
        case "vertical_press":
            return Motion(Pose(50, 36, -90, 60, -115, 90, 90, implement: .barbell),
                   Pose(50, 36, -90, -90, -90, 90, 90, implement: .barbell))
        case "chest_fly":
            return Motion(Pose(58, 40, 180, -40, -55, 60, 90, upperArm2: -140, forearm2: -125, implement: .dumbbell, props: [.bench]),
                   Pose(58, 40, 180, -85, -85, 60, 90, upperArm2: -95, forearm2: -95, implement: .dumbbell, props: [.bench]))
        case "lateral_raise":
            return Motion(Pose(50, 36, -90, 95, 95, 90, 90, upperArm2: 85, forearm2: 85, implement: .dumbbellVertical),
                   Pose(50, 36, -90, 0, 5, 90, 90, upperArm2: 180, forearm2: 175, implement: .dumbbellVertical))
        case "triceps_extension":
            return Motion(Pose(50, 36, -90, -80, -160, 90, 90, implement: .dumbbellVertical),
                   Pose(50, 36, -90, -80, -90, 90, 90, implement: .dumbbellVertical))
        case "vertical_pull":
            return Motion(Pose(46, 38, -100, -80, -80, 0, 90, implement: .barbell, props: [.cableHigh, .seat]),
                   Pose(46, 38, -100, 120, -30, 0, 90, implement: .barbell, props: [.cableHigh, .seat]))
        case "horizontal_row":
            return Motion(Pose(44, 34, -35, 90, 90, 60, 80, implement: .barbell),
                   Pose(44, 34, -35, 150, 60, 60, 80, implement: .barbell))
        case "rear_delt":
            return Motion(Pose(44, 34, -45, 85, 85, 112, 74, implement: .dumbbell),
                   Pose(44, 34, -45, -115, -105, 112, 74, implement: .dumbbell), armsXY: true)
        case "elbow_flexion":
            return Motion(Pose(50, 36, -90, 90, 85, 90, 90, implement: .dumbbell),
                   Pose(50, 36, -90, 90, -55, 90, 90, implement: .dumbbell))
        case "squat":
            return Motion(Pose(44, 36, -55, -170, 10, 10, 115, implement: .barbell),
                   Pose(44, 36, -90, -170, 10, 90, 90, implement: .barbell))
        case "hinge":
            return Motion(Pose(40, 32, -40, 90, 90, 50, 68, implement: .barbell),
                   Pose(40, 32, -90, 90, 90, 90, 90, implement: .barbell))
        case "quad_isolation":
            return Motion(Pose(44, 36, -90, 90, 90, 0, 80, props: [.seat, .backrest, .anklePad], grounded: false),
                   Pose(44, 36, -90, 90, 90, 0, 0, props: [.seat, .backrest, .anklePad], grounded: false))
        case "hamstring_isolation":
            return Motion(Pose(54, 42, 180, 150, 90, 0, 5, props: [.bench, .anklePad], grounded: false),
                   Pose(54, 42, 180, 150, 90, 0, -90, props: [.bench, .anklePad], grounded: false))
        case "calf":
            return Motion(Pose(46, 36, -90, -10, -10, 90, 90, props: [.calfBlock, .supportRail], grounded: false),
                   Pose(46, 33, -90, -10, -10, 90, 90, props: [.calfBlock, .supportRail], grounded: false))
        default:
            return Motion(Pose(50, 54, -155, -120, 160, -50, 70, grounded: false),
                   Pose(50, 54, -120, -85, 195, -50, 70, grounded: false), anchor: .hip)
        }
    }

    // MARK: - End table
}

// MARK: - Kinematics

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
        if p.grounded { shift(0, floorY - legs.map(\.foot.y).max()!) }
    }

    mutating func shift(_ dx: CGFloat, _ dy: CGFloat) {
        hip = off(hip, dx, dy); shoulder = off(shoulder, dx, dy); head = off(head, dx, dy)
        arms = arms.map { Arm(elbow: off($0.elbow, dx, dy), hand: off($0.hand, dx, dy)) }
        legs = legs.map { Leg(knee: off($0.knee, dx, dy), foot: off($0.foot, dx, dy), shinAngle: $0.shinAngle) }
    }

    func anchorPoint(_ mode: Motion.Anchor) -> CGPoint {
        switch mode {
        case .foot: return legs[0].foot
        case .foot2: return legs[legs.count - 1].foot
        case .hand: return arms[0].hand
        case .shoulder: return shoulder
        case .hip, .auto: return hip
        }
    }

    /// Move so this skeleton's anchor coincides with `ref`'s (grounded feet only slide horizontally).
    mutating func anchor(to ref: Skeleton, _ mode: Motion.Anchor) {
        let a = anchorPoint(mode), b = ref.anchorPoint(mode)
        let dy = (pose.grounded && (mode == .foot || mode == .foot2)) ? 0 : b.y - a.y
        shift(b.x - a.x, dy)
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

    let motion: Motion
    let anchor: Motion.Anchor
    /// Anchored keyframes: props are built from `skA` so gear never moves; `skB` fixes the framing.
    let skA: Skeleton, skB: Skeleton
    let origin: CGPoint, span: CGSize

    init(motion: Motion) {
        self.motion = motion
        anchor = motion.resolvedAnchor
        skA = Skeleton(motion.a)
        var b = Skeleton(motion.b); b.anchor(to: skA, anchor)
        skB = b
        let fr = Self.frame(skA, skB, anchor: anchor)
        origin = fr.0; span = fr.1
    }

    /// Live skeleton at phase `t`.
    func skeleton(at t: CGFloat) -> Skeleton {
        var sk = Skeleton(Pose.lerp(motion.a, motion.b, t))
        sk.anchor(to: skA, anchor)
        if motion.armsXY {
            let s = sk.shoulder
            sk.arms = sk.arms.indices.map { i in
                let pa = skA.arms[min(i, skA.arms.count - 1)], pb = skB.arms[min(i, skB.arms.count - 1)]
                func blend(_ qa: CGPoint, _ qb: CGPoint) -> CGPoint {
                    let ra = CGPoint(x: qa.x - skA.shoulder.x, y: qa.y - skA.shoulder.y), rb = CGPoint(x: qb.x - skB.shoulder.x, y: qb.y - skB.shoulder.y)
                    return CGPoint(x: s.x + ra.x + (rb.x - ra.x) * t, y: s.y + ra.y + (rb.y - ra.y) * t)
                }
                return Skeleton.Arm(elbow: blend(pa.elbow, pb.elbow), hand: blend(pa.hand, pb.hand))
            }
        }
        return sk
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize, phase t: CGFloat) {
        let sk = skeleton(at: t)
        let props = Self.propPrims(fixed: skA, live: sk)
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
        drawImplement(&ctx, sk)

        let (rest, nearArm) = segments(sk)
        for s in rest { segment(&ctx, s) }
        for (i, leg) in sk.legs.enumerated() where Skeleton.footFlat(leg) {
            let pinned = (i == 0 && anchor == .foot) || (i == sk.legs.count - 1 && anchor == .foot2)
            let toe = off(pinned ? skA.legs[i].foot : leg.foot, 5, 0)
            line(&ctx, leg.foot, toe, Self.limbW + 1.0, card)
            line(&ctx, leg.foot, toe, Self.limbW - 0.4, brass)
        }
        drawHead(&ctx, sk)
        for s in nearArm { segment(&ctx, s) }
        circle(&ctx, sk.hand, Self.limbW * 0.6, fill: brass, stroke: card, w: 0.9)
    }

    /// Bounding box (with padding) around everything drawn in either keyframe, in unit space.
    private static func frame(_ a: Skeleton, _ b: Skeleton, anchor: Motion.Anchor) -> (CGPoint, CGSize) {
        var pts: [CGPoint] = []
        for sk in [a, b] {
            pts += [sk.hip, sk.shoulder, off(sk.head, -headR, -headR), off(sk.head, headR, headR)]
            for arm in sk.arms { pts += [arm.elbow, arm.hand] }
            for l in sk.legs { pts += [l.knee, l.foot] }
            if sk.pose.implement != .none {
                let r = plateR[sk.pose.implement] ?? 4
                let c = sk.pose.implement == .barbellOnHips ? sk.hip : sk.hand
                pts += [off(c, -r, -r), off(c, r, r)]
            }
            for prim in propPrims(fixed: a, live: sk) {
                switch prim {
                case .line(let p, let q), .plate(let p, let q): pts += [p, q]
                case .circle(let c, let r): pts += [off(c, -r, -r), off(c, r, r)]
                case .floor: break
                }
            }
        }
        var x0 = pts.map(\.x).min()!, x1 = pts.map(\.x).max()!
        var y0 = pts.map(\.y).min()!, y1 = pts.map(\.y).max()!
        if a.pose.floor { y1 = max(y1, floorY) }
        let pad: CGFloat = 4.5
        x0 -= pad; x1 += pad; y0 -= pad; y1 += pad
        return (CGPoint(x: x0, y: y0), CGSize(width: x1 - x0, height: y1 - y0))
    }

    /// Far limbs first (dimmed), then torso, then the near leg; the near arm is returned separately
    /// so it can be drawn over the head.
    private func segments(_ sk: Skeleton) -> ([Segment], [Segment]) {
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

    private func drawHead(_ ctx: inout GraphicsContext, _ sk: Skeleton) {
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
    private func drawImplement(_ ctx: inout GraphicsContext, _ sk: Skeleton) {
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

    /// Fixed gear (benches, bars, blocks) is placed from the first keyframe; cables, pads and belts follow the live skeleton.
    private static func propPrims(fixed: Skeleton, live: Skeleton) -> [Prim] {
        let p = fixed.pose
        let hip = fixed.hip, shoulder = fixed.shoulder, hand = fixed.hand, hand2 = fixed.farHand
        let knee = fixed.legs[0].knee, foot = fixed.legs[0].foot
        let lh = live.hand, lhip = live.hip, lsh = live.shoulder, lknee = live.legs[0].knee, lfoot = live.legs[0].foot
        var out: [Prim] = []
        func L(_ a: CGPoint, _ b: CGPoint) { out.append(.line(a, b)) }
        func LXY(_ ax: CGFloat, _ ay: CGFloat, _ bx: CGFloat, _ by: CGFloat) { out.append(.line(CGPoint(x: ax, y: ay), CGPoint(x: bx, y: by))) }
        func legs(_ a: CGPoint, _ b: CGPoint) { L(a, b); L(a, CGPoint(x: a.x, y: floorY)); L(b, CGPoint(x: b.x, y: floorY)) }
        /// Roller pad perpendicular to the limb at `deg`.
        func pad(_ c: CGPoint, _ deg: CGFloat) {
            let r = deg * .pi / 180
            let u = CGPoint(x: cos(r), y: sin(r)), v = CGPoint(x: -u.y, y: u.x)
            func P(_ s: CGFloat, _ w: CGFloat) -> CGPoint { CGPoint(x: c.x + u.x * s + v.x * w, y: c.y + u.y * s + v.y * w) }
            out.append(.line(P(0, -3.5), P(0, 3.5)))
            for w: CGFloat in [-3.5, 3.5] { out.append(.plate(P(-2.5, w), P(2.5, w))) }
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
                let n = frontNormal(live.pose.torso)
                let low = CGPoint(x: lhip.x - 3 * n.x, y: lhip.y - 3 * n.y + 3), high = CGPoint(x: lsh.x - 3 * n.x - 2, y: lsh.y - 3 * n.y - 5)
                L(low, high); L(low, CGPoint(x: low.x + 4, y: floorY))
            case .frontPad:
                let n = frontNormal(p.torso)
                let low = CGPoint(x: hip.x + 3 * n.x, y: hip.y + 3 * n.y), high = CGPoint(x: shoulder.x + 3 * n.x + 2, y: shoulder.y + 3 * n.y - 2)
                L(low, high); L(low, CGPoint(x: low.x, y: floorY))
            case .preacherPad:
                let elbow = fixed.arms[0].elbow
                let top = CGPoint(x: shoulder.x + 1, y: shoulder.y + 3), bottom = CGPoint(x: elbow.x + 4, y: elbow.y + 3)
                L(top, bottom); L(bottom, CGPoint(x: bottom.x, y: floorY))
            case .chestPad:
                LXY(shoulder.x + 3, shoulder.y - 5, shoulder.x + 3, hip.y + 2.5)
            case .kneePad:
                LXY(lknee.x - 3, lknee.y - 3.5, lknee.x + 4, lknee.y - 3.5); LXY(lknee.x + 4, lknee.y - 3.5, lknee.x + 4, floorY)
            case .shoulderPads:
                LXY(lsh.x - 1, lsh.y - 1.5, lsh.x + 5, lsh.y - 1.5); LXY(lsh.x + 5, 6, lsh.x + 5, floorY); L(CGPoint(x: lsh.x + 5, y: lh.y), lh)
            case .cable:
                L(lh, CGPoint(x: hand.x + 10, y: 4)); LXY(hand.x - 4, 4, hand.x + 24, 4)
            case .cableHigh:
                L(lh, CGPoint(x: hand.x + 3, y: 2)); LXY(hand.x - 11, 2, hand.x + 17, 2)
            case .cableFromBehind:
                L(lh, CGPoint(x: hand.x - 22, y: 4)); LXY(hand.x - 26, 4, hand.x - 18, 4)
            case .cableLowFront:
                L(lh, CGPoint(x: hand.x + 6, y: floorY - 4)); LXY(hand.x + 3, floorY - 4, hand.x + 9, floorY - 4)
            case .cableBehindLow:
                L(lh, CGPoint(x: hand.x - 18, y: floorY - 6)); LXY(hand.x - 21, floorY - 6, hand.x - 15, floorY - 6)
            case .cableFrontLevel:
                L(lh, CGPoint(x: hand.x + 12, y: hand.y)); LXY(hand.x + 12, 4, hand.x + 12, floorY)
            case .rearBench:
                let f = fixed.legs[fixed.legs.count - 1].foot
                LXY(f.x - 6, f.y + 1, f.x + 5, f.y + 1)
                for x in [f.x - 4, f.x + 3] { LXY(x, f.y + 1, x, floorY) }
            case .footBlock:
                LXY(foot.x - 4, foot.y + 1, foot.x + 5, foot.y + 1)
                for x in [foot.x - 4, foot.x + 5] { LXY(x, foot.y + 1, x, floorY) }
            case .footPlate:
                LXY(lfoot.x + 1, lfoot.y - 7, lfoot.x + 2.5, lfoot.y + 7)
            case .highBar:
                LXY(hand.x - 20, hand.y, hand.x + 20, hand.y)
                for x in [hand.x - 20, hand.x + 20] { LXY(x, hand.y, x, hand.y - 6) }
            case .dipBars:
                LXY(hand.x - 14, hand.y, hand.x + 14, hand.y)
                for x in [hand.x - 10, hand.x + 10] { LXY(x, hand.y, x, floorY) }
            case .smithRails:
                for x in [hand.x - 16, hand.x + 16] { LXY(x, 4, x, floorY) }
            case .machineArm: L(lh, CGPoint(x: hand.x, y: hand.y + 12))
            case .tBar: L(lh, CGPoint(x: hand.x + 16, y: floorY - 1))
            case .post: LXY(hand2.x, 4, hand2.x, floorY)
            case .supportRail: LXY(hand2.x + 1, hand2.y - 12, hand2.x + 1, floorY)
            case .supportBench:
                LXY(hand2.x - 4, hand2.y + 1, hand2.x + 8, hand2.y + 1)
                for x in [hand2.x - 2, hand2.x + 6] { LXY(x, hand2.y + 1, x, floorY) }
            case .handBench:
                LXY(hand.x - 10, hand.y + 1, hand.x + 3, hand.y + 1)
                for x in [hand.x - 8, hand.x + 1] { LXY(x, hand.y + 1, x, floorY) }
            case .anklePad:
                let l = live.legs[0]
                pad(l.foot, l.shinAngle)
            case .heelAnchor:
                LXY(foot.x - 3, floorY, foot.x - 3, foot.y - 4); LXY(foot.x - 3, foot.y - 4, foot.x + 3, foot.y - 4)
            case .calfBlock:
                let toe = CGPoint(x: foot.x + 5, y: floorY)
                LXY(toe.x - 9, floorY, toe.x + 3, floorY); LXY(toe.x + 3, floorY, toe.x + 3, floorY + 3.5)
                LXY(toe.x - 9, floorY + 3.5, toe.x + 3, floorY + 3.5); LXY(toe.x - 9, floorY, toe.x - 9, floorY + 3.5)
            case .dipBelt:
                LXY(lhip.x + 2, lhip.y, lhip.x + 3, lhip.y + 6); out.append(.circle(CGPoint(x: lhip.x + 3, y: lhip.y + 8), 2))
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
