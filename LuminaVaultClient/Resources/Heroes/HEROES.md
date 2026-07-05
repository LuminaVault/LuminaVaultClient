# Hero Rive Assets

Drop `splash_hero.riv` and `get_started_hero.riv` into this folder once
exported from Rive. The `LuminaVaultClient` group is a file-system
synchronized root group (Xcode 16+), so the files are bundled automatically
on the next build.

## Rive contract (both files)

| Field         | Value               |
|---------------|---------------------|
| State Machine | `"State Machine 1"` |

### Inputs

| Name        | Type    | Behavior                                                  |
|-------------|---------|-----------------------------------------------------------|
| `isPlaying` | Boolean | `true` → plays looping `bounce`; `false` → idle rest pose. |

### Animations

| Name     | Type    | Description                                                        |
|----------|---------|--------------------------------------------------------------------|
| `bounce` | Looping | 2.0 s seamless bounce: rest → stretch on takeoff → ease-out rise → fall → squash on landing → recover to frame-0 pose. |

## Consumers

- `splash_hero.riv` → `Components/SplashHeroRiveView.swift` (splash screen).
- `get_started_hero.riv` → `Components/GetStartedHeroRiveView.swift`
  (onboarding Get Started screen).

Both views set `isPlaying = true` on load (unless Reduce Motion is enabled)
and fall back to their static PNG asset while the `.riv` is absent.
