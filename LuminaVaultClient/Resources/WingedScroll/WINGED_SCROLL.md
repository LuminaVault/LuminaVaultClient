# WingedScroll Rive Asset Contract

Drop the Rive file `winged_scroll.riv` into this directory and add it to the
LuminaVaultClient Xcode target so it is bundled into the app.

The runtime (`Components/WingedScrollRiveView.swift`) gracefully falls back to
`Image("WingedScroll")` if the `.riv` file is absent, so the UI never breaks
while the asset is being authored.

## Rive contract

| Field          | Value                                                  |
|----------------|--------------------------------------------------------|
| File           | `winged_scroll.riv`                                    |
| Artboard       | `WingedScroll`, 1024×1024                              |
| State Machine  | `"State Machine 1"`                                    |

### Inputs

| Name        | Type    | Behavior                                                  |
|-------------|---------|-----------------------------------------------------------|
| `isPlaying` | Boolean | `true` → plays looping `bounce`; `false` → idle rest pose. |

### Animations

| Name     | Type    | Description                                                        |
|----------|---------|--------------------------------------------------------------------|
| `bounce` | Looping | 2.0 s seamless bounce: rest → stretch on takeoff → ease-out rise → fall → squash on landing → recover to frame-0 pose. |

### Rigging notes

- Bones: `top_wing_L`, `top_wing_R`, `bottom_feathers_L`, `bottom_feathers_R`.
- Body (scroll + lock) must remain rigid — only the wings move.
- Pivot origins should anchor wings at the wing-root joint, not at the
  artboard center.

## Color palette

| Token  | Hex       | Notes                              |
|--------|-----------|------------------------------------|
| Cyan   | `#00D4FF` | Primary neon outline.              |
| Blue   | `#0096FF` | Secondary outline / depth.         |
| Amber  | `#F59E0B` | Highlight accent (lock, glyphs).   |
| Navy   | `#070D1E` | Outline color in dark mode only.   |

Export with transparent background — the SwiftUI host provides the cosmic
gradient (`.lvBackground()` modifier in `Utilities/Extensions/View+LVBackground.swift`).

## Fallback PNG

Until the `.riv` lands, the runtime renders `Image("WingedScroll")`. Drop a
transparent 1024×1024 PNG into
`LuminaVaultClient/Assets.xcassets/WingedScroll.imageset/` with this prompt:

```
Generate a transparent PNG, 1024×1024, centered subject, no padding, no border:

A glowing neon outline of an unrolled parchment scroll with a closed padlock
in the center and large feathered angel wings spread from the top sides.
Color palette: electric cyan (#00D4FF), amber (#F59E0B) highlights, deep
navy outlines. The image should have a subtle inner luminous glow as if
neon-lit. Background: fully transparent — alpha channel only, no fill, no
shadows, no border. Style: clean vector-feeling neon illustration, not
photorealistic, not 3D.
```

Once both the PNG and the `.riv` are committed, the runtime auto-detects the
`.riv` and switches off the fallback path.
