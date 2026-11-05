// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/QuickAssistantCardSnapshotTests.swift
//
// The card over a stand-in screen: empty, with a reply, and recording. Light and
// dark.
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
            QuickAssistantCard(session: session, onClose: {}, onOpenChat: { _ in })
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

    private func snap(_ session: QuickAssistantSession, _ name: String) throws {
        try QuickAssistantCardScene.borrowingKeyWindow {
            for dark in [false, true] {
                assertSnapshot(
                    of: QuickAssistantCardScene.view(session: session, dark: dark),
                    as: .image(
                        drawHierarchyInKeyWindow: true,
                        precision: 0.98,
                        perceptualPrecision: 0.96,
                        layout: .device(config: .iPhone13Pro),
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
}
