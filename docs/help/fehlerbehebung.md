---
id: troubleshooting
title: Wenn etwas hakt
title_en: Troubleshooting
---

# Wenn etwas hakt

> Die häufigsten Probleme, jeweils in wenigen Schritten gelöst.

**Springe zu:** [Öffnen](#open-anyway) · [Netzwerk](#local-network) · [Bridge](#bridge-not-found) · [Koppeln](#pairing-timeout) · [Siri](#siri-home) · [Lampe nicht erreichbar](#unreachable) · [Menüleiste](#menu-bar-icon) · [Gesten](#secondary-click)

<a id="open-anyway"></a>
## „Hoku“ lässt sich nicht öffnen
**Warum:** Hoku ist nicht von Apple geprüft (das kostet 99 € im Jahr). macOS blockiert deshalb den ersten Start, einmalig.
1. Öffne Hoku per Doppelklick und klick auf **Fertig**.
2. Öffne **gleich danach** **Systemeinstellungen → Datenschutz & Sicherheit** und scroll ganz nach unten. Der Knopf **Dennoch öffnen** erscheint nur etwa eine Stunde nach dem Startversuch.
3. Rechtsklick → „Öffnen“ reicht seit macOS 15 nicht mehr. Nimm den Weg über die Einstellungen.
4. Kein Knopf zu sehen, auch direkt danach? Auf Firmen- oder Schul-Macs kann das gesperrt sein. Frag deine IT oder [bau Hoku selbst](https://github.com/Philoni/hoku#selbst-bauen).

<a id="local-network"></a>
## Hoku findet die Bridge nicht, obwohl sie da ist
Hoku zeigt „Der Zugriff aufs lokale Netzwerk ist aus“ oder „Bridge gerade nicht erreichbar“.
**Warum:** macOS fragt einmal, ob Hoku in deinem Heimnetz suchen darf. Ohne Erlaubnis sieht Hoku die Bridge nicht. macOS 26 vergisst diese Erlaubnis manchmal nach einem Neustart. Das ist ein bekannter Fehler bei Apple.
1. Öffne **Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk**.
2. Schalte **Hoku** ein. Ist der Schalter schon an, schalte ihn aus und wieder ein.
3. Hoku macht von selbst weiter. Falls nicht: Klick in Hoku auf **Erneut**.
4. Fehlt Hoku in der Liste ganz? Dann ist Hoku vermutlich mehrfach installiert → [Mehrere Kopien](#siri-duplicates).

<a id="bridge-not-found"></a>
## Keine Bridge gefunden
**Warum:** Mac und Bridge müssen im selben Heimnetz sein. Gast-WLAN, VPN oder ein zweites Netz (z. B. ein Repeater mit eigenem Namen) verhindern die Suche.
1. Leuchten die Lämpchen an der Bridge? Steckt ihr Kabel im Router?
2. Ist dein Mac im WLAN deines Routers, nicht im Gast-WLAN? Schalte ein VPN kurz aus.
3. Klick in Hoku auf **Erneut suchen**.
4. Oder gib die IP-Adresse von Hand ein. Du findest sie in der Hue-App unter **Einstellungen → Hue Bridges → ⓘ**. In Hoku: **IP-Adresse eingeben** → **Prüfen**.
5. Für Fortgeschrittene: Hast du schon einen Hue-Schlüssel, klick nach der Adresse auf **Ich habe schon einen Schlüssel** und füg ihn ein. Dann braucht es keine Link-Taste. → [Installieren](installieren.md#advanced-connection)

<a id="connection-details"></a>
## Hoku zeigt die falsche Adresse für die Bridge
Normalerweise findet Hoku die Bridge von selbst wieder. Wenn nicht, schau nach: Einstellungen → **Bridge** → **Verbindungsdetails** zeigen Status, Adresse und Bridge-ID. Mit **Adresse von Hand** trägst du die IP selbst ein. Hoku übernimmt sie nur, wenn unter dieser Adresse dieselbe Bridge antwortet. Sonst übernimmt Hoku sie nicht. (ab 0.9.1)

<a id="pairing-timeout"></a>
## Die Zeit beim Koppeln ist abgelaufen
**Warum:** Nach dem Klick auf **Koppeln** wartet Hoku 60 Sekunden darauf, dass du die Taste drückst.
1. Steht die Bridge weit weg? Klick erst auf **Koppeln** und geh dann los, 60 Sekunden reichen.
2. Drück **einmal kurz** die große runde **Link-Taste** oben auf der Bridge.
3. Klick noch einmal auf **Koppeln**. Hoku meldet „Zeit abgelaufen“, wenn die 60 Sekunden vorbei sind.

<a id="not-paired"></a>
## „Hoku ist nicht mehr gekoppelt“
**Warum:** Die Bridge kennt Hoku nicht mehr, z. B. nach einem Zurücksetzen der Bridge.
1. Klick in Hoku auf **Koppeln** und drück die Link-Taste. Deine Siri-Befehle bleiben gültig.

<a id="siri-home"></a>
## Siri antwortet mit Home oder sagt, dass es auf dem Mac nicht geht
**Warum:** Siri hat keinen Kurzbefehl mit genau diesem Namen gefunden und den Satz an Apple Home weitergereicht. Ohne Apple Home klappt das am Mac nicht.
1. Öffne die Kurzbefehle-App und such den Befehl, z. B. „Wohnzimmer an“. Fehlt er? Dann wurde **Kurzbefehl hinzufügen** übersprungen. Richte ihn in Hoku noch einmal ein: Einstellungen → **Siri-Befehle einrichten**.
2. Sag den Namen **genau so**, wie er in der Kurzbefehle-App steht. Siri schreibt manche Namen anders („Light Strip“ statt „Lightstrip“). Wähl dafür in Hoku die Varianten mit ✦.
3. Prüf die Sprache: Die Sprache des Befehls muss zur Sprache von Siri passen, deutsche Befehle brauchen Siri auf Deutsch, englische Siri auf Englisch (Systemeinstellungen → **Apple Intelligence & Siri** → **Sprache**).
4. Ist deine Bridge in Apple Home, übernimmt Siri „Raum an/aus“ selbst. Das ist so gewollt.

<a id="siri-icloud"></a>
## „Kurzbefehl konnte nicht signiert werden“
**Warum:** macOS lässt jeden neuen Kurzbefehl von Apple signieren, und dafür musst du bei iCloud angemeldet sein. Manchmal antworten Apples Server auch einfach nicht.
1. Öffne **Systemeinstellungen** und prüf ganz oben in der Seitenleiste, ob dein **Apple Account** angemeldet ist. Sonst klick auf **Anmelden**.
2. Versuch es in Hoku noch einmal: Einstellungen → **Siri-Befehle einrichten**. Hoku probiert jeden Befehl selbst dreimal.
3. Ohne iCloud: Leg die Befehle selbst an. → [Siri ohne iCloud](siri.md#without-icloud)

<a id="siri-duplicates"></a>
## Siri startet die falsche App, oder Befehle tun nichts
**Warum:** Es gibt Hoku mehrmals auf deinem Mac (Downloads, Papierkorb, alte Version). Das bringt Siri und die Netzwerk-Erlaubnis durcheinander.
1. Beende Hoku (Rechtsklick aufs Symbol → **Hoku beenden**).
2. Such im Finder nach „Hoku“ und leg jede `Hoku.app`, die **nicht** in „Programme“ liegt, in den Papierkorb. Leer danach den Papierkorb.
3. Öffne Hoku aus „Programme“.

<a id="unreachable"></a>
## Eine Lampe zeigt „Nicht erreichbar“
**Warum:** Die Bridge erreicht die Lampe nicht. Fast immer ist der Lichtschalter oder die Steckerleiste aus, seltener ist die Lampe zu weit weg.
1. Schalte den Lichtschalter bzw. die Steckdose ein.
2. Warte etwa eine Minute, Hoku aktualisiert sich selbst.
3. Immer noch? **Einstellungen → Geräte-Check** zeigt, welche Geräte betroffen sind. Prüf die Lampe danach in der Hue-App.
Tipp: Hue-Lampen am besten immer am Strom lassen und mit Hoku oder einem Hue-Schalter schalten.

<a id="menu-bar-icon"></a>
## Das Symbol in der Menüleiste fehlt
**Warum:** Bei voller Menüleiste verschwinden Symbole hinter der Kamera-Aussparung. Oder Hoku ist dort ausgeblendet.
1. Drück **⌃⌥L**, das öffnet Hoku immer.
2. Öffne **Systemeinstellungen → Menüleiste** und schalte unter **In Menüleiste erlauben** **Hoku** ein.
3. Mach Platz: Blende andere Symbole aus oder nutze eine App wie Ice.

<a id="login-item"></a>
## Hoku startet nicht mehr beim Anmelden
1. Öffne in Hoku die Einstellungen und schalte **Bei Anmeldung starten** ein. <!-- Label heute so in den Einstellungen; nach Angleichung „Beim Anmelden starten“ (anleitungen.md §8). -->
2. Fragt macOS nach: **Systemeinstellungen → Allgemein → Anmeldeobjekte & Erweiterungen** → bei **Hoku** einschalten.

<a id="secondary-click"></a>
## Zwei-Finger-Klick klappt nichts auf
1. Öffne **Systemeinstellungen → Trackpad → Zeigen und Klicken** und stell **Sekundärklick** auf **Mit zwei Fingern klicken oder tippen**.
2. Räume mit nur einer Lampe klappen nicht auf, sie federn nur kurz. Das ist so gewollt.
3. Mit der Maus: Rechtsklick oder ctrl-Klick.

<a id="hotkey"></a>
## ⌃⌥L tut nichts
**Warum:** Eine andere App benutzt dieselbe Tastenkombination.
1. Öffne in Hoku die Einstellungen → **Tastenkürzel** → klick bei **Hoku öffnen** auf **Festlegen** und drück eine neue Kombination (mit ⌘, ⌥ oder ⌃).
2. Steht dort **belegt**, nutzt eine andere App die Kombination schon. Das gilt auch für deine Kürzel fürs Licht.

> **Hat nicht geklappt?** → [Häufige Fragen](faq.md) · Oder schreib uns auf [GitHub](https://github.com/Philoni/hoku/issues/new): macOS-Version, Hoku-Version (Finder → Programme → Hoku → ⌘I), Bridge-Modell und was du gemacht hast. Bitte keine IP-Adressen oder Schlüssel posten.

---

## English

# Troubleshooting

> The most common problems, each solved in a few steps.

<a id="open-anyway-en"></a>
## “Hoku” won’t open
**Why:** Hoku isn’t checked by Apple (that costs €99 a year), so macOS blocks the first launch, once.
1. Double-click Hoku and click **Done**.
2. **Right after**, open **System Settings → Privacy & Security** and scroll to the bottom. **Open Anyway** only shows for about an hour after the launch attempt.
3. Right-click → “Open” no longer works since macOS 15. Use System Settings instead.
4. Still no button? Work or school Macs may block it. Ask your IT team or [build Hoku yourself](https://github.com/Philoni/hoku#build-from-source).

<a id="local-network-en"></a>
## Hoku can’t find the bridge, even though it’s there
**Why:** macOS asks once whether Hoku may look around your home network. Without that permission Hoku can’t see the bridge. macOS 26 sometimes forgets the permission after a restart, which is a known Apple bug.
1. Open **System Settings → Privacy & Security → Local Network**.
2. Turn **Hoku** on. If it’s already on, turn it off and on again.
3. Hoku continues by itself. If not, click **Retry** in Hoku.
4. Hoku isn’t in the list at all? You probably have more than one copy → [Multiple copies](#siri-duplicates-en).

<a id="bridge-not-found-en"></a>
## No bridge found
**Why:** Your Mac and the bridge must be on the same home network. Guest Wi-Fi, a VPN or a second network (e.g. a repeater with its own name) block the search.
1. Are the lights on the bridge lit? Is its cable plugged into the router?
2. Is your Mac on your router’s Wi-Fi, not the guest network? Turn off any VPN for a moment.
3. Click **Search Again** in Hoku.
4. Or enter the IP address yourself. You’ll find it in the Hue app under **Settings → Hue Bridges → ⓘ**. In Hoku: **Enter IP address** → **Check**.
5. For advanced users: if you already have a Hue key, click **I already have a key** after the address and paste it. No link button needed. → [Install](installieren.md#advanced-connection-en)

<a id="connection-details-en"></a>
## Hoku shows the wrong address for the bridge
Normally Hoku finds the bridge again on its own. If not, take a look: Settings → **Bridge** → **Connection Details** show status, address and bridge ID. **Manual Address** lets you enter the IP yourself. Hoku only accepts it if the same bridge answers at that address. Otherwise Hoku doesn’t take it. (from 0.9.1)

<a id="pairing-timeout-en"></a>
## Pairing timed out
**Why:** After you click **Pair**, Hoku waits 60 seconds for you to press the button.
1. Bridge far away? Click **Pair** first, then walk over. 60 seconds is enough.
2. Press the big round **link button** on top of the bridge **once**.
3. Click **Pair** again. Hoku says “Time’s up” when the 60 seconds have passed.

<a id="not-paired-en"></a>
## “Hoku is no longer paired”
**Why:** The bridge no longer knows Hoku, e.g. after the bridge was reset.
1. Click **Pair** in Hoku and press the link button. Your Siri commands keep working.

<a id="siri-home-en"></a>
## Siri answers with Home or says it can’t do that on a Mac
**Why:** Siri found no shortcut with exactly that name and handed the sentence to Apple Home. Without Apple Home that fails on a Mac.
1. Open the Shortcuts app and look for the command, e.g. “Living Room on”. Missing? Then **Add Shortcut** was skipped. Set it up again in Hoku: Settings → **Set Up Siri Commands**.
2. Say the name **exactly** as it appears in the Shortcuts app. Siri spells some names differently (“Light Strip” vs. “Lightstrip”), so pick the ✦ variants in Hoku.
3. Check the language: the command’s language must match Siri’s language. German commands need Siri in German, English commands Siri in English (System Settings → **Apple Intelligence & Siri** → **Language**).
4. If your bridge is in Apple Home, Siri handles “room on/off” itself. That’s intended.

<a id="siri-icloud-en"></a>
## “Shortcut couldn’t be signed”
**Why:** macOS has Apple sign every new shortcut, which requires an iCloud sign-in. Sometimes Apple’s servers simply don’t answer.
1. Open **System Settings** and check the top of the sidebar: is your **Apple Account** signed in? If not, click **Sign In**.
2. Try again in Hoku: Settings → **Set Up Siri Commands**. Hoku retries each command three times by itself.
3. No iCloud? Create the commands yourself → [Siri without iCloud](siri.md#without-icloud-en)

<a id="siri-duplicates-en"></a>
## Siri opens the wrong app, or commands do nothing
**Why:** There are several copies of Hoku on your Mac (Downloads, Trash, an old version). That confuses Siri and the network permission.
1. Quit Hoku (right-click the icon → **Quit Hoku**).
2. Search the Finder for “Hoku” and move every `Hoku.app` that is **not** in Applications to the Trash. Then empty the Trash.
3. Open Hoku from Applications.

<a id="unreachable-en"></a>
## A lamp shows “Unreachable”
**Why:** The bridge can’t reach the lamp. Almost always the wall switch or power strip is off. Less often the lamp is too far away.
1. Turn the wall switch or socket on.
2. Wait about a minute. Hoku updates by itself.
3. Still there? **Settings → Device Check** shows which devices are affected. Then check the lamp in the Hue app.
Tip: Keep Hue lamps powered and switch them with Hoku or a Hue switch.

<a id="menu-bar-icon-en"></a>
## The menu bar icon is missing
**Why:** In a full menu bar, icons hide behind the camera notch. Or Hoku is hidden there.
1. Press **⌃⌥L**. It always opens Hoku.
2. Open **System Settings → Menu Bar** and turn on **Hoku** under **Allow in the Menu Bar**.
3. Make room: hide other icons or use an app like Ice.

<a id="login-item-en"></a>
## Hoku no longer opens at login
1. In Hoku’s Settings, turn on **Open at Login**.
2. If macOS asks: **System Settings → General → Login Items & Extensions** → turn on **Hoku**.

<a id="secondary-click-en"></a>
## Two-finger click doesn’t unfold anything
1. Open **System Settings → Trackpad → Point & Click** and set **Secondary click** to **Click or Tap with Two Fingers**.
2. Rooms with a single lamp don’t unfold, they just bounce. That’s intended.
3. With a mouse: right-click or control-click.

<a id="hotkey-en"></a>
## ⌃⌥L does nothing
**Why:** Another app uses the same key combination.
1. In Hoku, open Settings → **Keyboard Shortcuts** → click **Set** next to **Open Hoku** and press a new combination (with ⌘, ⌥ or ⌃).
2. If it says **in use**, another app already uses that combination. This goes for your light shortcuts, too.

> **Didn’t work?** → [FAQ](faq.md) · Or tell us on [GitHub](https://github.com/Philoni/hoku/issues/new): your macOS version, Hoku version (Finder → Applications → Hoku → ⌘I), bridge model and what you did. Please don’t post IP addresses or keys.
