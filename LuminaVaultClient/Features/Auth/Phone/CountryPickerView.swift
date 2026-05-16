// LuminaVaultClient/LuminaVaultClient/Features/Auth/Phone/CountryPickerView.swift
// HER-141: searchable country list presented as a sheet from PhoneEntryView.
import SwiftUI

struct CountryPickerView: View {
    @Binding var selection: Country
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [Country] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Countries.all }
        let lower = q.lowercased()
        return Countries.all.filter { c in
            c.name.lowercased().contains(lower)
                || c.dialCode.contains(q)
                || c.isoCode.lowercased() == lower
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { country in
                Button {
                    selection = country
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text(country.flag).font(.system(size: 22))
                        Text(country.name)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.lvTextPrimary)
                        Spacer()
                        Text(country.dialCode)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.lvTextSub)
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .lvBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search country or dial code")
            .navigationTitle("Select country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.lvCyan)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var country = Countries.default
    CountryPickerView(selection: $country)
}
