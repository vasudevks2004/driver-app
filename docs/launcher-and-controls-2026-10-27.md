# HireD Android 1.0.1 (2): launcher and registration controls

The launcher now uses the existing purple HireD SVG wordmark on white. Its geometry and brand colors are unchanged. Android has an adaptive launcher resource with a transparent, safely inset foreground and white background, plus five legacy density images. The 19 iOS catalogue entries use matching white-background images. `assets/launcher-icon.svg` is the canonical full launcher composition; `assets/hired-logo.svg` remains the unchanged in-app logo.

The Register as a new driver button opens the existing form even when phone authentication is unavailable. The form explains the availability problem and lets the user retry the provider check without losing entered name, phone or city. OTP submission checks provider availability before attempting an Auth request. This does not bypass phone verification, create an account, grant driver access or enable a paid provider. No draft is claimed to survive an app restart.

Version: `1.0.1+2`. Android application ID stays `com.hired.hired_driver`; the Home, Duties, Earnings and Profile tabs remain unchanged. The build uses the existing `config/auth.json` for the same live Cloudflare/Supabase services. An APK build does not enable the server's phone or Google providers.

## Validation scope

Run `dart format --output=none --set-exit-if-changed lib test integration_test`, `flutter analyze --fatal-infos --fatal-warnings` and `flutter test`, then build with `flutter build apk --debug --dart-define-from-file=config/auth.json`. Existing widget tests cover navigation, duty filters/detail, selfie-first Start, onboarding document controls, validation/consent, camera-denial recovery, masked details, wrong OTP and email-form validation. New widget tests cover registration with phone authentication off and retrying availability while preserving entered details. Their service responses are stand-ins, not a hosted workflow pass.

Icon validation checks dimensions, opaque white backgrounds, visible purple mark and the adaptive safe area. Icons were rasterized from SVG with CairoSVG 2.8.2. Android compilation must confirm that all resource references resolve. Review the APK's embedded assets and signing identity after download.

## Live acceptance remains separate

Phone OTP, Google and DigiLocker require configured providers. Valid driver sign-in needs an approved account. Camera/dialer/maps behavior and persistent private uploads require an authorized handset/account test. The full trip-to-wallet and two-Admin statement journey remains subject to the backend policy and authenticated acceptance gates in the shared repository's production rollout report. Passing widget tests or an emulator preview is not evidence that every live button works.

This is a debug APK, not an owner-signed store release. Different CI debug signing keys can prevent installation over an earlier debug APK. Preserve pending work and device data before removing an old installation; do not silently uninstall an app to force an update.
