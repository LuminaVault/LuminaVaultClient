# LuminaVaultShareExtension

iOS Share Extension target for universal capture from Safari, Mail, Notes, Chrome, and any app that can share URLs, plain text, or images.

The extension first attempts direct network capture while the host app is killed. If it cannot reach the API or cannot read the shared keychain access token, it writes the payload into the App Group queue. The host app drains that queue on launch and whenever it returns to the foreground.

## Runtime Behavior

- URL shares call `POST /v1/capture/safari`.
- Plain text shares are rendered into Markdown, uploaded through `POST /v1/vault/files`, and mirrored through memory upsert.
- Image shares are uploaded through `POST /v1/vault/files` and mirrored through memory upsert.
- There is no `/v1/capture/photo` endpoint contract in the current server. Image capture uses the existing vault file upload path.
- Last-used Space is stored in App Group `UserDefaults` and preselected the next time the extension opens.
- Offline, unauthenticated, or failed direct saves are queued under the shared App Group container and replayed by `CaptureCoordinator`.

The extension intentionally does not embed Sentry or PostHog SDKs. Keep extension telemetry lightweight unless a dedicated memory-budget ticket changes that rule.

## Required Configuration

Both the host app and extension receive build settings from the same configuration family:

| Key | Used by | Notes |
| --- | --- | --- |
| `API_BASE_URL` | Share extension direct save client | Hosted backend URL, normally `https://api.luminavault.com` |
| `KEYCHAIN_ACCESS_GROUP` | Host app and extension keychain sharing | Normally `$(AppIdentifierPrefix)com.lumina.fernando.shared` |

The host app mirrors the current access token into `KEYCHAIN_ACCESS_GROUP`. The extension reads that token directly, so this value must match exactly across targets and provisioning profiles.

## Bundle IDs

Use the existing bundle identifiers:

| Configuration | Bundle ID |
| --- | --- |
| Debug | `com.lumina.fernando.test.LuminaVaultShareExtension` |
| Beta | `com.lumina.fernando.beta.LuminaVaultShareExtension` |
| Release | `com.lumina.fernando.LuminaVaultShareExtension` |

## Apple Capabilities

Host app:

- App Groups: `group.com.lumina.fernando`
- Keychain Sharing: `$(KEYCHAIN_ACCESS_GROUP)`
- Push Notifications
- Sign in with Apple
- HealthKit
- Background delivery

Share extension:

- App Groups: `group.com.lumina.fernando`
- Keychain Sharing: `$(KEYCHAIN_ACCESS_GROUP)`

Regenerate provisioning profiles after adding App Groups or Keychain Sharing in Apple Developer.

## Source Files

Extension-only files:

```text
LuminaVaultShareExtension/
├── Info.plist
├── LuminaVaultShareExtension.entitlements
├── ShareExtensionCaptureClient.swift
├── ShareExtensionConfig.swift
├── ShareItemLoader.swift
├── SharePayload.swift
├── ShareRootView.swift
├── ShareViewController.swift
└── ShareViewModel.swift
```

Shared files compiled into both host app and extension:

```text
LuminaVaultClient/Services/AppGroup/
├── PendingShare.swift
├── SharedAppGroup.swift
├── SharedCapturePreferences.swift
├── SharedSessionKeychain.swift
└── SharedShareQueue.swift

LuminaVaultClient/Services/KeychainService.swift
```

Do not add `SharedSpacesCache.swift` to the extension target; it imports host-app-only dependencies.

## Verification

1. Build and run the host app once, then sign in so the access token is mirrored to the shared keychain.
2. From Safari or Chrome, share a URL to LuminaVault and confirm it saves without launching the host app.
3. From Notes or Mail, share plain text and confirm a Markdown capture appears in the selected Space.
4. Share an image and confirm the asset uploads through the vault file path.
5. Disable network, share any supported payload, then foreground the host app after restoring network. The queued capture should drain automatically.
