# Setup and integration notes

This is a **standalone personal repository**, not a fork or branch of UniT7. It contains Flutter source with an offline demonstration. Native Android/iOS folders were not available in the source snapshot and are generated with `flutter create . --platforms=android,ios`.

## Build prerequisites
- Flutter SDK 3.4+ / Dart SDK supported by selected Flutter version
- Android: Android SDK / Android emulator or real device
- iPhone: macOS + Xcode and signing
- Run: `flutter create . --platforms=android,ios && flutter pub get && flutter run`

## iOS/Android permissions
After generating platform scaffolding, add `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist`. Validate camera permissions on Android; check the requirements for the target Android SDK.

## Planned backend contract (NOT verified)
- POST `/auth/driver/login`
- GET `/drivers/me`
- PATCH `/drivers/me/availability`
- GET `/drivers/me/trips`
- POST `/trips/:id/start`
- POST `/trips/:id/selfie` multipart
- POST `/trips/:id/expenses`
- POST `/trips/:id/close` with numeric OTP
- GET `/drivers/me/wallet`
- POST `/drivers/me/documents/:type` multipart

Server must own identity verification, trip state, expenses validation, OTP, driver payout calculation, and exactly-once wallet credit. The client must not authorize those financial operations. Credentials and document uploads must remain protected.

## Limitations
The current application is a demo plus API adapter. Actual backend integration, Flutter analyzer, Android/iOS builds, and device tests remain outstanding. No API keys or credentials are stored here.
