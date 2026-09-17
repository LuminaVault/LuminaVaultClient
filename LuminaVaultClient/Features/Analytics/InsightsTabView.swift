import SwiftUI

/// Personal intelligence hub. It keeps the established reflection tools while
/// making memory health and usage intelligence a first-class tab destination.
///
/// Both pickers live in the navigation chrome rather than in the content:
/// Overview/Reflect as a segmented control pinned under the title, and the
/// analytics range as a trailing bar menu. That leaves the scroll view to
/// carry nothing but the sections themselves.
struct InsightsTabView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case reflect = "Reflect"
        var id: String { rawValue }
    }

    /// Which segment the tab opens on. Injectable for the same reason the
    /// view models are: a snapshot has to be able to ask for Reflect.
    @State var section: Section = .overview
    /// Owned here, not in `AnalyticsDashboardScreen`: the range menu is a
    /// navigation-bar item of this tab root, so the bar and the content have
    /// to read the same `range`.
    @State var analyticsViewModel: AnalyticsDashboardViewModel
    @State var reflectViewModel: ReflectViewModel
    @State var runner: ReflectionRunner

    let httpClient: BaseHTTPClient
    let vaultClient: VaultClientProtocol
    let memoryClient: MemoryClientProtocol

    var body: some View {
        content
            .safeAreaInset(edge: .top) { sectionPicker }
            // The title lives here rather than on `AnalyticsDashboardView` so
            // it appears once, for both sections.
            .navigationTitle("Insights")
            .toolbar { rangeToolbarItem }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            AnalyticsDashboardScreen(viewModel: analyticsViewModel, httpClient: httpClient)
        case .reflect:
            ReflectTabView(vm: reflectViewModel, runner: runner,
                           vaultClient: vaultClient, memoryClient: memoryClient)
        }
    }

    private var sectionPicker: some View {
        Picker("Insights section", selection: $section) {
            ForEach(Section.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// Only Overview is ranged, so Reflect does not carry a control that
    /// changes nothing it shows.
    @ToolbarContentBuilder
    private var rangeToolbarItem: some ToolbarContent {
        if section == .overview {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Range", selection: rangeSelection) {
                        ForEach(AnalyticsRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                } label: {
                    // `Text`, not `Label`. A toolbar takes a `Label`'s icon and
                    // drops its title, so the bar showed a bare calendar glyph
                    // and never said which range was active —
                    // `.labelStyle(.titleAndIcon)` does not change that: with
                    // it applied the rendered bar item kept the same width to
                    // the pixel, i.e. the title was still discarded. A label
                    // with no icon to extract leaves the toolbar nothing to
                    // render but the range itself.
                    Text(analyticsViewModel.range.title)
                        .accessibilityLabel("Range, \(analyticsViewModel.range.title)")
                }
            }
        }
    }

    /// `setRange` is the view model's only way in — it records the change and
    /// reloads — so the menu writes through it instead of assigning `range`.
    private var rangeSelection: Binding<AnalyticsRange> {
        Binding(
            get: { analyticsViewModel.range },
            set: { newValue in
                Task { await analyticsViewModel.setRange(newValue) }
            },
        )
    }
}
