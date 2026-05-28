# HER-299 redesign — audit + gap-fill work log

**Date:** 2026-05-28 · **Branch merged to:** `main` · **Commit:** `343f360`

Companion to the full audit: [`HER-299-redesign-audit.md`](HER-299-redesign-audit.md).

## Phase 1 — Audit

Verified all 9 HER-299 subtasks (HER-300…307) against each ticket's design constraints
**and** reference screenshot, using two evidence streams:

- **Code** — design-token usage per screen (`file:line`).
- **Visual** — renders captured via `swift-snapshot-testing` (iPhone 16 Pro, dark) vs the
  Linear reference. Confirmed the build compiles + existing snapshot suite passes on HEAD
  (the documented `HealthKitService.swift:221` blocker does not trigger on simulator).

Outcome: 6 PASS, 2 PARTIAL/gap, 1 accepted deviation. Full per-subtask verdicts, evidence,
and embedded captures live in the audit report.

## Phase 2 — Gaps filled

| Gap | Root cause / decision | Fix | Files |
|---|---|---|---|
| Mascot hero **blank** on Home + Settings (real on-device bug) | `hermie.riv` absent → fallback `Image()` path; asset is namespaced `Lumina/Mascot/hermie-hero` but code passed bare `"hermie-hero"` → resolved to nothing | Reference full namespaced path | `Features/Home/HomeView.swift`, `Features/Settings/Components/SettingsHeroBand.swift` |
| Onboarding copy ≠ reference | Adopt reference copy | Headline "Your Knowledge, Transcended", CTA "Begin Journey" | `Features/Onboarding/GetStartedView.swift` |
| Spaces card border too muted | Brighten to match reference neon outline | Added `.lvGlowStroke(intensity: LVGlow.card)` | `Features/Spaces/SpaceCardView.swift` |
| Tab IA differs from reference | Reviewed — intentional product IA (HER-194/HER-243) | Kept; documented | — |
| Settings avatar (disc vs crest) | Reviewed — on-brand | Kept | — |
| No snapshot coverage for redesigned surfaces | Lock in fixes | New `RedesignChromeSnapshotTests` (Spaces / Settings / Capture / Think) + re-recorded Home | `LuminaVaultClientTests/RedesignChromeSnapshotTests.swift`, `__Snapshots__/*` |

### Key insight
`OnboardingMascot` / `GetStartedHero` live in the **non-namespaced** `Onboarding/` folder, so
they always resolved — only the namespaced `hermie-hero` reference was broken. GetStarted's
blank capture was an opacity-gated intro-animation artifact, not a bug.

## Verification

- `xcodebuild test … iPhone 16 Pro -only-testing:HomeViewSnapshotTests -only-testing:RedesignChromeSnapshotTests` → **8/8 pass** (record-then-verify).
- Re-recorded Home snapshot visually confirms the mascot hero now renders.
- Build clean on simulator.

## Commit

`343f360 HER-299: fill redesign audit gaps — mascot hero, onboarding copy, Spaces glow`
(22 files: 4 source edits, 1 new test, 8 snapshot PNGs, audit docs). Fast-forward merged to
`main`; feature branch deleted. Not yet pushed.

## Optional follow-up (not a gap)

Ship `hermie.riv` + `get_started_hero.riv` so the mascot heroes animate instead of using the
static fallback PNG.
