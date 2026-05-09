import SwiftUI

struct MainTabView: View {
    var body: some View {
        ZStack {
            Color.lvNavy.ignoresSafeArea()
            // Subtle glow
            RadialGradient(colors: [Color.lvCyan.opacity(0.06), .clear],
                           center: .center, startRadius: 0, endRadius: 300)
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 52))
                    .foregroundStyle(LinearGradient(
                        colors: [.lvCyan, .lvAmber],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(color: Color.lvCyan.opacity(0.4), radius: 20)
                Text("LuminaVault")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(LinearGradient(
                        colors: [.lvCyan, .lvAmber],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("Your memories, illuminated.")
                    .font(.system(size: 12)).foregroundStyle(Color.lvTextSub)
            }
        }
    }
}
