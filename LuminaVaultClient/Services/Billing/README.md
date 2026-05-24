# Billing — RevenueCat + StoreKit 2 wiring

Stack overview, soft-failure contract, and the work that still needs to land for the iOS client to actually sell subscriptions. Reference for anyone touching `Services/Billing/`, `Features/Billing/`, or the paywall flow.

---

## Layout

```
LuminaVaultClient/Services/Billing/
├─ PurchasesProxy.swift          ← protocol seam (no RevenueCat import)
├─ LiveRevenueCatProxy.swift     ← production conformance (only file outside the app entrypoint that imports RevenueCat)
├─ BillingService.swift          ← @MainActor @Observable. UI consumes this.
└─ RCProduct.swift               ← canonical SKU constants (HER-211)
```

```
LuminaVaultClient/Features/Billing/
├─ PaywallView.swift             ← wraps RevenueCatUI.PaywallView, surfaces request-review on success (HER-298)
└─ TrialCountdownBanner.swift    ← Today + Settings header banner (HER-211)
```

Server-truth read:
```
LuminaVaultClient/API/Billing/
├─ BillingEndpoints.swift        ← GET /v1/auth/me/billing
├─ BillingClientProtocol.swift
└─ BillingHTTPClient.swift
```

Tickets that shipped this stack (in order): **HER-185** (BillingService + RC SDK), **HER-188** (paywall + EntitlementGate), **HER-211** (paywall sheet + universal 402 interceptor + Manage Subscription + trial banner), **HER-298** (App Review prompt + About pane + social links).

---

## Soft-failure contract

The app boots without a RevenueCat public key on:

- Debug schemes that don't set `REVENUECAT_PUBLIC_KEY` in their env block.
- TestFlight / Ad-Hoc builds shipped before HER-271 lands the real `LV_RC_API_KEY` xcconfig value.
- Any future env unwind where the key is rotated.

Two layers protect against this:

### Layer 1 — `Purchases.configure(...)` is gated at the app entrypoint

`LuminaVaultClientApp.init()` only calls `Purchases.configure(...)` when `Config.revenueCatPublicKey != nil`. Missing key emits a Sentry breadcrumb and continues booting.

### Layer 2 — `LiveRevenueCatProxy` guards every method on `Purchases.isConfigured`

RC's `Purchases.shared` accessor traps via `fatalError` when configure hasn't run. Every proxy method checks `Purchases.isConfigured` first:

| Method | When configured | When NOT configured |
|---|---|---|
| `logIn` / `logOut` | calls `Purchases.shared.*` | silent no-op |
| `customerInfo` | returns real snapshot | returns empty `RCCustomerInfoSnapshot` |
| `customerInfoStream` | streams real RC pushes | finished stream (BillingService for-await exits) |
| `purchase(productID:)` | StoreKit purchase sheet | throws `BillingUnavailableError` |
| `restorePurchases` | RC restore | throws `BillingUnavailableError` |

Behaviour in the unconfigured case is **"the rest of the app keeps working; billing falls back to server-truth only."** `BillingService.bootstrap` still runs, still hits `GET /v1/auth/me/billing`, still surfaces `currentTier`. The paywall just can't actually sell anything.

This was the [hotfix](https://github.com/LuminaVault/LuminaVaultClient/pull/80) (commit `0b2fdbd`) for the crash:

```
RevenueCat/Purchases.swift:73: Fatal error: Purchases has not been configured.
```

Login succeeded → `BillingService.bootstrap` → `purchases.logIn(...)` → `Purchases.shared.logIn(...)` → crash. The HER-185 design intended Layer 1 to be sufficient, but missed that the proxy itself touches `Purchases.shared`.

---

## What's missing for production (HER-271 + dashboard work)

To make Layer 2 a no-op in real builds (i.e. RC actually configured everywhere), the following still has to ship:

### 1. App Store Connect

| Item | Status |
|---|---|
| Subscription group `LV Subscriptions` | TODO |
| Product `pro_monthly_14_99` ($14.99/mo, 7d intro trial) | TODO |
| Product `pro_yearly_149_99` ($149.99/yr, 7d intro trial) | TODO |
| Product `ultimate_monthly_29_99` ($29.99/mo, 7d intro trial) | TODO |
| Product `ultimate_yearly_299_99` ($299.99/yr, 7d intro trial) | TODO |
| Sandbox test users provisioned | TODO |
| Paywall screenshot uploaded for App Review §3.1.2 | TODO |
| In-App Purchase capability enabled on app target | TODO (Xcode UI → Signing & Capabilities) |

Product IDs must match `RCProduct` constants verbatim — case-sensitive. See `RCProduct.swift`.

### 2. RevenueCat dashboard

| Item | Status |
|---|---|
| iOS app linked (bundle ID `com.lumina.fernando`) | TODO |
| Offering `default` configured | TODO |
| Packages in `default`: monthly + yearly per tier (4 total) | TODO |
| Entitlement `pro` mapped to `pro_monthly_14_99` + `pro_yearly_149_99` | TODO (entitlement ID must match `RCEntitlement.pro` in `BillingService.swift`) |
| Entitlement `ultimate` mapped to `ultimate_monthly_29_99` + `ultimate_yearly_299_99` | TODO (must match `RCEntitlement.ultimate`) |
| S2S webhook → `POST https://api.luminavault.com/v1/billing/webhooks/revenuecat` | TODO — auth via `revenueCatWebhookSecret` bearer (server: `App+build.swift`) |
| Server's `revenueCatWebhookSecret` env value matches the dashboard | TODO — set on Hetzner VPS `.env` |

### 3. Public SDK key (`appl_*`) wiring

| Surface | Status |
|---|---|
| `Config.revenueCatPublicKey` reader (env > Info.plist) | DONE (`Config.swift`, HER-185) |
| Debug scheme: `REVENUECAT_PUBLIC_KEY` env var set in Xcode scheme editor | TODO |
| Release xcconfig: `LV_RC_API_KEY` populated, fed into Info.plist via `$(LV_RC_API_KEY)` substitution | TODO |
| Info.plist key `LV_RC_API_KEY` present | DONE (HER-185 — substitution placeholder) |

Public RC keys (`appl_*`) are safe to ship in the binary. Do NOT put the **secret** (server-side) key here — that one belongs on the VPS only.

### 4. Server-side enforcement

| Item | Status |
|---|---|
| Server billing rails (`/v1/auth/me/billing`, `EntitlementMiddleware`, webhook handler) | DONE (HER-184) |
| Production flag `BILLING_ENFORCEMENT_ENABLED=true` on VPS | TODO — tracked by HER-286 (launch-day flip) |

Once the flip lands, the 8 `EntitlementMiddleware` mount points start returning `402 { paywall_id, required_tier }` for users below their required tier. iOS already handles this:

- `BaseHTTPClient` raises `APIError.paymentRequired(paywallID:requiredTier:)` from all three I/O paths.
- `AppState.pendingPaywallID` is set via the universal `onPaymentRequired` callback (HER-211).
- Root `.sheet(item:)` on `LuminaVaultClientApp` presents `PaywallView` automatically.

---

## Verification checklist (after the above lands)

1. **Configure smoke**

   With the key set in the Debug scheme:
   ```
   Build + run → log shows `[Purchases] Configured for ...` from RC SDK.
   `Purchases.isConfigured == true`.
   ```

   Without the key:
   ```
   Build + run → Sentry breadcrumb "RevenueCat key missing — billing disabled for this launch".
   `Purchases.isConfigured == false`.
   Sign in → no crash. `BillingService.currentTier` reflects /v1/auth/me/billing.
   Tap Subscription → Upgrade → paywall renders, `purchase()` throws BillingUnavailableError, user sees error toast.
   ```

2. **Sandbox purchase round-trip**
   - Sign in with a sandbox Apple ID.
   - Open paywall, buy `pro_monthly_14_99`.
   - Within ≤60 s: `BillingService.currentTier == .pro`, webhook landed, server `me/billing` echoes the new tier.
   - Apple review prompt appears 2 s after success (HER-298 hook). 3-per-365-day cap; subsequent purchases silent.

3. **Restore after reinstall**
   - Buy in sandbox, delete app, reinstall, sign in.
   - Settings → Subscription → Restore Purchases.
   - `BillingService.refreshFromServer` converges with the restored entitlement.

4. **Cancel grace period**
   - Cancel via `.manageSubscriptionsSheet` (Settings → Subscription → Manage Subscription).
   - After cancel period elapses, server flips tier to `.lapsed`.
   - Next gated request returns 402, paywall sheet presents at root.

---

## Test seam

`AppState.purchasesProxyFactory` is a `@MainActor () -> PurchasesProxy` closure. Production defaults to `LiveRevenueCatProxy()`. Tests inject `MockPurchasesProxy` (see `LuminaVaultClientTests/Mocks/`):

```swift
state = AppState(...)
state.purchasesProxyFactory = { mockProxy }
state.handleAuthSuccess(.stub)
// BillingService.bootstrap now talks to mockProxy
```

Same seam handles SwiftUI previews — drop a `MockPurchasesProxy` returning hardcoded `RCCustomerInfoSnapshot` to render the paywall against a deterministic offering without hitting RC.

---

## Refs

- `LuminaVaultServer/Sources/AppAPI/openapi.yaml` — `MeBillingResponse`, `RevenueCatWebhookBody`, `TierOverrideRequest` schemas
- `LuminaVaultShared/Sources/LuminaVaultShared/APIDTOs.swift` — `UserTier`, `MeBillingResponse` (HER-185 v0.27.0+)
- Tickets: HER-184 (server), HER-185 (iOS service), HER-188 (paywall), HER-211 (universal 402), HER-271 (ASC), HER-272 (CI/CD), HER-286 (enforcement flip), HER-294 / HER-295 / HER-296 / HER-297 (HER-287 follow-ups), HER-298 (review prompt + About)
- RC SDK: `purchases-ios` 5.10+ (`Package.resolved`), `RevenueCatUI` product linked on the `LuminaVaultClient` target only
