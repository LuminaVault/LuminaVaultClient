# Lumina mascot animation states (HER-152)

The Lumina mascot is a Rive-driven character that reacts to app activity so
the product reads as "alive" rather than a static chat UI. This doc covers
the state model and how to drive it. It supersedes the original Hermie rig
(HER-40 / HER-179) by exposing the full state set under the Lumina brand.

## Components

| Type | File | Role |
|------|------|------|
| `LuminaMascotView` | `Components/LuminaMascotView.swift` | Public facade. Use this in feature code. |
| `HermieMascotView` | `Components/HermieMascotView.swift` | Underlying Rive rig (`RiveViewModel` load + PNG fallback). |
| `LuminaMascotState` | typealias of `HermieMascotState` | The animation state enum. |

`LuminaMascotView` is a thin wrapper — it does **not** open a second
`RiveViewModel`. There is one load path (`HermieMascotView`) so the rig and
the branded API never drift.

## States

```swift
public enum HermieMascotState: String, CaseIterable, Sendable {
    case idle, thinking, happy, sad, sleeping, learning, celebrating
}
```

| State | Fires when | Rive trigger today |
|-------|-----------|--------------------|
| `idle` | Default resting state | `idle` |
| `thinking` | Chat / Ask Lumina request in flight | `thinking` |
| `happy` | Positive result (answer delivered, memo saved) | `happy` |
| `sad` | Capture or kb-compile **fails** | `idle` * |
| `sleeping` | Idle-timeout — app sits untouched | `idle` * |
| `learning` | kb-compile / embedding job running | `thinking` * |
| `celebrating` | Streak milestone / APNS digest delivered in-app | `happy` * |

\* **Graceful fallback.** `hermie.riv` currently ships only three triggers
(`idle`, `thinking`, `happy`). The starred states map onto the nearest
existing trigger so the mascot degrades gracefully instead of freezing.
Once the Rive Pro file ships a dedicated input per state, drop the overrides
in `HermieMascotState.riveTrigger` and let each case fire its own
`rawValue`.

## Usage

```swift
// Static state
LuminaMascotView(state: .thinking, size: 120)

// Issue-spec ergonomics — chain .state(_)
LuminaMascotView().state(.learning)

// Drive from view-model state
LuminaMascotView(state: viewModel.isCompiling ? .learning : .idle)
```

State changes are animated via `RiveViewModel.triggerInput(_:)` in
`HermieMascotView.onChange(of: state)`. No imperative calls needed — bind the
state and the rig fires the matching trigger.

## Wiring states from app activity

The mascot is presentation-only; drivers live in the feature layer:

- **Chat / Think** — `.thinking` while the request is in flight, `.happy` on
  success. See `Features/Think/ThinkWithLuminaView.swift`.
- **Capture / kb-compile** — `.learning` while embedding runs, `.sad` on
  failure. See `Features/Capture`.
- **Idle timeout** — `.sleeping` from the app inactivity timer.
- **Streaks / digests** — `.celebrating` (HER-179 APNS digest path).

## Assets (Xcode / Rive-side — not in code)

Per the HER-152 acceptance criteria, the following are **design tasks**, not
code, and are tracked separately:

1. **Rive Pro account** + per-state animation export.
2. **`hermie.riv`** added to the app bundle (`Bundle.main`). Until it lands,
   `LuminaMascotView` shows the `Mascot` PNG fallback from
   `Assets.xcassets/Branding/`.
3. State machine name must stay `"State Machine 1"` and trigger inputs must
   match the `rawValue` of each `HermieMascotState` case for the fallback
   overrides to be removable.

The `RiveRuntime` SPM dependency is already wired (HER-40).
