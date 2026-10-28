# Android emulator acceptance and cost controls

The staging review branch now enables the existing Android 35 emulator job on its pull request, as well as preserving the prior push trigger. App runtime files, branding, navigation, API configuration and signing are unchanged.

The existing `integration_test/device_smoke_test.dart` boots `HireDDevelopmentApp`, uses its explicit preview phone/code fixtures, and renders and taps the four navigation destinations. A pass proves emulator startup/navigation for that preview. It does **not** prove real SMS, production authentication, camera/secure-storage permissions, hosted financial workflow, physical handset behavior or iOS installation. Actual shipped Dart classes versus managed staging are separate evidence in the hosted test report.

All automatic Actions artifact uploads in these two workflows are now off. A manual `workflow_dispatch` may opt in to `upload_artifacts` or `upload_apk`; both default false. The APK still builds and its package/provenance checks still run; a normal PR does not upload duplicate APKs, previews or lockfiles. Emulator failures print a bounded log instead of uploading a file. No cache-upload action or larger runner is added. The existing delivered `HireD Test 1.0.2 (3)` remains the test APK while app runtime source is unchanged; a newly generated debug signing key must not replace that APK casually.

The repository was verified public before this change. Jobs retain standard `ubuntu-latest` runners, documented free for public repositories: https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job . Artifact storage has separate allowances, which is why uploads are opt-in: https://docs.github.com/en/billing/concepts/product-billing/github-actions . This does not certify historical account charges or storage usage.

Validation before commit: both workflow YAML files parsed, retained read-only contents permissions and standard Ubuntu jobs, and every artifact-upload step was checked to require explicit workflow-dispatch input. Actual CI/device run results are recorded after execution; no pending or skipped job is counted as passed.
