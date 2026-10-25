"""Builds the self-contained HTML review page: every technique guide (staged demonstration + cues) and, below it,
the compact deck pictograms side by side. Body-only HTML; `motions.py report` compiles it into the artifact shell."""
import html
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from guides import export_json as export_guides  # noqa: E402
from motions import export_json  # noqa: E402

PATTERN_NAMES = {
    "horizontal_press": "Horizontal press", "vertical_press": "Vertical press", "incline_press": "Incline press", "chest_fly": "Chest fly",
    "lateral_raise": "Lateral raise", "triceps_extension": "Triceps extension", "vertical_pull": "Vertical pull", "horizontal_row": "Horizontal row",
    "rear_delt": "Rear delt", "elbow_flexion": "Elbow flexion", "squat": "Squat", "hinge": "Hinge", "quad_isolation": "Quad isolation",
    "hamstring_isolation": "Hamstring isolation", "calf": "Calf", "core": "Core",
}


def esc(s: str) -> str:
    return html.escape(s)


def scope_badge(kind: str, scope: str) -> str:
    cls = "badge badge--exercise" if scope == "exercise" else "badge badge--family"
    label = f"{kind}: {'exercise-specific' if scope == 'exercise' else 'family'}"
    return f'<span class="{cls}">{esc(label)}</span>'


def guide_card(g: dict) -> str:
    stages = "".join(f'<li class="stage" data-i="{i}"><span class="stage__n">{i + 1}</span><span class="stage__name">{esc(s["name"])}</span>'
                     f'<span class="stage__cue">{esc(s["cue"])}</span></li>' for i, s in enumerate(g["stages"]))
    lists = "".join(f'<div class="cues__group"><h4>{title}</h4><ul>{"".join(f"<li>{esc(x)}</li>" for x in g["cues"][k])}</ul></div>'
                    for title, k in (("Set up", "setup"), ("Execute", "execute"), ("Avoid", "avoid")))
    overlays = ", ".join(g["overlays"])
    return f'''<article class="guide" data-key="{g["key"]}" data-plan="{g["plan"]}">
  <header class="guide__head"><h3>{esc(g["name"])}</h3><code>{g["key"]}</code>
    <span class="meta">{scope_badge("figure", g["motionScope"])} {scope_badge("cues", g["cuesScope"])}
    <span class="plan">plan <code>{g["plan"]}</code> · {len(g["keyframes"])} keyframes · overlays {esc(overlays)}</span></span></header>
  <div class="guide__body">
    <div class="demo">
      <canvas class="demo__loop" width="720" height="490" role="img" aria-label="{esc(g["name"])} staged demonstration"></canvas>
      <div class="demo__stages"><ol class="stages">{stages}</ol></div>
      <canvas class="demo__frames" width="720" height="160" role="img" aria-label="{esc(g["name"])} stage end positions"></canvas>
    </div>
    <div class="cues">{lists}<div class="cues__group"><h4>Breathe</h4><p>{esc(g["cues"]["breathe"])}</p></div></div>
  </div>
</article>'''


def body_html(data, guides) -> str:
    groups: dict[str, list] = {}
    for e in data:
        groups.setdefault(e["pattern"], []).append(e)
    gmap = {g["key"]: g for g in guides}
    n = len(guides)
    mot_ex = sum(g["motionScope"] == "exercise" for g in guides)
    cue_ex = sum(g["cuesScope"] == "exercise" for g in guides)
    plans = sorted({g["plan"] for g in guides})
    fam_cues = [g["name"] for g in guides if g["cuesScope"] == "family"]
    fam_mot = [g["name"] for g in guides if g["motionScope"] == "family"]

    summary = f'''
<section class="a-section" id="summary"><h2 class="a-section__title">Coverage</h2>
<div class="stats">
  <div class="stat"><div class="stat__v">{n}</div><div class="stat__l">exercises in the catalog</div></div>
  <div class="stat"><div class="stat__v">{mot_ex}<span class="stat__of">/{n}</span></div><div class="stat__l">exercise-specific figures (rest use the family pose)</div></div>
  <div class="stat"><div class="stat__v">{cue_ex}<span class="stat__of">/{n}</span></div><div class="stat__l">exercise-specific cues (rest use family cues, labelled)</div></div>
  <div class="stat"><div class="stat__v">{len(plans)}</div><div class="stat__l">stage plans</div></div>
</div>
<p class="a-section__note"><strong>Family cues</strong> ({len(fam_cues)}): {esc(", ".join(fam_cues))}.</p>
<p class="a-section__note"><strong>Family figure</strong> ({len(fam_mot)}): {esc(", ".join(fam_mot))} — for these the family pose is the
canonical exercise, so the drawing is right; it is labelled because it was not posed for that key specifically.</p>
</section>'''

    guide_sections = []
    for pattern, items in groups.items():
        guide_sections.append(f'<section class="a-section guides"><h2 class="a-section__title">{esc(PATTERN_NAMES.get(pattern, pattern))}'
                              f' <span class="count">{len(items)}</span></h2>')
        for e in items:
            guide_sections.append(guide_card(gmap[e["key"]]))
        guide_sections.append("</section>")

    cards = []
    for pattern, items in groups.items():
        cards.append(f'<section class="a-section"><h2 class="a-section__title">{esc(PATTERN_NAMES.get(pattern, pattern))}'
                     f' <span class="count">{len(items)}</span></h2><div class="grid">')
        for e in items:
            cards.append(
                f'<figure class="pic" data-key="{e["key"]}">'
                f'<canvas width="600" height="360" role="img" aria-label="{esc(e["name"])} animation"></canvas>'
                f'<figcaption><span class="name">{esc(e["name"])}</span><code>{e["key"]}</code></figcaption></figure>')
        cards.append("</div></section>")
    renderer = (HERE / "renderer.js").read_text()
    return f"""
<style>
.controls {{ display:flex; flex-wrap:wrap; gap:12px 20px; align-items:center; margin-top:24px; padding:12px 0; border-bottom:1px solid rgb(var(--border-primary)); font-size:13px; position:sticky; top:0; background:rgb(var(--bg-primary)); z-index:2; }}
.controls label {{ display:flex; gap:8px; align-items:center; }}
.controls button {{ font:inherit; padding:4px 12px; border-radius:6px; border:1px solid rgb(var(--border-primary)); background:rgb(var(--bg-elevated)); color:inherit; cursor:pointer; }}
.count {{ color:rgb(var(--text-tertiary)); font-weight:400; margin-left:6px; }}
.stats {{ display:grid; grid-template-columns:repeat(auto-fit, minmax(160px, 1fr)); gap:16px; margin:16px 0; }}
.stat__v {{ font-size:32px; font-weight:700; font-variant-numeric:tabular-nums; }} .stat__of {{ font-size:16px; color:rgb(var(--text-tertiary)); font-weight:400; }}
.stat__l {{ font-size:13px; color:rgb(var(--text-secondary)); }}
.badge {{ display:inline-block; font-size:11px; padding:2px 8px; border-radius:999px; border:1px solid; margin-right:6px; vertical-align:middle; }}
.badge--exercise {{ color:#D4B275; border-color:rgba(212,178,117,0.5); background:rgba(212,178,117,0.08); }}
.badge--family {{ color:rgb(var(--text-secondary)); border-color:rgb(var(--border-primary)); }}
.guide {{ border-top:1px solid rgb(var(--border-primary)); padding:20px 0 28px; }}
.guide__head {{ display:flex; flex-wrap:wrap; gap:4px 12px; align-items:baseline; margin-bottom:12px; }}
.guide__head h3 {{ margin:0; font-size:20px; }} .guide__head code {{ font-family:var(--font-mono); font-size:11px; color:rgb(var(--text-tertiary)); }}
.guide__head .meta {{ font-size:12px; color:rgb(var(--text-tertiary)); display:flex; flex-wrap:wrap; gap:6px; align-items:center; }}
.guide__body {{ display:grid; grid-template-columns:minmax(300px, 1.1fr) minmax(280px, 1fr); gap:24px; }}
@media (max-width: 820px) {{ .guide__body {{ grid-template-columns:1fr; }} }}
.demo canvas {{ display:block; width:100%; border-radius:12px; background:#151517; }}
.demo__loop {{ aspect-ratio:720/490; }} .demo__frames {{ aspect-ratio:720/160; margin-top:8px; }}
.stages {{ list-style:none; margin:10px 0 0; padding:0; display:grid; grid-template-columns:repeat(auto-fit, minmax(120px, 1fr)); gap:8px; }}
.stage {{ border-top:2px solid rgb(var(--border-primary)); padding-top:6px; font-size:12px; color:rgb(var(--text-tertiary)); cursor:pointer; }}
.stage.active {{ border-top-color:#D4B275; color:inherit; }} .stage.active .stage__name {{ color:#D4B275; }}
.stage__n {{ font-weight:700; margin-right:6px; font-variant-numeric:tabular-nums; }} .stage__name {{ font-weight:600; }}
.stage__cue {{ display:block; margin-top:4px; line-height:1.35; }}
.cues__group h4 {{ margin:0 0 4px; font-size:11px; letter-spacing:0.08em; text-transform:uppercase; color:rgb(var(--text-tertiary)); }}
.cues__group {{ margin-bottom:12px; }} .cues ul {{ margin:0; padding-left:18px; font-size:14px; line-height:1.45; }} .cues p {{ margin:0; font-size:14px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(230px, 1fr)); gap:16px; }}
.pic {{ margin:0; }}
.pic canvas {{ display:block; width:100%; aspect-ratio:5/3; border-radius:12px; background:#151517; }}
.pic.frames canvas {{ aspect-ratio:5/1; }}
body.big .grid {{ grid-template-columns:1fr; }} body.big .a-shell {{ max-width:none; }} body.big .guide__body {{ grid-template-columns:1fr; }}
.pic figcaption {{ display:flex; flex-direction:column; gap:2px; margin-top:8px; }}
.pic .name {{ font-weight:600; }}
.pic code {{ font-family:var(--font-mono); font-size:11px; color:rgb(var(--text-tertiary)); }}
details.pictos summary {{ cursor:pointer; font-size:20px; font-weight:700; margin:32px 0 8px; }}
</style>
<div class="controls" role="group" aria-label="Playback">
  <button type="button" id="play" aria-pressed="true">Pause</button>
  <label>Speed <input type="range" id="speed" min="0.25" max="2" step="0.25" value="1"> <span id="speedv">1×</span></label>
  <label><input type="checkbox" id="frames"> Deck pictograms: show keyframes (start · middle · end) instead of the loop</label>
  <label><input type="checkbox" id="onlyfamily"> Show only guides with family-level cues</label>
</div>
<p class="a-section__note" style="margin-top:16px">Each guide loops through its stages (1.1 s per move, 0.8 s hold) exactly as the in-app technique sheet does,
drawn from the same keyframes and renderer port. Under the loop, the end position of every stage is shown side by side. Dotted brass is the load
path over the whole rep; the dashed grey vertical is the mid-foot reference on grounded loaded lifts; small rings mark the joints. Dimmed limbs are
the far side of the body; barbells are seen end-on because every pose is a side view. Badges say whether the figure and the cues were authored for
that exercise or inherited from its movement family. Click a stage to freeze the figure there; click again to resume.</p>
{summary}
{''.join(guide_sections)}
<details class="pictos" id="pictos"><summary>Deck pictograms (compact, unchanged)</summary>
{''.join(cards)}
</details>
<script>{renderer}</script>
<script>
const DATA = {json.dumps(data)};
const GUIDES = {json.dumps(guides)};
const COLORS = {{ brass:'#D4B275', card:'#151517', far:'rgba(212,178,117,0.55)', gear:'rgba(245,245,247,0.6)', gearFill:'rgba(245,245,247,0.1)', prop:'rgba(212,178,117,0.38)' }};
const figs = new Map(DATA.map(d => [d.key, new Pictogram.Figure(d)]));
const cards = [...document.querySelectorAll('.pic')];
const guideEls = [...document.querySelectorAll('.guide')];
const guideState = new Map(GUIDES.map(g => {{
  const tl = new Pictogram.Timeline(g);
  const fig = new Pictogram.Figure(g, {{ joints: g.overlays.includes('joints'), midfoot: g.overlays.includes('midfoot'), maxScale: 2.4 }});
  if (g.overlays.includes('path')) {{
    const path = fig.trace(tl.order);
    const xs = path.map(p => p[0]), ys = path.map(p => p[1]);
    if (Math.max(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys)) > 2.5) fig.detail.path = path;
  }}
  return [g.key, {{ g, tl, fig, frozen: null, framesDrawn: false }}];
}}));
let playing = true, speed = 1, showFrames = false, clock = 0, last = performance.now();
const PERIOD = 2800;
function visible(el) {{ const r = el.getBoundingClientRect(); return r.bottom > -200 && r.top < innerHeight + 200; }}
function draw(now) {{
  if (playing) clock += (now - last) * speed; last = now;
  for (const card of cards) {{
    if (card.closest('details') && !card.closest('details').open) continue;
    if (!visible(card)) continue;
    const fig = figs.get(card.dataset.key), cv = card.querySelector('canvas'), ctx = cv.getContext('2d');
    ctx.clearRect(0, 0, cv.width, cv.height);
    if (showFrames) {{
      const w = cv.width / 3;
      [0, 0.5, 1].forEach((t, i) => {{ ctx.save(); ctx.translate(i * w, 0); fig.draw(ctx, w, cv.height, t, COLORS); ctx.restore(); }});
    }} else fig.draw(ctx, cv.width, cv.height, Pictogram.Figure.phase(clock, PERIOD), COLORS);
  }}
  for (const el of guideEls) {{
    const st = guideState.get(el.dataset.key);
    if (!st) continue;
    const loop = el.querySelector('.demo__loop'), framesCv = el.querySelector('.demo__frames');
    if (!st.framesDrawn) {{
      const n = st.g.stages.length, w = framesCv.width / n, fctx = framesCv.getContext('2d');
      fctx.clearRect(0, 0, framesCv.width, framesCv.height);
      st.g.stages.forEach((s, i) => {{ const f = st.tl.endOf(i, st.g); fctx.save(); fctx.translate(i * w, 0); st.fig.drawBetween(fctx, w, framesCv.height, f, f, 0, COLORS); fctx.restore();
        fctx.save(); fctx.fillStyle = 'rgba(245,245,247,0.45)'; fctx.font = '600 13px system-ui'; fctx.fillText((i + 1) + ' ' + s.name, i * w + 10, 20); fctx.restore(); }});
      st.framesDrawn = true;
    }}
    if (!visible(el)) continue;
    const ctx = loop.getContext('2d');
    ctx.clearRect(0, 0, loop.width, loop.height);
    let stage;
    if (st.frozen !== null) {{ const f = st.tl.endOf(st.frozen, st.g); st.fig.drawBetween(ctx, loop.width, loop.height, f, f, 0, COLORS); stage = st.frozen; }}
    else {{ const s = st.tl.at(clock); st.fig.drawBetween(ctx, loop.width, loop.height, s.from, s.to, s.t, COLORS); stage = s.stage; }}
    el.querySelectorAll('.stage').forEach((li, i) => li.classList.toggle('active', i === stage));
  }}
  requestAnimationFrame(draw);
}}
requestAnimationFrame(draw);
for (const el of guideEls) el.querySelectorAll('.stage').forEach(li => li.addEventListener('click', () => {{
  const st = guideState.get(el.dataset.key); const i = +li.dataset.i; st.frozen = st.frozen === i ? null : i;
}}));
document.getElementById('play').addEventListener('click', e => {{ playing = !playing; e.target.textContent = playing ? 'Pause' : 'Play'; e.target.setAttribute('aria-pressed', playing); }});
document.getElementById('speed').addEventListener('input', e => {{ speed = +e.target.value; document.getElementById('speedv').textContent = speed + '×'; }});
document.getElementById('frames').addEventListener('change', e => {{
  showFrames = e.target.checked;
  for (const c of cards) {{ c.classList.toggle('frames', showFrames); c.querySelector('canvas').height = showFrames ? 120 : 360; }}
}});
document.getElementById('onlyfamily').addEventListener('change', e => {{
  for (const el of guideEls) {{ const g = guideState.get(el.dataset.key).g; el.hidden = e.target.checked && g.cuesScope !== 'family'; }}
  document.querySelectorAll('.a-section.guides').forEach(s => {{ s.hidden = ![...s.querySelectorAll('.guide')].some(x => !x.hidden); }});
}});
// Hash modes for headless review: #frames[-big][-skip=N][-only=a,b] (deck keyframes), #guides-freeze=N freezes every guide on stage N,
// #guides-only=key1,key2 keeps just those guides, #guides-skip=N hides the first N guide sections.
if (location.hash.startsWith('#frames')) {{ document.getElementById('pictos').open = true; if (location.hash.startsWith('#frames-big')) document.body.classList.add('big');
  const only = (location.hash.match(/only=([\\w,]+)/) || [])[1]; if (only) {{ const keep = new Set(only.split(',')); document.querySelectorAll('.pic').forEach(c => {{ if (!keep.has(c.dataset.key)) c.remove(); }}); document.querySelectorAll('.a-section').forEach(s => {{ if (!s.querySelector('.pic')) s.remove(); }}); }}
  const skip = +(location.hash.split('skip=')[1] || 0); document.querySelectorAll('.a-section').forEach((s, i) => {{ if (i < skip) s.hidden = true; }}); const cb = document.getElementById('frames'); cb.checked = true; cb.dispatchEvent(new Event('change')); }}
if (location.hash.startsWith('#guides')) {{
  const freeze = location.hash.match(/freeze=(\\d+)/); if (freeze) for (const st of guideState.values()) st.frozen = Math.min(+freeze[1], st.g.stages.length - 1);
  const only = (location.hash.match(/only=([\\w,]+)/) || [])[1]; if (only) {{ const keep = new Set(only.split(',')); guideEls.forEach(el => {{ if (!keep.has(el.dataset.key)) el.remove(); }}); document.querySelectorAll('.a-section.guides').forEach(s => {{ if (!s.querySelector('.guide')) s.remove(); }}); }}
  const skip = +((location.hash.match(/skip=(\\d+)/) || [])[1] || 0); document.querySelectorAll('.a-section.guides').forEach((s, i) => {{ if (i < skip) s.hidden = true; }});
  if (location.hash.includes('big')) document.body.classList.add('big');
}}
if (matchMedia('(prefers-reduced-motion: reduce)').matches) {{ playing = false; document.getElementById('play').textContent = 'Play'; }}
</script>
"""


def build(out: str):
    body = HERE / "report_body.html"
    body.write_text(body_html(export_json(), export_guides()))
    print(f"wrote body fragment {body}; compile it with interactive_artifact_compile -> {out}")


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else str(Path.home() / "exercise-animations.html"))
