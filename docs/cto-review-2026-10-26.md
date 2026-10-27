# CTO review follow-up — 26 October 2026

The supplied review describes the older `main` branch (`6a702d8`). The current implementation is in [driver PR #1](https://github.com/vasudevks2004/driver-app/pull/1), based on `c3546a9`, and depends on [shared backend PR #12](https://github.com/Buildathon-HireD-Brototype-2026/UniT7/pull/12) at `2d0ad3f`. These changes are unmerged. A branch, a CI build and a production deployment are separate evidence.

## Findings against the current branch

| Review finding | Verified status |
| --- | --- |
| New idempotency key for every retry | Already corrected: account/backend-scoped hashes and UUID keys persist in secure storage. Ambiguous receipts remain unresolved across restart, upload retries and token rotation. The shared backend provides locks, receipts and cancellation fences. |
| Supabase refresh token sent to an incompatible route | The shared Worker forwards the token to Supabase `/auth/v1/token?grant_type=refresh_token`, then rechecks driver membership before returning rotated credentials. Client regressions now cover phone and Google session rotation and access revocation. Live provider expiry remains an acceptance check. |
| Open registration and SMS pumping | Still a rollout blocker. Live phone and Google are both disabled as of this review. Do not enable paid SMS until provider credentials, DLT approval where required, server-verified CAPTCHA/attestation, resend/rate/volume limits and spend controls are configured and tested. Client validation alone cannot protect a publicly callable Auth API. |
| Only auth tests | The existing branch already tests duty/expense/close retries, wallet signs, assignment refresh, stale resources, onboarding and UI. New tests cover non-finite money, expense precision/range and provider-session rotation. |
| main.dart god widget and local-only trip state | Already refactored: a small entry point, typed duty/wallet models, repository and ChangeNotifier state layer. Production mutations re-read server state. Explicit preview data lives under the separate development entry point. A state-management package is not needed to preserve this separation. |
| Permissive CI | Corrected in this follow-up: formatting changes and analyzer warnings/info fail CI, and braces are enforced. Android build and emulator jobs already existed. iOS now checks the committed native project on matching pushes and PRs. |
| NaN / Infinity and zero expense input | Input regex already rejected these on the branch. A separate shared-parser gap still accepted non-finite strings; this follow-up fixes it and rejects invalid signed ledger effects. Expense syntax now matches the backend's ten-digit/two-decimal range. Ordinary expense entry must be positive; the separate No expenses action sends zero without asking the driver to enter a dummy expense. An operational expense ceiling still needs business approval. |
| Unbounded uploads / missing authorization renewal | Already corrected on the branch: raw-body contract, file signatures/types, 5 MB bound, deadline, durable retry key and one bounded 401 refresh/retry. Consent, private storage, identity encryption and deletion queues are in the companion backend; rollout and scheduled deletion still require live verification. |
| Native projects absent | Corrected in this follow-up: fixed Android/iOS identities and projects, private release-signing configuration, permissions, HireD icons and a checksum-verified Gradle wrapper are committed. CI builds these files directly. Owner distribution credentials remain external. |

## Live rollout boundary

Cloudflare `hired-unit7` is still a direct-upload project. Its inspected production deployment is `0fa8073e-830f-4122-952c-92210effd7ce`, source `e2fa662`; preview has no configured environment variables. The inspected Supabase migration ledger does not contain the new reliability/PRD migrations. The older production contract cannot be treated as evidence for these source changes. The existing private Sites Admin project is also a separate publication; this app review does not replace either portal.

The configured Pages API prefix includes `/admin/api/v1`. That prefix is also accepted for driver routes and is not an admin authorization grant. Preserve it until a coordinated rollout exposes and verifies a stable driver alias or an owner-controlled API domain. Do not hardcode an unregistered domain into installed apps.

Google/phone provider credentials, SMS abuse protection/DLT setup, coordinated backend rollout, approved financial policy, PostgreSQL concurrency checks, and a real hosted booking → assignment → selfie → start → expense/no-expenses → partner code → wallet journey remain pilot gates. Background push, crash reporting, localization, an update gate and stronger proof-of-trip remain product work. Current reconnect/polling and durable retries improve network recovery but do not establish full offline operation.

## Evidence

Before this follow-up, [CI run 40219990043](https://github.com/vasudevks2004/driver-app/actions/runs/40219990043) passed 53 Flutter tests, an Android debug build and emulator preview. The iOS simulator build passed on the same prior app source. Those results do not validate the new commit; its checks must be assessed separately.

A Postman live read of `/admin/api/v1/drivers/me` returned 401 and passed two assertions (anonymous access denied and JSON error format). The CLI returned exit 1 for the expected non-2xx response; this is a passing security expectation, not a successful authenticated journey. Supabase public Auth settings reported `phone: false` and `google: false`. No SMS was sent and no real identity documents or money were created.

The attempted Postman 1.77.0 local refresh simulation could not start: its dataset runtime setup failed before the Worker could run. This provides no simulated refresh evidence. The added Flutter HTTP tests check the client contract separately, and the companion Worker's source shows the native Supabase refresh exchange; neither proves successful live provider refresh.

Local Flutter setup and offline generation were rejected by automatic approval review for attempted cloud metadata access. No approval to access metadata was requested or used. Static Dart formatting, source checks and native configuration checks can run locally; Flutter execution is validated through GitHub CI. Release readiness must follow the observed results, not the review's assumption that priorities 1–3 alone prove a 20-driver pilot.
