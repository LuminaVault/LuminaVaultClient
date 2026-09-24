//
//  AgentRunActivityWidget.swift
//  LuminaVaultWidgets
//
//  Muse Stage D — the Live Activity for a chat turn Hermie is still working
//  on. Lock screen banner plus the Dynamic Island's compact, expanded and
//  minimal presentations, in the Muse chat style
//  (`_reviews/muse-chat-contract.md`): near-black canvas, the Hermie avatar
//  with its working ring, name + status line, the prompt in a pill, and
//  the running tool as the stage glyph.
//
//  The app starts, updates and ends the activity locally
//  (`AgentRunLiveActivity` in the app target); this only renders
//  `AgentRunAttributes`, which both targets compile from one file. Tapping
//  anywhere opens the thread through `luminavault://chat/<id>`.
//
//  The views below take plain values rather than an ActivityKit context so
//  they can be rendered outside a widget host (review renders).
//

import ActivityKit
import SwiftUI
import WidgetKit

struct AgentRunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentRunAttributes.self) { context in
            AgentRunLockScreenView(
                agentName: context.attributes.agentName,
                state: context.state,
                isStale: context.isStale
            )
            .activityBackgroundTint(MuseActivityPalette.canvas)
            .activitySystemActionForegroundColor(MuseActivityPalette.text)
            .widgetURL(context.attributes.deepLink)
        } dynamicIsland: { context in
            let state = context.state
            let status = AgentRunActivityCopy.status(state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MuseActivityAvatar(stage: state.stage, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AgentRunStageGlyph(state: state)
                        .font(.title3)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    AgentRunNameStatus(agentName: context.attributes.agentName, status: status)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AgentRunIslandBottom(state: state)
                }
            } compactLeading: {
                MuseActivityAvatar(stage: state.stage, size: 24)
            } compactTrailing: {
                AgentRunStageGlyph(state: state)
            } minimal: {
                MuseActivityAvatar(stage: state.stage, size: 24)
            }
            .widgetURL(context.attributes.deepLink)
            .keylineTint(MuseActivityPalette.accent)
        }
    }
}

// MARK: - Palette

/// The Muse chat tokens for Lumina, dark variant. The lock screen and the
/// island are always dark surfaces, so there is no light variant here.
enum MuseActivityPalette {
    /// `muse.canvas` — `#070d1e`.
    static let canvas = Color(red: 7 / 255, green: 13 / 255, blue: 30 / 255)
    /// `muse.userBubble` / `--lv-secondary` — `#0096ff`. The ring and accents.
    static let accent = Color(red: 0, green: 150 / 255, blue: 1)
    /// `muse.pill` — white 10%.
    static let pill = Color.white.opacity(0.10)
    static let text = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let snag = Color(red: 1, green: 0.62, blue: 0.4)
}

// MARK: - Copy

enum AgentRunActivityCopy {
    /// The status line, with the stale case said honestly: once the app has
    /// been suspended for a while the follower is not listening, so the last
    /// known step is no longer news.
    static func status(_ state: AgentRunAttributes.ContentState, isStale: Bool) -> String {
        if isStale, state.stage == .working || state.stage == .waiting {
            return "may have finished — tap to check"
        }
        return state.status
    }

    static func glyph(_ state: AgentRunAttributes.ContentState) -> String {
        switch state.stage {
        case .waiting: "hand.raised.fill"
        case .done: "checkmark"
        case .failed: "exclamationmark"
        case .working: toolGlyph(state.toolLabel)
        }
    }

    /// An SF Symbol for the running tool's verb phrase (`MuseToolLabel`).
    static func toolGlyph(_ label: String?) -> String {
        guard let label = label?.lowercased() else { return "ellipsis" }
        let table: [(String, String)] = [
            ("web", "globe"),
            ("page", "doc.text"),
            ("vault", "books.vertical"),
            ("file", "doc"),
            ("code", "terminal"),
            ("calendar", "calendar"),
            ("email", "envelope"),
            ("weather", "cloud.sun"),
            ("location", "location"),
            ("health", "heart"),
            ("image", "photo"),
            ("memory", "brain"),
            ("schedul", "clock"),
            ("search", "magnifyingglass"),
        ]
        return table.first { label.contains($0.0) }?.1 ?? "sparkles"
    }
}

// MARK: - Pieces

/// The 110pt header avatar, shrunk: idle art plus the ring that carries the
/// working state (contract: "the ring carries the working state"). The ring
/// is a static stroke — a Live Activity cannot run an animation loop.
struct MuseActivityAvatar: View {
    let stage: AgentRunAttributes.ContentState.Stage
    let size: CGFloat
    var avatar: Image = Image("HermieAvatar")

    var body: some View {
        avatar
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(ringWidth + 1)
            .overlay(ring)
            .accessibilityHidden(true)
    }

    private var ringWidth: CGFloat { max(1.5, size / 16) }

    @ViewBuilder private var ring: some View {
        switch stage {
        case .working:
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(MuseActivityPalette.accent, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        case .waiting:
            Circle().stroke(MuseActivityPalette.accent.opacity(0.9), lineWidth: ringWidth)
        case .done:
            Circle().stroke(MuseActivityPalette.accent.opacity(0.35), lineWidth: ringWidth)
        case .failed:
            Circle().stroke(MuseActivityPalette.snag.opacity(0.6), lineWidth: ringWidth)
        }
    }
}

struct AgentRunNameStatus: View {
    let agentName: String
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(agentName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MuseActivityPalette.text)
            Text(status)
                .font(.system(size: 13))
                .foregroundStyle(MuseActivityPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AgentRunStageGlyph: View {
    let state: AgentRunAttributes.ContentState

    var body: some View {
        Image(systemName: AgentRunActivityCopy.glyph(state))
            .fontWeight(.semibold)
            .foregroundStyle(state.stage == .failed ? MuseActivityPalette.snag : MuseActivityPalette.accent)
            .accessibilityHidden(true)
    }
}

/// The prompt, in a `muse.pill`. The running tool is not repeated here: the
/// status line already says it ("is searching the web") and the stage glyph
/// shows it.
struct AgentRunTitlePill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(MuseActivityPalette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MuseActivityPalette.pill, in: Capsule())
    }
}

struct AgentRunIslandBottom: View {
    let state: AgentRunAttributes.ContentState

    var body: some View {
        AgentRunTitlePill(title: state.title)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }
}

// MARK: - Lock screen

struct AgentRunLockScreenView: View {
    let agentName: String
    let state: AgentRunAttributes.ContentState
    var isStale = false
    var avatar: Image = Image("HermieAvatar")

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MuseActivityAvatar(stage: state.stage, size: 48, avatar: avatar)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    AgentRunNameStatus(
                        agentName: agentName,
                        status: AgentRunActivityCopy.status(state, isStale: isStale)
                    )
                    AgentRunStageGlyph(state: state)
                        .font(.system(size: 15))
                }
                AgentRunTitlePill(title: state.title)
            }
        }
        .padding(16)
        .background(MuseActivityPalette.canvas)
    }
}
