// LuminaVaultClient/LuminaVaultClient/Features/Auth/Phone/PhoneEntryView.swift
// HER-141 step 1: country picker + phone field. Submits POST /v1/auth/phone/start
// and pushes PhoneOTPView when the VM transitions to `.code`.
import SwiftUI

struct PhoneEntryView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel
    @State private var showingCountryPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .standard, showSparkle: true)
                    .padding(.bottom, 24)

                Text("Continue with phone")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("We'll send you a 6-digit code by SMS.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 22)

                phoneRow

                if let err = vm.error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(.top, 10)
                }

                LVButton("Send code", isLoading: vm.isLoading) {
                    Task { await vm.startPhoneOTP() }
                }
                .padding(.top, 18)
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 40)
        }
        .lvBackground()
        .navigationTitle("")
        .sheet(isPresented: $showingCountryPicker) {
            CountryPickerView(selection: $vm.phoneCountry)
        }
        .navigationDestination(isPresented: Binding(
            get: { vm.phoneStep == .code },
            set: { if !$0 { vm.phoneStep = .entry } }
        )) {
            PhoneOTPView(vm: vm)
        }
    }

    private var phoneRow: some View {
        HStack(spacing: 8) {
            Button {
                showingCountryPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(vm.phoneCountry.flag).font(.system(size: 18))
                    Text(vm.phoneCountry.dialCode)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    LVIconView(.chevronDown, size: 10, tint: palette.textSecondary, weight: .semibold)
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .background(Color.lvGlass)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.surfaceStroke, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            LVTextField(
                placeholder: "Phone number",
                text: Binding(
                    get: { vm.phoneInput },
                    set: { vm.phoneInput = vm.formatPhoneAsTyped($0) }
                ),
                keyboardType: .phonePad,
                textContentType: .telephoneNumber,
                autocapitalization: .never
            )
        }
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack { PhoneEntryView(vm: vm) }
}
