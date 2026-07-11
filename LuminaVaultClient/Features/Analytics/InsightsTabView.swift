import SwiftUI

/// Personal intelligence hub. It keeps the established reflection tools while
/// making memory health and usage intelligence a first-class tab destination.
struct InsightsTabView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case reflect = "Reflect"
        var id: String { rawValue }
    }

    @State private var section: Section = .overview
    @State var reflectViewModel: ReflectViewModel
    @State var runner: ReflectionRunner

    let httpClient: BaseHTTPClient
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol
    let onOpenRecommendation: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Insights section", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            switch section {
            case .overview:
                NavigationStack {
                    AnalyticsDashboardScreen(httpClient: httpClient,
                                             onOpenRecommendation: onOpenRecommendation)
                }
            case .reflect:
                ReflectTabView(vm: reflectViewModel, runner: runner,
                               vaultClient: vaultClient, memoryClient: memoryClient)
            }
        }
    }
}
