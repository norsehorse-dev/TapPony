# TapPony

Planning document, Rev 2
September 25, 2026 (Rev 1: September 10, 2026)
Status: approved to start. Hardware spike and cores begin now, in parallel with current work.
Origin: suggested by a PGPony tester (Sep 2026). The first TestFlight build goes to that tester.

When the repos are created, this file becomes `PLANNING_1_0_0.md` at each repo root.

---

## 0. Decisions to date

- Sep 10, 2026: **Platform order.** iOS first, then Android. The iOS gap is the reason the app exists; Android follows on the same profile format. (Superseded Sep 25: Android is built in parallel; iOS still leads the pitch.)
- Sep 10, 2026: **Localization.** Family set at 1.0: en, de, es, fr, zh-Hans, pt-BR, ru.
- Sep 10, 2026: **Google Play.** Eventually, not at launch. F-Droid and direct APK first.
- Sep 10, 2026: **Tag writing.** In scope. It is what makes background launch possible (section 10.4).
- Sep 10, 2026: **Posture.** Ambitious. The recommendations in section 20 stand as provisional decisions unless overridden, same arrangement as the HashPony doc.

- Sep 25, 2026: **Name locked: TapPony.** IP sweep (web, App Store, Google Play, GitHub) found nothing using the name. Nearest strings are games in a different class: "Tappy Pony" (Google Play) and "Pony Tap Run" (App Store). Still to do by hand, since the planning sandbox cannot reach DNS or RDAP: a direct search at tmsearch.uspto.gov and the registrar check for tappony.app, which gets registered immediately because universal links and App Links depend on it.
- Sep 25, 2026: **Scope: full 1.0, phases A through E, one launch.** No early public build. The cut order in section 15 stays only as a contingency if the schedule breaks.
- Sep 25, 2026: **1.0 launches free on every channel.** No StoreKit 2 and no Play Billing in 1.0. The Plus feature line in sections 8 and 9 is kept and every Plus feature sits behind one entitlement gate (`Entitlements.plus`, hard-wired to true), so turning on the unlock later is a small update rather than a refactor. Section 9 describes the future unlock.
- Sep 25, 2026: **Android in parallel.** The full Android app is built alongside iOS instead of after it, on the same profile schema and conformance fixtures from the first commit. Side benefit: Android reads MIFARE Classic badge UIDs, so the access-logging job is covered early on F-Droid even if iPhone cannot read them.
- Sep 25, 2026: **Start now**, in parallel with the HashPony UI work and SopsPony.
- Sep 25, 2026: **Brand color: signal blue on charcoal.**
- Sep 25, 2026: **The Shortcuts "Read NFC Tag" action moves into Phase A.** Getting a tag's UID into Shortcuts is the most-asked-for piece of the gap and the easiest thing to show on r/shortcuts and r/homeassistant, so it is built with the reader, not in the automation phase.
- Sep 25, 2026: **Credit and names.** No tester names anywhere public: app, README, release notes, commit messages, or this file once it moves into the repo. Credit reads "suggested by a tester". Tester assignments live outside the repo.
- Sep 25, 2026: **Distribution.** F-Droid, direct APK, and GitHub releases. IzzyOnDroid is not a channel for this family.

Use-case questions for the requesting tester (use case, receiver, tags on hand, Shortcuts) were drafted in English on Sep 25; the answers roll into Rev 3. Already known: the tester's device is an iPhone 11 (Core NFC tag reading and background tag reading both supported, since background reading needs XS or later), and TestFlight uses the same Apple ID as the existing family betas.

## 1. Summary

Scan an NFC tag and the phone immediately sends an HTTP request you designed to a server you chose. The request carries the tag's UID, every other identifier the chip exposes (chip model, originality signature, IC manufacturer, FeliCa IDm and so on), and the NDEF payload. Method, URL, headers, and body are templates with variables; several profiles live side by side; the tag itself can route to the right one. No account, no cloud, no telemetry. Config and history stay on the device, secrets stay in the Keychain or Keystore. The missing "Get NFC tag" action for iOS, shipped as an app.

## 2. Why this app, why now

The gap is a platform one. Shortcuts has had an NFC trigger since iOS 13, and it identifies tags by UID internally, but each automation is bound to one pre-registered tag and the flow never receives the UID or the NDEF content as a variable. You cannot build "scan any badge and post its number" in Shortcuts at all. Core NFC hands an app the identifiers directly (iOS 13 and later, `NFCTagReaderSession`), so an app can do what Shortcuts cannot.

Market as of September 2026:

- NFC.cool has a webhook feature, but only in its Platinum subscription tier, with one URL for every scan, HTTP Basic auth only, and no custom headers or body templates. Closed source.
- NFC Tools and NFC Tasks (wakdev) run tasks that are written onto the tag as a proprietary NDEF record, so they fire only for tags you have written, need writable tags, and the tag content is the trigger, not the tag's identity. The HTTP tasks live in the Android NFC Tasks app; the iOS app carries a reduced task set, and the tasks still live on the tag.
- Home Assistant Companion supports tags on both platforms, but only tags it has written its own `https://www.home-assistant.io/tag/<id>` URL onto. Existing badges, fobs, and read-only tags are out, and on iOS the scan is a notification the user has to tap. Home Assistant only.
- NFC Web Gate (App Store, 2025) sits closest by name. The listing would not load during research; evaluate before launch copy is written.
- Android has more prior art: NFC ReTag (UID-based, 2012-era XDA app), and the general automation apps (Tasker, MacroDroid, Automate) with NFC triggers and HTTP actions. All closed source. Android is well served for hobbyists and poorly served for anyone who wants a focused, auditable tool.

Nothing here is a dying incumbent, which is the filter PGPony and HashPony passed. What this replaces is a stack of workarounds: per-tag Shortcuts automations, HA-written tags, NFC Tasks records, or a subscription for a single-URL webhook. The strongest claims are (a) works with tags you did not write and cannot write, (b) a real request builder, (c) free at 1.0, and a one-time unlock rather than a subscription if a paid tier comes later, (d) open source, (e) a native Shortcuts action that returns the UID and content into any flow, free. (NFC.cool can launch a shortcut on scan in its paid tier; whether it passes the identifier along is unverified and worth checking before the listing copy claims exclusivity.)

Rev 2 update (Sep 25, 2026): NFC.cool shipped 7.0 this week (about 6.8K ratings, 4.5 stars) and is actively developed. Its subscription is $3.99/month or $29.99/year. The listing now advertises webhooks ("send scan data to your server") and an "NFC Tap Counter" that appends the tag ID and tap count to a URL, email, SMS, or Shortcut. Tap Counter reads like the NTAG UID and counter mirror written onto the tag, which would limit it to tags NFC.cool wrote; confirm on hardware in the Phase A spike. Consequence for the listing: lead with claim (a), works with any tag including ones you cannot write, and do not claim to be the only app that gets a tag ID into Shortcuts. NFC Web Gate's US App Store listing returned a 404 on Sep 25 and looks pulled from the US store.

Name check (September 10, 2026): nothing called TapPony on the App Store, Google Play, or the web (nearest strings: a "Pony Tap Run" game, a bar's Facebook page). tappony.app and tappony.com have no DNS records, which is a soft signal only; the full IP sweep and registrar check are Q1 in section 20.

## 3. Target users and the jobs they are doing

**Asset tracking.** Small shops, labs, workshops, rental fleets. Stickers or ISO 15693 labels on equipment, a spreadsheet or inventory system behind a webhook. The job: tap the item, log where it is and who touched it, no barcode app and no typing. Batch mode matters here (thirty boxes in a row), and so does a stable UID that matches what their desktop reader printed (byte order, section 7.3).

**Access and attendance logging.** Existing employee badges, gym fobs, hotel-style cards. The job: tap a badge, post the badge number and a timestamp to a sign-in sheet or a door controller's API. The badge was issued by someone else, so it cannot be rewritten, and its UID is the only identity it has. Caveat that shapes the pitch: many legacy badges are MIFARE Classic, which iPhone cannot read reliably (section 10.1). Android handles them.

**Home Assistant and home automation.** Tags on the nightstand, by the door, on the washing machine. The job: tap to run a scene, with the tag's identity deciding which one, and a body the automation can template on. Most HA installs are on a LAN over plain HTTP, which drives the local-network policy in section 13.2. The `tag_scanned` preset lets existing cards act as HA tags without HA's companion app writing them.

**Field checklists and rounds.** Security rounds, maintenance rounds, cleaning checklists, delivery proof. Tags at each checkpoint, a form backend or a spreadsheet receiving one row per tap. The job: prove presence at a place and time. Offline queueing matters (basements, parking decks), and so does a server-returned message ("Checkpoint 4 of 9") shown on the phone.

**Makers and integrators.** People with n8n, Node-RED, ntfy, Zapier, or their own scripts. The job: an NFC event source with a request they fully control. They are also the ones who will read the source, file issues, and talk about the app.

## 4. Competitive landscape, and what we do better

| | TapPony | NFC.cool | NFC Tools / NFC Tasks | HA Companion | Shortcuts NFC trigger | Android automation apps |
|---|---|---|---|---|---|---|
| Works with tags you did not write | yes | yes | no (task on tag) | no (HA URL on tag) | yes (per registered tag) | partly (NFC ReTag yes) |
| UID in the request | yes, plus chip, signature, IDm | yes (identifier) | no | no (HA tag id) | no | varies |
| NDEF payload in the request | yes, decoded and raw | yes (content) | n/a | n/a | no | varies |
| Request builder (method, headers, body template) | full | one URL, Basic auth | HTTP tasks on Android | fixed HA webhook | Shortcuts actions | yes (HTTP actions) |
| Multiple profiles, tag routing | yes | one URL | per tag | HA automations | per automation | per macro |
| Batch scanning | yes | no | no | no | no | limited |
| Offline queue | yes | no | no | no | no | possible |
| Shortcuts action that returns the UID | yes, free | Tap Counter appends tag ID to a Shortcut URL (paid; appears limited to tags it wrote, verify) | no | no | n/a | n/a |
| Pricing | free everywhere at 1.0; one-time unlock later on store builds, F-Droid always free | subscription ($3.99/mo, $29.99/yr) | free plus Pro | free | free | free or one-time |
| Source | open | closed | closed | open | n/a | closed |

Where the incumbents are better and we should not pretend otherwise: NFC Tools is a far more complete tag toolbox (memory dumps, advanced commands, formatting on Android), Home Assistant Companion has device tracking and the whole HA integration, and the Android automation apps can do anything after the scan. TapPony wins by doing one job completely and being the only option on iOS that exposes tag identity to the user's own systems.

## 5. Goals and non-goals

Goals for 1.0:

- Read every identifier Core NFC exposes for ISO 14443-A (MIFARE family), ISO 15693, FeliCa, and ISO 7816 tags, plus the NDEF message, and hand them to a request template.
- A request builder good enough that a Node-RED user never feels boxed in: any method, URL, headers, JSON, form, or raw body, secrets by reference, HMAC signing.
- Profiles, presets for the common receivers, and rules that route a tag to the right profile.
- Fast entry points: Action button, Control Center, Lock Screen widget, Shortcuts, and background launch for tags we wrote ourselves.
- History that is useful for debugging and useless to anyone who takes the phone: no bodies unless asked, clear in one tap.
- Write tags: URL, text, our own launch link, mirror the UID into NDEF for readers that cannot see it.
- Android twin on the same profile JSON so a profile exported on one platform imports on the other.

Non-goals, deliberate:

- No account, no sync, no cloud relay. If two phones need the same profiles, they exchange a QR or an encrypted file.
- No tag memory dumps, sector editing, or password-protected NTAG features at 1.0. NFC Tools owns that; we read identifiers and NDEF, we write NDEF.
- No card emulation (HCE), no payment cards, no reading of ID documents. Apple gates the first two behind separate frameworks and the third is a different product.
- No scripting language in templates. Variables with modifiers, nothing that loops or branches. Logic belongs on the server.
- No analytics or crash reporting SDKs, ever. The only network traffic is the requests the user configured, plus the store's purchase flow on store builds.

## 6. Product shape

Four tabs plus Settings.

**Scan tab.** The main screen. A big scan button with the active profile's name on it, a profile switcher above, the last result below (profile, tag identity, HTTP status, latency, server message if the profile extracts one). Tapping scan starts the Core NFC sheet; the tag is read; the sheet closes; the request goes out; the result lands on this screen with a haptic and an optional sound. A batch toggle keeps the session alive for tag after tag with a running count. A queue badge shows when requests are waiting for a connection.

**Profiles tab.** The list, plus the editor. The editor has three panes: Request (method, URL, headers, body type and template, timeout, redirect policy, local-network opt-in), Tag (which technologies to accept, UID format, extended reads on or off, rules), and After (what to show on success and failure, which response field to surface, sound and haptic). A Test button sends the request with sample variables and shows the full exchange with secrets masked. Presets live behind "New from preset".

**Tags tab.** Two jobs. Write: pick a record type (URL, text, TapPony launch link, mirror UID), write, optionally lock. Registry: tags the app has seen, with a name and notes the user adds; a named tag exposes `{tag_label}` to templates and feeds the rules engine.

**History tab.** One row per scan: time, profile, identity, outcome. Tap for details. Bodies appear only if the profile keeps them. Filter by profile or outcome, export as CSV, clear all, auto-clear after N days.

**Settings.** Default UID format, device label, sounds and haptics, Local network and NFC status, a plain note that everything is free (the unlock screen replaces it when the unlock ships), and the family sections: About, Help, Licenses, More from NorseHorse, hub link, source link.

Onboarding is one screen: pick a preset or start blank, paste a URL, scan a tag. The first scan should succeed inside a minute of install.

## 7. Request engine

This is the core of the app and the part both platforms share as a spec. It is deliberately small: variables, modifiers, context-aware escaping. No conditionals, no loops.

### 7.1 Variables

Identity:

| Variable | Meaning | Notes |
|---|---|---|
| `{uid}` | canonical UID, uppercase hex, no separators | canonical byte order per 7.3 |
| `{uid_colon}` | `04:A2:7F:1B:5E:80:00` form | what NFC Tools and NXP TagInfo display |
| `{uid_dec}` | UID as a decimal integer, big-endian | what Wiegand-style access readers print |
| `{uid_rev}` | reversed byte order | what many USB desktop readers report |
| `{uid_len}` | 4, 7, 8, or 10 | |
| `{tag_type}` | `mifare_ultralight`, `mifare_desfire`, `mifare_plus`, `mifare_classic` (Android only), `iso15693`, `felica`, `iso7816`, `unknown` | |
| `{chip}` | `NTAG213`, `NTAG215`, `NTAG216`, `Ultralight EV1`, `DESFire EV1/EV2/EV3`, `ICODE SLIX2`, or empty | from GET_VERSION, Get System Info, IC reference |
| `{manufacturer}` | NXP, STMicro, Infineon, Sony, and so on | ISO 15693 IC manufacturer code, NFC-A UID0 heuristics |
| `{signature}` | NTAG21x / Ultralight EV1 originality signature, hex | empty when the chip has none or the read fails |
| `{counter}` | NTAG21x NFC counter | empty unless the tag has it enabled |
| `{random_uid}` | `true` when the tag presented a random ID (UID0 = 0x08) | see 7.4 |
| `{atqa}`, `{sak}` | NFC-A low-level bytes | Android only; empty on iOS |
| `{dsfid}`, `{afi}`, `{block_size}`, `{block_count}` | ISO 15693 system info | |
| `{idm}`, `{pmm}`, `{system_code}` | FeliCa | `{uid}` equals `{idm}` for FeliCa |
| `{pupi}`, `{historical_bytes}`, `{application_data}` | ISO 14443-4 / ISO 7816 | |
| `{tag_label}` | name from the Tags registry, empty if unnamed | |

Content:

| Variable | Meaning |
|---|---|
| `{payload}` | first NDEF record decoded: text for Text records, the URL for URI records, base64 otherwise; empty if no NDEF |
| `{ndef_text}` | first Text record |
| `{ndef_uri}` | first URI record |
| `{ndef_json}` | JSON array of records: tnf, type, id, payload base64, decoded text or uri where applicable |
| `{ndef_raw}` | base64 of the raw NDEF message bytes |
| `{ndef_count}` | record count |
| `{token}` | the `k` parameter of a TapPony launch link, when the scan came from one |

Context:

| Variable | Meaning |
|---|---|
| `{timestamp}` | scan time, ISO 8601 UTC with milliseconds |
| `{timestamp_local}`, `{unix}`, `{tz}` | local form, epoch seconds, IANA zone |
| `{sent_at}` | send time, differs from `{timestamp}` for queued requests |
| `{profile}`, `{profile_id}` | profile name and stable id |
| `{device_label}` | a label the user typed in Settings, empty by default; never a hardware identifier |
| `{platform}` | `ios` or `android` |
| `{nonce}` | 16 random bytes, hex, fresh per request |
| `{seq}` | per-profile monotonic counter |
| `{secret:NAME}` | resolved from the Keychain or Keystore at send time; allowed in headers, URL, and body; never rendered into history |

### 7.2 Modifiers and escaping

Modifiers chain with a pipe: `{uid|lower}`, `{payload|b64}`, `{ndef_text|url}`, `{uid|dec}`, `{uid|rev}`, `{timestamp|unix}`, `{payload|trim}`, `{payload|slice:0:32}`. Escaping is automatic by context: a variable inside a JSON body template is JSON-string-escaped, inside a URL it is percent-encoded, inside a form body it is form-encoded, inside a header it is stripped of CR and LF. `|raw` opts out, and the editor warns when it is used in a JSON body. This is the defense against hostile tags (section 13.5): NDEF content is attacker-controlled input and it must never be able to break out of a JSON string or inject a header.

Body types: JSON (default, template is the whole document), form (key and value pairs), raw (any text, any content type), none. Methods: GET, POST, PUT, PATCH, DELETE. Headers are key and value pairs with a "secret" flag per value. Auth helpers write the right header for Bearer, Basic, and API-key patterns so nobody has to remember base64.

### 7.3 Canonical UID byte order

The same tag must produce the same `{uid}` on iOS, on Android, and on a desktop reader, or every server-side allow-list breaks. The rule: `{uid}` is the order printed by NXP TagInfo and by the NFC Forum, which for ISO 14443-A is UID0 first (the manufacturer byte, 0x04 for NXP), for ISO 15693 is E0 first (the tag transmits it least significant byte first, and Android's `getId()` returns it in transmission order, so Android reverses; Core NFC's `identifier` needs a hardware check in the spike), and for FeliCa is the IDm as displayed. `{uid_rev}` exists for readers that disagree. Test vectors for every family go in the shared conformance fixtures (section 19).

### 7.4 Things a tag can do to you

- Random UIDs. DESFire EV2 and EV3 can be configured to present a random 4-byte ID starting with 0x08, and some ISO 14443-B cards randomize the PUPI. The app flags these (`{random_uid}`), the Scan tab explains it, and the fix is NDEF or a launch link, not the UID.
- MIFARE Classic on iPhone: not supported by Core NFC. Expect no tag object or an unusable one. The app says so instead of failing silently.
- A tag can carry any NDEF at all. Treat it as untrusted input everywhere (7.2, 13.5).

### 7.5 Presets

Shipped free, editable after creation, each with a one-paragraph explainer of what to set up on the other end:

- Home Assistant webhook trigger: `POST http://homeassistant.local:8123/api/webhook/<id>`, JSON body with uid, chip, payload, timestamp, device_label. Local network profile.
- Home Assistant `tag_scanned` event: `POST /api/events/tag_scanned` with a long-lived token as Bearer and `{"tag_id": "{uid}"}`. This makes any card a Home Assistant tag without the companion app writing it. Whether HA auto-registers the tag in its Tags list when the event arrives by REST rather than from the companion app needs a test; the automation trigger itself matches on `tag_id`.
- Node-RED `http in` node, n8n Webhook node, Zapier Catch Hook, Make custom webhook, IFTTT Webhooks (`/trigger/{event}/json/with/key/{key}`).
- ntfy (`POST https://ntfy.sh/<topic>`, text body), Discord and Slack incoming webhooks (JSON `content` or `text`).
- Generic JSON, generic form, generic GET with query parameters.
- Google Sheets via Apps Script web app, and a plain "log to CSV endpoint" example with a ten-line PHP receiver in the docs, since a PHP receiver on the apps VPS is the natural demo backend for this family.

## 8. Feature list: 1.0 and later

**1.0, free everywhere**

- Scan with the Core NFC sheet; ISO 14443-A MIFARE family, ISO 15693, FeliCa (curated system code list), ISO 7816 (optional AID list).
- Every variable in 7.1 including the extended reads (chip, signature, counter, system info), with per-profile toggles so people who only want the UID do not pay the extra tag time.
- Request builder per 7.2, up to three profiles, Test send with masked secrets, presets.
- Secrets in the Keychain, TLS enforced for public hosts, local-network opt-in per profile, HMAC-SHA256 signing header.
- History with identities and outcomes, bodies off by default, CSV export, clear, auto-clear.
- Shortcuts: "Read NFC Tag" action returning uid, chip, tag type, NDEF text and URI, signature; "Scan and Send" action per profile returning status and response field.
- Control Center control and Action button assignment (iOS 18), Lock Screen and Home Screen widgets, `tappony://scan?profile=<id>` URL scheme, App Shortcuts phrases.
- Tag writing: URL, text, TapPony launch link, mirror UID into NDEF, lock with a double confirm.
- Background launch for tags carrying a TapPony launch link (iPhone XS and later), landing in the chosen profile with `{payload}` and `{token}`.
- Family sections, seven locales, open source.

**1.0, Plus features (free on every channel at 1.0; this is the line the future store unlock will draw, and F-Droid and direct APK keep everything on forever)**

- Unlimited profiles.
- Rules: route by UID, UID prefix, regex, tag type, NDEF content, or tag label to one or more profiles; ignore unknown tags; fan-out to several requests per scan.
- Batch mode with per-tag results and dedupe window.
- Offline queue with retry and backoff, manual flush, queue badge.
- Response rules: surface a JSON field or header as the on-screen message, custom success and failure text per status range, spoken confirmation (TTS) for hands-free rounds.
- Encrypted profile export and import (all profiles, passphrase-protected, secrets included only when the user opts in) and QR handoff between devices, cross-platform.
- Custom transforms beyond the built-in modifiers: user-defined UID formats (separator, case, byte order, prefix and suffix) saved as named formats.
- Tags registry beyond 25 entries, with notes and per-tag default profile.

**Later, unscheduled**

- mTLS client certificates (PKCS#12 import) for profiles that need them; pinning by certificate fingerprint for LAN hosts with self-signed TLS. 1.1 candidate, earlier if the requesting tester's receiver needs it.
- Android launch-on-any-tag via `ACTION_TECH_DISCOVERED` (system chooser UX makes it a toggle, not a default).
- Tasker and MacroDroid interop on Android: broadcast intents in and out.
- NTAG password-protected reads, memory dumps, sector tools. Only if users who arrive from NFC Tools ask for them with a use case.
- Watch app (Apple Watch has no third-party NFC access; would only trigger a phone scan, so probably never).
- Bulk write for batches of launch-link tags.

## 9. Monetization

**At 1.0 (decided Sep 25, 2026):** free on every channel with every feature on. Neither platform links a billing library. Each Plus feature checks one gate, `Entitlements.plus`, which is a constant `true` in 1.0; the gate exists only so the future unlock is a small update. The Settings screen says plainly that everything is free. No promo codes are needed yet.

**Later, when the unlock turns on (planned, not scheduled):** the rest of this section describes it. Matches the family plan: core free everywhere; a small one-time unlock on the App Store and Google Play for the advanced set in section 8; the F-Droid build and the direct APK have everything enabled; promo codes for testers. Users who installed while everything was free should keep what they had; decide the mechanism (grandfathering by original purchase date on iOS via the app transaction, by first-install flag on Android) when the unlock is built.

- Unlock name: "TapPony Plus" (avoids "Pro", which the NFC reader clones all use). Price recommendation: set when the unlock ships. Rev 1 said $2.99; against NFC.cool's $29.99 a year, $4.99 is also easy to defend. One non-consumable product, StoreKit 2 on iOS, Play Billing one-time product in the `play` flavor on Android. Restore purchases is one tap and works without an account because both stores handle it.
- The line between free and unlocked is drawn so the free app does the whole core job (scan, full request builder, three profiles, presets, history, Shortcuts, writing). Nothing security-related is gated: TLS policy, Keychain storage, HMAC signing, history clearing are free on principle. The unlock buys scale and automation: more profiles, rules, batch, queue, response handling, export.
- Testers: App Store promo codes for in-app purchases (Apple allows up to 100 codes per in-app purchase item, 1,000 per app, codes expire four weeks after generation); Google Play promo codes (up to 500 per quarter across non-subscription promotions per app, unused codes do not carry over). No hidden unlock paths in the code; a tester without a store account uses the direct APK or the F-Droid build, which have everything.
- The `foss` flavor has no billing dependency at all, which keeps the F-Droid inclusion clean. The `play` flavor is the only place the Play Billing library appears. iOS has no flavor problem: StoreKit is first-party.
- The Settings unlock screen states plainly that the F-Droid build is free with everything, with a link. Honesty about that is the brand.

## 10. iOS technical notes

### 10.1 Which tag technologies expose which identifiers

`NFCTagReaderSession` (iOS 13 and later, iPhone 7 and later) with polling options `.iso14443`, `.iso15693`, and `.iso18092` (FeliCa). One reader session of any type can be active at a time systemwide.

- **NFCMiFareTag** (ISO 14443-A, NFC-A). `identifier` is the UID (7 bytes for NTAG, Ultralight, and DESFire; 4 bytes in random-ID mode and on some older or cloned cards). `mifareFamily` is `.ultralight`, `.plus`, `.desfire`, or `.unknown`. `historicalBytes` for the ISO 14443-4 capable ones. Extended reads through `sendMiFareCommand`: `GET_VERSION` (0x60) returns the exact chip and storage size for NTAG21x and Ultralight EV1 and NANO; `READ_SIG` (0x3C 0x00) returns the 32-byte NXP originality signature; `READ_CNT` (0x39 0x02) returns the NFC counter when enabled. NXP TagInfo and NFC Tools do these on iPhone, so the path works; the spike confirms the exact byte handling. DESFire and Plus take ISO 7816-wrapped commands through `sendMiFareISO7816Command`; a wrapped `GetVersion` (0x60) identifies EV1, EV2, EV3 and the production batch. Note the `D2760000850101` rule: if that NDEF application ID is listed in the ISO 7816 identifiers, DESFire arrives as an `NFCISO7816Tag` instead of an `NFCMiFareTag`. The default AID list therefore leaves it out.
- **MIFARE Classic.** Not supported by Core NFC. `NFCMiFareFamily` has no Classic case; developer reports range from the tag never being delivered to `connect` failing. Some NDEF-formatted Classic tags can be read through `NFCNDEFReaderSession`, but a raw access badge with no NDEF is invisible. This is the single most important hardware test before any copy mentions badges. Android reads Classic UIDs fine (section 11).
- **NFCISO15693Tag** (ICODE SLIX, ST M24LR, Infineon my-d). `identifier` (8 bytes, starts with E0 in canonical order), `icManufacturerCode`, `icSerialNumber`, and `getSystemInfo` for DSFID, AFI, block size and count, and the IC reference that names the chip. Byte order needs the hardware check in 7.3.
- **NFCFeliCaTag** (Sony, ISO 18092). `currentIDm` (8 bytes, the identity), `currentSystemCode`, and Polling returns the PMm. Requires the FeliCa system codes Info.plist list; Apple states each code must be a discrete value and the wildcard is not allowed. Default list: `12FC` (NFC Forum Type 3 NDEF), `88B4` (FeliCa Lite-S), `0003` (transit cards), `FE00` (common area), user-editable. Mostly a Japan feature, but it costs a plist entry and one delegate branch.
- **NFCISO7816Tag** (ISO 14443-4 Type A and B smart cards). `identifier` is the UID for Type A and the PUPI for Type B, plus `historicalBytes` (A), `applicationData` (B), `initialSelectedAID`. Only delivered when the app lists at least one AID the card answers to. Default off, a toggle adds `D2760000850101` (NFC Forum Type 4 NDEF) and a short public list; the user can add their own. `NFCTagReaderSession` refuses payment AIDs by design, which suits us.

Every tag class above also conforms to `NFCNDEFTag`: `queryNDEFStatus` then `readNDEF` give the NDEF message and capacity, and `writeNDEF` writes one. Core NFC cannot format an unformatted tag; NTAGs ship formatted, and Android can format the rest.

### 10.2 Entitlement and Info.plist

- Capability "Near Field Communication Tag Reading" on the App ID, which adds the entitlement `com.apple.developer.nfc.readersession.formats` with `TAG` and `NDEF` to the entitlements file. A forum report on iOS 26.2 of "Missing required entitlement" despite a correct setup was resolved by re-adding the capability through Signing and Capabilities in Xcode 26.1.1 and regenerating profiles, so do it through the UI, not by hand-editing.
- `NFCReaderUsageDescription` (required, shown in the sheet).
- `com.apple.developer.nfc.readersession.iso7816.select-identifiers` (Info.plist, array of AID hex strings) for ISO 7816.
- `com.apple.developer.nfc.readersession.felica.systemcodes` (Info.plist, array of 4-hex-digit codes, no wildcard) for FeliCa.
- `NSLocalNetworkUsageDescription` (the local network permission prompt appears the first time a profile targets a LAN address).
- `NSAppTransportSecurity` with `NSAllowsLocalNetworking = YES`. Apple's own text: on iOS 17 and later ATS no longer allows connections to IP addresses by default, and this key re-enables unqualified names, `.local`, and IP addresses; it is not on Apple's list of exceptions that require App Review justification. No `NSAllowsArbitraryLoads`, no per-domain exceptions, so plain HTTP to a public hostname stays impossible at the platform level as well as in our validator.
- Associated Domains (`applinks:tappony.app`) for background launch, with the AASA file on the domain.
- No background modes. Nothing here needs one; the offline queue flushes on foreground and opportunistically through `BGAppRefreshTask`.

### 10.3 Session UX and error states

Flow for a normal scan: `begin()` with the profile's alert text ("Hold near the badge") → `didDetect` (if more than one tag, set the message to "More than one tag, hold just one" and `restartPolling()` after half a second) → `connect` → read identifiers, then NDEF, then extended commands, each with a short timeout so a stalled command cannot eat the session → `invalidate()` so the system sheet shows its checkmark and closes → send the request from the app with the result on the Scan tab, haptic and sound. The network call never runs inside the session: the session has a 60-second lifetime, the sheet blocks the UI while it is up, and a slow server would make a successful tag read look like a failure. The sheet reports the read, the app reports the send.

Batch mode: after each tag, `restartPolling()` instead of `invalidate()`, the alert text carries the count, requests go out in the background as tags come in, and when the 60-second session times out the app immediately begins a new one until the user stops. Dedupe by UID within a configurable window so a tag held too long does not double-post.

Error states, each with its own copy:

- NFC unavailable (`readingAvailable` false: iPad, older hardware, or restrictions): the scan button explains instead of failing; Shortcuts and widgets are hidden.
- Session timeout (60 s with no tag): quiet, back to idle.
- User cancelled: quiet.
- System busy (another session active, or the system queued ours): retry once, then explain.
- Tag connection lost mid-read (moved away too early): "Hold still and try again," with whatever identifiers were read shown greyed out, not sent.
- Unsupported tag (Classic, unknown family): explain, offer the NDEF-only path if NDEF read succeeded.
- Random UID detected: warn, offer NDEF or launch link.
- Multiple tags: handled above.
- NDEF absent or unreadable: not an error; `{payload}` is empty and the request still goes out unless the profile requires NDEF.
- Network: offline (queue if unlocked and enabled, else fail with retry), TLS failure (show the reason; for LAN hosts offer the pinning path later), timeout, 4xx and 5xx (status plus the first 4 KB of the body when the profile keeps bodies), local-network permission denied (deep link to Settings).

### 10.4 Background tag reading: worth it, with the right expectations

Apple's mechanism: on iPhone XS and later, the system reads NDEF tags whose first URI record is a universal link or a supported scheme, shows a notification, and after the user taps it launches the app with the NDEF message in an `NSUserActivity` (`ndefMessagePayload`). It is off while the device has never been unlocked, while a Core NFC session is running, while Wallet or the camera is in use, and in Airplane mode. The UID is never delivered this way.

So it solves only the "tags I own" half of the problem, and it still costs a tap. Recommendation: ship it in 1.0 anyway, because tag writing is in scope and the two features compose into something no competitor has: write a TapPony launch link to a tag, and from then on that tag launches the right profile from the Lock Screen on any iPhone XS or later with the app installed, no app open, two taps total. Android gets the same through App Links. Identity in this mode is the `k` token in the link, not the UID; the profile can optionally require a follow-up in-app read to attach the UID for tags that also matter by hardware identity. For tags the user cannot write (every badge and fob), the foreground entry points in 10.5 are the answer, and they are the ones the marketing leads with.

Cost: the domain, an AASA file served from tappony.app, the Associated Domains entitlement, and one URL handler. Two evenings.

### 10.5 Fast entry points

- App Intents: `ReadNFCTagIntent` (opens the app, runs the sheet, returns a `TagReading` entity with uid, chip, tag type, NDEF text, NDEF URI, signature) and `ScanAndSendIntent(profile)` (returns status, latency, extracted message). Both run in the foreground because Core NFC requires it; Shortcuts resumes when `perform()` returns. The spike verifies that a foreground-opening intent returns its value to Shortcuts cleanly, since that is the whole point of the action.
- Control Center control (iOS 18 `ControlWidget`) bound to `ScanAndSendIntent` with a profile parameter, which the user can also assign to the Action button.
- Lock Screen and Home Screen widgets that deep link into a profile scan.
- `tappony://scan?profile=<id>` for other automation apps, and App Shortcuts phrases ("Scan with TapPony").

Minimum iOS: 18. Control Center controls and mature App Intents need it, and by September 2026 the installed base makes 17 support a cost with no audience. See Q5.

## 11. Android technical notes

- **Reader mode.** `NfcAdapter.enableReaderMode(activity, callback, flags, extras)` while the Scan screen is in the foreground, with `FLAG_READER_NFC_A | NFC_B | NFC_F | NFC_V | FLAG_READER_SKIP_NDEF_CHECK | FLAG_READER_NO_PLATFORM_SOUNDS`, so the app owns the sound and the system does not dispatch NDEF elsewhere. No 60-second limit, no system sheet, so batch mode is just leaving reader mode on. `EXTRA_READER_PRESENCE_CHECK_DELAY` tuned so a tag held on the phone is not re-read in a loop.
- **Identifiers.** `Tag.getId()` for the UID (the IDm for NFC-F; transmission order for NFC-V, which the core reverses into canonical order per 7.3), `getTechList()` for the technology set. `NfcA.getAtqa()` and `getSak()`, `NfcB.getApplicationData()` and `getProtocolInfo()`, `NfcF.getManufacturer()` (PMm) and `getSystemCode()`, `NfcV.getDsfId()` and `getResponseFlags()`, `IsoDep.getHistoricalBytes()` and `getHiLayerResponse()`. `MifareUltralight` and `NfcA.transceive` for `GET_VERSION`, `READ_SIG`, `READ_CNT`; `IsoDep.transceive` for DESFire `GetVersion`; `NfcV.transceive` for Get System Info. `MifareClassic.get(tag)` when present. Android's own reference says implementing `MifareClassic` is optional per device (it depends on the NFC controller), and on devices without it the class never appears in the tech list; the UID still arrives through `NfcA` on those devices, only the sector-level class is missing, which we do not need.
- **NDEF.** `Ndef.get(tag).getNdefMessage()` (or the cached message), `Ndef.writeNdefMessage`, `NdefFormatable.format` for blank tags (Android can format where iOS cannot), `makeReadOnly` for the lock option.
- **Background launch.** `ACTION_NDEF_DISCOVERED` with an `https` App Links filter for `tappony.app/t/` (`android:autoVerify="true"` plus `assetlinks.json` on the domain) launches the app with no chooser for our own launch-link tags, app closed or not. `ACTION_TECH_DISCOVERED` with a tech-list filter would launch on any tag but competes with every other NFC app on the device through the system chooser; it stays a later toggle.
- **Manifest.** `android.permission.NFC`, `INTERNET`, `<uses-feature android:name="android.hardware.nfc" android:required="true"/>` because the app is pointless without it. `POST_NOTIFICATIONS` only if the offline queue reports results through a notification (recommendation: no, report in-app, keep the permission list at two).
- **Network.** OkHttp as the one third-party network dependency (TLS configuration, future pinning and mTLS, sane timeouts), or `HttpURLConnection` if the zero-dependency instinct wins; recommendation OkHttp. Network security config: cleartext permitted in the base config, with the same private-range validator as iOS enforcing that plain HTTP only ever goes to RFC 1918, link-local, ULA, or `.local` destinations. Since Android has no ATS, the app's validator is the only guard, and it is unit-tested.
- **Secrets.** `EncryptedSharedPreferences` is deprecated, so: one AES-GCM key in the Android Keystore wrapping a small encrypted secrets file. Same shape as the iOS Keychain items.
- **Queue.** WorkManager with network constraints for the offline queue; immediate flush on app open.
- **Entry points.** Quick Settings tile ("Scan with <default profile>"), static and pinned launcher shortcuts per profile, a widget, `tappony://scan` deep links. Tasker and MacroDroid broadcasts later.
- **Stack.** Kotlin, Jetpack Compose, Material 3, DataStore, Moshi with KSP codegen only (`@JsonClass(generateAdapter = true)`, no `KotlinJsonAdapterFactory`), coroutines. Two Gradle modules: `:app` and `:core` (pure Kotlin: template engine, escaping, UID normalization, chip tables, HMAC, host policy, profile schema, history model). minSdk 26, matching HashPony. Flavors `foss` and `play`.

## 12. Privacy posture

- No account, no cloud, no sync, no telemetry, no crash reporting, no third-party SDK that phones home. The only outbound traffic is the requests the user configured to the hosts the user typed, plus StoreKit or Play Billing on store builds once a paid unlock exists (none in 1.0). That claim is checkable in the source and with a packet capture, and it goes first in every listing.
- What we never collect or store: hardware identifiers of the phone (no IDFV, no advertising ID, no device name in requests unless the user types a label), location, contacts, photos, anything from other apps. The app has no reason to know where a tag was scanned, so it does not ask.
- Tag reads never leave the device except inside the user's configured request. History stays local, holds identities and outcomes, and holds bodies only per profile opt-in. Clear is one tap, auto-clear is a setting, uninstall removes everything.
- Secrets live in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, excluded from iCloud Keychain and backups; the encrypted export is the migration path) and in the Keystore-wrapped store on Android. They are never written to history, logs, the Test view, or exports unless the user opts in during export with the passphrase.
- Permissions: iOS asks for NFC (system sheet) and, only when a LAN profile exists, local network. Android declares NFC and INTERNET. That is the whole list.
- No update checks, no news feeds, no "rate this app" prompts. Store and F-Droid handle updates.
- The privacy policy page on the site says all of this in plain language, matching hashpony.app's zero-data page in structure.

## 13. Security of the outbound request

### 13.1 Transport

TLS 1.2 or later with the platform defaults for public hosts (ATS on iOS, OkHttp defaults on Android). No arbitrary-loads exception on iOS. Redirects are not followed by default; when a profile enables them, same host and same scheme only, never a downgrade to HTTP. Request timeout 15 seconds by default, per profile. Response bodies capped at 64 KB in memory, 4 KB kept when bodies are on.

### 13.2 Local network policy

Plain HTTP is allowed only for destinations the validator classifies as local: RFC 1918 IPv4, IPv4 link-local, IPv6 ULA and link-local, `.local` names, and unqualified single-label hostnames. It is per-profile opt-in with a warning that names the risk (anyone on the Wi-Fi can read the request, including secrets). A profile that targets a public hostname or public IP over `http://` cannot be saved. On iOS, ATS closes plain HTTP to public hostnames on its own, but `NSAllowsLocalNetworking` reopens IP addresses of any kind, so the validator's private-range rule is what keeps public IPs out there; on Android the validator is the only guard at all. It is therefore a tested component in `:core` and TapPonyKit, not a UI check. Self-signed TLS on LAN hosts gets fingerprint pinning in 1.1 (section 8), which works there because ATS does not govern local connections.

### 13.3 Secrets

Header values and template fragments flagged as secret are stored by reference (`{secret:NAME}`), resolved at send time, and masked everywhere else: editor, Test view, history, exports without the passphrase opt-in, and the Shortcuts return values. Headers are scrubbed of CR and LF before assembly.

### 13.4 Integrity and replay

Optional HMAC-SHA256 signing per profile, free: `X-TapPony-Signature: sha256=<hex>` over `timestamp + "." + body` with a secret from the Keychain, plus `X-TapPony-Timestamp` and `X-TapPony-Nonce`, the same shape GitHub and Stripe webhooks use so receivers already have verification code. `{seq}` gives receivers a cheap ordering and gap check. The docs page ships verification snippets in PHP, Python, and Node-RED. mTLS later.

### 13.5 Hostile tags and hostile servers

- A tag is untrusted input. NDEF content can be anything, including attempts to inject JSON, headers, or URLs. The template engine's context-aware escaping (7.2) is the primary defense; `|raw` is an explicit opt-out with a warning; length caps apply to every variable (NDEF capped at 8 KB by default). Nothing in a tag is ever interpreted as an instruction to the app: no "open this URL" from arbitrary tags, only from TapPony launch links whose token the app minted.
- A server response is also untrusted. The message extraction shows text, never renders HTML, never follows links in it, and the TTS option reads at most 200 characters.
- Launch links carry a random token per tag; a link with an unknown token opens the app on the Scan tab and does nothing else.
- The Test send uses sample values and is labeled so nobody posts a fake scan into a production sheet by accident.

### 13.6 Local history

Identity, profile, outcome, latency, timestamps by default. Bodies per profile opt-in, secrets never. Clear all, clear per profile, auto-clear after N days, CSV export through the share sheet. History is in the app container under the platform's default data protection; it is not a security boundary against someone holding the unlocked phone, and the doc says so rather than promising otherwise.

## 14. Architecture and stack

- **iOS.** Swift 6, SwiftUI, iOS 18 minimum, built with Xcode 26 against the current SDK. Core NFC, App Intents, WidgetKit (widgets and the Control Center control), URLSession. StoreKit 2 only once the unlock ships; not linked in 1.0. Zero third-party dependencies in the app target.
- **TapPonyKit.** A Swift package inside the iOS repo, pure Swift with no UIKit: template engine and escaping, profile schema (Codable, versioned JSON), UID normalization and chip tables, host policy validator, HMAC signing, history model, presets. `swift test` on Linux in the cloud session for everything except CryptoKit, which gets `swift-crypto` behind `#if canImport(CryptoKit)` so the tests run there too. Same arrangement HashPony used with `:core`: the pure part is built and verified in the cloud, the Core NFC and SwiftUI layer is source-only for the Mac.
- **Tag reading abstraction.** A `TagReader` protocol with the Core NFC implementation and a fake that replays recorded tag readings, so the UI, rules, and request pipeline are testable in the iPhone 17 simulator where Core NFC does not exist.
- **Profiles as files.** Profiles are JSON documents in Application Support (secrets by reference), which makes the on-disk format, the export format, and the cross-platform format one thing. History is SwiftData on iOS and Room on Android; it never leaves the device except as CSV.
- **Android.** As in section 11: `:app` and `:core`, Kotlin, Compose, Material 3. `:core` is the JVM twin of TapPonyKit and shares the conformance fixtures.
- **Cross-platform contract.** `PROFILE_SCHEMA.md` in both repos, one schema version number, one set of template semantics, one set of fixtures (`template_vectors.json`, `uid_vectors.json`, `hostpolicy_vectors.json`) checked into both repos and run in both test suites. A profile exported on either platform imports on the other; that is a release-gating test, not a hope.
- **Project layout per standards.** `~/Apps/TapPony` (iOS, no platform suffix, per NorseHorse's convention since Sep 25 2026) and `~/Apps/TapPonyAndroid`, PascalCase, each its own directory. iOS uses XcodeGen (`project.yml`, the .xcodeproj is generated and gitignored) with `TapPonyKit` as a local package under `Packages/`, the ScrubPony pattern. Repo-local git identity `norsehorse-dev` set immediately after `git init`, no AI attribution anywhere, standard gitignore set on Android (local.properties, keystores, .DS_Store, build/, .gradle/, .kotlin/), Xcode user data and any exported certificates gitignored on iOS. This planning file lives in `~/Apps/Ideas/Pony/` and is copied to each repo root as `PLANNING_1_0_0.md`.

## 15. Phase plan and estimate

Estimates are part-time evenings on the iOS build; the ambitious scope makes this bigger than HashPony. A minimum shippable line is marked so scope can be cut without re-planning.

**Phase A: spike and core.** Order a tag sample pack before anything else (NTAG213/215/216 stickers, an ICODE label, a MIFARE Classic fob, a DESFire card). Hardware spike first, one evening: NTAG213/215/216, Ultralight EV1, a MIFARE Classic 1K fob, a DESFire card, an ICODE SLIX label, against the iPhone, recording identifiers and byte order for the fixtures; it settles the Classic question and the ISO 15693 order. Then TapPonyKit (template engine, escaping, schema, normalization, host policy, HMAC) with its test suite in the cloud, the Core NFC reader with the `TagReader` abstraction, the Scan tab, a first profile editor, presets, and the Shortcuts `ReadNFCTagIntent` (moved here from Phase C in Rev 2; the spike already has to prove a foreground intent returns its value to Shortcuts). 9 to 11 evenings. Clean Cowork handoff for everything except the spike and the on-device NFC layer.

**Phase B: identity depth and safety.** Extended reads per family (GET_VERSION, READ_SIG, READ_CNT, DESFire GetVersion, 15693 system info, FeliCa), random-UID detection, Keychain secrets, local-network policy, history with CSV export, the Test view, error copy for every state in 10.3. 5 to 7 evenings. **Minimum shippable is A plus B plus E.**

**Phase C: automation.** `ScanAndSendIntent`, Control Center control and Action button, widgets, URL scheme, rules engine, batch mode, offline queue, response rules with TTS. 7 to 9 evenings. This is the phase where the app pulls away from NFC.cool.

**Phase D: own tags.** Tags tab: write URL, text, launch link, mirror UID, lock; the registry; background launch through Associated Domains with the AASA file on tappony.app; the site itself on the Pony family shell (index, privacy, support, docs with receiver snippets, rc/). 4 to 6 evenings.

**Phase E: release.** Entitlement gate audit (every Plus feature behind `Entitlements.plus`, constant true), the Settings line that everything is free, string freeze and the seven locales, App Store assets and the 4.3(a) positioning pass (section 16), TestFlight to the requesting tester, then the wider pool. No StoreKit work in 1.0. 4 to 6 evenings.

**1.0 = A through E**, roughly 29 to 39 evenings, call it eight to ten weeks of weekday evenings. Cut order if it needs to shrink: D first (background launch and writing move to 1.1), then the TTS and response rules, then batch mode. Never cut B: an NFC app that mishandles byte order or leaks a secret into history is worse than no app.

**Android, in parallel (Rev 2).** Built alongside iOS rather than after it. `:core` is the Kotlin twin of TapPonyKit, written against the same fixtures in the same week, and both cores are built and tested in the cloud session. The Android app follows the same phase letters: core and reader mode (A), identity and safety (B), entry points and queue (C), App Links and writing (D), F-Droid metadata and release (E). The `play` flavor waits until Google Play and the unlock are both in play. Rev 1 estimated Android at 4 to 6 weeks as a follow-on; in parallel it adds roughly that much evening time, so for both 1.0s together budget about 12 to 16 weeks of weekday evenings if TapPony got all of them. Sharing evenings with HashPony and SopsPony stretches that proportionally. The hardware work is where parallel pays: one tag pack and one spike session capture UID vectors for both platforms, and Android confirms the MIFARE Classic badge path while iPhone documents that it cannot.

## 16. Distribution and release engineering

- **iOS.** TestFlight external group for the requesting tester's first build (the first build in a group goes through Beta App Review, usually a day, and it is a lighter check than App Review), the wider pool in the same group later, then App Store 1.0. Submit rather than hold: the app is a webhook and automation utility with a request builder, not an NFC reader, and the listing must say so in the name line, subtitle, first three screenshots, and the review notes. "NFC" belongs in the subtitle for search, never as the noun the app is. Review notes should include a two-minute setup for the reviewer (a public ntfy topic preset works without any server of ours) and a sentence on why the NFC entitlement is used. If 4.3(a) lands anyway, the appeal has the differentiators in section 2 ready, and the Android build keeps moving in parallel so a stall does not stall the project.
- **Android.** GitHub releases on `norsehorse-dev/TapPonyAndroid`, direct APK page on tappony.app, F-Droid main repo through a fdroiddata inclusion MR; direct APK and GitHub releases are the channels until inclusion lands (no IzzyOnDroid). Google Play after F-Droid inclusion, once the closed-testing requirement is met with the volunteer pool; the `play` flavor gets Play Billing only when the unlock turns on, and the `foss` flavor never carries it.
- Reproducible builds from the first tag: one working copy, release builds only from the committed tree, wrapper and AGP pinned, one signing key so direct-APK and F-Droid installs update over each other. Versioning 1.0.0 / versionCode 100, family convention. iOS builds through `xcodebuild` from the CLI like everything else.
- Every shipped Android update gets its section in NorseHorse_Android_Update_Log.md with the iOS counterpart column filled from day one, since here the iOS app exists first.
- RC hosting on tappony.app/rc/ in the pgpony.app pattern, with the APK SHA-256 published beside the file (HashPony can hash it).

## 17. Branding

- Name: TapPony, locked Sep 25, 2026 (sweep result in section 0; USPTO direct search and registrar check still his to run).
- Icon: a horse mark with the NFC-style contact arcs radiating from the nose, drawn in-house in the family style. Family color, decided Sep 25, 2026: signal blue on charcoal (blue is the color every NFC logo and reader uses, so it reads instantly), with a lighter blue for success states; it sits between HashPony silver and VaultPony gold without clashing.
- Domain: register tappony.app now. Unlike HashPony, this app needs a domain for function (universal links and App Links), not just for a landing page. tappony.com only if the registrar price is ordinary.
- Taglines to pick from: "Tap a tag, hit your server." and "Every tag is a webhook." Store listing leads with: works with any tag including badges you cannot rewrite, full request control, no account, open source, and the Shortcuts action.

## 18. Localization

Family set at 1.0: en, de, es, fr, zh-Hans, pt-BR, ru. String freeze at the end of Phase E, machine drafts for UI strings, human review for the security-adjacent copy (local network warning, the free-everything note, hostile-tag explanations) through native readers in the tester pool for ru, zh-Hans, and pt-BR (assignments kept outside the repo). Presets and their explainers are localized too; variable names and the template syntax are not, and the docs say so. Bigger string surface than HashPony because of the error copy in 10.3 and the preset explainers, so budget two evenings inside Phase E rather than one.

## 19. Testing

- TapPonyKit and `:core` unit tests: template engine (every context, every modifier, escaping of hostile NDEF including quotes, braces, CR/LF, null bytes, oversized input), UID normalization vectors per family captured in the Phase A spike, host policy vectors (every private range, `.local`, unqualified names, IPv6 forms, tricky encodings like decimal and octal IPs that must be rejected), HMAC vectors against a reference implementation, profile schema round-trip and forward-compatibility with an unknown field, presets rendering against sample variables.
- Shared conformance fixtures checked into both repos and run on both sides; a fixture change requires both suites green.
- Request pipeline against a local test server: the cloud container runs a tiny receiver for the Kotlin side; the Mac runs one for `xcodebuild test` on the iPhone 17 simulator with the fake `TagReader`. Assert exact bytes on the wire, header scrubbing, redirect refusal, timeout behavior, queue replay order.
- On-device NFC matrix (no simulator support): NTAG213, 215, 216; Ultralight EV1; MIFARE Classic 1K (expected unsupported on iPhone, documented result); DESFire EV1 and EV3, including one in random-ID mode; ICODE SLIX and SLIX2; FeliCa Lite-S if one can be sourced; a Type B card if one turns up; a blank NDEF-formatted tag; an unformatted tag; a locked tag. A sample pack of NTAG stickers, an ICODE label, and a Classic fob costs about the price of the unlock.
- Automation surfaces: Shortcuts returns values from a foreground intent (the Phase A spike), Control Center control fires on a locked phone after unlock, background launch from a written tag on an XS-or-later device, App Links on Android without a chooser.
- Security checks before RC: no secret appears in history, logs, exports without opt-in, or the Shortcuts return value; a hostile NDEF cannot break a JSON body; `http://` to a public host cannot be saved on either platform; a packet capture during a session shows only the configured requests.
- Testers: the requesting tester first, on TestFlight, with the use-case questions answered. Then the Android RC pool from the other family apps (direct APK on tappony.app/rc/) and a second iOS tester. No promo codes needed while everything is free. Same RC pattern as the rest of the family.

## 20. Open questions

Q-numbers restart for this project. Each carries a recommendation that stands as a provisional decision unless overridden; Rev 2 resolutions are marked inline; open items and the tester's answers roll into Rev 3.

1. **Name and domain.** RESOLVED Sep 25: TapPony, .app to register now. Rev 1 text: TapPony, with the full IP sweep (USPTO, App Store, Google Play, F-Droid, web) run once you confirm, and tappony.app registered immediately since universal links need it. Recommendation: confirm TapPony, register the .app now.
2. **Repos and identifiers.** RESOLVED Sep 25: repos `norsehorse-dev/TapPony` (iOS) and `norsehorse-dev/TapPonyAndroid`; iOS bundle id `com.tappony.app` (matches com.agepony.app, com.relaypony.app, com.carrierpony.app); Android package `com.tappony.android` (matches com.hashpony.android).
3. **Submit or hold on iOS.** Recommendation: submit 1.0, positioned as an automation utility per section 16, with the Android build running in parallel as the hedge.
4. **Unlock name and price.** DEFERRED Sep 25: 1.0 ships free with no billing; name and price are decided when the unlock is built. Rev 1 text: "TapPony Plus" at $2.99, single non-consumable. Recommendation: yes. Alternative: $3.99 if the family plan settles on one price for every Pony unlock.
5. **Minimum iOS.** 18 for Control Center controls and App Intents maturity. Recommendation: 18.
6. **Batch mode and offline queue in 1.0.** RESOLVED Sep 25: both in (full 1.0). Rev 1 text: Both are unlock features and the biggest chunk of Phase C. Recommendation: both in, cut batch first if Phase C runs long.
7. **Background launch and writing in 1.0.** RESOLVED Sep 25: both in (full 1.0). Rev 1 text: Phase D, needs the domain. Recommendation: in, and first on the cut list.
8. **FeliCa default system codes.** `12FC`, `88B4`, `0003`, `FE00`, user-editable, wildcard forbidden by Apple. Recommendation: ship that list.
9. **Brand color.** RESOLVED Sep 25: blue. Rev 1 text: Signal blue on charcoal, or teal. Recommendation: blue.
10. **ISO 7816 default.** Off by default; a toggle adds `D2760000850101` and a short public AID list; user-editable. Recommendation: as stated. Note that adding the NDEF AID makes DESFire arrive as an ISO 7816 tag, which the reader handles either way.
11. **Android launch-on-any-tag.** `ACTION_TECH_DISCOVERED` toggle. Recommendation: later, the chooser makes it a poor default.
12. **mTLS and LAN pinning.** Recommendation: 1.1 unless the requesting tester's receiver needs them, in which case they move into Phase B. The use-case questions ask.
13. **History cap.** 1,000 entries or 30 days, whichever comes first, adjustable. Recommendation: yes.
14. **Mirror UID into NDEF.** A write option that copies the tag's own UID into a Text record, so NDEF-only readers and Shortcuts users on other phones can see it. Cheap. Recommendation: yes, Phase D.
15. **Home Assistant `tag_scanned` preset.** Ships if the Phase B test confirms HA registers REST-fired tags in its Tags list; otherwise it ships with a note that the trigger works but the tag must be created by hand. Recommendation: ship either way, with the honest note.
16. **Credit.** RESOLVED Sep 25: "Suggested by a tester" in About and the README. No names in anything public or committed.
17. **Device label default.** Empty, so nothing identifies the phone unless the user types something. Recommendation: empty, with the field explained on first LAN or HA preset use since those receivers usually want it.
18. **Android Classic-badge copy.** Android reads MIFARE Classic UIDs and iPhone does not. Recommendation: the F-Droid and GitHub listings lead with badges and fobs; the App Store listing leads with stickers, labels, and DESFire, and says plainly which badges iPhone cannot read.
19. **iOS minimum with iOS 27 out.** Recommendation: keep 18 (Q5). Nothing in the 1.0 feature list needs a later SDK floor, and 18 keeps older supported iPhones in the audience.
20. **Launch posts.** Recommendation: a short write-up with one Home Assistant recipe and one Shortcuts recipe, posted to the Home Assistant community forum, r/homeassistant, and r/shortcuts on release day, since those are where people ask for tag UIDs on iPhone.
