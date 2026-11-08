# Hoku – Aufbau des Codes

Kurzüberblick für alle, die am Code arbeiten. Grundregel: **Logik in HueKit (testbar), Oberfläche und Systemanbindung in App.**

## Packages/HueKit – das Herz (Swift Package, ohne UI)
| Ordner | Inhalt |
|---|---|
| `Models/` | Hue-Ressourcen (`Light`, `HueGroup`, `HueScene` …), `JSONValue` (rohes JSON) und `JSONValueDecoder` (schnelles Dekodieren direkt aus `JSONValue`) |
| `Networking/` | `HueClient` (REST), `EventStream` (SSE), `BridgeTrust` (TLS-Pinning auf Signify-Zertifikate), Suche & Kopplung, `HueRemote` (für App Intents) |
| `Store/` | `HueStore` (Live-Spiegel der Bridge, optimistische Schreibvorgänge, Drosselung), Erweiterungen für Routinen und Geräte-Check, `SpokenNames` (tolerante Namenssuche), `NameHistory` (frühere Namen), `EntitySnapshot` (Liste für Siri), `UsageLog` (Lernvorschläge), `CredentialStore` |
| `Commands/` | `URLCommand` (`hoku://…`), `SiriCommand` (welche Siri-Befehle angeboten werden) |
| `Color/` | Farbumrechnung xy ↔ RGB ↔ Mirek |

Tests: `cd Packages/HueKit && swift test` (Lasttests: `swift test -c release --filter PerformanceTests`, gegen die echte Bridge – nur lesend: `HOKU_LIVE_BRIDGE=1 swift test --filter LiveBridgeTests`).

## App – Oberfläche und macOS
| Ordner | Inhalt |
|---|---|
| `HokuApp.swift` | Einstieg, App-Delegate, URL-Befehle |
| `Model/` | `AppModel` (Lebenszyklus, Kopplung, Automationen, Siri-Abgleich), Einstellungen |
| `Panel/` | Menüleisten-Symbol, Glas-Panel (`LightPanel`), `RootView` (Navigation) |
| `DesignSystem/` | Theme, `SliderCard`, Bedienelemente, Layout-Helfer, Himmel, Lichtkegel, Tastatursteuerung |
| `Features/` | Je Bildschirm ein Ordner: `Home`, `Room`, `Light`, `Routines`, `Devices`, `Settings`, `Onboarding` |
| `Integrations/` | App Intents (Siri/Kurzbefehle), Erzeugen und Signieren der persönlichen Siri-Kurzbefehle |
| `System/` | Globales Tastenkürzel, Scroll-Dimmen, Rechtsklick-Erkennung |
| `Support/` | Farben/Symbole für Hue-Daten, Szenen-Vorschau |
| `Debug/` | `HOKU_SNAPSHOT=<ordner>` rendert alle Seiten als PNG |

## Bauen
`./scripts/build-app.sh` (XcodeGen → xcodebuild → `~/Applications/Hoku.app`). Projektdatei kommt aus `project.yml`.

## Leitplanken
- Dauer-Animationen nur mit `TimelineView(… paused: !isPanelVisible)` – sonst rechnet Hoku auch bei geschlossenem Panel.
- Store-Modelle nur zuweisen, wenn sie sich wirklich geändert haben (spart Neuzeichnen).
- Nichts an der Bridge ändern in Tests; Live-Tests sind nur lesend.
