# Changelog

All notable changes to Hoku are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions `0.9.x` are public betas.

## [Unreleased]

### Added
- Keyboard shortcuts for the lights: toggle any room or zone, start a scene or switch everything off from
  anywhere on the Mac. A small capsule under the menu bar icon confirms what happened.
- English: the app, its notifications, the setup assistant and the Siri commands follow the system language
  (German or English).
- Connect with an existing application key instead of the link button, see the connection details and set
  the bridge address by hand (Settings → Bridge → Connection Details).
- Pin rooms and zones to the top and arrange them in your own order (Settings → Arrange Rooms).
- VoiceOver: cards, switches, sliders, the color wheel, scenes and shortcuts are labelled and adjustable.
- Sync detection: while Hue Sync or another sync app controls an entertainment area, Hoku says so on the
  home page and offers to stop it.

### Planned
- In-app updates via Sparkle (EdDSA-signed).

## [0.9.0] - 2026-11-09

First public beta.

### Added
- Setup assistant: install location check, Signify and light-sensitivity notices, "tell us about your home"
  (phone and wishes → what Hoku solves for you), Local Network permission explained before macOS asks,
  bridge pairing with countdown, menu bar coach mark, launch at login, Siri setup with Apple Home detection.
- Native menu bar app for Philips Hue with a Liquid Glass panel, light and dark mode, global shortcut ⌃⌥L.
- Room cards that work as dimmers (drag to set brightness), light dots, sky and light-cone visuals,
  hover preview.
- Expandable room cards (right-click or two-finger click) showing the room's lamps inline; the number of lamps
  shown adapts to the screen height.
- Hue scenes with living, slowly flowing scene tiles; the active scene glows.
- Trackpad haptic detents at 25 / 50 / 75 / 100 % while dragging; afterglow when switching everything off.
- Alarm with sunrise (including a sunrise preview), bedtime routine, sleep timer, lights off when the Mac locks.
- Device check: unreachable lamps, including lamps cut off by a wall switch.
- Learning suggestions based on your own usage – computed and stored only on your Mac.
- Siri without saying the app name ("Living room on") via personal shortcuts that Hoku creates for you,
  including spoken name variants and fuzzy name matching.
- App Intents for the Shortcuts app; usable from Control Center via Shortcuts controls.
- `hoku://` URL commands (German and English vocabulary).

### Changed
- Robust against changes made in the Hue app: old names keep working, Hoku reloads after lamps or rooms are
  added or removed.
- Calmer design: one-line header, rounded bars, text colour switches exactly at the bar edge, more restrained
  suggestion chip, less text per card.

### Fixed
- `hoku://alle/an` ("all on") switched everything off; it is now rejected.
- Scene lookup without a room is deterministic (prefers rooms that are currently on).

### Performance
- 0 % CPU while the panel is closed (previously about 12 %); continuous animations pause when hidden.
- JSON decoding 3–4× faster; fewer redraws (menu bar icon redraws are coalesced).

### Security
- TLS certificate pinning to the Hue Bridge (Signify certificates).
- Bridge credentials are stored in a private file (mode 0600) and written atomically.

### Fixed (since the first test builds)
- A room no longer blinks after switching one of its lamps off; rooms follow their lamps at once.
- The greeting follows the time of day again after the panel was closed for a while.

[Unreleased]: https://github.com/Philoni/hoku/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/Philoni/hoku/releases/tag/v0.9.0
