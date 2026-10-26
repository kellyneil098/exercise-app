import SwiftUI

// Original SwiftUI-drawn storybook props: honey pot, bee, balloon, cloud, drips, footprints.
// Animated ones use TimelineView + Canvas and stand still under Reduce Motion.

// MARK: - Honey pot

/// Classic belly pot with a "HUNNY" label. `fill` (0…1) raises a honey level inside; `drip` adds a run down the side.
public struct HoneyPot: View {
    let fill: Double
    let drip: Bool
    let label: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(fill: Double = 0.65, drip: Bool = true, label: String? = "HUNNY") {
        self.fill = fill; self.drip = drip; self.label = label
    }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                HoneyPot.draw(in: &g, size: size, fill: fill, drip: drip, label: label,
                              time: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    public static func draw(in g: inout GraphicsContext, size: CGSize, fill: Double, drip: Bool, label: String?, time: TimeInterval) {
        let s = min(size.width, size.height)
        let ox = (size.width - s) / 2, oy = (size.height - s) / 2
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        let ink = Theme.Colors.ink
        let lw = max(1.2, s * 0.028)

        // Body
        var body = Path()
        body.move(to: P(0.30, 0.26))
        body.addCurve(to: P(0.30, 0.92), control1: P(-0.02, 0.36), control2: P(0.02, 0.92))
        body.addLine(to: P(0.70, 0.92))
        body.addCurve(to: P(0.70, 0.26), control1: P(0.98, 0.92), control2: P(1.02, 0.36))
        body.closeSubpath()
        g.fill(body, with: .color(Theme.Colors.paper))

        // Honey level (clipped to body)
        if fill > 0 {
            var clipped = g
            clipped.clip(to: body)
            let level = 0.90 - 0.60 * min(1, max(0, fill))
            var honey = Path()
            let waveA = s * 0.012, k = 2 * CGFloat.pi / (s * 0.5)
            honey.move(to: P(0, 1))
            honey.addLine(to: CGPoint(x: ox, y: oy + level * s))
            var x: CGFloat = 0
            while x <= s {
                let y = oy + level * s + sin(x * k + CGFloat(time) * 2.2) * waveA
                honey.addLine(to: CGPoint(x: ox + x, y: y)); x += 2
            }
            honey.addLine(to: P(1, 1)); honey.closeSubpath()
            clipped.fill(honey, with: .color(Theme.Colors.honey))
            var gloss = Path()
            gloss.addEllipse(in: CGRect(x: ox + s * 0.22, y: oy + (level + 0.06) * s, width: s * 0.16, height: s * 0.06))
            clipped.fill(gloss, with: .color(Theme.Colors.honeyLight.opacity(0.8)))
        }
        g.stroke(body, with: .color(ink), style: StrokeStyle(lineWidth: lw, lineJoin: .round))

        // Rim
        let rim = Path(roundedRect: CGRect(x: ox + 0.22 * s, y: oy + 0.16 * s, width: 0.56 * s, height: 0.13 * s), cornerRadius: s * 0.04)
        g.fill(rim, with: .color(Theme.Colors.aged))
        g.stroke(rim, with: .color(ink), lineWidth: lw)
        var rimHoney = Path()
        rimHoney.move(to: P(0.26, 0.20)); rimHoney.addQuadCurve(to: P(0.74, 0.20), control: P(0.50, 0.30))
        rimHoney.addLine(to: P(0.74, 0.22)); rimHoney.addQuadCurve(to: P(0.26, 0.22), control: P(0.50, 0.32)); rimHoney.closeSubpath()
        g.fill(rimHoney, with: .color(Theme.Colors.honey.opacity(0.9)))

        // Drip over the rim
        if drip {
            var d = Path()
            d.move(to: P(0.62, 0.29))
            d.addCurve(to: P(0.66, 0.46), control1: P(0.60, 0.36), control2: P(0.60, 0.42))
            d.addCurve(to: P(0.70, 0.29), control1: P(0.72, 0.50), control2: P(0.72, 0.36))
            d.closeSubpath()
            g.fill(d, with: .color(Theme.Colors.honey))
            g.stroke(d, with: .color(ink.opacity(0.9)), lineWidth: lw * 0.7)
        }

        // Label
        if let label {
            let tag = Path(roundedRect: CGRect(x: ox + 0.27 * s, y: oy + 0.50 * s, width: 0.46 * s, height: 0.20 * s), cornerRadius: s * 0.03)
            g.fill(tag, with: .color(Theme.Colors.paper))
            g.stroke(tag, with: .color(ink), style: StrokeStyle(lineWidth: lw * 0.7, dash: [s * 0.02, s * 0.02]))
            let text = Text(label).font(.system(size: s * 0.11, weight: .heavy, design: .serif)).foregroundColor(ink)
            g.draw(text, at: P(0.5, 0.60), anchor: .center)
        }
    }
}

// MARK: - Bee

/// Round little bee: striped body, two translucent wings that flutter, dotted flight path optional.
public struct Bee: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(size: CGFloat = 28) { self.size = size }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, sz in
                Bee.draw(in: &g, at: CGPoint(x: sz.width / 2, y: sz.height / 2), size: size,
                         time: reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size * 1.4, height: size * 1.2)
        .accessibilityHidden(true)
    }

    public static func draw(in g: inout GraphicsContext, at c: CGPoint, size s: CGFloat, time: TimeInterval, heading: CGFloat = 0) {
        var g = g
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(heading))
        let ink = Theme.Colors.ink
        let lw = max(1, s * 0.07)
        let flutter = CGFloat(sin(time * 28)) * 0.35
        // Wings
        for side in [-1.0, 1.0] {
            var w = Path()
            w.addEllipse(in: CGRect(x: -s * 0.16 + CGFloat(side) * s * 0.02, y: -s * 0.62, width: s * 0.34, height: s * 0.44))
            var wg = g
            wg.translateBy(x: CGFloat(side) * s * 0.12, y: 0)
            wg.rotate(by: .radians(Double(CGFloat(side) * (0.5 + flutter))))
            wg.fill(w, with: .color(Theme.Colors.sky.opacity(0.45)))
            wg.stroke(w, with: .color(ink.opacity(0.7)), lineWidth: lw * 0.6)
        }
        // Body
        let body = Path(ellipseIn: CGRect(x: -s * 0.5, y: -s * 0.3, width: s, height: s * 0.6))
        g.fill(body, with: .color(Theme.Colors.honey))
        var stripes = g
        stripes.clip(to: body)
        for i in 0..<3 {
            let x = -s * 0.28 + CGFloat(i) * s * 0.22
            stripes.fill(Path(CGRect(x: x, y: -s * 0.4, width: s * 0.1, height: s * 0.8)), with: .color(ink))
        }
        g.stroke(body, with: .color(ink), lineWidth: lw)
        // Head + eye + stinger
        let head = Path(ellipseIn: CGRect(x: -s * 0.66, y: -s * 0.22, width: s * 0.36, height: s * 0.44))
        g.fill(head, with: .color(ink))
        g.fill(Path(ellipseIn: CGRect(x: -s * 0.56, y: -s * 0.12, width: s * 0.08, height: s * 0.08)), with: .color(Theme.Colors.paper))
        var sting = Path()
        sting.move(to: CGPoint(x: s * 0.48, y: -s * 0.06)); sting.addLine(to: CGPoint(x: s * 0.68, y: 0)); sting.addLine(to: CGPoint(x: s * 0.48, y: s * 0.06))
        g.fill(sting, with: .color(ink))
        // Antennae
        var ant = Path()
        ant.move(to: CGPoint(x: -s * 0.55, y: -s * 0.2)); ant.addQuadCurve(to: CGPoint(x: -s * 0.72, y: -s * 0.45), control: CGPoint(x: -s * 0.58, y: -s * 0.4))
        g.stroke(ant, with: .color(ink), lineWidth: lw * 0.6)
    }
}

/// A handful of bees drifting around a loose figure-eight, for rest cards and headers.
public struct BeeSwarm: View {
    let count: Int
    let beeSize: CGFloat
    let speed: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(count: Int = 3, beeSize: CGFloat = 16, speed: Double = 1) { self.count = count; self.beeSize = beeSize; self.speed = speed }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate * speed
                let w = size.width, h = size.height
                for i in 0..<count {
                    let phase = t * 0.5 + Double(i) * (2 * .pi / Double(count))
                    let x = w / 2 + CGFloat(sin(phase)) * w * 0.42
                    let y = h / 2 + CGFloat(sin(phase * 2)) * h * 0.36
                    let dx = cos(phase), dy = 2 * cos(phase * 2) * Double(h / w)
                    let heading = CGFloat(atan2(dy, dx)) + (dx < 0 ? .pi : 0)
                    var gg = g
                    if dx < 0 { gg.translateBy(x: x, y: y); gg.scaleBy(x: -1, y: 1); gg.translateBy(x: -x, y: -y) }
                    Bee.draw(in: &gg, at: CGPoint(x: x, y: y), size: beeSize, time: t + Double(i), heading: dx < 0 ? -heading : heading)
                    // dotted trail
                    var trail = Path()
                    for k in 1...5 {
                        let p2 = phase - Double(k) * 0.12
                        let tx = w / 2 + CGFloat(sin(p2)) * w * 0.42, ty = h / 2 + CGFloat(sin(p2 * 2)) * h * 0.36
                        trail.addEllipse(in: CGRect(x: tx - 1, y: ty - 1, width: 2, height: 2))
                    }
                    g.fill(trail, with: .color(Theme.Colors.ink.opacity(0.35)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Balloon

/// Red balloon on a wobbly string that bobs ±4 pt over 3 s.
public struct Balloon: View {
    let width: CGFloat
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    public init(width: CGFloat = 40, color: Color = Theme.Colors.balloon) { self.width = width; self.color = color }
    public var body: some View {
        BalloonShape(color: color).frame(width: width, height: width * 2.4)
            .offset(y: up ? -4 : 4)
            .rotationEffect(.degrees(up ? -2 : 2), anchor: .bottom)
            .onAppear { if !reduceMotion { withAnimation(Theme.Motion.bob) { up = true } } }
            .accessibilityHidden(true)
    }
}

public struct BalloonShape: View {
    let color: Color
    public init(color: Color = Theme.Colors.balloon) { self.color = color }
    public var body: some View {
        Canvas { g, size in
            let w = size.width
            let ink = Theme.Colors.ink
            var b = Path()
            b.addEllipse(in: CGRect(x: 0, y: 0, width: w, height: w * 1.18))
            g.fill(b, with: .radialGradient(Gradient(colors: [color.opacity(0.85), color]), center: CGPoint(x: w * 0.38, y: w * 0.35), startRadius: 0, endRadius: w * 0.7))
            g.stroke(b, with: .color(ink), lineWidth: max(1, w * 0.035))
            // highlight
            var hl = Path(); hl.addEllipse(in: CGRect(x: w * 0.22, y: w * 0.18, width: w * 0.16, height: w * 0.26))
            g.fill(hl, with: .color(.white.opacity(0.55)))
            // knot
            var k = Path()
            k.move(to: CGPoint(x: w * 0.44, y: w * 1.17)); k.addLine(to: CGPoint(x: w * 0.56, y: w * 1.17)); k.addLine(to: CGPoint(x: w * 0.5, y: w * 1.28)); k.closeSubpath()
            g.fill(k, with: .color(color)); g.stroke(k, with: .color(ink), lineWidth: max(1, w * 0.03))
            // string
            var s = Path()
            s.move(to: CGPoint(x: w * 0.5, y: w * 1.28))
            s.addCurve(to: CGPoint(x: w * 0.5, y: size.height), control1: CGPoint(x: w * 0.75, y: w * 1.6), control2: CGPoint(x: w * 0.25, y: w * 2.0))
            g.stroke(s, with: .color(ink), lineWidth: max(0.8, w * 0.025))
        }
    }
}

// MARK: - Cloud

/// Puffy outlined cloud. Drifts across its container when `drift` is set.
public struct Cloud: View {
    let width: CGFloat
    let drift: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var across = false
    public init(width: CGFloat = 60, drift: Double? = nil) { self.width = width; self.drift = drift }
    public var body: some View {
        // Stroke first, then fill over it: the fill hides the inner half of every ellipse's outline, leaving one
        // clean silhouette.
        ZStack {
            CloudShape().stroke(Theme.Colors.ink.opacity(0.75), lineWidth: 2.4)
            CloudShape().fill(Theme.Colors.paper)
        }
        .frame(width: width, height: width * 0.55)
            .offset(x: (drift != nil && across) ? 24 : (drift != nil ? -24 : 0))
            .onAppear {
                if let drift, !reduceMotion { withAnimation(.easeInOut(duration: drift).repeatForever(autoreverses: true)) { across = true } }
            }
            .accessibilityHidden(true)
    }
}

public struct CloudShape: Shape {
    public init() {}
    public func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.addEllipse(in: CGRect(x: r.minX, y: r.minY + h * 0.4, width: w * 0.45, height: h * 0.6))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.2, y: r.minY, width: w * 0.5, height: h * 0.85))
        p.addEllipse(in: CGRect(x: r.minX + w * 0.5, y: r.minY + h * 0.25, width: w * 0.5, height: h * 0.75))
        p.addRect(CGRect(x: r.minX + w * 0.2, y: r.minY + h * 0.55, width: w * 0.6, height: h * 0.45))
        return p
    }
}

// MARK: - Honey drips

/// A run of honey drips hanging from the top edge of a frame (card headers, finish banner).
public struct HoneyDrips: Shape {
    public var drips: Int
    public init(drips: Int = 5) { self.drips = drips }
    public func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width / CGFloat(drips)
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        for i in 0..<drips {
            let x0 = r.minX + CGFloat(i) * w
            let depth = r.height * (i % 2 == 0 ? 0.95 : 0.55) * (i % 3 == 0 ? 1 : 0.8)
            let mid = x0 + w / 2
            p.addCurve(to: CGPoint(x: mid, y: r.minY + depth), control1: CGPoint(x: x0 + w * 0.1, y: r.minY + depth * 0.1), control2: CGPoint(x: mid - w * 0.3, y: r.minY + depth))
            p.addCurve(to: CGPoint(x: x0 + w, y: r.minY), control1: CGPoint(x: mid + w * 0.3, y: r.minY + depth), control2: CGPoint(x: x0 + w * 0.9, y: r.minY + depth * 0.1))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY - 2)); p.addLine(to: CGPoint(x: r.minX, y: r.minY - 2)); p.closeSubpath()
        return p
    }
}

// MARK: - Footprints

/// A trail of little bear paw prints along a gentle S curve. `progress` (0…1) reveals the prints in order.
public struct Footprints: View {
    let count: Int
    let progress: Double
    let tint: Color
    public init(count: Int = 8, progress: Double = 1, tint: Color = Theme.Colors.ink) { self.count = count; self.progress = progress; self.tint = tint }
    public var body: some View {
        Canvas { g, size in
            let shown = Int((Double(count) * progress).rounded(.up))
            for i in 0..<min(shown, count) {
                let t = CGFloat(i) / CGFloat(max(count - 1, 1))
                let x = size.width * (0.06 + 0.88 * t)
                let y = size.height / 2 + sin(t * .pi * 2) * size.height * 0.28 + (i % 2 == 0 ? -size.height * 0.12 : size.height * 0.12)
                let tangent = cos(t * .pi * 2) * size.height * 0.28 * .pi * 2 / size.width
                Footprints.paw(in: &g, at: CGPoint(x: x, y: y), size: min(size.height * 0.34, 14), angle: atan(tangent) + .pi / 2, tint: tint.opacity(0.75))
            }
        }
        .accessibilityHidden(true)
    }
    static func paw(in g: inout GraphicsContext, at c: CGPoint, size s: CGFloat, angle: CGFloat, tint: Color) {
        var g = g
        g.translateBy(x: c.x, y: c.y); g.rotate(by: .radians(Double(angle)))
        var p = Path()
        p.addEllipse(in: CGRect(x: -s * 0.32, y: -s * 0.1, width: s * 0.64, height: s * 0.55))
        for (dx, dy) in [(-0.34, -0.42), (-0.12, -0.55), (0.12, -0.55), (0.34, -0.42)] {
            p.addEllipse(in: CGRect(x: CGFloat(dx) * s - s * 0.1, y: CGFloat(dy) * s - s * 0.1, width: s * 0.2, height: s * 0.2))
        }
        g.fill(p, with: .color(tint))
    }
}

// MARK: - Confetti

/// Bees and honey drops bursting out from the centre once, for the finish screen.
public struct HoneyBurst: View {
    let pieces: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    public init(pieces: Int = 22) { self.pieces = pieces }
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            Canvas { g, size in
                let elapsed = reduceMotion ? 1.2 : min(ctx.date.timeIntervalSince(start), 2.4)
                let c = CGPoint(x: size.width / 2, y: size.height * 0.45)
                for i in 0..<pieces {
                    let seed = Double(i) * 1.618
                    let angle = seed.truncatingRemainder(dividingBy: 1) * 2 * .pi
                    let speed = 120 + (seed * 7).truncatingRemainder(dividingBy: 1) * 160
                    let t = elapsed
                    let dx: Double = cos(angle) * speed * t
                    let dy: Double = sin(angle) * speed * t * 0.7 + 90 * t * t
                    let x = c.x + CGFloat(dx)
                    let y = c.y + CGFloat(dy)
                    let fade = max(0, 1 - t / 2.2)
                    var gg = g
                    gg.opacity = fade
                    if i % 4 == 0 {
                        Bee.draw(in: &gg, at: CGPoint(x: x, y: y), size: 14, time: elapsed, heading: 0)
                    } else {
                        let d = HoneyBurst.drop(at: CGPoint(x: x, y: y), r: 5)
                        gg.fill(d, with: .color(i % 3 == 0 ? Theme.Colors.honeyDeep : Theme.Colors.honey))
                        gg.stroke(d, with: .color(Theme.Colors.ink.opacity(0.6)), lineWidth: 0.8)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    static func drop(at c: CGPoint, r: CGFloat) -> Path {
        var d = Path()
        let top = CGPoint(x: c.x, y: c.y - r * 1.6)
        let bottom = CGPoint(x: c.x, y: c.y + r)
        d.move(to: top)
        d.addCurve(to: bottom, control1: CGPoint(x: c.x + r * 1.2, y: c.y - r * 0.2), control2: CGPoint(x: c.x + r * 1.3, y: c.y + r))
        d.addCurve(to: top, control1: CGPoint(x: c.x - r * 1.3, y: c.y + r), control2: CGPoint(x: c.x - r * 1.2, y: c.y - r * 0.2))
        return d
    }
}

// MARK: - Stamp

/// Rubber-stamp box: serif black italic text in a thick rounded outline, slightly rotated.
public struct Stamp: View {
    let text: String
    let color: Color
    let rotation: Double
    public init(_ text: String, color: Color, rotation: Double = -8) { self.text = text; self.color = color; self.rotation = rotation }
    public var body: some View {
        Text(text).font(Theme.Fonts.stamp).tracking(1).foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.m).padding(.vertical, Theme.Spacing.s)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color, lineWidth: 3.5))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: 1).padding(4))
            .background(Theme.Colors.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .rotationEffect(.degrees(rotation))
            .fixedSize()
    }
}
