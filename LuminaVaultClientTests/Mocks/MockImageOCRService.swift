// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockImageOCRService.swift
//
// HER-157 — scripted ImageOCRServiceProtocol fake. Captures the
// invocation so tests can assert it wasn't called when the pipeline
// short-circuits.

@testable import LuminaVaultClient
import Foundation

final class MockImageOCRService: ImageOCRServiceProtocol, @unchecked Sendable {
    var scriptedResult: Result<String, Error> = .success("scripted text")
    private(set) var calls: Int = 0

    func extractText(from _: Data, locale _: String?) async throws -> String {
        calls += 1
        return try scriptedResult.get()
    }
}
