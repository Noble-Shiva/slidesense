# SlideSense

**Slide the edges of your MacBook trackpad to change volume and brightness.**

SlideSense is a free, MIT-licensed menu bar app for macOS 13+. The left and right
edges of the trackpad become a brightness and volume slider, with haptics, a
matching on-screen display, quick mute, and a media strip along the bottom edge.

```
        ┌───────────────────────────────┐
        │                               │
  bright│ · · · · · · · · · · · · · · · │volume
        │                               │
        └───────────────────────────────┘
              ^ swipe up/down on an edge
```

## Features

| | |
|---|---|
| **Left edge → brightness** | Slide up/down anywhere along the left band. |
| **Right edge → volume** | Slide up/down anywhere along the right band. |
| **On-screen display** | A Liquid Glass panel on macOS 26, a frosted HUD before that. |
| **Haptics** | A physical tick as the level crosses each step. |
| **Precise sliding** | Quarter steps instead of sixteenths — always on, or only while holding ⇧⌥. |
| **Bottom quarter only** | Restrict the side bands to the lower quarter of the pad. |
| **Require a modifier** | Demand FN, Option or Control before an edge responds. |
| **Cursor freeze** | The pointer stays put and hidden while you slide. |
| **Quick Mute** | Double-tap the top-right corner. |
| **Media strip** | Swipe along the bottom edge to skip; double-tap to play/pause. |
| **Swap sides** | Brightness on the right if you prefer. |
| **Menu bar only** | No Dock icon. Idle CPU is effectively zero. |
| **Open at login** | Via `SMAppService`, no helper daemon. |

## Requirements

- macOS 13 Ventura or later (Liquid Glass appears on macOS 26)
- A built-in Force Touch trackpad (the one in every MacBook since 2015)
- Xcode 15+ **or** the Swift 6 toolchain, to build
- Accessibility permission for the media strip and key-event fallbacks

Magic Mouse support is not implemented yet — see [Roadmap](#roadmap).

## Build and run

```bash
git clone https://github.com/<you>/slidesense.git
cd slidesense

make app        # builds SlideSense.app in the repo root
make run        # builds and opens it
make install    # copies it to /Applications
make test       # runs the unit and UI-layout tests
```

The app is ad-hoc signed (`codesign --sign -`) so it runs locally without a
Developer ID. Because the signature changes on every rebuild, macOS may ask for
Accessibility permission again after a rebuild — that is expected.

On first launch macOS shows an Accessibility prompt. Approve it in
**System Settings → Privacy & Security → Accessibility**. Without it the edge
sliders still work; the media strip and any key-event fallback do not.

> Gatekeeper: if you download a prebuilt copy, right-click → Open the first time.
> This project does not ship notarised binaries.

## How to use it

| Gesture | Result |
|---|---|
| Slide up/down on the left band | Brightness |
| Slide up/down on the right band | Volume |
| Hold ⇧⌥ while sliding | Quarter steps |
| Double-tap the top-right corner | Mute / unmute |
| Swipe left/right on the bottom band | Next / previous track |
| Double-tap the bottom band | Play / pause (off by default) |

A slide always starts from the current system level, so you can nudge from
wherever you are. Because the level is absolute, dragging back down gives the
value back instead of drifting.

Multi-finger touches are left alone: as soon as a second finger lands, SlideSense
hands the gesture back to macOS, so scrolling, zooming and swiping still work.
Touches that start in the middle of the pad are ignored, and quick taps on an
edge do nothing.

## The menu

Deliberately short:

```
Volume        81%
Brightness    69%
─────────────
✓ Enabled
Settings…     ⌘,
─────────────
Quit SlideSense ⌘Q
```

The two readouts are live and non-interactive. Everything else lives in
Settings, so the menu stays a glance, not a control panel.

## Settings

Four tabs in a standard macOS preferences window:

- **Edges** — what each side controls, band width, sensitivity, bottom-quarter
  mode, required modifier, vertical-axis flip.
- **Feel** — cursor freeze, precise sliding, ⇧⌥ fine control, haptics and
  strength.
- **Extras** — Quick Mute, media strip, reverse swipe, tap to play/pause.
- **General** — Accessibility permission, HUD visibility and appearance, open at
  login, restore defaults.

Settings are stored as JSON under `io.github.slidesense.settings.v1` in
`UserDefaults`.

## How it works

Three small pieces, no background daemon, no kernel extension:

1. **Reading the trackpad** — `MultitouchSupport.framework`, Apple's private
   multitouch driver, is loaded with `dlopen`. Its contact-frame callback gives
   normalised finger positions (0…1, origin bottom-left) at the hardware frame
   rate. This is the same API used by many open-source trackpad utilities and is
   why SlideSense needs no event tap, no polling, and no CPU when nothing is
   touching the pad.

2. **Deciding what a gesture means** — `SlideEngine` is a pure state machine: it
   takes frames of contacts and emits `beginSlide` / `updateSlide` / `endSlide` /
   `media` events. Edge geometry, corner detection, tap vs. slide, double-tap,
   dropped-frame tolerance and step quantisation all live here, which is why they
   are covered by unit tests and can be exercised without a trackpad.

3. **Changing the system level** — volume goes through CoreAudio
   (`AudioObjectSetPropertyData` on the default output device, with fallbacks for
   devices that only expose per-channel scalars). Brightness goes through
   `DisplayServices.framework` (`DisplayServicesSetBrightness`), the same private
   framework the brightness keys use; if it is unavailable SlideSense falls back
   to posting brightness key events. Media commands are posted as system-defined
   key events (`NX_KEYTYPE_PLAY`, etc. via `CGEvent.post`).

Private frameworks are, by definition, not guaranteed to keep working across
macOS releases. `MultitouchSupport` and `DisplayServices` have been stable for
many years and are used by a large number of shipping apps, but treat this as
"works today" rather than "Apple promises it". Every private call is
feature-detected: if it disappears, the app degrades instead of crashing.

### The HUD

The panel is 210 × 60 pt with a 16 pt continuous corner radius, a 14 pt content
inset, a 22 pt icon box, a 12 pt gap and an 8 pt level bar with 4 pt caps. On
macOS 26 and later the background is a real `NSGlassEffectView` (Liquid Glass);
on macOS 13–15 it falls back to an `NSVisualEffectView` with the `.hudWindow`
material. Both draw the same content, so the layout is identical on every OS.

### Where the bars are

Normalised trackpad coordinates are `x: 0 (left) → 1 (right)` and
`y: 0 (bottom, near you) → 1 (top, near the screen)`. The edge band is
`edgeWidth` wide (default 18 %). If your Mac reports the vertical axis the other
way round, the **Flip vertical edges** setting corrects it.

## Testing

```bash
make test            # geometry, gesture engine, HUD layout, settings window
make snapshots       # writes PNGs of every UI state to ./Snapshots
```

`make snapshots` renders the HUD in nine states (0 %, 1 %, 50 %, 100 %, muted,
brightness, and three media symbols) and the settings window on all four tabs, in
light and dark appearance, at 2× — so padding and alignment can be checked
without a screen recording permission.

Diagnostics: `make dump-touches` prints live contacts (`id`, `x`, `y`, touch
state) and `swift run SlideSense --diagnose` prints the state of every subsystem.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Nothing happens on the edges | Check the menu bar shows ✓ Enabled, and that **Edge width** is not too small. |
| Volume works, brightness does not | Your display may not expose `DisplayServices` brightness (external monitors). SlideSense falls back to key events, which only affect the built-in panel. |
| Sliding up decreases the level | Turn on **Flip vertical edges** in Settings → Edges. |
| Media keys do nothing | Grant Accessibility access in Settings → General. |
| Permission prompt keeps coming back | Ad-hoc signatures change on rebuild; re-approve, or sign with a stable certificate. |
| Slides stop halfway | Update — 0.1.0 tolerates a dropped contact for ~120 ms. |
| Two-finger gestures feel different | They are untouched by design; if something still feels off, disable **Media strip**, which owns the bottom band. |
| Trackpad stops after sleep | SlideSense restarts the device 1.5 s after wake; if it persists, toggle the app off/on from the menu. |

## Privacy

No network access, no analytics, no crash reporting, no accounts. Everything is
local: the app reads the trackpad, writes volume/brightness, and stores its own
settings in `UserDefaults`.

## Roadmap

- [ ] Magic Mouse top-edge support
- [ ] Per-edge actions beyond brightness/volume (keyboard backlight, scroll speed)
- [ ] Onboarding tour with a live trackpad map
- [ ] Notarised release builds
- [ ] Menu bar icon themes

## Project layout

```
Sources/SlideSenseCore/
  Model/         Settings, edge geometry, the gesture state machine
  Multitouch/    dlopen bindings for MultitouchSupport + the frame monitor
  System/        CoreAudio, DisplayServices, media keys, haptics, permissions
  UI/            Menu bar item, settings window, HUD
  AppCoordinator.swift, AppDelegate.swift
Sources/SlideSense/    entry point
Tests/SlideSenseCoreTests/  geometry, gesture engine, HUD layout, settings window
scripts/build-app.sh       assembly + ad-hoc signing
scripts/make-icon.swift    icon generator
```

## Contributing

Issues and pull requests are welcome. Run `make test` before sending a change,
and keep hardware-facing code behind a protocol so it can be faked in tests.

## Licence

MIT — see [LICENSE](LICENSE).
