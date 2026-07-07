# HER-216 — Client follow-ups

The HER-216 scaffold lands the iOS plumbing for WebAuthn passkey enrollment and login. The client now wires the Settings pane, `WEBAUTHN_RP_ID` Info.plist value, associated-domain entitlement, and revoke telemetry. Production still depends on real environment values and the cross-device acceptance demo below.

## Hard blockers (must do before shipping)

### 1. Add the `webcredentials` associated-domain entitlement

Client status: wired through `webcredentials:$(WEBAUTHN_RP_ID)` in Debug/Beta and Release entitlements.

The matching `apple-app-site-association` block must be served by that apex domain — see the server follow-up doc.

### 2. Set `WEBAUTHN_RP_ID` in Info.plist

Client status: `Info.plist` reads `$(WEBAUTHN_RP_ID)` and all sample xcconfigs declare it. Fill the real gitignored xcconfigs and confirm the value matches the server's `webauthn.relyingPartyId` config exactly. A mismatch surfaces as `ASAuthorizationError.failed` at runtime with no useful error text.

### 3. Drop the inline DTO mirror after `LuminaVaultShared` tag bump

`LuminaVaultClient/API/Auth/WebAuthnDTOs.swift` is a temporary stand-in until `LuminaVaultShared` ships the matching types (>= 0.30.0). Sequence after the tag:

1. Bump the SPM dependency in `LuminaVaultClient.xcodeproj` to `LuminaVaultShared 0.30.0`.
2. Delete `LuminaVaultClient/API/Auth/WebAuthnDTOs.swift`.
3. Confirm the build is green — all references resolve via `@_exported import LuminaVaultShared` from `AuthModels.swift`.
4. Add the `LuminaVaultShared` typealiases to `AuthModels.swift` for symmetry with the existing pattern.

### 4. Wire `PasskeysPaneView` into `SettingsRootView`

Client status: wired under Settings -> Account & Data -> Passkeys. `PasskeysPaneViewModel` loads the authenticated username from `/v1/auth/me`.

## Should-do (before ticket marked truly complete)

### 5. Tests

Add `LuminaVaultClientTests/Auth/PasskeyServiceTests.swift` covering:

* `parseRegistrationOptions` accepts a server-shape JSON blob and returns the expected `challenge`/`rpID`/`userID`/`userName`.
* `parseAuthenticationOptions` tolerates both `rpId` and `rp.id` keys (servers vary).
* `parseAuthenticationOptions` decodes `allowCredentials` into base64url-decoded `Data` array.
* `base64URLEncodedString` round-trips arbitrary `Data`.
* End-to-end mocked flow: feed a fake `ASAuthorizationCredential` through the delegate and assert the resulting DTO has the right fields.

Mock `ASAuthorizationController` via protocol injection if needed — keep `PasskeyService` testable.

### 6. Settings → wire up `register` happy path

`PasskeysPaneViewModel.enrol()` calls `AuthViewModel.registerPasskey`, but that requires the device to surface the system passkey enrollment sheet for the authenticated user. Confirm:

* The user is already authenticated (passkeys are enrolled *for* an existing account, not as a sign-up alternative).
* `username` is the LuminaVault username, not the email.
* On success, `vm.load()` re-fetches the credential list so the new row appears.

### 7. Discoverable-credential / passkey autofill

Best-in-class UX: tapping the email field on `AuthLandingView` triggers `ASAuthorizationController.performAutoFillAssistedRequests` and lets the QuickType bar offer enrolled passkeys without typing a username. Requires the server-side discoverable-credential flow (see server follow-ups §9) to be live first. Then:

1. Add a `signInWithPasskeyDiscoverable()` method on `AuthViewModel` that calls `webAuthnAuthenticateBegin(username: nil)` and feeds the options into `PasskeyService.authenticate` with `request.allowedCredentials = []`.
2. On `EmailMagicEmailView` / wherever the email lives, fire `performAutoFillAssistedRequests` from `.onAppear`.

### 8. Graceful "passkey not available" fallback

The acceptance criteria explicitly mention the "falls back cleanly to email/OTP" case. Today the `PasskeyError.unavailable` path only surfaces a string in `vm.error`. Add a UI affordance that, on `unavailable`, dismisses the passkey sheet and pushes `EmailMagicLinkView` automatically.

### 9. Telemetry

Two PostHog events fired in `AuthViewModel`:

* `auth_signed_in` with `method: "passkey"` — already wired in `signInWithPasskey`.
* `auth_passkey_enrolled` — already wired in `registerPasskey`.

Confirm all three reach the dashboard before considering HER-216 done. `auth_passkey_revoked` is emitted in `PasskeysPaneViewModel.revoke`.

### 10. Acceptance flow

Per the Linear ticket, the final acceptance demo is:

> Enrol a passkey on iPhone, then sign in on a fresh iPad using iCloud Keychain sync.

Test both devices on the same iCloud account. Confirm:

* Enrollment on iPhone surfaces the system "Save a passkey for LuminaVault?" sheet.
* iPad surfaces "Sign in with a passkey for LuminaVault?" sheet without any further enrollment.
* The same `username` works on both.
* `Settings → Passkeys` on either device shows one credential.
