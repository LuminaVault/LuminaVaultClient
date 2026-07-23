# Rive animations — single-file contract (`lumina_anims.riv`)

All four Rive marks are authored as **artboards inside one Rive file** and
exported together as **`lumina_anims.riv`**. The runtime selects each mark by
artboard name (`RiveAssets.viewModel(named:artboardName:stateMachineName:)`),
so there is one bundled `.riv`, not four.

## Artboard contract

| Artboard | Size | State Machine | Animation | Consumer view |
|----------|------|---------------|-----------|---------------|
| `splash_hero`       | 512×512   | `State Machine 1` | `bounce` (loop) | `SplashHeroRiveView` |
| `get_started_hero`  | 512×512   | `State Machine 1` | `bounce` (loop) | `GetStartedHeroRiveView` |
| `winged_scroll`     | 1024×1024 | `State Machine 1` | `bounce` (loop) | `WingedScrollRiveView` / `LVLogoMark` |
| `hermie`            | 512×512   | `State Machine 1` | `idle` (loop)   | `HermieMascotView` |

Every state machine auto-enters its looping timeline — no inputs required to
play. Reduce Motion is handled on the Swift side (`viewModel.pause()` +
render-loop suspension), so the animation stops for those users regardless of
inputs.

### Known limitation — Hermie multi-state

`HermieMascotView` drives a `state` number input (idle/thinking/happy/…) via
`setInput`. The Rive **editor MCP cannot author classic state-machine inputs**
(it only exposes data-binding view-model properties, which rive-ios `getBool`/
`getNumber` do **not** read). So `hermie` currently ships **idle-only**: the
`setInput("state", …)` calls are harmless no-ops and the idle loop always
plays. To get true 7-state switching, either add classic `state` + `isPlaying`
inputs in the Rive editor by hand, or migrate `HermieMascotView` to rive-ios
data binding (`RiveModel.enableAutoBind`).

## Export → bundle (manual)

Rive desktop is sandboxed/cloud; there is no CLI/MCP export. To ship:

1. In the Rive editor, **Export → Download → Runtime (.riv)** for the file
   (exports all artboards into one `.riv`).
2. Save it here as **`Resources/lumina_anims.riv`**.
3. The `LuminaVaultClient` group is a file-system-synchronized root group
   (Xcode 16+), so the file bundles automatically on the next build. No
   pbxproj edit needed.
4. Build & run. Each view auto-detects its artboard and drops the static-PNG
   fallback. If the file (or a named artboard/state machine) is missing, the
   view keeps its PNG fallback — the app never breaks.

**Instant revert:** delete `Resources/lumina_anims.riv` → all four views fall
back to their approved PNG assets.
