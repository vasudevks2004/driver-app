# HireD Driver

Flutter app for Android and iOS. HireD supplies drivers; businesses supply vehicles. The minimal HireD interface retains Home, Duties, Earnings and Profile.

This reliability release is on `feature/driver-onboarding`. Its shared backend must be reviewed and deployed with [UniT7 PR #12](https://github.com/Buildathon-HireD-Brototype-2026/UniT7/pull/12). Pulling the app branch does not update the deployed API.

## Run

Use Flutter 3.35.7 (Dart 3.9 or newer) and JDK 17 for the checked Android setup. Create missing native folders in a separate temporary project, then configure them without overwriting app source:

```bash
flutter pub get
flutter create --platforms=android,ios --project-name hired_driver --org com.hired /path/to/hired-native
python scripts/prepare-native.py /path/to/hired-native
flutter devices
flutter run -d YOUR_DEVICE_ID --dart-define-from-file=config/auth.json
```

[Windows setup, emulator troubleshooting and validation](docs/reliability.md) include exact PowerShell commands. Keep the checkout outside OneDrive to avoid cache/file-lock interference. iOS builds require macOS/Xcode; distribution signing requires the owner's Apple credentials.

For the explicit in-memory preview:

```bash
flutter run -t lib/main_dev.dart -d YOUR_DEVICE_ID
```

Use the number/code shown in its permanent LOCAL TEST banner. It sends no SMS, uploads no documents and creates no real accounts. Production sign-in uses verified backend membership.

## Implemented behavior

- Raw private uploads, supported type/size checks, durable retry keys and receipt reconciliation.
- Server-controlled wallet balances and signed earnings, settlements and reversals.
- Six-digit partner completion, current-assignment selfie before Start duty, expenses or explicit No expenses, with persisted state.
- Resumable registration details, PAN/PCC/licence/Aadhaar photo collection, masked Aadhaar entry and review, and explicit review/correction/approval states.
- Directions, authorised partner contact, private realtime assignment updates with foreground polling fallback, reconnect refresh, bounded pages and lazy history lists.
- Honest loading, unavailable, stale and error states; failed reads do not become zero balances or empty duties.

## Verification boundary

CI runs Flutter analysis/tests, Android debug build and native preview smoke checks. A separate macOS workflow builds the iOS simulator app. Full API/SQL/security/financial tests live in the private shared repository. The public client uses a small HTTP stand-in only for transport/retry tests.

Phone and Google were disabled in the connected project's settings on 25 October 2026. DigiLocker requester credentials are unavailable. Provider configuration and a recorded authenticated hosted journey are required before live delivery/verification can be claimed. Fixed codes exist only in test/explicit preview code. Document upload does not establish government verification.

The new shared backend owns encryption, trusted approval, audited document access, deletion queues and retention. The legacy server copies in this repository are retained for history; [do not deploy them for this release](supabase/README.md). Never place service-role, bridge, SMS or DigiLocker secrets in mobile configuration.

## Assignment updates

The reviewed backend migration publishes empty invalidation hints on a private channel bound to the approved driver’s native Supabase Auth identity. The client re-reads authorised duty data on a hint and on reconnect; it never trusts a message as a new assignment. Backgrounding closes the channel, and foreground resume reconnects and refreshes. A delayed connection is shown explicitly and foreground polling remains as recovery. Apply the shared private-channel migration and verify the intended staging project’s Realtime private-channel settings before claiming live immediate assignment delivery. The app uses only its publishable project key and current user token.

The committed dependency lock is the resolution exercised by the 25 October 2026 CI run (53 Flutter tests, Android debug build/emulator preview and iOS simulator build). Release-device and authenticated staging journeys are separate acceptance checks.
