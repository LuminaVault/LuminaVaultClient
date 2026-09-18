# Hermie Rive Asset

> **This folder is empty, and nothing here ships (2026-09).** There is no
> `.riv` file anywhere in this repository. When one is made, Hermie goes in
> as the `hermie` **artboard inside the shared `Resources/lumina_anims.riv`**
> — not as a standalone `hermie.riv` — and `Resources/README_RIVE.md` is the
> file that says where things actually stand.
>
> **The timeline table below is live design, not dead reference.** It is the
> brief that `Components/HermieMotion.swift` implements in SwiftUI today, and
> that web implements in CSS, state for state and tempo for tempo. An
> artboard authored from it will match what users already see. Change this
> table and you are changing three things.
>
> The `state`-input contract below is what the app already sends and nothing
> yet reads; see README_RIVE for the two blockers.

## Required Rive contract

`HermieMascotView` (in `Components/HermieMascotView.swift`) loads the file by
name `hermie` and activates a state machine named **`State Machine 1`** (Rive's
default name — rename your machine to match, or update
`HermieMascotView.stateMachineName`).

The machine exposes two inputs:

| Input       | Type    | Behavior                                          |
| ----------- | ------- | ------------------------------------------------- |
| `state`     | Number  | Selects the active per-state timeline. Values match `HermieMascotState.stateValue`: idle=0, thinking=1, happy=2, sad=3, sleeping=4, learning=5, celebrating=6. Any State → timeline on `state == N`, 200 ms crossfade. |
| `isPlaying` | Boolean | Reduce Motion gate. `false` → highest-priority transition to a 1-frame `rest` hold (frame-0 pose). Default `true`. |

The view drives `state` from `HermieMascotState` and forces `isPlaying`
`false` (plus pauses the render loop) when the user has Reduce Motion
enabled — see `HermieMascotView.apply(state:)`.

### Timelines (all loop; frame 0 == final frame == rest pose)

| Timeline | Duration | Motion |
| --- | --- | --- |
| `idle` | 3.0 s | breathing: scaleY 1.00→1.03, y −4 px bob, ±1° |
| `thinking` | 1.6 s | pendulum sway ±4° about bottom-center, y −3 px, glow dot pulse |
| `happy` | 2.0 s | anticipation squash → stretch takeoff → 40 px rise → landing squash → rest |
| `sad` | 4.0 s | slump +3°, y +6 px, scale 0.98, slow shallow breathing |
| `sleeping` | 4.5 s | deep breathing, lean −2°, rising "Z" glyphs |
| `learning` | 1.2 s | absorb pulse scale →1.05, glow-ring ripple |
| `celebrating` | 0.9 s | clap: double hop (y −18 px ×2), ±6° wiggle, scale pulse, confetti burst layer |
| `rest` | 1 frame | hold pose for `isPlaying == false` |

If the `.riv` file is missing — which, today, it always is — the view falls
back to the static `Mascot` image asset in `Assets.xcassets` and animates it
directly. The app still ships.

### What the SwiftUI fallback does and does not do

`Components/HermieMotion.swift` implements the table above with transforms,
opacity and the palette glow the view already applies. Three deliberate
simplifications, because they need extra layers rather than extra transforms:

- `sleeping` has no rising "Z" glyphs. It distinguishes itself from `idle`
  by tempo and direction instead — twice the amplitude at half the speed,
  sinking and dimming where idle lifts and brightens.
- `learning`'s glow-ring ripple is a glow ramp on the mascot's own shadows,
  not a separate ring.
- `celebrating` has no confetti layer of its own. The wizard already fires
  `ConfettiOverlay` at the tab-view root, hosted where nothing can clip it.

Amplitudes are ratios of the rendered size rather than the pixel figures
above, so the same gesture reads at a 56pt avatar and a 220pt hero. Below
48pt nothing moves at all; see `HermieMotion.sizeThreshold`.

## Xcode wiring

1. Place `hermie.riv` next to this README.
2. The `LuminaVaultClient` group is a file-system synchronized root group
   (Xcode 16+), so the file is picked up automatically on next build.
3. Confirm the file appears under
   `LuminaVaultClient ▸ Build Phases ▸ Copy Bundle Resources`.

## Source `.rev` / Rive editor file

Keep the editable Rive project under
`LuminaAssets/hermie/` (outside the Xcode bundle) — only `.riv` exports
ship in the app binary.
