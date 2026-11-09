---
id: install
title: Hoku installieren
title_en: Install Hoku
---

# Hoku installieren

> In zwei Minuten in deiner Menüleiste.

**Du brauchst:** einen Mac mit macOS 26 (Tahoe) oder neuer und eine Philips Hue Bridge im selben Netzwerk.

1. **Laden:** Hol dir die neueste **Hoku-‹Version›.dmg** von der [Release-Seite](https://github.com/Philoni/hoku/releases/latest).
2. **Ziehen:** Öffne die Datei und zieh **Hoku** auf den Ordner **Programme**.
   Bitte verschieben, nicht an einen anderen Ort kopieren. Eine zweite Kopie bringt Siri durcheinander.
3. **Öffnen:** Starte Hoku aus „Programme“ (oder mit ⌘-Leertaste und „Hoku“). macOS zeigt **„Hoku“ nicht geöffnet**. Klick auf **Fertig**, nicht auf „In den Papierkorb legen“.
4. **Erlauben:** Öffne **Systemeinstellungen → Datenschutz & Sicherheit** und scroll nach unten zu **Sicherheit**. Dort steht: „„Hoku“ wurde blockiert, um deinen Mac zu schützen.“ Klick auf **Dennoch öffnen**.
5. **Bestätigen:** Gib dein Passwort ein oder nutze Touch ID. Fragt macOS noch einmal **„Hoku“ öffnen?**, klick auf **Dennoch öffnen**.
6. **Einrichten:** Hoku begrüßt dich und führt dich durch den Rest: Netzwerk erlauben, Bridge koppeln, fertig.

**Das ist nur einmal nötig.** Für ein Update lädst du die neue Version und ersetzt die alte in „Programme“ – automatische Updates folgen.

<details>
<summary>Warum muss ich „Dennoch öffnen“ klicken?</summary>

Hoku ist kostenlos. Damit macOS eine App ohne Nachfrage öffnet, muss Apple sie prüfen (Notarisierung). Das kostet 99 € im Jahr. Hoku ist deshalb mit einem eigenen, dauerhaften Zertifikat signiert („Hoku Release Signing“), aber nicht von Apple geprüft. Der Code ist offen, jeder kann nachsehen. Rechtsklick → „Öffnen“ reicht seit macOS 15 nicht mehr.
</details>

<details>
<summary>Andere Wege: Zip, selbst bauen</summary>

- **Zip:** Doppelklick auf `Hoku-‹Version›.zip`, dann `Hoku.app` in **Programme** ziehen. Weiter bei Schritt 3.
- **Selbst bauen** (mit Xcode und kostenloser Apple-ID, ohne „Dennoch öffnen“): siehe [README](https://github.com/Philoni/hoku#selbst-bauen).
</details>

<a id="advanced-connection"></a>
<details>
<summary>Für Fortgeschrittene: Verbindung mit der Bridge (ab 0.9.1)</summary>

Normalerweise musst du hier nichts tun: Hoku findet die Bridge von selbst und findet sie auch wieder, wenn sich ihre Adresse ändert.

- **Schon einen Schlüssel?** Gib im Schritt mit der Bridge die IP-Adresse von Hand ein. Danach erscheint **Ich habe schon einen Schlüssel**. Füg dort deinen vorhandenen Hue-Schlüssel (Application Key) ein, und Hoku verbindet sich ohne Link-Taste. Der Schlüssel bleibt nur auf diesem Mac.
- **Verbindungsdetails:** Einstellungen → **Bridge** → **Verbindungsdetails** zeigen Status, Adresse, Bridge-ID, Modell, Software- und API-Version. Dort steht auch, wie die Verbindung gesichert ist: im lokalen Netzwerk, per HTTPS, mit einem von Signify ausgestellten Zertifikat, das an diese Bridge gebunden ist.
- **Adresse ändern:** Dort kannst du unter **Adresse von Hand** die IP der Bridge selbst eintragen. Hoku übernimmt sie nur, wenn unter dieser Adresse dieselbe Bridge antwortet.
</details>

> **Hat nicht geklappt?**
> → [Kein „Dennoch öffnen“ zu sehen](fehlerbehebung.md#open-anyway) · [Hoku findet die Bridge nicht](fehlerbehebung.md#local-network) · [Symbol fehlt in der Menüleiste](fehlerbehebung.md#menu-bar-icon)

---

## English

# Install Hoku

> In your menu bar in two minutes.

**You need:** a Mac with macOS 26 (Tahoe) or later and a Philips Hue Bridge on the same network.

1. **Download** the latest **Hoku-‹version›.dmg** from the [releases page](https://github.com/Philoni/hoku/releases/latest).
2. **Drag:** Open it and drag **Hoku** onto the **Applications** folder.
   Please move it rather than copying it somewhere else. A second copy confuses Siri.
3. **Open** Hoku from Applications (or press ⌘-Space and type “Hoku”). macOS shows **“Hoku” Not Opened**. Click **Done**, not “Move to Trash”.
4. **Allow:** Open **System Settings → Privacy & Security** and scroll down to **Security**. It says “Hoku” was blocked to protect your Mac. Click **Open Anyway**.
5. **Confirm** with your password or Touch ID. If macOS asks **Open “Hoku”?**, click **Open Anyway**.
6. **Set up:** Hoku welcomes you and walks you through the rest: allow the network, pair the bridge, done.

**You only do this once.** To update, download the new version and replace the old one in Applications – automatic updates are coming.

<details>
<summary>Why do I have to click “Open Anyway”?</summary>

Hoku is free. For macOS to open an app without asking, Apple has to check it first (notarization), which costs €99 a year. So Hoku is signed with its own long-lived certificate (“Hoku Release Signing”) but not checked by Apple. The code is open for anyone to read. Right-click → “Open” no longer works since macOS 15.
</details>

<details>
<summary>Other ways: Zip, build it yourself</summary>

- **Zip:** Double-click `Hoku-‹version›.zip`, then drag `Hoku.app` to **Applications**. Continue with step 3.
- **Build it yourself** (Xcode and a free Apple ID, no “Open Anyway” needed): see the [README](https://github.com/Philoni/hoku#build-from-source).
</details>

<a id="advanced-connection-en"></a>
<details>
<summary>For advanced users: connecting to the bridge (from 0.9.1)</summary>

Normally you don’t need any of this: Hoku finds the bridge on its own and finds it again if its address changes.

- **Already have a key?** In the setup assistant’s bridge step, enter the IP address by hand. **I already have a key** then appears. Paste your existing Hue application key there and Hoku connects without the link button. The key stays on this Mac only.
- **Connection details:** Settings → **Bridge** → **Connection Details** show status, address, bridge ID, model, software and API version. They also show how the connection is secured: on your local network, over HTTPS, with a certificate issued by Signify and pinned to this bridge.
- **Change the address:** There, **Manual Address** lets you set the bridge’s IP yourself. Hoku only accepts it if the same bridge answers at that address.
</details>

> **Didn’t work?**
> → [No “Open Anyway” button](fehlerbehebung.md#open-anyway) · [Hoku can’t find the bridge](fehlerbehebung.md#local-network) · [No icon in the menu bar](fehlerbehebung.md#menu-bar-icon)
