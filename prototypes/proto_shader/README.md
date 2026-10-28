# mannequin_proto: SDF fragment-shader mannequin (approach B)

3D artist's mannequin ("Gliederpuppe") for calisthenics animations, raymarched in
`shaders/mannequin.frag`; skeleton / props / camera computed in Dart (`lib/mannequin/`).

## Regenerate renders

```sh
export PATH=/opt/sdk/flutter/bin:$PATH ANDROID_HOME=/opt/sdk/android
python3 tool/make_fixture.py assets/exercises.json          # only if pose data / 3D tweaks change
flutter test --update-goldens test/sheet_test.dart test/hero_test.dart test/extra_test.dart
python3 tool/compose_sheets.py   # out/sheet_dark.png sheet_light.png thumb_100px.png anim_strip.png hero_*.png extras.png
python3 tool/measure_fill.py dark_   # figure fill / centre per sheet cell
flutter test                     # full suite in compare mode (deterministic)
python3 tool/make_debug_shader.py && flutter test --dart-define=QUALITY=medium test/cost_test.dart   # march cost
flutter build web --no-web-resources-cdn && (cd build/web && python3 -m http.server 8765 &) ; node tool/web_shots.js 8765 out
```

## API

- `ExerciseAnimation.fromJson(anim)`: joint-space interpolation (shoulder/hip
  flexion relative to the torso, elbow/knee flexion relative to the parent
  segment, unwrapped into anatomical ranges), so near-180-degree keyframe
  differences can never swing a limb the wrong way. Optional `"view": {"yaw": 35, "avoid": [75, 105]}`.
- `Mannequin3DView(animation, interactive = true, playing = true, initialYaw = 30,
  usePreferredYaw = false, initialPitch = 12, background, fixedTime, resolutionScale,
  quality, fitToPose)`. `usePreferredYaw: true` starts at the exercise's preferred
  yaw instead (35 for horizontal bodies: levers incl. tucks, planche, flag).
- `MannequinSnapshot(animation, time, ...)`: renders once into an image (lists / thumbnails).
- `MannequinPainter` / `MannequinScene` can be driven directly (tests).

## Framing

- At rest and for static renders (`fixedTime`, sheets, snapshots) the camera fits the
  projected bounding box of ALL animation frames for the current yaw / pitch and
  centres it (figure ~85 % of the view, no rescale between frames).
- While the user drags, the framing blends (0.25 s) to a yaw-invariant one (fixed
  target, the distance that fits every yaw), so the rotation itself never zooms; on
  release it eases (0.35 s) to the per-yaw framing of the final yaw / pitch.
- Horizontal bodies snap out of the end-on yaw window (72..108 deg, mod 180) on release.
- Exercises whose animation travels a lot (muscle-up: hang -> support; pistol:
  standing -> bottom; dips) fill less of a static cell, because the all-frames
  envelope is framed (the figure must not rescale while animating).
- The contact sheets render yaw >= 75 cells at pitch 22 (others 12) so levers, dips
  and the flag keep some depth in the front view. The interactive view never rests
  there for horizontal bodies (snap window).

## Gestures

Horizontal drag = yaw, vertical drag = pitch (clamped -8..65). The view uses a pan
recognizer (slop 36 px), so inside a vertically scrolling page the scrollable's
vertical drag (slop 18 px) wins vertical gestures and the page scrolls; horizontal
drags rotate the figure (tested in `test/interaction_test.dart`).

## Rendering notes

- Grips: a hand within reach of a bar / parallel bar / pole becomes a fist centred on
  the grip axis; fingers form a cuff around the cylinder, the drawn wrist sits
  `MannequinRig.gripOffset` (2.3) back along the forearm. A wrist used as the
  animation anchor on a grip moves the whole figure back by that offset.
- Torso group = pelvis..neck plus both whole thighs (blend radius tapering along the
  thigh) and the neck, so there is no shelf at the thigh root and no crease at the collar.
- Quality tiers `MannequinQuality.low/medium/high` = 48/64/80 march steps, 2/3/4 AO taps.
- Resolution: auto = full resolution up to dpr 2; above that 2 physical px per logical
  px, never below 0.75 of the physical resolution, upscaled with `FilterQuality.medium`.
  The reduced path reuses its last offscreen image while nothing changes.
- Not profiled on a phone yet (no device here). First step on a mid-range Android:
  profile medium/low at the auto scale before lowering resolution further.
