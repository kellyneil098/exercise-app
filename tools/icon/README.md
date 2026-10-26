# App icons

`app_icon.py` draws each icon as an SVG and renders it to a 1024×1024 opaque PNG in the asset catalog
(`ios/WorkoutApp/Resources/Assets.xcassets`). One variant per app theme:

| variant   | theme            | asset set                | description |
|-----------|------------------|--------------------------|-------------|
| `classic` | Default          | `AppIcon.appiconset`       | "Kettlebell buddy" — brass kettlebell with a face on near-black (primary icon) |
| `hunny`   | Winnie the Pooh  | `AppIcon-Hunny.appiconset` | "Hunny-pot kettlebell" — storybook honey pot with a kettlebell handle on parchment (alternate icon) |

```sh
pip3 install --user pillow             # the only Python dependency
python3 tools/icon/app_icon.py                   # regenerate both
python3 tools/icon/app_icon.py --variant hunny   # one variant
python3 tools/icon/app_icon.py --variant hunny --svg > hunny.svg
python3 tools/icon/preview.py ios/WorkoutApp/Resources/Assets.xcassets/AppIcon-Hunny.appiconset/AppIcon-Hunny.png preview.png
```

Rendering uses headless Chrome (PATH or `/Applications/Google Chrome.app`), falling back to `rsvg-convert`, then `cairosvg`.
`preview.py` composites an icon at 180/120/60 px on light and dark home-screen mocks.

The alternate set is compiled in via `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: AppIcon-Hunny` in
`ios/WorkoutApp/project.yml` and applied at runtime with `AppIconSwitcher.apply("AppIcon-Hunny")` (or `nil` for the primary).
