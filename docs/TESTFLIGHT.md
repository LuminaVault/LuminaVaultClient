# TestFlight Submission

End-to-end checklist for getting a build into TestFlight, plus the required CI secrets and known-blocker follow-ups.

## Build configurations

The Xcode project has three target configurations:

| Configuration | Bundle ID | Used for |
| --- | --- | --- |
| Debug | `com.lumina.fernando.test` | Local dev on simulator + physical device |
| Beta | `com.lumina.fernando.beta` | TestFlight builds (Fastlane `beta` lane) |
| Release | `com.lumina.fernando` | App Store submission (Fastlane `release` lane) |

`MARKETING_VERSION` lives in `project.pbxproj`. `CURRENT_PROJECT_VERSION` is read from the env var `BUILD_NUMBER`; CI sets this to `${{ github.run_number }}` (see `.github/workflows/testflight.yml:26`).

Each build configuration should use the matching local xcconfig copied from `LuminaVaultClient/Config/*.xcconfig.sample`. Those files provide `API_BASE_URL`, OAuth client IDs, RevenueCat public SDK key, PostHog keys, Sentry DSN, and legal URLs.

## Pre-submission checklist

Run through these before pushing a build to TestFlight. Most are already wired in `project.pbxproj` / `LuminaVaultClient.entitlements`; this list exists so the next contributor doesn't re-discover the requirements from rejection emails.

### Encryption export

`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set across all three configs. **Do not flip this without legal review** — flipping to YES enables the export-compliance question wall.

### Privacy usage descriptions

All required strings are baked into `INFOPLIST_KEY_*` keys:

- `NSFaceIDUsageDescription` — biometric unlock copy.
- `NSHealthShareUsageDescription` — HealthKit read copy.
- `NSHealthUpdateUsageDescription` — HealthKit write copy.

If you add a feature that touches camera, photo library, location, microphone, or contacts, **add the matching `NS*UsageDescription` key in all three build configs** in the same PR or TestFlight will reject the build.

### Background execution

`INFOPLIST_KEY_UIBackgroundModes = processing` is required for HealthKit background delivery (`HKObserverQuery` + `enableBackgroundDelivery`). It is set in all three build configs.

### Entitlements (`LuminaVaultClient/LuminaVaultClient.entitlements`)

- `com.apple.developer.applesignin` — `[Default]`. Required for Sign in with Apple.
- `aps-environment` — required for APNS device-token registration.
- `com.apple.developer.healthkit` — `true`. Required for any HealthKit read/write.
- `com.apple.developer.healthkit.background-delivery` — `true`. Required for HealthKit background queries.
- `com.apple.security.application-groups` — `group.com.lumina.fernando`. Required by the share extension.

These must match the App ID's capabilities in App Store Connect. The Fastlane `match` setup keeps the provisioning profile in sync — re-run `bundle exec fastlane match appstore` after adding a new entitlement.

### OAuth URL schemes

`GoogleSignIn` requires `CFBundleURLTypes` in `Info.plist` containing the reversed `GIDClientID`. Use `LuminaVaultClient/Config/Info.plist` as the target plist and set `REVERSED_CLIENT_ID` from the environment xcconfig.

Cross-repo invariants:

- `GID_CLIENT_ID` must equal server `OAUTH_GOOGLE_CLIENTID`.
- `APPLE_SERVICE_ID` must equal server `OAUTH_APPLE_CLIENTID`.
- `X_CLIENT_ID` must equal server `OAUTH_X_CLIENTID`.
- `X_REDIRECT_URI` must match the X Developer Portal callback exactly.

### RevenueCat and App Store products

RevenueCat is configured by `LV_RC_API_KEY` in the active xcconfig. The server receives RevenueCat webhook events at `/v1/billing/revenuecat` and validates them with `REVENUECAT_WEBHOOK_SECRET`.

Recommended SKU/product identifiers:

| Item | Identifier |
| --- | --- |
| App SKU | `luminavault-ios` |
| Beta/internal SKU | `luminavault-ios-beta` |
| Monthly Plus | `lv_plus_monthly` |
| Annual Plus | `lv_plus_annual` |
| Monthly Pro | `lv_pro_monthly` |
| Annual Pro | `lv_pro_annual` |

Before TestFlight with purchases, create products in App Store Connect, attach them to RevenueCat offerings, and verify purchase plus restore on a sandbox tester.

## Fastlane lanes

`fastlane/Fastfile` defines two lanes:

- `bundle exec fastlane beta` — builds the Beta config, signs with `com.lumina.fernando.beta`, uploads to TestFlight.
- `bundle exec fastlane release` — builds the Release config, signs with `com.lumina.fernando`, submits a draft release to App Store Connect.

The `beta` lane is the one CI invokes (`.github/workflows/testflight.yml`). The `release` lane has no CI trigger yet — invoke it manually until the release workflow lands.

## Required GitHub Actions secrets

`.github/workflows/testflight.yml` reads these (lines 29–30 and below):

| Secret | Purpose |
| --- | --- |
| `MATCH_GIT_URL` | URL of the private match certificates repo. |
| `MATCH_PASSWORD` | Passphrase for the match-encrypted certs/profiles. |
| `APP_STORE_CONNECT_API_KEY_KEY_ID` | App Store Connect API key ID. |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | API key issuer ID. |
| `APP_STORE_CONNECT_API_KEY_KEY` | The raw `.p8` private key contents. |
| `FASTLANE_USER` | Apple ID with App Store Connect access (fallback if API key path fails). |
| `FASTLANE_PASSWORD` | App-specific password for the above. |
| `SENTRY_AUTH_TOKEN` | Required if dSYM upload runs in CI. |

Rotate annually or whenever a team member with access leaves.

## Local invocation

```sh
# Beta build → TestFlight (uses match for signing)
bundle exec fastlane beta

# Bump build number manually before invoking the lane:
BUILD_NUMBER=$(date +%s) bundle exec fastlane beta
```

CI auto-bumps via `${{ github.run_number }}`; locally you pass `BUILD_NUMBER` yourself.

## Post-build smoke test

After a TestFlight build lands on a physical device:

1. Launch on a device that has **never** opened any version of LuminaVault.
2. Walk through onboarding to the auth landing.
3. Tap **Sign in with Apple** — confirm the native Apple sheet appears and authenticates.
4. Tap **Continue with phone** — confirm the OTP flow lands.
5. Sign in, then grant HealthKit permissions when prompted.
6. Backbone the app, leave it overnight, re-open. Confirm a fresh HealthKit batch lands (background delivery sanity).
