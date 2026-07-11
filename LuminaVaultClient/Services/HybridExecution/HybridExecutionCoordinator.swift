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
            return capabilities.cloudAvailable ? .cloud : .unavailable("No local or cloud model is available.")
        case .quality:
            if capabilities.cloudAvailable {
                return .cloud
            }
            return capabilities.localAvailable ? .local : .unavailable("No model is available.")
        }
    }
}
