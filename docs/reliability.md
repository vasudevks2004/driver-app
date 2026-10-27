# Running and reviewing HireD Driver

Use this PR's `feature/driver-onboarding` branch; `main` remains unchanged until review/merge. Backend companion: https://github.com/Buildathon-HireD-Brototype-2026/UniT7/pull/12 . The new client needs that shared contract deployed to the API configured in config/auth.json. Pulling this Flutter branch alone does not update Cloudflare or Supabase.

## Windows Android

Keep the checkout outside OneDrive to reduce sync/file-lock interference:

```powershell
cd $env:USERPROFILE
mkdir source -ErrorAction SilentlyContinue
cd source
git clone --branch feature/driver-onboarding https://github.com/vasudevks2004/driver-app.git HireD_Driver
cd HireD_Driver
flutter doctor -v
flutter pub get
flutter emulators
flutter emulators --launch YOUR_AVD_ID
flutter devices
flutter run -d YOUR_DEVICE_ID --dart-define-from-file=config/auth.json
```

Use the ID actually listed by `flutter devices`; emulator-5554 is not guaranteed. Do not repeatedly clean/pull while Gradle is downloading dependencies. The first native build downloads SDK/Gradle artifacts and is slower than hot reload. If the specific Kotlin incremental-cache close error returns, stop Gradle (`cd android; .\gradlew --stop; cd ..`), remove only the generated build folder, then rebuild outside OneDrive. Android and iOS projects are committed; do not regenerate or replace them when running the app.

The committed projects include Internet/camera permission, iOS camera/photo descriptions and HireD icons. Google native URL scheme/signing configuration remains provider-specific and must be completed with the actual client IDs. See native-release.md for app IDs and signing. Do not put a service role key, SMS key, bridge key or DigiLocker secret in Dart/config/auth.json. Its existing publishable key is a public client configuration, not privileged backend authorization.

For explicit in-memory preview only: `flutter run -t lib/main_dev.dart -d YOUR_DEVICE_ID`. The visible LOCAL TEST banner contains the synthetic number/code. Preview creates no real identity, uploads no documents and grants no real driver access. Fixed codes are absent from production main.dart's imports.

## Validation

Run `flutter analyze`, `flutter test`, and the existing onboarding HTTP/service checks under Node 24. The Flutter transport tests use a small public HTTP stand-in to check encoding and retry behavior. Full contract tests against the actual Worker, Edge handler and PostgreSQL rules live only in the private shared repository, with explicit Auth/Storage stand-ins. They must pass together; the public stand-in is not financial or backend authorization evidence.

Android debug build runs in CI. iOS simulator builds use a separate macOS workflow. A successful build is not evidence of camera permission behavior, background/resume reliability, OTP delivery or Google/DigiLocker verification. Do not call this release production-ready until the hosted staging journey and device checks are recorded.

## Behavior

Four tabs and HireD branding remain. Failed initial earnings/duty reads remain unavailable, with retry. Failed later reads preserve confirmed data with a stale/error notice. Histories request 25 records per page and render lazily. Foreground assignment checks run every 60 seconds and on app resume; background push delivery is not configured.

Non-GET requests persist an account-scoped fingerprint and UUID retry key in secure storage until confirmed or definitively rejected. The same unresolved action survives restart and auth refresh. Upload keys also bind file bytes, filename and expiry. No request bodies, Aadhaar numbers or partner codes are persisted in that retry store. Server locks, receipts and financial constraints provide the authority; a spinning button alone is not duplicate protection.

Phone and Google providers were disabled when inspected. The UI reports provider availability and disables unavailable methods. Registration needs verified phone access. DigiLocker is unavailable until requester credentials and callback endpoints are configured. Upload/format validation never means UIDAI/government verification.

Registration drafts resume from the protected server record. Full Aadhaar entry is masked, excluded from drafts and review responses, and encrypted by a database BEFORE trigger during submission. Review outcomes/corrections are explicit. Only trusted admin approval can activate the verified Auth identity. Applicant deletion removes database details and queues private object deletion; verify the hosted retention schedule is running. Approved-account closure and financial retention need an agreed operations policy, not deletion of immutable payroll history.
