import SwiftUI

struct ForgotPasswordView: View {
    @Bindable var vm: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .standard, showSparkle: true)
                    .padding(.bottom, 18)

                ZStack {
                    Circle()
                        .fill(Color.lvCyan.opacity(0.10))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color.lvCyan.opacity(0.40), lineWidth: 1.5))
                        .shadow(color: Color.lvCyan.opacity(0.35), radius: 14)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.lvCyan)
                }
                .padding(.bottom, 14)

                switch vm.forgotStep {
                case 1:  ForgotPasswordEmailView(vm: vm)
                case 2:  ForgotPasswordOTPView(vm: vm)
                default: ForgotPasswordResetView(vm: vm)
                }
            }
            .padding(.top, 48).padding(.bottom, 40)
        }
        .lvBackground()
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                LVBackButton()
            }
        }
        .onDisappear { vm.forgotStep = 1; vm.error = nil }
    }
}

private struct LVBackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.lvCyan.opacity(0.8))
                .frame(width: 32, height: 32)
                .background(Color.lvGlass)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.lvBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
