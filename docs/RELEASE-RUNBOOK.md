# Release Runbook — TestFlight → App Store

Operational guide for shipping LuminaVault. Paste-ready field values live in
[`APP-STORE-SUBMISSION.md`](./APP-STORE-SUBMISSION.md); RevenueCat dashboard
detail in [`revenuecat-appstore-setup.md`](./revenuecat-appstore-setup.md).

- Bundle ID: `com.lumina.fernando` · Team: `84X9WYBF36`
- API (Release): `https://api.luminavault.fyi` (live)
- Privacy: `https://luminavault.fyi/privacy` · Terms: `https://luminavault.fyi/terms` (live)
- Release build verified: `xcodebuild ... -configuration Release` → BUILD SUCCEEDED

---

## A. How to provide me the Apple certs & secrets — **do NOT paste them in chat**

Secrets pasted into chat land in transcripts/logs. Use these instead:

**I never need the raw certificates.** fastlane `match` keeps the distribution
cert + provisioning profiles in a **private git repo, encrypted** with
`MATCH_PASSWORD`. CI checks them out at build time. So:

1. **Distribution cert / profiles** → seed once from your Mac (has Apple login):
   ```bash
   cd LuminaVaultClient
   fastlane match init          # point at a PRIVATE repo, e.g. git@github.com:LuminaVault/ios-certs.git
   bundle exec fastlane match appstore --app_identifier com.lumina.fernando
   ```
   This uploads encrypted signing material. I don't see it; CI reads it.

2. **All secrets → GitHub Secrets** (encrypted at rest, never echoed). Set them
   yourself with `gh secret set`, which reads a file or stdin — the value never
   appears in the terminal or chat:
   ```bash
   gh secret set MATCH_PASSWORD --repo LuminaVault/LuminaVaultClient
   gh secret set MATCH_GIT_URL  --repo LuminaVault/LuminaVaultClient
   gh secret set APP_STORE_CONNECT_API_KEY_ID     --repo LuminaVault/LuminaVaultClient
   gh secret set APP_STORE_CONNECT_API_KEY_ISSUER_ID --repo LuminaVault/LuminaVaultClient
   gh secret set APP_STORE_CONNECT_API_KEY_KEY < AuthKey_XXXX.p8   # file → never printed
   gh secret set FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD --repo LuminaVault/LuminaVaultClient
   ```

3. **If I must run a signed build locally** (not preferred — CI is the path):
   put the ASC API `.p8` at a **gitignored** path and just tell me the path +
   key/issuer IDs. Never paste the key contents. Better: let CI build via
   `testflight.yml` and I drive it with `gh`.

**Bottom line:** run `fastlane match` once + set GitHub secrets yourself. Tell me
"secrets are set" and I trigger/inspect the build. I require zero raw secrets.

---

## B. TestFlight testers & monetization — answers

**Who can test?** Any Apple ID you invite in App Store Connect → TestFlight can
install. Inside the app they sign in with **any LuminaVault account** (email,
phone, Sign in with Apple, or Google) — that's your app's own auth, unrelated to
the tester's Apple ID. **No special Apple ID needed.**

**Does monetization block testing?** **No.** In TestFlight builds, in-app
purchases run in **StoreKit sandbox = free** — testers can subscribe to Pro /
Ultimate and are **never charged**, and renewals are accelerated. So testers can
exercise paid tiers without real money and without you skipping monetization. (No
separate "sandbox tester" account is required for TestFlight — that's only for
direct Xcode dev builds.)

**Do you need a special user to skip the paywall?** Optional. Two ways:
- **Let them buy in sandbox** (free) — exercises the real purchase flow. Best for
  validating billing end-to-end.
- **Comp an account to a tier** (skips the paywall entirely) — best for App Review
  and for testers who shouldn't touch billing. The server supports this:
  ```bash
  curl -X PUT https://api.luminavault.fyi/v1/admin/users/<USER_ID>/tier-override \
    -H "X-Admin-Token: $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"tierOverride":"ultimate"}'    # none | pro | ultimate
  ```
  This forces the tier **without changing RevenueCat state**. Requires
  `ADMIN_TOKEN` set in the server `.env.production` (currently empty → endpoint
  disabled until you set it). Get `<USER_ID>` from the account after it signs in.

**Recommendation:** create ONE dedicated review/demo account (email + password),
comp it to `ultimate`, and give those credentials to App Review in the submission
notes. Yes — create a special email+password for this. App Review needs a working
login that reaches paid features.

> App Review (required only for **external** TestFlight testers and for public
> release) tests purchases in sandbox; internal testers (≤100, your team) need
> **no review** and install within minutes.

---

## C. Full ordered runbook

### 1. Apple Developer portal (one-time)
- App ID `com.lumina.fernando` with capabilities matching the Release
  entitlements: **HealthKit, Sign in with Apple, Push Notifications, Associated
  Domains, App Groups** (`group.com.lumina.fernando`), **Keychain Sharing**.
- Share-extension App ID `com.lumina.fernando.LuminaVaultShareExtension` (+ same
  app group).

### 2. App Store Connect — app record
- Create the app, bundle `com.lumina.fernando`. Fill App Information
  (§1 of `APP-STORE-SUBMISSION.md`).

### 3. Subscriptions (monetization)
- Subscription group `LV Subscriptions`, 4 products (exact IDs/prices in §4 of
  `APP-STORE-SUBMISSION.md`), 7-day free trial on the two monthly products.
- Wire RevenueCat (`revenuecat-appstore-setup.md`): link iOS app, ASC shared
  secret + ASC API key, import products, map `pro`/`ultimate`, build `default`
  offering. Put the public `appl_*` key as `LV_RC_API_KEY` in
  `Config/Config.Release.xcconfig`.

### 4. Signing
- `fastlane match appstore --app_identifier com.lumina.fernando` (§A above).

### 5. CI secrets
- Set the GitHub secrets (§A above).

### 6. Build + upload
```bash
gh workflow run testflight.yml --repo LuminaVault/LuminaVaultClient
gh run watch --repo LuminaVault/LuminaVaultClient
```
Pipeline: match certs → archive (Release config, `api.luminavault.fyi`) →
`upload_to_testflight`. Build number = CI run number (auto).

### 7. ASC forms
- App Privacy (§2), Accessibility (§3 — verify each on-device first), App
  Information (§1), App Review notes incl. the comped demo account (§5).

### 8. Distribute
- Internal testers (instant). External testers → one-time Beta App Review.

### 9. Public release (later)
- Screenshots (run `aso-appstore-screenshots`), description/keywords, submit the
  version + subscriptions for review.

---

## D. Server prerequisite for comping accounts
Set `ADMIN_TOKEN` in `/opt/obsidian-claudebrain/.env.production` on the VPS
(strong random value), then redeploy or restart the app, before using the
tier-override endpoint in §B. Keep this token secret (GitHub secret / 1Password).

> Legal text is reasonable defaults, **not legal advice** — have counsel review
> before public launch.
