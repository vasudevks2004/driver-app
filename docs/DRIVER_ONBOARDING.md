# Driver applications and DigiLocker

## What the app does

The login link is **Register as a new driver**. Applicants enter name, mobile and city, verify a six-digit SMS code, then add:

- Driving licence number, date of birth, licence expiry and vehicle class.
- Front/back licence photos (camera or photo library, JPEG/PNG, maximum 6 MB each).
- A camera selfie, previewed as the driver avatar.
- Explicit permission for document review and using the selfie as the driver profile photo.

The service issues an application reference after a successful submission. Returning applicants can reopen their existing application by verifying the same mobile number. Draft document upload markers are restored; no documents are included in Auth user metadata. Onboarding tokens remain in memory and never unlock the duties dashboard. If the app is killed during camera use, verify the mobile again and resume the saved application; an interrupted, unsent photo must be captured again.

The avatar is read through an authenticated endpoint for the same application owner after driver sign-in. It has no public storage URL. No facial matching, liveness test or automatic licence approval is performed.

## Service setup

The function uses existing Supabase Auth and a separate private bucket. It does not change the existing HireD API, role mappings or wallet rules.

1. Apply `supabase/setup-onboarding.sql` as an additive database migration in the same project used by `config/auth.json`.
2. Deploy `supabase/functions/driver-onboarding` under the name `driver-onboarding`. Its `verify_jwt = false` supports the public OAuth callback; the handler validates **every other route** with Auth `/auth/v1/user`, requires a confirmed phone, and scopes queries to that user's ID. Never deploy a handler without that check.
3. The function receives `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from the server runtime. Never copy the service key to Dart configuration. Both tables have RLS enabled and deny direct access to public/anon/authenticated roles. The private bucket has no client access policy.
4. Enable/configure Supabase Phone and test SMS delivery separately. Existing Google login also needs the previously documented Google provider setup. This change does not activate either provider.
5. After review, an authorized HireD administrator must provision/link the Auth user in the existing driver backend. `driver_applications.status = approved` alone does **not** grant a driver role. Approval UI and automatic provisioning are outside this driver application.

Reviewers can inspect the isolated `driver_applications` table and private objects through authorized server/admin tools. The app cannot alter review status or the provider's document receipt flag. Set an organization-approved retention/deletion process for rejected and abandoned applications before accepting real documents. Delete the corresponding private storage objects when deleting an application; deleting an Auth row cascades database rows but does not remove Storage objects automatically.

## DigiLocker activation

DigiLocker requester access requires organization onboarding and approved credentials. Official entry points:

- https://www.digilocker.gov.in/web/partners/requesters
- https://www.digilocker.gov.in/web/partners/introductions
- https://www.digilocker.gov.in/assets/FAQ%20DL%20EL_onboarding.pdf

Configure these **server secrets**, using the exact API endpoints/scopes approved in your requester documentation:

| Secret | Value |
| --- | --- |
| `DIGILOCKER_CLIENT_ID` | Approved requester client ID |
| `DIGILOCKER_CLIENT_SECRET` | Requester secret; server only |
| `DIGILOCKER_REDIRECT_URI` | `https://rzynmkewypubveiqneat.supabase.co/functions/v1/driver-onboarding/digilocker/callback` — register this exact URL with the provider |
| `DIGILOCKER_AUTHORIZATION_URL` | Approved OAuth authorization endpoint |
| `DIGILOCKER_TOKEN_URL` | Approved authorization-code token endpoint |
| `DIGILOCKER_ISSUED_DOCUMENTS_URL` | Approved issued-document list endpoint returning `items` with `doctype` and `uri` |
| `DIGILOCKER_DOCUMENT_URL_TEMPLATE` | Approved document fetch endpoint with a literal `{uri}` placeholder |
| `DIGILOCKER_SCOPE` | Approved minimal scopes; leave empty only if the provider uses its registered default |

Endpoints are intentionally not guessed or supplied by the mobile client. The adapter accepts official `digilocker.gov.in` / `meripehchaan.gov.in` HTTPS hosts only. Adapt the issuer-specific response mapping if the approved API version differs. No requester credentials were available during implementation, so live token exchange/document retrieval is unverified. Discovery found an API Setu certificate API but it was not a substitute for the requested DigiLocker consent flow.

The connection asks for user consent, creates random state and a PKCE S256 verifier, keeps only the state hash plus short-lived verifier server-side, and opens DigiLocker in the external browser. The callback atomically consumes unexpired state, exchanges the code server-side, fetches an issued `DRVLC` document, stores it privately and clears the verifier. Tokens are not persisted or returned to the app. Opening the browser or returning to the app alone never marks a connection successful. After returning, **Check DigiLocker connection** reads the server result.

The status **Issued licence received. HireD review is pending.** means the configured provider returned a licence document. It does not certify that a manually entered licence number, name or date matches it; reviewers must compare them and check validity. Cancellation, no issued licence, expired/replayed state, missing credentials and provider errors leave manual photo upload available. A selfie remains required.

## App service contract

Base URL: `${SUPABASE_URL}/functions/v1/driver-onboarding`.
Every route except `/digilocker/callback` needs `Authorization: Bearer <confirmed-phone Auth access token>` and the project's public `apikey`. Responses never include private object paths or provider tokens.

| Method | Path | Request | Result |
| --- | --- | --- | --- |
| POST | `/application` | JSON `full_name`, `city` | Create or reopen caller's application |
| GET | `/application` | — | Application reference, status, upload markers, DigiLocker status |
| POST | `/documents/selfie` | Raw JPEG/PNG bytes and matching Content-Type | Updated application markers |
| POST | `/documents/licence_front` | Raw JPEG/PNG bytes | Updated markers |
| POST | `/documents/licence_back` | Raw JPEG/PNG bytes | Updated markers |
| GET | `/avatar` | — | Owner's private selfie bytes, no-store |
| POST | `/digilocker/start` | JSON `consent: true` | Official authorization URL with state and PKCE challenge |
| GET | `/digilocker/callback` | Provider `state`, `code` or `error` query | Static return-to-app page, single-use state |
| POST | `/submit` | JSON `licence_number`, `birth_date` and `licence_expiry` (`YYYY-MM-DD`), `vehicle_class` (`LMV`, `TRANSPORT`, `BOTH`), `consent: true` | Submitted application reference |

Public failures use `{ "message": "…" }` with 400 (validation), 401 (expired/missing identity), 403 (unverified phone), 404 (missing resource), 409 (already submitted), 413 (oversize), or 503 (setup/upstream unavailable). Submit is repeatable for an already submitted application. Submitted documents are immutable through this app.

## Checks

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
npx --yes deno@2.9.6 check supabase/functions/driver-onboarding/index.ts
node --experimental-strip-types --test supabase/functions/driver-onboarding/service.test.mjs
```

The Node suite runs the real service handler against local HTTP stand-ins for Auth, database, private Storage and the configured provider contract. Dart HTTP tests exercise the mobile transport against a local HTTP server; widget tests cover narrow screens, selfie/document controls, consent and the receipt. Stand-ins prove implementation behavior against this contract; they do not prove live DigiLocker access, SMS delivery, document authenticity or native camera behavior.
