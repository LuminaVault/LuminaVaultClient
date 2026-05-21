// LuminaVaultClient/LuminaVaultClient/Features/Settings/Skills/SkillsHubView.swift
//
// HER-247 — Settings → Skills hub. Grouped list (Built-in / Custom /
// Disabled), per-skill toggle inline, tap row for full detail.

import LuminaVaultShared
import SwiftUI

struct SkillsHubView: View {
    @State var vm: SkillsHubViewModel
    let detailClient: SkillsClientProtocol

    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
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
            ProgressView().tint(.lvCyan)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
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
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
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
        .listRowBackground(Color.lvNavy.opacity(0.5))
    }
}
