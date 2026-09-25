# TapPony (iOS)

Scan an NFC tag and the phone sends an HTTP request you designed to a server you chose. The request can carry the tag's UID, chip details and NDEF content. No account, no cloud, no telemetry.

**Status:** 1.0.0 in development, Phase A (reader, request engine, Scan tab, profiles, Read NFC Tag Shortcuts action).

## Layout

- `App/` SwiftUI app: Core NFC reader, Scan / Profiles / Settings tabs, Shortcuts intent
- `Packages/TapPonyKit/` the platform-neutral core: template engine, host policy, UID and NDEF handling, request assembly, profile codec, presets
- `fixtures/` shared conformance vectors, identical in the Android repo and run by both test suites
- `PROFILE_SCHEMA.md` the cross-platform contract for profiles and templates
- `tools/fixtures/` the Python reference implementation that generates `fixtures/`

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The `.xcodeproj` is generated and not committed.

```
cd Packages/TapPonyKit && swift test
cd ../.. && xcodegen generate
xcodebuild -scheme TapPony -destination 'platform=iOS Simulator,name=iPhone 17' build
```

The simulator uses a fake tag reader; real reads need an iPhone 7 or later.

## Privacy

The only network traffic is the requests you configure, to the hosts you type. Plain HTTP only ever goes to local network addresses, and only when a profile opts in. Secrets live in the Keychain, this device only, and never appear in profiles or exports.

## License

Apache-2.0. See `LICENSE`.
