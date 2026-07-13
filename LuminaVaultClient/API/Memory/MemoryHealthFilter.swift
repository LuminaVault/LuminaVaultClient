enum MemoryHealthFilter: String, CaseIterable, Identifiable, Sendable {
    case reviewOverdue = "review-overdue"
    case pending
    case unorganized
    case unused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reviewOverdue: "Review overdue"
        case .pending: "Pending review"
        case .unorganized: "Unorganized memories"
        case .unused: "Unused knowledge"
        }
    }
}
