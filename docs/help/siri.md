---
id: siri
title: Siri einrichten
title_en: Set up Siri
---

# Siri einrichten

> „Hey Siri, Wohnzimmer an“, ganz ohne „Hoku“ davor.

**Du brauchst:** Siri eingeschaltet und am Mac eine Anmeldung bei iCloud (mit deinem Apple Account). Ohne iCloud geht es auch, siehe [unten](#without-icloud).

### Welcher Weg passt zu dir?
| Deine Lage | Was Hoku einrichtet |
|---|---|
| **Kein iPhone** (z. B. Android) oder Hue ist **nicht** in Apple Home | Alles: Räume an/aus, Lampen, Szenen, „Alles aus“ |
| Hue ist **schon in Apple Home** (am iPhone eingerichtet) | Siri kann deine Räume schon. Hoku ergänzt nur, was Apple Home nicht kann: Hue-Szenen und Einschlaf-Timer. So gibt es keine doppelten Befehle. |
| iPhone vorhanden, Hue **noch nicht** in Apple Home | Du hast die Wahl: Apple Home am iPhone einrichten (Home-App → **+** → Gerät hinzufügen → Code unten auf der Bridge scannen) oder einfach „Nur Hoku am Mac“ wie in Zeile 1. |

Der Einrichtungs-Assistent fragt das beim ersten Start ab. Hier geht es um den Weg über die Einstellungen.

1. Öffne Hoku und klick oben auf das **Zahnrad** (Einstellungen). Dort wählst du **Siri-Befehle einrichten**.
2. **Wähle deine Befehle.** Räume an/aus und „Alles aus“ sind schon ausgewählt. Szenen heißen „‹Raum› ‹Szene›“, z. B. „Wohnzimmer Entspannen“.
   ✓ = schon eingerichtet · ✦ = Sprechvariante, so wie Siri den Namen versteht (z. B. „Light Strip“ für „Lightstrip“).
3. Klick auf **‹Anzahl› Befehle einrichten**. Die Kurzbefehle-App öffnet sich.
4. Klick bei **jedem** Befehl auf **Kurzbefehl hinzufügen**. Das verlangt macOS einmal pro Befehl, Hoku kann es nicht abkürzen.
5. **Ausprobieren:** „Hey Siri, Wohnzimmer an“. Sag genau den Namen des Befehls.
6. **Beim ersten Benutzen** fragt macOS bei jedem Befehl **einmal**, ob er Hoku öffnen darf. Erlaube es dauerhaft – danach fragt dieser Befehl nie wieder, auch nicht nach einem Neustart. Tipp: Sag jeden neuen Befehl einmal kurz zum Ausprobieren, dann ist alles freigegeben.

**Gut zu wissen**
- **Eine Frage pro Befehl, nur einmal:** macOS speichert die Freigabe für jeden Kurzbefehl einzeln. Fragt ein Befehl erneut, wurde er zum ersten Mal benutzt (z. B. „Vitrine aus“ nach „Vitrine an“) oder es wurde nur „einmal“ erlaubt.
- **Nach dem Umbenennen** in der Hue-App funktionieren alte Befehle weiter. Hoku merkt sich frühere Namen.
- **Auf jedem Mac:** Deine Kurzbefehle kommen per iCloud auch auf deine anderen Macs. Dort brauchen sie nur Hoku.
- **Als Knopf:** Jeder Befehl lässt sich ins Kontrollzentrum legen: Kontrollzentrum öffnen → **Steuerelemente bearbeiten** → Kurzbefehle.
- **Löschen** geht nur in der Kurzbefehle-App (Rechtsklick auf den Befehl → Löschen). Apple erlaubt Apps nicht, Kurzbefehle zu löschen.
- **Sprache:** Hoku legt persönliche Befehle in der Sprache der App an („Wohnzimmer an“ bzw. „Living room on“, ab 0.9.1). Früher angelegte Befehle funktionieren weiter. Sprich sie in der Sprache von Siri (Systemeinstellungen → **Apple Intelligence & Siri** → **Sprache**): Die Sprache des Befehls muss zu Siri passen.

<a id="without-icloud"></a>
### Ohne iCloud
Hoku lässt jeden neuen Kurzbefehl von Apple signieren, und dafür braucht macOS eine iCloud-Anmeldung. Ohne iCloud legst du die Befehle selbst an, das dauert etwa 30 Sekunden pro Befehl:
1. Öffne in Hoku die Einstellungen → **Für Fortgeschrittene** und kopier die Adresse, z. B. `hoku://raum/Wohnzimmer/an`.
2. Öffne die Kurzbefehle-App → **+** → such die Aktion **URLs öffnen** und füg die Adresse ein.
3. Gib dem Kurzbefehl den Namen, den du zu Siri sagen willst, z. B. **Wohnzimmer an**. Fertig.

<a id="siri-off"></a>
### Siri ist aus?
Systemeinstellungen → **Apple Intelligence & Siri** (auf manchen Macs nur **Siri**) → Siri einschalten.

> **Hat nicht geklappt?**
> → [Siri antwortet mit Home oder „geht auf dem Mac nicht“](fehlerbehebung.md#siri-home) · [„Kurzbefehl konnte nicht signiert werden“](fehlerbehebung.md#siri-icloud) · [Siri startet die falsche App](fehlerbehebung.md#siri-duplicates)

---

## English

# Set up Siri

> “Hey Siri, living room on”, without saying “Hoku” first.

**You need:** Siri turned on and this Mac signed in to iCloud with your Apple Account. It also works without iCloud, see [below](#without-icloud-en).

### Which way fits you?
| Your setup | What Hoku sets up |
|---|---|
| **No iPhone** (e.g. Android), or Hue is **not** in Apple Home | Everything: rooms on/off, lamps, scenes, “All lights off” |
| Hue is **already in Apple Home** (set up on your iPhone) | Siri already handles your rooms. Hoku only adds what Apple Home can’t do: Hue scenes and the sleep timer. That way no command exists twice. |
| You have an iPhone, but Hue is **not yet** in Apple Home | Your choice: set up Apple Home on the iPhone (Home app → **+** → Add Accessory → scan the code on the bottom of the bridge), or just pick “Hoku on This Mac Only” as in row 1. |

The setup assistant asks this on first launch. This page covers the way through Settings.

1. Open Hoku, click the **gear** at the top (Settings) and choose **Set Up Siri Commands**.
2. **Pick your commands.** Rooms on/off and “All lights off” are already selected. Scenes are named “‹Room› ‹Scene›”, e.g. “Living Room Relax”.
   ✓ = already set up · ✦ = spoken variant, the way Siri hears the name (e.g. “Light Strip” for “Lightstrip”).
3. Click **Set Up ‹number› Commands**. The Shortcuts app opens.
4. For **each** command, click **Add Shortcut**. macOS requires this once per command, and Hoku can’t skip it.
5. **Try it:** “Hey Siri, living room on”. Say the command’s exact name.
6. **On first use**, macOS asks **once** per command whether it may open Hoku. Allow it permanently – that command never asks again, not even after a restart. Tip: say each new command once to try it, and everything is approved.

**Good to know**
- **One question per command, only once:** macOS stores the approval for each shortcut separately. If a command asks again, it was used for the first time (e.g. “cabinet off” after “cabinet on”) or was only allowed once.
- **Renamed something** in the Hue app? Old commands keep working. Hoku remembers earlier names.
- **On every Mac:** Your shortcuts sync to your other Macs via iCloud. All they need there is Hoku.
- **As a button:** Put any command in Control Center: open Control Center → **Edit Controls** → Shortcuts.
- **Delete** commands in the Shortcuts app (right-click → Delete). Apple doesn’t let apps delete shortcuts.
- **Language:** Hoku creates personal commands in the app’s language (“Wohnzimmer an” / “Living room on”, from 0.9.1). Commands created earlier keep working. Say them in Siri’s language (System Settings → **Apple Intelligence & Siri** → **Language**): the command’s language has to match Siri.

<a id="without-icloud-en"></a>
### Without iCloud
Hoku has Apple sign each new shortcut, and macOS only does that when you’re signed in to iCloud. Without iCloud, you create the commands yourself. It takes about 30 seconds each:
1. In Hoku, open Settings → **Advanced** and copy an address such as `hoku://room/Living%20Room/on`.
2. Open the Shortcuts app → **+** → search for the **Open URLs** action and paste the address.
3. Name the shortcut what you want to say to Siri, e.g. **Living Room on**. Done.

### Siri is off?
System Settings → **Apple Intelligence & Siri** (on some Macs just **Siri**) → turn Siri on.

> **Didn’t work?**
> → [Siri answers with Home or says it can’t do that on Mac](fehlerbehebung.md#siri-home) · [“Shortcut couldn’t be signed”](fehlerbehebung.md#siri-icloud) · [Siri opens the wrong app](fehlerbehebung.md#siri-duplicates)
