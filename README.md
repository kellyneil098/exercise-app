# exercise-app

Native iOS workout tracker for strength training and running, with a small FastAPI sync backend.

- Spec: [`docs/workout-app-spec.md`](docs/workout-app-spec.md)
- Seed data (exercise catalog, movement patterns, equipment, validator): [`seed/`](seed/)

Run `python3 seed/validate_seed.py` after editing any seed file.

## Shipping to TestFlight

`.github/workflows/testflight.yml` archives and uploads on `workflow_dispatch` or a `v*` tag. It needs three repo secrets:
`APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_P8` (the `.p8` contents).
Marketing version lives in `ios/WorkoutApp/project.yml` (`MARKETING_VERSION`); the build number is the CI run number.
