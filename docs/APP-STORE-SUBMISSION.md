# App Store Connect Submission Package — LuminaVault

Everything to fill in App Store Connect (ASC) for TestFlight + public release.
Code/config side is done; this is the portal-side data to paste. Items marked
**[decide]** need your final call; **[verify]** means confirm against the build.

- **Bundle ID:** `com.lumina.fernando`
- **Team ID:** `84X9WYBF36`
- **API base (Release):** `https://api.luminavault.fyi` (live)
- **Privacy Policy URL:** `https://luminavault.fyi/privacy`
- **Terms (EULA) URL:** `https://luminavault.fyi/terms`
- **Marketing version:** `1.0` · **Build:** CI `github.run_number`

---

## 1. App Information

| Field | Value |
| --- | --- |
| Name (30 char) | LuminaVault **[decide]** |
| Subtitle (30 char) | Your AI knowledge vault **[decide]** |
| Primary category | Productivity |
| Secondary category | Utilities **[decide]** |
| Content rights | Does **not** contain third-party content |
| Age rating | Complete questionnaire → likely **17+** (unrestricted AI-generated content + user-generated content). **[decide]** |
| Privacy Policy URL | `https://luminavault.fyi/privacy` |
| License agreement | Apple standard EULA, or link `https://luminavault.fyi/terms` |
| Support URL | `https://luminavault.fyi` **[decide — needs a support page/email]** |
| Marketing URL (optional) | `https://luminavault.fyi` |

**Description / keywords / promo text** — draft separately; not blocking TestFlight
(internal testing needs no store listing). Required for public release.

---

## 2. App Privacy (the "nutrition label")

Source of truth = `LuminaVaultClient/PrivacyInfo.xcprivacy`. Mirror these in
ASC → App Privacy. All are **linked to the user's identity** (account-based app)
and **not used for tracking** (no ad/attribution SDKs) — **[verify]** you do not
run ATT-tracking; if PostHog is configured for cross-app/3rd-party linkage, flip
"Tracking" to Yes and add an ATT prompt.

| Data type | Category | Purpose | Linked | Tracking |
| --- | --- | --- | --- | --- |
| Email address | Contact Info | App Functionality, Account | Yes | No |
| Phone number | Contact Info | App Functionality (phone auth) | Yes | No |
| Health | Health & Fitness | App Functionality | Yes | No |
| Photos or Videos | User Content | App Functionality | Yes | No |
| Other user content (notes/vault/messages) | User Content | App Functionality | Yes | No |
| Customer support / other content | User Content | App Functionality | Yes | No |
| User ID | Identifiers | App Functionality | Yes | No |
| Purchase history | Purchases | App Functionality | Yes | No |
| Product interaction | Usage Data | Analytics | Yes | No |
| Crash data | Diagnostics | App Functionality | Yes | No |
| Performance data | Diagnostics | Analytics | Yes | No |

SDKs behind each: **Sentry** (crash/performance), **PostHog** (product
interaction/analytics), **RevenueCat** (purchase history), **Apple/Google Sign-In**
(email/user ID), **HealthKit** (health), photo picker (photos). Health, Photos,
and user content are **never** used for ads and not sold (matches Privacy Policy).

> HealthKit reminder: App Review checks that Health usage strings are specific
> and that Health data isn't used for advertising/data-mining. Both hold here.

---

## 3. App Accessibility (Accessibility Nutrition Labels)

ASC → App version → Accessibility. Declare only what the build genuinely
supports. **[verify each on-device]**:

- [ ] **VoiceOver** — labels on controls/images
- [ ] **Voice Control**
- [ ] **Larger Text (Dynamic Type)** — text scales with system size
- [ ] **Sufficient Contrast**
- [ ] **Reduced Motion** — honor `accessibilityReduceMotion` (esp. Rive/graph animations)
- [ ] **Captions** (only if you ship video/audio with speech)

SwiftUI gives VoiceOver + Dynamic Type largely for free; audit custom views
(graph canvas, paywall, Rive animations) before ticking. Don't claim a feature
you haven't tested — Apple can reject for false accessibility claims.

---

## 4. Monetization — In-App Purchases (auto-renewable subscriptions)

ASC → Features → Subscriptions. One **Subscription Group**: `LV Subscriptions`
(all four products → StoreKit treats them as upgrade/downgrade of one sub).
Product IDs must match `Services/Billing/RCProduct.swift` **verbatim**.

| Product ID | Reference name | Price | Intro offer | Entitlement |
| --- | --- | --- | --- | --- |
| `pro_monthly_9_99` | Pro Monthly | $9.99 / mo | 7-day free trial, once/user | `pro` |
| `pro_yearly_79_99` | Pro Yearly | $79.99 / yr | — | `pro` |
| `ultimate_monthly_19_99` | Ultimate Monthly | $19.99 / mo | 7-day free trial, once/user | `ultimate` |
| `ultimate_yearly_179_99` | Ultimate Yearly | $179.99 / yr | — | `ultimate` |

Each product needs a non-empty **localized display name + description** or it
stays "Missing Metadata". Add the 7-day **Introductory Offer → Free trial** on
the two monthly products.

**RevenueCat dashboard** (full steps in `docs/revenuecat-appstore-setup.md`):
link iOS app `com.lumina.fernando`, paste ASC shared secret + ASC API key,
import the 4 product IDs, map `pro`/`ultimate` entitlements, build the `default`
offering (4 packages, lowest tier first). Put `LV_RC_API_KEY` (the public
`appl_*` key) in `Config/Config.Release.xcconfig` (env vars don't reach archives).

**Required in the binary** (App Review rejects subs without these — **[verify]** present in PaywallView):
- Title + price + duration of each sub
- Auto-renew disclosure text
- Functional links to Privacy Policy + Terms (EULA)
- A visible **Restore Purchases** button

---

## 5. App Review notes

- **Demo account:** create one and paste credentials (email + password / phone +
  fixed code) so review can sign in without OTP friction. **[decide]**
- **IAP review:** submit at least one subscription "for review" attached to this
  app version. Note in review notes that tiers gate AI/feature limits.
- **Sign in with Apple** is present (required when other social logins exist — satisfied).
- **AI content note:** state that AI responses are generated by an LLM and the app
  includes content moderation / acceptable-use terms.

---

## 6. Screenshots (required for public release; not for internal TestFlight)

Need 6.9" (iPhone 16 Pro Max) and 6.5" sets minimum. Optional: run the
`aso-appstore-screenshots` skill to generate ASO-optimized shots from the codebase.

---

## 7. Order of operations

1. Apple Developer portal: App ID `com.lumina.fernando` + capabilities (HealthKit,
   Sign in with Apple, Push, Associated Domains, App Groups `group.com.lumina.fernando`,
   Keychain Sharing). Same for the share-extension App ID.
2. ASC: create the app record (bundle `com.lumina.fernando`).
3. ASC: create subscription group + 4 products (§4). RevenueCat wiring.
4. `fastlane match appstore --app_identifier com.lumina.fernando` (seed certs to a private match repo).
5. Add the GitHub secrets (see `TESTFLIGHT.md` / fastlane env).
6. `gh workflow run testflight.yml` → build + upload.
7. ASC: fill App Privacy (§2), Accessibility (§3), App Information (§1), review notes (§5).
8. TestFlight: internal testers (no review) → external testers (Beta App Review).
9. Public release: screenshots (§6), description, submit version + subscriptions for review.

> Legal pages are live at `https://luminavault.fyi/privacy` and `/terms`
> (served by the production Caddy). Have counsel review the generated text before
> public launch — the drafts are reasonable defaults, not legal advice.
