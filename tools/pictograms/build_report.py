"""Builds the self-contained HTML review page: every exercise animating side by side."""
import html
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from motions import export_json  # noqa: E402

PATTERN_NAMES = {
    "horizontal_press": "Horizontal press", "vertical_press": "Vertical press", "incline_press": "Incline press", "chest_fly": "Chest fly",
    "lateral_raise": "Lateral raise", "triceps_extension": "Triceps extension", "vertical_pull": "Vertical pull", "horizontal_row": "Horizontal row",
    "rear_delt": "Rear delt", "elbow_flexion": "Elbow flexion", "squat": "Squat", "hinge": "Hinge", "quad_isolation": "Quad isolation",
    "hamstring_isolation": "Hamstring isolation", "calf": "Calf", "core": "Core",
}


def body_html(data) -> str:
    groups: dict[str, list] = {}
    for e in data:
        groups.setdefault(e["pattern"], []).append(e)
    cards = []
    for pattern, items in groups.items():
        cards.append(f'<section class="a-section"><h2 class="a-section__title">{html.escape(PATTERN_NAMES.get(pattern, pattern))}'
                     f' <span class="count">{len(items)}</span></h2><div class="grid">')
        for e in items:
            cards.append(
                f'<figure class="pic" data-key="{e["key"]}">'
                f'<canvas width="600" height="360" role="img" aria-label="{html.escape(e["name"])} animation"></canvas>'
                f'<figcaption><span class="name">{html.escape(e["name"])}</span><code>{e["key"]}</code></figcaption></figure>')
        cards.append("</div></section>")
    renderer = (HERE / "renderer.js").read_text()
    return f"""
<style>
.controls {{ display:flex; flex-wrap:wrap; gap:12px 20px; align-items:center; margin-top:24px; padding:12px 0; border-bottom:1px solid rgb(var(--border-primary)); font-size:13px; }}
.controls label {{ display:flex; gap:8px; align-items:center; }}
.controls button {{ font:inherit; padding:4px 12px; border-radius:6px; border:1px solid rgb(var(--border-primary)); background:rgb(var(--bg-elevated)); color:inherit; cursor:pointer; }}
.count {{ color:rgb(var(--text-tertiary)); font-weight:400; margin-left:6px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(230px, 1fr)); gap:16px; }}
.pic {{ margin:0; }}
.pic canvas {{ display:block; width:100%; aspect-ratio:5/3; border-radius:12px; background:#151517; }}
.pic.frames canvas {{ aspect-ratio:5/1; }}
body.big .grid {{ grid-template-columns:1fr; }} body.big .a-shell {{ max-width:none; }}
.pic figcaption {{ display:flex; flex-direction:column; gap:2px; margin-top:8px; }}
.pic .name {{ font-weight:600; }}
.pic code {{ font-family:var(--font-mono); font-size:11px; color:rgb(var(--text-tertiary)); }}
</style>
<div class="controls" role="group" aria-label="Playback">
  <button type="button" id="play" aria-pressed="true">Pause</button>
  <label>Speed <input type="range" id="speed" min="0.25" max="2" step="0.25" value="1"> <span id="speedv">1×</span></label>
  <label><input type="checkbox" id="frames"> Show keyframes (start · middle · end) instead of the loop</label>
</div>
<p class="a-section__note" style="margin-top:16px">Each card loops start → end → start with an eased tempo (about 2.8 s per rep). The figure is drawn
from the same kinematic skeleton as the app, so what you see here is what the deck cards show. Dimmed limbs are the far side of the body;
barbells are seen end-on (a plate ring at the hand) because every pose is a side view.</p>
{''.join(cards)}
<script>{renderer}</script>
<script>
const DATA = {json.dumps(data)};
const COLORS = {{ brass:'#D4B275', card:'#151517', far:'rgba(212,178,117,0.55)', gear:'rgba(245,245,247,0.6)', gearFill:'rgba(245,245,247,0.1)', prop:'rgba(212,178,117,0.38)' }};
const figs = new Map(DATA.map(d => [d.key, new Pictogram.Figure(d)]));
const cards = [...document.querySelectorAll('.pic')];
let playing = true, speed = 1, showFrames = false, clock = 0, last = performance.now();
const PERIOD = 2800;
function draw(now) {{
  if (playing) clock += (now - last) * speed; last = now;
  for (const card of cards) {{
    const fig = figs.get(card.dataset.key), cv = card.querySelector('canvas'), ctx = cv.getContext('2d');
    ctx.clearRect(0, 0, cv.width, cv.height);
    if (showFrames) {{
      const w = cv.width / 3;
      [0, 0.5, 1].forEach((t, i) => {{ ctx.save(); ctx.translate(i * w, 0); fig.draw(ctx, w, cv.height, t, COLORS); ctx.restore(); }});
    }} else fig.draw(ctx, cv.width, cv.height, Pictogram.Figure.phase(clock, PERIOD), COLORS);
  }}
  requestAnimationFrame(draw);
}}
requestAnimationFrame(draw);
document.getElementById('play').addEventListener('click', e => {{ playing = !playing; e.target.textContent = playing ? 'Pause' : 'Play'; e.target.setAttribute('aria-pressed', playing); }});
document.getElementById('speed').addEventListener('input', e => {{ speed = +e.target.value; document.getElementById('speedv').textContent = speed + '×'; }});
document.getElementById('frames').addEventListener('change', e => {{
  showFrames = e.target.checked;
  for (const c of cards) {{ c.classList.toggle('frames', showFrames); c.querySelector('canvas').height = showFrames ? 120 : 360; }}
}});
if (location.hash.startsWith('#frames')) {{ if (location.hash.startsWith('#frames-big')) document.body.classList.add('big');
  const only = (location.hash.match(/only=([\w,]+)/) || [])[1]; if (only) {{ const keep = new Set(only.split(',')); document.querySelectorAll('.pic').forEach(c => {{ if (!keep.has(c.dataset.key)) c.remove(); }}); document.querySelectorAll('.a-section').forEach(s => {{ if (!s.querySelector('.pic')) s.remove(); }}); }}
  const skip = +(location.hash.split('skip=')[1] || 0); document.querySelectorAll('.a-section').forEach((s, i) => {{ if (i < skip) s.hidden = true; }}); const cb = document.getElementById('frames'); cb.checked = true; cb.dispatchEvent(new Event('change')); }}
if (matchMedia('(prefers-reduced-motion: reduce)').matches) {{ playing = false; document.getElementById('play').textContent = 'Play'; }}
</script>
"""


def build(out: str):
    body = HERE / "report_body.html"
    body.write_text(body_html(export_json()))
    print(f"wrote body fragment {body}; compile it with interactive_artifact_compile -> {out}")


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "exercise-animations.html")
