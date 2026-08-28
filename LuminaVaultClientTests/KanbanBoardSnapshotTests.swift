// LuminaVaultClient/LuminaVaultClientTests/KanbanBoardSnapshotTests.swift
//
// Light/Dark coverage for the Kanban board surface, which had none while it
// was hardcoding `Color.black`, a fixed `.cyan`, and an 8%-alpha white card
// border — the combination that made the feature unusable in Light mode.
//
// The board's own `KanbanBoardView` builds its view model internally from a
// client and populates it from `.task`, which a snapshot render does not wait
// for. So these compose the same surface the board composes — `lvBackground`
// under a row of `KanbanColumnView`s holding `KanbanCardView`s — which is
// exactly the layer the tokenization changed. The board's remaining
// contribution is the `.lvBackground()` applied here.
//
// Palette is injected explicitly per scheme: `\.lvPalette` defaults to
// `.cyanGoldDark`, so without this a "light" snapshot would still render the
// dark palette and prove nothing.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class KanbanBoardSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Fixtures

    /// Deterministic UUIDs, built from bytes rather than parsed from a string
    /// so the fixtures need no force unwrap. Only the last byte varies.
    private static func uuid(_ byte: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0x40, 0x00, 0x80, 0, 0, 0, 0, 0, 0, byte))
    }

    /// Fixed ids so the render is byte-stable across runs.
    private static func card(
        _ seed: UInt8,
        title: String,
        body: String? = nil,
        priority: CardPriority? = nil,
        dueAt: Date? = nil
    ) -> CardDTO {
        CardDTO(
            id: uuid(seed),
            columnID: uuid(0xAA),
            title: title,
            body: body,
            priority: priority,
            dueAt: dueAt,
            rank: "a\(seed)",
            updatedAt: nil
        )
    }

    private static var columns: [ColumnDTO] {
        [
            ColumnDTO(
                id: uuid(0xAA),
                title: "Todo",
                rank: "a",
                cards: [
                    card(1, title: "Ship the beta build", body: "TestFlight, then the ten strangers.", priority: .urgent,
                         dueAt: Date(timeIntervalSince1970: 1_000_000_000)),
                    card(2, title: "Write the release notes", priority: .low),
                    card(3, title: "Untriaged idea with no body and no priority"),
                ]
            ),
            ColumnDTO(
                id: uuid(0xBB),
                title: "In Progress",
                rank: "b",
                cards: [
                    card(4, title: "Kanban light mode", body: "Tokenize against LVPalette.", priority: .high),
                ]
            ),
        ]
    }

    /// Mirrors `KanbanBoardView`'s composition: the themed backdrop under a
    /// horizontally scrolling row of columns.
    private func makeView(_ palette: LVPalette) -> some View {
        ZStack {
            Color.clear.lvBackground()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: LVSpacing.base) {
                    ForEach(Self.columns) { column in
                        KanbanColumnView(
                            column: column,
                            otherColumns: Self.columns.filter { $0.id != column.id },
                            onAddCard: { _ in },
                            onOpenCard: { _ in },
                            onMoveCard: { _, _ in },
                            onDropCard: { _ in }
                        )
                    }
                }
                .padding(.vertical)
            }
            .contentMargins(.horizontal, LVSpacing.base, for: .scrollContent)
        }
        .environment(\.lvPalette, palette)
        .transaction { $0.disablesAnimations = true }
        .environment(\.lvAmbientMotionEnabled, false)
    }

    private func snap(_ scheme: ColorScheme, style: UIUserInterfaceStyle, named: String) {
        let view = makeView(LVTheme.cyanGold.palette(for: scheme)).preferredColorScheme(scheme)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: style)
            ),
            named: named
        )
    }

    // MARK: - Cases

    func testKanbanBoardDarkMode() {
        snap(.dark, style: .dark, named: "iPhone13Pro-board-dark")
    }

    /// The regression case. Before tokenization this rendered a near-black
    /// scrim with a fixed-cyan header and an invisible card border.
    func testKanbanBoardLightMode() {
        snap(.light, style: .light, named: "iPhone13Pro-board-light")
    }
}
