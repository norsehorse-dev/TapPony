# tappony.app well-known files

Both files are served from `https://tappony.app/.well-known/` with no redirects.

- `apple-app-site-association`: no file extension, served as `application/json`. It lets iPhones open `https://tappony.app/t/...` launch links in TapPony, including from background tag reading.
- `assetlinks.json`: verifies the Android App Links for the same path. Replace `RELEASE_SIGNING_CERT_SHA256` with the SHA-256 fingerprint of the key that signs the release APK, in colon-separated uppercase hex as `keytool -list -v` prints it. To test App Links on debug builds, add a second entry for the package `com.tappony.android.debug` with the debug key's fingerprint.

The rest of the site (index, privacy, support, receiver docs) is built on the Pony family shell and lands here in a later step.
