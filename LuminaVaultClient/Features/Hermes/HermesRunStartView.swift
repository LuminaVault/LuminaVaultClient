// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesRunStartView.swift
//
// Hermes Companion Phase 1 — "Run as agent" from the chat composer.
//
// Chat asks a model a question; this hands the same words to the user's own
// Hermes as a task it will actually carry out, with tool calls the user
// approves. That difference deserves a confirmation step rather than a
// silent send, so the sheet shows the prompt, says where it will run, and
// only then starts.
//
// On success the sheet stays put and becomes the run's detail screen, so the
// approval prompt lands in front of the person who just asked for it.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class HermesRunStartViewModel {
    var prompt: String
    private(set) var isStarting = false
    private(set) var failure: HermesRunsFailure?
    /// Set once Hermes has accepted the run; the sheet swaps to its detail.
    private(set) var startedRun: HermesRunDTO?

    private let client: any HermesRunsClientProtocol
    private let conversationID: UUID?

    init(client: any HermesRunsClientProtocol, prompt: String, conversationID: UUID? = nil) {
        self.client = client
        self.prompt = prompt
        self.conversationID = conversationID
    }

    var canStart: Bool {
        !isStarting && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() async {
        guard canStart else { return }
        isStarting = true
        failure = nil
        defer { isStarting = false }
        do {
            startedRun = try await client.start(
                HermesRunStartRequest(
                    prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                    // Linking the run to the conversation makes the server
                    // append a system message pointing back at it, so the
                    // transcript records that the agent was dispatched.
                    conversationID: conversationID
                )
            )
        } catch is CancellationError {
            return
        } catch {
            failure = HermesRunsFailure(error)
        }
    }
}

struct HermesRunStartView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State var vm: HermesRunStartViewModel
    let client: any HermesRunsClientProtocol

    var body: some View {
        Group {
            if let run = vm.startedRun {
                HermesRunDetailView(vm: HermesRunDetailViewModel(client: client, run: run))
            } else {
                composeForm
            }
        }
    }

    private var composeForm: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: LVSpacing.lg) {
                    Text("Hermes runs this on your own machine, with your tools. It asks before anything risky.")
                        .lvFont(.callout)
                        .foregroundStyle(palette.textSecondary)

                    VStack(alignment: .leading, spacing: LVSpacing.sm) {
                        Text("TASK")
                            .lvFont(.kicker)
                            .foregroundStyle(palette.textSecondary)
                        TextEditor(text: $vm.prompt)
                            .lvFont(.body)
                            .foregroundStyle(palette.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 140)
                            .padding(LVSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                                    .fill(palette.surface.opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                                    .stroke(palette.surfaceStroke, lineWidth: 1)
                            )
                    }

                    if let failure = vm.failure {
                        VStack(alignment: .leading, spacing: LVSpacing.xs) {
                            Text(failure.message)
                                .lvFont(.callout)
                                .foregroundStyle(.red)
                            if let guidance = failure.guidance {
                                Text(guidance)
                                    .lvFont(.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                        }
                    }

                    Button {
                        Task { await vm.start() }
                    } label: {
                        if vm.isStarting {
                            ProgressView().tint(palette.primary)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Run on my Hermes")
                                .lvFont(.button)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primary)
                    .controlSize(.large)
                    .disabled(!vm.canStart)
                }
                .padding(LVSpacing.lg)
            }
        }
        .navigationTitle("Run as agent")
        .navigationBarTitleDisplayMode(.inline)
        .lvBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

/// Identifies the "Run as agent" sheet by the draft it opened with, so
/// `.sheet(item:)` re-presents when the draft changes rather than reusing a
/// stale one.
struct AgentRunDraft: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
}

/// Wraps a run id for `.sheet(item:)` presentation from a push deep link.
struct HermesRunPresentation: Identifiable, Equatable {
    let id: UUID
}
