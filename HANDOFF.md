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

1. Run the three commands above and fix whatever the first real compile finds.
2. Hardware spike, one evening, both phones: NTAG213/215/216, Ultralight EV1, a MIFARE Classic 1K fob, DESFire EV1 and EV3 (one in random-ID mode), ICODE SLIX. For each tag, record UID bytes and order on both platforms and append them to `fixtures/uid_vectors.json` under `hardware`.
3. Confirm the Read NFC Tag action returns its value to a running shortcut (the plan's Phase A check).
4. Then Phase B: history (SwiftData / Room), the Test view polish, response message extraction, and error copy for every read state.
