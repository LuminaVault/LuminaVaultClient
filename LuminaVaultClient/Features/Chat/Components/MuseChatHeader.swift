// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/MuseChatHeader.swift
//
// Muse chat header (`_reviews/muse-chat-contract.md`, Stage A).
//
// A 56pt bar — a 40pt circular button on the left, a "New chat" pill on the
// right — with Hermie centred at 110pt, hanging ~55pt below the bar into the
// transcript. Under Hermie, one pill: the agent's name, and a status line.
//
// This view owns no state machine. It says what it is told: `ChatView` maps
// the phase it already has onto the status copy. Stage B replaces that
// mapping; the header does not change.
//
// Rides `.safeAreaInset(edge: .top)`, so the transcript scrolls underneath.
// A canvas → clear scrim behind it keeps the name and status legible over
// whatever is passing below. The scrim is the required path, not a fallback
// that only kicks in when blur is off: there is no blur.

import SwiftUI

struct MuseChatHeader<Accessory: View>: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var name: String = "Hermie"
    /// Second line of the pill. "Ready", "is thinking", …
    let status: String
    let mascotState: HermieMascotState
    /// Draws the ring around the avatar. The contract has no "working" art;
    /// the ring is what says Hermie is busy.
    let isWorking: Bool
    /// Marks the status line as a warning (e.g. a provider fallback).
    var isAttention: Bool = false
    /// When set, the name pill is a button that opens the run details.
    var isDetailExpanded: Binding<Bool>?
    /// Left circle button. `nil` hides it (a chat with nowhere to go back to).
    var onShowConversations: (() -> Void)?
    let onNewChat: () -> Void
    /// Sits under the pill: the tool trail and the run details.
    @ViewBuilder var accessory: () -> Accessory

    private var muse: LVMuseColors { palette.muse(scheme) }

    private static var barHeight: CGFloat { 56 }
    private static var sideButtonSize: CGFloat { 40 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                bar
                VStack(spacing: -LVSpacing.md) {
                    MuseAvatar(state: mascotState, isWorking: isWorking, fill: muse.pill)
                    namePill
                }
            }
            accessory()
        }
        .padding(.bottom, LVSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { scrim }
    }

    // MARK: - Bar

    private var bar: some View {
        HStack {
            if let onShowConversations {
                Button(action: onShowConversations) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(muse.text)
                        .frame(width: Self.sideButtonSize, height: Self.sideButtonSize)
                        .background(Circle().fill(muse.pill))
                        .frame(width: LVSize.tapTarget, height: LVSize.tapTarget)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All chats")
            }
            Spacer(minLength: 0)
            Button(action: onNewChat) {
                HStack(spacing: LVSpacing.xs) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("New chat")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(muse.text)
                .padding(.horizontal, LVSpacing.md)
                .frame(height: Self.sideButtonSize)
                .background(Capsule().fill(muse.pill))
                .frame(minHeight: LVSize.tapTarget)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LVSpacing.md)
        .frame(height: Self.barHeight)
    }

    // MARK: - Name pill

    @ViewBuilder
    private var namePill: some View {
        if let isDetailExpanded {
            Button {
                isDetailExpanded.wrappedValue.toggle()
            } label: {
                pillLabel(chevron: isDetailExpanded.wrappedValue ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.plain)
            .accessibilityHint(isDetailExpanded.wrappedValue ? "Hides run details" : "Shows run details")
        } else {
            pillLabel(chevron: nil)
        }
    }

    private func pillLabel(chevron: String?) -> some View {
        HStack(spacing: LVSpacing.sm) {
            VStack(spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(muse.text)
                HStack(spacing: LVSpacing.xs) {
                    if isAttention {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .accessibilityHidden(true)
                    }
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(muse.textSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            if let chevron {
                Image(systemName: chevron)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(muse.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.sm - 2)
        .background {
            // The canvas under the pill fill keeps it opaque: 10% white alone
            // would let the transcript show through the status text.
            Capsule().fill(muse.canvas)
            Capsule().fill(muse.pill)
        }
        .frame(maxWidth: 260)
        .contentShape(.capsule)
        // One announcement, "Hermie, is thinking", instead of two stops.
        .accessibilityElement(children: .combine)
        .lvAnimation(LVMotion.standard, value: status)
    }

    // MARK: - Scrim

    /// Solid canvas behind the bar (and up through the status bar), then a
    /// 120pt fade to clear behind Hermie.
    private var scrim: some View {
        VStack(spacing: 0) {
            // Only the solid part runs up under the status bar. Ignoring the
            // safe area on the whole stack shifted the fade up by the status
            // bar's height, so the transcript showed through behind Hermie.
            muse.canvas
                .frame(height: Self.barHeight)
                .ignoresSafeArea(edges: .top)
            LinearGradient(
                colors: [muse.canvas, muse.canvas.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: LVMuse.scrimHeight)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension MuseChatHeader where Accessory == EmptyView {
    init(
        name: String = "Hermie",
        status: String,
        mascotState: HermieMascotState,
        isWorking: Bool,
        isAttention: Bool = false,
        isDetailExpanded: Binding<Bool>? = nil,
        onShowConversations: (() -> Void)? = nil,
        onNewChat: @escaping () -> Void
    ) {
        self.init(
            name: name,
            status: status,
            mascotState: mascotState,
            isWorking: isWorking,
            isAttention: isAttention,
            isDetailExpanded: isDetailExpanded,
            onShowConversations: onShowConversations,
            onNewChat: onNewChat,
            accessory: { EmptyView() }
        )
    }
}

// MARK: - Avatar

/// Hermie at 110pt in a disc, with the working ring when busy.
private struct MuseAvatar: View {
    let state: HermieMascotState
    let isWorking: Bool
    let fill: Color

    var body: some View {
        ZStack {
            Circle().fill(fill)
            HermieMascotView(
                state: state,
                size: LVMuse.avatarSize,
                fallbackImageName: "OnboardingMascot",
                hostTab: "think"
            )
            .clipShape(.circle)
            if isWorking {
                MuseWorkingRing()
            }
        }
        .frame(width: LVMuse.avatarSize, height: LVMuse.avatarSize)
        .accessibilityHidden(true)
    }
}

/// A partial arc that turns while Hermie works. Under Reduce Motion (or in a
/// snapshot, which freezes ambient motion) it is a full, still stroke — the
/// state still reads, nothing moves.
private struct MuseWorkingRing: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lvAmbientMotionEnabled) private var ambientMotionEnabled
    @State private var turned = false

    private var isStatic: Bool { reduceMotion || !ambientMotionEnabled }

    var body: some View {
        Group {
            if isStatic {
                Circle()
                    .stroke(palette.glowPrimary.opacity(0.8), lineWidth: 3)
            } else {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        palette.glowPrimary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(turned ? 360 : 0))
                    .lvRepeatingAnimation(
                        .linear(duration: 1.2).repeatForever(autoreverses: false),
                        value: turned
                    )
                    .onAppear { turned = true }
            }
        }
        .padding(-3)
    }
}

// MARK: - Previews

#Preview("States · dark") {
    MuseChatHeaderPreviewGrid()
        .preferredColorScheme(.dark)
}

#Preview("States · light") {
    MuseChatHeaderPreviewGrid()
        .preferredColorScheme(.light)
}

private struct MuseChatHeaderPreviewGrid: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(spacing: LVSpacing.xl) {
                MuseChatHeader(status: "Ready", mascotState: .idle, isWorking: false,
                               onShowConversations: {}, onNewChat: {})
                MuseChatHeader(status: "is listening", mascotState: .idle, isWorking: false,
                               onShowConversations: {}, onNewChat: {})
                MuseChatHeader(status: "is thinking", mascotState: .thinking, isWorking: true,
                               isDetailExpanded: $expanded, onShowConversations: {}, onNewChat: {})
                MuseChatHeader(status: "is still working — you can leave", mascotState: .thinking,
                               isWorking: true, onShowConversations: {}, onNewChat: {})
                MuseChatHeader(status: "hit a snag", mascotState: .idle, isWorking: false,
                               isAttention: true, onNewChat: {})
            }
        }
        .background(palette.muse(scheme).canvas)
    }
}
