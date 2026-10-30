# Exercise technique guides

Tapping the pictogram on a set card opens a technique sheet (`ExerciseGuideView`): a large staged demonstration
of the movement, the stages as a tappable strip with one cue each, and the written set-up / execution / faults /
breathing cues. This document describes the data model, where the content comes from, and how specific it is.

## Data model

Everything is authored in `tools/pictograms/guides.py` and generated into `ios/WorkoutApp/Sources/ExerciseGuide.swift`
(`python3 motions.py guides`); never hand-edit the Swift table.

| Piece | Where | Granularity |
|---|---|---|
| Keyframes | `motions.py` `TABLE` / `PATTERNS` (the same side-view poses the deck pictogram uses, with the implement/Smith fixes applied) | per exercise where `TABLE` has one, otherwise the family pose |
| Plan | `guides.py` `PLANS` — the order the keyframes are visited and the named stages (`Set up → Descend → Drive`), one cue per stage. The `deadlift` plan derives a knee-pass keyframe (shins vertical, back angle held) from the floor and lockout poses. | per family (`PATTERN_PLAN`), overridden per exercise where the pictogram's keyframe convention or the staging differs (`EXERCISE_PLAN`) |
| Overlays | `guides.py` `overlays_for` — joint markers, the dotted load path (bar/dumbbell, or the hip when unloaded), and a dashed mid-foot reference for grounded loaded lifts | derived per exercise |
| Cues | `guides.py` `FAMILY_CUES` (the canonical lift of each movement pattern), `EXERCISE_CUES` (overrides), `DEFAULT_CUES` (custom exercises with unknown patterns) | family, exercise, fallback |
| Scope | `motionScope` / `cuesScope` = `exercise` or `family`, carried into Swift and the review sheet | — |

`GuideTimeline` (Swift) / `Pictogram.Timeline` (JS) turn a plan into a clock: each stage eases through its keyframe
legs (1.1 s each) and holds (0.8 s), then the loop repeats. Tapping a stage freezes the figure on that stage's end
position; with Reduce Motion on, the sheet opens frozen on stage 1 and the user steps through by tapping.

The sheet always states its scope in one line under the title (“General guidance for squat exercises; your setup may
differ.”) so family-level content is never presented as exercise-specific.

## Checks

`python3 tools/pictograms/motions.py check` runs the pictogram checks (centre of mass between heel and toe for
free-standing poses, nothing below the floor, no joint spinning the long way) on **every leg of every guide loop**,
plus: all plan/cue keys exist in `seed/exercises.json`, stage frame indices are in range, every guide has set-up,
execution, avoid and breathing cues. The report (`python3 motions.py report`) renders every guide for eyeballing.

Three pre-existing pictogram warnings (push-up hands 1 unit below the floor at mid-rep, dumbbell rear-delt fly centre
of mass slightly ahead of the toes, bird-dog hands at floor level) are unchanged by this work.

## Sources

Cues were written from established coaching and biomechanics references, not invented per exercise:

- Haff & Triplett (eds.), *NSCA Essentials of Strength Training and Conditioning*, 4th ed., ch. 15 “Exercise Technique
  for Free Weight and Machine Training” — bench press, overhead press, rows, pulldown, squat, deadlift, RDL, lunges,
  curls, triceps, calf raises (grip, stance, bar path, breathing, spotting-relevant faults).
- ACE Exercise Library (American Council on Exercise) — machine and dumbbell variants, push-up and plank family set-up.
- Rippetoe, *Starting Strength*, 3rd ed. — bar over mid-foot, hips/shoulders rising together, head “through” at the
  top of the press.
- McGill, *Low Back Disorders* / *Back Mechanic* — bracing, neutral spine, plank / side plank / bird dog / dead bug.
- Contreras, *Glute Lab* — hip thrust set-up (bar at the hip crease, vertical shins at the top, chin tucked).
- Tsatsouline, *Kettlebell Simple & Sinister* — hike, hip snap, “arms are ropes”, no squatting the swing.

No medical claims are made; the sheet closes with “General technique guidance, not medical advice.”

## Coverage status

Counts come from `python3 -c "import guides; ..."` in `tools/pictograms` and are shown live in the review sheet's
Coverage section.

- **Demonstration**: 70 of 90 catalog exercises use exercise-specific keyframes; 20 inherit the family pose
  (barbell / dumbbell / Smith bench press, overhead press, standing dumbbell press, the three incline presses, dumbbell
  fly, dumbbell lateral raise, lat pulldown, barbell row, dumbbell rear-delt fly, barbell and dumbbell curl, back squat,
  Smith squat, conventional deadlift, leg extension, lying leg curl). For those the family pose *is* the canonical
  exercise, so the figure is correct; it is labelled `family` because it was not posed for that key specifically.
- **Cues**: 72 of 90 exercises have exercise-specific cues (including the canonical lifts, whose family text is their
  write-up). The remaining 18 use family cues and say so on the sheet: chest press machine, Smith bench press, dumbbell
  floor press, shoulder press machine, incline dumbbell / Smith press, cable fly, pec deck fly, cable and lean-away
  lateral raise, overhead cable extension, neutral-grip pulldown, cable reverse fly, cable curl, Smith squat, seated leg
  curl, dumbbell and bodyweight calf raise.
- **Views**: one side view per exercise (the renderer is a profile skeleton). A front view would need a second renderer
  and a second set of checked poses; it is not fabricated here.
- **Stages**: 3 per exercise (set up, out, back) for 84 exercises; 4 for the two floor deadlifts (adds the knee pass);
  2 for the three holds and the dead bug.

Adding specificity later means adding an entry to `EXERCISE_CUES` (and `EXERCISE_PLAN` if the staging differs) and
rerunning `python3 motions.py guides` — no UI changes.
