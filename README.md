# LuminaVaultClient

Native iOS client for **LuminaVault** — your personal knowledge guardian. Captures everything from your phone, compiles it into a private Markdown vault, and lets Lumina (the AI) remember, organise, and surface it back to you.

This app is the front door to [LuminaVaultServer](../LuminaVaultServer): an OpenAPI-first Hummingbird 2 backend (Swift 6) that owns your vault, your Hermes Profile, and your semantic memory. The client never touches third-party clouds — it talks only to your own server, hosted on your own VPS.

## Meet Lumina

He's your personal knowledge guardian — a wise, curious companion who never forgets and always learns from you. Lumina will:

- **Capture everything effortlessly** — screenshots, photos from your gallery, Apple Maps locations, HealthKit data, Safari links, notes, and more — all saved as clean Markdown in your private vault.
- **Compile and organize your memories** with one tap using `kb-compile` — turning raw notes into a smart, searchable wiki.
- **Learn your habits and patterns** over time so he understands how you think, work, and live.
- **Answer any question** about your past with perfect context — no more digging through old notes.
- **Generate smart memos and creative ideas** from everything you've captured.
- **Send quiet, intelligent nudges** only when something actually matters (sleep trends, unusual patterns, opportunities, etc.).
- **Keep it all 100% private** — your data never leaves your own VPS or iPhone.

LuminaVault is Obsidian with a living memory. Built for you. Hosted by you. Powered by Hermes.

## Responsibilities

The client is responsible for everything that has to happen on-device:

- **Authentication UX** — email/password, magic-link, phone OTP, Apple/Google/X SSO, WebAuthn passkeys, biometric unlock.
- **Capture pipelines** — Share Sheet (Safari URLs), screenshot intake, photo library, Apple Maps locations, voice notes, manual text.
- **HealthKit ingestion** — read sleep, activity, mindfulness, workouts → ship to `/v1/capture` and `/v1/memory/upsert`.
- **Vault navigation** — browse and read the user's per-tenant Markdown vault streamed from the server.
- **Visual Search** — on-device OCR + server-side semantic search (HER-157).
- **Real-time channel** — open a WebSocket to `/v1/ws` for live Lumina nudges and broadcast events.
- **Local cache + offline reads** — encrypted on-device cache backed by Keychain-stored secrets.

All authority over **what gets stored** lives in the server: the client is a thin tenant-scoped UI over [the OpenAPI contract](../LuminaVaultServer/Sources/AppAPI/openapi.yaml).

## Tech stack

- **Swift 5 / SwiftUI** (iOS 26.4+, Xcode project — no `Package.swift`).
- **swift-openapi-generator** consumes [the server's `openapi.yaml`](../LuminaVaultServer/Sources/AppAPI/openapi.yaml) to generate a typed `AppAPIClient`. Same source of truth as the server, no hand-rolled networking.
- **HealthKit** — sleep, activity, workouts, mindfulness.
- **Local Authentication** — Face ID / Touch ID gate on app open.
- **Keychain Services** — access/refresh JWT and biometric-gated secrets.
- **Sign-in providers** — AuthenticationServices (Apple), [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS), custom OAuth dance for X.
- **[rive-ios](https://github.com/rive-app/rive-ios)** — Hermie mascot animations (HER-40).

## Project structure

```
LuminaVaultClient/
├── LuminaVaultClientApp.swift          # @main; splash → biometrics → auth gate
├── App/
│   ├── AppState.swift                   # global @Observable state
│   ├── HealthKitCoordinator.swift       # HealthKit auth + sync loop
│   └── Telemetry.swift                  # client-side metrics
├── API/                                 # generated + hand-written API layer
│   ├── Core/                            # AppAPIClient, transport, auth middleware
│   ├── Auth/                            # login, register, refresh, MFA, OAuth
│   ├── Memory/                          # /v1/memory upsert / search / get
│   ├── Health/                          # /v1/health probes
│   └── Settings/                        # /v1/settings, /v1/me
├── Features/
│   ├── Auth/                            # sign-in, sign-up, SSO, password reset
│   ├── Onboarding/                      # first-run flow + BYO gateway step (HER-219)
│   ├── Settings/
│   ├── VisualSearch/                    # HER-157
│   ├── MainTabView.swift                # root tab container
│   └── LVSplashView.swift               # launch screen
├── Services/                            # AppleSignInService, GoogleSignInService,
│   │                                    # XSignInService, BiometricsService,
│   │                                    # HealthKitService, ImageOCRService,
│   │                                    # KeychainService
├── Components/                          # reusable SwiftUI views
├── Utilities/                           # extensions, formatters, helpers
├── Resources/                           # Rive .riv assets, fonts, copy
└── Assets.xcassets/                     # icons, colors, mascot stills
```

## Prerequisites

- Xcode 26+ / iOS 26.4 SDK.
- A reachable [LuminaVaultServer](../LuminaVaultServer) — local (`http://127.0.0.1:8080`) or your VPS over HTTPS.
- For SSO: Apple Sign-in capability, Google OAuth client ID, X OAuth app.

## Running locally

1. Boot the server (`./setup.sh` in `LuminaVaultServer`).
2. Open `LuminaVaultClient.xcodeproj`.
3. Set the dev base URL in `App/AppState.swift` (default points at `http://127.0.0.1:8080`).
4. Pick a simulator or device, run.

The first launch goes splash → biometric prompt → auth gate. Onboarding (HER-219) optionally lets the user point the client at a self-hosted Hermes gateway before signing in.

## Auth & Tenancy (client side)

The server is tenant-first: every domain row carries `tenant_id` (= the user's UUID). The client mirrors that model:

- **One device = one tenant.** Login binds the device's Keychain to a single `tenant_id` derived from the JWT `sub` claim.
- **Bearer auth** — `AppAPIClient`'s transport middleware injects `Authorization: Bearer <access>`; 401s trigger refresh-token rotation via `/v1/auth/refresh`.
- **Biometric gate** — Face ID / Touch ID unlocks Keychain-stored refresh tokens on launch; without biometrics the user must re-enter credentials.
- **Hermes Profile** — provisioned on register/SSO-create by the server (1:1, isolated memory). The client never sees other tenants' data.

## API contract

All HTTP / WebSocket calls go through the typed `AppAPIClient` generated from [`../LuminaVaultServer/Sources/AppAPI/openapi.yaml`](../LuminaVaultServer/Sources/AppAPI/openapi.yaml). Coverage today: 65 operations across Auth, Memory, Vault, Capture, Query, Memos, Skills, KB, LLM, Admin, Health, Me, Settings, Spaces, Onboarding, Achievements, Devices, WebSocket, plus the Hermes profile surface.

For interactive exploration, see the regenerated Bruno collection at [`LuminaVaultCollection/LuminaVaultServer/`](../LuminaVaultCollection/LuminaVaultServer) (HER-230). To regenerate after the OpenAPI spec changes, run `make bruno-regen` in the server repo.

## Adding a new endpoint call

1. Server adds the operation to `openapi.yaml` and implements the handler (see [server README](../LuminaVaultServer/README.md#adding-a-new-endpoint)).
2. Re-resolve SPM in the client so the generated `AppAPIClient` picks up the new operation.
3. Wrap the generated method in a feature-level service (e.g. `MemoryService` in `API/Memory/`).
4. Call from the SwiftUI feature with `@Observable` state. Errors surface as typed `AppAPIError`.

## Environments

| Track | Bundle ID | Xcode config | Ship with |
| --- | --- | --- | --- |
| **App Store** | `com.lumina.fernando` | Release | `bundle exec fastlane release` |
| **TestFlight** | `com.lumina.fernando.beta` | Beta | `bundle exec fastlane beta` |
| **Local** | `com.lumina.fernando.test` | Debug | Xcode Run |

Each bundle id has its own push topic and OAuth audience. Switching environments wipes Keychain — by design, so prod tokens never bleed into test.

Build-time public configuration is supplied through gitignored xcconfig files copied from `LuminaVaultClient/Config/Config.*.xcconfig.sample`. Those files define the hosted API URL, Apple/Google/X OAuth IDs, RevenueCat public SDK key, PostHog keys, Sentry DSN, and legal URLs. See [`LuminaVaultClient/Config/README.md`](LuminaVaultClient/Config/README.md) and [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) (Fastlane + CI).

## Logo assets

| # | Name | Description | Best for |
|---|------|-------------|----------|
| 1 | **Primary Brand Mark** | Full "LuminaVault" wordmark + integrated glowing "L" symbol | Most official uses |
| 2 | **Symbolic Icon-Only** | Glowing cyan scroll + golden wings + neural vault lock | Small spaces & icons |
| 3 | **Hero / Onboarding** | Wordmark + small Hermie mascot holding the glowing scroll | Splash & onboarding screens |
| 4 | **Animated Primary** | Pulsing cyan glow + floating particles + energy trails | Loading states & dynamic screens |
| 5 | **Animated Symbolic** | Fluttering wings + pulsing neural circuits + scroll glow | Compact animated uses |

## Related repos

- **[LuminaVaultServer](../LuminaVaultServer)** — Swift 6 / Hummingbird 2 backend, OpenAPI-first.
- **[LuminaVaultShared](../LuminaVaultShared)** — shared DTO + protocol package consumed by both client and server.
- **[LuminaVaultCollection](../LuminaVaultCollection)** — Bruno collection of every API request (auto-generated + manual).
