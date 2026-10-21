import SwiftUI
import WorkoutEngine
import WorkoutUI

/// Minimal line-art pictogram of a movement: a stick figure plus the implement, one per movement pattern.
/// Drawn in a 100×60 unit box and scaled to fit; stroked, never filled, so it stays quiet on the card.
struct ExerciseArt: View {
    let exerciseKey: String
    let pattern: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.card)
            FigureShape(kind: FigureKind.for(exerciseKey: exerciseKey, pattern: pattern))
                .stroke(Theme.Colors.brass, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .padding(Theme.Spacing.m)
        }
        .aspectRatio(100.0 / 60.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

enum FigureKind {
    case benchPress, inclinePress, overheadPress, fly, lateralRaise, tricepsExtension, pushUp, dip
    case pullUp, pulldown, row, rearDelt, curl
    case squat, hinge, legExtension, legCurl, calf, lunge, hipThrust
    case plank, hangingLegRaise, crunch, deadBug

    static func `for`(exerciseKey key: String, pattern: String) -> FigureKind {
        if key.contains("push_up") { return .pushUp }
        if key.contains("dip") { return .dip }
        if key.contains("pull_up") || key.contains("chin_up") { return .pullUp }
        if key.contains("pulldown") { return .pulldown }
        if key.contains("lunge") || key.contains("split_squat") || key.contains("step_up") { return .lunge }
        if key.contains("hip_thrust") { return .hipThrust }
        if key.contains("plank") || key.contains("hollow") || key.contains("pallof") { return .plank }
        if key.contains("hanging") { return .hangingLegRaise }
        if key.contains("dead_bug") || key.contains("bird_dog") { return .deadBug }
        switch pattern {
        case "horizontal_press": return .benchPress
        case "incline_press": return .inclinePress
        case "vertical_press": return .overheadPress
        case "chest_fly": return .fly
        case "lateral_raise": return .lateralRaise
        case "triceps_extension": return .tricepsExtension
        case "vertical_pull": return .pulldown
        case "horizontal_row": return .row
        case "rear_delt": return .rearDelt
        case "elbow_flexion": return .curl
        case "squat": return .squat
        case "hinge": return .hinge
        case "quad_isolation": return .legExtension
        case "hamstring_isolation": return .legCurl
        case "calf": return .calf
        default: return .crunch
        }
    }
}

struct FigureShape: Shape {
    let kind: FigureKind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        draw(&p)
        let s = min(rect.width / 100, rect.height / 60)
        let dx = rect.midX - 50 * s, dy = rect.midY - 30 * s
        return p.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: dx, ty: dy))
    }

    // MARK: Primitives (unit space: x 0…100, y 0…60, y grows downward)

    private func head(_ p: inout Path, _ x: CGFloat, _ y: CGFloat, r: CGFloat = 4) {
        p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private func line(_ p: inout Path, _ pts: [(CGFloat, CGFloat)]) {
        guard let f = pts.first else { return }
        p.move(to: CGPoint(x: f.0, y: f.1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
    }

    /// Barbell: bar with a plate at each end.
    private func bar(_ p: inout Path, from a: (CGFloat, CGFloat), to b: (CGFloat, CGFloat), plate: CGFloat = 5) {
        line(&p, [a, b])
        let horizontal = abs(a.1 - b.1) < 0.01
        for e in [a, b] {
            if horizontal { line(&p, [(e.0, e.1 - plate), (e.0, e.1 + plate)]) } else { line(&p, [(e.0 - plate, e.1), (e.0 + plate, e.1)]) }
        }
    }

    private func dumbbell(_ p: inout Path, at c: (CGFloat, CGFloat), vertical: Bool = false) {
        if vertical {
            line(&p, [(c.0, c.1 - 4), (c.0, c.1 + 4)]); line(&p, [(c.0 - 3, c.1 - 4), (c.0 + 3, c.1 - 4)]); line(&p, [(c.0 - 3, c.1 + 4), (c.0 + 3, c.1 + 4)])
        } else {
            line(&p, [(c.0 - 4, c.1), (c.0 + 4, c.1)]); line(&p, [(c.0 - 4, c.1 - 3), (c.0 - 4, c.1 + 3)]); line(&p, [(c.0 + 4, c.1 - 3), (c.0 + 4, c.1 + 3)])
        }
    }

    private func floor(_ p: inout Path) { line(&p, [(8, 56), (92, 56)]) }
    private func bench(_ p: inout Path) { line(&p, [(28, 42), (76, 42)]); line(&p, [(34, 42), (34, 56)]); line(&p, [(70, 42), (70, 56)]) }

    // MARK: Figures

    private func draw(_ p: inout Path) {
        switch kind {
        case .benchPress:
            bench(&p); floor(&p)
            head(&p, 32, 36)                                        // lying, head left
            line(&p, [(36, 38), (62, 38)])                           // torso on bench
            line(&p, [(62, 38), (72, 46), (72, 56)])                 // leg down
            line(&p, [(62, 38), (80, 44), (82, 56)])
            line(&p, [(46, 38), (46, 18)])                           // arms straight up
            line(&p, [(50, 38), (50, 18)])
            bar(&p, from: (30, 18), to: (66, 18))
        case .inclinePress:
            floor(&p); line(&p, [(30, 56), (30, 44), (56, 30)]); line(&p, [(56, 30), (56, 56)])   // incline bench
            head(&p, 36, 32)
            line(&p, [(40, 36), (58, 42)]); line(&p, [(58, 42), (72, 48), (74, 56)]); line(&p, [(58, 42), (64, 56)])
            line(&p, [(47, 38), (54, 20)]); line(&p, [(51, 40), (58, 22)])
            bar(&p, from: (40, 16), to: (72, 24))
        case .overheadPress:
            floor(&p)
            head(&p, 50, 22)
            line(&p, [(50, 26), (50, 42)]); line(&p, [(50, 42), (44, 56)]); line(&p, [(50, 42), (56, 56)])
            line(&p, [(50, 30), (40, 20), (40, 10)]); line(&p, [(50, 30), (60, 20), (60, 10)])
            bar(&p, from: (30, 10), to: (70, 10))
        case .fly:
            bench(&p); floor(&p)
            head(&p, 32, 36); line(&p, [(36, 38), (62, 38)]); line(&p, [(62, 38), (72, 46), (72, 56)]); line(&p, [(62, 38), (80, 44), (82, 56)])
            line(&p, [(48, 38), (36, 24), (30, 14)]); line(&p, [(48, 38), (60, 24), (66, 14)])
            dumbbell(&p, at: (30, 12)); dumbbell(&p, at: (66, 12))
        case .lateralRaise:
            floor(&p)
            head(&p, 50, 14); line(&p, [(50, 18), (50, 38)]); line(&p, [(50, 38), (44, 56)]); line(&p, [(50, 38), (56, 56)])
            line(&p, [(50, 22), (30, 20)]); line(&p, [(50, 22), (70, 20)])
            dumbbell(&p, at: (26, 20), vertical: true); dumbbell(&p, at: (74, 20), vertical: true)
        case .tricepsExtension:
            floor(&p)
            head(&p, 50, 16); line(&p, [(50, 20), (50, 40)]); line(&p, [(50, 40), (44, 56)]); line(&p, [(50, 40), (56, 56)])
            line(&p, [(50, 24), (58, 14), (54, 4)]); line(&p, [(50, 24), (56, 12), (52, 4)])
            dumbbell(&p, at: (52, 3))
        case .pushUp:
            floor(&p)
            head(&p, 24, 36); line(&p, [(28, 38), (80, 50)]); line(&p, [(80, 50), (90, 56)])
            line(&p, [(36, 40), (34, 56)]); line(&p, [(40, 41), (38, 56)])
        case .dip:
            line(&p, [(26, 24), (26, 56)]); line(&p, [(74, 24), (74, 56)]); line(&p, [(18, 24), (34, 24)]); line(&p, [(66, 24), (82, 24)])
            head(&p, 50, 16); line(&p, [(50, 20), (50, 38)]); line(&p, [(50, 38), (46, 48), (50, 56)]); line(&p, [(50, 38), (54, 48), (56, 56)])
            line(&p, [(50, 24), (38, 30), (30, 24)]); line(&p, [(50, 24), (62, 30), (70, 24)])
        case .pullUp:
            bar(&p, from: (24, 8), to: (76, 8), plate: 0); line(&p, [(24, 8), (24, 16)]); line(&p, [(76, 8), (76, 16)])
            head(&p, 50, 16); line(&p, [(50, 20), (50, 40)]); line(&p, [(50, 40), (46, 56)]); line(&p, [(50, 40), (54, 52)])
            line(&p, [(50, 24), (38, 16), (38, 8)]); line(&p, [(50, 24), (62, 16), (62, 8)])
        case .pulldown:
            line(&p, [(34, 4), (66, 4)]); line(&p, [(42, 4), (46, 14)]); line(&p, [(58, 4), (54, 14)])
            head(&p, 50, 20); line(&p, [(50, 24), (50, 42)]); line(&p, [(50, 42), (36, 44), (36, 56)]); line(&p, [(50, 42), (62, 44), (62, 56)])
            line(&p, [(50, 28), (40, 20), (38, 10)]); line(&p, [(50, 28), (60, 20), (62, 10)])
            line(&p, [(30, 10), (70, 10)])
        case .row:
            floor(&p)
            head(&p, 76, 26); line(&p, [(72, 28), (44, 36)]); line(&p, [(44, 36), (40, 56)]); line(&p, [(44, 36), (50, 56)])
            line(&p, [(62, 31), (62, 44)]); line(&p, [(66, 30), (66, 44)])
            bar(&p, from: (50, 46), to: (80, 46), plate: 4)
        case .rearDelt:
            floor(&p)
            head(&p, 76, 24); line(&p, [(72, 26), (44, 34)]); line(&p, [(44, 34), (40, 56)]); line(&p, [(44, 34), (50, 56)])
            line(&p, [(62, 30), (56, 44)]); line(&p, [(62, 30), (70, 44)])
            dumbbell(&p, at: (54, 46)); dumbbell(&p, at: (72, 46))
        case .curl:
            floor(&p)
            head(&p, 50, 14); line(&p, [(50, 18), (50, 40)]); line(&p, [(50, 40), (44, 56)]); line(&p, [(50, 40), (56, 56)])
            line(&p, [(50, 22), (42, 34), (40, 24)]); line(&p, [(50, 22), (58, 34), (60, 24)])
            bar(&p, from: (34, 24), to: (66, 24), plate: 3)
        case .squat:
            floor(&p)
            head(&p, 46, 14); line(&p, [(48, 18), (50, 34)]); line(&p, [(50, 34), (66, 36), (62, 56)]); line(&p, [(50, 34), (64, 38), (58, 56)])
            line(&p, [(49, 22), (40, 22)]); line(&p, [(49, 22), (58, 22)])
            bar(&p, from: (30, 20), to: (70, 20))
        case .hinge:
            floor(&p)
            head(&p, 70, 20); line(&p, [(66, 22), (44, 30)]); line(&p, [(44, 30), (42, 56)]); line(&p, [(44, 30), (48, 56)])
            line(&p, [(60, 25), (62, 46)]); line(&p, [(64, 24), (66, 46)])
            bar(&p, from: (48, 48), to: (80, 48), plate: 7)
        case .legExtension:
            floor(&p)
            line(&p, [(36, 36), (36, 56)]); line(&p, [(30, 36), (54, 36)])                       // seat
            head(&p, 40, 12); line(&p, [(40, 16), (40, 36)]); line(&p, [(40, 36), (56, 36), (74, 32)])  // thigh + extended shin
            line(&p, [(40, 20), (34, 30)])
            dumbbell(&p, at: (76, 32), vertical: true)
        case .legCurl:
            bench(&p); floor(&p)
            head(&p, 30, 36); line(&p, [(34, 38), (62, 38)]); line(&p, [(62, 38), (78, 40)]); line(&p, [(78, 40), (76, 24)])  // heel curled up
            line(&p, [(40, 38), (36, 44)])
            dumbbell(&p, at: (76, 22))
        case .calf:
            floor(&p)
            head(&p, 50, 12); line(&p, [(50, 16), (50, 36)]); line(&p, [(50, 36), (46, 50), (46, 54)]); line(&p, [(50, 36), (54, 50), (54, 54)])
            line(&p, [(42, 50), (46, 54)]); line(&p, [(50, 50), (54, 54)])                             // on toes
            line(&p, [(50, 20), (40, 26)]); line(&p, [(50, 20), (60, 26)])
            line(&p, [(50, 8), (80, 8)]); line(&p, [(80, 8), (80, 56)])                                   // support
        case .lunge:
            floor(&p)
            head(&p, 46, 12); line(&p, [(46, 16), (46, 36)]); line(&p, [(46, 36), (60, 40), (60, 56)]); line(&p, [(46, 36), (36, 48), (28, 56)])
            line(&p, [(46, 20), (40, 34)]); line(&p, [(46, 20), (52, 34)])
            dumbbell(&p, at: (40, 36), vertical: true); dumbbell(&p, at: (52, 36), vertical: true)
        case .hipThrust:
            floor(&p); line(&p, [(20, 36), (20, 56)]); line(&p, [(20, 36), (36, 36)])
            head(&p, 24, 30); line(&p, [(28, 32), (56, 30)]); line(&p, [(56, 30), (66, 42), (68, 56)]); line(&p, [(56, 30), (60, 44), (62, 56)])
            bar(&p, from: (50, 22), to: (62, 22), plate: 0); line(&p, [(56, 22), (56, 30)])
        case .plank:
            floor(&p)
            head(&p, 22, 32); line(&p, [(26, 34), (80, 44)]); line(&p, [(80, 44), (90, 56)])
            line(&p, [(34, 36), (30, 56)]); line(&p, [(30, 56), (22, 56)])
        case .hangingLegRaise:
            line(&p, [(30, 6), (70, 6)])
            head(&p, 50, 14); line(&p, [(50, 18), (50, 38)]); line(&p, [(50, 22), (40, 14), (40, 6)]); line(&p, [(50, 22), (60, 14), (60, 6)])
            line(&p, [(50, 38), (68, 34)]); line(&p, [(50, 38), (68, 40)])                                // legs raised forward
        case .crunch:
            floor(&p)
            head(&p, 32, 34); line(&p, [(36, 36), (60, 44)]); line(&p, [(60, 44), (68, 32), (78, 44)]); line(&p, [(78, 44), (80, 56)])
            line(&p, [(42, 38), (34, 30)])
        case .deadBug:
            floor(&p)
            head(&p, 24, 46); line(&p, [(28, 48), (62, 48)]); line(&p, [(44, 48), (42, 26)]); line(&p, [(62, 48), (64, 30), (80, 30)]); line(&p, [(62, 48), (74, 40)])
        }
    }
}
