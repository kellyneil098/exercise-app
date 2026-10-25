"""Exercise technique guides: the detail sheet behind a tap on a deck pictogram.

A Guide is a staged demonstration plus written cues. The demonstration reuses the exercise's pictogram keyframes
from motions.py (so every exercise already has an anatomically-checked side view) and adds a *plan*: the order the
keyframes are visited, named stages ("Set up", "Descend", "Drive"...) with a one-line cue each, and where the plan
needs an intermediate position (the knee-pass of a deadlift) it derives one from the two keyframes.

Cues are written per movement family and overridden per exercise where the exercise differs in a way that matters
for safety or form. The scope of both the motion and the cues is recorded so the UI and the review sheet can say
"general guidance for the squat family" instead of pretending to be exercise-specific. Sources and the status of
per-exercise coverage are documented in docs/exercise-guides.md.

Outputs (never hand-edit): the Swift table in ios/WorkoutApp/Sources/ExerciseGuide.swift between the
`MARK: - Table (generated)` markers (`python3 motions.py guides`) and the review sheet (`python3 motions.py report`).
"""
from __future__ import annotations

from dataclasses import dataclass, field

from motions import TABLE, Motion, Pose, all_exercises, com_check, floor_check, lerp_pose, motion_for, pose_json, pose_swift, wrap_check

FAMILY_NAMES = {
    "horizontal_press": "Horizontal press", "vertical_press": "Vertical press", "incline_press": "Incline press", "chest_fly": "Chest fly",
    "lateral_raise": "Lateral raise", "triceps_extension": "Triceps extension", "vertical_pull": "Vertical pull", "horizontal_row": "Row",
    "rear_delt": "Rear delt", "elbow_flexion": "Curl", "squat": "Squat", "hinge": "Hinge", "quad_isolation": "Quad / lunge",
    "hamstring_isolation": "Hamstring", "calf": "Calf", "core": "Core",
}


@dataclass(frozen=True)
class Stage:
    name: str
    cue: str
    frames: tuple[int, ...]  # keyframe indices visited in this stage; the last one is held


@dataclass(frozen=True)
class Cues:
    setup: tuple[str, ...]
    execute: tuple[str, ...]
    avoid: tuple[str, ...]
    breathe: str


@dataclass(frozen=True)
class Guide:
    key: str
    name: str
    pattern: str
    keyframes: tuple[Pose, ...]
    stages: tuple[Stage, ...]
    anchor: str
    arms_xy: bool
    plan: str
    overlays: tuple[str, ...]
    cues: Cues
    motion_scope: str  # exercise | family
    cues_scope: str  # exercise | family
    family: str


def C(setup, execute, avoid, breathe) -> Cues:
    return Cues(tuple(setup), tuple(execute), tuple(avoid), breathe)


# ---------------------------------------------------------------- stage plans
# Each plan maps the exercise's two pictogram keyframes (a, b) to an ordered keyframe list and named stages.
# `S(name, cue, *frames)`: the figure moves through `frames` (indices into the keyframe list) and holds on the last.
# A stage whose only frame is the one already shown is a pure hold (used for "Set up").
def S(name: str, cue: str, *frames: int) -> Stage:
    return Stage(name, cue, tuple(frames))


def three(a_name, a_cue, out_name, out_cue, back_name, back_cue):
    return (S(a_name, a_cue, 0), S(out_name, out_cue, 1), S(back_name, back_cue, 0))


def knee_pass(floor: Pose, top: Pose) -> Pose:
    """Deadlift at the knee: bar just past the kneecap, shins vertical, back angle barely changed from the floor position."""
    mid = lerp_pose(floor, top, 0.42)
    return mid.w(sh=90, torso=floor.torso + (top.torso - floor.torso) * 0.3, head=None)


PLANS: dict[str, tuple] = {
    # name: (keyframe order as a function of (a, b), stages)
    "press": (lambda a, b: (a, b), three("Set up", "Shoulder blades back and down, feet planted, load locked out over the shoulders",
                                           "Lower", "Control the weight to the chest; elbows about 45° from the torso",
                                           "Press", "Drive up and slightly back to lock out over the shoulders")),
    "press_from_rack": (lambda a, b: (a, b), three("Rack", "Bar on the front shoulders, trunk braced, ribs down",
                                                     "Press", "Straight up past the face; head comes through at the top",
                                                     "Lower", "Back to the shoulders under control")),
    "dip": (lambda a, b: (b, a), three("Support", "Arms locked, shoulders down, slight forward lean",
                                         "Lower", "Until the upper arms are about parallel to the floor",
                                         "Press", "Back to lockout without flaring the elbows")),
    "fly": (lambda a, b: (b, a), three("Set up", "Slight elbow bend that stays fixed for the whole set",
                                         "Open", "Wide arc until a stretch across the chest, elbows at shoulder height",
                                         "Squeeze", "Back along the same arc; stop just short of touching")),
    "raise": (lambda a, b: (a, b), three("Set up", "Stand tall, soft elbows, shoulders down",
                                           "Raise", "Lead with the elbows out to the side up to shoulder height",
                                           "Lower", "Slowly, two to three seconds down")),
    "extend": (lambda a, b: (a, b), three("Set up", "Upper arms fixed; only the elbows will move",
                                            "Extend", "Straighten the arms fully and squeeze",
                                            "Return", "Back to a full stretch at the elbow, upper arms still")),
    "pull": (lambda a, b: (a, b), three("Reach", "Full hang or reach, shoulders pulled down away from the ears",
                                          "Pull", "Shoulder blades down first, then elbows toward the hips",
                                          "Lower", "All the way back to a straight-arm stretch")),
    "row": (lambda a, b: (a, b), three("Reach", "Arms long, spine neutral, chest up",
                                         "Row", "Elbows back past the torso; squeeze the shoulder blades",
                                         "Lower", "Full stretch without letting the back round")),
    "rear_delt": (lambda a, b: (a, b), three("Reach", "Arms hang in front of the shoulders, soft elbows",
                                               "Sweep", "Out and back until the arms are in line with the shoulders",
                                               "Return", "Slowly, without shrugging")),
    "curl": (lambda a, b: (a, b), three("Set up", "Elbows pinned at the sides, wrists neutral",
                                          "Curl", "Squeeze at the top without moving the upper arm",
                                          "Lower", "Slowly to a straight arm")),
    "squat": (lambda a, b: (b, a), three("Set up", "Weight over the mid-foot, brace, chest up",
                                           "Descend", "Hips back and down; knees track over the toes",
                                           "Drive", "Push the floor away; hips and chest rise together")),
    "deadlift": (lambda a, b: (a, knee_pass(a, b), b),
                 (S("Set up", "Bar over mid-foot, shins to the bar, back flat, shoulders slightly ahead of the bar", 0),
                  S("Break the floor", "Push the floor away; bar straight up along the shins, hips and shoulders rise together", 1),
                  S("Lock out", "Drive the hips through to stand tall; glutes squeezed, no lean back", 2),
                  S("Lower", "Hips back first; bend the knees once the bar passes them", 1, 0))),
    "hinge_from_top": (lambda a, b: (a, b), three("Set up", "Stand tall, knees soft and fixed, load against the thighs",
                                                    "Hinge", "Push the hips back; the load slides down the legs to a hamstring stretch",
                                                    "Stand", "Drive the hips forward; squeeze the glutes at the top")),
    "swing": (lambda a, b: (a, b), three("Hike", "Hinge with a flat back; bell high between the legs",
                                           "Snap", "Hips drive forward; arms are ropes, bell floats to chest height",
                                           "Hinge", "Let the bell fall and hinge as it reaches the thighs")),
    "hip_thrust": (lambda a, b: (a, b), three("Set up", "Upper back on the bench, bar across the hip crease, chin tucked",
                                                "Drive", "Through the heels until torso and thighs are level; squeeze",
                                                "Lower", "Under control, ribs down")),
    "lunge": (lambda a, b: (a, b), three("Stand", "Tall, trunk braced, dumbbells at the sides",
                                           "Lower", "Back knee toward the floor; front knee over the toes",
                                           "Drive", "Through the front foot back to standing")),
    "step_up": (lambda a, b: (a, b), three("Set up", "Whole foot on the box, shin near vertical",
                                             "Step up", "Drive through the top foot; the trailing leg does not push",
                                             "Step down", "Lower under control")),
    "leg_curl": (lambda a, b: (a, b), three("Set up", "Pad just above the heels, hips pressed down",
                                              "Curl", "Heels toward the glutes with control",
                                              "Lower", "Slowly to a straight leg")),
    "nordic": (lambda a, b: (a, b), three("Set up", "Ankles anchored, hips extended, straight from knees to head",
                                            "Lower", "As slowly as possible; hamstrings resist the fall",
                                            "Return", "Catch with the hands, push back lightly, pull with the hamstrings")),
    "calf": (lambda a, b: (a, b), three("Stretch", "Heels dropped below the step to a full stretch",
                                          "Raise", "All the way onto the toes; pause a second",
                                          "Lower", "Slowly, no bounce")),
    "leg_raise": (lambda a, b: (a, b), three("Hang", "Shoulders active, slight tuck of the pelvis",
                                               "Raise", "Legs to at least parallel; curl the pelvis at the top",
                                               "Lower", "Slowly, without swinging")),
    "crunch": (lambda a, b: (a, b), three("Set up", "Rope by the ears, hips still",
                                            "Crunch", "Ribs toward the pelvis — flex the spine, don't pull with the arms",
                                            "Return", "Under control to a tall kneel")),
    "rollout": (lambda a, b: (a, b), three("Set up", "Wheel under the shoulders, ribs down, glutes tight",
                                             "Roll out", "Only as far as the lower back stays flat",
                                             "Pull back", "With the abs, not the hips")),
    "situp": (lambda a, b: (a, b), three("Set up", "Feet hooked, hands light at the chest or ears",
                                           "Sit up", "Curl up one segment at a time",
                                           "Lower", "Slowly; stop if the lower back complains")),
    "pallof": (lambda a, b: (a, b), three("Set up", "Side-on to the cable, handle at the sternum",
                                            "Press out", "Straight out; resist the pull to rotate; hold two seconds",
                                            "Return", "To the sternum under control")),
    "push_up": (lambda a, b: (a, b), three("Plank", "One straight line from head to heels; glutes and abs braced",
                                             "Lower", "Chest to just above the floor; elbows about 45° from the torso",
                                             "Press", "Back to full elbow extension without the hips moving")),
    "leg_press": (lambda a, b: (a, b), three("Set up", "Lower back and hips flat on the pad; feet mid-platform, shoulder width",
                                               "Lower", "Knees to about 90°; the hips stay down on the pad",
                                               "Press", "Through the whole foot; stop just short of locking the knees")),
    "hold": (lambda a, b: (a, b), (S("Hold", "Straight line, glutes and abs braced, breathe steadily", 1),
                                   S("Hold", "Stop the set before the position breaks", 0))),
    "alternate": (lambda a, b: (a, b), (S("Reach", "Lower the opposite arm and leg slowly; low back stays down", 1),
                                        S("Switch", "Return and change sides without the back lifting", 0))),
    "bird_dog": (lambda a, b: (b, a), three("Set up", "Hands under shoulders, knees under hips, spine neutral",
                                              "Reach", "Opposite arm and leg to parallel without tilting the hips; hold",
                                              "Return", "Slowly, pelvis still")),
    "twist": (lambda a, b: (a, b), three("Set up", "Sit tall, slight lean back, spine long",
                                           "Rotate", "Turn the ribcage, not just the arms",
                                           "Return", "Through the centre to the other side")),
}

PATTERN_PLAN = {
    "horizontal_press": "press", "incline_press": "press", "vertical_press": "press_from_rack", "chest_fly": "fly", "lateral_raise": "raise",
    "triceps_extension": "extend", "vertical_pull": "pull", "horizontal_row": "row", "rear_delt": "rear_delt", "elbow_flexion": "curl",
    "squat": "squat", "hinge": "deadlift", "quad_isolation": "extend", "hamstring_isolation": "leg_curl", "calf": "calf", "core": "crunch",
}
# Exercises whose pictogram keyframes don't follow their family's convention, or that need a different staging.
EXERCISE_PLAN = {
    "weighted_dip": "dip", "bench_dip": "dip", "close_grip_bench_press": "press",
    "leg_press": "leg_press", "push_up": "push_up", "decline_push_up": "push_up",
    "romanian_deadlift": "hinge_from_top", "dumbbell_romanian_deadlift": "hinge_from_top", "good_morning": "hinge_from_top",
    "cable_pull_through": "hinge_from_b", "kettlebell_swing": "swing", "barbell_hip_thrust": "hip_thrust",
    "walking_lunge": "lunge", "reverse_lunge": "lunge", "step_up": "step_up", "bulgarian_split_squat": "squat",
    "nordic_curl": "nordic",
    "hanging_leg_raise": "leg_raise", "ab_wheel_rollout": "rollout", "decline_sit_up": "situp", "pallof_press": "pallof",
    "plank": "hold", "side_plank": "hold", "hollow_hold": "hold", "dead_bug": "alternate", "bird_dog": "bird_dog", "russian_twist": "twist",
}
# Variants of plans that only differ in which keyframe is the start.
PLANS["hinge_from_b"] = (lambda a, b: (b, a), PLANS["hinge_from_top"][1])

# ---------------------------------------------------------------- written cues
# Family cues describe the canonical exercise of the family (bench press, overhead press, lat pulldown, barbell row,
# back squat, conventional deadlift...). Per-exercise overrides below replace them where the setup or the risks differ.
FAMILY_CUES: dict[str, Cues] = {
    "horizontal_press": C(
        ["Eyes under the bar; shoulder blades pulled back and down; feet flat on the floor.",
         "Grip width so the forearms are vertical at the bottom of the press.",
         "A slight natural arch is fine; the hips stay on the bench."],
        ["Lower under control to the lower chest, elbows about 45° from the torso.",
         "Press up and slightly back so the bar locks out over the shoulders.",
         "Keep the wrists stacked over the elbows."],
        ["Bouncing the bar off the chest.", "Elbows flared straight out to the sides.", "Lifting the hips off the bench."],
        "Breathe in on the way down, out as you press."),
    "incline_press": C(
        ["Bench at 30–45°; shoulder blades back and down; feet flat.",
         "Grip so the forearms are vertical with the bar at the upper chest."],
        ["Lower to the upper chest / collarbone line.", "Press up and slightly back to lock out over the shoulders."],
        ["Flaring the elbows straight out.", "Bouncing off the chest.", "Sliding down the bench."],
        "Breathe in on the way down, out as you press."),
    "vertical_press": C(
        ["Bar on the front shoulders, grip just outside shoulder width, elbows slightly ahead of the bar.",
         "Feet hip width; squeeze the glutes and brace so the ribs stay down."],
        ["Press straight up; move the head back slightly so the bar clears the face.",
         "Lock out with the bar over the mid-foot and the head back through under the bar.",
         "Lower to the shoulders under control."],
        ["Leaning back and arching the lower back.", "Pressing forward around the chin.", "Stopping short of a full lockout."],
        "Brace before each press; exhale through the lockout."),
    "chest_fly": C(
        ["Light load; a slight elbow bend that stays fixed for the whole set.",
         "Shoulder blades back and down against the bench or pad."],
        ["Open the arms in a wide arc until you feel a stretch across the chest, elbows no lower than the shoulders.",
         "Squeeze back along the same arc; stop just short of the weights touching."],
        ["Bending and straightening the elbows mid-rep (it becomes a press).", "Dropping the arms far below the shoulders.",
         "Heavy loads — this is an isolation movement."],
        "Inhale as the arms open, exhale as they close."),
    "lateral_raise": C(
        ["Stand tall with a slight forward lean, soft elbows, light dumbbells.", "Shoulders down away from the ears."],
        ["Raise out to the sides, leading with the elbows, until the upper arms are about parallel to the floor.",
         "Pause, then lower slowly over two to three seconds."],
        ["Shrugging or swinging the weight up.", "Raising above shoulder height.", "Rocking the torso to heave the weight."],
        "Exhale on the raise, inhale as you lower."),
    "triceps_extension": C(
        ["Upper arms fixed and pointing one way for the whole set; only the elbows move.", "Shoulders down, trunk braced."],
        ["Extend until the arms are straight and squeeze the triceps.", "Return under control to a full stretch at the elbow."],
        ["Letting the elbows drift or flare.", "Using the shoulders or torso to swing the weight.", "Snapping the elbows into lockout."],
        "Exhale as you extend."),
    "vertical_pull": C(
        ["Grip slightly wider than the shoulders; thighs locked under the pad.", "Chest up, slight lean back, shoulders down."],
        ["Start the pull by drawing the shoulder blades down, then drive the elbows toward the hips.",
         "Bring the bar to the upper chest and pause.", "Return to a full stretch with control."],
        ["Pulling behind the neck.", "Leaning far back and rowing the weight.", "Short reps that never reach full extension."],
        "Exhale as you pull, inhale on the return."),
    "horizontal_row": C(
        ["Hinge at the hips to about 45°, knees soft, spine neutral.", "Grip just outside the legs, arms long, shoulders over the bar."],
        ["Pull the bar to the lower ribs, elbows close to the body.", "Squeeze the shoulder blades together at the top.",
         "Lower to a full stretch without letting the back round."],
        ["Jerking the torso upright to move the weight.", "Rounding the lower back.", "Shrugging the shoulders toward the ears."],
        "Exhale as you row."),
    "rear_delt": C(
        ["Light weight; hinge forward or set the pad so the arms hang in front of the shoulders.", "Soft elbows, fixed for the set."],
        ["Sweep the arms out and back until they are in line with the shoulders.", "Pause, then return slowly."],
        ["Momentum or heavy loads.", "Shrugging — the upper traps take over.", "Rising out of the hinge."],
        "Exhale as the arms open."),
    "elbow_flexion": C(
        ["Elbows pinned at the sides, shoulders back, wrists neutral.", "Stand or sit tall."],
        ["Curl until the forearm is fully flexed and squeeze.", "Lower slowly to a straight arm."],
        ["Swinging the torso or driving the elbows forward.", "Half reps at the bottom.", "Curling with the wrists."],
        "Exhale as you curl."),
    "squat": C(
        ["Bar over the mid-foot; feet about shoulder width with the toes turned out slightly.",
         "Big breath, brace the trunk, chest up, eyes forward."],
        ["Sit down and back; the knees travel over the toes, in line with the feet.",
         "Go to at least parallel (hip crease level with the knee) as long as the spine stays neutral.",
         "Drive the floor away; hips and chest rise at the same rate."],
        ["Knees collapsing inward.", "Heels lifting or the weight shifting onto the toes.",
         "The lower back rounding at the bottom — stop higher if it does."],
        "Breathe and brace at the top; exhale as you stand."),
    "hinge": C(
        ["Bar over the mid-foot, about an inch from the shins.", "Grip outside the legs; bring the shins to the bar; shoulders slightly ahead of it.",
         "Chest up, back flat, lats tight."],
        ["Push the floor away; the bar travels straight up, brushing the legs.",
         "Hips and shoulders rise at the same rate until the bar passes the knees.",
         "Finish standing tall with the glutes squeezed; don't lean back.",
         "Return by pushing the hips back first, then bending the knees once the bar clears them."],
        ["Rounding the lower back.", "Letting the bar drift forward away from the legs.", "Jerking the bar off the floor."],
        "Big breath and brace before each pull; exhale at the top."),
    "quad_isolation": C(
        ["Set up so the knee tracks straight over the toes.", "Trunk tall and braced."],
        ["Move through a full, controlled range with the knee in line with the foot.", "Pause at the hardest point, then return under control."],
        ["The knee caving inward.", "Momentum."],
        "Exhale on the effort."),
    "hamstring_isolation": C(
        ["Pad just above the heels; hips pressed into the bench or seat.", "Hold the handles; the trunk stays still."],
        ["Curl the heels toward the glutes with control.", "Lower slowly to a straight leg."],
        ["Lifting the hips to cheat the weight up.", "Fast, bouncing reps."],
        "Exhale as you curl."),
    "calf": C(
        ["Balls of the feet on the edge, heels free to drop; knees straight (or fixed at 90° when seated).", "Hold something for balance."],
        ["Drop the heels to a full stretch.", "Rise all the way onto the toes and pause for a second.", "Lower slowly."],
        ["Bouncing out of the stretch.", "Partial reps from the middle of the range."],
        "Exhale as you rise."),
    "core": C(
        ["Neutral spine: ribs down, pelvis level.", "Move slowly; the trunk resists motion rather than creating it."],
        ["Brace the abdomen as if about to be nudged.", "Keep the lower-back position constant while the limbs move."],
        ["Holding your breath for the whole set.", "Letting the lower back arch or round to finish a rep."],
        "Breathe steadily; don't hold your breath."),
}
DEFAULT_CUES = C(
    ["Set up stable: feet planted, trunk braced, joints stacked over each other."],
    ["Move through the range you can control; pause briefly at each end."],
    ["Momentum, bouncing, or anything that hurts."],
    "Exhale on the effort.")

EXERCISE_CUES: dict[str, Cues] = {
    # The family text *is* the write-up of these canonical lifts, so they count as exercise-specific.
    "barbell_bench_press": FAMILY_CUES["horizontal_press"],
    "incline_barbell_press": FAMILY_CUES["incline_press"],
    "dumbbell_fly": FAMILY_CUES["chest_fly"],
    "dumbbell_lateral_raise": FAMILY_CUES["lateral_raise"],
    "dumbbell_overhead_extension": FAMILY_CUES["triceps_extension"],
    "dumbbell_rear_delt_fly": FAMILY_CUES["rear_delt"],
    "barbell_curl": FAMILY_CUES["elbow_flexion"],
    "dumbbell_curl": FAMILY_CUES["elbow_flexion"],
    "lying_leg_curl": FAMILY_CUES["hamstring_isolation"],
    "standing_calf_raise": FAMILY_CUES["calf"],
    # presses
    "dumbbell_bench_press": C(
        ["Kick the dumbbells up from the knees; start locked out over the chest.", "Shoulder blades back and down; feet flat."],
        ["Lower to the sides of the chest, elbows about 45° from the torso.", "Press up and slightly inward to lock out over the shoulders."],
        ["Flaring the elbows to shoulder height.", "Clanging the dumbbells together at the top.", "Lifting the hips."],
        "Breathe in on the way down, out as you press."),
    "push_up": C(
        ["Hands slightly wider than the shoulders, under the chest; body one straight line from head to heels.", "Glutes and abs braced."],
        ["Lower the chest to just above the floor, elbows about 45° from the torso.", "Press back to full elbow extension."],
        ["Hips sagging or piking up.", "The head poking forward.", "Elbows flared straight out."],
        "Breathe in on the way down, out as you press."),
    "decline_push_up": C(
        ["Feet on a bench, hands under the shoulders; body one straight line from head to heels.", "Glutes and abs braced."],
        ["Lower until the head is just above the floor, elbows about 45° from the torso.", "Press back to full extension."],
        ["Hips sagging or piking up.", "Letting the head drop first."],
        "Breathe in on the way down, out as you press."),
    "weighted_dip": C(
        ["Arms locked on the bars, belt hanging in front; shoulders down.", "Slight forward lean; knees bent, feet crossed."],
        ["Lower until the upper arms are about parallel to the floor.", "Press back up to lockout."],
        ["Dropping below the point where the front of the shoulder pinches.", "Flaring the elbows wide.", "Swinging."],
        "Breathe in on the way down, out as you press."),
    "bench_dip": C(
        ["Hands on the bench edge beside the hips, fingers forward; feet out in front.", "Hips close to the bench, shoulders down."],
        ["Lower until the upper arms are about parallel to the floor.", "Press back up to straight arms."],
        ["Going so deep the front of the shoulder pinches.", "Shrugging the shoulders up."],
        "Breathe in on the way down, out as you press."),
    "overhead_press": FAMILY_CUES["vertical_press"],
    "dumbbell_shoulder_press": C(
        ["Seated with the back against the pad; dumbbells at shoulder height, palms forward.", "Feet planted, ribs down."],
        ["Press up to lockout over the shoulders.", "Lower until the dumbbells are at about ear level."],
        ["Arching off the backrest.", "Pressing the dumbbells out to the sides."],
        "Exhale as you press."),
    "standing_dumbbell_press": C(
        ["Dumbbells at shoulder height, palms forward; feet hip width.", "Glutes and abs braced so the ribs stay down."],
        ["Press straight up to lockout over the shoulders.", "Lower until the dumbbells are at about ear level."],
        ["Leaning back and arching the lower back.", "Pressing the dumbbells out to the sides."],
        "Brace before each press; exhale through the lockout."),
    "seated_dumbbell_press": C(
        ["Seated with the back against the pad; dumbbells at shoulder height, palms forward.", "Feet planted, ribs down."],
        ["Press up to lockout over the shoulders.", "Lower until the dumbbells are at about ear level."],
        ["Arching off the backrest.", "Pressing the dumbbells out to the sides."],
        "Exhale as you press."),
    "arnold_press": C(
        ["Seated, back against the pad; dumbbells in front of the shoulders with the palms facing you."],
        ["Press up while turning the palms to face forward; finish locked out overhead.", "Reverse the turn on the way down."],
        ["Arching off the backrest.", "Rushing the rotation."],
        "Exhale as you press."),
    # triceps
    "skullcrusher": C(
        ["Lie on the bench; bar locked out over the face with the upper arms vertical or tilted slightly back."],
        ["Bend only the elbows to lower the bar toward the forehead or just behind the head.", "Extend back to lockout without moving the upper arms."],
        ["Flaring the elbows.", "Letting the upper arms drift toward the hips (it becomes a press).", "Going heavy enough to lose control near the face."],
        "Exhale as you extend."),
    "cable_pushdown": C(
        ["Elbows pinned at the sides, slight forward lean, handle at chest height."],
        ["Push down until the arms are straight and squeeze.", "Return until the forearms are just above parallel."],
        ["Elbows drifting forward or out.", "Leaning on the weight with the body."],
        "Exhale as you extend."),
    "close_grip_bench_press": C(
        ["Grip at about shoulder width (not narrower); shoulder blades back and down; feet flat."],
        ["Lower to the lower chest with the elbows tucked close to the torso.", "Press up to lockout, keeping the wrists straight."],
        ["A very narrow grip that strains the wrists.", "Bouncing off the chest.", "Elbows flaring."],
        "Breathe in on the way down, out as you press."),
    # pulls
    "pull_up": C(
        ["Overhand grip slightly wider than the shoulders; dead hang with the shoulders pulled down.", "Brace the trunk; legs still."],
        ["Drive the elbows down to pull the chest toward the bar; chin clears the bar.", "Lower all the way to a straight-arm hang."],
        ["Kipping or swinging.", "Half reps.", "Craning the neck to clear the bar."],
        "Exhale as you pull."),
    "chin_up": C(
        ["Underhand grip at shoulder width; dead hang with the shoulders pulled down.", "Brace the trunk; legs still."],
        ["Pull the chest toward the bar; chin clears the bar.", "Lower all the way to a straight-arm hang."],
        ["Kipping or swinging.", "Half reps."],
        "Exhale as you pull."),
    "weighted_pull_up": C(
        ["Load on a dip belt (or a dumbbell between the feet) only once strict bodyweight reps are solid.", "Dead hang, shoulders pulled down."],
        ["Drive the elbows down; chin clears the bar.", "Lower all the way to a straight-arm hang."],
        ["Swinging the load.", "Half reps."],
        "Exhale as you pull."),
    "lat_pulldown": FAMILY_CUES["vertical_pull"],
    "straight_arm_pulldown": C(
        ["Slight hinge; arms nearly straight with soft elbows; bar at about eye level."],
        ["Sweep the bar down to the thighs with the arms straight; feel the lats work.", "Return under control."],
        ["Bending the elbows into a pushdown.", "Rounding the back."],
        "Exhale as you pull down."),
    "kneeling_cable_pulldown": C(
        ["Kneel tall facing the stack; handles overhead; shoulders down."],
        ["Pull the elbows down and back toward the hips; handles to the shoulders.", "Return to a full stretch."],
        ["Leaning back and rowing.", "Shrugging."],
        "Exhale as you pull."),
    "barbell_row": FAMILY_CUES["horizontal_row"],
    "pendlay_row": C(
        ["Torso parallel to the floor; bar on the floor at the start of every rep; grip wider than the shoulders."],
        ["Pull hard to the lower chest, elbows out and back.", "Lower to a dead stop on the floor each rep."],
        ["Lifting the torso during the pull.", "Rounding the back."],
        "Exhale as you row."),
    "t_bar_row": C(
        ["Chest up, hinge to about 45°, knees soft; handles gripped with arms long."],
        ["Pull the handles to the stomach; squeeze the shoulder blades.", "Lower to a full stretch."],
        ["Rounding the back.", "Jerking with the hips."],
        "Exhale as you row."),
    "chest_supported_row": C(
        ["Chest flat on the pad; arms long; feet planted."],
        ["Pull the elbows back past the torso; squeeze the shoulder blades.", "Lower to a full stretch."],
        ["Lifting the chest off the pad.", "Shrugging."],
        "Exhale as you row."),
    "seated_cable_row": C(
        ["Feet on the plate, knees soft; sit tall with the arms long."],
        ["Pull the handle to the stomach with the elbows close and the chest up.", "Return to a controlled stretch without rounding."],
        ["Rocking the torso back and forth.", "Shrugging."],
        "Exhale as you row."),
    "single_arm_dumbbell_row": C(
        ["Knee and hand on the bench; back flat and parallel to the floor."],
        ["Row the dumbbell to the hip with the elbow close to the body.", "Lower to a full stretch."],
        ["Twisting the torso to lift the weight.", "Rounding the back."],
        "Exhale as you row."),
    "inverted_row": C(
        ["Under a bar, body straight from heels to head, arms long; glutes tight."],
        ["Pull the chest to the bar; squeeze the shoulder blades.", "Lower fully."],
        ["Hips sagging.", "Chin poking toward the bar."],
        "Exhale as you row."),
    "face_pull": C(
        ["Rope at face height; step back to tension; thumbs pointing toward you."],
        ["Pull toward the face with the elbows high and wide; finish with the hands beside the ears and the shoulder blades squeezed.",
         "Return under control."],
        ["Pulling to the chest with the elbows low.", "Leaning back to move the weight."],
        "Exhale as you pull."),
    "reverse_pec_deck": C(
        ["Chest against the pad; handles in front at shoulder height; slight elbow bend."],
        ["Sweep the arms back until they are in line with the shoulders.", "Return slowly."],
        ["Shrugging.", "Heavy loads with momentum."],
        "Exhale as the arms open."),
    # curls
    "hammer_curl": C(
        ["Neutral grip (thumbs up); elbows pinned at the sides."],
        ["Curl until the forearm is fully flexed.", "Lower slowly to a straight arm."],
        ["Swinging the torso.", "Elbows drifting forward."],
        "Exhale as you curl."),
    "preacher_curl": C(
        ["Upper arms flat on the pad, armpits at the top edge; grip the bar with the wrists neutral."],
        ["Curl to full flexion and squeeze.", "Lower under control to a nearly straight arm."],
        ["Slamming into full extension at the bottom under load.", "Lifting the upper arms off the pad."],
        "Exhale as you curl."),
    "incline_dumbbell_curl": C(
        ["Bench at about 45°; arms hang straight down behind the torso; shoulders back."],
        ["Curl without moving the upper arm.", "Lower slowly to a full stretch."],
        ["Letting the shoulders roll forward.", "Swinging."],
        "Exhale as you curl."),
    # squat family
    "back_squat": FAMILY_CUES["squat"],
    "front_squat": C(
        ["Bar on the front shoulders with the elbows high; fingertips under the bar.", "Feet shoulder width, toes slightly out; brace."],
        ["Sit straight down keeping the torso upright and the elbows up.", "Knees travel forward over the toes.",
         "Drive up; the elbows stay high so the bar can't roll forward."],
        ["Elbows dropping (the bar rolls off).", "Heels lifting.", "Knees caving inward."],
        "Breathe and brace at the top; exhale as you stand."),
    "goblet_squat": C(
        ["Hold the dumbbell vertically against the chest, elbows pointing down.", "Feet a little wider than the shoulders, toes out."],
        ["Sit down between the heels; the elbows track inside the knees.", "Chest tall; drive up through the whole foot."],
        ["Rounding forward.", "Knees caving inward."],
        "Breathe and brace at the top; exhale as you stand."),
    "leg_press": C(
        ["Feet shoulder width in the middle of the platform; lower back and hips flat on the pad.", "Release the safeties with the knees slightly bent."],
        ["Lower until the knees reach about 90°, or just before the hips start to roll off the pad.",
         "Press through the whole foot; stop just short of locking the knees."],
        ["The hips lifting off the pad at the bottom.", "Locking the knees hard at the top.", "Knees caving inward."],
        "Breathe in as you lower, out as you press."),
    "hack_squat": C(
        ["Shoulders under the pads, back flat on the pad; feet shoulder width in the middle of the platform."],
        ["Lower under control to parallel or a little below.", "Drive through the whole foot; knees track over the toes."],
        ["Heels lifting.", "Bottoming out with a rounded lower back."],
        "Breathe in as you lower, out as you drive."),
    "bulgarian_split_squat": C(
        ["Rear foot on the bench; front foot far enough forward that the shin stays near vertical at the bottom.",
         "Slight forward lean from the hips; trunk braced."],
        ["Lower straight down until the front thigh is about parallel.", "Drive through the front foot; the weight stays on the front leg."],
        ["Front knee caving inward.", "Pushing off the rear foot.", "Bouncing at the bottom."],
        "Breathe in as you lower, out as you drive."),
    # hinge family
    "deadlift": FAMILY_CUES["hinge"],
    "trap_bar_deadlift": C(
        ["Stand in the centre of the bar; grip the handles with the shins near vertical.", "Hips a little higher than a squat; chest up, back flat."],
        ["Push the floor away and stand up in one motion.", "Finish tall; don't lean back.", "Lower by pushing the hips back, then bending the knees."],
        ["Rounding the back.", "Squatting the weight with the hips too low."],
        "Big breath and brace before each pull; exhale at the top."),
    "romanian_deadlift": C(
        ["Start standing with the bar at the hips; knees slightly bent and fixed.", "Shoulders back; pull the bar into the thighs with the lats."],
        ["Push the hips back; the bar slides down the thighs.", "Lower until you feel a strong hamstring stretch, usually around mid-shin, with a flat back.",
         "Drive the hips forward to stand and squeeze the glutes."],
        ["Bending the knees more as you lower (it becomes a squat).", "Rounding the lower back.", "Letting the bar drift away from the legs."],
        "Breathe in at the top, brace, and exhale as you stand."),
    "dumbbell_romanian_deadlift": C(
        ["Dumbbells in front of the thighs; knees slightly bent and fixed; shoulders back."],
        ["Push the hips back; the dumbbells slide down the thighs.", "Lower to a strong hamstring stretch with a flat back, then drive the hips forward."],
        ["Bending the knees more as you lower.", "Rounding the lower back.", "Letting the dumbbells drift away from the legs."],
        "Breathe in at the top, brace, and exhale as you stand."),
    "good_morning": C(
        ["Bar on the upper back as for a squat; light load.", "Knees soft and fixed; feet hip width."],
        ["Hinge the hips back until the torso is near parallel or the hamstrings stop you.", "Back flat, bar over the mid-foot.",
         "Drive the hips forward to stand."],
        ["Rounding the back.", "Going heavy — this is a hamstring exercise, not a max lift."],
        "Breathe in at the top, brace, and exhale as you stand."),
    "kettlebell_swing": C(
        ["Bell a foot in front; hinge, grip it, and hike it back high between the legs.", "Flat back, shins near vertical, shoulders packed."],
        ["Snap the hips forward; the arms are ropes and the bell floats to chest height.", "Stand tall at the top with the glutes squeezed and ribs down.",
         "Let the bell swing back and hinge again as it reaches the thighs."],
        ["Squatting the swing (lots of knee bend).", "Lifting with the arms or shoulders.", "Leaning back at the top."],
        "Exhale sharply at the top of each swing."),
    "cable_pull_through": C(
        ["Face away from a low pulley with the rope between the legs; step forward to tension it.", "Soft knees, flat back."],
        ["Hinge back until the hamstrings stretch.", "Drive the hips forward to stand tall and squeeze the glutes."],
        ["Pulling with the arms.", "Leaning back at the top."],
        "Exhale as you stand."),
    "barbell_hip_thrust": C(
        ["Upper back on the bench edge; padded bar across the hip crease.", "Feet placed so the shins are vertical at the top."],
        ["Drive through the heels until the torso and thighs are level.", "Chin tucked, ribs down; squeeze the glutes at the top.", "Lower under control."],
        ["Over-arching the lower back at the top.", "Pushing through the toes."],
        "Exhale as you drive up."),
    # quads / lunges
    "leg_extension": C(
        ["Knee joint lined up with the machine's pivot; pad just above the ankles; back against the seat."],
        ["Extend fully and pause for a second.", "Lower slowly without letting the weight stack slam."],
        ["Swinging the weight up.", "Lifting the hips off the seat."],
        "Exhale as you extend."),
    "walking_lunge": C(
        ["Dumbbells at the sides; stand tall.", "Step far enough that the front shin stays near vertical at the bottom."],
        ["Lower until the back knee nearly touches the floor; front knee over the toes.", "Drive through the front foot and step straight into the next lunge."],
        ["Front knee caving inward.", "Leaning forward.", "Dropping the back knee onto the floor."],
        "Breathe in as you lower, out as you drive."),
    "reverse_lunge": C(
        ["Dumbbells at the sides; stand tall, trunk braced."],
        ["Step back and lower until the back knee nearly touches the floor; front shin near vertical.", "Push through the front foot to return."],
        ["Front knee caving inward.", "Leaning forward."],
        "Breathe in as you lower, out as you drive."),
    "step_up": C(
        ["Whole foot on the box; shin near vertical; box height so the thigh is about parallel."],
        ["Drive through the top foot to stand tall; the trailing leg does not push off.", "Lower under control."],
        ["Pushing off the bottom foot.", "The knee caving inward."],
        "Exhale as you step up."),
    # hamstrings / calves
    "nordic_curl": C(
        ["Kneel with the ankles anchored; hips extended; body straight from the knees to the head."],
        ["Lower forward as slowly as you can, the hamstrings resisting the fall.",
         "Catch yourself with the hands, push back lightly, and pull up with the hamstrings."],
        ["Bending at the hips (sitting back).", "Dropping fast."],
        "Exhale as you lower."),
    "seated_calf_raise": C(
        ["Knees under the pad at 90°; balls of the feet on the edge."],
        ["Drop the heels to a full stretch.", "Rise all the way onto the toes and pause."],
        ["Bouncing out of the stretch.", "Partial reps."],
        "Exhale as you rise."),
    # core
    "hanging_leg_raise": C(
        ["Dead hang with the shoulders active; slight backward tilt of the pelvis."],
        ["Raise the legs (bent or straight) until the thighs are at least parallel; curl the pelvis at the top.", "Lower slowly without swinging."],
        ["Swinging.", "Arching the lower back."],
        "Exhale as you raise."),
    "cable_crunch": C(
        ["Kneel facing the stack; rope held beside the ears; hips still."],
        ["Crunch the ribs toward the pelvis — flex the spine.", "Return under control to a tall kneel."],
        ["Pulling with the arms.", "Sitting back onto the heels to move the weight."],
        "Exhale as you crunch."),
    "ab_wheel_rollout": C(
        ["Kneel with the wheel under the shoulders; ribs down, glutes tight."],
        ["Roll out as far as you can keep the lower back from arching.", "Pull back with the abs, not the hips."],
        ["The lower back arching or the hips sagging.", "Going further than you can control."],
        "Exhale as you roll out."),
    "decline_sit_up": C(
        ["Feet hooked under the pads; hands light at the chest or ears."],
        ["Lower slowly.", "Curl up one segment at a time without pulling on the neck."],
        ["Yanking on the head or neck.", "Arching the lower back on the way down."],
        "Exhale as you sit up."),
    "pallof_press": C(
        ["Stand side-on to the cable at chest height; handle at the sternum; feet shoulder width."],
        ["Press the handle straight out and hold for two seconds, resisting the pull to rotate.", "Bring it back to the sternum."],
        ["Rotating or leaning toward the stack.", "Shrugging."],
        "Breathe steadily; don't hold your breath."),
    "plank": C(
        ["Forearms under the shoulders; body a straight line from head to heels."],
        ["Squeeze the glutes, brace the abs, ribs down; breathe steadily.", "Hold with a perfect line; stop before the hips sag."],
        ["Hips sagging or piking up.", "Holding your breath."],
        "Breathe steadily; don't hold your breath."),
    "side_plank": C(
        ["Elbow under the shoulder; feet stacked or staggered; hips lifted and stacked."],
        ["Hold a straight line from head to feet.", "Breathe steadily; stop before the hips drop."],
        ["Hips dropping or rolling back.", "Holding your breath."],
        "Breathe steadily; don't hold your breath."),
    "hollow_hold": C(
        ["On the back; lower back pressed into the floor; arms and legs extended."],
        ["Shoulder blades off the floor.", "Lower the legs only as far as the back stays pressed down."],
        ["The lower back lifting off the floor.", "Holding your breath."],
        "Breathe steadily; don't hold your breath."),
    "dead_bug": C(
        ["On the back; arms up, knees over the hips at 90°; lower back pressed into the floor."],
        ["Lower the opposite arm and leg slowly toward the floor.", "Return and switch sides."],
        ["The lower back lifting off the floor.", "Rushing."],
        "Exhale as the limbs lower."),
    "bird_dog": C(
        ["Hands under the shoulders, knees under the hips; spine neutral."],
        ["Reach the opposite arm and leg to parallel without tilting the hips; hold two seconds.", "Return slowly."],
        ["Arching the back or lifting the leg above the hip.", "Rotating the pelvis."],
        "Breathe steadily; don't hold your breath."),
    "russian_twist": C(
        ["Sit tall with a slight lean back; spine long; feet on the floor if needed."],
        ["Rotate the ribcage, not just the arms.", "Move through the centre to the other side with control."],
        ["Rounding the back.", "Fast, jerky reps."],
        "Breathe steadily; don't hold your breath."),
}


# ---------------------------------------------------------------- assembly
LOADED = {"barbell", "barbellNarrow", "trapBar", "dumbbell", "dumbbellVertical", "dumbbellFirst", "kettlebell"}


def overlays_for(m: Motion, order: tuple[Pose, ...]) -> tuple[str, ...]:
    out = ["joints"]
    a = m.a
    anchor = m.resolved_anchor()
    if a.impl != "none" or not a.grounded:
        out.append("path")
    if a.grounded and a.floor and anchor in ("foot", "foot2") and a.impl in LOADED and not ({"seat", "bench", "inclineBench"} & set(a.props)):
        out.append("midfoot")
    return tuple(out)


def guide_for(key: str, name: str, pattern: str) -> Guide:
    m = motion_for(key, pattern)
    plan_key = EXERCISE_PLAN.get(key) or PATTERN_PLAN.get(pattern, "extend")
    order_fn, stages = PLANS[plan_key]
    order = tuple(order_fn(m.a, m.b))
    cues = EXERCISE_CUES.get(key)
    cues_scope = "exercise" if cues else "family"
    cues = cues or FAMILY_CUES.get(pattern, DEFAULT_CUES)
    return Guide(key, name, pattern, order, tuple(stages), m.resolved_anchor(), m.arms_xy, plan_key, overlays_for(m, order), cues,
                 "exercise" if key in TABLE else "family", cues_scope, FAMILY_NAMES.get(pattern, pattern.replace("_", " ").capitalize()))


def all_guides() -> list[Guide]:
    return [guide_for(k, n, p) for k, n, p in all_exercises()]


# ---------------------------------------------------------------- checks
def check_guides() -> list[str]:
    issues = []
    for k in list(EXERCISE_PLAN) + list(EXERCISE_CUES):
        if k not in {e[0] for e in all_exercises()}:
            issues.append(f"guide key not in seed: {k}")
    seed_patterns = {e[2] for e in all_exercises()}
    for p in list(PATTERN_PLAN) + list(FAMILY_CUES) + list(FAMILY_NAMES):
        if p not in seed_patterns:
            issues.append(f"plan pattern not in seed: {p}")
    for g in all_guides():
        n = len(g.keyframes)
        for s in g.stages:
            for f in s.frames:
                if not 0 <= f < n:
                    issues.append(f"{g.key}: stage {s.name} frame {f} out of range")
        # every consecutive leg of the loop must pass the same plausibility checks as a pictogram
        order = [g.stages[-1].frames[-1]]
        for s in g.stages:
            order += list(s.frames)
        for i, j in zip(order, order[1:]):
            if i == j:
                continue
            leg = Motion(g.keyframes[i], g.keyframes[j], g.anchor, g.arms_xy)
            tag = f"{g.key} leg {i}->{j}"
            issues += com_check(leg, tag) + floor_check(leg, tag) + wrap_check(leg, tag)
        if not (g.cues.setup and g.cues.execute and g.cues.avoid and g.cues.breathe):
            issues.append(f"{g.key}: incomplete cues")
    return issues


# ---------------------------------------------------------------- export
def guide_json(g: Guide) -> dict:
    return {"key": g.key, "name": g.name, "pattern": g.pattern, "family": g.family, "plan": g.plan,
            "keyframes": [pose_json(p) for p in g.keyframes], "stages": [{"name": s.name, "cue": s.cue, "frames": list(s.frames)} for s in g.stages],
            "anchor": g.anchor, "armsXY": g.arms_xy, "overlays": list(g.overlays),
            "cues": {"setup": list(g.cues.setup), "execute": list(g.cues.execute), "avoid": list(g.cues.avoid), "breathe": g.cues.breathe},
            "motionScope": g.motion_scope, "cuesScope": g.cues_scope}


def export_json() -> list[dict]:
    return [guide_json(g) for g in all_guides()]


def swift_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def swift_list(items, indent: str) -> str:
    return "[\n" + "".join(f"{indent}    {swift_str(s)},\n" for s in items) + f"{indent}]"


def cues_swift(c: Cues, indent: str) -> str:
    return (f"Cues(setUp: {swift_list(c.setup, indent)},\n{indent}     execute: {swift_list(c.execute, indent)},\n"
            f"{indent}     avoid: {swift_list(c.avoid, indent)},\n{indent}     breathing: {swift_str(c.breathe)})")


def export_swift() -> str:
    L = ["    // Generated by tools/pictograms/guides.py — edit that file and rerun `python3 motions.py guides`."]
    # 1. demonstration: keyframes in stage order + plan + overlays, per exercise
    L += ["    static func demonstration(exerciseKey key: String, pattern: String) -> Demonstration {", "        switch key {"]
    for g in all_guides():
        kf = ",\n                     ".join(pose_swift(p) for p in g.keyframes)
        ov = ", ".join("." + o for o in g.overlays)
        L.append(f'        case "{g.key}":\n            return Demonstration(keyframes: [{kf}],\n'
                 f'                   anchor: .{g.anchor}, armsXY: {"true" if g.arms_xy else "false"}, plan: "{g.plan}", overlays: [{ov}],\n'
                 f'                   motionScope: .{g.motion_scope})')
    fallback = guide_for("__custom__", "", "__none__")
    kf = ",\n                     ".join(pose_swift(p) for p in fallback.keyframes)
    L += ["        default:", f"            return Demonstration(keyframes: [{kf}],",
          f'                   anchor: .{fallback.anchor}, armsXY: {"true" if fallback.arms_xy else "false"}, plan: "{fallback.plan}", '
          f'overlays: [{", ".join("." + o for o in fallback.overlays)}],', "                   motionScope: .family)", "        }", "    }", ""]
    # 2. stage plans
    L += ["    static func stages(plan: String) -> [Stage] {", "        switch plan {"]
    for name, (_, stages) in PLANS.items():
        body = ", ".join(f"Stage(name: {swift_str(s.name)}, cue: {swift_str(s.cue)}, frames: [{', '.join(map(str, s.frames))}])" for s in stages)
        L.append(f'        case "{name}": return [{body}]')
    L += ["        default: return []", "        }", "    }", ""]
    # 3. cues: exercise overrides, then family, then default
    L += ["    static func cues(exerciseKey key: String, pattern: String) -> (Cues, Scope) {", "        switch key {"]
    for key, c in EXERCISE_CUES.items():
        L.append(f'        case "{key}":\n            return ({cues_swift(c, "                   ")}, .exercise)')
    L += ["        default: break", "        }", "        switch pattern {"]
    for pattern, c in FAMILY_CUES.items():
        L.append(f'        case "{pattern}":\n            return ({cues_swift(c, "                   ")}, .family)')
    L += ["        default:", f'            return ({cues_swift(DEFAULT_CUES, "                   ")}, .family)', "        }", "    }", ""]
    # 4. family display names
    L += ["    static func familyName(pattern: String) -> String {", "        switch pattern {"]
    for p, n in FAMILY_NAMES.items():
        L.append(f'        case "{p}": return {swift_str(n)}')
    L += ['        default: return pattern.replacingOccurrences(of: "_", with: " ").capitalized', "        }", "    }"]
    return "\n".join(L)


from motions import REPO  # noqa: E402

SWIFT_FILE = REPO / "ios" / "WorkoutApp" / "Sources" / "ExerciseGuide.swift"
BEGIN, END = "    // MARK: - Table (generated)", "    // MARK: - End table"


def write_swift():
    src = SWIFT_FILE.read_text()
    i, j = src.index(BEGIN) + len(BEGIN), src.index(END)
    SWIFT_FILE.write_text(src[:i] + "\n\n" + export_swift() + "\n\n" + src[j:])
    print(f"wrote table into {SWIFT_FILE.relative_to(REPO)}")
