// LuminaVaultClient/LuminaVaultClientTests/HermesRunsViewSnapshotTests.swift
//
// Hermes Companion Phase 1 — image snapshots for the three run surfaces.
// Recorded on the iPhone 16 Pro simulator CI pins (see .github/workflows/ci.yml);
// the canvas is fixed by `layout: .device(config: .iPhone13Pro)` but the render
// still varies with the host device class, so both must match.

@testable import LuminaVaultClient
@testable import LuminaVaultShared
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@MainActor
final class HermesRunsViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Runs list

    func testRunsListGroupsBlockedRunsFirst() {
        let client = StubHermesRunsClient()
        let vm = HermesRunsListViewModel(
            client: client,
            runs: [
                .stub(status: .waitingForApproval, prompt: "Clean up the build directory", id: Self.id(1), startedAt: Self.ago(5 * 60)),
                .stub(status: .running, prompt: "Summarise this week's notes", lastEvent: "tool.started", id: Self.id(2), startedAt: Self.ago(20 * 60)),
                .stub(status: .completed, prompt: "Check the deploy logs", id: Self.id(3), startedAt: Self.ago(65 * 60)),
                .stub(status: .failed, prompt: "Rebuild the search index", id: Self.id(4), startedAt: Self.ago(3 * 60 * 60)),
            ]
        )
        let view = NavigationStack {
            HermesRunsListView(vm: vm, client: client)
        }
        snap(view, named: "iPhone16Pro-runs-list-dark")
    }

    // MARK: - Run detail

    func testRunDetailShowsTheApprovalPromptAndTrail() {
        let client = StubHermesRunsClient()
        let vm = HermesRunDetailViewModel(
            client: client,
            run: HermesRunDTO(
                id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                hermesRunID: "run_ab12",
                status: .waitingForApproval,
                prompt: "Clean up the build directory and re-run the tests",
                startedAt: Self.ago(65 * 60),
                lastEvent: "approval.request",
                lastSeq: 3,
                pendingApproval: HermesRunPendingApprovalDTO(
                    command: "rm -rf ./build && swift test",
                    choices: [.once, .session, .deny],
                    requestedAt: Self.ago(5 * 60)
                )
            )
        )
        let view = NavigationStack {
            HermesRunDetailView(vm: vm)
        }
        snap(view, named: "iPhone16Pro-run-detail-approval-dark")
    }

    // MARK: - Run as agent

    func testRunAsAgentSheetShowsTheDraft() {
        let client = StubHermesRunsClient()
        let view = NavigationStack {
            HermesRunStartView(
                vm: HermesRunStartViewModel(
                    client: client,
                    prompt: "Summarise this week's notes and file them under raw/weekly."
                ),
                client: client
            )
        }
        snap(view, named: "iPhone16Pro-run-as-agent-dark")
    }

    // MARK: - Helper

    /// Relative dates are rendered as "1 hour ago" / "5 minutes ago", so the
    /// fixtures are anchored to *now* rather than to a fixed epoch: a fixed
    /// date renders "3 years ago" today and "4 years ago" in 2027, which
    /// would silently invalidate these baselines. Offsets sit well inside a
    /// bucket so the wording cannot flip mid-run.
    private static func ago(_ seconds: TimeInterval) -> Date {
        Date().addingTimeInterval(-seconds)
    }

    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func snap(_ view: some View, named: String) {
        assertSnapshot(
            of: view
                .transaction { $0.disablesAnimations = true }
                // Freezes `repeatForever` hero drift at frame zero; the
                // components gate on this and `disablesAnimations` alone does
                // not reach an explicit `withAnimation` from `onAppear`.
                .environment(\.lvAmbientMotionEnabled, false),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: named
        )
    }
}
