import SwiftUI

#if DEBUG
struct EnvironmentTagView: View {
    @AppStorage("appEnvironment") private var currentEnvRaw: String = Config.currentEnvironment.rawValue
    @Environment(AppState.self) private var appState
    @State private var showPicker = false
    
    var currentEnv: AppEnvironment {
        AppEnvironment(rawValue: currentEnvRaw) ?? .local
    }
    
    var body: some View {
        Button(action: { showPicker = true }) {
            Text(currentEnv.displayName)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(currentEnv == .prod ? Color.red : Color.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .shadow(radius: 2)
        }
        .confirmationDialog("Select Environment", isPresented: $showPicker) {
            ForEach(AppEnvironment.allCases) { env in
                Button(env.displayName) {
                    currentEnvRaw = env.rawValue
                    Config.currentEnvironment = env
                    appState.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Switching environments will sign you out.")
        }
    }
}

#Preview {
    EnvironmentTagView()
        .environment(AppState())
}
#endif
