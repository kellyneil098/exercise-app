# Workout Tracker — Implementation Spec

**Version:** 2.0 — native iOS + hosted backend (supersedes 1.1)
**Audience:** an autonomous coding agent implementing this end to end.

### What changed from 1.1

- **Platform:** native iOS app (Swift 6, SwiftUI, iOS 17+), not a PWA. §7, §10, §11, §16.
- **Backend:** FastAPI + Postgres stays, as **pure storage + sync + identity**. All recommendation and progression logic runs on-device. §10, §11.
- **Users:** generalized from "a pair" to **N users with explicit read-only shares**. Still invite-only. §2.
- **Auth:** Sign in with Apple against a server-side allowlist; session token in the Keychain. §2.
- **Engine fixes** found reviewing 1.1 against the seed JSON: slot tables now match `movement_patterns.json` (core supersetted every day, `chest_fly` as push slot 7); leg day no longer double-books `hinge`; the time-budget loop no longer drops core when a more expensive slot doesn't fit; non-loadable exercises are barred from the heavy slot; warm-up weights, timed-core progression, `rep_seconds` precedence and a running-volume ceiling are now specified. §3.3, §4.1, §4.2, §5.2, §6.
- **New §8 Design & aesthetic.** The app must look and feel like a first-party Apple app with a luxury-brand sensibility; the section gives rules, not adjectives.
- Rebaseline snapshot column removed (derived from history instead). §4.4.

---

## 1. Summary

A small-group training app for **strength training and running only**. The core loop is not logging — it's *recommendation*. A user opens the app, confirms their location and how much time they have, and the app produces a complete, ordered, time-boxed workout with prescribed sets, reps, and weights. Logging is a byproduct of executing that plan.

The defining constraints:

- **Location-aware.** Gyms have different equipment. The plan must only contain exercises that are actually performable where the user is standing.
- **Time-boxed.** The user picks a duration bucket (30 / 40 / 45 / 60 / 90 min) and the plan is fitted to it.
- **Reorderable and swappable mid-workout.** Gyms are busy. The prescribed order is a suggestion, and any exercise can be substituted for an equivalent one.
- **Offline-first.** Generating a plan and logging sets must work with no signal. The server is only ever touched by background sync.
- **Beautiful.** This is a product two people will look at several times a week for years. It has to feel like something Apple shipped, not a CRUD app. §8 is binding.

### Success criteria

1. From a cold open, a user reaches a complete recommended workout in **at most three taps** (location and duration both default, so often one).
2. Swapping an occupied machine for an alternative takes **one swipe and one tap**, without leaving the workout.
3. A full session can be completed in airplane mode and syncs cleanly afterward.
4. The generated plan is *roughly* the right size for the time available. Being 5–10 minutes off is fine and explicitly not worth engineering against.
5. Nothing in the app looks like a default control that nobody designed.

---

## 2. Users and access

- Initial users: Neil and Natalie. The schema and UI must support **N users**; nothing may assume two.
- **No public signup.** Access is by server-side allowlist of Apple user identifiers / emails, edited by the operator (a `users` table row with `status = 'invited'`, created via an admin CLI command — no admin UI in v1).
- **Auth: Sign in with Apple** is the only identity provider. Flow: `ASAuthorizationAppleIDProvider` on device → `POST /auth/apple` with the identity token → server verifies it against Apple's JWKS, matches `sub` (or the email on first sign-in) to an allowlisted user, and returns an opaque **session token with a 1-year expiry**. Store it in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`, so background sync works with the phone locked). Nobody re-authenticates at a squat rack. Refresh silently on any 401 by re-running Sign in with Apple, which is non-interactive once granted.
- **Dev login:** `POST /dev/login {user_id}` returns a session token for any user, enabled only when `ENV != production`. The app exposes it behind `#if DEBUG` as a user picker on the sign-in screen. Simulator builds and UI tests use it.

### Sharing model

```
share
  id, owner_user_id, viewer_user_id, created_at, revoked_at (nullable)
```

- A share grants the viewer **full, read-only** access to everything the owner has: sessions, exercises, sets, reps, weights, ratings, runs, working weights, and all derived charts. There is no partial-visibility mode and no per-session toggle — building one would be wasted work.
- Shares are **directional**. Neil → Natalie and Natalie → Neil are two rows. Onboarding creates both when a user accepts an invite ("share with each other" is the default; one-way is possible but not surfaced in v1 UI).
- **All cross-user access is read-only.** No user can create, edit, assign, or delete anything belonging to another. No plan assignment, no coaching flows.
- Invites: owner taps *Invite* → server mints a one-time code → shared via the iOS share sheet → the invitee enters it after signing in → both shares are created.
- Enforce write scoping server-side (`user_id` must equal the authenticated user on every mutation), not just in the UI. Read scoping is one check: `target_user_id == me OR exists share(owner=target, viewer=me, revoked_at IS NULL)`.

### Shared structure, separate state

All users run the **same** push/pull/legs and full-body slot templates, rep bands, progression rules, and heavy-rotation defaults. There is no per-user template system to build. What differs per user is *state*, all of which the schema scopes by `user_id`: working weights, split position, heavy-rotation position, default location, equipment overrides, and run plan.

### Units

**Pounds throughout v1.** Store weights as pounds, display as pounds, no conversion layer. Keep the unit in a single constant so a kilogram toggle can be added later without a schema migration, but do not build the toggle now.

### Sessions per day

There is **no uniqueness constraint on (user_id, date)**. A user may log a lift and a run on the same day, or two lifts, and the deck supports it. Nothing in the schema, the split-rotation logic, or the charts may assume one session per day.

---

## 3. Domain model concepts

Four concepts do most of the work. Get these right and the rest follows.

### 3.1 Location + equipment inventory

```
location
  id, name, kind ('home_gym'|'commercial'), created_by_user_id (nullable for seeded)

equipment_type       -- seeded reference table; the full vocabulary is seed/equipment_types.json
  id, key, label, note

location_equipment   -- per user, per location
  user_id, location_id, equipment_type_id, available (bool),
  dumbbell_max_weight (nullable), plate_increment (nullable), notes
```

Locations are shared reference data (two users at the same Crunch see the same location row), but **availability is per user** — Natalie unchecking a broken machine shouldn't change Neil's plan unless he agrees. In practice they'll match; the schema just doesn't force it.

Two locations are seeded (`seed/equipment_types.json`):

- **Building Gym** — `available` defaults to **false** for everything; the user checks off what's actually there during setup.
- **Crunch Union Square** — `available` defaults to **true** for everything; the user unchecks anything missing as they discover it.

**`dumbbell_max_weight` is load-bearing, not a nicety.** An apartment gym whose rack stops at 50 lb makes dumbbell bench press *nominally* available but useless once the user's working weight exceeds it. The availability filter must therefore be:

> An exercise is available at a location iff **all** its required equipment is marked available **and**, if it is `dumbbell_based`, the user's current working weight for it (estimated first if never performed, §4.3) is ≤ `dumbbell_max_weight`.

This single rule prevents the most common failure mode of this kind of app: prescribing a lift the user physically cannot load.

**Make the gate legible.** When a dumbbell exercise is excluded for weight, it still appears in the swap sheet (§7), greyed, with "needs 55 lb · rack tops out at 50". An exercise silently vanishing from a stable slot is confusing; an exercise explaining why it left is not.

### 3.2 Exercises and movement patterns

```
exercise
  id, key, name, movement_pattern, required_equipment (array of equipment_type key),
  rep_seconds, measure ('reps'|'seconds'), range_low, range_high (timed only),
  loadable (bool), dumbbell_based (bool), supersettable (bool), rank_hint,
  is_custom, created_by_user_id
```

`day_type` and `strength_cluster` are **derived** from `movement_pattern` via `seed/movement_patterns.json`; exercises do not repeat them.

`movement_pattern` is the substitution key. Two exercises with the same `movement_pattern` are valid substitutes for each other. This is how "chest press machine is taken, give me a dumbbell bench" works, and it costs one column.

### 3.3 Slot templates

Each day type is an **ordered list of slots by priority**, not a fixed exercise list. This is the central architectural idea: equipment filtering, time-boxing, and substitution all fall out of it. **`seed/movement_patterns.json` is the source of truth for the tables below**; if they ever disagree, the JSON wins.

#### Training philosophy — enforce this as an invariant

> **Exactly one slot per workout — always slot 1 — carries the heavy 5–8 rep range.** Every other slot is 8–12, or 15–20 for high-volume core and stabilizer work.

This is a hard rule, not a default. The generator must never produce a plan with two exercises in the 5–8 range, and slot 1 must never fall outside it. Note the consequence on leg day: the hinge is *not* a second heavy movement — if squat is slot 1, the RDL runs at 8–12.

Two further hard rules on slot 1:

- **Slot 1 requires `loadable: true`.** A 5–8 rep push-up is not a heavy press. Non-loadable exercises (push-ups, pull-ups, planks…) are eligible only for slots 2+.
- Slot 1 is the **only** slot with prescribed warm-up sets (§4.2).

Slots marked **[heavy]** use the 5–8 range; **[volume]** slots use 15–20; everything else is 8–12. Slot 6 (core) is **supersetted** on every day type (§3.6).

**Push**
| # | Movement pattern | Sets | Rep range | Rest |
|---|---|---|---|---|
| 1 | heavy rotation: horizontal_press **or** vertical_press **[heavy]** | 4 | 5–8 | 180s |
| 2 | vertical_press | 3 | 8–12 | 120s |
| 3 | incline_press | 3 | 8–12 | 90s |
| 4 | triceps_extension | 3 | 8–12 | 75s |
| 5 | lateral_raise **[volume]** | 3 | 15–20 | 60s |
| 6 | core **[volume, superset]** | 3 | 15–20 | — |
| 7 | chest_fly **[volume]** | 3 | 15–20 | 60s |

Slot 7 only ever fits at 60/90 minutes; that's intentional. When the heavy rotation lands on `vertical_press`, slot 2 is still `vertical_press` — the engine applies the same omit rule as pull: **if slot 1 already consumed a slot's pattern, drop that slot** (`omit_if_slot1_pattern`, generalized to all days, see JSON).

**Pull** — slot 1 is resolved by the heavy rotation (§3.4).

| # | Movement pattern | Sets | Rep range | Rest |
|---|---|---|---|---|
| 1 | heavy rotation: horizontal_row **or** hinge **[heavy]** | 4 | 5–8 | 180s |
| 2 | vertical_pull | 3 | 8–12 | 120s |
| 3 | horizontal_row (omit if slot 1 was a row) | 3 | 8–12 | 90s |
| 4 | elbow_flexion | 3 | 8–12 | 75s |
| 5 | rear_delt **[volume]** | 3 | 15–20 | 60s |
| 6 | core **[volume, superset]** | 3 | 15–20 | — |

When slot 1 resolves to a hinge (deadlift), slot 3's horizontal row is retained and the plan simply carries more pulling volume. When slot 1 resolves to a row, slot 3 is dropped and every later slot shifts up one — so the plan still fills to the same time budget, it just reaches further down the list.

**Legs**
| # | Movement pattern | Sets | Rep range | Rest |
|---|---|---|---|---|
| 1 | heavy rotation: squat (dominant) **or** hinge **[heavy]** | 4 | 5–8 | 180s |
| 2 | hinge — **becomes squat (8–12) when slot 1 is a hinge** | 3 | 8–12 | 120s |
| 3 | quad_isolation | 3 | 8–12 | 90s |
| 4 | hamstring_isolation | 3 | 8–12 | 90s |
| 5 | calf **[volume]** | 3 | 15–20 | 60s |
| 6 | core **[volume, superset]** | 3 | 15–20 | — |

Leg day therefore always carries exactly one squat-pattern and one hinge-pattern movement, in either order (`alt_pattern_if_slot1_pattern` in the JSON).

Because slot ordering is also the priority order for time-budget trimming (§4.1), a 30-minute session naturally reduces to the heavy compound plus one or two 8–12 movements plus core — which is the correct thing to cut to.

### 3.4 Exercise variation

Not every push day should be identical. But variety and progression pull against each other: double progression (§5) needs repeated exposure to the *same* exercise to know whether the reps were hit. If lateral raises rotate between cable, dumbbell, and machine every session, each variant carries its own `working_weight` and each progresses at a third of the rate.

**So variety is concentrated where progression matters least.**

| Slot | Variation policy |
|---|---|
| 1 **[heavy]** | Rotates by an explicit pattern rotation (below). Within a pattern, the exercise is **stable** — squat day means back squat every time. |
| 2–4 (8–12) | **Stable by default.** This is where most loading progress happens. The exercise changes only if equipment is unavailable or the user swaps manually. |
| 5–7 **[volume]** | **Rotate freely.** Prefer an exercise not used in the last 2 sessions of this day type. Loads here are light and the rep climb is slow anyway, so nothing is lost. |

#### Heavy rotation

Per user, per day type, an ordered cycle of movement patterns for slot 1:

```
heavy_rotation
  user_id, day_type, sequence (ordered array of movement_pattern), position

Defaults:
  push:  [horizontal_press, horizontal_press, vertical_press]
  pull:  [horizontal_row, hinge]
  legs:  [squat, squat, squat, hinge]
```

`position` advances by one each time a workout of that day type is completed, wrapping at the end. Pull day therefore alternates row → deadlift → row → deadlift. Leg day is squat three times out of four.

The rotation is user-editable — it's a list of patterns, and the settings screen should expose it as such rather than hard-coding the defaults above.

### 3.5 Split state

```
split_state
  user_id, last_day_type, last_completed_at
```

Rotation is **sequence-driven, not calendar-driven**: push → pull → legs → push. A missed week does not shift anything; the user simply picks up at the next day type. Runs do not advance the rotation. The user can override the day type at session start (a manual override *does* advance the rotation).

### 3.6 Supersets

Core work is not run as a standalone block. It is **supersetted into the rest periods of another exercise** — a set of lat pulldowns, then a set of hanging leg raises, then the next set of pulldowns, and so on.

Build this as a general `superset_group` mechanism on the plan, not a core-specific special case. It costs nothing extra and leaves room to pair other things later. But by default, **only the core slot is supersetted.**

**Host selection.** The core slot pairs with the **last 8–12 band exercise in the plan whose rest is ≥ 90s** — slot 3 on push/pull, slot 4 on legs, slot 2 in a trimmed session.

Two hard constraints:

- **Never superset with slot 1.** You do not want a fatigued, braced core going into a heavy squat or deadlift, and the 180s rest on the heavy compound is rest you actually need. The generator must exclude slot 1 from host selection unconditionally.
- **Only superset when the host's rest is ≥ 90s.** Below that there isn't room, and interleaving turns into a scramble.

If no eligible host survives trimming (a 30-minute session cut to the heavy compound alone), core either runs standalone at the end if it fits its own block cost, or is dropped — normal trimming behaviour applies.

**Set-count mismatch.** Interleave as far as the shorter exercise goes, then revert to normal rest cards for the host's remaining sets. Do not pad either exercise to make the counts line up.

---

## 4. The recommendation engine

The heart of the app. Given `(user, location, duration_bucket, day_type)`, produce an ordered plan. It runs **entirely on-device** in the `WorkoutEngine` package (§11) against the local store; the server never generates anything.

### 4.1 Algorithm

```
1. day_type := next in rotation from split_state (user-overridable)
2. slots := slot_template[day_type]                    # ordered by priority
   slot[1].pattern := heavy_rotation[day_type].current()   # see §3.4
   for each slot s > 1:
       if s.omit_if_slot1_pattern == slot[1].pattern: drop s
       if s.alt_pattern_if_slot1_pattern[slot[1].pattern]: s.pattern := that
3. for each slot:
       candidates := exercises where
           movement_pattern == slot.pattern
           AND all required_equipment available at location
           AND (not dumbbell_based OR working_weight <= dumbbell_max)
           AND (slot.band != heavy OR exercise.loadable)
       chosen := rank(candidates, slot) -> highest
       if candidates is empty: skip slot, continue
4. plan := []
   budget := duration_bucket * 60
   for each slot in priority order:
       cost := estimate_block_seconds(slot, chosen)      # 60 if supersetted, §4.2
       if sum(plan.cost) + cost <= budget:
           plan.append(block)
       else:
           continue                                      # NOT break — a cheaper slot may still fit
5. resolve superset host (§3.6); if none, re-cost core as a standalone block
   and drop it if it no longer fits
6. slack := budget - sum(plan.cost)
   while slack >= 180:                                   # >= 3 min spare
       add one set to the highest-priority *non-heavy, non-supersetted* block
       not yet padded (slots 2-4 first, then 5+); stop if none remain
       recompute slack
7. return plan
8. on session completion: advance heavy_rotation[day_type].position
```

Step 4 uses `continue`, not `break`: skipping a 5-minute lateral-raise block must not also drop a 60-second supersetted core block behind it. Step 6 never pads slot 1 (five heavy sets changes the progression test, §5.1) or supersetted blocks (their cost doesn't change).

`rank(candidates, slot)` depends on the slot's variation policy from §3.4:

- **Slots 1–4 (stable):** strongly prefer the exercise the user most recently performed for this pattern — continuity is the point. Then `rank_hint` from the catalog (which encodes barbell/dumbbell over machine for slot 1, machine over free weight for slots 3–4). Alphabetical as a stable tiebreak.
- **Slots 5–7 (rotate):** strongly *penalize* exercises used in the last 2 sessions of this day type, then fall back to the same ordering.

The inversion between these two cases is the whole variation mechanism. Implement it as a single scoring function with a sign flip on the recency term, not as two code paths.

### 4.2 Time estimation

```
warmup_seconds     = 2 * (8 * rep_seconds) + 2 * 45     # slot 1 only
working_seconds    = sets * reps_target * rep_seconds   # timed exercises: sets * range_high
rest_seconds       = (sets - 1) * slot.rest_seconds
transition_seconds = 60

block_total = warmup_seconds? + working_seconds + rest_seconds + transition_seconds
```

**Supersetted exercises cost almost nothing.** A core slot supersetted into a host's rest periods (§3.6) does not get its own block cost. Its sets consume rest that was already budgeted. Charge it a flat 60 seconds for setup and station transition and nothing more:

```
if slot.is_supersetted:
    block_total = 60
```

This is the correct model and it has a useful consequence: core becomes nearly free, so it survives time-budget trimming far longer than a standalone block would. A 40-minute session can still include core. If a core set is longer than the host's rest interval, the extra time is real but small — ignore it, well within tolerance.

**`rep_seconds` precedence:** the per-exercise value in `exercises.json` wins; the config defaults (3.5 for heavy-slot exercises, 2.5 otherwise) apply only to custom exercises without one. All constants live in a single `EngineConfig` so they can be tuned without touching engine logic.

**Warm-up sets (slot 1 only):**

| Set | Load | Reps |
|---|---|---|
| W1 | 50 % of working weight | 8 |
| W2 | 75 % of working weight | 5 |

Round down to the location's increment; for barbell lifts the floor is the empty bar (45 lb). If the working weight is ≤ 2× the bar, prescribe a single warm-up set with the empty bar.

**This calculation runs exactly once, at plan generation.** Its only job is to decide how many exercises and how many sets go into the plan. It is a coarse sizing heuristic, not a schedule:

- Do **not** recompute it as the workout progresses.
- Do **not** compare it against actual elapsed time.
- Do **not** store per-block actual durations or calibrate the constants over time.
- Do **not** surface a "you're behind schedule" indicator.

An error of 5–10 minutes or more is acceptable and explicitly not worth engineering against. A plain elapsed-time clock in the header is fine; anything that reacts to it is out of scope.

### 4.3 Weight selection

Each `(user, exercise)` pair has a `working_weight`. For an exercise the user has never performed, estimate it from a related lift via the seeded ratio table in `movement_patterns.json` (`ratio_table`; dumbbell targets are per hand). Excerpt:

| From | To | Ratio |
|---|---|---|
| Barbell bench | Dumbbell bench (per hand) | 0.42 |
| Barbell bench | Machine chest press | 0.90 |
| Barbell bench | Incline barbell | 0.82 |
| Back squat | Leg press | 1.80 |
| Back squat | Hack squat | 1.10 |
| Deadlift | Romanian deadlift | 0.65 |
| Overhead press | DB shoulder press (per hand) | 0.40 |

If neither the exercise nor any ratio source has a weight (brand-new user, exercise outside the table), fall back to the empty bar / lightest dumbbell / lightest machine increment, flagged as an estimate. Estimated weights are **flagged as estimates** in the UI, and the post-exercise rating (§5.3) resolves them quickly.

### 4.4 Rebaselining stale exercises

The problem: you bench, dumbbell press, and dip for two months, all progressing. You haven't touched the chest press machine in that time. Next time it comes up, the app recommends the weight you used two months ago — far too light — and you waste a set discovering that.

**Do not solve this with the absolute ratio table.** Deriving `chest_press = bench × 0.90` and recomputing is tempting but fragile: those ratios vary enormously between people, and a bad ratio produces a bad absolute number no matter how much progress data you have.

**Transfer relative growth instead.** The percentage you've gained is far more portable across exercises than the ratio between them.

```
strength_cluster                # derived from movement_pattern via movement_patterns.json

Per (user, exercise), track:
  working_weight, last_performed_at, last_rebaselined_at,
  weight_source ('measured' | 'estimated' | 'rebaselined'),
  pre_rebaseline_weight (nullable)   # for the §5.4 revert
```

`anchor.weight_when_E_last_performed` is **derived from set history** — the heaviest measured working set of the anchor exercise on or before `E.last_performed_at` — not stored as a snapshot. One fewer thing to keep consistent.

Runs on-device on app foreground (cheap: a few hundred rows), at most once per day:

```
for each exercise E where last_performed_at > 21 days ago
                     and (last_rebaselined_at is null or > 14 days ago):
    cluster := E.strength_cluster
    anchors := exercises in cluster, performed since E.last_performed_at,
               with weight_source == 'measured'
    if anchors is empty: skip

    growth := median over anchors of
                  (anchor.working_weight / anchor.weight_when_E_last_performed) - 1

    if growth <= 0: skip                      # never downgrade
    adjusted := growth * 0.5                  # damping
    adjusted := min(adjusted, 0.10)           # cap one rebaseline at +10%

    new_weight := round_down_to_increment(E.working_weight * (1 + adjusted))
    if new_weight > E.working_weight:
        E.pre_rebaseline_weight := E.working_weight
        E.working_weight := new_weight
        E.weight_source := 'rebaselined'
        E.last_rebaselined_at := now
```

Design constraints, all deliberate:

- **Monotonic upward.** A rebaseline can only raise a weight. Growth ≤ 0 is a no-op, never a reduction. Real deloads only ever come from measured failure (§5.1).
- **Conservative by construction.** The 0.5 damping factor, the +10% cap, and rounding *down* to the nearest available increment all bias light. A weight that's too light costs one easy set and a manual bump; a weight that's too heavy costs a failed lift and possibly an injury. These are not symmetric errors.
- **Only measured anchors count.** Rebaselined weights cannot themselves seed further rebaselines — otherwise estimates compound into fiction.
- **Within-cluster only.** Bench press informs dumbbell bench and dips. It does not inform overhead press.
- **At most one rebaseline per exercise per 14 days.**

A rebaselined weight is surfaced in the deck as an estimate, which routes it straight into the rating flow below.

---

## 5. Progression

### 5.1 Double progression

Per `(user, exercise)`:

```
state: working_weight, consecutive_failures, weight_source
```

**The prescribed target is always the top of the rep range.** There is no incrementing target — an 8–12 exercise always shows 12 as the target, and the weight holds until every working set reaches it.

```
On exercise completion (over the template's prescribed set count, ignoring §4.1 padding sets):

  all_sets_at_top := every working set hit rep_range_high
  any_set_below_bottom := any working set fell below rep_range_low

  if all_sets_at_top:
      working_weight += progression_step        # modified by rating, §5.3
      weight_source = 'measured'
      consecutive_failures = 0
  elif any_set_below_bottom:
      consecutive_failures += 1
      if consecutive_failures >= 2:
          working_weight *= 0.90                # round to available increment
          consecutive_failures = 0
  else:
      hold                                      # this is the healthy steady state
      consecutive_failures = 0
```

Worked example, 8–12 range, 4 sets: hitting 12/12/12/12 raises the weight. Hitting 12/12/11/10 — failure a couple of reps short on the last set — is exactly right and the weight holds. Dropping to 12/10/8/7 twice in a row triggers a 10% deload.

Padding sets added by §4.1 step 6 are logged but excluded from the progression test, so progression speed doesn't depend on which duration bucket was picked.

Rationale for double progression over straight linear loading: adding weight every session works for about six weeks and then stalls hard. Climbing within the rep range first gives a longer runway and generates a natural deload trigger.

**No deload after a layoff.** Time away from training has no effect on `working_weight`. After two weeks or two months off, the app recommends exactly what it recommended before the break. If that turns out to be too heavy, the normal DNF path (§5.4) handles it in one session. Do not implement any time-decay on weights — no "welcome back, here's 90%."

### 5.2 Progression step by rep band

The three rep bands need different increments — a 15–20 rep lateral raise cannot take the same jump as a 5–8 rep bench press. Values live in `movement_patterns.json → progression_steps_lb`.

| Band | Slots | Step on weight increase | Notes |
|---|---|---|---|
| 5–8 **[heavy]** | slot 1 only | 5 lb upper / 10 lb lower | |
| 8–12 | slots 2–4 | 5 lb, or 5 lb per hand | |
| 15–20 **[volume]** | slots 5–7 | 2.5 lb, else 5 lb | Long climb; see below |

Round all computed weights to the location's available increment (`plate_increment`), and to 5 lb for dumbbells. **Round down, always.**

**Lateral raises and rear delts** use the smallest increment the gym actually stocks. If the building gym only jumps in 5 lb steps, take the 5 lb step — a coarse progression is acceptable here rather than stalling the exercise indefinitely.

**Non-loadable exercises** (`loadable: false`, including all bodyweight core) progress by reps then sets: when the top of the range is hit on all sets, add a set up to a maximum of 4, then hold as maintenance work. **Timed holds** (`measure: seconds`) use `range_low`/`range_high` as seconds in exactly the same rule — 20s → 45s plank, then a fourth set, then hold. Loadable core (cable crunch, weighted hanging raise) takes weight increases at the smallest available increment once the set cap is reached.

### 5.3 Effort rating

At the end of each exercise, the deck presents a three-way rating:

| Rating | Meaning | Effect |
|---|---|---|
| **Easy** | Could have done several more reps | Apply **2× the normal step** on the next increase. If reps weren't all at the top of range, still increase by one step. |
| **Good effort** | Hard but completed | Normal §5.1 logic. This is the default. |
| **Did not finish** | Failed to complete prescribed sets | See §5.4 — the effect depends on *which* set failed. |

The rating is optional — skipping it means "good effort."

Its most valuable job is **collapsing the uncertainty on estimated and rebaselined weights**. A weight arriving from §4.3 or §4.4 carries real error; one `Easy` rating corrects it in a single session rather than over the three or four it would take pure double progression to climb. When `weight_source != 'measured'` and the rating is `Easy`, apply the 2× step **and** set `weight_source = 'measured'`.

### 5.4 Did-not-finish severity

A DNF is not one signal. Failing the *first* set means the weight was simply too heavy — you had no fatigue yet and still couldn't complete it. Failing the *third* set means the weight was probably about right and you ran out of gas, which is the normal outcome of training hard.

Record `first_failed_set_index` on the exercise result and branch on it:

| Situation | First set failed | A later set failed |
|---|---|---|
| `weight_source` is `rebaselined` or `estimated` | **Revert immediately** to `pre_rebaseline_weight` (or −10% for a cold-start estimate). Set `weight_source = 'measured'`. Does not count toward `consecutive_failures`. | No revert. Hold the weight, treat as a normal hold. |
| `weight_source` is `measured` | Counts as a failure; `consecutive_failures += 1`. Two in a row → 10% deload per §5.1. | Hold. Does not count toward `consecutive_failures`. |

This is the only automatic downgrade path in the system, and it fires only on the unambiguous signal.

---

## 6. Running

```
run_plan
  user_id, runs_per_week (2 or 3), easy_pace_sec_per_mi,
  long_run_distance_mi, weekly_volume_mi, target_weekly_volume_mi, week_index

planned_run
  id, user_id, scheduled_week, run_type ('easy'|'tempo'|'long'),
  target_distance_mi, target_pace_sec_per_mi, status

run                              -- the logged result
  id, user_id, planned_run_id (nullable), performed_at, run_type,
  distance_mi, duration_sec, source ('manual')
```

Weekly template at 3 runs/week: **easy + tempo + long**. At 2 runs/week: **easy + long**.

Pace targets derive from a single user-entered anchor (current comfortable easy pace, or a recent 5K time):

- easy = `easy_pace`
- tempo = `easy_pace − 70 s/mi`
- long = `easy_pace + 15 s/mi`

**Volume split** of `weekly_volume_mi`: at 3 runs, long 40 % / tempo 25 % / easy 35 %; at 2 runs, long 55 % / easy 45 %. Round each to 0.5 mi.

**Progression:** +10 % per week with a deload every 4th week to 70 % of the prior week, **until `weekly_volume_mi` reaches `target_weekly_volume_mi`**, then hold there (deload weeks continue). The target is set in onboarding (default: 1.5× the starting volume) and editable in settings. Without a ceiling, +10 %/week compounds to nonsense within a year.

Runs are scheduled by count per week, not by weekday; the app does not enforce rest-day placement.

Runs render in the deck as a short card sequence: warm-up, main segment(s) with target pace, cool-down. **No GPS or live tracking in v1** — the user enters actual distance and time afterward. If actual easy-run pace beats target by ≥ 20 s/mi for 3 consecutive easy runs, nudge `easy_pace_sec_per_mi` down by 10 s/mi.

---

## 7. The deck UI

The workout is a **stack of cards, one at a time** (think Tinder, not a list). The user never sees more than the card in hand plus the edges of the next one or two behind it. Every card is one *step*: a warm-up set or a working set of one exercise, showing exactly three things — exercise name, weight, and `set n of m · rep range`.

| Card | Swipe right | Swipe left | Swipe up | Tap |
|---|---|---|---|---|
| `set` (warm-up or working) | **Done** → rest card | **Skip** the exercise | **Rate** this set | — |
| `rate` | Back to the set card | — | — | Easy / Good / Hard, or "Didn't finish" |
| `rest` | Skip rest | Skip rest | — | — (pause / −10 / +10 are buttons under the ring) |

Swiping right logs the set as completed at the top of the rep range with no rating; the rest countdown starts and, at zero, the next card is already in hand. Swiping up shows the rating card; the rating implies the reps logged (easy/good = top of range, hard = bottom of range, didn't finish = short of target) so the **working weight adjusts itself** through §5 — the user never types a number mid-set. `hard` holds the load without counting as a failure. Swiping left skips the whole exercise for this session: it leaves the stack, sets already logged stay, and it is listed under **Skipped** in the overview with a one-tap restore (back to the end of the deck).

As the drag grows the card tints and stamps the pending action, Tinder-style, so the user knows what letting go will do: **green** for Done, **red** for Skip, **blue** for Rate — the one exception to §8 rule 4. A `.selection` haptic marks the threshold.

Superset partners alternate with their host: host set → partner set (no rest) → rest → host set. Rest after a warm-up is 60 s regardless of band.

There are no buttons on the set card. The only chrome is the header (day, `n of m` done, and the overview button) and a one-line swipe hint.

### Zoomed-out deck view

The overview is the management surface for the whole workout, reached from the header. It lists every block in deck order and is where everything that isn't "do the set" lives:

- **Reorder** by long-press drag (the machine is taken, do this one later).
- **Edit** a block: working weight (plate / dumbbell increments), number of sets (fewer than prescribed re-prescribes; more are padding and don't gate progression), rep range.
- **Swipe a row** right to **swap** the exercise (blue; opens the picker — same slot, same superset link, weight re-estimated) or left to **delete** it (red). Deleted blocks aren't lost: they sit under **Deleted** at the bottom, and a swipe right there (or on a **Skipped** block) **restores** it to the end of the deck. Rows also expose Swap / Delete / Restore as accessibility actions for anyone who can't swipe.
- **Undo last set** from the expanded row.
- Before the workout starts the same screen is "Today's plan": it replaces Home at the root, so it closes with an **X** in the header (like the live run), not a back chevron or bottom bar; nothing is logged yet, so there's no confirmation.
- **End workout** — finish and save progress, or discard (discarded sessions soft-delete their set logs so charts never see them).

### Rest timer

Compute remaining time from a **stored start `Date`**, never from a running counter — iOS suspends the app when the screen locks, and a `Timer` that was counting down simply stops. This is the single most common bug in workout apps. On return to foreground, recompute from the stored date.

- Schedule a `UNUserNotificationCenter` local notification for the end time when the rest card appears; cancel it if the user skips rest. Request notification permission the first time a rest card is shown, not at launch.
- Run a **Live Activity** (ActivityKit) for the duration of a workout showing the rest countdown and the next exercise on the Lock Screen and in the Dynamic Island. The phone is locked between sets; this is where the timer is actually read.
- **Pause**, **−10 s** and **+10 s** controls sit under the ring. Pausing stores the seconds left and cancels the notification; resuming sets a new end date. ±10 moves the end date (or the paused remainder) and reschedules; dropping to zero ends the rest, stretching past the original length grows the ring.
- Haptic (`.success`) when the timer hits zero if the app is foregrounded.
- The timer does not force-advance; it goes to zero and shows overage in the same typographic style, tinted.

### Native behaviours

- `UIApplication.isIdleTimerDisabled = true` while a workout is in progress.
- Weight and rep entry use a custom stepper/wheel sized for sweaty thumbs, not the system keyboard. Steps follow the location's increment.
- The whole deck works one-handed in portrait. No landscape.

---

## 8. Design and aesthetic

This is a product two people will look at several times a week for years, in the exact moments they're tired and impatient. It should feel like it belongs in the Apple Design Awards shortlist, with the restraint of a luxury brand: **confident, quiet, precise, nothing extraneous.** The references are Apple Fitness+, the iOS Weather and Stocks apps, Linear, Teenage Engineering, Aesop, Hermès packaging — not Strava, not Strong, not anything with a leaderboard or a confetti animation.

The rules below are binding. The visual language itself (exact palette, type choices, card proportions) is to be settled in a **design prototype built before the real deck** (§16 build order step 0): a SwiftUI preview app with static data showing the start screen, one of each card type, the rest timer, and one chart, iterated with the owner until it's right.

### 8.1 Principles

1. **One thing per screen.** A card shows the one number that matters right now — the weight, the reps, the countdown — at a size you can read from the floor with the phone on a bench. Secondary information is small, low-contrast, and never competes.
2. **Typography does the work.** No icons where a word is clearer; no decoration. Hierarchy is created by size, weight and spacing, not by boxes and colours.
3. **Dark by default, light as an option.** Gym lighting is harsh and the phone is often face-up on a bench; a near-black canvas with high-contrast type reads better and looks more expensive. Both modes must be fully designed; this is not "dark mode support."
4. **Colour is rare and meaningful.** One accent colour, used for exactly three things: the primary action, the active state of the timer, and the user's own series in charts. The partner gets a second, equally-weighted hue in charts and nowhere else. Day types (push/pull/legs/full body) get four muted tints used only in chart bars and the small day-type label. Everything else is a neutral ramp. No red/green for good/bad — use type and position.
5. **Motion is physical and brief.** Cards move the way paper moves: spring curves (`.spring(response: 0.35, dampingFraction: 0.85)`), interruptible, driven by the gesture's velocity. Nothing bounces for fun. Nothing animates that the user didn't touch, except the timer. Honour `Reduce Motion`.
6. **Haptics are part of the design.** Set complete: `.light` impact. Exercise complete: `.medium`. Timer done: `.success` notification. Swipe threshold crossed: `.selection`. Nothing else vibrates.
7. **Native where native is right.** Standard navigation, sheets, context menus, Dynamic Type, VoiceOver labels on every control, SF Symbols where an icon is unavoidable. Custom where the system control would look like a settings page: the deck, the timer, the weight stepper, the charts.
8. **No empty states that apologise.** A new user's progress screen shows the chart frame with the axis and a single line of copy ("Your first session will appear here"), not an illustration of a sad dumbbell.
9. **Copy is short, lower-case-calm, and never exclamatory.** "Set 3 of 4." "Rest." "Up 5 lb." Never "Crushed it!" Never emoji.

### 8.2 System

- **Type:** SF Pro throughout. Display sizes use SF Pro Display with tight tracking (−2 % to −3 %) for the hero number on each card (weight / reps / countdown), rendered with `monospacedDigit()` so the countdown doesn't jitter. Body is SF Pro Text at Dynamic Type sizes. New York (serif) is permitted for exactly one thing — the session title / day-type on the intro card — if the prototype shows it earns its place; otherwise don't.
- **Spacing:** an 8-pt grid, with 4-pt allowed only inside compound controls. Generous margins (24 pt sides on cards). Whitespace is a feature, not waste.
- **Surfaces:** flat, no drop shadows on cards against the canvas; depth comes from a subtle 1-px hairline (`separator` opacity ~0.12) and material blur (`.ultraThinMaterial`) on sheets. Corner radius 28 pt on cards (continuous corners), 14 pt on buttons, 8 pt on chips.
- **Palette (starting point for the prototype):** canvas `#0B0B0C`, card `#141416`, primary text `#F5F5F7`, secondary text at 60 % opacity, tertiary at 35 %. Accent: a single warm metallic — brass/champagne (`#C8A96A`) — rather than the usual electric blue or neon green; it photographs well on dark surfaces and nothing else in the category uses it. Partner hue: cool slate (`#8FA3B8`). Day-type tints: push `#B86B5E`, pull `#5E7FB8`, legs `#6E9A6B`, all at low saturation. Light mode inverts the neutrals and darkens the accent to `#8E6E32` for contrast. **All text must pass WCAG AA against its background in both modes.**
- **Charts:** Swift Charts with the chrome stripped — no gridlines except a single baseline, axis labels in tertiary text, points only on hover/press, rebaselined points hollow with a dashed connector (§12.1). Two-user overlays are two lines of equal weight; no fills, no area gradients.
- **App icon:** a single glyph on the canvas colour (a horizontal bar or a plate edge in the accent), no gradient background, no text. Provide the dark and tinted variants iOS 18 expects.
- **Launch:** the launch screen is the canvas colour and nothing else; the start screen fades in over 200 ms.

### 8.3 Non-negotiables

- No stock SwiftUI `List` chrome on primary screens (settings may use it).
- No modals that could be inline. No confirmation dialogs for reversible actions — use undo.
- No badges, streaks, rings, confetti, medals, levels, or any gamification. The reward is the number going up.
- No onboarding carousel. Onboarding (§14) is a sequence of the same cards used everywhere else.
- Every screen reviewed in both appearance modes and at the largest accessibility Dynamic Type size before it's considered done.

---

## 9. The plan is fixed once generated

**There is no automatic mid-workout re-planning.** The time budget is a sizing input consumed at generation time and then discarded.

Once the deck exists, the only things that change it are direct user actions:

- Swapping an exercise for an alternative (§7)
- Deferring an exercise to the end
- Skipping an exercise or a set
- Adding or removing an exercise from the zoomed-out deck view

None of these trigger a recalculation, a warning, or a suggestion to drop something. If a swap makes the workout longer, that is the user's business. Show elapsed time in the header and nothing else.

This is a deliberate simplification. Live re-planning would be the most complex subsystem in the app and would earn very little: the user already knows how much time they have and can simply stop.

---

## 10. Offline and sync

Local-first. Every write lands in the on-device SQLite database immediately; the UI never blocks on the network.

- **Recommendation and progression run on the client**, in the `WorkoutEngine` package, against the locally cached exercise catalog, equipment inventory, and working weights. The server is pure storage; it never computes a plan, a weight, or a chart. One implementation, in Swift. (A Python mirror of the engine is **not** required and should not be built.)
- **Local store:** SQLite via **GRDB.swift**, with an explicit schema mirroring the server tables plus an `outbox` table. Not SwiftData/Core Data — we need deterministic SQL for the chart queries and an outbox we control. GRDB's `ValueObservation` drives SwiftUI updates.
- **Outbox:** every local mutation appends `{id, table, op, payload, created_at}`; a background drainer posts batches to `/sync/push` in order with exponential backoff (1s → 5 min cap), triggered on write, on foreground, on network-reachability change, and by a `BGAppRefreshTask`.
- `POST /sync/push` applies **last-write-wins per record** by client `updated_at`; rejects any mutation whose `user_id` ≠ authenticated user.
- `GET /sync/pull?since=<cursor>` returns changed records (including tombstones) for the user **and every user who shares with them**, ordered by server sequence number. The cursor is the server sequence, not a timestamp.
- All IDs are client-generated **UUIDv7**. All deletes are soft (`deleted_at`).
- Reference tables (`exercise` catalog, `equipment_type`, `movement_pattern`, seeded `location`) ship in the app bundle (§13) and are not synced; only user-created rows (`is_custom` exercises, user-created locations) go through the outbox.

Every record belongs to exactly one user and users cannot write to each other's records, so the only possible conflict is one user on two devices. LWW is sufficient. **Do not add a CRDT layer or a third-party sync engine.**

---

## 11. Tech stack, project structure, hosting

### iOS app

- **Swift 6, SwiftUI, iOS 17.0 minimum**, iPhone only, portrait only. Xcode 16+. Strict concurrency on.
- **Repository layout** — one repo, two deployables:

```
/ios
  WorkoutApp.xcodeproj
  WorkoutApp/              # thin app target: scenes, navigation, DI
  Packages/
    WorkoutEngine/         # pure Swift, no UIKit/SwiftUI import. §3-§6 + seed loading. swift test on macOS.
    WorkoutStore/          # GRDB schema, migrations, outbox, sync client, Keychain
    WorkoutUI/             # design system (§8): tokens, card components, timer, stepper, chart styles
  WorkoutAppTests/, WorkoutAppUITests/
/server
  app/                     # FastAPI
  alembic/
  pyproject.toml
/seed                      # the three JSONs + validate_seed.py; symlinked/copied into the app bundle at build time
```

- **Dependencies (iOS):** GRDB.swift. That's the list. No networking library (URLSession), no DI framework, no reactive framework beyond Observation. Gestures and animation are SwiftUI's own.
- **Testing:** `WorkoutEngine` has exhaustive unit tests, including a Swift port of `validate_seed.py`'s coverage simulation and **snapshot tests of generated plans** across (location × duration × day type × rotation position) checked into the repo as readable text, so a human can review that the plans are ones they'd actually run. Store tests cover migrations, outbox ordering, and LWW. UI tests cover the three success criteria in §1 (taps-to-workout, swipe-to-swap, airplane-mode session).
- **Distribution:** TestFlight (internal testers). Requires an **Apple Developer Program membership ($99/yr)** — the only unavoidable cost. Free provisioning is not viable (7-day installs). CI: Xcode Cloud (free tier) or GitHub Actions with a macOS runner building, testing, and uploading to TestFlight on tag.

### Backend

- **FastAPI, Python 3.12, SQLAlchemy 2.x + Alembic, Pydantic v2.** Endpoints: `/auth/apple`, `/dev/login`, `/sync/push`, `/sync/pull`, `/invites` (create / accept), `/health`. Nothing else. There is no REST resource API — the app never reads a single record through anything but `/sync/pull`.
- Pydantic models are the API contract; generate Swift `Codable` types from the OpenAPI schema (`swift-openapi-generator`) in the `WorkoutStore` package so the two sides can't drift.
- Admin CLI (`python -m app.admin add-user <email>`) for the allowlist.

### Hosting (target: ≈ $0/month beyond the Apple membership)

| Layer | Choice | Why |
|---|---|---|
| Backend | FastAPI on **Fly.io** or Render free tier | Cold starts on idle — fine, see below |
| Database | **Neon** free tier (Postgres) | Scale-to-zero compute, 0.5 GB storage |

**Use Neon, not Supabase.** Supabase's free tier pauses projects after a week of inactivity and requires a manual unpause — for an app that might go eight days between sessions, that is a hard failure. Neon's compute scales to zero and wakes on demand.

**On backend cold starts:** the first request after a quiet period is slow. Here that's a non-issue: generation and logging are on-device, and the backend is only touched by background sync, where a 30-second cold start is invisible. **This is a direct payoff of the local-first decision and should not be traded away.**

---

## 12. Progress and charts

A **Progress** screen with a persistent person switcher at the top (Me / each user who shares with me). Every chart renders identically for any user, or with two series overlaid where noted.

All metrics are **computed on the fly from SQLite**. Do not build aggregation tables or a metrics pipeline — a handful of users generating a few hundred sessions a year is a trivial amount of data.

Charting: **Swift Charts**, styled per §8.2.

### 12.1 Weight over time, per exercise

An exercise picker (defaulting to the user's most-performed lift), then a line chart of the **heaviest working set performed per session**, over time.

**Render rebaselined points differently** — hollow markers with a dashed connecting segment. A weight that jumped because §4.4 inferred progress from other lifts is not the same kind of data point as a weight you actually lifted, and a chart that conflates them will quietly overstate progress. Include a legend entry saying so.

Optional secondary line: estimated 1RM via Epley (`weight × (1 + reps/30)`), computed only from sets of 12 reps or fewer.

### 12.2 Running

Two charts.

**Pace over time — split by run type.** Easy, tempo, and long runs must be separate series. Plotting them as one line produces noise, not a trend: a tempo run is *supposed* to be 70 s/mi faster than an easy run, so a week with a tempo session would read as a fitness gain that isn't there. Three lines, or a filter, but never one merged line.

**Weekly mileage.** Bar chart by week. Overlay the planned volume from §6 as a faint reference so under-running and over-running are visible.

### 12.3 Volume

Total volume = `Σ (sets × reps × weight)` over non-warm-up sets. Day-by-day bars and a week-by-week view, toggleable.

Two caveats that must be reflected in the UI:

- **Bodyweight exercises are excluded** (weight = 0 would drag the total down and misrepresent the session). Show a small note on days containing bodyweight work rather than silently omitting it.
- **Volume is dominated by leg day** by a wide margin — a 5-rep squat set moves the number far more than twenty lateral raises. Tint bars by day type so the sawtooth is legible as structure rather than inconsistency.

### 12.4 Comparison

Two users' series can be overlaid on the volume and weekly-mileage charts.

**Frame this as parallel trends, not a leaderboard.** Raw tonnage between two people of different bodyweights and training histories is not a measure of who worked harder, and a UI that implies otherwise is actively bad. Use neutral labels, no ranking, no "winner," no totals-to-date scoreboard. Same-axis lines, two colours of equal weight, nothing else.

---

## 13. Seed data

Ships alongside this spec in `seed/`, and is bundled into the app. This is authored data, not something to regenerate — the quality of every recommendation the app makes depends on it being correct.

| File | Contents |
|---|---|
| `equipment_types.json` | 27 equipment keys, plus the two location definitions and their availability defaults |
| `movement_patterns.json` | 16 movement patterns with their strength clusters, the three slot templates (incl. `omit_if_slot1_pattern` / `alt_pattern_if_slot1_pattern`), heavy-rotation defaults, progression steps, and the cold-start ratio table |
| `exercises.json` | 90 exercises with pattern, equipment requirements, and timing |
| `validate_seed.py` | Integrity checks plus a coverage simulation (now also checks heavy-slot loadability and alt patterns) |

**Loading:** on first launch, and whenever the bundled `seed_version` is newer than the one recorded in the local DB, upsert the catalog by `key`. User state keys off exercise `key`, never a row id, so a catalog update never orphans working weights.

`movement_pattern` determines both which slot an exercise can fill and what it can be swapped for. `strength_cluster` is a *separate* axis governing rebaseline growth transfer (§4.4) — do not collapse the two.

Timed core holds carry `measure: "seconds"` with `range_low`/`range_high` instead of a rep range. `loadable: false` means weight never applies and progression runs on reps then sets (§5.2). `dumbbell_based: true` is what activates the `dumbbell_max_weight` gate (§3.1).

**Run `validate_seed.py` after any edit to these files**, and keep the Swift port of its coverage check green in CI. Edit `MINIMAL_GYM` at the top of the script to match the real building gym inventory before implementation.

---

## 14. Onboarding

One-time setup, skippable and resumable, built from the same card components as the deck (§8.3):

1. Sign in with Apple. If the Apple ID isn't allowlisted, show a single calm screen: "This app is invite-only." with an *Enter invite code* field.
2. Accept or send an invite (creates the shares, §2). Skippable.
3. Default location (default: last used; Natalie's onboarding preselects Building Gym).
4. **Building Gym equipment checklist** — the equipment list with toggles, plus a dumbbell max-weight field and plate increment. Five minutes of work, done once. Everything defaults to unavailable here; Crunch defaults to available.
5. **Baseline strength** — the primary lifts (bench, overhead press, squat, deadlift, row, pulldown): current working weight × reps. Everything else is estimated from the ratio table and refined in use. Accept CSV paste as an alternative.
6. **Running baseline** — current comfortable easy pace, typical long run distance, runs per week, target weekly volume.

---

## 15. Non-goals for v1

Do not build these:

- Jiu-jitsu, climbing, cycling, swimming, or any modality other than lifting and running
- GPS run tracking, live pace, or route mapping
- HealthKit / Strava / Garmin import or export (keep a `source` column on `run` and `session` for later; writing an `HKWorkout` is cheap natively and is the first v1.1 candidate)
- Apple Watch app, iPad layout, widgets other than the rest-timer Live Activity, landscape
- Android or web clients (the backend doesn't preclude them; the app does not consider them)
- Social features, feed, public sharing links, leaderboards, streaks, badges
- Nutrition or bodyweight tracking
- Exercise demo videos
- Admin UI (the CLI is enough)
- Kilogram units

---

## 16. Decisions log and build order

### Resolved

- Native iOS, not PWA; Swift 6 / SwiftUI / iOS 17+, iPhone only → §11
- Hosted FastAPI + Neon backend kept as pure storage + identity; CloudKit rejected because the user base is open-ended and identity shouldn't be bound to Apple IDs server-side → §10, §11
- N users with directional read-only shares, invite-only; Sign in with Apple → §2
- GRDB over SwiftData/Core Data → §10
- Engine runs on-device only; no Python mirror → §4, §10
- Core supersetted on every day type; `chest_fly` is push slot 7 → §3.3
- Leg day: hinge in slot 1 flips slot 2 to squat 8–12 → §3.3
- Trimming loop skips, never breaks; padding excludes slot 1 and supersets → §4.1
- Heavy slot requires loadable → §3.3
- Warm-ups: 50 % × 8, 75 % × 5 → §4.2
- Running volume plateaus at a target → §6
- Rebaseline snapshot derived from history → §4.4
- Natalie uses the same templates, rep bands, and progression rules; she also runs → §2
- No deload after a layoff; weights persist across breaks → §5.1
- Pounds throughout, kg toggle deferred → §2
- Runs and lifts may share a day → §2
- Deadlift/squat adjacency across days is acceptable and needs no scheduling logic → §3.4
- DNF severity keyed to which set failed → §5.4
- Lateral raise / rear delt progression uses the smallest stocked increment → §5.2
- HealthKit write deferred to v1.1 → §15

### Open (defaults assumed; confirm before step 2)

- Apple Developer Program membership and Team ID — assumed the owner will enrol.
- Repo: assumed a fresh repo (or the existing `exercise-app` if empty).
- Exact palette / type choices — to be settled in the design prototype, step 0.

### Build order

The engine carries the correctness risk; the design carries the product risk. Front-load both.

0. **Design prototype** (§8): a SwiftUI preview app with static data — start screen, one of each card, the rest timer, one chart, both appearance modes. Iterate with the owner until approved. Output: the `WorkoutUI` token set and components.
1. **`WorkoutEngine`**: §3 model + seed loading, §4 generator, §5 progression, §6 run plan, with the plan snapshot tests. Verify the plans are ones you'd actually run.
2. **Backend + `WorkoutStore`**: schema, migrations, outbox, `/sync`, Sign in with Apple, invites. Airplane-mode test passes before any deck UI exists — retrofitting local-first onto a networked app is painful.
3. **Deck UI** (§7) on the approved design system, including superset sequencing, swipe-to-substitute, rest timer + Live Activity.
4. **Running** (§6) and **Progress** (§12).
5. **Onboarding** (§14) and Settings (heavy rotation editor, equipment checklist, run targets) last — seed your own data directly until then.
6. TestFlight.
