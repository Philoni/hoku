# Security Policy

> **Deutsch:** Sicherheitslücken bitte **nicht** als öffentliches Issue melden, sondern privat über
> [„Report a vulnerability“](https://github.com/Philoni/hoku/security/advisories/new). Deutsch oder Englisch ist beides in Ordnung.

## Supported versions
Hoku is a small spare-time project. Security fixes go into the **latest release** only, so please update
before reporting.

| Version | Supported |
|---|---|
| latest 0.9.x | yes |
| older | no |

## Reporting a vulnerability
Please report privately via GitHub: **[Report a vulnerability](https://github.com/Philoni/hoku/security/advisories/new)**
(Security tab → "Report a vulnerability"). Do not open a public issue, discussion or pull request for it.

Helpful details: Hoku version, macOS version, what an attacker needs (same network? a malicious website?
local access?), steps to reproduce, and the impact you see. Please do **not** include your real bridge key
(`hue-application-key`) or other personal data – a description is enough.

What you can expect (best effort, one maintainer):
- acknowledgement within **7 days**,
- an assessment and a plan within **30 days**,
- a fixed release, then a published GitHub Security Advisory crediting you (unless you prefer not to be named).

## Scope
In scope – anything in this repository and the release artifacts, for example:
- the **`hoku://` URL scheme** (any website or app can try to open it),
- storage of the bridge credentials (`~/Library/Application Support/Hoku`, file mode 0600),
- TLS certificate pinning towards the Hue Bridge (`BridgeTrust`), bridge discovery and pairing,
- the generated personal Siri shortcuts and App Intents,
- the **release chain**: the release signing certificate and the published zip files (and, once added, the
  Sparkle update feed).

Out of scope:
- **Gatekeeper warnings on first launch.** Hoku is signed with its own certificate ("Hoku Release Signing") but
  not notarized by Apple – this is expected and documented in the README.
- Vulnerabilities in the **Hue Bridge, its firmware or the Hue cloud** – please report those to Signify:
  via the Philips Hue support pages (<https://www.philips-hue.com/support>).
- Vulnerabilities in macOS or Sparkle themselves – please report them upstream (Apple Security Research,
  Sparkle's security policy). We'll gladly update quickly once a fix exists.
- Attacks that require an attacker who already has full control of your Mac user account.

## Verifying a download
Each release lists the SHA-256 of `Hoku-X.Y.Z.zip` and the SHA-1 fingerprint of the release certificate.
The app's designated requirement must contain that fingerprint:

```sh
shasum -a 256 -c Hoku-X.Y.Z.zip.sha256
codesign -d -r- /Applications/Hoku.app   # → identifier "io.github.philoni.hoku" and certificate leaf = H"<fingerprint>"
```

If a "Hoku" app is signed differently and did not come from your own source build, do not run it – and please tell us.
