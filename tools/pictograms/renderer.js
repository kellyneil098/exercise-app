// Canvas port of FigureRenderer / Skeleton in ios/WorkoutApp/Sources/ExerciseArt.swift. Keep in sync.
(function (global) {
  const FLOOR = 56, TORSO = 15, NECK = 6.6, UA = 8, FA = 8, TH = 10, SH = 10;
  const HEAD_R = 5.4, TORSO_W = 5.0, LIMB_W = 3.4, OUTLINE = 1.4;
  const PLATE_R = { barbell: 5, barbellOnHips: 5, trapBar: 5, barbellNarrow: 3.6, shortBar: 3 };
  const rad = d => d * Math.PI / 180;
  const seg = (p, deg, len) => [p[0] + len * Math.cos(rad(deg)), p[1] + len * Math.sin(rad(deg))];
  const off = (p, dx, dy) => [p[0] + dx, p[1] + dy];
  const frontNormal = deg => [-Math.sin(rad(deg)), Math.cos(rad(deg))];
  const lerp = (a, b, t) => (a == null ? b : b == null ? a : a + (b - a) * t);

  function lerpPose(a, b, t) {
    const ha = a.head ?? a.torso, hb = b.head ?? b.torso;
    return { hx: lerp(a.hx, b.hx, t), hy: lerp(a.hy, b.hy, t), torso: lerp(a.torso, b.torso, t), head: lerp(ha, hb, t),
      ua: lerp(a.ua, b.ua, t), fa: lerp(a.fa, b.fa, t), th: lerp(a.th, b.th, t), sh: lerp(a.sh, b.sh, t),
      ua2: lerp(a.ua2, b.ua2, t), fa2: lerp(a.fa2, b.fa2, t), th2: lerp(a.th2, b.th2, t), sh2: lerp(a.sh2, b.sh2, t),
      impl: a.impl, props: a.props, grounded: a.grounded, floor: a.floor };
  }

  class Skeleton {
    constructor(p) {
      this.pose = p;
      this.hip = [p.hx, p.hy];
      this.shoulder = seg(this.hip, p.torso, TORSO);
      this.headAngle = p.head ?? p.torso;
      this.head = seg(this.shoulder, this.headAngle, NECK);
      const e = seg(this.shoulder, p.ua, UA);
      this.arms = [[e, seg(e, p.fa, FA)]];
      if (p.ua2 != null && p.fa2 != null) { const e2 = seg(this.shoulder, p.ua2, UA); this.arms.push([e2, seg(e2, p.fa2, FA)]); }
      const k = seg(this.hip, p.th, TH);
      this.legs = [{ knee: k, foot: seg(k, p.sh, SH), shin: p.sh }];
      if (p.th2 != null && p.sh2 != null) { const k2 = seg(this.hip, p.th2, TH); this.legs.push({ knee: k2, foot: seg(k2, p.sh2, SH), shin: p.sh2 }); }
      if (p.grounded) this.shift(0, FLOOR - Math.max(...this.legs.map(l => l.foot[1])));
    }
    shift(dx, dy) {
      const mv = q => [q[0] + dx, q[1] + dy];
      this.hip = mv(this.hip); this.shoulder = mv(this.shoulder); this.head = mv(this.head);
      this.arms = this.arms.map(a => [mv(a[0]), mv(a[1])]);
      this.legs = this.legs.map(l => ({ knee: mv(l.knee), foot: mv(l.foot), shin: l.shin }));
    }
    anchorPoint(mode) {
      if (mode === 'foot') return this.legs[0].foot;
      if (mode === 'foot2') return this.legs[this.legs.length - 1].foot;
      if (mode === 'hand') return this.arms[0][1];
      if (mode === 'shoulder') return this.shoulder;
      return this.hip;
    }
    anchorTo(ref, mode) {
      const a = this.anchorPoint(mode), b = ref.anchorPoint(mode);
      const dy = (this.pose.grounded && (mode === 'foot' || mode === 'foot2')) ? 0 : b[1] - a[1];
      this.shift(b[0] - a[0], dy);
    }
    get hand() { return this.arms[0][1]; }
    get farHand() { return this.arms[this.arms.length - 1][1]; }
    static footFlat(leg) { return Math.abs(Math.cos(rad(leg.shin))) < 0.5; }
    // Toe mark length: full when the shin is near vertical, shrinking smoothly to nothing as the foot points away.
    static toeLength(leg) { const c = Math.abs(Math.cos(rad(leg.shin))); return 5 * Math.max(0, Math.min(1, (0.62 - c) / 0.25)); }
  }

  class Figure {
    constructor(m) {
      this.m = m;
      this.anchor = m.anchor;
      this.a = new Skeleton(m.a);
      this.b = new Skeleton(m.b); this.b.anchorTo(this.a, this.anchor);
      this.frame = this.computeFrame();
    }
    at(t) {
      const sk = new Skeleton(lerpPose(this.m.a, this.m.b, t));
      sk.anchorTo(this.a, this.anchor);
      if (this.m.armsXY) {
        const s = sk.shoulder;
        sk.arms = sk.arms.map((_, i) => {
          const pa = this.a.arms[Math.min(i, this.a.arms.length - 1)], pb = this.b.arms[Math.min(i, this.b.arms.length - 1)];
          return [0, 1].map(j => {
            const ra = [pa[j][0] - this.a.shoulder[0], pa[j][1] - this.a.shoulder[1]], rb = [pb[j][0] - this.b.shoulder[0], pb[j][1] - this.b.shoulder[1]];
            return [s[0] + lerp(ra[0], rb[0], t), s[1] + lerp(ra[1], rb[1], t)];
          });
        });
      }
      return sk;
    }
    // Props are built from the anchored first keyframe (fixed gear) plus the live skeleton (cables, pads, belts).
    props(live) {
      const fixed = this.a, p = this.m.a, out = [];
      const hip = fixed.hip, shoulder = fixed.shoulder, hand = fixed.hand, hand2 = fixed.farHand, knee = fixed.legs[0].knee, foot = fixed.legs[0].foot;
      const L = (a, b) => out.push(['line', a, b]);
      const LXY = (ax, ay, bx, by) => out.push(['line', [ax, ay], [bx, by]]);
      const legs = (a, b) => { L(a, b); L(a, [a[0], FLOOR]); L(b, [b[0], FLOOR]); };
      const pad = (c, deg) => { // pad perpendicular to `deg`
        const u = [Math.cos(rad(deg)), Math.sin(rad(deg))], v = [-u[1], u[0]];
        const P = (s, w) => [c[0] + u[0] * s + v[0] * w, c[1] + u[1] * s + v[1] * w];
        out.push(['line', P(0, -3.5), P(0, 3.5)]);
        for (const w of [-3.5, 3.5]) out.push(['plate', P(-2.5, w), P(2.5, w)]);
      };
      const lh = live.hand, lhip = live.hip, lsh = live.shoulder, lknee = live.legs[0].knee, lfoot = live.legs[0].foot;
      for (const prop of p.props) {
        switch (prop) {
          case 'bench': { const y = shoulder[1] + 2.5; LXY(shoulder[0] - 10, y, hip[0] + 4, y); LXY(shoulder[0] - 6, y, shoulder[0] - 6, FLOOR); LXY(hip[0], y, hip[0], FLOOR); break; }
          case 'inclineBench': { const seat = [hip[0] + 2, hip[1] + 2.5]; L(seat, [shoulder[0] - 6, shoulder[1] - 2]); L(seat, [seat[0], FLOOR]); L([hip[0] - 8, seat[1]], seat); break; }
          case 'declineBench': legs([hip[0] - 12, hip[1] + 5], [knee[0] + 2, knee[1] + 2]); break;
          case 'seat': LXY(hip[0] - 6, hip[1] + 2.5, hip[0] + 8, hip[1] + 2.5); LXY(hip[0] - 4, hip[1] + 2.5, hip[0] - 4, FLOOR); break;
          case 'backrest': LXY(hip[0] - 5, hip[1] + 2.5, shoulder[0] - 3, shoulder[1] - 4); break;
          case 'hackPad': { const n = frontNormal(live.pose.torso); const low = [lhip[0] - 3 * n[0], lhip[1] - 3 * n[1] + 3], high = [lsh[0] - 3 * n[0] - 2, lsh[1] - 3 * n[1] - 5]; L(low, high); L(low, [low[0] + 4, FLOOR]); break; }
          case 'frontPad': { const n = frontNormal(p.torso); const low = [hip[0] + 3 * n[0], hip[1] + 3 * n[1]], high = [shoulder[0] + 3 * n[0] + 2, shoulder[1] + 3 * n[1] - 2]; L(low, high); L(low, [low[0], FLOOR]); break; }
          case 'preacherPad': { const elbow = fixed.arms[0][0]; const top = [shoulder[0] + 1, shoulder[1] + 3], bottom = [elbow[0] + 4, elbow[1] + 3]; L(top, bottom); L(bottom, [bottom[0], FLOOR]); break; }
          case 'chestPad': LXY(shoulder[0] + 3, shoulder[1] - 5, shoulder[0] + 3, hip[1] + 2.5); break;
          case 'kneePad': LXY(lknee[0] - 3, lknee[1] - 3.5, lknee[0] + 4, lknee[1] - 3.5); LXY(lknee[0] + 4, lknee[1] - 3.5, lknee[0] + 4, FLOOR); break;
          case 'shoulderPads': LXY(lsh[0] - 1, lsh[1] - 1.5, lsh[0] + 5, lsh[1] - 1.5); LXY(lsh[0] + 5, 6, lsh[0] + 5, FLOOR); L([lsh[0] + 5, lh[1]], lh); break;
          case 'cable': L(lh, [hand[0] + 10, 4]); LXY(hand[0] - 4, 4, hand[0] + 24, 4); break;
          case 'cableHigh': L(lh, [hand[0] + 3, 2]); LXY(hand[0] - 11, 2, hand[0] + 17, 2); break;
          case 'cableFromBehind': L(lh, [hand[0] - 22, 4]); LXY(hand[0] - 26, 4, hand[0] - 18, 4); break;
          case 'cableLowFront': L(lh, [hand[0] + 6, FLOOR - 4]); LXY(hand[0] + 3, FLOOR - 4, hand[0] + 9, FLOOR - 4); break;
          case 'cableBehindLow': L(lh, [hand[0] - 18, FLOOR - 6]); LXY(hand[0] - 21, FLOOR - 6, hand[0] - 15, FLOOR - 6); break;
          case 'cableFrontLevel': L(lh, [hand[0] + 12, hand[1]]); LXY(hand[0] + 12, 4, hand[0] + 12, FLOOR); break;
          case 'rearBench': { const f = fixed.legs[fixed.legs.length - 1].foot; LXY(f[0] - 6, f[1] + 1, f[0] + 5, f[1] + 1); for (const x of [f[0] - 4, f[0] + 3]) LXY(x, f[1] + 1, x, FLOOR); break; }
          case 'footBlock': LXY(foot[0] - 4, foot[1] + 1, foot[0] + 5, foot[1] + 1); for (const x of [foot[0] - 4, foot[0] + 5]) LXY(x, foot[1] + 1, x, FLOOR); break;
          case 'footPlate': LXY(lfoot[0] + 1, lfoot[1] - 7, lfoot[0] + 2.5, lfoot[1] + 7); break;
          case 'highBar': LXY(hand[0] - 20, hand[1], hand[0] + 20, hand[1]); for (const x of [hand[0] - 20, hand[0] + 20]) LXY(x, hand[1], x, hand[1] - 6); break;
          case 'dipBars': LXY(hand[0] - 14, hand[1], hand[0] + 14, hand[1]); for (const x of [hand[0] - 10, hand[0] + 10]) LXY(x, hand[1], x, FLOOR); break;
          case 'smithRails': for (const x of [hand[0] - 16, hand[0] + 16]) LXY(x, 4, x, FLOOR); break;
          case 'machineArm': L(lh, [hand[0], hand[1] + 12]); break;
          case 'tBar': L(lh, [hand[0] + 16, FLOOR - 1]); break;
          case 'post': LXY(hand2[0], 4, hand2[0], FLOOR); break;
          case 'supportRail': LXY(hand2[0] + 1, hand2[1] - 12, hand2[0] + 1, FLOOR); break;
          case 'supportBench': LXY(hand2[0] - 4, hand2[1] + 1, hand2[0] + 8, hand2[1] + 1); for (const x of [hand2[0] - 2, hand2[0] + 6]) LXY(x, hand2[1] + 1, x, FLOOR); break;
          case 'handBench': LXY(hand[0] - 10, hand[1] + 1, hand[0] + 3, hand[1] + 1); for (const x of [hand[0] - 8, hand[0] + 1]) LXY(x, hand[1] + 1, x, FLOOR); break;
          case 'anklePad': { const l = live.legs[0]; const flat = Skeleton.footFlat(fixed.legs[0]); pad(flat ? l.foot : off(l.foot, 0, 0), l.shin); break; }
          case 'heelAnchor': LXY(foot[0] - 3, FLOOR, foot[0] - 3, foot[1] - 4); LXY(foot[0] - 3, foot[1] - 4, foot[0] + 3, foot[1] - 4); break;
          case 'calfBlock': {
            const toe = [foot[0] + 5, FLOOR];
            LXY(toe[0] - 9, FLOOR, toe[0] + 3, FLOOR); LXY(toe[0] + 3, FLOOR, toe[0] + 3, FLOOR + 3.5); LXY(toe[0] - 9, FLOOR + 3.5, toe[0] + 3, FLOOR + 3.5); LXY(toe[0] - 9, FLOOR, toe[0] - 9, FLOOR + 3.5);
            break;
          }
          case 'dipBelt': LXY(lhip[0] + 2, lhip[1], lhip[0] + 3, lhip[1] + 6); out.push(['circle', [lhip[0] + 3, lhip[1] + 8], 2]); break;
        }
      }
      if (p.floor) out.push(['floor']);
      return out;
    }
    computeFrame() {
      const pts = [];
      for (const sk of [this.a, this.b]) {
        pts.push(sk.hip, sk.shoulder, off(sk.head, -HEAD_R, -HEAD_R), off(sk.head, HEAD_R, HEAD_R));
        for (const a of sk.arms) pts.push(a[0], a[1]);
        for (const l of sk.legs) pts.push(l.knee, l.foot);
        if (sk.pose.impl !== 'none') { const r = PLATE_R[sk.pose.impl] ?? 4; const c = sk.pose.impl === 'barbellOnHips' ? sk.hip : sk.hand; pts.push(off(c, -r, -r), off(c, r, r)); }
        for (const prim of this.props(sk)) {
          if (prim[0] === 'line' || prim[0] === 'plate') pts.push(prim[1], prim[2]);
          else if (prim[0] === 'circle') pts.push(off(prim[1], -prim[2], -prim[2]), off(prim[1], prim[2], prim[2]));
        }
      }
      let x0 = Math.min(...pts.map(p => p[0])), x1 = Math.max(...pts.map(p => p[0]));
      let y0 = Math.min(...pts.map(p => p[1])), y1 = Math.max(...pts.map(p => p[1]));
      if (this.m.a.floor) y1 = Math.max(y1, FLOOR);
      const pad = 4.5;
      return { x: x0 - pad, y: y0 - pad, w: x1 - x0 + 2 * pad, h: y1 - y0 + 2 * pad };
    }
    draw(ctx, w, h, t, colors) {
      const sk = this.at(t), props = this.props(sk), fr = this.frame;
      const fit = Math.min(w / 100, h / 60), scale = Math.min(100 / fr.w, 60 / fr.h, 1.5), k = fit * scale;
      const vw = 100 / scale, vh = 60 / scale;
      ctx.save();
      ctx.translate((w - 100 * fit) / 2, (h - 60 * fit) / 2);
      ctx.scale(k, k);
      ctx.translate(-(fr.x + fr.w / 2 - vw / 2), -(fr.y + fr.h / 2 - vh / 2));
      ctx.lineCap = 'round'; ctx.lineJoin = 'round';
      const line = (a, b, lw, color) => { ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineWidth = lw; ctx.strokeStyle = color; ctx.stroke(); };
      const circle = (c, r, fill, stroke, lw) => { ctx.beginPath(); ctx.arc(c[0], c[1], r, 0, Math.PI * 2); if (fill) { ctx.fillStyle = fill; ctx.fill(); } if (stroke && lw > 0) { ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.stroke(); } };
      const { brass, card, far, gear, gearFill, prop } = colors;
      for (const prim of props) {
        if (prim[0] === 'line') line(prim[1], prim[2], 1.4, prop);
        else if (prim[0] === 'plate') line(prim[1], prim[2], 2.4, prop);
        else if (prim[0] === 'circle') circle(prim[1], prim[2], null, prop, 1.4);
        else line([fr.x - 1.5, FLOOR], [fr.x + fr.w + 1.5, FLOOR], 1.4, prop);
      }
      // implement
      const hand = sk.hand, impl = sk.pose.impl;
      const plate = (c, r) => { circle(c, r, gearFill, gear, 1.6); circle(c, 1.3, gear); };
      const dumbbell = (hh, vertical) => {
        if (vertical) { line(off(hh, 0, -3.2), off(hh, 0, 3.2), 1.6, gear); for (const y of [-3.2, 3.2]) line(off(hh, -2.4, y), off(hh, 2.4, y), 2.6, gear); }
        else { line(off(hh, -3.2, 0), off(hh, 3.2, 0), 1.6, gear); for (const x of [-3.2, 3.2]) line(off(hh, x, -2.4), off(hh, x, 2.4), 2.6, gear); }
      };
      switch (impl) {
        case 'none': break;
        case 'barbell': case 'barbellNarrow': case 'shortBar': plate(hand, PLATE_R[impl]); break;
        case 'barbellOnHips': plate(sk.hip, PLATE_R.barbellOnHips); break;
        case 'trapBar': plate(hand, PLATE_R.trapBar); line(off(hand, 0, -4), off(hand, 0, 4), 1.8, gear); break;
        case 'dumbbell': for (const a of sk.arms) dumbbell(a[1], false); break;
        case 'dumbbellVertical': for (const a of sk.arms) dumbbell(a[1], true); break;
        case 'dumbbellFirst': dumbbell(hand, true); break;
        case 'handle': line(off(hand, -2.6, 0), off(hand, 2.6, 0), 2.2, gear); break;
        case 'kettlebell': line(hand, off(hand, 0, 2.5), 1.6, gear); circle(off(hand, 0, 5.5), 3.2, gear); break;
        case 'wheel': circle([hand[0], FLOOR - 2.6], 2.6, gearFill, gear, 1.6); break;
      }
      // body: far legs, near leg, torso, far arm, (head), near arm
      const segment = (a, b, isTorso, isFar) => { const lw = isTorso ? TORSO_W : LIMB_W; line(a, b, lw + OUTLINE, card); line(a, b, lw, isFar ? far : brass); };
      const legsRev = [...sk.legs].reverse();
      legsRev.forEach((leg, i) => { const isFar = sk.legs.length > 1 && i === 0; segment(sk.hip, leg.knee, false, isFar); segment(leg.knee, leg.foot, false, isFar); });
      segment(sk.hip, sk.shoulder, true, false);
      const armsRev = [...sk.arms].reverse(); const near = [];
      armsRev.forEach((arm, i) => { const isFar = sk.arms.length > 1 && i === 0; if (isFar) { segment(sk.shoulder, arm[0], false, true); segment(arm[0], arm[1], false, true); } else near.push([sk.shoulder, arm[0]], [arm[0], arm[1]]); });
      sk.legs.forEach((leg, i) => {
        const len = Skeleton.toeLength(leg);
        if (len <= 0) return;
        const pinned = i === 0 && this.anchor === 'foot' || (i === sk.legs.length - 1 && this.anchor === 'foot2');
        const toe = pinned ? off(this.a.legs[i].foot, len, 0) : off(leg.foot, len, 0);
        line(leg.foot, toe, LIMB_W + 1.0, card); line(leg.foot, toe, LIMB_W - 0.4, brass);
      });
      // head
      const hd = sk.head, r = HEAD_R, ang = sk.headAngle;
      circle(hd, r, brass, card, 1.1);
      const f = frontNormal(ang), u = [Math.cos(rad(ang)), Math.sin(rad(ang))];
      const eye = [hd[0] + f[0] * r * 0.5 + u[0] * r * 0.12, hd[1] + f[1] * r * 0.5 + u[1] * r * 0.12];
      circle(eye, r * 0.19, card);
      const ba = [eye[0] - f[0] * r * 0.12 + u[0] * r * 0.34, eye[1] - f[1] * r * 0.12 + u[1] * r * 0.34];
      const bb = [eye[0] + f[0] * r * 0.32 + u[0] * r * 0.4, eye[1] + f[1] * r * 0.32 + u[1] * r * 0.4];
      line(ba, bb, r * 0.18, card);
      for (const s of near) segment(s[0], s[1], false, false);
      circle(sk.hand, LIMB_W * 0.6, brass, card, 0.9);
      ctx.restore();
    }
  }
  // phase: eased ping-pong A -> B -> A with a short pause at each end
  Figure.phase = function (time, period) {
    const u = (time % period) / period;
    const hold = 0.08, span = 0.5 - hold;
    let t;
    if (u < span) t = u / span; else if (u < 0.5) t = 1; else if (u < 0.5 + span) t = 1 - (u - 0.5) / span; else t = 0;
    return (1 - Math.cos(Math.PI * t)) / 2;
  };
  global.Pictogram = { Figure, Skeleton, FLOOR };
})(typeof window !== 'undefined' ? window : globalThis);
