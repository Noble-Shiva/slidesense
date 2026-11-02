# Changelog

All notable changes to SlideSense are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] — 2026-11-02

### Changed
- The 1 Hz refresh timer is gone. Volume and mute now arrive as CoreAudio
  property callbacks, and brightness is read when a finger lands and when the
  menu opens. The app no longer wakes up while the pad is untouched.
  (`AppCoordinator` had a timer behind a README that promised "no polling" —
  that was a fair catch, and the code now matches the claim.)

### Planned
- Magic Mouse top-edge support
- Per-edge actions beyond brightness and volume
- Onboarding tour with a live trackpad map

## [0.1.0] — 2026-11-02

The first public release.

### Added
- Volume on the right trackpad edge and brightness on the left, driven by raw
  `MultitouchSupport` contacts rather than an event tap.
- On-screen display: a real Liquid Glass capsule on macOS 26, a frosted HUD on
  macOS 13–15, with a 1 s auto-hide.
- Haptic tick on every level step, with light/medium/strong strength.
- Precise sliding (quarter steps), plus ⇧⌥ fine control while sliding.
- Quick Mute by double-tapping the top-right corner.
- Media strip along the bottom edge: swipe to skip tracks, double-tap to play or
  pause.
- Cursor freeze, bottom-quarter-only mode, required modifier, swap sides, and a
  vertical-axis flip for trackpads that report it backwards.
- Menu bar item with live volume and brightness readouts and a deliberately
  short menu.
- Four-tab settings window: Edges, Feel, Extras, General.
- Open at login via `SMAppService`.
- `--diagnose` and `--dump-touches` diagnostics.

### Notes
- Volume uses CoreAudio, brightness uses the private `DisplayServices` framework
  with a key-event fallback, media commands are posted as system key events.
- Builds are unsigned; downloaded copies need one right-click → Open.

[Unreleased]: https://github.com/shashvat1965/slidesense/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/shashvat1965/slidesense/releases/tag/v0.1.1
[0.1.0]: https://github.com/shashvat1965/slidesense/releases/tag/v0.1.0
