fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios sync_signing

```sh
[bundle exec] fastlane ios sync_signing
```

Seed or refresh match certs/profiles. Beta always; production only with SEED_PRODUCTION=1

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build Beta (com.lumina.fernando.beta) and upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build Production (com.lumina.fernando) and upload a draft App Store release

### ios build_release

```sh
[bundle exec] fastlane ios build_release
```

Build production IPA only (no upload) — useful before the ASC app exists

### ios build_beta

```sh
[bundle exec] fastlane ios build_beta
```

Build beta IPA only (no upload)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
