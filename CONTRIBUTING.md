# Contributing to Hoku

Thanks for helping! Hoku is a small, free, open-source menu bar app for Philips Hue, maintained by one person
in his spare time. Issues and pull requests in **English or German** are equally welcome.

> **Deutsch:** Beiträge auf Deutsch sind ausdrücklich willkommen – Issues, Diskussionen und PRs.
> Die Code-Kommentare und Commit-Nachrichten sind auf Englisch.

## Before you start
- **Questions and ideas** → [Discussions](https://github.com/Philoni/hoku/discussions). **Bugs** → an issue using the bug form.
- **Security problems** → never in a public issue. See [SECURITY.md](SECURITY.md).
- **Bigger changes** (new screens, new dependencies, anything touching signing, updates or the Siri setup):
  please open an issue or discussion first, so we can agree on the approach before you spend time on it.
- Hoku is **local-only by design**: no accounts, no cloud services, no analytics or telemetry. PRs that add any
  of these will not be merged.

## Set up the project
Requirements: macOS 26, **Xcode 27**, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`),
a free Apple ID in Xcode (Settings → Accounts → Personal Team → Manage Certificates → + → Apple Development),
and a Hue Bridge (v2 or Pro) for manual testing.

```sh
git clone https://github.com/Philoni/hoku.git && cd hoku
make install      # XcodeGen → xcodebuild → ~/Applications/Hoku.app, then launches it
make test         # HueKit unit tests (no bridge needed)
```
`make build` only builds. The Xcode project is generated from `project.yml` – edit that file, not `Hoku.xcodeproj`
(it is not committed). A plain `swift build` is not enough: Siri and Shortcuts need the App Intents metadata
that only Xcode produces.

Keep **only one** copy of Hoku registered on your Mac (`make install` takes care of that). Several copies confuse
Siri, Shortcuts and the Local Network permission.

## How the code is organised
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The short version:
- **Logic goes into `Packages/HueKit`** (Swift package, no UI, unit-tested). **UI and macOS integration go into `App/`.**
- One folder per screen under `App/Features/`. Shared UI lives in `App/DesignSystem/`.

## Ground rules for changes
- **Swift 6 with strict concurrency.** No new warnings.
- **Tests:** new logic in HueKit comes with unit tests (`cd Packages/HueKit && swift test`). Tests must never change
  anything on a real bridge. Live tests (`HOKU_LIVE_BRIDGE=1`) are read-only.
- **Energy:** continuous animations only via `TimelineView(… paused: !isPanelVisible)`. Hoku must stay at 0 % CPU
  while the panel is closed.
- **Store updates:** only assign store models when they actually changed (avoids redraws).
- **Texts in both languages:** every user-facing string goes through the String Catalog with German **and** English.
  German is the source language. If you only speak one of them, say so in the PR – we'll fill in the other.
- **No new dependencies** without prior discussion. Hoku has none so far (Sparkle for in-app updates is planned).
- **Philips Hue:** do not add Hue logos, icons, product photos or other Signify assets. Hoku may only say
  "for Philips Hue" / "works with Philips Hue".
- **Privacy in examples:** no real bridge keys (`hue-application-key`), bridge IDs, IP addresses or personal room
  names in code, fixtures, screenshots or logs. Use made-up names ("Living Room", "Desk Lamp").

## Pull requests
1. Fork, create a branch from `main` (`fix/…`, `feature/…`).
2. Keep PRs small and focused – one topic per PR.
3. Commit messages: short, imperative, English (`Show unreachable lamps in the device check`).
4. Fill in the PR template: what changed, why, how you tested it (macOS version, bridge model), screenshots
   for UI changes (light **and** dark mode).
5. CI must be green. PRs are merged with **squash**, so don't worry about a tidy commit history.

By contributing you agree that your contribution is licensed under the project's [MIT License](LICENSE).

## Releases (maintainer only)
Releases are built and signed by GitHub Actions from a `vX.Y.Z` tag and published by hand after testing.
Signing keys never leave the protected `release` environment. See `.github/workflows/release.yml`.

## Code of Conduct
This project follows the [Contributor Covenant 2.1](CODE_OF_CONDUCT.md). Be kind – everyone here is a volunteer.
