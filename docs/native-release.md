# Native build and release setup

Build the committed `android/` and `ios/` projects; do not run `flutter create` over this checkout. They were assembled from the Flutter 3.35.7 templates at `adc901062556672b4138e18a4dc62a4be8f4b3c2`, with the app's existing permissions, HireD icon and signing changes. Build validation belongs to the matching CI commit.

| Setting | Committed value |
| --- | --- |
| Android application ID / namespace | `com.hired.hired_driver` |
| iOS bundle ID | `com.hired.hiredDriver` |
| iOS minimum | 13.0 |
| Gradle wrapper | 8.12, distribution SHA-256 pinned |
| Android Gradle Plugin | 8.9.1 |
| Kotlin plugin | 2.1.0 |
| Flutter / JDK used by CI | 3.35.7 / 17 |

Android release builds require a local `android/key.properties` based on `android/key.properties.example`, plus the owner's upload keystore. A missing signing configuration fails release tasks; release builds never fall back to a debug key. Real signing files and passwords stay out of Git. Debug APKs remain review artifacts.

iOS distribution requires the owner's Apple team, certificate and provisioning profile selected in Xcode. The simulator workflow needs no distribution identity. Confirm the bundle identifiers before first store registration; changing them after installation changes app identity.

Google requires a web client ID in build configuration, Android OAuth registration for the exact package and signing fingerprints, and an iOS OAuth client for the exact bundle ID. Set `GOOGLE_IOS_CLIENT_ID` and add that client's actual reversed URL scheme to `ios/Runner/Info.plist`. Do not invent a scheme or client ID. The current values are empty and the connected Google provider remains disabled.

Native builds do not verify Google account selection, OTP delivery, camera permissions on a real device, background/resume behavior or live driver membership. Run those acceptance checks with the coordinated backend before pilot distribution.
