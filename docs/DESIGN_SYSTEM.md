# LuminaVault Design System

This document is the source of truth for LuminaVault's iOS visual language. The code in `LuminaVaultClient/Utilities/` and `LuminaVaultClient/Components/` is canonical — this file documents what already exists and how to use it. There is no Figma library; SwiftUI is the design system.

> **Read [`adr/0001-native-hig-shell.md`](adr/0001-native-hig-shell.md) first.** On 2026-09-17 the app's chrome became the system's: a native `TabView`, one `NavigationStack` per tab, inset-grouped lists, system bar materials. The cinematic language below is still the language — it is now confined to onboarding, the paywall, empty states and `CaptureSheet`. §13 is the rule for everything else; where §13 and an older section disagree, §13 wins.

Linear:
- [HER-59 — DES-003 Define full design system](https://linear.app/luminavault/issue/HER-59)
- [HER-299 — Cinematic redesign (parent)](https://linear.app/luminavault/issue/HER-299/redesign-app)
- [HER-300 — (a) Overall design system direction](https://linear.app/luminavault/issue/HER-300/a-overall-design-system-direction) — §13's predecessor; superseded by ADR 0001
- [HER-301 — (b) Icon system](https://linear.app/luminavault/issue/HER-301/b-icon-system) — §12 updates

## Visual direction at a glance

Two registers, and which one a screen is in is not a taste call — it follows from what the screen is.

**Places** — the five tab roots and everything pushed on them. Native iOS: a standard `TabView`, one `NavigationStack` per tab, inset-grouped lists, system bar materials, stock controls, the brand carried by the tint and the app icon. §13 is the whole rule.

**Moments** — onboarding, the paywall, empty states, `CaptureSheet`. Here LuminaVault feels **cinematic, magical, sci-fi**, never sterile. The reference language (HER-299 Stitch frames):

- **Deep cosmic backdrop** — black → cyan aurora → amber bottom-leading wash → starfield.
- **Volumetric glow** on interactive surfaces; cyan is primary, amber is reserved for premium CTAs.
- **Glassmorphism** for content surfaces — translucent fills, hairline gradient strokes, subtle inner highlights.
- **Mascot as hero** — Hermie renders large on Onboarding and empty states; small on chat assistant rows.
- **Custom illustrated icons** (`Lumina/Icons/*`); SF Symbols for system affordances, and for every tab glyph.

Subtask plans (c–i under HER-299) consume the conventions documented here — but only for the surfaces §5 still allows them on. See §13 "Native chrome conventions" before designing a new screen.

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

**Where they are allowed (2026-09-17, ADR 0001).** `lvGlassCard`, `lvGlowStroke`, `lvAuroraGoldRing`, `lvParticleBackground`, `lvPulse` and `lvGlowPress` are valid on **onboarding, the paywall, empty states and `CaptureSheet`** — surfaces that are a moment rather than a place. They are **not** valid on a tab root, a `List` row, a `Form`, or anything in a navigation or tab bar. Those use system materials, `Color(.secondarySystemGroupedBackground)` and the tint; see §13.

The starfield + aurora scene backdrop, the gold ring on tab content, and the particle field are no longer part of the tab-surface story at all: the five tab roots are plain grouped lists on the system background.

### `lvBackground()` — root scene background

`LuminaVaultClient/Utilities/Extensions/View+LVBackground.swift`

- Fills with `backgroundBase`.
- Dark mode only: renders `LVStarField` (55 deterministic stars).
- Three layered `RadialGradient`s: top-trailing (`auroraTop`), bottom-leading (`auroraBottom`), center pulse (`auroraCenter`).
- **Not for tab roots.** Its remaining consumers are the capture and onboarding surfaces; a tab root that calls it fights the `List`'s own background and the bar materials above it.

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

### `lvAuroraGoldRing(cornerRadius:intensity:)` — premium-CTA gold ring

`View+LVGlass.swift` (HER-300)

- 1.5pt linear-gradient stroke `palette.accent → palette.glowPrimary.opacity(0.5) → palette.accent`.
- Outer shadow stack: `palette.accent @ 0.4 × intensity` @ 12pt, `palette.glowPrimary @ 0.18 × intensity` @ 28pt.
- **Reserve for the single most important CTA on an onboarding, paywall or empty-state screen** (Onboarding "Start", paywall "Continue"). Multiple gold rings per screen flattens the hierarchy. Never on a tab root — Home's "Sync & Learn" is a plain list row now.
- Defaults: `cornerRadius: 20`, `intensity: 1.0`.
- Composes with `palette.surface` fill underneath; does not paint the fill itself.

```swift
Text("Sync & Learn")
    .padding(.horizontal, LVSpacing.xxl)
    .padding(.vertical, LVSpacing.base)
    .background(palette.surface)
    .lvAuroraGoldRing()
```

### `lvParticleBackground(intensity:)` — neural-network particle overlay

`View+LVParticleBackground.swift` (HER-300)

- Layers `Lumina/Backgrounds/neural-network` PNG with `.screen` blend on top of `lvBackground()`.
- `LVParticleIntensity.subtle` (0.10) / `.standard` (0.18) / `.hero` (0.28).
- **Reserve for hero surfaces** — Onboarding, splash, empty states, full-screen mascot moments. Never on a tab root, a list or a toolbar; it competes with copy and with the bar materials.

```swift
ZStack { ... }.lvBackground().lvParticleBackground(intensity: .hero)
```

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

Prefix convention: all SwiftUI components are `LV*`. (Earlier `HV*` files were renamed under HER-292.)

### Inputs

| Component       | File                                            | Notes |
|-----------------|-------------------------------------------------|-------|
| `LVButton`      | `Components/LVButton.swift`                     | Primary CTA. Heavy-weight label. Apply `.lvGlowPress()` for tap feedback. |
| `LVTextField`   | `Components/LVTextField.swift`                  | Standard text input with floating-style label (12pt). |
| `LVSecureField` | `Components/LVSecureField.swift`                | Password input, same chrome as `LVTextField`. |
| `OTPFieldRow`   | `Components/OTPFieldRow.swift`                  | 6-digit OTP entry — used in phone auth + password reset. |
| `SSOButton`     | `Components/SSOButton.swift`                    | Single SSO provider button. |
| `SSORow`        | `Components/SSORow.swift`                       | Horizontal group of SSO buttons. |
| `LVSelectionChip` | `Components/LVSelectionChip.swift`            | Toggle chip with selected state. |
| `LVChipGrid`    | `Components/LVChipGrid.swift`                   | Flowing grid of chips. |

### Chrome & Identity

| Component            | File                                       | Notes |
|----------------------|--------------------------------------------|-------|
| `LVLogoMark`         | `Components/LVLogoMark.swift`              | Static logo glyph. Top-of-funnel only (splash, onboarding, About). |
| `CaptureToolbarItem` | `Features/Capture/CaptureToolbarItem.swift` | The `+`. A `ToolbarItem` a tab root attaches with `.captureToolbarItem()`, not a floating button — one primary action per bar (§13). |
| `LVIconView`         | `Utilities/LVIcon.swift`                   | Renders an `LVIcon` token with theme tint + size (§12). Custom-asset fallback transparent. |
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

### Tab-surface content (2026-09-17)

Native-shell components. All of them render inside an inset-grouped `List`; none of them paint their own background.

| Component               | File                                              | Notes |
|-------------------------|---------------------------------------------------|-------|
| `HomeGlanceStrip`       | `Features/Home/Components/HomeGlanceStrip.swift`  | Three numbers on one row — today, streak, to revisit. Redacted placeholder while loading, `—` on a failed call. |
| `HomeRecommendationRow` | `Features/Home/Components/HomeRecommendationRow.swift` | The one suggestion under the strip. A plain list row with a `Label`; `HomeRecommendationLabel` is the `NavigationLink` half. |
| `VaultFileRow`          | `Features/Vault/VaultFileRow.swift`               | One vault row, wherever the vault is listed. Layout only. |
| `VaultFileDisplay`      | `Features/Vault/VaultFileDisplay.swift`           | Not a view — the pure rules that turn a `VaultFileDTO` into a title, a subtitle and a glyph. Both vault surfaces read it so they cannot disagree. |
| `ChatInboxDisplay`      | `Features/Chat/ChatInboxDisplay.swift`            | Not a view — the pure rule that turns a thread into a scannable title and an optional preview, in place of the server's "New conversation" placeholder. |

#### Deleted 2026-09-17 (ADR 0001)

`LVTabBar`, `LVTabBarMinimizeState`, `LVNavigationBrand` / the `LuminaHeader` wordmark header, `LVFAB`, `CaptureFAB`, `LVLayout`, and the Dashboard set: `HomeView`, `HomeViewModel`, `CommandCenterHeroView`, `SystemVitalsPanel`, `CommandDeckPanel`, `DashboardCardShell`, `ActiveJobsPanel`, `ActivityFeedView`, `BrainPreviewCard`, `CronsPreviewPanel`, `HomeActivityChartCard`, `HomeMixDonutCard`, `PeriodChipBar`, `PeriodKpiRow`, `PowerLevelTitle`, `PowerProgressStrip`, `RetrievalHealthTile`, `SkillsPreviewPanel`, `ToolsPreviewPanel`, `QuickSettingsView`.

`SciFiCardView` (in `Components/HermieMascotView.swift`) survives, used only by Reflect's saved-reflection cards. It is not a tab-root component; do not reach for it on a list surface.

---

## 7. Motion Conventions

| Motion                    | When to use                                   |
|---------------------------|-----------------------------------------------|
| `.lvPulse(active:)`       | Drawing attention to state change, on a §13.9 surface only. |
| `.lvGlowPress()`          | A custom tappable surface on a §13.9 surface. On a tab surface, use a stock button and inherit its press state. |
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
3. **New component** — check §13 first: on a tab surface, the answer is usually a stock control and no new component. If one is warranted, pick prefix (`HV*` for primitive input, `LV*` for composite), drop in `Components/`, add snapshot tests (see HER-241 `HermesGatewaysPaneViewSnapshotTests` for the pattern), document in §6. Baselines are recorded by the `record-snapshots` workflow, not locally.
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
| `.tabBarGlyph`         | 22    | 22pt inline glyph. The custom tab bar it was named for is gone; a native `Tab` sizes its own `systemImage`. |
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

- ~~No icon token system — features use SF Symbols directly with palette tints.~~ Closed by HER-291 — see §12.
- Snapshot test coverage uneven — HermesGateways suite is the reference pattern; expand to other components incrementally.
- Many feature views still contain ad-hoc `.font(.system(size:))` and raw point literals — migrate incrementally as files are touched.
- LVIcon migration is exemplar-only — `MainTabView`, `SettingsRootView`, `AuthLandingView`, `ChatView` use it; ~150 other call sites still pass raw SF Symbol strings. ~~HER-301 (b) closes the asset-wiring gap.~~ **Closed by HER-301** — 24 cases now ship a `Lumina/*` PNG override; per-surface call-site conversions track in subtasks c–i under [HER-299](https://linear.app/luminavault/issue/HER-299).
- Orphaned screens (Tasks, Reminders, Projects, Kanban, Sessions, Today, Health, Achievements) compile but have no entry point since 2026-09-17; the `.today` deep link has no handler reachable. They are kept building rather than deleted so the decision to restore or drop each one is a separate, deliberate call.
- The cinematic modifiers (`lvAuroraGoldRing`, `lvParticleBackground`) now have a smaller legitimate surface than they were written for — onboarding, paywall, empty states, `CaptureSheet` (§5). Some of those surfaces still do not use them.
- Three snapshot suites (`CaptureHomeViewSnapshotTests`, `ChatInboxViewSnapshotTests`, `InsightsTabViewSnapshotTests`) have no baselines and eight more are quarantined behind an `XCTSkipIf`, pending the `record-snapshots` workflow.

---

## 12. Icons (`LVIcon`)

`LuminaVaultClient/Utilities/LVIcon.swift` is the fourth token tier alongside `LVPalette`, `LVTypography`, and `LVSpacing`/`LVSize`/`LVRadius`. It is the source of truth for every icon used in the app and the only place SF Symbol strings live.

```swift
LVIconView(.lockShield, size: 18, tint: palette.glowPrimary, weight: .medium)
    .frame(width: 24)
```

### Why a token tier

Three concrete wins over raw `Image(systemName:)`:

1. **Single source of truth.** Symbol strings live in one enum. Renaming or swapping an icon is one file edit.
2. **Automatic custom-asset fallback.** Cases that have a branded glyph under `Assets.xcassets/Lumina/Tab/` or `Lumina/Icons/` use the custom asset transparently — designers drop a PNG in, call sites get the upgrade for free.
3. **Themed by default.** `LVIconView` reads palette tints and `LVSize` tokens, so icons stay consistent with the rest of the design language.

### `LVIcon` cases

Cases are grouped semantically in the source file. **24 cases ship a `Lumina/*` custom asset** that overrides the SF Symbol fallback transparently (HER-301). The full list is browsable in `LVIcon.swift`; key entries:

| Case                       | SF Symbol fallback                     | Custom asset (Lumina/*)       |
|----------------------------|----------------------------------------|-------------------------------|
| `.tabHome`                 | `sparkles`                             | `Tab/home`                    |
| `.tabSpaces`               | `folder.fill`                          | `Tab/spaces`                  |
| `.tabThink`                | `bubble.left.and.text.bubble.right`    | `Tab/think`                   |
| `.tabSettings`             | `gear`                                 | `Tab/settings`                |
| `.tabVisualSearch`         | `photo.on.rectangle.angled`            | `Tab/visualsearch`            |
| `.brain`                   | `brain`                                | `Icons/brain`                 |
| `.brainHeadProfile`        | `brain.head.profile`                   | `Icons/brain-neural`          |
| `.cameraAperture`          | `camera.aperture`                      | `Icons/camera`                |
| `.gear`                    | `gear`                                 | `Icons/gear`                  |
| `.lightbulbFill`           | `lightbulb.fill`                       | `Icons/lightbulb`             |
| `.linkCircle`              | `link.circle`                          | `Icons/link`                  |
| `.magnifyingglass`         | `magnifyingglass`                      | `Icons/magnify`               |
| `.micFill`                 | `mic.fill`                             | `Icons/mic`                   |
| `.photoOnRectangleAngled`  | `photo.on.rectangle.angled`            | `Icons/gallery`               |
| `.plusCircleFill`          | `plus.circle.fill`                     | `Icons/plus-circle`           |
| **HER-301 new cases** (no clean SF Symbol equivalent) | | |
| `.brainPremium`            | `brain.head.profile`                   | `Icons/brain_premium`         |
| `.briefcase`               | `briefcase.fill`                       | `Icons/briefcase`             |
| `.chartUp`                 | `chart.line.uptrend.xyaxis`            | `Icons/chart-up`              |
| `.cloudWinged`             | `cloud.fill`                           | `Icons/cloud-winged`          |
| `.door`                    | `door.left.hand.open`                  | `Icons/door`                  |
| `.heartWinged`             | `heart.fill`                           | `Icons/heart-winged`          |
| `.homeGlow`                | `house.fill`                           | `Icons/home`                  |
| `.layers`                  | `square.3.layers.3d`                   | `Icons/layers`                |
| `.scrollWinged`            | `scroll.fill`                          | `Icons/scroll-winged`         |
| `.shieldBrain`             | `lock.shield.fill`                     | `Icons/shield-brain`          |
| `.skeletonKeyPremium`      | `key.fill`                             | `Icons/skeleton_key_premium`  |
| `.wandSparkle`             | `wand.and.stars`                       | `Icons/wand-sparkle`          |
| `.wingedLockPremium`       | `lock.shield`                          | `Icons/winged_lock_premium`   |
| `.wingedScrollPremium`     | `scroll.fill`                          | `Icons/winged_scroll_premium` |

Identity / auth / navigation / status cases (`.apple`, `.lockShield`, `.chevronRight`, `.checkmarkCircleFill`, …) intentionally stay SF-Symbol-only — they should match iOS system affordances, not the brand glyph language. See `LVIcon.swift` for the full enum (browsable via Xcode quick-help).

### Asset-resolution test

`LuminaVaultClientTests/LVIconAssetTests.swift` iterates `LVIcon.allCases` and asserts every `customAssetName` resolves to a real `UIImage`. Catches typos and missing imagesets before they ship as silent SF-Symbol fallbacks. Run any time the table above changes.

(Trimmed — see `LVIcon.swift` for the full enum.)

### Rendering — `LVIconView`

```swift
LVIconView(
    _ icon: LVIcon,
    size: CGFloat = LVSize.rowGlyph,   // 28pt default
    tint: Color? = nil,                // default Color.primary
    weight: Font.Weight = .regular,
)
```

- **Default size** is `LVSize.rowGlyph` (28pt) — list-row leading glyphs. For inline body glyphs (composer search icon, etc.) pass an explicit pt value.
- Custom assets render with `.template` mode + tint — the same `LVIcon` case looks consistent everywhere it is used.
- Glow / pulse / press effects stay on the wrapper view (`.lvPulse()`, `.lvGlowStroke()`, `.shadow(...)`). `LVIconView` only resolves name + tint. On a tab root, do not add them at all (§5).

### Not in the tab bar

The tab bar takes SF Symbols and nothing else: a native `Tab("Home", systemImage: "house", …)` renders and tints its own glyph, so `LVIcon` and the `Lumina/Tab/*` brand artwork play no part in it. The brand in the shell is the tint and the app icon.

### Migration recipe

For each ad-hoc `Image(systemName:)` or `Label(_:systemImage:)`:

1. Find the SF Symbol string.
2. Find or add the matching `LVIcon` case in `LVIcon.swift` (alphabetical inside its semantic group).
3. Rewrite the call site:

| Old                                                                                 | New                                                                          |
|-------------------------------------------------------------------------------------|------------------------------------------------------------------------------|
| `Image(systemName: "key.fill")`                                                     | `LVIconView(.keyFill)`                                                       |
| `Image(systemName: "key.fill").foregroundStyle(palette.accent)`                     | `LVIconView(.keyFill, tint: palette.accent)`                                 |
| `Image(systemName: "lock.shield").font(.system(size: 18, weight: .medium))`         | `LVIconView(.lockShield, size: 18, weight: .medium)`                         |
| `Label("X", systemImage: "key.fill")` (stays valid SwiftUI — leave it)              | `Label("X", systemImage: LVIcon.keyFill.sfSymbol)` if a token is needed      |

`Label(_:systemImage:)` is left in place by default — SwiftUI menus and toolbars take the string form, and a wrapped `Label { } icon: { LVIconView(...) }` is heavier than the value of forcing the migration. Wrap manually when a custom-asset fallback is required.

### Adding a new icon

1. Append the case to `LVIcon.swift` inside its semantic group (alphabetical).
2. Return its SF Symbol from `sfSymbol`.
3. (Optional) Map a custom asset path in `customAssetName`.
4. Add a row to the table above.
5. Bump this section in the same PR.

---

## 13. Native chrome conventions

Adopted 2026-09-17 by [ADR 0001](adr/0001-native-hig-shell.md), replacing the cinematic chrome conventions that stood here. **This section outranks every older section in this file.** Where §5 or §12 still describes a glowing, glass or wordmarked surface, §13 says where that is allowed: onboarding, the paywall, empty states and `CaptureSheet` — nowhere else.

The rule behind all of it: the app's chrome is the system's. A user should be able to tell what a control does from having used any other iPhone app. The brand is the content and the tint, not the furniture.

### 13.1 The shell

A standard `TabView` with five `Tab`s. Nothing is drawn under, over or around it; there is no minimize-on-scroll state for scroll surfaces to opt into.

| Label      | `AppTab` id   | Root view              |
|------------|---------------|------------------------|
| Home       | `home`        | `CaptureHomeView`      |
| Spaces     | `workspaces`  | `WorkspacesView`       |
| AI         | `think`       | `ThinkWithLuminaView`  |
| Brain      | `brain`       | `BrainTabView`         |
| Insights   | `reflect`     | `InsightsTabView`      |

The raw values are load-bearing — `\.lvActiveTab` consumers compare them literally — so a tab is renamed in its label, never in its id.

Settings is a sheet from Home's leading toolbar item, not a sixth tab. A sixth tab is how the old bar ended up with an overflow menu inside it.

### 13.2 One `NavigationStack` per tab

Each tab owns exactly one stack, and every push inside that tab goes on it. A tab root either declares the stack in `MainTabView` (Home, Spaces) or owns it itself (AI, Brain, Insights) — never both, and never a second stack nested inside the first.

A screen reached by push is a place, and gets a push. A screen that is an errand — a run, an editor, a picker, a review — is a sheet.

### 13.3 Titles

- **Large title** on a list root: Home, Spaces, AI, Insights.
- **Inline title** on a canvas or a detail: Brain (the graph needs its vertical space), every sheet, every pushed detail.
- The title is the only place the screen names itself. No `Text` at the top of the content repeating it, and no wordmark above it.

### 13.4 Lists

Content surfaces are `List` with `.listStyle(.insetGrouped)` and section headers that are plain strings. Rows do not paint their own backgrounds; a card that must stand apart from a list uses `Color(.secondarySystemGroupedBackground)` at `LVRadius.card`, as the Spaces grid does.

No hand-drawn cards, dividers, capsules or segmented controls where a `Section`, a `Picker` or a stock `Button` does the job. The stock control gets Dynamic Type, the tint, the pressed state, VoiceOver and the right contrast for free; the hand-drawn one gets none of them and has to be maintained.

### 13.5 Materials

System materials appear in exactly two places: the navigation and tab bars, which apply their own, and a `safeAreaInset` pinned to a bar edge, which uses `.background(.bar)` so it reads as part of the bar above or below it.

`.ultraThinMaterial` in content is a glass card by another name — see §5.

### 13.6 Brand

The brand in the shell is `.tint(palette.accent)` on the `TabView` and the app icon. That is the whole list.

Tab glyphs are SF Symbols, sized and tinted by the system. The wordmark does not appear inside the app; it belongs to splash, onboarding, the paywall and About.

### 13.7 Toolbars

**One primary action per screen**, at the trailing edge:

- Capture `+` on Spaces, Brain and Insights, via `.captureToolbarItem()`. Home has none — its composer is the entry.
- **New chat** on AI, which is that tab's create action instead.

Everything else goes in a single overflow `Menu` labelled `ellipsis.circle`, next to the primary action. Two visible verbs in a bar is already a menu that has not been written yet.

Leading edge is for navigation, plus Home's Settings entry point.

### 13.8 What does not go on a tab surface

- Wordmarks, brand headers, mascots-as-chrome.
- Decorative ordinals, kickers, mono small-caps eyebrows (§14 is for marketing and onboarding copy, not for list headers).
- Glows, glass, gold rings, particle fields, starfields, aurora backdrops (§5).
- Floating buttons over the tab bar.
- A second control that duplicates one the navigation bar already offers — `.searchable` is the search field; a drawn one underneath it is a bug.

### 13.9 When a surface may still be cinematic

Onboarding, the paywall, empty states and `CaptureSheet`. These are moments rather than places: they are entered deliberately, they are not scrolled through daily, and the language in §5 and §14 is what makes them feel like the product rather than a settings screen. Match the energy of the HER-299 reference frames there, and nowhere else.

## 14. Motif Kit & Kickers (identity-deepening pass, 2026-07)

Cross-platform layer that makes the cyanGold identity pervasive. **iOS scope since 2026-09-17: §13.9 surfaces only** — kickers, sigil frames, seams and constellation backdrops do not belong on a tab root or in a list. The web app is unaffected. Same vocabulary on both surfaces; web classes live in `LuminaVaultWebApp/src/lib/theme/palette.css`, iOS counterparts below. All iOS motifs read `palette.*` slots — never hardcode cyan/amber (nebula/solar must keep working).

| Motif | iOS | Web |
|---|---|---|
| Kicker (mono small-caps eyebrow with amber tick) | `LVKickerLabel("Vault / Connections")`, `LVTypography.kicker` | `.lv-kicker` |
| Glass card | `lvGlassCard` (existing) | `.lv-glass-card` |
| Sigil frame (sealed-card corner ticks) | `.lvSigilFrame(cornerRadius:)` | `.lv-sigil-frame` |
| Vault seam (hairline divider, warm center) | `LVVaultSeam` / `lvVaultSeam()` | `.lv-vault-seam` |
| Constellation dot grid | `lvConstellationBackdrop(spacing:)` | `.lv-constellation` |
| Status lumen (glowing status dot) | `LVStatusLumen` | `.lv-status-lumen` + `connectionHealthTone()` |
| Premium/headline halo | `lvAuroraGoldRing` (existing) | `.lv-lumen-ring` |
| Starfield (dark-only ambient) | `LVStarField` (existing) | `.lv-starfield` |
| Capture-lifecycle pulse | `View+LVPulse` (existing) | `.lv-node-pulse` |

Rules: one lumen ring per view (amber = premium signal). Kickers are for eyebrows/system labels, not body copy. Motion mirrors product states (capture → embed → recalled; Hermie `.thinking` = agent working) and always respects reduced motion.

## 15. Domain Language Glossary

Applied in eyebrows, empty states, onboarding, marketing — never nav labels. Web source of truth: `LuminaVaultWebApp/src/lib/brand/copy.ts`; iOS: `BrandCopy`.

- **Vault** — the encrypted store ("Unseal your vault")
- **Lumen** — one captured memory fragment / graph node ("1,204 lumens")
- **Recall** — retrieval/search ("Recall anything")
- **Constellation** — the brain graph / connected knowledge
- **Gateway** — a messaging bridge (WhatsApp, Telegram, Matrix, …)
- **Keys** — BYOK provider credentials ("Your keys, your models")

Cross-surface parity contract: `LuminaVaultWebApp/src/lib/theme/palette.css` is a port of `LVPalette.swift` — palette changes must land in both.
