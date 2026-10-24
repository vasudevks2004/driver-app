# HireD Driver

Flutter driver app for Android and iOS. HireD supplies drivers; the business or customer supplies the vehicle.

## Sign in and registration

- **Google:** native Google account chooser, Supabase token exchange, then HireD driver-profile verification.
- **Mobile number:** SMS OTP, code verification, resend countdown and change-number controls. Login does not create an account.
- **Register as a new driver:** full name, mobile number and city; verify the number, then add licence number, date of birth, expiry, vehicle class, front/back photos and a camera selfie for the driver avatar. Submit the application for HireD review. No password is required for phone accounts.
- **Email:** existing administrator-issued email/password login remains available.
- **DigiLocker:** consent-based, server-side OAuth with PKCE and a single-use callback. An issued licence can replace manual licence photos. Live use requires approved requester credentials; missing configuration keeps photo upload available.
- Sessions are stored securely only after the backend confirms a driver profile. New or unlinked identities see activation instructions before dashboard access.

## Run

Use Flutter 3.29+ / Dart 3.7+. The checks use Flutter 3.35.7.

```bash
# Run once if android/ and ios/ have not been generated on your machine.
flutter create . --platforms=android,ios --project-name=hired_driver --org=com.hired
flutter pub get
flutter run --dart-define-from-file=config/auth.json
```

`config/auth.json` contains the existing HireD API URL and the project's **public** Supabase configuration. Add your Google OAuth client IDs there, or supply a different config file. Never put service-role keys, Google client secrets, SMS credentials or signing keys in mobile configuration.

To inspect the sample dashboard without connecting to real accounts:

```bash
flutter run --dart-define=ALLOW_DEMO=true
```

Select **Explore demo** on the login screen. Sample duty `TRP-1028` can be started, a selfie captured, expenses logged, and closed with duty demo OTP `4826`. This code is only for the sample duty, never for authentication. Demo changes remain in memory.

See [docs/DRIVER_ONBOARDING.md](docs/DRIVER_ONBOARDING.md) for private document storage, the onboarding service, DigiLocker credentials, and reviewer handoff. The HireD wordmark uses a transparent cropped SVG through one shared component.

## Free local OTP preview

```bash
flutter run -t lib/main_dev.dart
```

Use **+91 9876543210** and test code **123456** to try login and driver registration. This debug-only preview uses local in-memory data and sends no SMS or documents. The yellow banner stays visible; existing production accounts/sessions are not accessed. A restart resets preview data.

For real Indian SMS, the MSG91 delivery hook is implemented; activation requires your MSG91 key, approved Flow template and Supabase signing secret. See [docs/SMS_SETUP.md](docs/SMS_SETUP.md) for setup and exact readiness limits.

## Provider setup still required

On 24 October 2026, the connected project's public Auth settings reported `google: false` and `phone: false`. The screens and HTTP flows are implemented, but Google and SMS sign-in cannot work live until those providers are configured and enabled. No live SMS was sent and no Google account was signed in during development.

Follow [GITHUB_SETUP.md](GITHUB_SETUP.md) for Google Android/iOS registration and driver linking, and [docs/SMS_SETUP.md](docs/SMS_SETUP.md) for MSG91 activation.

## Driver features

Dashboard, online/offline availability, a fourteen-day availability calendar, assigned/completed duties, selfie and expense capture, duty completion OTP, per-duty wallet credits, and document upload controls.

Driver duties, wallet balances and permissions come from the existing HireD backend. Authentication changes do not replace or alter its financial rules.

## Validation and builds

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --dart-define-from-file=config/auth.json
# Requires macOS, Xcode and signing:
flutter build ipa --release --dart-define-from-file=config/auth.json
```

Tests cover phone/Google HTTP exchanges against local stand-ins, driver access verification, failed/expired codes, disabled providers, rate limits, cancellation, registration and narrow-screen layouts. Passing these checks does not prove live OAuth, real SMS delivery or device integration.

This is a standalone driver repository. The existing admin/B2B portal source remains separate.
