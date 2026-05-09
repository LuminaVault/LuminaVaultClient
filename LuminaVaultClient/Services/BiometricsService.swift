import LocalAuthentication

final class BiometricsService: Sendable {
    static let shared = BiometricsService()
    private init() {}

    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    func authenticate(reason: String) async -> Bool {
        guard isAvailable else { return false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }
}
