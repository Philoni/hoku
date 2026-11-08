---
id: privacy
title: Datenschutz
title_en: Privacy
---

# Datenschutz

> Alles bleibt bei dir. Was trotzdem rausgeht, steht hier.

**Kurz:** Hoku spricht direkt mit deiner Hue Bridge in deinem Heimnetz. Es gibt kein Konto, keine Cloud, keine Werbung, kein Tracking und keine Absturzberichte an Dritte.

### Was deinen Mac verlässt, und warum
| Wohin | Wann | Was | Vermeiden |
|---|---|---|---|
| **Deine Hue Bridge** (bei dir zu Hause) | Immer, das ist die Steuerung | Schaltbefehle und der Zugangsschlüssel. Verschlüsselt, und Hoku prüft das Zertifikat der Bridge. | – |
| **Signify** (`discovery.meethue.com`) | Nur beim Suchen, und nur wenn die Bridge sich im Netzwerk nicht von selbst meldet | Eine normale Webanfrage ohne Daten von dir. Signify sieht dabei deine öffentliche IP-Adresse und antwortet mit der Adresse deiner Bridge. | IP-Adresse der Bridge selbst eingeben |
| **Apple** (iCloud) | Nur beim Einrichten von Siri-Befehlen | Jeder neue Kurzbefehl wird von Apple signiert. Dabei geht er an Apple: sein Name (z. B. „Wohnzimmer an“) und die Hoku-Adresse darin. | Befehle selbst anlegen ([Siri ohne iCloud](siri.md#without-icloud)) |
| **GitHub** | Regelmäßig, zur Update-Prüfung | Abruf der Update-Liste. GitHub sieht deine IP-Adresse und die Hoku-Version, wie bei jedem Download. Keine Systemdaten. | Automatische Update-Prüfung ausschalten |

Wenn du mit Siri sprichst, verarbeitet Apple deine Sprache nach deinen Siri-Einstellungen. Hoku hört dabei nie mit und hat keinen Zugriff aufs Mikrofon. Deine Bridge kann unabhängig von Hoku mit Signify sprechen, z. B. für Firmware-Updates oder die Hue-App unterwegs. Daran ändert Hoku nichts.

### Was auf deinem Mac bleibt
- **Zugangsschlüssel der Bridge:** `~/Library/Application Support/Hoku/bridge.json`, lesbar nur für deinen Benutzer.
- **Gewohnheiten für Vorschläge** (welche Szene wann): `usage.json`, wird nur auf deinem Mac berechnet.
- **Frühere Namen** von Räumen und Lampen, damit alte Siri-Befehle weiter klappen: `former-names.json`.
- **Einstellungen** (Kürzel, Erscheinungsbild, Automationen): in den normalen macOS-Einstellungen von Hoku.

### Alles löschen
1. Beende Hoku: Rechtsklick aufs Symbol → **Hoku beenden**.
2. Leg `Hoku.app` aus **Programme** in den Papierkorb.
3. Finder → **Gehe zu → Gehe zum Ordner …** → `~/Library/Application Support/Hoku` → Ordner in den Papierkorb.
4. Lösche deine Siri-Befehle in der Kurzbefehle-App (Rechtsklick → Löschen).
5. Leer den Papierkorb.

> **Hat nicht geklappt?** → [Wenn etwas hakt](fehlerbehebung.md) · [Häufige Fragen](faq.md)

---

## English

# Privacy

> Everything stays with you. What still leaves your Mac is listed here.

**In short:** Hoku talks directly to your Hue Bridge on your home network. No account, no cloud, no ads, no tracking, no crash reports to third parties.

### What leaves your Mac, and why
| Where | When | What | How to avoid it |
|---|---|---|---|
| **Your Hue Bridge** (in your home) | Always, that’s how Hoku controls your lights | Light commands and the access key. Encrypted, and Hoku checks the bridge’s certificate. | – |
| **Signify** (`discovery.meethue.com`) | Only when searching, and only if the bridge doesn’t show up on the network by itself | A plain web request with none of your data. Signify sees your public IP address and replies with your bridge’s address. | Enter the bridge’s IP address yourself |
| **Apple** (iCloud) | Only when setting up Siri commands | Apple signs every new shortcut, so it is sent to Apple: its name (e.g. “Living Room on”) and the Hoku address inside. | Create the commands yourself ([Siri without iCloud](siri.md#without-icloud-en)) |
| **GitHub** | Regularly, to check for updates | Fetching the update list. GitHub sees your IP address and Hoku version, as with any download. No system data. | Turn off automatic update checks |

When you talk to Siri, Apple processes your speech according to your Siri settings. Hoku never listens and has no microphone access. Your bridge may talk to Signify on its own, e.g. for firmware updates or the Hue app away from home. Hoku doesn’t change that.

### What stays on your Mac
- **The bridge access key:** `~/Library/Application Support/Hoku/bridge.json`, readable only by your user.
- **Habits for suggestions** (which scene when): `usage.json`, computed only on your Mac.
- **Earlier names** of rooms and lamps, so old Siri commands keep working: `former-names.json`.
- **Settings** (shortcut, appearance, automations): in Hoku’s regular macOS preferences.

### Delete everything
1. Quit Hoku: right-click the icon → **Quit Hoku**.
2. Move `Hoku.app` from **Applications** to the Trash.
3. Finder → **Go → Go to Folder…** → `~/Library/Application Support/Hoku` → move the folder to the Trash.
4. Delete your Siri commands in the Shortcuts app (right-click → Delete).
5. Empty the Trash.

> **Didn’t work?** → [Troubleshooting](fehlerbehebung.md) · [FAQ](faq.md)
