# HealthKit setup (Xcode-side)

The Swift code is shipped (`HealthKitService`, `HealthKitCoordinator`,
`HealthKitMetricCatalog`, `HealthEndpoints.Ingest`). Three Xcode-only
steps are required before the build runs on a real device.

## 1. Capabilities

Target → **Signing & Capabilities** → **+ Capability**:

- **HealthKit** — must be enabled. After adding, tick:
  - ☑ "Background Delivery" — required for `HKObserverQuery`
    background wake-ups via `enableBackgroundDelivery`.
- **Background Modes**:
  - ☑ "Background processing"

This writes the following into `LuminaVaultClient.entitlements`:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

…and adds `processing` to `UIBackgroundModes` in Info.plist.

## 2. Info.plist usage strings

HealthKit refuses to authorize without these. Add to `Info.plist`
(target's plist or via Xcode's "Custom iOS Target Properties"):

| Key | Value |
|---|---|
| `NSHealthShareUsageDescription` | "LuminaVault syncs sleep, recovery, and activity from HealthKit so Hermes can correlate them with your notes." |
| `NSHealthUpdateUsageDescription` | (only needed if you ever write back; the current code only reads — leave blank/omit) |

## 3. App boot wiring

In your `@main` `App` struct, construct the dependency chain once:

```swift
import SwiftUI

@main
struct LuminaVaultApp: App {
    @State private var appState: AppState

    init() {
        let keychain = KeychainService.shared
        let httpClient = BaseHTTPClient(
            tokenProvider: { keychain.accessToken }
        )
        let healthKit = HealthKitCoordinator(
            service: HealthKitService(httpClient: httpClient)
        )
        _appState = State(initialValue: AppState(
            keychain: keychain,
            healthKit: healthKit
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
```

`AppState.handleAuthSuccess` calls `healthKit.start()`, which:

1. Requests authorization (one-time prompt).
2. Enables background delivery for every type in
   `HealthKitMetricCatalog.allReadTypes`.
3. Runs `syncAll` to pull deltas since the last anchor and POST them
   to `/v1/health` in 500-event chunks.

`AppState.signOut` calls `healthKit.stop()` to disable background
delivery so iOS stops waking the app.

## 4. Foreground refresh

Wire a pull-to-refresh on the dashboard:

```swift
.refreshable {
    await appState.healthKit?.sync()
}
```

## 5. Adding a metric

Add one row to `HealthKitMetricCatalog.quantityMetrics` with the
`HKQuantityTypeIdentifier`, server `type` tag, unit string, and
`HKUnit`. The service walks the catalog automatically — no other code
changes required for new quantity metrics.

For category samples (other than sleep / mindful, already wired): add a
new typed branch in `HealthKitService.syncAll`.

## 6. Testing

- iOS Simulator: HealthKit data exists if the scheme has an attached
  simulator with health data. Add samples via "Health" simulator app or
  inject via `HKHealthStore.save` in a debug build.
- Device: install on a real iPhone with paired Apple Watch for richest
  data. Trigger a fresh sync via pull-to-refresh; check Console.app for
  `subsystem == com.luminavault, category == healthkit` log lines.
- Background wake: Settings → Privacy → Health → LuminaVault → toggle
  off then on. Apple Health writes a sample (e.g. water log), watch for
  the observer firing.

## 7. Server side

POST body shape lands in `health_events` (server M14 migration).
Server-side schema, indexes, and ingest controller live in
`LuminaVaultServer/Sources/App/Health/HealthIngestController.swift`.
Bruno: `LuminaVaultServer/bruno/Health/Ingest.bru`.
