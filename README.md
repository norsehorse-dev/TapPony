# TapPony (iOS)

Scan an NFC tag and the phone sends an HTTP request you designed to a server you chose. The request can carry the tag's UID, chip details and NDEF content. No account, no cloud, no telemetry.

**Status:** 1.0.0 in beta on TestFlight. Website and receiver docs: [tappony.app](https://tappony.app). Android app: [TapPonyAndroid](https://github.com/norsehorse-dev/TapPonyAndroid).

## Features

- Reads the tag's own identity, not just NDEF: UID in canonical byte order, chip model, NXP originality signature and scan counter where the chip has them. Works with tags you didn't write.
- A full request builder: method, URL, headers, JSON, form or raw body built from templates like `{uid}` and `{payload}`, bearer, basic or API key auth, optional HMAC-SHA256 signing.
- Rules that route each tag to one or more profiles, batch mode, an offline queue, and the server's reply shown or spoken after each tap.
- Tag writing: links, text, the tag's own UID, and TapPony launch links that open the app and send even when it's closed.
- Shortcuts actions (Read NFC Tag, Scan and Send), a Control Center control and Home and Lock Screen widgets.
- English, German, Spanish, French, Brazilian Portuguese, Russian and Simplified Chinese.

## Layout

- `App/` SwiftUI app: Core NFC reader and writer, Scan / Profiles / Tags / History / Settings tabs, Shortcuts actions, string catalogs
- `Widgets/` WidgetKit extension: Control Center control and Home and Lock Screen widgets
- `Packages/TapPonyKit/` the platform-neutral core: template engine, host policy, UID and NDEF handling, request assembly, profile codec, presets
- `fixtures/` shared conformance vectors, identical in the Android repo and run by both test suites
- `PROFILE_SCHEMA.md` the cross-platform contract for profiles and templates
- `tools/fixtures/` the Python reference implementation that generates `fixtures/`
- `site/` templates for the files tappony.app serves for universal links

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
