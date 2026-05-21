# LuminaVaultShareExtension (HER-258)

iOS Share Extension target. Receives URLs from Safari / X / YouTube /
Reader via the system share sheet and queues them into the App Group
container; the main app's `CaptureCoordinator` replays the queue into
`CaptureQueue` on next launch, and `CaptureDrainer` posts to
`POST /v1/capture/safari` (HER-149).

## Xcode target setup (one-time, manual)

The Swift source + entitlements + `Info.plist` in this directory are
ready to drop into a new Xcode target. The target itself must be
created via Xcode UI (Claude can't safely synthesise the `.pbxproj`
entries by hand):

1. **File → New → Target… → iOS → Share Extension.**
2. **Product name:** `LuminaVaultShareExtension`.
3. **Team / signing:** same as the main `LuminaVaultClient` target.
4. **Embed in Application:** `LuminaVaultClient`.
5. Xcode generates a scaffold — **delete** the auto-created
   `ShareViewController.swift`, `MainInterface.storyboard`, and the
   default `Info.plist`.
6. **Drag this folder's files into the new target's group** in the
   navigator: `ShareViewController.swift`, `ShareRootView.swift`,
   `ShareViewModel.swift`, `Info.plist`,
   `LuminaVaultShareExtension.entitlements`.
   - Confirm target membership = `LuminaVaultShareExtension` only.
7. **Add target membership** of these existing files in the
   `LuminaVaultClient/Services/AppGroup/` folder to the extension
   target (the same files stay in the main app target too — checkbox
   both):
   - `SharedAppGroup.swift`
   - `PendingShare.swift`
   - `SharedShareQueue.swift`
   - **Do NOT** add `SharedSpacesCache.swift` (imports
     `LuminaVaultShared` — main app only).
8. Build Settings on the extension target:
   - **Code Signing Entitlements** → point at
     `LuminaVaultShareExtension/LuminaVaultShareExtension.entitlements`.
   - **Info.plist File** → point at
     `LuminaVaultShareExtension/Info.plist`.
   - **Product Bundle Identifier**:
     - Debug: `com.lumina.fernando.test.share`
     - Release: `com.lumina.fernando.share`
   - **Skip Install** → `NO`.
9. Add an **App Group** capability to the main `LuminaVaultClient`
   target as well: Signing & Capabilities → `+` → App Groups →
   `group.com.lumina.fernando`. Xcode appends the entitlement to the
   app's `.entitlements` file.
10. Open Apple Developer portal → App IDs → confirm both bundle ids
    have **App Groups** enabled and the `group.com.lumina.fernando`
    group is registered. Regenerate provisioning profiles if Xcode
    prompts.

## Verification

1. Build + run the app once to provision the App Group container.
2. From Safari, share any URL → tap **LuminaVault** in the share sheet.
3. Confirm: URL preview, optional note field, Space picker (if any
   Spaces exist), Save dismisses the sheet.
4. Reopen the LuminaVault app. The shared URL should appear in the
   vault within a few seconds (`CaptureDrainer` ticks on startup).

## File layout

```
LuminaVaultShareExtension/
├── README.md                                  (this file)
├── Info.plist                                 (activation rules + principal class)
├── LuminaVaultShareExtension.entitlements     (App Group)
├── ShareViewController.swift                  (UIKit entry point)
├── ShareRootView.swift                        (SwiftUI: URL + note + Space picker)
└── ShareViewModel.swift                       (@Observable; writes to App Group)
```

## Shared files (compiled into both targets)

```
LuminaVaultClient/Services/AppGroup/
├── SharedAppGroup.swift          App Group root URL + Codable I/O
├── PendingShare.swift            wire shape extension → host
├── SharedShareQueue.swift        append / drain helpers
└── SharedSpacesCache.swift       host-only writer (imports LuminaVaultShared)
```

## Out of scope (HER-258 v1)

- No direct network from the extension — all `/v1/capture/safari`
  traffic flows through the host app's `CaptureDrainer`.
- No Sentry / PostHog SDKs in the extension target (memory budget).
- No "sign in from the extension" affordance — when the host app has
  never been launched the share lands in the queue and processes on
  first launch post-sign-in.
