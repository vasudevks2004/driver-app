# HireD on iPhone

The iOS app uses the existing Flutter driver screens and API contracts: onboarding,
Home, Duties, Earnings, Profile, availability, private documents, duty selfies and
foreground assignment updates. The bundle identifier is `com.hired.hiredDriver`.
The minimum deployment target is iOS 13; the selected Flutter plugins may require
a newer OS after dependency upgrades. Use the committed lockfile.

## Run on a Mac

Install Xcode with its iOS platform, CocoaPods and Flutter 3.35.7. From this repo:

```sh
python3 scripts/check_ios.py
flutter pub get
open -a Simulator
flutter devices
flutter run -d YOUR_IPHONE_SIMULATOR_ID -t lib/main_dev.dart
```

The preview shows its local test phone/code and cannot create accounts or send
SMS. A simulator cannot validate the real camera. For the connected production
backend, omit `-t lib/main_dev.dart` and pass
`--dart-define-from-file=config/auth.json`. Use only approved test identities.
For staging, create a separate local JSON with the staging gateway API_URL,
staging SUPABASE_URL and its publishable key; do not mix staging and production.
Do not place privileged keys in either mobile configuration.

## Physical iPhone and TestFlight

1. Open `ios/Runner.xcworkspace` after `flutter pub get` and `cd ios && pod install`.
2. Select Runner, your Apple development team and the connected iPhone. Verify
   `com.hired.hiredDriver` belongs to that team. Keychain access is committed for
   Debug, Profile and Release so persisted sessions and queued operations use
   the app's Keychain group.
3. Run on the phone. Verify login, restart/session restoration, logout, permission
   denial and retry, camera selfie, document selection, assignment refresh after
   background/resume, duty completion and wallet reads against staging.
4. For distribution, configure the owner's distribution signing and run:

```sh
flutter build ipa --release --dart-define-from-file=/absolute/path/to/staging.json
```

Upload the signed archive through Xcode Organizer/App Store Connect. The iOS
simulator artifact from Actions cannot be installed on a physical iPhone.
Do not describe simulator CI as a signed device or TestFlight release.

## Optional Google login

Google login requires both backend provider enablement and real web/iOS OAuth
client IDs. The iOS client must be registered for this exact bundle identifier.
Set `GOOGLE_IOS_CLIENT_ID` and `GOOGLE_WEB_CLIENT_ID` in the chosen local build JSON.
Add the actual reversed iOS client ID under `CFBundleURLTypes` / `CFBundleURLSchemes`
in Runner's Info.plist before enabling that method. No invented identifiers are
committed. Verify App Store login requirements before submission.

## Validation and release boundary

The iOS Actions workflow validates native configuration, builds the backend app,
saves a simulator artifact and runs the existing native preview smoke test on an
iPhone simulator. Check the workflow result for the exact commit before using
its artifact. Authenticated staging and physical-device acceptance remain
separate from preview smoke tests. Review privacy disclosures, account deletion,
SDK privacy manifests and App Store metadata before submission.

Backend discovery on 28 October 2026 confirmed both production and staging
Cloudflare Pages projects and Supabase projects exist. This change does not
migrate or deploy either backend. Existing Postman collections cover public
connection checks and staging booking-to-wallet flows; their existence does not
establish a successful authenticated iOS run.
