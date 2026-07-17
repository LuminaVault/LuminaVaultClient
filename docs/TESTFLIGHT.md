# TestFlight + App Store shipping

End-to-end checklist for dual-track iOS builds: **TestFlight beta** (exists today) and **App Store production** (create later).

## Build configurations

The Xcode project has three target configurations:

| Configuration | Bundle ID | Scheme | Fastlane lane | Destination |
| --- | --- | --- | --- | --- |
| Debug | `com.lumina.fernando.test` | `LuminaVaultClient` (Run) | — | Local simulator/device |
| Beta | `com.lumina.fernando.beta` | `LuminaVaultClient-Beta` | `beta` | TestFlight |
| Release | `com.lumina.fernando` | `LuminaVaultClient` (Archive) | `release` | App Store Connect draft |

Share extension IDs mirror the host:

| Config | Share extension bundle ID |
| --- | --- |
| Debug | `com.lumina.fernando.test.LuminaVaultShareExtension` |
| Beta | `com.lumina.fernando.beta.LuminaVaultShareExtension` |
| Release | `com.lumina.fernando.LuminaVaultShareExtension` |

`MARKETING_VERSION` lives in `project.pbxproj`. `CURRENT_PROJECT_VERSION` is read from `BUILD_NUMBER`; CI sets this to `${{ github.run_number }}`.

Each configuration uses the matching local xcconfig copied from `LuminaVaultClient/Config/*.xcconfig.sample`. See `LuminaVaultClient/Config/README.md`.

## Current status

| Track | App Store Connect app | Signing (match) | CI |
| --- | --- | --- | --- |
| **TestFlight beta** | Exists | Seed with `bundle exec fastlane sync_signing` | `.github/workflows/testflight.yml` on `development` + manual |
| **App Store production** | Create later | Seed after ASC app + App IDs: `SEED_PRODUCTION=1 bundle exec fastlane sync_signing` | `.github/workflows/release.yml` **manual only** (type `ship-production`) |

Do **not** re-collapse beta into the production bundle ID without updating Fastlane, match profiles, APNS topic, RevenueCat, and server `APNS_BUNDLE_ID` in the same change.

## Fastlane lanes

| Command | What it does |
| --- | --- |
| `bundle exec fastlane beta` | Match (beta IDs) → Beta archive → TestFlight upload |
| `bundle exec fastlane release` | Match (prod IDs) → Release archive → ASC draft (no review submit) |
| `bundle exec fastlane build_beta` | Beta IPA only, no upload |
| `bundle exec fastlane build_release` | Production IPA only, no upload |
| `bundle exec fastlane sync_signing` | Create/refresh match certs for **beta** |
| `SEED_PRODUCTION=1 bundle exec fastlane sync_signing` | Also seed **production** certs/profiles |

### One-time local setup

```sh
cd LuminaVaultClient
bundle install

# 1. Ensure match certs repo exists (private) and MATCH_PASSWORD is set.
export MATCH_PASSWORD='…'
export MATCH_GIT_URL='git@github.com:LuminaVault/LuminaVaultIOSSecrets.git'  # optional override

# 2. Seed TestFlight signing (host + share extension)
bundle exec fastlane sync_signing

# 3. Ship a TestFlight build
BUILD_NUMBER=$(date +%s) bundle exec fastlane beta
```

When the production ASC app exists:

```sh
# Developer portal App IDs + ASC app for com.lumina.fernando (+ share extension)
SEED_PRODUCTION=1 bundle exec fastlane sync_signing
BUILD_NUMBER=$(date +%s) bundle exec fastlane release
```

## Required GitHub Actions secrets

| Secret | Purpose |
| --- | --- |
| `MATCH_GIT_URL` | Private match certificates repo URL |
| `MATCH_PASSWORD` | Passphrase for match-encrypted certs/profiles |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | API key issuer ID |
| `APP_STORE_CONNECT_API_KEY_KEY` | Base64-encoded `.p8` private key contents |
| `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD` | Fallback Apple ID app-specific password |
| `SENTRY_AUTH_TOKEN` | Optional dSYM upload |
| `CONFIG_BETA_XCCONFIG` | Full contents of `Config.Beta.xcconfig` for CI TestFlight builds |
| `CONFIG_RELEASE_XCCONFIG` | Full contents of `Config.Release.xcconfig` for CI release builds |

If `CONFIG_*_XCCONFIG` is unset, CI copies the `.sample` file so the project graph resolves — those placeholders are not suitable for a real TestFlight binary. Prefer storing the real xcconfig body in the secret.

## Pre-submission checklist

### Encryption export

`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set across all three configs. **Do not flip this without legal review.**

### Privacy usage descriptions

Required `NS*UsageDescription` keys must exist in **all three** build configs when a capability is added.

### Entitlements

Host app (Debug/Beta share `LuminaVaultClient.entitlements`; Release uses `LuminaVaultClient.Release.entitlements`):

- Sign in with Apple, APNS, HealthKit (+ background delivery), App Groups, Keychain Sharing, Associated Domains as required.

These must match App ID capabilities. After adding an entitlement:

```sh
bundle exec fastlane sync_signing
# and when production is live:
SEED_PRODUCTION=1 bundle exec fastlane sync_signing
```

### OAuth / analytics / billing

Cross-repo invariants are documented in `LuminaVaultClient/Config/README.md` and the root `LUMINAVAULT_DEPLOYMENT_CONFIG_GUIDE.md`.

Beta and production may use different Google client IDs and RevenueCat public keys (see sample xcconfigs). Server audiences must accept the identity token for each shipping bundle.

## Post-build smoke test (TestFlight)

1. Install on a device that has never opened LuminaVault.
2. Walk through onboarding to auth.
3. Sign in with Apple / phone OTP.
4. Grant HealthKit when prompted.
5. Confirm capture/share extension and push registration against the beta bundle topic.
