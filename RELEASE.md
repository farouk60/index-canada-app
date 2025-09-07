# Release Guide (Android & iOS)

This document walks you through building, signing, and submitting the app to Google Play and Apple App Store.

## 1) Versioning
- Update version in `pubspec.yaml` (done): `version: 1.0.1+2`.

## 2) Android (Google Play)

### 2.1 Prerequisites
- Create a Google Play Console app (if not already).
- Recommended: Enable Play App Signing.

### 2.2 Keystore (Upload key)
If you do not have an upload keystore:
1. Generate a keystore (on any OS):
   - Windows (PowerShell):
     - `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
   - Remember keystore path, alias and passwords.
2. Place the keystore under `android/` (e.g., `android/upload-keystore.jks`).
3. Create `android/key.properties` with:
   ```
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=upload
   storeFile=../upload-keystore.jks
   ```
4. Wire in `android/app/build.gradle(.kts)` signingConfigs.release -> buildTypes.release.

If you use Google Play App Signing, this upload key signs only the upload; Google manages the install key.

### 2.3 Build
- From project root (Windows CMD):
  - `cd mon_index_app`
  - `flutter clean`
  - `flutter pub get`
  - `flutter build appbundle --release`
- Output: `build/app/outputs/bundle/release/app-release.aab`

### 2.4 Play Console
- Create app listing: icon (512×512), feature graphic (1024×500), screenshots.
- Data Safety: declare analytics, network, location, photos/camera usage.
- Content Rating questionnaire.
- Upload the `.aab` to Internal testing first; test; then promote to Production.

## 3) iOS (App Store)

### 3.1 Prerequisites
- Apple Developer Program account.
- A Mac with Xcode 15+, and configured signing team.

### 3.2 App IDs & Signing
- Open `ios/Runner.xcworkspace` in Xcode.
- In `Runner` target > Signing & Capabilities:
  - Set Team.
  - Ensure unique Bundle Identifier.
  - Select `Release` configuration for `Any iOS Device (arm64)`.

### 3.3 Privacy & Permissions (already configured)
- `ios/Runner/Info.plist` includes keys for Camera, Photo Library (view & add), and Location (WhenInUse only).
- `ios/Runner/PrivacyInfo.xcprivacy` present with `NSPrivacyTracking=false`. If you use SDKs that require a privacy manifest, include theirs too.

### 3.4 Archive & Upload
- In Xcode: Product > Archive, then Distribute (App Store), sign, and upload.
- Alternatively: `flutter build ipa --release` (on macOS) and upload via Xcode Organizer/Transporter.

### 3.5 App Store Connect
- Fill in App information, pricing, App Privacy (data collection), and screenshots for required devices.
- Submit for review.

## 4) Store Policy Notes
- Android Manifest:
  - Removed `QUERY_ALL_PACKAGES` (Play policy compliance).
  - Added `INTERNET` and `ACCESS_NETWORK_STATE` (network).
- iOS Info.plist:
  - Only `NSLocationWhenInUseUsageDescription` (no Always), plus Photo/Camera usage.

## 5) Troubleshooting
- No AAB output: verify Flutter/Android SDK installed and `flutter build appbundle` logs. Check Gradle errors; ensure JDK 17 is used.
- Signing errors: ensure `key.properties` present and referenced by `build.gradle(.kts)`; passwords correct.
- iOS signing: verify Team, certificates, and provisioning profiles.

## 6) Post-Release
- Enable Crash reporting (e.g., Firebase Crashlytics) and ANR monitoring.
- Fill release notes; use staged rollout.
- Monitor KPIs and user feedback; iterate.
