// LuminaVaultClient/LuminaVaultClient/Features/Home/GuidedStart/GuidedStartHost.swift
//
// The composition root for "Get started with Hermie": the one place that
// knows about `AppState`, the HTTP clients, and the real wire fields, so
// that `GuidedStartCoordinator` can stay pure logic.
//
// ## The dismissal seam, now backed for real
//
// The coordinator's header describes `isDismissed` / `setDismissed` as a
// stand-in for a field that had not shipped. It has shipped —
// `OnboardingStateDTO.guidedStartDismissedAt` and
// `OnboardingPatchRequest.guidedStartDismissed`, LuminaVaultShared 5.17.0 —
// and this file binds the seam to it. The closure pair stays, because it is
// still the injection point that lets the whole coordinator suite run with
// no network and no AppState; what changed is that the production binding
// below is the real field rather than a placeholder.
//
// Reading through `appState.onboardingState` rather than holding a private
// copy is what makes a dismissal from another device reconcile for free:
// `refresh()` applies the snapshot into AppState, and `isDismissed` reads
// the same snapshot on the next evaluation.
//
// ## The pending count must be fresh
//
// `pendingCaptureCount` hits `KBCompileClientProtocol.pending()` on every
// call. It is deliberately *not* `HomeGlanceViewModel.recommendation`,
// which loads once when Home appears and never polls: a memory saved since
// then makes it stale, and a stale zero opens step 2 on a spotlight that
// cannot end in anything but the five-minute timeout.
//
// That is `GET /v1/memory-compile/pending`, the name the contract uses and
// the one `KBCompileEndpoints.Pending` now calls. The type is still spelled
// `KBCompile*` after HER-240 renamed the endpoints; that is a rename waiting
// to happen, not a second probe.

import LuminaVaultShared
import SwiftUI

extension GuidedStartCoordinator {
    /// The production wiring. One per app shell, created in `MainTabView`.
    static func live(appState: AppState) -> GuidedStartCoordinator {
        let onboardingClient = appState.makeOnboardingClient()
        let compileClient = appState.makeKBCompileClient()

        return GuidedStartCoordinator(
            client: onboardingClient,
            telemetry: GuidedStartTelemetry(),
            snapshot: { appState.onboardingState },
            applySnapshot: { appState.onboardingState = $0 },
            // Fresh every time, by construction.
            pendingCaptureCount: { try await compileClient.pending().pendingFiles },
            isDismissed: { appState.onboardingState?.guidedStartDismissedAt != nil },
            setDismissed: { dismissed in
                // The PATCH answers with the updated row, so applying it
                // keeps the snapshot and the seam agreeing without a
                // follow-up GET.
                appState.onboardingState = try await onboardingClient.patch(
                    OnboardingPatchRequest(guidedStartDismissed: dismissed)
                )
            }
        )
    }
}

// MARK: - Derived view state

// Read-only conveniences over `phase`, so the shell and Home agree on what
// the phase means instead of each pattern-matching it. Additive: nothing
// here changes the coordinator's own surface.
extension GuidedStartCoordinator {
    /// The step whose spotlight is on screen, or `nil`. At most one step is
    /// ever active (contract), so one optional says it all.
    var activeStep: GuidedStartStep? {
        if case .active(let step, _) = phase { return step }
        return nil
    }

    /// The contract's reaction vocabulary: `idle` on the resting card,
    /// `thinking` while a step is open, `happy` on a step completing,
    /// `celebrating` on the last one.
    ///
    /// **One deliberate deviation, matched on web.** Step 2 is `learning`,
    /// not `thinking`. "Sync & Learn" is literally handing Hermie something
    /// to read, and `learning` is already defined as the absorb pulse for a
    /// compile or embedding job (`Resources/Hermie/README.md`) — which is
    /// exactly what the step kicks off. Web landed this first; the shared
    /// contract is being amended to match rather than the two platforms
    /// quietly disagreeing. Steps 1 and 3 stay `thinking`.
    ///
    /// `sleeping` and `sad` are unreachable from here on purpose. A
    /// first-time user who has not started yet should be invited, not shown
    /// a mascot asleep, and there is no wizard input that means "failed".
    /// `GuidedStartHermieStateTests` asserts no phase can produce either, so
    /// nobody wires one up silently. Web does the same.
    var hermieState: HermieMascotState {
        Self.hermieState(for: phase, isAllDone: progress.isAllDone)
    }

    /// The mapping itself, as a pure function over the only two inputs it
    /// has. `phase` is `private(set)`, so this is what lets the wizard's
    /// whole reaction vocabulary be enumerated in a test — including the
    /// negative half, that nothing here can reach `sleeping` or `sad`.
    static func hermieState(
        for phase: Phase,
        isAllDone: Bool
    ) -> HermieMascotState {
        switch phase {
        case .idle:                  .idle
        case .active(let step, _):   step == .syncLearn ? .learning : .thinking
        case .celebrating:           isAllDone ? .celebrating : .happy
        case .finished:              .celebrating
        }
    }
}

// MARK: - Reopening from Settings

private struct LVReopenGuidedStartKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Settings › "Show me around". Supplied by `MainTabView`, because
    /// clearing the dismissal is only half of it — the user also has to end
    /// up back on Home, and the tab selection lives there.
    ///
    /// `nil` where no shell is hosting (previews, snapshot suites), which is
    /// also how the row knows to hide itself.
    var lvReopenGuidedStart: (() -> Void)? {
        get { self[LVReopenGuidedStartKey.self] }
        set { self[LVReopenGuidedStartKey.self] = newValue }
    }
}
