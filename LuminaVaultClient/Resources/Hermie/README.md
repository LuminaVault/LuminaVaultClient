# Hermie Rive Asset

Drop `hermie.riv` into this folder once exported from Rive.

## Required Rive contract

`HermieMascotView` (in `Components/HermieMascotView.swift`) loads the file by
name `hermie` and activates a state machine named **`State Machine 1`** (Rive's
default name — rename your machine to match, or update
`HermieMascotView.stateMachineName`).

The view fires **Trigger inputs** named exactly:

| Trigger    | Fires when `HermieMascotState` is |
| ---------- | --------------------------------- |
| `idle`     | `.idle`                           |
| `thinking` | `.thinking`                       |
| `happy`    | `.happy`                          |

If the `.riv` file is missing, the view falls back to the static
`Mascot` image asset in `Assets.xcassets` — the app still ships.

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
