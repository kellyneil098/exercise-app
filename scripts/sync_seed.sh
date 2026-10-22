#!/usr/bin/env bash
# seed/ is canonical; the Swift package ships a copy. Run after editing seed/*.json.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 seed/validate_seed.py
cp seed/*.json ios/Packages/WorkoutEngine/Sources/WorkoutEngine/Seed/
echo "seed synced"
