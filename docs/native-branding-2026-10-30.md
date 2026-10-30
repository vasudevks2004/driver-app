# Native branding — 30 October 2026

The existing transparent `assets/hired-logo.svg` (Git blob `948727c4d3da8e8414d985738c6a3c67c7628fa4`) is rendered into 180×60, 360×120 and 540×180 RGBA splash images with aspect-preserving framing. Matching images are used for Android density resources and the iOS LaunchImage set. The logo design and launcher icons are unchanged.

Android before API 31 displays the centered wordmark. API 31+ uses the existing launcher icon in the system splash with an explicit canvas background. Native day/night startup backgrounds and iOS use `#F6F7FB`, matching the app's existing light Flutter theme. The iOS launch image has explicit 180×60-point constraints and aspect-fit scaling instead of the 1×1 placeholder.

## Verification boundary

Generated PNGs were decoded for visual inspection in the authoring session. Source references, dimensions and storyboard constraint replacements were inspected. The execution environment was unavailable: Node/Flutter checks, Android compilation, Xcode builds and physical-device tests have NOT run for this change. No APK/IPA or store release is produced by this commit.

Before merging/releasing, run `node scripts/check-native-branding.mjs`, normal Flutter analysis/tests and native builds. Verify cold starts on supported Android versions, Android 12+, and iOS, in both device appearances. Check orientation/safe-area behavior, splash-to-first-frame colors and actual launcher masks. This source branch is in the standalone driver repository; apply the reviewed resource patch separately to any other mobile checkout used for release.
