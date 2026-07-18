# Fastlane (LuminaVault iOS)

Dual-track shipping. Full operator guide: [`docs/TESTFLIGHT.md`](../docs/TESTFLIGHT.md).

## Install

```sh
bundle install
```

## Lanes

### `beta` — TestFlight (ready now)

Builds **Beta** (`com.lumina.fernando.beta` + share extension) and uploads to TestFlight.

```sh
BUILD_NUMBER=$(date +%s) bundle exec fastlane beta
```

### `release` — App Store draft (after production ASC app exists)

Builds **Release** (`com.lumina.fernando` + share extension) and uploads a **draft** to App Store Connect (does not submit for review).

```sh
SEED_PRODUCTION=1 bundle exec fastlane sync_signing   # once
BUILD_NUMBER=$(date +%s) bundle exec fastlane release
```

### `sync_signing` — match certs

```sh
bundle exec fastlane sync_signing                    # beta only
SEED_PRODUCTION=1 bundle exec fastlane sync_signing  # + production
```

### Build-only (no upload)

```sh
bundle exec fastlane build_beta
bundle exec fastlane build_release
```

## CI

| Workflow | Trigger | Lane |
| --- | --- | --- |
| `testflight.yml` | `development` push + `workflow_dispatch` | `beta` |
| `release.yml` | `workflow_dispatch` with confirm `ship-production` | `release` |

## Identities

| Track | Host bundle ID | Xcode config | Scheme |
| --- | --- | --- | --- |
| TestFlight | `com.lumina.fernando.beta` | Beta | `LuminaVaultClient-Beta` |
| App Store | `com.lumina.fernando` | Release | `LuminaVaultClient` |
