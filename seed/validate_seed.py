#!/usr/bin/env python3
"""
Validates the seed data and simulates whether a given equipment inventory can
actually produce a full workout for every day type.

Run this after ANY edit to the seed files. The coverage simulation is the point:
it tells you the minimum equipment your building gym needs before the generator
starts silently dropping slots.

    python3 validate_seed.py
    python3 validate_seed.py --gym minimal
"""

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).parent

# A plausible small apartment-building gym. Edit to match reality, then re-run.
MINIMAL_GYM = {
    "bodyweight", "dumbbells", "bench_adjustable", "bench_flat",
    "cable_machine", "treadmill",
}
MINIMAL_GYM_DUMBBELL_MAX = 50


def load():
    eq = json.loads((HERE / "equipment_types.json").read_text())
    mp = json.loads((HERE / "movement_patterns.json").read_text())
    ex = json.loads((HERE / "exercises.json").read_text())
    return eq, mp, ex


def check_integrity(eq, mp, ex):
    errors, warnings = [], []

    equipment_keys = {e["key"] for e in eq["equipment_types"]}
    # The equipment list is the master catalog every gym selects from; the app groups it by category.
    for e in eq["equipment_types"]:
        if not isinstance(e.get("category"), str) or not e["category"].strip():
            errors.append(f"equipment '{e['key']}': category must be a non-empty string")
        if not isinstance(e.get("label"), str) or not e["label"].strip():
            errors.append(f"equipment '{e['key']}': label must be a non-empty string")
    eq_keys_list = [e["key"] for e in eq["equipment_types"]]
    for k in {k for k in eq_keys_list if eq_keys_list.count(k) > 1}:
        errors.append(f"duplicate equipment key: {k}")
    pattern_keys = {p["key"] for p in mp["movement_patterns"]}
    exercise_keys = set()

    for e in ex["exercises"]:
        key = e["key"]
        if key in exercise_keys:
            errors.append(f"duplicate exercise key: {key}")
        exercise_keys.add(key)

        if e["movement_pattern"] not in pattern_keys:
            errors.append(f"{key}: unknown movement_pattern '{e['movement_pattern']}'")

        for req in e["required_equipment"]:
            if req not in equipment_keys:
                errors.append(f"{key}: unknown equipment '{req}'")

        if e.get("measure") == "seconds":
            if "range_low" not in e or "range_high" not in e:
                errors.append(f"{key}: timed exercise missing range_low/range_high")
        elif "rep_seconds" not in e:
            errors.append(f"{key}: missing rep_seconds")

        if e.get("dumbbell_based") and "dumbbells" not in e["required_equipment"]:
            errors.append(f"{key}: dumbbell_based but does not require dumbbells")

    # Every slot template pattern must resolve
    for day, slots in mp["slot_templates"].items():
        for slot in slots:
            pat = slot["pattern"]
            if pat == "heavy_rotation":
                for rot_pat in mp["heavy_rotation_defaults"][day]:
                    if rot_pat not in pattern_keys:
                        errors.append(f"{day} heavy rotation: unknown pattern '{rot_pat}'")
            elif pat not in pattern_keys:
                errors.append(f"{day} slot {slot['slot']}: unknown pattern '{pat}'")
            for alt in slot.get("alt_pattern_if_slot1_pattern", {}).values():
                if alt not in pattern_keys:
                    errors.append(f"{day} slot {slot['slot']}: unknown alt pattern '{alt}'")

    # Every pattern should have at least one exercise
    by_pattern = defaultdict(list)
    for e in ex["exercises"]:
        by_pattern[e["movement_pattern"]].append(e["key"])
    for p in pattern_keys:
        if not by_pattern[p]:
            errors.append(f"pattern '{p}' has no exercises")
        elif len(by_pattern[p]) < 3:
            warnings.append(
                f"pattern '{p}' has only {len(by_pattern[p])} exercise(s) — "
                "thin substitution pool"
            )

    # Ratio table sanity
    for src, targets in mp["ratio_table"].items():
        if src.startswith("$"):
            continue
        if src not in exercise_keys:
            warnings.append(f"ratio_table source '{src}' is not an exercise key")
        for tgt in targets:
            base = tgt.replace("_added_load", "")
            if base not in exercise_keys:
                warnings.append(f"ratio_table target '{tgt}' is not an exercise key")

    # Seeded locations: keys are stable ids stamped on user rows; a former name must not be any seed's current name,
    # or the app's rename-on-launch (previous_names -> name) would fight itself.
    loc_keys = [loc["key"] for loc in eq["locations"]]
    for k in {k for k in loc_keys if loc_keys.count(k) > 1}:
        errors.append(f"duplicate location key: {k}")
    current_names = {loc["name"] for loc in eq["locations"]}
    for loc in eq["locations"]:
        for k in loc.get("default_equipment", []):
            if k not in equipment_keys:
                errors.append(f"location {loc['key']}: default_equipment '{k}' is not an equipment key")
        if loc.get("default_available") and "default_equipment" in loc:
            errors.append(f"location {loc['key']}: default_available gyms start with everything; drop default_equipment")
    for loc in eq["locations"]:
        prev = loc.get("previous_names", [])
        if not isinstance(prev, list) or not all(isinstance(n, str) and n for n in prev):
            errors.append(f"location {loc['key']}: previous_names must be a list of non-empty strings")
            continue
        for n in prev:
            if n in current_names:
                errors.append(f"location {loc['key']}: previous name '{n}' is a current location name")

    return errors, warnings, by_pattern


def check_coverage(mp, ex, available, dumbbell_max, label):
    """Can this inventory fill every slot for every day type?"""
    print(f"\n=== Coverage: {label} ===")
    if dumbbell_max:
        print(f"    (dumbbell ceiling {dumbbell_max} lb — "
              "not applied here, it gates per-user at runtime)")

    def usable(e):
        return all(r in available for r in e["required_equipment"])

    def heavy_ok(e):
        # §4.1: the 5-8 slot needs a loadable exercise (no 5-rep push-ups)
        return e.get("loadable", True)

    by_pattern = defaultdict(list)
    for e in ex["exercises"]:
        if usable(e):
            by_pattern[e["movement_pattern"]].append(e)

    gaps = []
    for day, slots in mp["slot_templates"].items():
        print(f"\n  {day.upper()}")
        for slot in slots:
            pat = slot["pattern"]
            if pat == "heavy_rotation":
                rot = mp["heavy_rotation_defaults"][day]
                for rot_pat in dict.fromkeys(rot):
                    cands = [c for c in by_pattern.get(rot_pat, []) if heavy_ok(c)]
                    mark = "ok " if cands else "GAP"
                    best = max(cands, key=lambda c: c.get("rank_hint", 0))["name"] if cands else "— none —"
                    print(f"    [{mark}] slot 1 heavy / {rot_pat:<20} {len(cands):>2} option(s)  → {best}")
                    if not cands:
                        gaps.append(f"{day} heavy rotation entry '{rot_pat}'")
            else:
                pats = [pat] + list(slot.get("alt_pattern_if_slot1_pattern", {}).values())
                for p in pats:
                    cands = by_pattern.get(p, [])
                    mark = "ok " if cands else "GAP"
                    best = max(cands, key=lambda c: c.get("rank_hint", 0))["name"] if cands else "— none —"
                    tag = f"slot {slot['slot']}" if p == pat else f"slot {slot['slot']} alt "
                    print(f"    [{mark}] {tag:<11} {p:<26} {len(cands):>2} option(s)  → {best}")
                    if not cands:
                        gaps.append(f"{day} slot {slot['slot']} ({p})")
    return gaps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gym", choices=["all", "minimal", "both"], default="both")
    args = ap.parse_args()

    eq, mp, ex = load()
    errors, warnings, by_pattern = check_integrity(eq, mp, ex)

    print(f"Loaded {len(ex['exercises'])} exercises, "
          f"{len(mp['movement_patterns'])} patterns, "
          f"{len(eq['equipment_types'])} equipment types.")

    if errors:
        print("\nERRORS:")
        for e in errors:
            print(f"  ✗ {e}")
    if warnings:
        print("\nWarnings:")
        for w in warnings:
            print(f"  ! {w}")
    if not errors and not warnings:
        print("\nIntegrity: clean.")

    all_equipment = {e["key"] for e in eq["equipment_types"]}
    gaps = []
    if args.gym in ("all", "both"):
        gaps += check_coverage(mp, ex, all_equipment, 120, "Crunch USQ (everything)")
    if args.gym in ("minimal", "both"):
        gaps += check_coverage(mp, ex, MINIMAL_GYM, MINIMAL_GYM_DUMBBELL_MAX,
                               "The Victoria (assumed minimal)")

    if gaps:
        print("\n--- SLOTS THAT CANNOT BE FILLED ---")
        for g in gaps:
            print(f"  ✗ {g}")
        print("\nThe generator will silently skip these slots. Either add the "
              "equipment to the inventory, or add exercises covering the pattern.")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
