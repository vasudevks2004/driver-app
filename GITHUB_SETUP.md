# Authentication and device setup

## Configuration

Launch with `flutter run --dart-define-from-file=config/auth.json`.

| Key | Purpose |
| --- | --- |
| `API_URL` | Existing HireD driver API base, including `/api/v1` |
| `SUPABASE_URL` | Supabase project origin, without `/auth/v1` |
| `SUPABASE_PUBLISHABLE_KEY` | Public client key from that same project |
| `GOOGLE_WEB_CLIENT_ID` | Web OAuth client ID used as native sign-in's server audience |
| `GOOGLE_IOS_CLIENT_ID` | iOS OAuth client ID; required for iPhone sign-in |

The checked-in Supabase URL/public key belong to `B_2_B`; the driver API must use that same project. Public client configuration is intended to ship in the app. Never add admin capabilities, a service-role key, OAuth client secrets or SMS provider credentials here.

## Google

1. Register Android and iOS apps in the Google Cloud/Firebase project used for HireD. Use the **actual** Android `applicationId` and iOS bundle identifier from your native project. Record the debug and release signing certificate fingerprints for Android.
2. Create a **Web application** OAuth client. Configure Supabase's Google provider using its client ID/secret. Add every native/web audience required by the provider's client-ID settings. Keep the secret in Supabase only.
3. Fill `GOOGLE_WEB_CLIENT_ID` in the config. This is passed to `GoogleSignIn.instance.initialize(serverClientId: ...)`, so Android does not require `google-services.json` for this integration. The registered package and SHA fingerprints must still match the installed build.
4. For iOS, fill `GOOGLE_IOS_CLIENT_ID`. In `ios/Runner/Info.plist`, add a `CFBundleURLTypes` entry whose `CFBundleURLSchemes` contains that client's **reversed client ID**, copied from Google's configuration. Passing client IDs from Dart does not remove this URL-scheme requirement.
5. Enable the Google provider in Supabase. Test account selection, cancellation, logout and signing back in on both platforms. Configure OAuth consent-screen test users if the Google project requires them.

The native SDK acquires Google proof. Supabase validates that proof and issues an Auth session. The app then calls `GET /drivers/me` with the resulting access token before it saves a HireD driver session. Google profile data never grants a driver role.

Official setup: [Google Flutter plugin](https://pub.dev/packages/google_sign_in), [Android](https://pub.dev/packages/google_sign_in_android), [iOS](https://pub.dev/packages/google_sign_in_ios), [Supabase Google](https://supabase.com/docs/guides/auth/social-login/auth-google).

## Phone and registration

1. Enable Phone in Supabase Authentication providers and connect an SMS provider. Provider credentials stay in Supabase. Adjust sending/rate-limit settings for the prototype; use provider test numbers where available.
2. The app uses a 6-digit SMS OTP. Keep the project's SMS OTP length at 6. The resend button waits 60 seconds, and server-side limits remain authoritative.
3. Login calls `/auth/v1/otp` with `create_user: false`. Registration calls the same route with `create_user: true`, `full_name`, optional `city`, and an onboarding intent. OTP verification calls `/auth/v1/verify` with `type: sms`.
4. A registration creates/verifies a **Supabase Auth identity**, not an approved driver record or an admin review queue. A HireD administrator must review it and provision/link the existing driver record to that Auth user's ID using the backend's trusted onboarding process. A phone-looking value in user metadata does not link a phone identity.
5. Existing email/password drivers must have a verified phone identity associated with their **same Auth user** to use phone login. The app does not silently merge accounts based on an unverified phone/name. For Google, use the approved account's email and confirm the identity is linked to the correct Auth user.
6. Check correct, wrong and expired OTPs, resend, change-number, duplicate registration, network failure and a verified identity without driver access. The app presents an activation screen for a profile denied with HTTP 403 and revokes the temporary identity-only session.

Official setup: [Supabase phone login](https://supabase.com/docs/guides/auth/phone-login), [identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking).

## Native project notes

Native folders are generated with `flutter create . --platforms=android,ios --project-name=hired_driver --org=com.hired` if absent. Preserve native folders you already configured locally; do not regenerate an existing signed app unnecessarily.

- Android: add the `android.permission.INTERNET` permission to the **main/release** manifest as well as debug manifests. Verify camera access for duty selfies and the platform requirements of `image_picker` and `file_picker`.
- iOS: add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist` for duty selfies/document uploads, alongside the Google URL scheme. Build on macOS/Xcode with the appropriate signing team.
- The native Google button targets Android and iOS. Web/Windows previews can inspect the screens, but Google sign-in there is not implemented by this mobile integration.

## Existing backend contract

The existing email/password login, refresh, logout and forced-password-change routes remain under `/auth/driver/*`. Google/phone use Supabase's public Auth endpoints directly, then the existing `GET /drivers/me` role check; no unimplemented Google/phone routes are assumed in the HireD Worker.

Driver service routes for duties, availability, wallet and uploads retain their existing contracts. This change does not add new database tables, auto-approve drivers, deploy backend changes or activate external providers.

## Testing

`flutter test test/auth_http_test.dart` runs the real Auth/driver HTTP clients against a local server implementing the documented endpoint contracts. It injects only the Google SDK credential acquisition and secure-storage plugin, so it exercises HTTP paths, headers, payloads and responses without sending SMS or logging in a real account.

`flutter test test/auth_screen_test.dart` tests forms and navigation with a fake controller. The fake never ships in the app. Live end-to-end Google/SMS checks and Android/iOS device builds require the setup above.
