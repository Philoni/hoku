<p align="center"><img src="docs/images/icon.png" width="128" alt="Hoku icon"></p>
<h1 align="center">Hoku</h1>

<p align="center"><strong>Your Philips Hue lights in the Mac menu bar – with Siri, no iPhone required.</strong></p>
<p align="center"><sub>Native macOS app · local only, no cloud, no account · free and open source</sub></p>

<p align="center">
  <a href="https://github.com/Philoni/hoku/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/Philoni/hoku?style=flat"></a>
  <a href="https://github.com/Philoni/hoku/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/Philoni/hoku/total?style=flat"></a>
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-blue?style=flat">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-orange?style=flat">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/Philoni/hoku?style=flat"></a>
  <a href="https://github.com/Philoni/hoku/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/Philoni/hoku/actions/workflows/ci.yml/badge.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/Philoni/hoku/releases/latest"><strong>Download</strong></a> ·
  <a href="https://philoni.github.io/hoku/">Website</a> ·
  <a href="docs/help/">Help</a> ·
  <a href="docs/help/faq.md">FAQ</a> ·
  <a href="README.de.md">Deutsch</a>
</p>

<p align="center"><img src="docs/images/hero.jpg" alt="Hoku: room view, overview with an expanded room, and setup"></p>
<p align="center"><em>The screenshots show the German interface. The app follows your system language, German or English.</em></p>

---

## Why Hoku

You have a Mac and Philips Hue, but Siri on the Mac knows nothing about your lamps. The reason is Apple Home: lights can only be added to it with an iPhone or iPad.

Hoku closes that gap. It talks directly to your Hue Bridge, puts every room, lamp and scene in the menu bar, and sets up Siri commands that work on the Mac itself. Many things are also quicker than in a phone app.

## What it does

- **One click, all bright:** rooms and zones as glowing cards. Drag to dim, flip the switch to turn on or off, and a **two-finger click unfolds a room's lamps**.
- **Siri without the app name:** "Hey Siri, living room on", "display cabinet off", "all off". Hoku creates personal shortcuts for this. Spellings such as "Light Strip" and singular/plural are understood.
- **Hue scenes:** preview on hover, dynamic scenes with a speed slider, favourite scenes first.
- **Wake-up and sleep:** wake-up light with sunrise (including a time-lapse preview), "go to sleep" and a sleep timer. These run on the bridge, even while the Mac sleeps.
- **Lights off when you leave:** when you lock or close the Mac, and back on when you return.
- **Keyboard shortcuts for the lights:** toggle rooms and zones, start scenes or switch everything off with your own key combinations, from anywhere on the Mac. A small capsule under the menu bar icon confirms what happened.
- **Keyboard and gestures:** ⌃⌥L opens Hoku from anywhere, arrow keys control, swiping dims.
- **Arrange and pin:** pin rooms and zones to the top and put them in your own order.
- **Connection options:** pair with the link button, use an existing application key, view the connection details or set the bridge address by hand.
- **Sync detection:** while Hue Sync or another sync app controls an entertainment area, Hoku says so on the home page and offers to stop it.
- **VoiceOver:** cards, switches, sliders, the color wheel, scenes and shortcuts are labelled and adjustable.
- **German and English:** the app, notifications, setup and Siri commands follow the system language.
- **Device check:** empty batteries, unreachable lamps, pending updates.
- **Learns along:** suggests the scene you usually pick at that time of day. Computed and stored only on your Mac.
- **Light on your Mac:** 0 % CPU while the window is closed.

| Overview | Room | Setup |
|---|---|---|
| ![Overview](docs/images/home-dark.jpg) | ![Room](docs/images/room.jpg) | ![Setup in nine steps](docs/images/wizard-steps.jpg) |

## Who it is for

Hoku asks about your equipment during setup and configures exactly what is missing.

| Your equipment | What is missing without Hoku | What Hoku gives you |
|---|---|---|
| **Mac + Android phone** (or no phone at all) | No Apple Home is possible, so Siri on the Mac does not know your lamps, and there is no Hue control on the Mac | **"Hey Siri, living room on" right on the Mac**, plus all rooms, lamps and scenes in the menu bar |
| **Mac + iPhone, Hue not in Apple Home** | Siri on the Mac does not know your lamps until you set up Apple Home | Siri commands right away, without Apple Home, or Hoku shows you the way there |
| **Mac + iPhone with Apple Home** | Home can do on/off and brightness, but no real Hue scenes, no dynamic scenes, no Hue routines | Hue scenes including dynamic ones and speed, **wake-up light with sunrise**, sleep timer, device check, all quick from the menu bar |
| **Several people / Macs in the household** | Only the phone of the person who set up Hue "knows" everything | Each Mac pairs on its own, with its own Siri commands and favourite scenes |
| **You tried Hue Sync** | Hue Sync makes lights dance to films, games and music on the computer, but it does not control rooms, single lamps or scenes for everyday use | **Every room, every lamp, every scene** in the menu bar. You can still keep Hue Sync for effects |
| **Privacy matters to you** | Many apps need an account or the Hue cloud | Hoku talks **only to your bridge on the home network**. No account, no telemetry |

### Hoku or Hue Sync?

Both, depending on the task: Hue Sync makes your light dance to the screen. Hoku is your light switch on the Mac.

## Install

**Requirements:** macOS 26 (Tahoe) or later. A Hue Bridge v2 (square) or Bridge Pro on the same network as your Mac. For personal Siri commands: signed in to the Mac with an Apple Account (iCloud).

### Download

1. Download the **DMG** `Hoku-X.Y.Z.dmg` from [Releases](https://github.com/Philoni/hoku/releases/latest) and open it.
2. **Drag Hoku to Applications.** Eject the disk image afterwards; several copies confuse Siri.
3. Open Hoku. macOS says Apple could not check the app, so click **Done**.
4. **System Settings → Privacy & Security**, scroll to the bottom, click **Open Anyway** next to "Hoku" and confirm.

This is needed **only once**. Why? Hoku is free, and Apple's notarization costs $99 per year. Hoku is therefore signed with its own long-lived certificate but not notarized by Apple.
Step by step with pictures: [Install](docs/help/installieren.md).

### Homebrew

```bash
brew tap philoni/hoku
brew trust philoni/hoku
brew install --cask hoku
```

Update later with `brew upgrade --cask hoku`.

### Build from source

You need Xcode 27 and a free Apple ID (Xcode → Settings → Accounts → Personal Team → "Apple Development" certificate):

```sh
brew install xcodegen
git clone https://github.com/Philoni/hoku.git && cd hoku
make install    # builds, installs to ~/Applications and launches Hoku
```

`make test` runs the tests. The structure of the code is explained in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## First launch

A short assistant walks you through everything: your equipment, the network permission (explained first, then asked), pairing with the bridge (press the round button once), launch at login, and Siri.
You can find it again under **Settings → Restart Setup**.

## Help

The help pages are bilingual (German and English).

- [Install](docs/help/installieren.md) · [Set up Siri](docs/help/siri.md) · [Gestures & keyboard](docs/help/gesten-und-tastatur.md)
- [Troubleshooting](docs/help/fehlerbehebung.md) · [FAQ](docs/help/faq.md) · [Privacy](docs/help/datenschutz.md)
- Found a bug or have an idea? [Open an issue](https://github.com/Philoni/hoku/issues/new/choose)

## Privacy

Hoku talks **directly to your Hue Bridge on your network** – no cloud, no account, no telemetry. The bridge key stays on your Mac.
Only two things go to the internet: the bridge search at Signify (`discovery.meethue.com`), in case the bridge does not show up on the network by itself, and macOS signing your Siri shortcuts via iCloud. Details: [Privacy](docs/help/datenschutz.md).

## Notices

> **Hoku is not an app from Signify.** Hoku is an independent open-source project by Philoni and is not an app, product or service of Signify (Philips Hue). Signify neither makes, supports nor reviews Hoku; Philoni alone is responsible for it. Philips and Philips Hue are trademarks of their respective owners.

> **Light and health:** Certain light colours, fast changes or flashing can cause discomfort and, for people sensitive to light (for example with photosensitive epilepsy), seizures or migraines. If you feel unwell, stop the effect, scene or Hoku immediately.

## Status and roadmap

Hoku is a **beta**. It is available in German and English, following the system language (from 0.9.1). Automatic updates are planned. See the [CHANGELOG](CHANGELOG.md) for what is coming next.

## Contributing and license

Contributions are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). Hoku is released under the [MIT License](LICENSE); third-party work used is listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
