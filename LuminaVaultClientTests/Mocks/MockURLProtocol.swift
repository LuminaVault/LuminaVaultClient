// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockURLProtocol.swift
import Foundation

final class MockURLProtocol: URLProtocol {
    // HER-237: async handler so tests can await isolated counters (Counter,
    // TokenStore actors) when scripting multi-attempt responses. Sync
    // closures auto-convert, so existing tests keep working unchanged.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) async throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocolDidFinishLoading(self); return
        }
        let req = request
        let protoClient = self.client
        let me = self
        Task {
            do {
                let (response, data) = try await handler(req)
                protoClient?.urlProtocol(me, didReceive: response, cacheStoragePolicy: .notAllowed)
                protoClient?.urlProtocol(me, didLoad: data)
            } catch {
                protoClient?.urlProtocol(me, didFailWithError: error)
            }
            protoClient?.urlProtocolDidFinishLoading(me)
        }
    }
    override func stopLoading() {}
}
