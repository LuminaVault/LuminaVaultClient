# Rive animations — what is real, and what is not

**There is no `.riv` file in this repository.** Not tracked, not on disk, not
in the bundle. `Resources/Hermie/` holds a `.gitkeep` and a design brief;
`lumina_anims.riv` has never existed. Every Rive-aware view in the app is
rendering its PNG fallback, and has been since the views were written.

This file used to describe `lumina_anims.riv` as a shipped artefact with an
idle-only Hermie in it. That was wrong on both counts.

## What the app actually does today

Four views ask for a Rive artboard, find nothing, and fall back:

| Artboard the view asks for | Consumer view | What renders |
|---|---|---|
| `splash_hero` | `SplashHeroRiveView` | static PNG |
| `get_started_hero` | `GetStartedHeroRiveView` | static PNG |
| `winged_scroll` | `WingedScrollRiveView` / `LVLogoMark` | static PNG + host-side breathing |
| `hermie` | `HermieMascotView` | static PNG + host-side reactions |

**Hermie's seven reactions are host-side SwiftUI**, in
`Components/HermieMotion.swift`: one pose function per state, driven by a
single animated `cycle` scalar through an `Animatable` view modifier.
`idle` breathes, `thinking` sways, `learning` pulses, `sad` slumps and dims,
`sleeping` breathes deeply and leans, `happy` hops once, `celebrating` hops
twice with a wiggle. Tempos come from the timeline table in
`Hermie/README.md`.

**Web does the same thing in CSS**, state for state and tempo for tempo. The
two were built to read as one character, and the shared contract
(`LuminaVaultShared/docs/guided-start.md`) is what keeps the *inputs* aligned.

## This is the interim, and it is meant to hold

Not a workaround waiting to be ripped out. Two reasons to leave it alone:

1. It is what ships the behaviour. Before it, seven distinct states rendered
   one static image on both platforms — the app was claiming a reaction
   vocabulary it did not have.
2. It is the fallback either way. When an artboard lands, the host-side
   motion does not get deleted; it becomes what plays when the file is
   missing, when the artboard is renamed, or when an export goes wrong. The
   app has never been allowed to break on a missing `.riv` and that does not
   change.

## What adding Rive later actually costs

Less than it looks, because **the code already sends the state**.

`HermieMascotView` drives a `state` number input from `HermieMascotState`
(idle=0 … celebrating=6) and an `isPlaying` boolean for Reduce Motion. Web
sends the same. Both have been sending them the whole time — into nothing.
So the artboard arrives with **no code change on either platform**: drop the
file in, the runtime finds the artboard, `viewModel` becomes non-nil, and the
Rive canvas renders instead of the image. `HermieMotionModifier` keeps
applying poses to whatever is inside it, so a loaded artboard wants its own
`state` timelines to do the work and the host-side poses become dead weight
under it — the one follow-up worth doing at that point is deciding whether to
skip the host motion when a view model is present, which is one `if`.

The full input contract the artboard has to honour is in `Hermie/README.md`.

### The two blockers, unchanged

1. **The Rive editor MCP cannot author classic state-machine inputs.** It
   only exposes data-binding view-model properties, which rive-ios `getBool` /
   `getNumber` do not read. So the `state` / `isPlaying` inputs have to be
   added by hand in the editor, or `HermieMascotView` has to migrate to
   rive-ios data binding (`RiveModel.enableAutoBind`).
2. **Export has no command line.** Rive desktop is sandboxed/cloud; there is
   no CLI and no MCP export. Shipping a file is a human going to
   **Export → Download → Runtime (.riv)** and committing the result.

Neither is a code problem, which is why neither has moved.

## If a `.riv` ever does land

1. Save it as `Resources/lumina_anims.riv` (all artboards in one file; the
   runtime selects by name via
   `RiveAssets.viewModel(named:artboardName:stateMachineName:)`).
2. The `LuminaVaultClient` group is a file-system-synchronized root group
   (Xcode 16+), so it bundles on the next build. No pbxproj edit.
3. Each state machine must auto-enter its looping timeline. Reduce Motion
   stays a Swift-side concern (`viewModel.pause()` plus render-loop
   suspension), so it works regardless of inputs.
4. **Re-record the snapshot baselines.** Twelve of them render Hermie. They
   currently capture the fallback image; a Rive canvas will not match.

**Instant revert:** delete the file → every view falls back to its approved
PNG, exactly as it does now.
