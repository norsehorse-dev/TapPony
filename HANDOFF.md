# TapPony handoff: Phase A start (Sep 25, 2026)

Both repos were scaffolded in one session: `~/Apps/TapPony` (iOS) and `~/Apps/TapPonyAndroid`. This file is identical in both.

## What exists

**Shared contract**
- `PROFILE_SCHEMA.md`: profile document, template syntax, modifiers, escaping contexts, host policy, UID canonical order, request assembly, NDEF and variable rules.
- `fixtures/`: 79 template vectors, 60 host-policy vectors and 8 URL-template vectors, 11 UID and 14 chip vectors, 5 signing vectors, 14 variable-builder vectors, 20 request-assembly vectors.
- `tools/fixtures/`: the Python reference implementation and generator. Every vector has a hand-checked expectation, so a reference bug can't silently become the contract.

**Cores**
- Android `:core` (pure Kotlin/JVM): compiled and tested in the cloud session. All 10 conformance tests pass, and they fail when a fixture is deliberately broken.
- iOS `TapPonyKit`: a line-for-line port of `:core`. No Swift toolchain was reachable from the session, so it is source-only. It had two independent read-through reviews against the Kotlin, with fixes applied. `swift test` on the Mac is its first real compile.
- Both cores write profiles byte-for-byte identically. A pinned literal in each test suite checks this.

**Apps (source-only, first compile on the Mac)**
- iOS: XcodeGen project, Core NFC reader with extended reads (GET_VERSION, READ_SIG, READ_CNT, DESFire GetVersion, ISO 15693 system info, FeliCa PMm), NDEF read, and a fake reader for the simulator. Also URLSession sender with the same-host redirect policy, Keychain secrets, profile files, Scan / Profiles / Settings tabs, profile editor with validation and Test send, preset picker, and the **Read NFC Tag** Shortcuts action returning a TagReading entity.
- Android: Gradle project (AGP 8.13.2, Kotlin 2.1.0, compileSdk 36, minSdk 26), reader mode on the Scan screen with a 2 s same-UID dedupe, and a tag reader with the same extended reads. Also OkHttp sender with the same redirect policy, Keystore-wrapped secrets, profile files, and Scan / Profiles / Settings screens with the editor, validation, Test send and presets. Strings are in resources.
- Everything is free, and there is no billing code. Plus features will sit behind one gate when they arrive (planning doc, section 9).

## Build and test

```
cd ~/Apps/TapPony/Packages/TapPonyKit && swift test
cd ~/Apps/TapPony && xcodegen generate && xcodebuild -scheme TapPony -destination 'platform=iOS Simulator,name=iPhone 17' build
cd ~/Apps/TapPonyAndroid && ./gradlew :core:test :app:assembleDebug
```

## Known decisions and open risks

- **iOS ISO 7816 AID list** includes `D2760000850101` because a session polling ISO 14443 without that key is commonly refused with "Missing required entitlement". As a result, DESFire and other Type 4 tags carrying an NDEF app arrive as ISO 7816 tags (tag type `iso7816`), not `mifare_desfire`. The spike should confirm both the entitlement behavior and what a DESFire card reports.
- **iOS read order**: NDEF is read before the MIFARE extended commands. An NTAG answers READ_CNT with a NAK when its counter is off, which drops it to idle and would lose the NDEF read.
- **iOS editor lists** use index-based bindings. Deleting the last header or field while its text field is focused can crash on some iOS versions; test it on device and switch to identifiable rows if it does.
- **Android header values** must be ASCII (OkHttp rule). A non-ASCII device label in a header fails the send with a clear message rather than crashing.
- **Deprecations to expect on the iOS 26 SDK**: `openAppWhenRun` and `.tabItem` may warn. They are warnings only.

## Next: Phase A remainder

1. Done Sep 25, 2026: `swift test`, the iOS simulator build, `:core:test` and `:app:assembleDebug` all pass on the Mac (after two setup fixes: the iOS 18 platform declaration in Package.swift and a local `local.properties` for the SDK path).
2. Hardware spike, one evening, both phones: NTAG213/215/216, Ultralight EV1, a MIFARE Classic 1K fob, DESFire EV1 and EV3 (one in random-ID mode), ICODE SLIX. For each tag, record UID bytes and order on both platforms and append them to `fixtures/uid_vectors.json` under `hardware`.
3. Confirm the Read NFC Tag action returns its value to a running shortcut (the plan's Phase A check).
4. Then Phase B: history (SwiftData / Room), the Test view polish, response message extraction, and error copy for every read state.

## Phase B progress (Sep 25, 2026, Android first while tags are in the mail)

- **Both cores:** response message extraction (`after.messageField`, PROFILE_SCHEMA.md section 11) and history CSV export (section 12), with new fixtures `message_vectors.json` (23 cases) and `history_csv_vectors.json`. Kotlin: 12 of 12 conformance tests green in the cloud. Swift: twins written; run `swift test` to confirm.
- **Android:** Room history (bodies kept only when the profile opts in, secrets masked, secrets echoed by a server masked too), History tab with All / OK / Failed filters, detail view, Export CSV through the share sheet, Clear. Retention in Settings: 7, 30 (default), 90, 365 days, or until the 1,000-scan cap. The server message shows on the Scan result, and the editor has an "After sending" section (Show from the reply, Keep bodies).
- **iOS app:** not yet wired to history or the server message. That comes after the NTAG215 stickers confirm iPhone reads.
- **Known difference:** non-integer JSON numbers in a server message can print differently on each platform (Kotlin `1.5E-5`, Swift `1.5e-05`). The spec allows platform shortest form; integers and simple decimals match.

## Phase C part 1 (Sep 25, 2026, Android)

- **Offline queue:** per-profile "Save and send later when offline" (`after.queueOffline`, spec section 13, in both cores). Only transport failures queue (no connection, DNS, timeout), never bad URLs or build errors. The queue stores variables, not rendered requests, so secrets never reach it. WorkManager flushes it oldest first when a network is back, and also on app start and from "Send now" on the Scan screen. Items older than 24 hours are dropped into history as `network_error`. Room is now at DB version 2, with a real migration, so existing history survives.
- **Batch mode:** a Batch chip on the Scan screen gives a running count and a per-tag result list. "Each tag once per batch" is in Settings, on by default. Sounds and a vibration on every read follow the profile's sound and haptic switches.
- **Entry points:** a `tappony://scan?profile=<id>` link for other apps, launcher long-press shortcuts for up to four profiles, "Add to home screen" in the editor, and a Quick Settings tile that opens TapPony on the Scan tab. Android only reads tags with an app in the foreground, so these save taps rather than scanning in the background.
- **Design calls:** a live scan with a connection is sent immediately even while older scans wait in the queue, so a receiver can get them out of order. Use `{timestamp}` and `{seq}` to reorder.
- **Next in Phase C:** the rules engine (tag-to-profile routing, a new cross-platform spec and fixtures) and response rules with spoken confirmation.

## Phase C part 2 (Sep 25, 2026, Android)

- **Rules engine:** spec section 14, both cores, `rules_vectors.json` (12 routing cases, validation, and a pinned encoding). Rules match on UID (separator- and case-insensitive), tag type, chip, maker, content, NDEF text, or NDEF link, using is, starts with, contains, or a pattern. The first match wins and fans out to every profile it lists. With no match, the scan goes to the Scan-screen profile or nowhere, as chosen. Android keeps rules in `rules.json` and edits them on a Rules screen reached from Profiles, with reordering and "Use last scanned tag".
- **Result text and speech:** spec section 15, `after.successText`, `after.failureText` and `after.speak` in both cores, `result_text_vectors.json`. Android shows the text large on the result card and speaks the result with the phone's own text-to-speech.
- **Kotlin core:** 14 of 14 conformance tests green in the cloud. Swift twins written; `swift test` still to run.
- **Still open for Phase C:** the iOS side of all of Phase B and C (history, reply message, queue, rules, speech, Shortcuts "Scan and Send", Control Center), after the stickers confirm iPhone reads.

