# RevenueCat + App Store Connect setup (HER-271)

Click-by-click runbook for the **manual dashboard work** that makes LuminaVault subscriptions sellable. The iOS code (`Services/Billing/`) is already shipped; this doc covers the App Store Connect and RevenueCat console steps that no code change can perform.

**Source of truth is the code, not this doc.** Product IDs and entitlement IDs must match `Services/Billing/RCProduct.swift` and `RCEntitlement` in `Services/Billing/BillingService.swift` **verbatim, case-sensitive**. A mismatch silently breaks tier resolution (the app sees no active entitlement and never elevates the tier).

## Products to configure

Four products, two entitlements, one offering. Per `RCProduct.swift`:

| Product ID | Price | Intro offer | Entitlement |
| --- | --- | --- | --- |
| `pro_monthly_9_99` | $9.99 / month | 7-day free trial, once per user | `pro` |
| `pro_yearly_79_99` | $79.99 / year | — | `pro` |
| `ultimate_monthly_19_99` | $19.99 / month | 7-day free trial, once per user | `ultimate` |
| `ultimate_yearly_179_99` | $179.99 / year | — | `ultimate` |

Offering id: `default`. Bundle id (Release): `com.lumina.fernando`.

---

## 1. App Store Connect

App Store Connect → your app → **Subscriptions**.

1. **Create the subscription group** named `LV Subscriptions`. All four products live in this one group (so StoreKit treats them as upgrade/downgrade/crossgrade of the same subscription).
2. **Create each of the four products** with the exact Product ID, reference name, and price from the table above.
   - For the two monthly products, add an **Introductory Offer** → *Free trial* → **7 days** → **once per user** (matches the 7-day trial baked into the paywall copy).
   - The yearly products have no intro offer.
3. **Localization (en, primary):** for each product add a display name, description, and the marketing copy. Screenshot placeholders are fine until final paywall art lands, but the field must be non-empty or the product stays in "Missing Metadata".
4. **Enable the In-App Purchase capability** on the app target (Xcode → target → *Signing & Capabilities* → **+ Capability** → *In-App Purchase*) if not already present.
5. **App Review paywall screenshot:** upload a screenshot of `PaywallView` for App Review §3.1.2. It must show **Restore Purchases** and linked **Terms** / **Privacy** (HIG requirement). The legal links are driven by `LV_TERMS_URL` / `LV_PRIVACY_URL` in the active `Config.<env>.xcconfig`.

> Products stay in "Ready to Submit" / "Waiting for Review" until attached to an app version submission. RevenueCat can read them in sandbox before they're approved, so dashboard wiring (below) does not block sandbox testing.

---

## 2. RevenueCat dashboard

RevenueCat → project → **Project settings** and **Offerings**.

1. **Link the iOS app**: App settings → add iOS app with bundle id `com.lumina.fernando`. Paste the App Store Connect shared secret and the App Store Connect API key so RC can validate receipts and receive server notifications.
2. **Import products**: Products tab → add all four App Store product IDs exactly as above.
3. **Entitlements** (Entitlements tab) — IDs are **case-sensitive** and MUST equal the constants in `BillingService.swift`:
   - `pro` → attach `pro_monthly_9_99` and `pro_yearly_79_99`
   - `ultimate` → attach `ultimate_monthly_19_99` and `ultimate_yearly_179_99`
4. **Offering** `default` (Offerings tab) — create one offering with id `default` containing four packages: monthly + yearly per tier, lowest tier first (presentation order matches `RCProduct.all`).
5. **Server-to-server webhook**: Integrations → Webhooks →
   - URL: `POST https://api.luminavault.com/v1/billing/webhooks/revenuecat`
   - Authorization header bearer token must equal the server's `revenueCatWebhookSecret` (`LuminaVaultServer` `App+build.swift`), which is set in the Hetzner VPS `.env`. **If these don't match, the server rejects every webhook and tiers never update server-side.**

---

## 3. SDK key + sandbox

- **Public SDK key** (`appl_*`): safe to ship in the binary. It reaches the app two ways (`Utilities/Config.swift` → `Config.revenueCatPublicKey`):
  - **Debug (local dev):** `REVENUECAT_PUBLIC_KEY` env var in the `LuminaVaultClient` scheme. The scheme ships a **disabled placeholder** — enable it and paste the real `appl_*` key locally (do not commit the real key).
  - **Beta / Release (archives):** `LV_RC_API_KEY` in `Config/Config.Beta.xcconfig` / `Config.Release.xcconfig`, substituted into `Config/Info.plist` via `$(LV_RC_API_KEY)`. Env vars do **not** apply to archives, so this xcconfig path is the only one that works on TestFlight/Release. See `Config/README.md` for the file-based Info.plist + xcconfig wiring required in the Xcode project.
- **Do NOT** put the RevenueCat **secret** key anywhere in the client — that one is server-only.
- **Sandbox tester:** App Store Connect → Users and Access → **Sandbox** → Testers → create one. Sign out of the App Store on the test device, then sign in with the sandbox account when prompted during purchase. **Document the sandbox credentials + the public `appl_*` key in 1Password** (LuminaVault vault).

---

## 4. Acceptance

Run the **Verification checklist** in [`Services/Billing/README.md`](../LuminaVaultClient/Services/Billing/README.md). Headline criteria:

- A fresh sandbox purchase of `pro_monthly_9_99` on a real iPhone elevates `BillingService.currentTier` to `.pro` within 60 s (webhook lands, `GET /v1/auth/me/billing` echoes the new tier).
- `PaywallView` renders all four products with correctly localized 7-day-trial copy.
- App Review screenshot passes HIG (Restore Purchases + Terms/Privacy visible).
