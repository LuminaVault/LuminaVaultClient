# LuminaVault Design System

This document is the source of truth for LuminaVault's iOS visual language. The code in `LuminaVaultClient/Utilities/` and `LuminaVaultClient/Components/` is canonical — this file documents what already exists and how to use it. There is no Figma library; SwiftUI is the design system.

Linear: [HER-59 — DES-003 Define full design system](https://linear.app/luminavault/issue/HER-59)

---

## 1. Architecture

Theming is environment-driven, not view-modifier-driven.

```
LVThemeManager  ──▶  resolves LVAppearance × LVTheme × system ColorScheme
       │
       ▼
.lvThemed(manager)  ──▶  injects \.lvPalette into Environment
       │
       ▼
@Environment(\.lvPalette) var palette   // every view reads from one source
```

- Apply `.lvThemed(themeManager)` **once at the scene root**.
- Inside any view, read colors via `@Environment(\.lvPalette) private var palette`.
- Never hard-code `Color(red:...)` outside `LVPalette.swift`. If a token is missing, add it to `LVPalette` first.

**Persistence:** `LVThemeManager` writes `lv_appearance` and `lv_theme` to `UserDefaults`. Survives app launches.

---

## 2. Themes

Three palettes × dark/light = 6 concrete `LVPalette` values. The user picks via Settings → Appearance.

| Theme       | Personality                          | Primary | Accent |
|-------------|--------------------------------------|---------|--------|
| `cyanGold`  | Default LuminaVault — cosmic + electric | `#00D4FF` cyan | `#F59E0B` amber |
| `nebula`    | Magenta + violet — deep-space nebula    | `#E040FB` magenta | `#FF6EC7` pink |
| `solar`     | Amber + rose — solar flare              | `#FFB300` amber  | `#FFD54F` gold |

Each theme has light and dark variants. Light variants darken `primary`/`secondary`/`accent` for contrast on bright backgrounds; glow colors stay vivid for visual identity.

### Appearance override

```swift
enum LVAppearance { case system, dark, light }
```

`LVAppearance.system` follows OS color scheme. `.dark`/`.light` override via `.preferredColorScheme(...)`.

---

## 3. Color Tokens (`LVPalette`)

Every palette exposes the same semantic slots. Use slots, never raw hex.

| Token            | Purpose                                                        |
|------------------|----------------------------------------------------------------|
| `primary`        | Brand identity, CTA buttons, key strokes                        |
| `secondary`      | Supporting accents, link tone, secondary CTAs                   |
| `accent`         | High-contrast highlight (warnings, badges, pull focus)          |
| `glowPrimary`    | Outer glow / pulse — always vivid even in light mode            |
| `glowSecondary`  | Layered shadow tint paired with `glowPrimary`                   |
| `surface`        | Glass-card fill (subtle; pairs with `.ultraThinMaterial`)       |
| `surfaceStroke`  | Hairline border on cards/pills                                  |
| `backgroundBase` | Root background (dark cosmic / light cream)                     |
| `auroraTop`      | Top-trailing radial wash on `lvBackground`                      |
| `auroraBottom`   | Bottom-leading radial wash on `lvBackground`                    |
| `auroraCenter`   | Mid-depth pulse on `lvBackground`                               |
| `textPrimary`    | Body and heading copy                                           |
| `textSecondary`  | Captions, hints, disabled states (62% alpha)                    |

### Reference values — `cyanGold` (default)

| Token | Dark | Light |
|-------|------|-------|
| `primary` | `#00D4FF` | `#007EA8` |
| `secondary` | `#0096FF` | `#0061B2` |
| `accent` | `#F59E0B` | `#C98000` |
| `backgroundBase` | `#070D1E` | `#F0F7FF` |
| `textPrimary` | `#FFFFFF` | `#0D1530` |

Full source: `LuminaVaultClient/Utilities/LVPalette.swift`.

---

## 4. Typography (`LVTypography`)

`LuminaVaultClient/Utilities/LVTypography.swift` is the typography scale. Every token maps to a `Font.TextStyle` so it scales with Dynamic Type automatically (except `.hero` and `.button`, which are visual anchors and stay fixed).

Apply with `.font(LVTypography.button.font)`, `Text(...).lv(.title)`, or `.lvFont(.body)`.

| Token           | Style                                  | Use for                                            |
|-----------------|----------------------------------------|----------------------------------------------------|
| `.hero`         | 56pt regular (fixed)                   | Splash glyphs, full-screen state icons             |
| `.display`      | `.largeTitle` bold                     | Top-level screen headers                           |
| `.title`        | `.title2` bold                         | Section banners, modal titles                      |
| `.subtitle`     | `.title3` semibold                     | Card titles, empty-state headlines                 |
| `.headline`     | `.headline` semibold                   | Emphasized primary copy                            |
| `.body`         | `.body` regular                        | Default body                                       |
| `.bodyEmphasis` | `.body` semibold                       | CTA labels inside list rows                        |
| `.callout`      | `.callout`                             | Secondary body / banner copy                       |
| `.fieldLabel`   | `.subheadline` semibold                | Field labels, group headers                        |
| `.footnote`     | `.footnote`                            | Helper text below inputs                           |
| `.caption`      | `.caption`                             | Captions, tab-bar text                             |
| `.microTag`     | `.caption2` semibold                   | Micro tags, env badges                             |
| `.button`       | 13pt heavy (fixed)                     | Primary CTA labels (`LVButton`)                    |
| `.otp`          | 18pt bold monospacedDigit (fixed)      | OTP entry, code displays                           |
| `.mono`         | `.body` monospaced                     | Code blocks, server URLs, identifiers              |

### Migration

Existing `.font(.system(size:weight:))` calls are tech debt. Replace as files are touched. Migrated exemplars: `LVButton`, `LVTextField`, `LVSecureField`, `OTPFieldRow`.

Common rewrites:

| Old                                            | New                              |
|------------------------------------------------|----------------------------------|
| `.font(.system(size: 13, weight: .heavy))`     | `.font(LVTypography.button.font)` |
| `.font(.system(size: 12))`                     | `.font(LVTypography.caption.font)` |
| `.font(.subheadline.weight(.semibold))`        | `.font(LVTypography.fieldLabel.font)` |
| `.font(.title3.weight(.semibold))`             | `.font(LVTypography.subtitle.font)` |
| `.font(.caption.bold())`                       | `.font(LVTypography.microTag.font)` |

---

## 5. Effect Modifiers

Reusable view modifiers that read `\.lvPalette`. All are palette-aware — they automatically restyle when the user switches theme.

### `lvBackground()` — root scene background

`LuminaVaultClient/Utilities/Extensions/View+LVBackground.swift`

- Fills with `backgroundBase`.
- Dark mode only: renders `LVStarField` (55 deterministic stars).
- Three layered `RadialGradient`s: top-trailing (`auroraTop`), bottom-leading (`auroraBottom`), center pulse (`auroraCenter`).
- Apply at the root of every full-screen view that should feel "in space".

```swift
ScrollView { ... }.lvBackground()
```

### `lvGlassCard(cornerRadius:intensity:)` — glass-morphic surface

`View+LVGlass.swift`

- `.ultraThinMaterial` + `surface` tint + subtle top highlight.
- Gradient stroke from `surfaceStroke` → `glowPrimary.opacity(0.25)` → clear.
- Outer shadow stack: `glowPrimary @ 0.45 × intensity`, `glowSecondary @ 0.18 × intensity`.
- Defaults: `cornerRadius: 20`, `intensity: 0.6`.

```swift
VStack { ... }.padding().lvGlassCard()
```

### `lvGlowStroke(cornerRadius:intensity:)` — glowing pill outline

- Stroke + double-layer shadow in palette glow colors.
- Use for pills, capsules, focus rings.

### `lvPulse(active:)` — breathing scale + glow loop

`View+LVPulse.swift`

- Repeating scale (`1.0 → 1.06`) and glow opacity animation, 1.4s ease-in-out, autoreverses.
- Pass `active: false` to freeze (used to gate the Home tab pulse behind "pending insights exist").
- **Respects `accessibilityReduceMotion`** — freezes completely when reduce-motion is on.

### `lvGlowPress()` — tap feedback

- Scale to 0.97 on press, glow flash via `glowPrimary @ 0.6`.
- Spring animation. Use on any custom tappable surface (replaces default button press).

---

## 6. Component Inventory

Prefix convention:
- `HV*` — primitive inputs (Hermes Vault era prefix; kept for stability).
- `LV*` — LuminaVault composite components and chrome.

### Inputs

| Component       | File                                            | Notes |
|-----------------|-------------------------------------------------|-------|
| `HVButton`      | `Components/HVButton.swift`                     | Primary CTA. Heavy-weight label. Apply `.lvGlowPress()` for tap feedback. |
| `HVTextField`   | `Components/HVTextField.swift`                  | Standard text input with floating-style label (12pt). |
| `HVSecureField` | `Components/HVSecureField.swift`                | Password input, same chrome as `HVTextField`. |
| `OTPFieldRow`   | `Components/OTPFieldRow.swift`                  | 6-digit OTP entry — used in phone auth + password reset. |
| `SSOButton`     | `Components/SSOButton.swift`                    | Single SSO provider button. |
| `SSORow`        | `Components/SSORow.swift`                       | Horizontal group of SSO buttons. |
| `LVSelectionChip` | `Components/LVSelectionChip.swift`            | Toggle chip with selected state. |
| `LVChipGrid`    | `Components/LVChipGrid.swift`                   | Flowing grid of chips. |

### Chrome & Identity

| Component            | File                                       | Notes |
|----------------------|--------------------------------------------|-------|
| `HVLogoMark`         | `Components/HVLogoMark.swift`              | Static logo glyph. |
| `LVNavigationBrand`  | `Components/LVNavigationBrand.swift`       | Brand mark + wordmark for nav bar. |
| `LVTabBar`           | `Components/LVTabBar.swift`                | Custom 5-tab bar. Home tab uses `.lvPulse` gated on pending insights. |
| `EnvironmentTagView` | `Components/EnvironmentTagView.swift`      | Dev/staging/prod environment badge. |
| `LVPasteBanner`      | `Components/LVPasteBanner.swift`           | Clipboard-paste prompt banner. |
| `LVEmptyState`       | `Components/LVEmptyState.swift`            | Empty list illustration + CTA. |
| `StepIcon`           | `Components/StepIcon.swift`                | Numbered step indicator. |

### Identity & Motion

| Component                  | File                                          | Notes |
|----------------------------|-----------------------------------------------|-------|
| `HermieMascotView`         | `Components/HermieMascotView.swift`           | Hermie mascot — animated. |
| `SparkleField`             | `Components/SparkleField.swift`               | Floating sparkle particle field. |
| `SplashHeroRiveView`       | `Components/SplashHeroRiveView.swift`         | Rive animation for splash. |
| `GetStartedHeroRiveView`   | `Components/GetStartedHeroRiveView.swift`     | Rive hero for onboarding. |
| `WingedScrollRiveView`     | `Components/WingedScrollRiveView.swift`       | Rive winged-scroll motif (see `Resources/WingedScroll/WINGED_SCROLL.md`). |

---

## 7. Motion Conventions

| Motion                    | When to use                                   |
|---------------------------|-----------------------------------------------|
| `.lvPulse(active:)`       | Drawing attention to state change (pending insights, new memory). |
| `.lvGlowPress()`          | Any custom tappable surface (replaces system button press). |
| Spring `response:0.3, dampingFraction:0.7` | Default for tap feedback and small UI shifts. |
| `.easeInOut(duration:1.4).repeatForever` | Pulse / breathing loops only. |
| Rive animations           | Hero moments — splash, onboarding, signature views. Not for general UI. |

**Reduce Motion:** all pulse/breathing animations must check `@Environment(\.accessibilityReduceMotion)` and freeze when on. `lvPulse` already handles this; replicate the pattern for any new looping animation.

---

## 8. Accessibility Rules

- Always use `palette.textPrimary` / `palette.textSecondary` — never hard-code white/black. They're tuned per palette per scheme for WCAG contrast.
- Light-mode primaries are intentionally darker than dark-mode for contrast on bright backgrounds. Don't "fix" this by reusing dark-mode hex.
- Reduce Motion: gate any continuous animation behind `accessibilityReduceMotion`.
- Dynamic Type: components use `.system(size:)` — track gap to introduce `LVTypography` with `relativeTo:` for Dynamic Type scaling.

---

## 9. Adding New Tokens or Components

1. **New color token** — add the slot to `LVPalette`, set values in **all six** concrete palettes, document in §3 here.
2. **New modifier** — add to `Utilities/Extensions/View+LV*.swift`, read palette via `@Environment(\.lvPalette)`, never accept `Color` as a parameter.
3. **New component** — pick prefix (`HV*` for primitive input, `LV*` for composite), drop in `Components/`, add snapshot tests (see HER-241 `HermesGatewaysPaneViewSnapshotTests` for the pattern), document in §6.
4. **Bump this doc in the same PR.** Code without docs decays.

---

## 10. Spacing, Sizing, Radius (`LVSpacing` / `LVSize` / `LVRadius`)

`LuminaVaultClient/Utilities/LVSpacing.swift` defines three sibling enums. 4pt base grid. Use these for any `padding`, `spacing`, `frame`, or `cornerRadius`. Raw point literals in feature code are tech debt — replace as files are touched.

### `LVSpacing` — gutters and padding

| Token        | Value | Use for                                       |
|--------------|-------|-----------------------------------------------|
| `.hairline`  | 2     | Hairline separation                           |
| `.xs`        | 4     | Icon ↔ label, tight intra-component spacing  |
| `.sm`        | 8     | Chip padding, badge gutter                    |
| `.md`        | 12    | Default vertical rhythm inside cards          |
| `.base`      | 16    | Standard padding, inter-section gutter        |
| `.lg`        | 20    | List-row vertical padding                     |
| `.xl`        | 24    | Section margin, dialog inset                  |
| `.xxl`       | 32    | Major group separation                        |
| `.hero`      | 48    | Splash / empty-state hero spacing             |
| `.heroTop`   | 64    | Top-of-screen drop above hero content         |

### `LVSize` — component dimensions

| Token                  | Value | Use for                                  |
|------------------------|-------|------------------------------------------|
| `.buttonHeight`        | 48    | Primary CTA button height (`LVButton`)   |
| `.largeControlHeight`  | 56    | Large CTA, search bar                    |
| `.tabBarGlyph`         | 22    | Tab-bar glyph (`LVTabBar`)               |
| `.rowGlyph`            | 28    | List-row leading glyph                   |
| `.mascotSmall`         | 220   | Empty-state Rive mascot                  |
| `.heroLarge`           | 320   | Splash / onboarding hero size            |

### `LVRadius` — corner radii

| Token    | Value | Use for                              |
|----------|-------|--------------------------------------|
| `.pill`  | 999   | Pill / capsule shapes                |
| `.sm`    | 8     | Small chips, tight pills             |
| `.md`    | 12    | Inputs, small cards                  |
| `.lg`    | 16    | `.lvGlowStroke` default              |
| `.card`  | 20    | `.lvGlassCard` default               |
| `.sheet` | 28    | Bottom sheets, large surfaces        |

Example:

```swift
VStack(spacing: LVSpacing.md) { ... }
    .padding(LVSpacing.base)
    .frame(height: LVSize.buttonHeight)
    .clipShape(RoundedRectangle(cornerRadius: LVRadius.card))
```

---

## 11. Known Gaps

- No icon token system — features use SF Symbols directly with palette tints.
- Snapshot test coverage uneven — HermesGateways suite is the reference pattern; expand to other components incrementally.
- Many feature views still contain ad-hoc `.font(.system(size:))` and raw point literals — migrate incrementally as files are touched.
