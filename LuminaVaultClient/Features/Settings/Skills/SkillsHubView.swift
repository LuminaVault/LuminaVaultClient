// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/SkillsHubView.swift
//
// HER-247 — Settings → Skills hub. Grouped list (Built-in / Custom /
// Disabled), per-skill toggle inline, tap row for full detail.

import LuminaVaultShared
import SwiftUI

struct SkillsHubView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: SkillsHubViewModel
    let detailClient: SkillsClientProtocol

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Skills")
        .lvBackground()
        .task { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let message):
            Text(message)
                .font(LVTypography.footnote.font)
                .foregroundStyle(Color.lvTextMuted)
                .padding()
        case .loaded:
            List {
                if !vm.builtInEnabled.isEmpty {
                    Section("Built-in") {
                        ForEach(vm.builtInEnabled) { skill in
                            rowLink(skill)
                        }
                    }
                }
                if !vm.customEnabled.isEmpty {
                    Section("Custom") {
                        ForEach(vm.customEnabled) { skill in
                            rowLink(skill)
                        }
                    }
                }
                if !vm.disabled.isEmpty {
                    Section("Disabled") {
                        ForEach(vm.disabled) { skill in
                            rowLink(skill)
                        }
                    }
                }
                nvidiaSection
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
        }
    }

    /// Track B (catalog-only) — curated NVIDIA GPU skills from the Hermes
    /// `official/mlops/*` catalog. These are SKILL.md docs that run *inside*
    /// a Hermes instance backed by an NVIDIA GPU (RTX / DGX). They cannot run
    /// on the managed cloud Hermes, so this is a read-only discovery surface:
    /// it shows what's available and how to install it on your own box.
    @ViewBuilder
    private var nvidiaSection: some View {
        Section {
            ForEach(NvidiaGpuSkill.catalog) { skill in
                NavigationLink {
                    NvidiaGpuSkillDetailView(skill: skill)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skill.name).font(LVTypography.body.font)
                        Text(skill.summary)
                            .font(LVTypography.footnote.font)
                            .foregroundStyle(Color.lvTextMuted)
                            .lineLimit(2)
                    }
                }
                .listRowBackground(palette.backgroundBase.opacity(0.5))
            }
        } header: {
            Text("GPU Skills (NVIDIA)")
        } footer: {
            Text("Run on your own Hermes with an NVIDIA GPU (RTX / DGX). Not available on the managed cloud brain.")
                .font(LVTypography.footnote.font)
                .foregroundStyle(Color.lvTextMuted)
        }
    }

    private func rowLink(_ skill: LuminaVaultShared.SkillDTO) -> some View {
        let detailVM = SkillDetailViewModel(skill: skill, client: detailClient)
        detailVM.onSkillUpdated = { [weak vm] updated in vm?.replace(updated) }
        return NavigationLink {
            SkillDetailView(vm: detailVM)
        } label: {
            SkillRowView(skill: skill) { newEnabled in
                Task { await vm.toggle(skill: skill, enabled: newEnabled) }
            }
        }
        .listRowBackground(palette.backgroundBase.opacity(0.5))
    }
}

// MARK: - Track B: NVIDIA GPU skill catalog (read-only)

/// A curated entry from the Hermes `official/mlops/*` catalog that drives an
/// NVIDIA GPU workflow. Static client-side data — these skills execute inside
/// a user's own NVIDIA-backed Hermes, so there is no server round-trip; this
/// is purely a discovery + "how to install" surface.
struct NvidiaGpuSkill: Identifiable, Hashable {
    let id: String          // Hermes skill ref, e.g. "official/mlops/tensorrt-llm"
    let name: String
    let summary: String
    let requirement: String
    let docsURL: URL

    var installCommand: String { "hermes skills install \(id)" }

    static let catalog: [NvidiaGpuSkill] = [
        NvidiaGpuSkill(
            id: "official/mlops/tensorrt-llm",
            name: "TensorRT-LLM",
            summary: "Optimize LLM inference with NVIDIA TensorRT for maximum throughput and lowest latency.",
            requirement: "NVIDIA GPU (A100 / H100-class) on your Hermes host.",
            docsURL: URL(string: "https://hermes-agent.nousresearch.com/docs/reference/optional-skills-catalog")!
        ),
        NvidiaGpuSkill(
            id: "official/mlops/nemo-curator",
            name: "NeMo Curator",
            summary: "GPU-accelerated data preparation for training — fuzzy dedup and quality filtering across modalities.",
            requirement: "NVIDIA GPU infrastructure on your Hermes host.",
            docsURL: URL(string: "https://hermes-agent.nousresearch.com/docs/reference/optional-skills-catalog")!
        ),
    ]
}

/// Read-only detail for a Track B GPU skill: what it does, what hardware it
/// needs, and the exact CLI command to install it on a self-hosted Hermes.
struct NvidiaGpuSkillDetailView: View {
    @Environment(\.lvPalette) private var palette
    let skill: NvidiaGpuSkill

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            List {
                Section {
                    Text(skill.summary)
                        .font(LVTypography.body.font)
                        .foregroundStyle(Color.lvTextMuted)
                }
                Section("Requires") {
                    Label(skill.requirement, systemImage: "cpu")
                        .font(LVTypography.footnote.font)
                }
                Section("Install on your Hermes") {
                    Text(skill.installCommand)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Link("Open Hermes skills catalog", destination: skill.docsURL)
                        .font(LVTypography.footnote.font)
                }
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(palette.backgroundBase.opacity(0.5))
        }
        .navigationTitle(skill.name)
        .lvBackground()
    }
}
