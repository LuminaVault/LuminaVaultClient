import LuminaVaultShared
import SwiftUI

struct AskModelSheet: View {
    @Environment(\.dismiss) private var dismiss
    let routes: [RouterModelRouteDTO]
    let onSelect: (RouterModelRouteDTO) -> Void

    var body: some View {
        NavigationStack {
            List(routes) { route in
                Button {
                    onSelect(route)
                } label: {
                    VStack(alignment: .leading) {
                        Text(route.model)
                        Text(route.provider.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose a model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
