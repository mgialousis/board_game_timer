# Android downloads and releases

## Install without Flutter

1. Open the [latest release](https://github.com/mgialousis/board_game_timer/releases/latest) on an Android phone.
2. Download `turntimer-android.apk` from **Assets**. The source-code ZIP is not the app.
3. Open the APK. If Android requests it, allow your browser or file manager to
   install apps from this source. You can turn that permission off afterward.
4. Launch **TurnTimer** and follow the [two-minute walkthrough](WALKTHROUGH.md).

The APK requires Android 7.0 or newer (API 24+) and is a universal release-mode
build for ARMv7, ARM64, and x86_64.
It is signed with this project's private release key, not the Android debug key.
It is distributed directly on GitHub, not through Google Play; managed devices
may prohibit sideloading. No Flutter SDK, account, or backend is needed to try it.

Bundled content and local storage let the app run offline.

If you installed an older development APK, its signing key may differ. Android
will not update it with this APK. Use a separate device/profile, or uninstall
the old app first **only if you are willing to lose its locally stored data**.
Future GitHub updates must retain the same application ID and signing key.

## Verify a download

Each release includes `SHA256SUMS.txt`. From the download directory:

```bash
# macOS
shasum -a 256 -c SHA256SUMS.txt
# Linux
sha256sum -c SHA256SUMS.txt
```

A checksum detects a damaged or changed download; it is not an independent proof
of publisher identity. Release notes also record the signing certificate's
SHA-256 fingerprint. With Android SDK Build Tools installed, inspect it using:

```bash
apksigner verify --verbose --print-certs turntimer-android.apk
```

## Maintainer: private signing setup

Use Flutter **3.38.8** (Dart **3.10.7**), Java 17, and the Android SDK.
The committed `pubspec.lock` records dependency versions.

Generate a key once, using interactive password prompts (do not put passwords
in shell history):

```bash
keytool -genkeypair -v -keystore android/upload-keystore.jks \
  -storetype PKCS12 -keyalg RSA -keysize 3072 -validity 10000 -alias upload
```

Copy `android/key.properties.example` to `android/key.properties` and set the
passwords, alias, and absolute keystore path. Both the real properties file and
`*.jks` / `*.keystore` files are ignored by Git. Restrict file access to the
owner and back up the key and passwords securely outside the repository.
Never upload them as release assets or commit them, even to a private branch.

**Reuse the existing release key for updates.** Losing it means existing users
cannot install an in-place update. Without `key.properties`, Gradle can build
an unsigned artifact for verification, but it must not be published.
Debug builds continue to work without private signing configuration.

## Maintainer: build and publish

1. Increment both the version name and build number in `pubspec.yaml`.
2. Run the quality checks and build:
   ```bash
   flutter pub get --enforce-lockfile
   flutter analyze
   flutter test --exclude-tags golden
   flutter build apk --release
   ```
3. Verify the signature with `apksigner`, inspect the APK for accidentally
   bundled secrets, and install/launch it on Android. The output is
   `build/app/outputs/flutter-apk/app-release.apk`.
4. Commit the release source and documentation. Create a new version tag on that
   exact commit; do not move an existing tag.
5. Copy the verified APK to `turntimer-android.apk` in a staging directory
   outside Git and generate `SHA256SUMS.txt` there:
   ```bash
   shasum -a 256 turntimer-android.apk > SHA256SUMS.txt
   ```
6. Publish a GitHub release for that tag with the APK and checksum file. Include
   the version/build number, source commit, signing fingerprint, installation
   instructions, test results, and known limitations.
7. Download the published assets, compare their checksums, and check the README
   download link.

Only upload the APK and public verification files—not an entire build directory.
The tagged source is provided under AGPL-3.0-only; dependency licenses remain
applicable. A build signed with someone else's key will not replace this APK.
