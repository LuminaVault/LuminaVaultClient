import Foundation
import LuminaVaultShared

enum HybridExecutionDecision: Equatable, Sendable {
    case local
    case cloud
    case unavailable(String)
}

struct HybridExecutionCapabilities: Equatable, Sendable {
    let localAvailable: Bool
    let cloudAvailable: Bool
    let requiresCloudTool: Bool
    let contextFitsLocally: Bool
    let localFallbackEnabled: Bool
    let cloudFallbackEnabled: Bool

    init(
        localAvailable: Bool,
        cloudAvailable: Bool,
        requiresCloudTool: Bool,
        contextFitsLocally: Bool,
        localFallbackEnabled: Bool = true,
        cloudFallbackEnabled: Bool = true
    ) {
        self.localAvailable = localAvailable
        self.cloudAvailable = cloudAvailable
        self.requiresCloudTool = requiresCloudTool
        self.contextFitsLocally = contextFitsLocally
        self.localFallbackEnabled = localFallbackEnabled
        self.cloudFallbackEnabled = cloudFallbackEnabled
    }
}

struct HybridExecutionCoordinator: Sendable {
    func decide(profile: HybridExecutionProfile, capabilities: HybridExecutionCapabilities) -> HybridExecutionDecision {
        switch profile {
        case .private:
            guard capabilities.localAvailable else {
                return .unavailable("Private mode needs a downloaded model or reachable local endpoint.")
            }
            guard !capabilities.requiresCloudTool else {
                return .unavailable("This tool is unavailable in Private mode.")
            }
            guard capabilities.contextFitsLocally else {
                return .unavailable("This conversation is too large for the local model.")
            }
            return .local
        case .balanced:
            if capabilities.localAvailable, capabilities.contextFitsLocally, !capabilities.requiresCloudTool {
                return .local
            }
            return capabilities.cloudFallbackEnabled && capabilities.cloudAvailable
                ? .cloud
                : .unavailable("The local model cannot handle this turn and cloud fallback is unavailable.")
        case .quality:
            if capabilities.cloudAvailable {
                return .cloud
            }
            return capabilities.localFallbackEnabled && capabilities.localAvailable && capabilities.contextFitsLocally
                && !capabilities.requiresCloudTool
                ? .local
                : .unavailable("Cloud is unavailable and local fallback cannot handle this turn.")
        }
    }
}
