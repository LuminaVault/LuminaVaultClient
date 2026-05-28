# Branch Protection — LuminaVaultClient

Production-grade branch protection for the two release branches. **You** (repo admin) apply these settings; this doc records the contract so they can be reproduced or audited.

## Topology

- `main` → **App Store release** via `.github/workflows/release.yml` on push. Every merge produces a build uploaded to App Store Connect (not auto-submitted for review — `submit_for_review: false` in `fastlane/Fastfile`).
- `development` → **TestFlight beta** via `.github/workflows/testflight.yml` on push. Every merge ships an internal build.
- All other branches: feature work. PR into `development` (default) or `main` (release promotion).

Standard flow:
1. Feature branch → PR → `development` → TestFlight build for internal testing.
2. After validation: PR `development` → `main` → App Store build queued for manual submission.

## Required settings (both `main` and `development`)

- **Require a pull request before merging**: ON
  - Required approvals: **0** (solo dev — CI is the gate)
  - Dismiss stale approvals when new commits are pushed: ON
- **Require status checks to pass before merging**: ON
  - Required checks: `lint` (job names from `.github/workflows/ci.yml`)
  - Require branches to be up to date before merging: ON
  - **`test` is NOT yet required** — GitHub-hosted macos-15 runners ship Xcode 26.x with no iOS Simulator runtime preinstalled, and `xcodebuild -downloadPlatform iOS` doesn't fully resolve scheme/destination mismatches. Promote `test` to required once a working iOS simulator runtime is available on the runner image (or a self-hosted macOS runner with Xcode 26.4 + iOS 26 sims is wired up). Add `"test"` back to the JSON `contexts` array when stable.
- **Require conversation resolution before merging**: ON
- **Allow force pushes**: OFF
- **Allow deletions**: OFF
- **Do not allow bypassing the above settings** (include administrators): **ON**

## Allowed merge methods (repo-level setting)

- Squash merge: ON
- Merge commit: OFF
- Rebase merge: OFF

## Apply via `gh` CLI

```bash
# main
gh api -X PUT repos/LuminaVault/LuminaVaultClient/branches/main/protection \
  --input docs/cicd/branch-protection-main.json

# development
gh api -X PUT repos/LuminaVault/LuminaVaultClient/branches/development/protection \
  --input docs/cicd/branch-protection-development.json
```

## Verification after apply

```bash
# Direct push should fail
git push origin main
# expect: remote: error: GH006: Protected branch update failed

# Admin merge of a failing PR should fail
gh pr merge <num> --admin --squash
# expect: GraphQL error about required status checks
```
