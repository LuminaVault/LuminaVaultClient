<wizard-report>
# PostHog post-wizard report

The wizard has completed a deep integration of PostHog analytics into LuminaVaultClient, a Swift/SwiftUI iOS app. The integration covers user identification, all authentication paths, core onboarding conversion events, feature engagement actions, and churn signals.

**Changes made:**

- **`LuminaVaultClient.xcodeproj/project.pbxproj`** — Added `posthog-ios` as an `XCRemoteSwiftPackageReference` (minimum version 3.0.0, upToNextMajor), plus a `PBXBuildFile` and `XCSwiftPackageProductDependency` wired into the main app target's Frameworks phase and `packageProductDependencies`.
- **`xcshareddata/xcschemes/LuminaVaultClient.xcscheme`** + **`LuminaVaultClient-Beta.xcscheme`** — Added `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST` environment variables to each scheme's Run LaunchAction.
- **`LuminaVaultClientApp.swift`** — Added `PostHogEnv` enum (reads from `ProcessInfo.processInfo.environment`), initialises `PostHogSDK.shared` with `captureApplicationLifecycleEvents = true`.
- **`App/AppState.swift`** — On `handleAuthSuccess`: calls `PostHogSDK.shared.identify()` with the user's UUID and email. On `signOut`: captures `user_signed_out` then calls `PostHogSDK.shared.reset()`.
- **`Features/Auth/AuthViewModel.swift`** — Captures `auth_signed_in` (email), `auth_signed_up`, `auth_signed_in_sso` (with `provider` property), `auth_signed_in_phone`, and `auth_signed_in_email_magic`.
- **`Features/Vault/CreateVaultViewModel.swift`** — Captures `vault_created` on successful vault initialisation.
- **`Features/KB/SyncAndLearnViewModel.swift`** — Captures `kb_compile_completed` with `memories_ingested` and `duration_ms` properties.
- **`Features/Spaces/SpacesViewModel.swift`** — Captures `space_created` (with `space_slug`, `category`) and `space_deleted`.
- **`Features/Vault/VaultSearchViewModel.swift`** — Captures `vault_search_performed` with `memory_hits` and `file_hits` counts.
- **`Features/Settings/PrivacyDataViewModel.swift`** — Captures `account_data_exported` (with `size_bytes`) and `account_deleted`.
- **`Features/Settings/HermesGatewayViewModel.swift`** — Captures `hermes_gateway_configured` (with `verified` bool) and `hermes_gateway_disconnected`.

| Event | Description | File |
|-------|-------------|------|
| `auth_signed_in` | User signed in with email/password | `Features/Auth/AuthViewModel.swift` |
| `auth_signed_up` | User registered a new account | `Features/Auth/AuthViewModel.swift` |
| `auth_signed_in_sso` | User signed in via Apple/Google/X SSO | `Features/Auth/AuthViewModel.swift` |
| `auth_signed_in_phone` | User signed in via phone OTP | `Features/Auth/AuthViewModel.swift` |
| `auth_signed_in_email_magic` | User signed in via email magic link | `Features/Auth/AuthViewModel.swift` |
| `user_signed_out` | User signed out (identity reset follows) | `App/AppState.swift` |
| `vault_created` | User completed Create My Vault onboarding | `Features/Vault/CreateVaultViewModel.swift` |
| `kb_compile_completed` | Sync & Learn KB compile succeeded | `Features/KB/SyncAndLearnViewModel.swift` |
| `space_created` | User created a new Space | `Features/Spaces/SpacesViewModel.swift` |
| `space_deleted` | User deleted a Space | `Features/Spaces/SpacesViewModel.swift` |
| `vault_search_performed` | User ran a universal vault search | `Features/Vault/VaultSearchViewModel.swift` |
| `account_data_exported` | User exported their vault data (GDPR) | `Features/Settings/PrivacyDataViewModel.swift` |
| `account_deleted` | User permanently deleted their account | `Features/Settings/PrivacyDataViewModel.swift` |
| `hermes_gateway_configured` | User saved a BYO-Hermes Gateway config | `Features/Settings/HermesGatewayViewModel.swift` |
| `hermes_gateway_disconnected` | User removed their Hermes Gateway config | `Features/Settings/HermesGatewayViewModel.swift` |

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behavior, based on the events we just instrumented:

- [Analytics basics dashboard](/dashboard/1595508)
- [New sign-ups over time](/insights/DTdxZuct) — daily registration trend
- [Sign-in method breakdown](/insights/JM9DJUwK) — email vs SSO vs phone vs magic link
- [Onboarding conversion funnel](/insights/jyFHTvhL) — sign-up → vault creation conversion rate
- [Vault search engagement](/insights/a4VXf4hy) — total searches and unique searching users per day
- [Churn signals](/insights/EvwU3O6B) — account deletions and data exports as leading churn indicators

### Agent skill

We've left an agent skill folder in your project at `.claude/skills/integration-swift/`. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
