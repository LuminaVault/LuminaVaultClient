// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/QuickAssistantCardSnapshotTests.swift
//
// The card over a stand-in screen: empty, with a reply, recording, and with each
// kind of action (done chip, confirm for a calendar event and for forgetting a
// memory, permission, and a crowded card on the smallest phone). Light and dark.
//
// Every case has the glow and the waveform at rest, through `lvAmbientMotionEnabled`,
// so there is no separate Reduce Motion case: it would be the same picture as the
// empty one. Reduce Motion takes that same still path, and the breathing it turns
// off cannot be pinned to a frame.
//
// These draw in the host app's key window, unlike the rest of the suite. A plain
// layer render has no glow at all and flattens the material, and those are most of
// what this card looks like. See `QuickAssistantCardScene.borrowingKeyWindow`.
//
// Baselines are recorded on CI's iPhone 16 Pro / iOS 26.4 renderer by the
// `record-snapshots` workflow (`.github/workflows/ci.yml`), never locally, so
// these cases have no reference images until that runs.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
enum QuickAssistantCardScene {
    /// The card over a screen, the way the shell shows it.
    static func view(session: QuickAssistantSession, dark: Bool) -> some View {
        ZStack {
            StandInScreen()
            QuickAssistantCard(session: session, onClose: {}, onOpenChat: { _ in }, onRoute: { _ in })
        }
        .environment(\.lvAmbientMotionEnabled, false)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
        .preferredColorScheme(dark ? .dark : .light)
    }

    /// `drawHierarchyInKeyWindow` calls `fatalError` with no key window, resizes the
    /// one it finds, and leaves it with no root view controller. So this skips
    /// instead of aborting the run (or, when `CI` is set, fails), and hands the window back as it found it.
    struct NoKeyWindow: Error, CustomStringConvertible {
        var description: String { "Drawing the card needs the host app's key window, and there is none." }
    }

    static func borrowingKeyWindow(_ body: () -> Void) throws {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let keyWindow else {
            // On CI a missing window means the baselines were never compared, which
            // must not read as a pass.
            if ProcessInfo.processInfo.environment["CI"] != nil {
                throw NoKeyWindow()
            }
            throw XCTSkip("Drawing the card needs the host app's key window, and there is none.")
        }
        let frame = keyWindow.frame
        let root = keyWindow.rootViewController
        defer {
            keyWindow.rootViewController = root
            keyWindow.frame = frame
        }
        body()
    }

    static func empty() -> QuickAssistantSession {
        QuickAssistantFixture.session()
    }

    static func reply() async -> QuickAssistantSession {
        let conversations = QuickAssistantStubConversations()
        conversations.script = [
            .token(
                "Your next meeting is the design review at 3 pm. You have one open loop from it: send Priya the updated flows."
            ),
            .done,
        ]
        let session = QuickAssistantFixture.session(conversations: conversations)
        session.send("What's on this afternoon?", viaVoice: false)
        for _ in 0 ..< 400 where session.model.reply.isEmpty || session.model.phase != .idle {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return session
    }

    /// A finished turn with `actions`, as the stream would deliver them.
    static func turn(
        reply: String,
        actions: [AssistantActionDTO]
    ) async -> QuickAssistantSession {
        let conversations = QuickAssistantStubConversations()
        conversations.script = [.token(reply)] + actions.map { .assistantAction($0) } + [.done]
        let session = QuickAssistantFixture.session(conversations: conversations)
        session.send("Do it", viaVoice: false)
        for _ in 0 ..< 400 where session.model.actions.count < actions.count || session.model.phase != .idle {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return session
    }

    static func done() async -> QuickAssistantSession {
        await turn(reply: "Done. I saved that for you.", actions: [
            AssistantActionDTO(id: UUID(), kind: .done, summary: "Reminder set: Call the bank, tomorrow 9:00 AM"),
            AssistantActionDTO(id: UUID(), kind: .done, summary: "Saved to memory: window seats"),
        ])
    }

    static func confirmCalendar() async -> QuickAssistantSession {
        await turn(reply: "I can add that. Check the details first.", actions: [calendarAsk(minutes: 5)])
    }

    static func confirmForget() async -> QuickAssistantSession {
        await turn(reply: "That memory will be gone for good.", actions: [forgetAsk])
    }

    static func permission() async -> QuickAssistantSession {
        await turn(reply: "I need your say-so first.", actions: [
            AssistantActionDTO(id: UUID(), kind: .needsPermission, summary: "Allow Calendar changes in Data Access to add events."),
        ])
    }

    /// A long reply, three confirm cards, a permission card and several chips.
    static func crowded() async -> QuickAssistantSession {
        let reply = String(repeating: "Here is the plan for the week, in order, with the loose ends from Monday folded in. ", count: 6)
        return await turn(reply: reply, actions: [
            AssistantActionDTO(id: UUID(), kind: .done, summary: "Saved to memory: window seats"),
            AssistantActionDTO(id: UUID(), kind: .done, summary: "Reminder set: Call the bank, tomorrow 9:00 AM"),
            AssistantActionDTO(id: UUID(), kind: .done, summary: "Opening Brain"),
            calendarAsk(minutes: 5),
            calendarAsk(minutes: 5, title: "Design review"),
            forgetAsk,
            AssistantActionDTO(id: UUID(), kind: .needsPermission, summary: "Allow Calendar changes in Data Access to add events."),
        ])
    }

    private static func calendarAsk(minutes: Double, title: String = "Dentist") -> AssistantActionDTO {
        AssistantActionDTO(
            id: UUID(), kind: .needsConfirm,
            summary: "Add to Calendar: \(title), Thu 3 Nov 3:00 PM at Dr. Ferreira",
            expiresAt: Date().addingTimeInterval(minutes * 60)
        )
    }

    private static let forgetAsk = AssistantActionDTO(
        id: UUID(), kind: .needsConfirm,
        summary: "Forget this memory: \u{201C}I prefer window seats on long flights\u{201D}",
        expiresAt: Date().addingTimeInterval(300)
    )

    static func recording() async -> QuickAssistantSession {
        let recognizer = StubSpeechRecognizer(available: true, authorized: true)
        let session = QuickAssistantFixture.session(recognizer: recognizer)
        await session.voice.startRecording()
        recognizer.emit("Remind me to call the bank")
        for _ in 0 ..< 400 where session.voice.liveTranscript.isEmpty {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return session
    }

    private struct StandInScreen: View {
        @Environment(\.lvPalette) private var palette

        var body: some View {
            VStack(alignment: .leading, spacing: LVSpacing.base) {
                Text("Home")
                    .lvFont(.display)
                    .foregroundStyle(palette.textPrimary)
                ForEach(0 ..< 6, id: \.self) { index in
                    Text("Saved note \(index + 1)")
                        .lvFont(.body)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LVSpacing.base)
                        .background(palette.surface, in: .rect(cornerRadius: LVRadius.md))
                }
                Spacer()
            }
            .padding(LVSpacing.base)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.backgroundBase)
        }
    }
}

@MainActor
final class QuickAssistantCardSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private func snap(
        _ session: QuickAssistantSession,
        _ name: String,
        config: ViewImageConfig = .iPhone13Pro
    ) throws {
        try QuickAssistantCardScene.borrowingKeyWindow {
            for dark in [false, true] {
                assertSnapshot(
                    of: QuickAssistantCardScene.view(session: session, dark: dark),
                    as: .image(
                        drawHierarchyInKeyWindow: true,
                        precision: 0.98,
                        perceptualPrecision: 0.96,
                        layout: .device(config: config),
                        traits: .init(userInterfaceStyle: dark ? .dark : .light)
                    ),
                    testName: "\(name)-\(dark ? "dark" : "light")"
                )
            }
        }
    }

    func testEmpty() async throws {
        try snap(QuickAssistantCardScene.empty(), "quick-assistant-empty")
    }

    func testReply() async throws {
        try await snap(QuickAssistantCardScene.reply(), "quick-assistant-reply")
    }

    func testVoiceRecording() async throws {
        try await snap(QuickAssistantCardScene.recording(), "quick-assistant-recording")
    }

    func testDone() async throws {
        try await snap(QuickAssistantCardScene.done(), "quick-assistant-done")
    }

    func testConfirmCalendar() async throws {
        try await snap(QuickAssistantCardScene.confirmCalendar(), "quick-assistant-confirm-calendar")
    }

    func testConfirmForget() async throws {
        try await snap(QuickAssistantCardScene.confirmForget(), "quick-assistant-confirm-forget")
    }

    func testPermission() async throws {
        try await snap(QuickAssistantCardScene.permission(), "quick-assistant-permission")
    }

    func testCrowdedCardOnTheSmallestPhone() async throws {
        try await snap(QuickAssistantCardScene.crowded(), "quick-assistant-crowded-se", config: .iPhoneSe)
    }
}
