// LuminaVaultClient/LuminaVaultClient/API/Core/TokenRefreshCoordinator.swift
import Foundation

/// Single-flight refresh coordinator. If multiple concurrent requests hit a
/// 401 simultaneously they share one refresh attempt instead of stampeding
/// the auth server. After the in-flight refresh resolves, the next caller
/// starts a fresh attempt.
actor TokenRefreshCoordinator {
    typealias RefreshOperation = @Sendable () async throws -> String

    private var inFlight: Task<String, Error>?

    func refresh(using operation: @escaping RefreshOperation) async throws -> String {
        if let existing = inFlight {
            return try await existing.value
        }
        let task = Task { try await operation() }
        inFlight = task
        let result: Result<String, Error>
        do {
            let value = try await task.value
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        inFlight = nil
        return try result.get()
    }
}
