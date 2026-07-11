import LuminaVaultShared
import SwiftUI

struct MarketplacePluginDetailView: View {
    @State private var viewModel: MarketplacePluginDetailViewModel

    init(plugin: MarketplacePluginDTO, install: PluginInstallDTO?, client: any PluginsClientProtocol, onChange: @escaping () async -> Void) {
        _viewModel = State(initialValue: MarketplacePluginDetailViewModel(
            plugin: plugin, install: install, client: client, onChange: onChange
        ))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Publisher") {
                    Label(
                        viewModel.plugin.publisher.displayName,
                        systemImage: viewModel.plugin.publisher.verified ? "checkmark.seal.fill" : "person.crop.circle"
                    )
                    .foregroundStyle(viewModel.plugin.publisher.verified ? .blue : .secondary)
                }
                LabeledContent("Rating", value: viewModel.plugin.ratingCount == 0
                    ? "No ratings"
                    : "\(viewModel.plugin.ratingAverage.formatted(.number.precision(.fractionLength(1)))) / 5")
                LabeledContent("Runtime", value: viewModel.plugin.latestVersion.runtimeKind.rawValue.capitalized)
            }

            if !viewModel.plugin.screenshots.isEmpty {
                Section("Preview") {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(viewModel.plugin.screenshots, id: \.self) { screenshot in
                                AsyncImage(url: URL(string: screenshot)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    ProgressView()
                                }
                                .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 12)
                                .frame(minHeight: 180)
                                .clipShape(.rect(cornerRadius: 16))
                                .accessibilityLabel("\(viewModel.plugin.name) preview")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }

            Section("About") {
                Text(viewModel.plugin.description).foregroundStyle(.secondary)
            }

            if !viewModel.plugin.latestVersion.permissions.isEmpty {
                Section {
                    ForEach(viewModel.plugin.latestVersion.permissions, id: \.self) { permission in
                        Button {
                            viewModel.toggle(permission)
                        } label: {
                            Label(
                                Self.permissionLabel(permission),
                                systemImage: viewModel.selectedPermissions.contains(permission) ? "checkmark.circle.fill" : "circle"
                            )
                        }
                        .accessibilityValue(viewModel.selectedPermissions.contains(permission) ? "Approved" : "Not approved")
                    }
                    if !viewModel.plugin.latestVersion.networkHosts.isEmpty {
                        Text("Allowed websites: \(viewModel.plugin.latestVersion.networkHosts.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    Text("Every requested permission must be approved before installation.")
                }
            }

            if !viewModel.plugin.configFields.isEmpty {
                Section("Configuration") {
                    ForEach(viewModel.plugin.configFields, id: \.key) { field in
                        MarketplaceConfigField(field: field, values: $viewModel.values)
                    }
                }
            }

            Section {
                Button(viewModel.install == nil ? "Install" : "Update") {
                    Task { await viewModel.installPlugin() }
                }
                .disabled(!viewModel.hasAllPermissions || viewModel.state == .working)
                if viewModel.install != nil {
                    Button("Uninstall", role: .destructive) {
                        Task { await viewModel.uninstallPlugin() }
                    }
                    .disabled(viewModel.state == .working)
                }
            }

            switch viewModel.state {
            case .idle:
                EmptyView()
            case .working:
                Section { ProgressView().frame(maxWidth: .infinity) }
            case .installed:
                Section { Label("Installed and ready to use.", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
            case let .error(message):
                Section { Text(message).foregroundStyle(.red) }
            }

            Section("Reviews") {
                if viewModel.install != nil {
                    Stepper("Your rating: \(viewModel.rating) of 5", value: $viewModel.rating, in: 1 ... 5)
                    TextField("Share your experience", text: $viewModel.reviewBody, axis: .vertical)
                        .lineLimit(3 ... 6)
                    Button("Save review") {
                        Task { await viewModel.submitRating() }
                    }
                    .disabled(viewModel.state == .working)
                }
                if let reviewsError = viewModel.reviewsError {
                    Text(reviewsError).foregroundStyle(.secondary)
                }
                if viewModel.reviews.isEmpty {
                    ContentUnavailableView("No reviews yet", systemImage: "star")
                } else {
                    ForEach(viewModel.reviews) { review in
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(review.authorUsername, value: "\(review.rating) / 5")
                            if let body = review.body {
                                Text(body).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.plugin.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadReviews() }
    }

    private static func permissionLabel(_ permission: PluginPermission) -> String {
        switch permission {
        case .memoryRead: "Read memories"
        case .memoryWrite: "Create memories"
        case .vaultRead: "Read vault files"
        case .vaultWrite: "Create or update vault files"
        case .networkFetch: "Contact approved websites"
        case .outputEmit: "Return structured output"
        }
    }
}

private struct MarketplaceConfigField: View {
    let field: PluginConfigField
    @Binding var values: [String: String]

    var body: some View {
        VStack(alignment: .leading) {
            Text(field.label).font(.caption).foregroundStyle(.secondary)
            if field.kind == .secret {
                SecureField(field.placeholder ?? "", text: value)
            } else {
                TextField(field.placeholder ?? "", text: value)
                    .keyboardType(field.kind == .url ? .URL : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var value: Binding<String> {
        Binding(
            get: { values[field.key, default: ""] },
            set: { values[field.key] = $0 }
        )
    }
}
