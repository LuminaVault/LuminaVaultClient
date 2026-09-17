# ADR 0001 — A native HIG shell, and Home is capture

- Status: accepted
- Date: 2026-09-17
- Supersedes: `docs/design-audit/HER-299-redesign-audit.md` (the cinematic
  redesign it audits is what this replaces)
- Supersedes in part: `docs/DESIGN_SYSTEM.md` §13 "Cinematic Conventions"
  (§5's `lvBackground()` too). The full rewrite of that document is a later
  task; until then, §13 describes chrome the app no longer draws.

## Context

The app had accumulated a second, bespoke shell on top of the system's:

- a gradient-glow wordmark header (`LuminaHeader`) on every screen, carrying a
  second "+" and a tappable mascot that opened a "Quick Settings" sheet;
- a custom floating glass tab bar (`LVTabBar`) with six items, a raised
  capture FAB overlapping it, and a scroll-driven minimize state
  (`LVTabBarMinimizeState`) every scroll surface had to opt into;
- a cinematic backdrop behind ~97 screens — an aurora wash plus a 55-star
  field — which since `cyanGold` became the default was what every user got on
  first launch;
- a "LUMINA COMMAND / SYSTEM VITALS / COMMAND DECK" Dashboard, reachable only
  through the bar's More menu, drawing seventeen bespoke panels off six
  endpoints.

Two things forced the decision. The chrome reads as vibe-coded rather than
designed, and it costs real engineering: every new scroll surface had to know
about the floating bar's height, and the 6th tab put SwiftUI's own "More" list
in the way (a blank screen and a double back chevron). And the
strangers-count is 0 — nobody outside has used this yet, so there is nothing
to preserve and no reason to keep paying for it.

## Decision

Wear the system's chrome.

- **Native `TabView`, five tabs**: Home, Spaces, AI, Brain, Insights. Each tab
  owns one `NavigationStack` with a large title. The tab raw values
  (`home|workspaces|think|brain|reflect`) are unchanged — `\.lvActiveTab`
  consumers compare them literally to pause Rive and particle animations.
- **Brand survives as `.tint(palette.accent)` at the root, and the app icon.**
  Nothing else: no gradient titles, no glow strokes on chrome, no starfield.
- **`lvBackground()` is one plain fill**, and every theme's `backgroundBase`
  maps to `Color(.systemGroupedBackground)`, so `List` screens and
  `.lvBackground()` screens sit on the same colour. The ~97 call sites did not
  have to change.
- **Home is the composer**: an inset-grouped `List` of composer → "Today"
  (three numbers plus at most one recommendation) → "Recent" (what you saved).
  No "+" on Home; the composer is the entry. Every other tab gets one trailing
  toolbar "+" (`CaptureToolbarItem`).
- **Settings is a sheet** from a profile button on Home, not a tab and not a
  mascot tap.
- **The Dashboard is deleted.** Its three numbers worth keeping became the
  Home glance strip (`HomeGlanceViewModel` asks three endpoints, once on
  appear and on pull-to-refresh, never polls). Its agent status became a
  read-only row in Settings → Your Agent.
- **Orphaned screens are left unreachable but compiling.** Tasks, Reminders,
  Projects, Kanban, Sessions, Today, Health, Achievements and Visual Search
  were only reachable from the Dashboard or the More menu. They are not
  re-homed and not deleted; where they belong is a product question, and
  deleting them would answer it by accident. `DailyReviewView` is reachable
  again through the Home recommendation row.

## Consequences

Deleted: `Components/LVTabBar.swift`, `Components/LVTabBarMinimizeState.swift`,
`Features/Capture/CaptureFAB.swift`, the `LuminaHeader` struct,
`Utilities/LVLayout.swift` (its only token was the floating bar's clearance),
`LVCinematicBackdrop` / `LVStarField`, `Features/Settings/QuickSettingsView.swift`,
`Features/Home/HomeView.swift`, `Features/Home/HomeViewModel.swift` and the
seventeen Dashboard panels under `Features/Home/Components/`.

Added: `Features/Capture/CaptureToolbarItem.swift`,
`Features/Home/HomeGlanceViewModel.swift`,
`Features/Home/Components/HomeGlanceStrip.swift`,
`Features/Home/Components/HomeRecommendationRow.swift`,
`Features/Vault/VaultFileDisplay.swift` (titles and subtitles for vault rows —
`VaultFileDTO` has no excerpt field, so every human-readable string is derived
there), `Features/Settings/Components/AgentStatusRow.swift`.

Snapshot baselines change wherever a subject drew `lvBackground()` or
`palette.backgroundBase`, and the three suites added for the new tab roots
(`CaptureHomeViewSnapshotTests`, `ChatInboxViewSnapshotTests`,
`InsightsTabViewSnapshotTests`) had none at all.
`GatewaysSetupViewSnapshotTests`, `HermesGatewayDetailViewSnapshotTests` and
`HermesGatewaysPaneViewSnapshotTests` were first read as unaffected because
neither subject names `lvBackground()` directly; they inherit the new ground
through the chrome around them, so they needed re-recording too.

All fourteen suites were recorded on CI's iPhone 16 Pro / iOS 26.4 renderer
on 2026-09-17, via the `record-snapshots` workflow — which sets
`SNAPSHOT_TESTING_RECORD` through `TEST_RUNNER_SNAPSHOT_TESTING_RECORD` so it
reaches the simulator's test process, runs every case, and uploads the
resulting PNGs as the `snapshots-<sha>` artifact. Those PNGs are now
committed under `LuminaVaultClientTests/__Snapshots__/` and the quarantine
that skipped these suites before the baselines existed is gone.

To re-record a suite after an intentional render change: run
`record-snapshots` from the Actions tab, unzip its `snapshots-<sha>` artifact
over `LuminaVaultClientTests/__Snapshots__/`, and commit the PNGs. No suite
sets the process-global `isRecording`; a one-off re-record uses the
per-assert `record:` parameter.

Known follow-up: the `.today` push deep link was handled only inside
`TodayView`, which is now unreachable, so that notification currently opens
the app on Home and does nothing else.
