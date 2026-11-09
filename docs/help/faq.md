---
id: faq
title: Häufige Fragen
title_en: FAQ
---

# Häufige Fragen

> Kurze Antworten, ehrlich.

**Was kostet Hoku?**
Nichts. Hoku ist Open Source (MIT-Lizenz). Kein Abo, keine Werbung.

**Ist Hoku von Philips oder Signify?**
Nein. Hoku ist ein unabhängiges Projekt von Philoni. Es ist kein Produkt von Signify oder Philips Hue und wird von Signify weder unterstützt noch geprüft. Philips Hue ist eine Marke von Signify.

**Was brauche ich?**
Einen Mac mit macOS 26 (Tahoe) oder neuer und eine Hue Bridge (die eckige Bridge oder die Bridge Pro) im selben Netzwerk. Die alte runde Bridge der ersten Generation kann Hoku nicht steuern. Ein Hue-Konto brauchst du nicht.

**Funktioniert Hoku auch unterwegs?**
Nein. Hoku spricht direkt mit deiner Bridge, also nur im Heimnetz. Wecker und Schlafen-Routinen laufen trotzdem, denn sie liegen auf der Bridge.

**Was ist der Unterschied zu Hue Sync?**
Hue Sync von Signify lässt die Lampen eines Entertainment-Bereichs zu Filmen, Spielen und Musik am Computer leuchten. Räume, einzelne Lampen oder Szenen fürs Zuhause steuert es nicht. Hoku ist genau dafür da. Beide vertragen sich: Nutze Hue Sync für Effekte und Hoku für alles andere. Während Hue Sync läuft, übernimmt es die Lampen seines Bereichs; Änderungen aus Hoku oder der Hue-App gelten dort erst wieder, wenn du den Sync beendest.

**Ich habe ein Android-Handy. Geht Siri trotzdem?**
Ja, am Mac. Hoku legt Siri-Befehle als Kurzbefehle an, dafür brauchst du kein iPhone. → [Siri einrichten](siri.md)

**Kann ich Hue am Mac zu Apple Home hinzufügen?**
Nein. Neue Geräte lassen sich in Apple Home nur am iPhone oder iPad einrichten. Hoku braucht Apple Home nicht.

**Warum muss ich bei jedem Siri-Befehl „Kurzbefehl hinzufügen“ klicken?**
Apple lässt Apps keine Kurzbefehle still anlegen. Du bestätigst jeden einmal, danach nie wieder.

**Warum muss ich „Dennoch öffnen“ klicken? Ist Hoku sicher?**
Damit macOS ohne Nachfrage öffnet, müsste Apple Hoku prüfen. Das kostet 99 € im Jahr. Hoku ist mit einem eigenen, dauerhaften Zertifikat signiert, und der Code ist offen. Das Klicken ist nur einmal nötig, Updates fragen nicht mehr. Wer ganz sichergehen will, baut Hoku selbst oder prüft den Download:
1. Lade neben der App auch die Datei `Hoku-‹Version›.dmg.sha256` von der Release-Seite.
2. Öffne das Terminal im Download-Ordner und gib ein: `shasum -a 256 -c Hoku-‹Version›.dmg.sha256`. Es muss **OK** erscheinen.
3. Nach dem Installieren: `codesign -dv /Applications/Hoku.app 2>&1 | grep Authority` zeigt **Authority=Hoku Release Signing**.

**Laufen Wecker auch, wenn der Mac schläft oder aus ist?**
Ja. Wecker und Schlafen-Routinen speichert Hoku auf der Bridge. Du siehst sie auch in der Hue-App.

**Sehe ich meine Szenen aus der Hue-App?**
Ja, immer aktuell, auch bewegte (dynamische) und smarte Szenen. Neue Szenen erstellst du bisher in der Hue-App.

**Mehrere Macs, Mitbewohner, Familie?**
Jeder Mac koppelt sich einmal selbst mit der Link-Taste, die Bridge erlaubt viele Geräte. Deine Siri-Befehle kommen per iCloud auf deine anderen Macs. Jede Person richtet auf ihrem Mac eigene Befehle ein.

**Mehrere Bridges?**
Noch nicht. Hoku steuert im Moment eine Bridge. Mehrere sind geplant.

**Welche Sprachen?**
Deutsch und Englisch (ab 0.9.1). App, Hinweise, Einrichtungs-Assistent und Siri-Befehle folgen der Systemsprache. Persönliche Siri-Befehle legt Hoku in der Sprache der App an („Wohnzimmer an“ bzw. „Living room on“). Früher angelegte Befehle funktionieren weiter. Gesprochen wird in der Sprache von Siri.

**Kann ich Licht per Tastenkürzel schalten?**
Ja (ab 0.9.1). Unter Einstellungen → **Tastenkürzel** gibst du jedem Raum und jeder Zone ein Kürzel, dazu eins für **Alles aus** und für Szenen (**Szene hinzufügen**). Sie gelten überall am Mac, auch bei geschlossenem Hoku. → [Gesten & Tastatur](gesten-und-tastatur.md)

**Kann ich die Reihenfolge der Räume ändern?**
Ja. Einstellungen → **Räume ordnen**: oben anheften, nach oben oder unten schieben, **Nach Name sortieren** setzt zurück. → [Gesten & Tastatur](gesten-und-tastatur.md)

**Kann ich Hoku mit einem vorhandenen Hue-Schlüssel verbinden?**
Ja, für Fortgeschrittene (ab 0.9.1). Gib im Einrichtungs-Assistenten die IP-Adresse der Bridge von Hand ein und wähl **Ich habe schon einen Schlüssel**. Dann braucht es keine Link-Taste, und der Schlüssel bleibt nur auf diesem Mac. Einstellungen → **Bridge** → **Verbindungsdetails** zeigen Adresse, Bridge-ID und wie die Verbindung gesichert ist. → [Installieren](installieren.md#advanced-connection)

**Was ist mit meinen Daten?**
Alles bleibt auf deinem Mac und in deinem Netzwerk, bis auf drei klar benannte Ausnahmen. → [Datenschutz](datenschutz.md)

**Licht und Gesundheit**
Bestimmte Lichtfarben, schnelle Wechsel oder Blinken können Unwohlsein auslösen, bei lichtempfindlichen Menschen (z. B. mit fotosensitiver Epilepsie) auch Anfälle oder Migräne. Wenn du dich unwohl fühlst, beende den Effekt, die Szene oder Hoku sofort.

**Fehler gefunden oder einen Wunsch?**
Gern auf [GitHub](https://github.com/Philoni/hoku/issues). Erst einmal hier schauen: [Wenn etwas hakt](fehlerbehebung.md).

> **Hat nicht geklappt?** → [Wenn etwas hakt](fehlerbehebung.md)

---

## English

# FAQ

> Short answers, honest ones.

**What does Hoku cost?**
Nothing. Hoku is open source (MIT license). No subscription, no ads.

**Is Hoku made by Philips or Signify?**
No. Hoku is an independent project by Philoni. It is not a Signify or Philips Hue product and is not endorsed or reviewed by Signify. Philips Hue is a trademark of Signify.

**What do I need?**
A Mac with macOS 26 (Tahoe) or later and a Hue Bridge (the square bridge or the Bridge Pro) on the same network. Hoku can’t control the old round first-generation bridge. You don’t need a Hue account.

**Does Hoku work away from home?**
No. Hoku talks directly to your bridge, so it only works on your home network. Wake-up and bedtime routines still run, because they live on the bridge.

**How is Hoku different from Hue Sync?**
Signify’s Hue Sync makes the lights of an entertainment area follow films, games and music on your computer. It doesn’t control rooms, single lamps or everyday scenes. That’s what Hoku is for. They get along: use Hue Sync for effects and Hoku for everything else. While Hue Sync runs it takes over the lights in its area; changes from Hoku or the Hue app apply there again once you stop the sync.

**I have an Android phone. Does Siri still work?**
Yes, on your Mac. Hoku creates Siri commands as shortcuts, no iPhone needed. → [Set up Siri](siri.md)

**Can I add Hue to Apple Home on my Mac?**
No. New accessories can only be added to Apple Home on an iPhone or iPad. Hoku doesn’t need Apple Home.

**Why do I have to click “Add Shortcut” for every Siri command?**
Apple doesn’t let apps create shortcuts silently. You confirm each one once, and never again.

**Why “Open Anyway”? Is Hoku safe?**
For macOS to open Hoku without asking, Apple would have to check it, which costs €99 a year. Hoku is signed with its own long-lived certificate and the code is open. You only click once; updates don’t ask again. To be extra sure, build Hoku yourself or check the download:
1. Also download `Hoku-‹version›.dmg.sha256` from the releases page.
2. Open Terminal in your Downloads folder and run `shasum -a 256 -c Hoku-‹version›.dmg.sha256`. It must say **OK**.
3. After installing, `codesign -dv /Applications/Hoku.app 2>&1 | grep Authority` shows **Authority=Hoku Release Signing**.

**Do wake-up routines run while my Mac sleeps or is off?**
Yes. Hoku stores wake-up and bedtime routines on the bridge. You’ll see them in the Hue app, too.

**Do I see my scenes from the Hue app?**
Yes, always up to date, including moving (dynamic) and smart scenes. For now, you create new scenes in the Hue app.

**Several Macs, roommates, family?**
Each Mac pairs once with the link button, and the bridge allows many devices. Your Siri commands sync to your other Macs via iCloud. Everyone sets up their own commands on their own Mac.

**Several bridges?**
Not yet. Hoku controls one bridge for now. Support for more is planned.

**Which languages?**
German and English (from 0.9.1). The app, notifications, setup assistant and Siri commands follow the system language. Hoku creates personal Siri commands in the app’s language (“Wohnzimmer an” / “Living room on”). Commands created earlier keep working. You speak them in Siri’s language.

**Can I switch lights with keyboard shortcuts?**
Yes (from 0.9.1). In Settings → **Keyboard Shortcuts** you can give any room or zone a shortcut, plus one for **All off** and for scenes (**Add scene**). They work everywhere on your Mac, even while Hoku is closed. → [Gestures & keyboard](gesten-und-tastatur.md)

**Can I change the order of my rooms?**
Yes. Settings → **Arrange Rooms**: pin to the top, move up or down, **Sort by Name** resets. → [Gestures & keyboard](gesten-und-tastatur.md)

**Can I connect Hoku with an existing Hue key?**
Yes, for advanced users (from 0.9.1). In the setup assistant, enter the bridge’s IP address by hand and choose **I already have a key**. No link button needed, and the key stays on this Mac only. Settings → **Bridge** → **Connection Details** show the address, bridge ID and how the connection is secured. → [Install](installieren.md#advanced-connection-en)

**What about my data?**
Everything stays on your Mac and your network, with three clearly named exceptions. → [Privacy](datenschutz.md)

**Light and health**
Certain light colors, rapid changes or flashing can cause discomfort and, in people with light sensitivity (e.g. photosensitive epilepsy), may trigger seizures or migraines. If you feel unwell, stop the effect, the scene or Hoku immediately.

**Found a bug or have a wish?**
Please tell us on [GitHub](https://github.com/Philoni/hoku/issues). Check [Troubleshooting](fehlerbehebung.md) first.

> **Didn’t work?** → [Troubleshooting](fehlerbehebung.md)
