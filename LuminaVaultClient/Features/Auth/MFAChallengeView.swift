import SwiftUI
import Combine

struct MFAChallengeView: View {

    @Environment(\.lvPalette) private var palette

    @Bindable var vm: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                LVLogoMark(size: .auth, intensity: .subtle, showSparkle: false)
                    .padding(.bottom, 28)

                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(palette.accent.opacity(0.08))
                        .frame(width: 56, height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .stroke(palette.accent.opacity(0.35), lineWidth: 1.5))
                        .shadow(color: palette.accent.opacity(0.18), radius: 16)
                    Image(systemName: "lock.shield")
                        .font(.system(size: 24))
                        .foregroundStyle(palette.accent.opacity(0.9))
                }
                .padding(.bottom, 12)

                Text("Two-factor auth")
                    .font(.system(size: 20, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .padding(.bottom, 4)
                Text("Enter the code we sent you")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center).padding(.bottom, 20)

                OTPFieldRow(code: $vm.mfaCode, accentColor: palette.accent)
                    .padding(.horizontal, 24).padding(.bottom, 16)

                LVTOTPTimerView()
                    .padding(.bottom, 20)

                if let err = vm.error {
                    Text(err).font(.system(size: 11)).foregroundStyle(.red.opacity(0.8)).padding(.bottom, 10)
                }

                LVButton("Verify", isLoading: vm.isLoading) { Task { await vm.verifyMFA() } }
                    .padding(.horizontal, 24).padding(.bottom, 16)

                Button("Lost access? Use backup code") {}
                    .font(.system(size: 10)).foregroundStyle(palette.primary.opacity(0.55))
            }
            .padding(.top, 48).padding(.bottom, 40)
        }
        .lvBackground()
        .navigationBarBackButtonHidden(true)
    }
}

private struct LVTOTPTimerView: View {

    @Environment(\.lvPalette) private var palette

    @State private var secondsLeft = 30
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(palette.surfaceStroke, lineWidth: 3).frame(width: 22, height: 22)
                Circle()
                    .trim(from: 0, to: CGFloat(secondsLeft) / 30)
                    .stroke(secondsLeft <= 10 ? palette.accent : palette.primary,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: secondsLeft)
            }
            (Text("Code expires in ").foregroundStyle(palette.textSecondary)
             + Text("\(secondsLeft)s").foregroundColor(secondsLeft <= 10 ? palette.accent : palette.primary))
                .font(.system(size: 10))
        }
        .onReceive(timer) { _ in
            secondsLeft = secondsLeft > 0 ? secondsLeft - 1 : 30
        }
    }
}

#Preview {
    @Previewable @State var vm = AuthViewModel(authClient: PreviewAuthClient(), appState: AppState())
    NavigationStack { MFAChallengeView(vm: vm) }
}
