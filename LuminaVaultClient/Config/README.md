# LuminaVaultClient/Config

OAuth client-side configuration for HER-239 (Google Auth).

## What's in here

| File | Committed? | Purpose |
|------|------------|---------|
| `GoogleAuth.xcconfig.sample` | ✅ | Template with placeholder values |
| `GoogleAuth.xcconfig` | ❌ (gitignored) | Real values — created locally |
| `Info.plist` | ✅ | Replaces the auto-generated Info.plist; references `$(GID_CLIENT_ID)` and `$(REVERSED_CLIENT_ID)` |
| `README.md` | ✅ | This file |

## One-time Xcode wiring

Required after pulling this scaffold for the first time.

1. **Copy the sample**
   ```bash
   cp LuminaVaultClient/Config/GoogleAuth.xcconfig.sample \
      LuminaVaultClient/Config/GoogleAuth.xcconfig
   ```
   Edit `GoogleAuth.xcconfig` and paste the real iOS OAuth 2.0 client ID from
   Google Cloud Console → Credentials → your iOS OAuth client.

2. **Register the xcconfig in Xcode**
   - Open `LuminaVaultClient.xcodeproj` in Xcode.
   - Drag `LuminaVaultClient/Config/GoogleAuth.xcconfig` into the project
     navigator (do **not** add it to the target — xcconfig files are
     build-time only).
   - Select the project root → **Info** tab → **Configurations**.
   - Set `GoogleAuth` as the project-level config file for both **Debug**
     and **Release**.

3. **Switch from generated to file-based Info.plist**
   - Select the `LuminaVaultClient` target → **Build Settings** → All.
   - Search `Info.plist File` → set to `LuminaVaultClient/Config/Info.plist`
     for both configs.
   - Search `Generate Info.plist File` → set to **No** for both configs.
   - Remove every `INFOPLIST_KEY_*` row (their values now live in the new
     `Info.plist`).

4. **Verify**
   - Build the app. The Info.plist preprocessor substitutes the xcconfig
     vars; the `CFBundleURLTypes` entry now contains the real reversed
     client ID.
   - Run the app and tap **Sign in with Google** on `AuthLandingView`.
     The system web sheet opens, you consent, and the app receives a
     `com.googleusercontent.apps.*` callback that
     `LuminaVaultClientApp.swift` forwards to `GIDSignIn.sharedInstance.handle(_:)`.

## Cross-repo invariant

The iOS `GID_CLIENT_ID` MUST equal the LuminaVaultServer env var
`OAUTH_GOOGLE_CLIENTID` (server config key `oauth.google.clientId`,
wired in `Sources/App/App+build.swift`). The server verifies the
ID token's `aud` claim against that value — a mismatch returns
`401 OAuthError.invalidToken`.

If you rotate the iOS OAuth client, update both repos in the same change.

## Why not GoogleService-Info.plist?

LuminaVault doesn't use Firebase or other Google services that require
`GoogleService-Info.plist`. Only `GIDClientID` is needed for the
GoogleSignIn-iOS SDK, and we set it directly so no Google-managed plist
needs to be checked into the repo.
