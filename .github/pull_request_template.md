## Summary

<!-- 1–3 bullets: what changed, why. -->

## Linear

<!-- HER-XXX (or "n/a") -->

## Target branch

- [ ] `development` (default — ships to TestFlight on merge)
- [ ] `main` (App Store release — only after TestFlight validation)

## Test plan

- [ ] `xcodebuild test -scheme LuminaVaultClient -only-testing:LuminaVaultClientTests` green
- [ ] `swiftlint lint` clean
- [ ] DTO comes from `LuminaVaultShared` (not duplicated client-side) if wire shape touched
- [ ] Manual smoke test on device/simulator for UI-touching changes
