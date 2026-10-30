# Driver app 1.0.2 (3) alignment

The mobile version is declared once as `version: 1.0.2+3` in `pubspec.yaml`.
Android uses Flutter's versionCode/versionName, and iOS uses the generated
FLUTTER_BUILD_NAME/FLUTTER_BUILD_NUMBER settings. CI reads these defaults instead
of supplying a different hardcoded version. A version label is not proof of the
source, backend deployment or successful user acceptance.

This review combines the existing Android staging build and launcher work with
the existing iOS parity/Keychain-signing work. It preserves the HireD logo,
Home/Duties/Earnings/Profile navigation, current app behavior, dependency lock,
native platform identity defaults and both parents' history. The hosted-client
contract test remains opt-in and requires private synthetic test credentials;
CI runs no customer, notification or financial workflow automatically.

## Pick the environment explicitly

For an Android test build, from the Flutter project directory:

```powershell
python scripts/check_driver_release.py
$env:ORG_GRADLE_PROJECT_hiredApplicationId = 'com.hired.hired_driver.staging'
$env:ORG_GRADLE_PROJECT_hiredAppName = 'HireD Test'
flutter pub get
flutter build apk --debug --dart-define-from-file=config/staging.json
```

For a local run, select your emulator with `flutter devices`, then use
`flutter run -d YOUR_DEVICE_ID --dart-define-from-file=config/staging.json` with
the same two environment variables. The package and app name let the test
client coexist with production. Do not reuse those environment variables for
an authorized production build. Keep production `config/auth.json` separate;
neither a sync nor a version bump deploys or changes the backend.

In UniT7, run these commands inside `driver-app/`. In the standalone checkout,
run them at the repository root. The source synchronization record in the shared
project identifies the reviewed upstream commit and copied file hashes.

## Verification and release boundary

- `scripts/check_driver_release.py` validates the version mapping, public client
  fields, HTTPS addresses and separate staging/production hosts without network
  access. `--field name`, `--field build` and `--field version` expose only the
  non-secret version for build verification.
- Existing format/analyzer/Flutter tests, Android staging build and native
  emulator preview checks remain required. The iOS checker preserves required
  permission messages, Keychain entitlements and HTTPS enforcement; the iOS
  simulator build and preview are separate from signed iPhone installation.
- Every artifact upload is an explicit workflow-dispatch choice, default false.
  No plan, paid runner, provider, credentials or production data changes are part
  of this review. A build or emulator preview is not a hosted phone/UI pass.
- Existing APK files are immutable evidence of their recorded source. Do not
  rename an older binary to suggest that it contains newer code. Future changes
  after this candidate require a new build number for actual distribution, with
  controlled signing. Keep older app/repository history for rollback.

Original PRD email/maps/provider and hands-on acceptance gates are not resolved
by this source synchronization. Review and approve the matching app/backend
release before any production rollout or protected-branch merge.
