import Foundation

enum AnalyticsRecommendationDestination: Hashable, Identifiable {
    case memory(MemoryHealthFilter?)
    case models

    var id: String {
        switch self {
        case let .memory(filter): "memory:\(filter?.rawValue ?? "all")"
        case .models: "models"
        }
    }

    init?(deepLink: String) {
        guard let components = URLComponents(string: deepLink),
              components.scheme == nil,
              components.host == nil
        else { return nil }

        switch components.path {
        case "/analytics" where components.fragment == "models":
            self = .models
        case "/memories":
            let values = components.queryItems ?? []
            let filter = values.first(where: { $0.name == "filter" })?.value
                .flatMap(MemoryHealthFilter.init(rawValue:))
            let pending = values.contains { $0.name == "reviewState" && $0.value == "pending" }
            self = .memory(filter ?? (pending ? .pending : nil))
        default:
            return nil
        }
    }
}
